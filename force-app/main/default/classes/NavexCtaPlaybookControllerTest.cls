@IsTest
private class NavexCtaPlaybookControllerTest {
  private static final String GUIDANCE = 'Confirm the risk, agree an action, then close the loop with the customer.';

  /**
   * Publishing an Action Plan Template Version requires at least one item, and each Task item
   * requires Subject / Priority / ActivityDate values, so the template is built in full here.
   */
  private static Id buildPublishedTemplateVersion(List<String> stepNames) {
    String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
    ActionPlanTemplate template = new ActionPlanTemplate(
      Name = 'Playbook Test Template',
      UniqueName = 'Playbook_Test_Template_' + suffix,
      TargetEntityType = 'Account',
      ActionPlanType = 'Sales',
      Description = GUIDANCE
    );
    insert template;

    ActionPlanTemplateVersion version = [
      SELECT Id, Status
      FROM ActionPlanTemplateVersion
      WHERE ActionPlanTemplateId = :template.Id
      LIMIT 1
    ];

    List<ActionPlanTemplateItem> templateItems = new List<ActionPlanTemplateItem>();
    for (Integer i = 0; i < stepNames.size(); i++) {
      templateItems.add(
        new ActionPlanTemplateItem(
          Name = stepNames[i],
          UniqueName = 'Playbook_Test_Step_' + i + '_' + suffix,
          ActionPlanTemplateVersionId = version.Id,
          ItemEntityType = 'Task',
          DisplayOrder = i + 1,
          IsRequired = Math.mod(i, 2) == 0,
          IsActive = true
        )
      );
    }
    insert templateItems;

    List<ActionPlanTemplateItemValue> values = new List<ActionPlanTemplateItemValue>();
    for (Integer i = 0; i < templateItems.size(); i++) {
      Id itemId = templateItems[i].Id;
      values.add(
        new ActionPlanTemplateItemValue(
          Name = 'Subject',
          ActionPlanTemplateItemId = itemId,
          ItemEntityFieldName = 'Task.Subject',
          ValueLiteral = stepNames[i],
          IsActive = true
        )
      );
      values.add(
        new ActionPlanTemplateItemValue(
          Name = 'Priority',
          ActionPlanTemplateItemId = itemId,
          ItemEntityFieldName = 'Task.Priority',
          ValueLiteral = 'Normal',
          IsActive = true
        )
      );
      values.add(
        new ActionPlanTemplateItemValue(
          Name = 'ActivityDate',
          ActionPlanTemplateItemId = itemId,
          ItemEntityFieldName = 'Task.ActivityDate',
          ValueFormula = 'StartDate + ' + i,
          IsActive = true
        )
      );
    }
    insert values;

    version.Status = 'Final';
    update version;
    return version.Id;
  }

  private static ActionPlan buildPlan(List<String> stepNames) {
    Account account = new Account(Name = 'Playbook Test Account');
    insert account;

    ActionPlan plan = new ActionPlan(
      Name = 'RISK: Playbook Test Plan',
      TargetId = account.Id,
      ActionPlanTemplateVersionId = buildPublishedTemplateVersion(stepNames),
      ActionPlanType = 'Sales',
      ActionPlanState = 'In Progress',
      StartDate = Date.today()
    );
    insert plan;
    return plan;
  }

  /** Mirrors a real dependency-blocked step: an item whose Task has not been created yet. */
  private static ActionPlanItem addWaitingItem(Id planId, String name) {
    return addWaitingItem(planId, name, 99);
  }

  private static ActionPlanItem addWaitingItem(
    Id planId,
    String name,
    Integer displayOrder
  ) {
    ActionPlanItem waiting = new ActionPlanItem(
      Name = name,
      ActionPlanId = planId,
      ItemState = 'Pending',
      IsRequired = true,
      DisplayOrder = displayOrder
    );
    insert waiting;
    return waiting;
  }

  private static Map<String, NavexCtaPlaybookController.PlaybookItem> bySubject(
    NavexCtaPlaybookController.Playbook plan
  ) {
    Map<String, NavexCtaPlaybookController.PlaybookItem> result = new Map<String, NavexCtaPlaybookController.PlaybookItem>();
    for (NavexCtaPlaybookController.PlaybookItem item : plan.items) {
      result.put(item.subject, item);
    }
    return result;
  }

