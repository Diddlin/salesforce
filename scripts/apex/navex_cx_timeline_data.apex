// ============================================================================
// NAVEX CX Demo - Meridian Health lifecycle milestones (idempotent / re-runnable)
//
// Seeds the nine historical milestones the navexCxTimeline component plots, spanning
// March 2025 to May 2026. The org's own activity data only reaches back to June 2026,
// which is not enough history to tell a lifecycle story.
//
// This is demo content, not test data: it is meant to persist. Re-running the script
// updates the existing records in place rather than creating duplicates.
//
//   Run:     sf apex run --file scripts/apex/navex_cx_timeline_data.apex --target-org HeadlessOrg
//   Remove:  sf apex run --file scripts/apex/navex_cx_timeline_cleanup.apex --target-org HeadlessOrg
//
// Identity / idempotency marker: a seeded record is the activity on THIS account whose
// Subject is one of SEEDED_SUBJECTS below. Subject was chosen over a marker in the
// Description because the description is read aloud in the demo and shown verbatim in the
// component's detail panel, so it has to stay clean. Keep the subjects in this file and in
// navex_cx_timeline_cleanup.apex identical.
//
// Every seeded record is also flagged CX_Milestone__c = true. That is what the component's
// "Lifecycle Milestones Only" property filters on, and it is the reason the timeline shows these
// nine rather than every logged call and email on the account. The subject list above stays the
// idempotency key; the checkbox is the curation signal, and the two are deliberately separate so
// that a CSM can tick any other activity onto the timeline from the UI without editing a script.
//
// Note on ordering: navex_cx_demo_data.apex begins with `delete [SELECT Id FROM Task WHERE
// WhatId = :ACCT]`, so if you re-run that loader you must re-run this script afterwards.
// ============================================================================

Id ACCT = '001Hs00005wLdgKIAS'; // Meridian Health

List<Account> targets = [SELECT Id, Name FROM Account WHERE Id = :ACCT LIMIT 1];
if (targets.isEmpty()) {
  throw new IllegalArgumentException(
    'Meridian Health (' +
      ACCT +
      ') was not found in this org. Nothing was changed.'
  );
}
System.debug('Seeding lifecycle milestones for ' + targets[0].Name);

// The SDO's Customer Success persona, so the detail panel reads "Logged by Sarah Success"
// rather than naming whoever happened to run the script. Falls back to the running user.
Id milestoneOwner = UserInfo.getUserId();
for (User u : [
  SELECT Id
  FROM User
  WHERE Name = 'Sarah Success' AND IsActive = TRUE
  LIMIT 1
]) {
  milestoneOwner = u.Id;
}

