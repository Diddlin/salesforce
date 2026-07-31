// Read-only verification of NavexCtaPlaybookController against the two Meridian action plans.
// No DML.
List<ActionPlan> plans = [
    SELECT Id, Name
    FROM ActionPlan
    WHERE TargetId = '001Hs00005wLdgKIAS'
    ORDER BY Name
];

for (ActionPlan p : plans) {
    NavexCtaPlaybookController.Playbook pb = NavexCtaPlaybookController.getPlaybook(p.Id);
    System.debug('=====================================================');
    System.debug(
        'PLAN | ' + pb.planName + ' | type=' + pb.ctaType + ' | state=' + pb.state +
        ' | start=' + pb.startDate + ' | end=' + pb.endDate
    );
    System.debug('TEMPLATE | ' + pb.templateName);
    System.debug('GUIDANCE | ' + pb.templateGuidance);
    System.debug(
        'PROGRESS | ' + pb.completedCount + '/' + pb.totalCount + ' = ' + pb.percentComplete +
        '% | canEditTasks=' + pb.canEditTasks
    );
    Integer waiting = 0;
    for (NavexCtaPlaybookController.PlaybookItem i : pb.items) {
        if (i.isWaiting) {
            waiting++;
        }
        System.debug(
            '  ROW | ' + i.subject +
            ' | waiting=' + i.isWaiting +
            ' | taskId=' + i.taskId +
            ' | status=' + i.status +
            ' | due=' + i.dueDate +
            ' | overdue=' + i.isOverdue +
            ' | complete=' + i.isComplete +
            ' | required=' + i.isRequired +
            ' | priority=' + i.priority +
            ' | owner=' + i.ownerName +
            ' | dep=' + i.dependencyStatus
        );
    }
    System.debug('WAITING ROWS (null ItemId rendered as locked): ' + waiting);
}