  @IsTest
  static void getPlaybookReturnsHeaderAndOrderedItems() {
    ActionPlan plan = buildPlan(
      new List<String>{ '1: Internal Sync', '2: Customer Discovery' }
    );
    addWaitingItem(plan.Id, '3: Customer Readout');

    Test.startTest();
    NavexCtaPlaybookController.Playbook result = NavexCtaPlaybookController.getPlaybook(
      plan.Id
    );
    Test.stopTest();

    Assert.areEqual(plan.Id, result.planId, 'Should return the requested plan');
    Assert.areEqual(
      'RISK: Playbook Test Plan',
      result.planName,
      'Plan name should be returned'
    );
    Assert.areEqual(
      'In Progress',
      result.state,
      'Plan state should be returned'
    );
    Assert.areEqual(
      Date.today(),
      result.startDate,
      'Start date should be returned'
    );
    Assert.areEqual(
      GUIDANCE,
      result.templateGuidance,
      'Guidance should come from the template description'
    );
    Assert.areEqual(
      3,
      result.items.size(),
      'All three items should be returned'
    );
    Assert.areEqual(
      3,
      result.totalCount,
      'Total count should include the waiting step'
    );
    Assert.areEqual(0, result.completedCount, 'Nothing is complete yet');
    Assert.areEqual(0, result.percentComplete, 'Progress should be zero');
    Assert.areEqual(
      '1: Internal Sync',
      result.items[0].subject,
      'Items should be ordered by DisplayOrder'
    );
    Assert.areEqual(
      '2: Customer Discovery',
      result.items[1].subject,
      'Items should be ordered by DisplayOrder'
    );
    Assert.areEqual(
      '3: Customer Readout',
      result.items[2].subject,
      'The waiting step sorts last'
    );
    Assert.isTrue(result.canEditTasks, 'A system administrator can edit tasks');
  }

  @IsTest
  static void getPlaybookMarksItemsWithoutTasksAsWaiting() {
    ActionPlan plan = buildPlan(new List<String>{ '1: Internal Sync' });
    addWaitingItem(plan.Id, '2: Blocked Step');

    Test.startTest();
    NavexCtaPlaybookController.Playbook result = NavexCtaPlaybookController.getPlaybook(
      plan.Id
    );
    Test.stopTest();

    Map<String, NavexCtaPlaybookController.PlaybookItem> items = bySubject(
      result
    );
    NavexCtaPlaybookController.PlaybookItem waiting = items.get(
      '2: Blocked Step'
    );
    Assert.isNotNull(
      waiting,
      'The dependency-blocked step should still be returned'
    );
    Assert.isTrue(waiting.isWaiting, 'An item with no Task is waiting');
    Assert.isNull(waiting.taskId, 'A waiting item has no task');
    Assert.isNull(waiting.dueDate, 'A waiting item has no due date');
    Assert.isNull(waiting.ownerName, 'A waiting item has no assignee');
    Assert.isFalse(waiting.isComplete, 'A waiting item is never complete');
    Assert.isFalse(waiting.isOverdue, 'A waiting item is never overdue');
    Assert.isNotNull(waiting.itemId, 'The ActionPlanItem id is the row key');

    NavexCtaPlaybookController.PlaybookItem live = items.get(
      '1: Internal Sync'
    );
    Assert.isFalse(live.isWaiting, 'An item with a Task is not waiting');
    Assert.isNotNull(live.taskId, 'A live item exposes its task');
    Assert.isNotNull(live.ownerId, 'A live item exposes its assignee');
    Assert.isNotNull(live.dueDate, 'A live item exposes its due date');
    Assert.areEqual(
      'Normal',
      live.priority,
      'A live item exposes its priority'
    );
  }

