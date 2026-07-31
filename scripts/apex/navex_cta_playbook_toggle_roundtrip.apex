// Round-trip check: complete one Meridian playbook step through the controller, confirm the Task
// really changed in the org, then put it straight back so the demo data is unchanged.
final Id PLAN_ID = '07rHs000000QjpNIAS'; // RISK: PolicyTech Adoption Review - Meridian
final Id TASK_ID = '00THs0000EDfvnTMQR'; // 3: Generate Configuration Report

Task before = [SELECT Id, Subject, Status, IsClosed FROM Task WHERE Id = :TASK_ID];
System.debug('BEFORE | ' + before.Subject + ' | status=' + before.Status + ' | closed=' + before.IsClosed);
System.debug('BEFORE ITEMS | ' + [SELECT Id, Name, ItemId FROM ActionPlanItem WHERE ActionPlanId = :PLAN_ID].size() + ' items');

NavexCtaPlaybookController.Playbook afterComplete = NavexCtaPlaybookController.toggleTaskCompletion(
    PLAN_ID,
    TASK_ID,
    true
);
Task mid = [SELECT Id, Status, IsClosed FROM Task WHERE Id = :TASK_ID];
System.debug(
    'AFTER COMPLETE | task.status=' + mid.Status + ' | closed=' + mid.IsClosed +
    ' | progress=' + afterComplete.completedCount + '/' + afterComplete.totalCount +
    ' = ' + afterComplete.percentComplete + '%'
);

NavexCtaPlaybookController.Playbook afterRevert = NavexCtaPlaybookController.toggleTaskCompletion(
    PLAN_ID,
    TASK_ID,
    false
);
Task restored = [SELECT Id, Status, IsClosed FROM Task WHERE Id = :TASK_ID];
System.debug(
    'AFTER REVERT | task.status=' + restored.Status + ' | closed=' + restored.IsClosed +
    ' | progress=' + afterRevert.completedCount + '/' + afterRevert.totalCount +
    ' = ' + afterRevert.percentComplete + '%'
);
System.debug('RESTORED TO ORIGINAL STATUS: ' + (restored.Status == before.Status));
System.debug('AFTER ITEMS | ' + [SELECT Id, Name, ItemId FROM ActionPlanItem WHERE ActionPlanId = :PLAN_ID].size() + ' items');
