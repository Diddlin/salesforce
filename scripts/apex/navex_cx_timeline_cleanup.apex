// ============================================================================
// NAVEX CX Demo - remove the seeded Meridian Health lifecycle milestones
//
// Deletes only the nine activities created by navex_cx_timeline_data.apex: activities on
// Meridian Health whose Subject is one of SEEDED_SUBJECTS. Everything else on the account —
// the org's own June-August 2026 activities and the Action Plan playbook tasks — is left
// untouched. Keep this list identical to the one in navex_cx_timeline_data.apex.
//
// The CX_Milestone__c flag needs no separate cleanup: it lives on these records and goes with
// them. The tail of this script reports any activity still carrying the flag, which would be one
// a CSM ticked by hand and which would therefore stay on the curated timeline.
//
//   Run: sf apex run --file scripts/apex/navex_cx_timeline_cleanup.apex --target-org HeadlessOrg
// ============================================================================

Id ACCT = '001Hs00005wLdgKIAS'; // Meridian Health

Set<String> SEEDED_SUBJECTS = new Set<String>{
  'Platform kickoff',
  'Onboarding complete',
  'Adoption review',
  'Champion role change',
  'Health check',
  'Adoption alert',
  'EBR - Sarah Okonkowo',
  'API escalation',
  'Renewal planning'
};

List<Task> seededTasks = [
  SELECT Id, Subject, ActivityDate
  FROM Task
  WHERE WhatId = :ACCT AND Subject IN :SEEDED_SUBJECTS
];
List<Event> seededEvents = [
  SELECT Id, Subject, ActivityDate
  FROM Event
  WHERE WhatId = :ACCT AND Subject IN :SEEDED_SUBJECTS
];

for (Task t : seededTasks) {
  System.debug('Deleting Task  ' + t.ActivityDate + '  ' + t.Subject);
}
for (Event e : seededEvents) {
  System.debug('Deleting Event ' + e.ActivityDate + '  ' + e.Subject);
}

if (!seededTasks.isEmpty()) {
  delete seededTasks;
}
if (!seededEvents.isEmpty()) {
  delete seededEvents;
}

System.debug(
  'Removed ' +
    seededTasks.size() +
    ' Tasks and ' +
    seededEvents.size() +
    ' Events seeded for the CX Timeline. Remaining activities on this account were not touched.'
);

Integer stillFlagged =
  [SELECT COUNT() FROM Task WHERE WhatId = :ACCT AND CX_Milestone__c = TRUE] +
  [SELECT COUNT() FROM Event WHERE WhatId = :ACCT AND CX_Milestone__c = TRUE];
System.debug(
  stillFlagged == 0
    ? 'No activity on this account is flagged CX_Milestone__c. The curated timeline is now empty.'
    : stillFlagged +
      ' activity/activities on this account are still flagged CX_Milestone__c and will keep appearing on the curated timeline.'
);