// ---------------------------------------------------------------- definitions
// object | subject | activity type | date | description
List<List<Object>> seeds = new List<List<Object>>{
  new List<Object>{
    'Event',
    'Platform kickoff',
    'Meeting',
    Date.newInstance(2025, 3, 11),
    'Kickoff for NAVEX One: EthicsPoint Hotline, Case Management and PolicyTech Policy Management. ' +
    'Attendees: Dana Whitfield (VP Compliance, executive sponsor), Marcus Reyes (Compliance Program Manager, ' +
    'day-to-day champion) and Priya Nair (CSM). Success measures agreed at kickoff: hotline live across all ' +
    'facilities inside 90 days, 400 policies migrated into PolicyTech, and 90% of corporate staff through ' +
    'Compliance Training by year end.'
  },
  new List<Object>{
    'Task',
    'Onboarding complete',
    'Other',
    Date.newInstance(2025, 6, 24),
    'Implementation signed off ahead of schedule. EthicsPoint Hotline live across all 14 facilities, 412 policies ' +
    'migrated into PolicyTech, and Case Management workflows configured for both HR and Ethics intake. ' +
    'Adoption baseline recorded at go-live: 121 active PolicyTech users. Marcus Reyes certified as the in-house ' +
    'PolicyTech administrator and single point of contact for enablement.'
  },
  new List<Object>{
    'Event',
    'Adoption review',
    'Meeting',
    Date.newInstance(2025, 9, 17),
    'First quarterly adoption review. PolicyTech active users at 118 against the 121 go-live baseline and policy ' +
    'attestation completion at 87% — both healthy. Hotline volume steady at 34 reports for the quarter. ' +
    'Corporate Compliance Training completion is the outlier at 61% against a 90% target. Action agreed: ' +
    'Marcus Reyes to run departmental training pushes through Q4, reviewed at the January health check.'
  },
  new List<Object>{
    'Task',
    'Champion role change',
    'Email',
    Date.newInstance(2025, 10, 28),
    'Marcus Reyes has moved to an internal audit role and is no longer the PolicyTech administrator. No named ' +
    'replacement. Compliance operations have been absorbed by Dana Whitfield\'s team on top of existing duties. ' +
    'Risk logged against the account: the only trained administrator has left, no successor has been enabled, ' +
    'and PolicyTech adoption has no internal owner. Recommended a transition enablement package; no response yet.'
  },
  new List<Object>{
    'Task',
    'Health check',
    'Call',
    Date.newInstance(2026, 1, 15),
    'Quarterly health check with Dana Whitfield. Account health down to 71. PolicyTech active users at 62, roughly ' +
    'half the go-live baseline, and attestation completion has slipped from 87% to 64%. Hotline and Case ' +
    'Management remain healthy and well used. Dana confirmed no replacement administrator has been appointed and ' +
    'that compliance headcount is frozen until the new fiscal year. Offered a CSM-led adoption sprint; Dana asked ' +
    'to revisit after budget planning closes.'
  },
  new List<Object>{
    'Task',
    'Adoption alert',
    'Other',
    Date.newInstance(2026, 3, 12),
    'Active users at cycle low — 34. Eight consecutive months of decline since champion departure. Enablement plan ' +
    'proposed: dedicated onboarding sessions for new hires, CSM-led adoption sprint. Response pending.'
  },
  new List<Object>{
    'Event',
    'EBR - Sarah Okonkowo',
    'Meeting',
    Date.newInstance(2026, 4, 16),
    'Executive business review with Sarah Okonkowo, newly appointed Chief Compliance Officer, and Dana Whitfield. ' +
    'Walked the three-contract portfolio: EthicsPoint Hotline (health 88) and Case Management (84) performing ' +
    'well, PolicyTech at 47 and Corporate Compliance Training at 49. Sarah questioned whether PolicyTech is worth ' +
    'its licence cost at current utilisation and asked for a consolidation proposal ahead of the November ' +
    'renewal. NAVEX committed to an enablement plan and a follow-up within 30 days.'
  },
  new List<Object>{
    'Task',
    'API escalation',
    'Call',
    Date.newInstance(2026, 5, 8),
    'Severity 2 escalation raised by Meridian IT. The PolicyTech attestation API returned intermittent 500s against ' +
    'their HRIS sync, blocking nightly user provisioning for four working days. Logged as case #40188. Root cause ' +
    'was a rate limit on the bulk attestation endpoint; the limit was raised and the sync has been stable since. ' +
    'Sarah Okonkowo cited the incident in writing as evidence of platform fragility, which now sits alongside the ' +
    'adoption numbers in the renewal conversation.'
  },
  new List<Object>{
    'Task',
    'Renewal planning',
    'Email',
    Date.newInstance(2026, 5, 26),
    'Renewal planning note sent ahead of the 30 November contract end. Renewal likelihood scored at 58, with the ' +
    'NAVEX One contract flagged Medium risk and Corporate Compliance Training High. Proposed a consolidation ' +
    'path: hold EthicsPoint Hotline and Case Management at current levels, restructure PolicyTech onto a smaller ' +
    'committed user tier bundled with an enablement package, and align all three contracts to a single ' +
    'co-terminous renewal date. Awaiting Sarah Okonkowo\'s response.'
  }
};

// ---------------------------------------------------------------- fan out by object
Map<String, List<Object>> taskSeeds = new Map<String, List<Object>>();
Map<String, List<Object>> eventSeeds = new Map<String, List<Object>>();
for (List<Object> seed : seeds) {
  String objectType = (String) seed[0];
  String subject = (String) seed[1];
  if (objectType == 'Event') {
    eventSeeds.put(subject, seed);
  } else {
    taskSeeds.put(subject, seed);
  }
}
Set<String> allSubjects = new Set<String>();
allSubjects.addAll(taskSeeds.keySet());
allSubjects.addAll(eventSeeds.keySet());

// A subject that has moved between Task and Event across script revisions would otherwise
// leave a duplicate node on the timeline, so any wrong-object leftovers go first.
List<Task> strandedTasks = [
  SELECT Id
  FROM Task
  WHERE WhatId = :ACCT AND Subject IN :eventSeeds.keySet()
];
List<Event> strandedEvents = [
  SELECT Id
  FROM Event
  WHERE WhatId = :ACCT AND Subject IN :taskSeeds.keySet()
];
if (!strandedTasks.isEmpty()) {
  delete strandedTasks;
  System.debug(
    'Removed ' + strandedTasks.size() + ' stale Task(s) now seeded as Events'
  );
}
if (!strandedEvents.isEmpty()) {
  delete strandedEvents;
  System.debug(
    'Removed ' + strandedEvents.size() + ' stale Event(s) now seeded as Tasks'
  );
}