  @IsTest
  static void getPlaybookFallsBackToStepNumberWhenDisplayOrderIsFlat() {
    // Templates frequently leave every DisplayOrder at 0 and number the steps in the name.
    ActionPlan plan = buildPlan(new List<String>{ '1: Internal Sync' });
    delete [SELECT Id FROM ActionPlanItem WHERE ActionPlanId = :plan.Id];
    addWaitingItem(plan.Id, '10: Wrap Up', 0);
    addWaitingItem(plan.Id, '2: Customer Discovery', 0);
    addWaitingItem(plan.Id, 'Ad hoc follow up', 0);
    addWaitingItem(plan.Id, 'A different ad hoc step', 0);

    Test.startTest();
    NavexCtaPlaybookController.Playbook result = NavexCtaPlaybookController.getPlaybook(
      plan.Id
    );
    Test.stopTest();

    Assert.areEqual(
      4,
      result.items.size(),
      'All flat-ordered items should be returned'
    );
    Assert.areEqual(
      '2: Customer Discovery',
      result.items[0].subject,
      'Step 2 sorts before step 10'
    );
    Assert.areEqual(
      '10: Wrap Up',
      result.items[1].subject,
      'Step 10 sorts after step 2, not before'
    );
    Assert.areEqual(
      'A different ad hoc step',
      result.items[2].subject,
      'Unnumbered steps sort last, alphabetically'
    );
    Assert.areEqual(
      'Ad hoc follow up',
      result.items[3].subject,
      'Unnumbered steps sort last, alphabetically'
    );
  }

  @IsTest
  static void getPlaybookFlagsOverdueIncompleteTasks() {
    ActionPlan plan = buildPlan(
      new List<String>{ '1: Internal Sync', '2: Customer Discovery' }
    );
    List<Task> tasks = [
      SELECT Id, Subject, ActivityDate
      FROM Task
      WHERE
        Id IN (SELECT ItemId FROM ActionPlanItem WHERE ActionPlanId = :plan.Id)
      ORDER BY Subject
    ];
    tasks[0].ActivityDate = Date.today().addDays(-5);
    tasks[1].ActivityDate = Date.today().addDays(5);
    update tasks;

    Test.startTest();
    NavexCtaPlaybookController.Playbook result = NavexCtaPlaybookController.getPlaybook(
      plan.Id
    );
    Test.stopTest();

    Map<String, NavexCtaPlaybookController.PlaybookItem> items = bySubject(
      result
    );
    Assert.isTrue(
      items.get('1: Internal Sync').isOverdue,
      'A past due, open task is overdue'
    );
    Assert.isFalse(
      items.get('2: Customer Discovery').isOverdue,
      'A future due date is not overdue'
    );
  }

  @IsTest
  static void toggleTaskCompletionCompletesAndReopensAStep() {
    ActionPlan plan = buildPlan(
      new List<String>{ '1: Internal Sync', '2: Customer Discovery' }
    );
    Task target = [
      SELECT Id, ActivityDate
      FROM Task
      WHERE
        Id IN (SELECT ItemId FROM ActionPlanItem WHERE ActionPlanId = :plan.Id)
      ORDER BY Subject
      LIMIT 1
    ];
    target.ActivityDate = Date.today().addDays(-2);
    update target;

    Test.startTest();
    NavexCtaPlaybookController.Playbook completed = NavexCtaPlaybookController.toggleTaskCompletion(
      plan.Id,
      target.Id,
      true
    );
    NavexCtaPlaybookController.Playbook reopened = NavexCtaPlaybookController.toggleTaskCompletion(
      plan.Id,
      target.Id,
      false
    );
    Test.stopTest();

    Assert.areEqual(1, completed.completedCount, 'One step should be complete');
    Assert.areEqual(
      50,
      completed.percentComplete,
      'Progress should be recalculated'
    );
    for (NavexCtaPlaybookController.PlaybookItem item : completed.items) {
      if (item.taskId == target.Id) {
        Assert.isTrue(item.isComplete, 'The toggled task should be complete');
        Assert.isFalse(
          item.isOverdue,
          'A completed task is never shown as overdue'
        );
      }
    }

    Assert.areEqual(
      0,
      reopened.completedCount,
      'Reopening should undo the completion'
    );
    Assert.areEqual(
      0,
      reopened.percentComplete,
      'Progress should return to zero'
    );
    Assert.isFalse(
      [SELECT IsClosed FROM Task WHERE Id = :target.Id].IsClosed,
      'Task should be open again'
    );
  }

