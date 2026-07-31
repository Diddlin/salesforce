/**
 * Controller for the navexCtaPlaybook LWC.
 *
 * Action Plan tasks are reached through ActionPlanItem, never directly from ActionPlan.
 * ActionPlanItem.ItemId stays null until the platform materialises the Task, which happens
 * only once the prerequisite step closes. Those rows are surfaced as "waiting" rather than
 * dropped, so the checklist shows the whole playbook instead of blank rows.
 */
public with sharing class NavexCtaPlaybookController {
  private static final String CTA_TYPE_FIELD = 'Tech_CTA_Type__c';
  private static final Pattern LEADING_SEQUENCE = Pattern.compile(
    '^\\s*(\\d+)'
  );
  private static final Integer SORT_LAST = 2147483647;

  private static String cachedClosedStatus;
  private static String cachedOpenStatus;
  private static Set<Schema.SObjectType> cachedTaskWhatTypes;

  // ---------------------------------------------------------------- DTOs

  public class PlaybookItem implements Comparable {
    @AuraEnabled
    public Id itemId; // ActionPlanItem Id — always present, unique row key
    @AuraEnabled
    public Id taskId; // null while the step is waiting on a prerequisite
    @AuraEnabled
    public String subject;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public String priority;
    @AuraEnabled
    public String ownerName;
    @AuraEnabled
    public Id ownerId;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Boolean isRequired;
    @AuraEnabled
    public Boolean isWaiting;
    @AuraEnabled
    public Boolean isComplete;
    @AuraEnabled
    public Boolean isOverdue;
    @AuraEnabled
    public Boolean isAdHoc; // added by a user rather than generated from the template
    @AuraEnabled
    public Integer displayOrder;
    @AuraEnabled
    public String dependencyStatus;

    private Integer sortOrder;
    private Integer sortSequence;
    private String sortName;
    private Datetime sortCreated;

    public Integer compareTo(Object other) {
      PlaybookItem that = (PlaybookItem) other;
      Integer result = compareInteger(this.sortOrder, that.sortOrder);
      if (result != 0) {
        return result;
      }
      result = compareInteger(this.sortSequence, that.sortSequence);
      if (result != 0) {
        return result;
      }
      result = this.sortName.compareTo(that.sortName);
      if (result != 0) {
        return result;
      }
      if (this.sortCreated == that.sortCreated) {
        return 0;
      }
      return this.sortCreated < that.sortCreated ? -1 : 1;
    }

    private Integer compareInteger(Integer left, Integer right) {
      if (left == right) {
        return 0;
      }
      return left < right ? -1 : 1;
    }
  }

  public class Playbook {
    @AuraEnabled
    public Id planId;
    @AuraEnabled
    public String planName;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public Date endDate;
    @AuraEnabled
    public String ctaType;
    @AuraEnabled
    public String templateName;
    @AuraEnabled
    public String templateGuidance;
    @AuraEnabled
    public Id relatedToId; // plan target, when it is a valid Task.WhatId, so ad-hoc tasks land on its timeline
    @AuraEnabled
    public Boolean canEditTasks;
    @AuraEnabled
    public Boolean canCreateSteps;
    @AuraEnabled
    public Boolean canDeleteAdHocSteps;
    @AuraEnabled
    public Integer totalCount;
    @AuraEnabled
    public Integer completedCount;
    @AuraEnabled
    public Integer percentComplete;
    @AuraEnabled
    public List<PlaybookItem> items;
  }

  // ---------------------------------------------------------------- API

  /**
   * Returns the plan header, guidance and the ordered checklist for one ActionPlan.
   */
  @AuraEnabled(cacheable=true)
  public static Playbook getPlaybook(Id recordId) {
    validateRecordId(recordId);
    try {
      return loadPlaybook(recordId);
    } catch (AuraHandledException e) {
      throw e;
    } catch (QueryException e) {
      throw auraError(
        'You don\'t have access to all of the fields this playbook needs. Ask your administrator to grant read access to Action Plan, Action Plan Item and Task.'
      );
    } catch (Exception e) {
      throw auraError('The playbook could not be loaded: ' + e.getMessage());
    }
  }

  /**
   * Marks the Task behind one checklist row complete or incomplete and returns the refreshed
   * playbook so the caller can reconcile its optimistic UI against server truth.
   */
  @AuraEnabled
  public static Playbook toggleTaskCompletion(
    Id recordId,
    Id taskId,
    Boolean markComplete
  ) {
    validateRecordId(recordId);
    if (taskId == null) {
      throw auraError(
        'This step is still waiting on a previous step, so it can\'t be updated yet.'
      );
    }
    if (!isTaskStatusUpdateable()) {
      throw auraError(
        'You don\'t have permission to update tasks on this action plan.'
      );
    }

    // Only tasks that actually belong to this plan may be touched, whatever the client sends.
    List<ActionPlanItem> owned = [
      SELECT Id, ItemId
      FROM ActionPlanItem
      WHERE ActionPlanId = :recordId AND ItemId = :taskId
      WITH USER_MODE
      LIMIT 1
    ];
    if (owned.isEmpty()) {
      throw auraError('That step is not part of this action plan.');
    }

    String targetStatus = markComplete == true
      ? closedTaskStatus()
      : openTaskStatus();
    if (String.isBlank(targetStatus)) {
      throw auraError(
        'No suitable Task status value is configured in this org.'
      );
    }

    try {
      Database.update(
        new Task(Id = taskId, Status = targetStatus),
        AccessLevel.USER_MODE
      );
    } catch (DmlException e) {
      throw auraError('The step could not be updated: ' + e.getDmlMessage(0));
    } catch (System.NoAccessException e) {
      throw auraError(
        'You don\'t have permission to update tasks on this action plan.'
      );
    }

    return loadPlaybook(recordId);
  }

  /**
   * Links a Task that the client just created through the UI API onto this plan as an ad-hoc step.
   *
   * The Task itself is created by lightning-record-edit-form so that field-level security, layout
   * validation and picklist rules are enforced by the platform. Only the ActionPlanItem junction,
   * which the UI API cannot create, is handled here.
   */
  @AuraEnabled
  public static Playbook addAdHocStep(Id recordId, Id taskId) {
    validateRecordId(recordId);
    if (taskId == null || taskId.getSObjectType() != Task.SObjectType) {
      throw auraError(
        'A task is required before it can be added to this action plan.'
      );
    }
    if (!ActionPlanItem.SObjectType.getDescribe().isCreateable()) {
      throw auraError(
        'You don\'t have permission to add steps to this action plan.'
      );
    }

    // Confirms the plan is visible to this user before anything is written.
    List<SObject> plans = Database.queryWithBinds(
      planQuery(),
      new Map<String, Object>{ 'recordId' => recordId },
      AccessLevel.USER_MODE
    );
    if (plans.isEmpty()) {
      throw auraError(
        'This action plan could not be found, or you don\'t have access to it.'
      );
    }

    List<ActionPlanItem> alreadyLinked = [
      SELECT Id
      FROM ActionPlanItem
      WHERE ItemId = :taskId
      WITH USER_MODE
      LIMIT 1
    ];
    if (!alreadyLinked.isEmpty()) {
      throw auraError('That task is already a step on an action plan.');
    }

    String stepName = 'New step';
    for (Task task : [
      SELECT Subject
      FROM Task
      WHERE Id = :taskId
      WITH USER_MODE
      LIMIT 1
    ]) {
      if (String.isNotBlank(task.Subject)) {
        stepName = task.Subject;
      }
    }

    try {
      Database.insert(
        new ActionPlanItem(
          Name = stepName.abbreviate(80),
          ActionPlanId = recordId,
          ItemId = taskId,
          ItemState = 'InProgress',
          IsRequired = false,
          DisplayOrder = nextDisplayOrder(recordId)
        ),
        AccessLevel.USER_MODE
      );
    } catch (Exception e) {
      // The Task exists but is not on any plan, so remove it rather than leaving it stranded
      // on the related record's timeline.
      discardUnlinkedTask(taskId);
      throw auraError('The step could not be added: ' + e.getMessage());
    }

    return loadPlaybook(recordId);
  }

  /**
   * Removes an ad-hoc step and the Task behind it. Template-generated steps are refused, because
   * deleting one would put the plan out of step with its template.
   */
  @AuraEnabled
  public static Playbook deleteAdHocStep(Id recordId, Id itemId) {
    validateRecordId(recordId);
    if (
      itemId == null ||
      itemId.getSObjectType() != ActionPlanItem.SObjectType
    ) {
      throw auraError('That step could not be found.');
    }

    List<ActionPlanItem> items = [
      SELECT Id, ItemId, ActionPlanTemplateItemId
      FROM ActionPlanItem
      WHERE Id = :itemId AND ActionPlanId = :recordId
      WITH USER_MODE
      LIMIT 1
    ];
    if (items.isEmpty()) {
      throw auraError('That step is not part of this action plan.');
    }
    ActionPlanItem item = items[0];
    if (item.ActionPlanTemplateItemId != null) {
      throw auraError(
        'Only steps you added yourself can be removed. This step comes from the plan template.'
      );
    }
    if (!ActionPlanItem.SObjectType.getDescribe().isDeletable()) {
      throw auraError(
        'You don\'t have permission to remove steps from this action plan.'
      );
    }

    Id taskId = item.ItemId;
    try {
      Database.delete(item, AccessLevel.USER_MODE);
      if (taskId != null && Task.SObjectType.getDescribe().isDeletable()) {
        Database.delete(new Task(Id = taskId), AccessLevel.USER_MODE);
      }
    } catch (DmlException e) {
      throw auraError('The step could not be removed: ' + e.getDmlMessage(0));
    } catch (System.NoAccessException e) {
      throw auraError(
        'You don\'t have permission to remove steps from this action plan.'
      );
    }

    return loadPlaybook(recordId);
  }

  // ---------------------------------------------------------------- internals

  private static Integer nextDisplayOrder(Id recordId) {
    // Ad-hoc steps go to the end. Templates often leave every DisplayOrder at 0, in which case
    // this returns 1 and the new step still sorts after the generated ones.
    AggregateResult result = [
      SELECT MAX(DisplayOrder) maxOrder
      FROM ActionPlanItem
      WHERE ActionPlanId = :recordId
      WITH USER_MODE
    ];
    Integer highest = (Integer) result.get('maxOrder');
    return highest == null ? 0 : highest + 1;
  }

  private static void discardUnlinkedTask(Id taskId) {
    try {
      if (!Task.SObjectType.getDescribe().isDeletable()) {
        return;
      }
      List<ActionPlanItem> stillLinked = [
        SELECT Id
        FROM ActionPlanItem
        WHERE ItemId = :taskId
        LIMIT 1
      ];
      if (stillLinked.isEmpty()) {
        Database.delete(new Task(Id = taskId), AccessLevel.USER_MODE);
      }
    } catch (Exception ignored) {
      // Best effort only; the caller is already reporting the original failure.
    }
  }

  private static Playbook loadPlaybook(Id recordId) {
    Playbook plan = new Playbook();
    plan.items = new List<PlaybookItem>();
    plan.totalCount = 0;
    plan.completedCount = 0;
    plan.percentComplete = 0;
    plan.canEditTasks = isTaskStatusUpdateable();
    plan.canCreateSteps =
      Task.SObjectType.getDescribe().isCreateable() &&
      ActionPlanItem.SObjectType.getDescribe().isCreateable();
    plan.canDeleteAdHocSteps = ActionPlanItem.SObjectType.getDescribe()
      .isDeletable();

    List<SObject> plans = Database.queryWithBinds(
      planQuery(),
      new Map<String, Object>{ 'recordId' => recordId },
      AccessLevel.USER_MODE
    );
    if (plans.isEmpty()) {
      throw auraError(
        'This action plan could not be found, or you don\'t have access to it.'
      );
    }
    SObject record = plans[0];
    plan.planId = (Id) record.get('Id');
    plan.planName = (String) record.get('Name');
    plan.state = (String) record.get('ActionPlanState');
    plan.startDate = (Date) record.get('StartDate');
    plan.endDate = (Date) record.get('EndDate');
    if (hasCtaTypeField()) {
      plan.ctaType = (String) record.get(CTA_TYPE_FIELD);
    }
    Id targetId = (Id) record.get('TargetId');
    if (isValidTaskWhat(targetId)) {
      plan.relatedToId = targetId;
    }

    Id versionId = (Id) record.get('ActionPlanTemplateVersionId');
    if (versionId != null) {
      for (ActionPlanTemplateVersion version : [
        SELECT ActionPlanTemplate.Name, ActionPlanTemplate.Description
        FROM ActionPlanTemplateVersion
        WHERE Id = :versionId
        WITH USER_MODE
        LIMIT 1
      ]) {
        plan.templateName = version.ActionPlanTemplate.Name;
        plan.templateGuidance = version.ActionPlanTemplate.Description;
      }
    }

    List<ActionPlanItem> items = [
      SELECT
        Id,
        Name,
        ItemId,
        ItemState,
        IsRequired,
        DisplayOrder,
        DependencyStatus,
        ItemEntityType,
        ActionPlanTemplateItemId,
        CreatedDate
      FROM ActionPlanItem
      WHERE ActionPlanId = :recordId
      WITH USER_MODE
    ];
    if (items.isEmpty()) {
      return plan;
    }

    Set<Id> taskIds = new Set<Id>();
    for (ActionPlanItem item : items) {
      if (
        item.ItemId != null &&
        item.ItemId.getSObjectType() == Task.SObjectType
      ) {
        taskIds.add(item.ItemId);
      }
    }

    Map<Id, Task> tasksById = new Map<Id, Task>();
    if (!taskIds.isEmpty()) {
      tasksById = new Map<Id, Task>(
        [
          SELECT
            Id,
            Subject,
            Status,
            ActivityDate,
            Priority,
            OwnerId,
            Owner.Name,
            Description,
            IsClosed
          FROM Task
          WHERE Id IN :taskIds
          WITH USER_MODE
        ]
      );
    }

    Date today = Date.today();
    for (ActionPlanItem item : items) {
      plan.items.add(toDto(item, tasksById.get(item.ItemId), today));
    }
    plan.items.sort();

    plan.totalCount = plan.items.size();
    for (PlaybookItem dto : plan.items) {
      if (dto.isComplete) {
        plan.completedCount++;
      }
    }
    plan.percentComplete = plan.totalCount == 0
      ? 0
      : (Integer) Math.round((100.0 * plan.completedCount) / plan.totalCount);
    return plan;
  }

  private static PlaybookItem toDto(
    ActionPlanItem item,
    Task task,
    Date today
  ) {
    PlaybookItem dto = new PlaybookItem();
    dto.itemId = item.Id;
    dto.isRequired = item.IsRequired == true;
    dto.displayOrder = item.DisplayOrder;
    dto.dependencyStatus = item.DependencyStatus;
    // Steps generated from the template carry a template item id; ad-hoc ones never do.
    dto.isAdHoc = item.ActionPlanTemplateItemId == null;
    // The Task only exists once its prerequisite closes; until then the row is locked.
    dto.isWaiting = (task == null);
    dto.subject = String.isNotBlank(item.Name) ? item.Name : 'Untitled step';
    dto.isComplete = false;
    dto.isOverdue = false;

    if (task != null) {
      dto.taskId = task.Id;
      dto.status = task.Status;
      dto.dueDate = task.ActivityDate;
      dto.priority = task.Priority;
      dto.ownerId = task.OwnerId;
      dto.ownerName = task.Owner == null ? null : task.Owner.Name;
      dto.description = task.Description;
      if (String.isNotBlank(task.Subject)) {
        dto.subject = task.Subject;
      }
      dto.isComplete = task.IsClosed == true;
      dto.isOverdue =
        !dto.isComplete &&
        task.ActivityDate != null &&
        task.ActivityDate < today;
    }

    dto.sortOrder = item.DisplayOrder == null ? SORT_LAST : item.DisplayOrder;
    dto.sortSequence = leadingSequence(dto.subject);
    dto.sortName = dto.subject == null ? '' : dto.subject;
    dto.sortCreated = item.CreatedDate;
    return dto;
  }

  /**
   * Action Plan templates commonly number their steps ("1: Internal Sync") while leaving
   * DisplayOrder at 0, so a numeric prefix is the only reliable secondary sort key.
   */
  private static Integer leadingSequence(String label) {
    if (String.isBlank(label)) {
      return SORT_LAST;
    }
    Matcher m = LEADING_SEQUENCE.matcher(label);
    return m.find() ? Integer.valueOf(m.group(1)) : SORT_LAST;
  }

  private static String planQuery() {
    List<String> fields = new List<String>{
      'Id',
      'Name',
      'ActionPlanState',
      'StartDate',
      'EndDate',
      'TargetId',
      'ActionPlanTemplateVersionId'
    };
    if (hasCtaTypeField()) {
      fields.add(CTA_TYPE_FIELD);
    }
    return 'SELECT ' +
      String.join(fields, ', ') +
      ' FROM ActionPlan WHERE Id = :recordId LIMIT 1';
  }

  private static Boolean hasCtaTypeField() {
    Schema.SObjectField field = ActionPlan.SObjectType.getDescribe()
      .fields.getMap()
      .get(CTA_TYPE_FIELD);
    return field != null && field.getDescribe().isAccessible();
  }

  /**
   * An ActionPlan can target objects that Task.WhatId does not accept (Contact and Lead are
   * WhoId targets, for example), so the relationship is only offered when it is actually valid.
   */
  private static Boolean isValidTaskWhat(Id targetId) {
    if (targetId == null) {
      return false;
    }
    if (cachedTaskWhatTypes == null) {
      cachedTaskWhatTypes = new Set<Schema.SObjectType>(
        Task.WhatId.getDescribe().getReferenceTo()
      );
    }
    return cachedTaskWhatTypes.contains(targetId.getSObjectType());
  }

  private static Boolean isTaskStatusUpdateable() {
    return Task.SObjectType.getDescribe().isUpdateable() &&
      Schema.SObjectType.Task.fields.Status.isUpdateable();
  }

  private static String closedTaskStatus() {
    loadTaskStatuses();
    return cachedClosedStatus;
  }

  private static String openTaskStatus() {
    loadTaskStatuses();
    return cachedOpenStatus;
  }

  /**
   * Status labels differ per org, so derive them from TaskStatus rather than hardcoding
   * "Completed" / "Not Started".
   */
  private static void loadTaskStatuses() {
    if (cachedClosedStatus != null || cachedOpenStatus != null) {
      return;
    }
    String firstOpen;
    String defaultOpen;
    for (TaskStatus status : [
      SELECT ApiName, IsClosed, IsDefault
      FROM TaskStatus
      ORDER BY SortOrder
    ]) {
      if (status.IsClosed == true) {
        if (cachedClosedStatus == null) {
          cachedClosedStatus = status.ApiName;
        }
      } else {
        if (firstOpen == null) {
          firstOpen = status.ApiName;
        }
        if (defaultOpen == null && status.IsDefault == true) {
          defaultOpen = status.ApiName;
        }
      }
    }
    cachedOpenStatus = defaultOpen != null ? defaultOpen : firstOpen;
  }

  private static void validateRecordId(Id recordId) {
    if (
      recordId == null ||
      recordId.getSObjectType() != ActionPlan.SObjectType
    ) {
      throw auraError(
        'This component must be placed on an Action Plan record page.'
      );
    }
  }

  private static AuraHandledException auraError(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
