/*
 * Sets the guidance copy surfaced by the navexCtaPlaybook LWC.
 *
 * The component reads guidance from ActionPlanTemplate.Description via the
 * plan's template version, so guidance is per-TEMPLATE, not per-plan. Both
 * templates below are shared SDO templates, so the copy is written to suit the
 * template's own purpose rather than one specific demo plan.
 *
 * Original values, for rollback:
 *   0PRHs000000MufJOAS  LIFECYCLE: Upcoming QBR                  -> 'General QBR CTA framework'
 *   0PRHs000000MufMOAS  RISK: Adoption - Configuration Review    -> 'General Adoption CTA framework.'
 *
 * Idempotent: re-running sets the same values.
 */
// ActionPlanTemplate.Description is capped at 255 characters, so this copy is
// deliberately tight. For longer guidance, set the LWC's guidanceText property
// in App Builder instead -- it overrides this and has no 255 limit.
final String QBR_GUIDANCE =
    'Review NPS history, open cases and recent usage first, so the conversation starts from ' +
    'evidence, not a score. Lead with what changed, not the number. Confirm the program owner ' +
    'before escalating to an exec check-in, and log the outcome the same day.';

final String ADOPTION_GUIDANCE =
    'Start from the data: which features are configured, which are actually used, and by whom. ' +
    'Separate a configuration gap from a training gap before proposing a fix. Agree a measurable ' +
    'usage target with the program owner and set the follow-up date.';

Map<Id, String> guidanceByTemplateId = new Map<Id, String>{
    '0PRHs000000MufJOAS' => QBR_GUIDANCE,
    '0PRHs000000MufMOAS' => ADOPTION_GUIDANCE
};

for (String g : guidanceByTemplateId.values()) {
    if (g.length() > 255) {
        throw new IllegalArgumentException('Guidance exceeds the 255 char limit: ' + g.length());
    }
}

List<ActionPlanTemplate> toUpdate = new List<ActionPlanTemplate>();
for (ActionPlanTemplate t : [
    SELECT Id, Name, Description
    FROM ActionPlanTemplate
    WHERE Id IN :guidanceByTemplateId.keySet()
]) {
    String desired = guidanceByTemplateId.get(t.Id);
    System.debug('BEFORE ' + t.Name + ' :: ' + t.Description);
    if (t.Description != desired) {
        t.Description = desired;
        toUpdate.add(t);
    }
}

if (!toUpdate.isEmpty()) {
    update toUpdate;
}
System.debug('Updated ' + toUpdate.size() + ' template(s).');

for (ActionPlanTemplate t : [
    SELECT Name, Description FROM ActionPlanTemplate WHERE Id IN :guidanceByTemplateId.keySet()
]) {
    System.debug('AFTER ' + t.Name + ' :: ' + t.Description);
}