  @IsTest
  static void toggleTaskCompletionRejectsTasksFromAnotherPlan() {
    ActionPlan plan = buildPlan(new List<String>{ '1: Internal Sync' });
    Task foreignTask = new Task(Subject = 'Unrelated', Status = 'Not Started');
    insert foreignTask;

    String message;
    Test.startTest();
    try {
      NavexCtaPlaybookController.toggleTaskCompletion(
        plan.Id,
        foreignTask.Id,
        true
      );
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    Test.stopTest();

    Assert.isNotNull(message, 'A task outside the plan should be rejected');
    Assert.isTrue(
      message.contains('not part of this action plan'),
      'Message should explain the rejection: ' + message
    );
  }

  @IsTest
  static void toggleTaskCompletionRejectsWaitingSteps() {
    ActionPlan plan = buildPlan(new List<String>{ '1: Internal Sync' });

    String message;
    Test.startTest();
    try {
      NavexCtaPlaybookController.toggleTaskCompletion(plan.Id, null, true);
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    Test.stopTest();

    Assert.isNotNull(message, 'A waiting step cannot be toggled');
    Assert.isTrue(
      message.contains('waiting'),
      'Message should explain the step is blocked: ' + message
    );
  }

  @IsTest
  static void getPlaybookRejectsNonActionPlanRecordIds() {
    Account account = new Account(Name = 'Not A Plan');
    insert account;

    String message;
    Test.startTest();
    try {
      NavexCtaPlaybookController.getPlaybook(account.Id);
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    Test.stopTest();

    Assert.isNotNull(message, 'A non ActionPlan id should be rejected');
    Assert.isTrue(
      message.contains('Action Plan record page'),
      'Message should tell the admin where the component belongs: ' + message
    );
  }

  @IsTest
  static void getPlaybookRejectsNullRecordId() {
    String message;
    Test.startTest();
    try {
      NavexCtaPlaybookController.getPlaybook(null);
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    Test.stopTest();

    Assert.isNotNull(message, 'A null record id should be rejected');
  }

  @IsTest
  static void getPlaybookReturnsEmptyChecklistWhenPlanHasNoItems() {
    ActionPlan plan = buildPlan(new List<String>{ '1: Internal Sync' });
    delete [SELECT Id FROM ActionPlanItem WHERE ActionPlanId = :plan.Id];

    Test.startTest();
    NavexCtaPlaybookController.Playbook result = NavexCtaPlaybookController.getPlaybook(
      plan.Id
    );
    Test.stopTest();

    Assert.areEqual(0, result.items.size(), 'No items should be returned');
    Assert.areEqual(0, result.totalCount, 'Total should be zero');
    Assert.areEqual(
      0,
      result.percentComplete,
      'Progress should be zero, not a divide by zero'
    );
  }

  // -------------------------------------------------------------- ad-hoc steps

  @IsTest
  static void getPlaybookDistinguishesAdHocStepsFromTemplateSteps() {
    ActionPlan plan = buildPlan(new List<String>{ '1: Internal Sync' });
    Id taskId = createLooseTask('Call the CISO', plan.TargetId);

    Test.startTest();
    NavexCtaPlaybookController.addAdHocStep(plan.Id, taskId);
    NavexCtaPlaybookController.Playbook result = NavexCtaPlaybookController.getPlaybook(
      plan.Id
    );
    Test.stopTest();

    Map<String, NavexCtaPlaybookController.PlaybookItem> items = bySubject(
      result
    );
    Assert.isFalse(
      items.get('1: Internal Sync').isAdHoc,
      'A template-generated step is not ad-hoc'
    );
    Assert.isTrue(
      items.get('Call the CISO').isAdHoc,
      'A step with no template item is ad-hoc'
    );
  }

  @IsTest
  static void getPlaybookExposesThePlanTargetWhenItCanCarryTasks() {
    ActionPlan plan = buildPlan(new List<String>{ '1: Internal Sync' });

    Test.startTest();
    NavexCtaPlaybookController.Playbook result = NavexCtaPlaybookController.getPlaybook(
      plan.Id
    );
    Test.stopTest();

    Assert.areEqual(
      plan.TargetId,
      result.relatedToId,
      'An Account target is a valid Task.WhatId'
    );
    Assert.isTrue(result.canCreateSteps, 'An administrator can add steps');
    Assert.isTrue(
      result.canDeleteAdHocSteps,
      'An administrator can remove ad-hoc steps'
    );
  }

  @IsTest
  static void addAdHocStepLinksTheTaskAndSortsItLast() {
    ActionPlan plan = buildPlan(
      new List<String>{ '1: Internal Sync', '2: Customer Discovery' }
    );
    Id taskId = createLooseTask(
      'Chase the security questionnaire',
      plan.TargetId
    );

    Test.startTest();
    NavexCtaPlaybookController.Playbook result = NavexCtaPlaybookController.addAdHocStep(
      plan.Id,
      taskId
    );
    Test.stopTest();

    Assert.areEqual(
      3,
      result.totalCount,
      'The new step should be counted in progress'
    );
    Assert.areEqual(
      'Chase the security questionnaire',
      result.items[2].subject,
      'An ad-hoc step should sort after the template steps'
    );

    ActionPlanItem created = [
      SELECT
        ItemId,
        ItemState,
        IsRequired,
        DisplayOrder,
        ActionPlanTemplateItemId
      FROM ActionPlanItem
      WHERE ActionPlanId = :plan.Id AND ActionPlanTemplateItemId = NULL
    ];
    Assert.areEqual(
      taskId,
      created.ItemId,
      'The junction should point at the new task'
    );
    Assert.areEqual(
      'InProgress',
      created.ItemState,
      'A live step is in progress'
    );
    Assert.isFalse(
      created.IsRequired,
      'Ad-hoc steps are not required by the template'
    );
    Assert.areEqual(
      3,
      created.DisplayOrder,
      'The new step takes the next display order'
    );
  }

  @IsTest
  static void addAdHocStepPlacesTheStepLastWhenEveryDisplayOrderIsFlat() {
    ActionPlan plan = buildPlan(new List<String>{ '1: Internal Sync' });
    for (ActionPlanItem item : [
      SELECT Id, DisplayOrder
      FROM ActionPlanItem
      WHERE ActionPlanId = :plan.Id
    ]) {
      item.DisplayOrder = 0;
      update item;
    }
    Id taskId = createLooseTask('Ad hoc follow up', plan.TargetId);

    Test.startTest();
    NavexCtaPlaybookController.Playbook result = NavexCtaPlaybookController.addAdHocStep(
      plan.Id,
      taskId
    );
    Test.stopTest();

    Assert.areEqual(
      'Ad hoc follow up',
      result.items[result.items.size() - 1].subject,
      'A flat DisplayOrder should still push the ad-hoc step to the end'
    );
  }

  @IsTest
  static void addAdHocStepRejectsATaskThatAlreadyBelongsToAPlan() {
    ActionPlan plan = buildPlan(new List<String>{ '1: Internal Sync' });
    Id existingTaskId = [
      SELECT ItemId
      FROM ActionPlanItem
      WHERE ActionPlanId = :plan.Id AND ItemId != NULL
      LIMIT 1
    ]
    .ItemId;

    String message;
    Test.startTest();
    try {
      NavexCtaPlaybookController.addAdHocStep(plan.Id, existingTaskId);
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    Test.stopTest();

    Assert.isNotNull(
      message,
      'A task that is already a step should be rejected'
    );
    Assert.isTrue(
      message.contains('already a step'),
      'Message should explain the rejection: ' + message
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM ActionPlanItem WHERE ActionPlanId = :plan.Id],
      'No duplicate junction should be created'
    );
  }

  @IsTest
  static void addAdHocStepRejectsIdsThatAreNotTasks() {
    ActionPlan plan = buildPlan(new List<String>{ '1: Internal Sync' });

    String message;
    Test.startTest();
    try {
      NavexCtaPlaybookController.addAdHocStep(plan.Id, plan.TargetId);
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    Test.stopTest();

    Assert.isNotNull(message, 'A non-Task id should be rejected');
    Assert.isTrue(
      message.contains('task is required'),
      'Message should explain the rejection: ' + message
    );
  }

  @IsTest
  static void addAdHocStepRejectsNullTaskIds() {
    ActionPlan plan = buildPlan(new List<String>{ '1: Internal Sync' });

    String message;
    Test.startTest();
    try {
      NavexCtaPlaybookController.addAdHocStep(plan.Id, null);
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    Test.stopTest();

    Assert.isNotNull(message, 'A null task id should be rejected');
  }

  @IsTest
  static void addAdHocStepRejectsPlansTheUserCannotSee() {
    Id taskId = createLooseTask('Orphan candidate', null);
    ActionPlan plan = buildPlan(new List<String>{ '1: Internal Sync' });
    Id planId = plan.Id;
    delete plan;

    String message;
    Test.startTest();
    try {
      NavexCtaPlaybookController.addAdHocStep(planId, taskId);
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    Test.stopTest();

    Assert.isNotNull(message, 'A missing plan should be rejected');
    Assert.isTrue(
      message.contains('could not be found'),
      'Message should explain the rejection: ' + message
    );
  }

  @IsTest
  static void deleteAdHocStepRemovesTheStepAndItsTask() {
    ActionPlan plan = buildPlan(new List<String>{ '1: Internal Sync' });
    Id taskId = createLooseTask('Temporary step', plan.TargetId);
    NavexCtaPlaybookController.addAdHocStep(plan.Id, taskId);
    Id itemId = [
      SELECT Id
      FROM ActionPlanItem
      WHERE ActionPlanId = :plan.Id AND ItemId = :taskId
    ]
    .Id;

    Test.startTest();
    NavexCtaPlaybookController.Playbook result = NavexCtaPlaybookController.deleteAdHocStep(
      plan.Id,
      itemId
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      result.totalCount,
      'The removed step should no longer be counted'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM ActionPlanItem WHERE Id = :itemId],
      'The junction should be gone'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Task WHERE Id = :taskId],
      'The task behind the step should be gone'
    );
  }

  @IsTest
  static void deleteAdHocStepRefusesTemplateGeneratedSteps() {
    ActionPlan plan = buildPlan(new List<String>{ '1: Internal Sync' });
    Id itemId = [
      SELECT Id
      FROM ActionPlanItem
      WHERE ActionPlanId = :plan.Id
      LIMIT 1
    ]
    .Id;

    String message;
    Test.startTest();
    try {
      NavexCtaPlaybookController.deleteAdHocStep(plan.Id, itemId);
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    Test.stopTest();

    Assert.isNotNull(message, 'A template step should not be deletable');
    Assert.isTrue(
      message.contains('plan template'),
      'Message should explain the rejection: ' + message
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM ActionPlanItem WHERE Id = :itemId],
      'The step must survive'
    );
  }

  @IsTest
  static void deleteAdHocStepRejectsStepsFromAnotherPlan() {
    ActionPlan planA = buildPlan(new List<String>{ '1: Internal Sync' });
    ActionPlan planB = buildPlan(new List<String>{ '1: Internal Sync' });
    Id foreignItemId = [
      SELECT Id
      FROM ActionPlanItem
      WHERE ActionPlanId = :planB.Id
      LIMIT 1
    ]
    .Id;

    String message;
    Test.startTest();
    try {
      NavexCtaPlaybookController.deleteAdHocStep(planA.Id, foreignItemId);
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    Test.stopTest();

    Assert.isNotNull(message, 'A step from another plan should be rejected');
    Assert.isTrue(
      message.contains('not part of this action plan'),
      'Message should explain: ' + message
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM ActionPlanItem WHERE Id = :foreignItemId],
      'The step must survive'
    );
  }

  @IsTest
  static void deleteAdHocStepRejectsIdsThatAreNotPlanItems() {
    ActionPlan plan = buildPlan(new List<String>{ '1: Internal Sync' });

    String message;
    Test.startTest();
    try {
      NavexCtaPlaybookController.deleteAdHocStep(plan.Id, plan.TargetId);
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    Test.stopTest();

    Assert.isNotNull(message, 'A non ActionPlanItem id should be rejected');
    Assert.isTrue(
      message.contains('could not be found'),
      'Message should explain the rejection: ' + message
    );
  }

  @IsTest
  static void adHocMethodsRejectNonActionPlanRecordIds() {
    Account account = new Account(Name = 'Not A Plan');
    insert account;
    Id taskId = createLooseTask('Nowhere to go', account.Id);

    Integer rejections = 0;
    Test.startTest();
    try {
      NavexCtaPlaybookController.addAdHocStep(account.Id, taskId);
    } catch (AuraHandledException e) {
      rejections++;
    }
    try {
      NavexCtaPlaybookController.deleteAdHocStep(account.Id, null);
    } catch (AuraHandledException e) {
      rejections++;
    }
    Test.stopTest();

    Assert.areEqual(
      2,
      rejections,
      'Both ad-hoc methods should guard the record id'
    );
  }

  @IsTest
  static void addAdHocStepCleansUpTheTaskWhenTheLinkCannotBeCreated() {
    ActionPlan plan = buildPlan(new List<String>{ '1: Internal Sync' });
    Id taskId = createLooseTask('Doomed step', plan.TargetId);
    // Removing the task first makes the junction insert fail the way a validation rule would.
    delete new Task(Id = taskId);

    String message;
    Test.startTest();
    try {
      NavexCtaPlaybookController.addAdHocStep(plan.Id, taskId);
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    Test.stopTest();

    Assert.isNotNull(
      message,
      'A junction that cannot be inserted should surface an error'
    );
    Assert.isTrue(
      message.contains('could not be added'),
      'Message should explain the failure: ' + message
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM ActionPlanItem WHERE ActionPlanId = :plan.Id],
      'Only the template step should remain'
    );
  }

  @IsTest
  static void getPlaybookReportsAPlanThatNoLongerExists() {
    ActionPlan plan = buildPlan(new List<String>{ '1: Internal Sync' });
    Id planId = plan.Id;
    delete plan;

    String message;
    Test.startTest();
    try {
      NavexCtaPlaybookController.getPlaybook(planId);
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    Test.stopTest();

    Assert.isNotNull(
      message,
      'A deleted plan should be reported, not swallowed'
    );
    Assert.isTrue(
      message.contains('could not be found'),
      'Message should explain the failure: ' + message
    );
  }

  @IsTest
  static void getPlaybookBreaksIdenticalStepNamesByCreationOrder() {
    ActionPlan plan = buildPlan(new List<String>{ '1: Internal Sync' });
    delete [SELECT Id FROM ActionPlanItem WHERE ActionPlanId = :plan.Id];
    ActionPlanItem first = addWaitingItem(plan.Id, 'Follow up', 0);
    ActionPlanItem second = addWaitingItem(plan.Id, 'Follow up', 0);

    Test.startTest();
    NavexCtaPlaybookController.Playbook result = NavexCtaPlaybookController.getPlaybook(
      plan.Id
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      result.items.size(),
      'Both identically named steps should be returned'
    );
    Assert.areEqual(
      first.Id,
      result.items[0].itemId,
      'The older step sorts first'
    );
    Assert.areEqual(
      second.Id,
      result.items[1].itemId,
      'The newer step sorts second'
    );
  }

  /** A Task that exists but is not yet a step, mirroring what lightning-record-edit-form creates. */
  private static Id createLooseTask(String subject, Id whatId) {
    Task task = new Task(
      Subject = subject,
      Status = 'Not Started',
      Priority = 'Normal',
      ActivityDate = Date.today().addDays(3),
      WhatId = whatId
    );
    insert task;
    return task.Id;
  }

  @IsTest
  static void playbookIsReadOnlyForUsersWithoutTaskEditAccess() {
    ActionPlan plan = buildPlan(new List<String>{ '1: Internal Sync' });
    Id planId = plan.Id;
    Id taskId = [
      SELECT ItemId
      FROM ActionPlanItem
      WHERE ActionPlanId = :planId AND ItemId != NULL
      LIMIT 1
    ]
    .ItemId;

    // Profile names vary by org, so fall back through the usual low-privilege candidates.
    List<Profile> candidates = [
      SELECT Id, Name
      FROM Profile
      WHERE
        Name IN (
          'Read Only',
          'Minimum Access - Salesforce',
          'Chatter Only User'
        )
      ORDER BY Name
      LIMIT 1
    ];
    Assert.isFalse(
      candidates.isEmpty(),
      'This org needs a low-privilege profile for this test'
    );

    User restricted = new User(
      Alias = 'plbkro',
      Email = 'playbook.readonly@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'ReadOnly',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = candidates[0].Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'playbook.readonly.' +
        Math.abs(Crypto.getRandomInteger()) +
        '@example.com'
    );
    insert restricted;

    String message;
    Test.startTest();
    System.runAs(restricted) {
      try {
        NavexCtaPlaybookController.toggleTaskCompletion(planId, taskId, true);
      } catch (Exception e) {
        message = e.getMessage();
      }
    }
    Test.stopTest();

    Assert.isNotNull(
      message,
      'A user without task edit access should be blocked'
    );
    Assert.isFalse(
      [SELECT IsClosed FROM Task WHERE Id = :taskId].IsClosed,
      'The task must not change'
    );
  }
}
