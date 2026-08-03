/**
 * Controller for the navexCxTimeline LWC.
 *
 * Builds a chronological milestone list for one Account out of its Task and Event records.
 *
 * Two independent filters narrow what reaches the timeline:
 *
 * - Action Plan steps are always excluded. A playbook step is a Task (or Event) whose Id appears
 *   as ActionPlanItem.ItemId, so the generated checklist rows ("1: Internal Sync",
 *   "2: Customer Discovery" ...) stay on the CTA page instead of crowding out the lifecycle story.
 * - When milestonesOnly is on, only activities flagged CX_Milestone__c are returned, which turns
 *   a busy activity feed into a short lifecycle narrative. The flag is optional: if the field is
 *   absent or unreadable the filter is skipped rather than emptying the card.
 */
public with sharing class NavexCxTimelineController {
  @TestVisible
  private static final Integer DEFAULT_MAX_MILESTONES = 20;
  @TestVisible
  private static final Integer MAX_MILESTONES_CEILING = 100;

  // Defined once on Activity, which makes it available to both Task and Event. Treated as
  // optional throughout: an org that has not deployed it still gets a working timeline.
  private static final String MILESTONE_FIELD = 'CX_Milestone__c';

  // Lets a test point the lookup at a field name that does not exist, which is the only way to
  // exercise the "org has not deployed the field" fallback from an org where it is deployed.
  // Production code never writes to this.
  @TestVisible
  private static String milestoneFieldOverride;

  // Read cap per object. Keeps the query bounded on accounts with a long activity history;
  // the newest rows are read first, which is also the end of the timeline users care about.
  private static final Integer QUERY_LIMIT = 200;

  // Stands in for "no upper bound" so includeFuture can be honoured by a single static query
  // rather than by building the SOQL dynamically.
  private static final Date FAR_FUTURE = Date.newInstance(4000, 1, 1);

  // ---------------------------------------------------------------- DTOs

  public class Milestone implements Comparable {
    @AuraEnabled
    public Id recordId;
    @AuraEnabled
    public String objectApiName; // 'Task' or 'Event' — drives the record link
    @AuraEnabled
    public String subject;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Date activityDate;
    @AuraEnabled
    public String activityType; // Task.Type / Event.Type, feeds the category mapping
    @AuraEnabled
    public String status; // Task.Status; null on Event, which has no status
    @AuraEnabled
    public String ownerName;
    @AuraEnabled
    public Boolean isCompleted;
    @AuraEnabled
    public Boolean isFuture;
    @AuraEnabled
    public Boolean isUndated;

    public Integer compareTo(Object other) {
      Milestone that = (Milestone) other;
      // Undated activities have no position on a date axis, so they are pinned to the end
      // rather than dropped, which would silently hide real records.
      if (this.activityDate == null || that.activityDate == null) {
        if (this.activityDate == that.activityDate) {
          return compareFallback(that);
        }
        return this.activityDate == null ? 1 : -1;
      }
      if (this.activityDate == that.activityDate) {
        return compareFallback(that);
      }
      return this.activityDate < that.activityDate ? -1 : 1;
    }

    /** Same-day milestones need a stable order so the row does not shuffle between loads. */
    private Integer compareFallback(Milestone that) {
      String left = this.subject == null ? '' : this.subject;
      String right = that.subject == null ? '' : that.subject;
      Integer bySubject = left.compareTo(right);
      if (bySubject != 0) {
        return bySubject;
      }
      return String.valueOf(this.recordId)
        .compareTo(String.valueOf(that.recordId));
    }
  }

  public class Timeline {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public Integer totalCount; // milestones actually returned
    @AuraEnabled
    public Integer availableCount; // milestones found before the max was applied
    @AuraEnabled
    public Boolean isTruncated;
    @AuraEnabled
    public Boolean excludesPlaybookSteps; // false when ActionPlanItem is unreadable
    @AuraEnabled
    public Boolean milestonesOnlyRequested; // what the page asked for
    @AuraEnabled
    public Boolean milestonesOnlyApplied; // what actually happened — see hasMilestoneField
    @AuraEnabled
    public List<Milestone> milestones;
  }

  // ---------------------------------------------------------------- API

  /**
   * Returns the account's milestones oldest-first.
   *
   * @param recordId       Account whose activities are read.
   * @param maxMilestones  Upper bound on returned rows. Null or <= 0 falls back to the default.
   * @param includeFuture  When false, activities dated after today are left out. Undated
   *                       activities are never "future", so they survive either way.
   * @param milestonesOnly When true, restricts the result to activities flagged CX_Milestone__c.
   *                       Ignored, rather than enforced as an empty result, in an org where that
   *                       field is missing or unreadable.
   */
  @AuraEnabled(cacheable=true)
  public static Timeline getTimeline(
    Id recordId,
    Integer maxMilestones,
    Boolean includeFuture,
    Boolean milestonesOnly
  ) {
    validateRecordId(recordId);
    try {
      return loadTimeline(
        recordId,
        normaliseMax(maxMilestones),
        includeFuture == true,
        milestonesOnly == true
      );
    } catch (AuraHandledException e) {
      throw e;
    } catch (QueryException e) {
      throw auraError(
        'You don\'t have access to all of the fields this timeline needs. Ask your administrator to grant read access to Account, Task and Event.'
      );
    } catch (Exception e) {
      throw auraError('The timeline could not be loaded: ' + e.getMessage());
    }
  }

  // ---------------------------------------------------------------- internals

  private static Timeline loadTimeline(
    Id recordId,
    Integer maxMilestones,
    Boolean includeFuture,
    Boolean milestonesOnly
  ) {
    Timeline timeline = new Timeline();
    timeline.accountId = recordId;
    timeline.milestones = new List<Milestone>();
    timeline.totalCount = 0;
    timeline.availableCount = 0;
    timeline.isTruncated = false;
    timeline.excludesPlaybookSteps = true;
    timeline.milestonesOnlyRequested = milestonesOnly;

    // Account access is the one hard requirement: without it there is no timeline to show.
    // WITH USER_MODE raises QueryException when the object itself is off limits, which is the
    // same outcome for the user as the record not existing, so both collapse to one message.
    List<Account> accounts;
    try {
      accounts = [
        SELECT Id, Name
        FROM Account
        WHERE Id = :recordId
        WITH USER_MODE
        LIMIT 1
      ];
    } catch (QueryException e) {
      accounts = new List<Account>();
    }
    if (accounts.isEmpty()) {
      throw auraError(
        'This account could not be found, or you don\'t have access to it.'
      );
    }
    timeline.accountName = accounts[0].Name;

    Date today = Date.today();
    Date horizon = includeFuture ? FAR_FUTURE : today;

    // The flag is checked per object even though one Activity field definition backs both,
    // because field-level security is still granted per object and can drift apart.
    Boolean filterTasks = milestonesOnly && hasMilestoneField(Task.SObjectType);
    Boolean filterEvents =
      milestonesOnly && hasMilestoneField(Event.SObjectType);
    timeline.milestonesOnlyApplied = filterTasks && filterEvents;

    List<Milestone> found = new List<Milestone>();
    found.addAll(readTasks(recordId, horizon, today, filterTasks));
    found.addAll(readEvents(recordId, horizon, today, filterEvents));

    // Playbook steps live on the CTA page, not here. ActionPlanItem.ItemId is polymorphic, so
    // both Task and Event ids are offered to the lookup.
    Set<Id> playbookActivityIds = playbookActivityIds(activityIds(found));
    if (playbookActivityIds == null) {
      // ActionPlanItem is not readable for this user; the timeline still renders, but it
      // cannot promise that generated checklist steps have been filtered out.
      timeline.excludesPlaybookSteps = false;
      playbookActivityIds = new Set<Id>();
    }

    List<Milestone> kept = new List<Milestone>();
    for (Milestone milestone : found) {
      if (!playbookActivityIds.contains(milestone.recordId)) {
        kept.add(milestone);
      }
    }
    kept.sort();

    timeline.availableCount = kept.size();
    timeline.milestones = applyMax(kept, maxMilestones);
    timeline.totalCount = timeline.milestones.size();
    timeline.isTruncated = timeline.totalCount < timeline.availableCount;
    return timeline;
  }

  /**
   * Keeps the newest milestones when the list overruns the cap, so the visible timeline always
   * runs up to the present. Undated rows sort last and therefore survive the trim.
   */
  private static List<Milestone> applyMax(
    List<Milestone> ordered,
    Integer maxMilestones
  ) {
    if (ordered.size() <= maxMilestones) {
      return ordered;
    }
    List<Milestone> trimmed = new List<Milestone>();
    for (Integer i = ordered.size() - maxMilestones; i < ordered.size(); i++) {
      trimmed.add(ordered[i]);
    }
    return trimmed;
  }

  private static List<Milestone> readTasks(
    Id recordId,
    Date horizon,
    Date today,
    Boolean milestonesOnly
  ) {
    List<Milestone> results = new List<Milestone>();
    // AccountId is the derived roll-up, so activities logged against the account's opportunities
    // and cases are picked up too. WhatId is kept as a belt-and-braces match for records where
    // the roll-up is not populated.
    List<Task> tasks;
    try {
      tasks = (List<Task>) Database.queryWithBinds(
        activityQuery('Task', 'Status, IsClosed', milestonesOnly),
        new Map<String, Object>{ 'recordId' => recordId, 'horizon' => horizon },
        AccessLevel.USER_MODE
      );
    } catch (QueryException e) {
      // One unreadable activity object should degrade the timeline, not replace the whole
      // account page with an error. The other object is still worth showing.
      return results;
    }
    for (Task task : tasks) {
      Milestone milestone = new Milestone();
      milestone.recordId = task.Id;
      milestone.objectApiName = 'Task';
      milestone.subject = String.isBlank(task.Subject)
        ? 'Untitled activity'
        : task.Subject;
      milestone.description = task.Description;
      milestone.activityDate = task.ActivityDate;
      milestone.activityType = task.Type;
      milestone.status = task.Status;
      milestone.ownerName = task.Owner == null ? null : task.Owner.Name;
      milestone.isCompleted = task.IsClosed == true;
      stampTiming(milestone, today);
      results.add(milestone);
    }
    return results;
  }

  private static List<Milestone> readEvents(
    Id recordId,
    Date horizon,
    Date today,
    Boolean milestonesOnly
  ) {
    List<Milestone> results = new List<Milestone>();
    List<Event> events;
    try {
      events = (List<Event>) Database.queryWithBinds(
        activityQuery('Event', 'ActivityDateTime', milestonesOnly),
        new Map<String, Object>{ 'recordId' => recordId, 'horizon' => horizon },
        AccessLevel.USER_MODE
      );
    } catch (QueryException e) {
      return results;
    }
    for (Event evt : events) {
      Milestone milestone = new Milestone();
      milestone.recordId = evt.Id;
      milestone.objectApiName = 'Event';
      milestone.subject = String.isBlank(evt.Subject)
        ? 'Untitled event'
        : evt.Subject;
      milestone.description = evt.Description;
      // Timed events populate ActivityDate from the start; the fallback covers the rare row
      // where only the datetime survived an import.
      milestone.activityDate = evt.ActivityDate != null
        ? evt.ActivityDate
        : (evt.ActivityDateTime == null ? null : evt.ActivityDateTime.date());
      milestone.activityType = evt.Type;
      milestone.status = null;
      milestone.ownerName = evt.Owner == null ? null : evt.Owner.Name;
      stampTiming(milestone, today);
      // An Event has no status field, so "has it happened yet" is the only sensible reading.
      milestone.isCompleted =
        milestone.isFuture == false &&
        milestone.isUndated == false;
      results.add(milestone);
    }
    return results;
  }

  /**
   * Task and Event differ only in a couple of columns, so one builder covers both. The SOQL is
   * assembled rather than written inline because the CX_Milestone__c predicate can only be
   * included in orgs where that field exists — naming a missing field in static SOQL would stop
   * the class compiling.
   *
   * @param objectApiName Task or Event.
   * @param extraFields   Comma-separated columns unique to that object.
   * @param milestonesOnly Adds the milestone predicate. Callers must already have confirmed the
   *                       field is present and accessible.
   */
  private static String activityQuery(
    String objectApiName,
    String extraFields,
    Boolean milestonesOnly
  ) {
    String soql =
      'SELECT Id, Subject, Description, Type, ActivityDate, Owner.Name, ' +
      extraFields +
      ' FROM ' +
      objectApiName +
      ' WHERE (AccountId = :recordId OR WhatId = :recordId)' +
      ' AND (ActivityDate <= :horizon OR ActivityDate = NULL)';
    if (milestonesOnly) {
      soql += ' AND ' + milestoneField() + ' = TRUE';
    }
    return soql + ' ORDER BY ActivityDate DESC NULLS LAST LIMIT ' + QUERY_LIMIT;
  }

  /**
   * True when CX_Milestone__c is deployed on the given object and readable by this user.
   *
   * Both halves matter. A missing field means the org never deployed the demo package; an
   * unreadable one means the running user's permission set is short a field grant. Either way the
   * component falls back to showing every activity, because a timeline with too many nodes still
   * tells a story and a blank card does not.
   */
  @TestVisible
  private static Boolean hasMilestoneField(Schema.SObjectType objectType) {
    Schema.SObjectField field = objectType.getDescribe()
      .fields.getMap()
      .get(milestoneField());
    return field != null && field.getDescribe().isAccessible();
  }

  private static String milestoneField() {
    return milestoneFieldOverride == null
      ? MILESTONE_FIELD
      : milestoneFieldOverride;
  }

  private static void stampTiming(Milestone milestone, Date today) {
    milestone.isUndated = milestone.activityDate == null;
    milestone.isFuture =
      milestone.activityDate != null &&
      milestone.activityDate > today;
  }

  private static Set<Id> activityIds(List<Milestone> milestones) {
    Set<Id> ids = new Set<Id>();
    for (Milestone milestone : milestones) {
      ids.add(milestone.recordId);
    }
    return ids;
  }

  /**
   * Returns the subset of the given activity ids that are Action Plan steps, or null when
   * ActionPlanItem cannot be read at all — the caller reports that as a degraded result rather
   * than failing the whole component.
   */
  private static Set<Id> playbookActivityIds(Set<Id> candidateIds) {
    if (candidateIds.isEmpty()) {
      return new Set<Id>();
    }
    if (!Schema.SObjectType.ActionPlanItem.isAccessible()) {
      return null;
    }
    Set<Id> playbookIds = new Set<Id>();
    try {
      for (ActionPlanItem item : [
        SELECT ItemId
        FROM ActionPlanItem
        WHERE ItemId IN :candidateIds
        WITH USER_MODE
      ]) {
        if (item.ItemId != null) {
          playbookIds.add(item.ItemId);
        }
      }
    } catch (QueryException e) {
      return null;
    }
    return playbookIds;
  }

  private static Integer normaliseMax(Integer requested) {
    if (requested == null || requested <= 0) {
      return DEFAULT_MAX_MILESTONES;
    }
    return Math.min(requested, MAX_MILESTONES_CEILING);
  }

  private static void validateRecordId(Id recordId) {
    if (recordId == null || recordId.getSObjectType() != Account.SObjectType) {
      throw auraError(
        'This component must be placed on an Account record page.'
      );
    }
  }

  private static AuraHandledException auraError(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
