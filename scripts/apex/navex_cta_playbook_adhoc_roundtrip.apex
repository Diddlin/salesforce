/**
 * Verifies the new controller entry points against the real Meridian Health plans and puts the
 * demo data back exactly as it was found. Nothing is left behind, including the recycle bin.
 */
final Id RISK_PLAN = '07rHs000000QjpNIAS';
final Id LIFECYCLE_PLAN = '07rHs000000QjpMIAS';

Map<Id, String> fingerprints = new Map<Id, String>();

for (Id planId : new List<Id>{ RISK_PLAN, LIFECYCLE_PLAN }) {
    NavexCtaPlaybookController.Playbook p = NavexCtaPlaybookController.getPlaybook(planId);
    System.debug('=== ' + p.planName);
    System.debug(
        '    ctaType=' + p.ctaType +
        ' | state=' + p.state +
        ' | progress=' + p.completedCount + '/' + p.totalCount + ' (' + p.percentComplete + '%)'
    );
    System.debug(
        '    relatedToId=' + p.relatedToId +
        ' | canEdit=' + p.canEditTasks +
        ' | canCreate=' + p.canCreateSteps +
        ' | canDeleteAdHoc=' + p.canDeleteAdHocSteps
    );
    List<String> lines = new List<String>();
    for (NavexCtaPlaybookController.PlaybookItem i : p.items) {
        System.debug(
            '    - ' + i.subject +
            ' | task=' + i.taskId +
            ' | status=' + i.status +
            ' | complete=' + i.isComplete +
            ' | waiting=' + i.isWaiting +
            ' | overdue=' + i.isOverdue +
            ' | adHoc=' + i.isAdHoc +
            ' | owner=' + i.ownerName
        );
        lines.add(i.itemId + ':' + i.subject + ':' + i.status + ':' + i.isComplete + ':' + i.isWaiting);
    }
    fingerprints.put(planId, String.join(lines, '|'));
}

// ---- ad-hoc create + delete round trip on the RISK plan -------------------------------------
NavexCtaPlaybookController.Playbook before = NavexCtaPlaybookController.getPlaybook(RISK_PLAN);
Id targetId = before.relatedToId;

Task adHoc = new Task(
    Subject = 'VERIFY ad-hoc step (temporary)',
    Status = 'Not Started',
    Priority = 'Normal',
    ActivityDate = Date.today().addDays(2),
    WhatId = targetId
);
insert adHoc;
System.debug('CREATED TASK ' + adHoc.Id + ' whatId=' + targetId);

NavexCtaPlaybookController.Playbook added = NavexCtaPlaybookController.addAdHocStep(RISK_PLAN, adHoc.Id);
System.debug(
    'AFTER ADD | total=' + added.totalCount +
    ' | complete=' + added.completedCount +
    ' | pct=' + added.percentComplete +
    ' | last=' + added.items[added.items.size() - 1].subject +
    ' | lastIsAdHoc=' + added.items[added.items.size() - 1].isAdHoc
);

ActionPlanItem newItem = [
    SELECT Id, DisplayOrder, ItemState, ActionPlanTemplateItemId
    FROM ActionPlanItem
    WHERE ActionPlanId = :RISK_PLAN AND ItemId = :adHoc.Id
];
System.debug(
    'JUNCTION | order=' + newItem.DisplayOrder +
    ' | state=' + newItem.ItemState +
    ' | tplItem=' + newItem.ActionPlanTemplateItemId
);

NavexCtaPlaybookController.Playbook removed = NavexCtaPlaybookController.deleteAdHocStep(RISK_PLAN, newItem.Id);
System.debug(
    'AFTER DELETE | total=' + removed.totalCount +
    ' | complete=' + removed.completedCount +
    ' | pct=' + removed.percentComplete
);

// Hard delete so the temporary task does not linger in the recycle bin.
Database.emptyRecycleBin(new List<Id>{ adHoc.Id });
System.debug('RECYCLE BIN PURGED');

// ---- confirm both plans match their opening fingerprint --------------------------------------
Boolean clean = true;
for (Id planId : new List<Id>{ RISK_PLAN, LIFECYCLE_PLAN }) {
    NavexCtaPlaybookController.Playbook after = NavexCtaPlaybookController.getPlaybook(planId);
    List<String> lines = new List<String>();
    for (NavexCtaPlaybookController.PlaybookItem i : after.items) {
        lines.add(i.itemId + ':' + i.subject + ':' + i.status + ':' + i.isComplete + ':' + i.isWaiting);
    }
    String now = String.join(lines, '|');
    Boolean same = now == fingerprints.get(planId);
    clean = clean && same;
    System.debug('RESTORED ' + planId + ' -> ' + same);
}

System.debug(
    'STRAY TASKS: ' + [SELECT COUNT() FROM Task WHERE Subject LIKE 'VERIFY ad-hoc%' OR Subject LIKE 'PROBE ad-hoc%']
);
System.debug(clean ? 'DEMO DATA UNCHANGED' : 'DEMO DATA DRIFTED - INVESTIGATE');