// ---------------------------------------------------------------- TASKS
Map<String, Task> existingTasks = new Map<String, Task>();
for (Task t : [
  SELECT Id, Subject
  FROM Task
  WHERE WhatId = :ACCT AND Subject IN :taskSeeds.keySet()
]) {
  existingTasks.put(t.Subject, t);
}

List<Task> tasksToUpsert = new List<Task>();
for (String subject : taskSeeds.keySet()) {
  List<Object> seed = taskSeeds.get(subject);
  Task t = existingTasks.containsKey(subject)
    ? new Task(Id = existingTasks.get(subject).Id)
    : new Task(WhatId = ACCT);
  t.Subject = subject;
  t.Type = (String) seed[2];
  t.ActivityDate = (Date) seed[3];
  t.Description = (String) seed[4];
  t.Status = 'Completed';
  t.Priority = 'Normal';
  t.OwnerId = milestoneOwner;
  t.CX_Milestone__c = true;
  tasksToUpsert.add(t);
}
upsert tasksToUpsert;

// ---------------------------------------------------------------- EVENTS
Map<String, Event> existingEvents = new Map<String, Event>();
for (Event e : [
  SELECT Id, Subject
  FROM Event
  WHERE WhatId = :ACCT AND Subject IN :eventSeeds.keySet()
]) {
  existingEvents.put(e.Subject, e);
}

List<Event> eventsToUpsert = new List<Event>();
for (String subject : eventSeeds.keySet()) {
  List<Object> seed = eventSeeds.get(subject);
  Date milestoneDate = (Date) seed[3];
  // A 10:00 start keeps the event on the intended calendar day in every US timezone the demo
  // is run from, which matters because the timeline label is derived from ActivityDate.
  Datetime startsAt = Datetime.newInstance(
    milestoneDate,
    Time.newInstance(10, 0, 0, 0)
  );
  Event e = existingEvents.containsKey(subject)
    ? new Event(Id = existingEvents.get(subject).Id)
    : new Event(WhatId = ACCT);
  e.Subject = subject;
  e.Type = (String) seed[2];
  e.Description = (String) seed[4];
  e.StartDateTime = startsAt;
  e.EndDateTime = startsAt.addMinutes(60);
  e.IsAllDayEvent = false;
  e.OwnerId = milestoneOwner;
  e.CX_Milestone__c = true;
  eventsToUpsert.add(e);
}
upsert eventsToUpsert;

// ---------------------------------------------------------------- verify
Integer taskCount = [
  SELECT COUNT()
  FROM Task
  WHERE WhatId = :ACCT AND Subject IN :allSubjects
];
Integer eventCount = [
  SELECT COUNT()
  FROM Event
  WHERE WhatId = :ACCT AND Subject IN :allSubjects
];
System.debug(
  'Seeded ' +
    taskCount +
    ' Tasks + ' +
    eventCount +
    ' Events = ' +
    (taskCount + eventCount) +
    ' lifecycle milestones on Meridian Health'
);
for (Task t : [
  SELECT Subject, ActivityDate, Type, CX_Milestone__c
  FROM Task
  WHERE WhatId = :ACCT AND Subject IN :allSubjects
  ORDER BY ActivityDate
]) {
  System.debug(
    '  Task  ' +
      t.ActivityDate +
      '  ' +
      t.Subject +
      '  (' +
      t.Type +
      ')  CX_Milestone__c=' +
      t.CX_Milestone__c
  );
}
for (Event e : [
  SELECT Subject, ActivityDate, Type, CX_Milestone__c
  FROM Event
  WHERE WhatId = :ACCT AND Subject IN :allSubjects
  ORDER BY ActivityDate
]) {
  System.debug(
    '  Event ' +
      e.ActivityDate +
      '  ' +
      e.Subject +
      '  (' +
      e.Type +
      ')  CX_Milestone__c=' +
      e.CX_Milestone__c
  );
}

// The number the component will actually plot with "Lifecycle Milestones Only" on. Counts the
// whole account, not just the seeded subjects, so a stray flag ticked elsewhere shows up here.
Integer flaggedTasks = [
  SELECT COUNT()
  FROM Task
  WHERE WhatId = :ACCT AND CX_Milestone__c = TRUE
];
Integer flaggedEvents = [
  SELECT COUNT()
  FROM Event
  WHERE WhatId = :ACCT AND CX_Milestone__c = TRUE
];
System.debug(
  'Flagged CX_Milestone__c on this account: ' +
    flaggedTasks +
    ' Tasks + ' +
    flaggedEvents +
    ' Events = ' +
    (flaggedTasks + flaggedEvents) +
    ' (expected 9)'
);
