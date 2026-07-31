// ============================================================================
// NAVEX CX Demo - Meridian Health Account Plan (idempotent / re-runnable)
// Native-first: uses standard AccountPlan + AccountPlanObjective (Sales Planning).
// Objectives are linked to the existing Action Plans (CTAs) via the SDO's
// AccountPlanObjective.Tech_CTA__c lookup -> ActionPlan.
// Run:  sf apex run --target-org HeadlessOrg --file scripts/apex/navex_cx_account_plan.apex
// ============================================================================
Id ACCT = '001Hs00005wLdgKIAS';            // Meridian Health

// ---------------------------------------------------------------- RESET
List<AccountPlan> existing = [SELECT Id FROM AccountPlan WHERE AccountId = :ACCT];
if (!existing.isEmpty()) {
    delete [SELECT Id FROM AccountPlanObjective WHERE AccountPlanId IN :existing];
    delete existing;
}

Integer yr = Date.today().year();
Date yStart = Date.newInstance(yr, 1, 1);
Date yEnd   = Date.newInstance(yr, 12, 31);

// ---------------------------------------------------------------- PLAN
AccountPlan p = new AccountPlan(
    Name       = yr + ' Meridian Health Customer Experience Plan',
    AccountId  = ACCT,
    Status     = 'Active',
    StartDate  = yStart,
    EndDate    = yEnd,

    AccountVision =
      '<p><span style="font-size: 14px;">Partner with Meridian Health to move from fragmented, '
    + 'department-level compliance tooling to a single ethics and compliance program spanning '
    + 'their clinical and corporate organizations &mdash; so that every program owner has the '
    + 'reporting, policy and training coverage they need to satisfy healthcare regulators.</span></p>',

    AccountStrategicPriorities =
      '<p><strong>1. Stabilize the PolicyTech program.</strong> Policy management adoption is the '
    + 'single largest detractor of overall health. Close the feature gaps blocking the compliance '
    + 'team and re-establish confidence before the next renewal cycle.</p><p><br></p>'
    + '<p><strong>2. Unify a split training experience.</strong> Clinical training is performing well '
    + 'while corporate training is not meeting stakeholder needs. Align both programs to a shared '
    + 'success definition rather than managing them as separate relationships.</p><p><br></p>'
    + '<p><strong>3. Protect the core hotline and case management footprint.</strong> These products '
    + 'are healthy and must stay that way &mdash; they anchor the multi-year renewal.</p><p><br></p>'
    + '<p><strong>4. Recover relationship sentiment.</strong> Latest NPS response places Meridian in '
    + 'the detractor band. Convert the survey signal into a structured, visible follow-up.</p>',

    AccountChallenges =
      '<p><strong>1. Multiple budget and program owners.</strong> Compliance, HR and the clinical '
    + 'organization each own separate contracts and hold different views of success, so a single '
    + 'account-level health number hides real risk.</p><p><br></p>'
    + '<p><strong>2. Feature gaps in policy management.</strong> Specific PolicyTech capabilities the '
    + 'compliance team expected are not yet in place, driving low utilization.</p><p><br></p>'
    + '<p><strong>3. Regulatory pressure.</strong> As a healthcare provider, Meridian carries HIPAA and '
    + 'accreditation obligations that make policy attestation and training completion non-negotiable.</p>',

    AccountIndustryTrends =
      '<p>- Increasing regulatory scrutiny of healthcare compliance programs and attestation evidence</p>'
    + '<p>- Consolidation of point compliance tools into single-vendor platforms</p>'
    + '<p>- Growing expectation that ethics reporting is anonymous, multi-channel and auditable</p>',

    RelationshipStrengths =
      '<p>- Executive sponsor in the Chief Compliance Officer is engaged and responsive</p>'
    + '<p>- Hotline and case management are embedded in daily operations with strong utilization</p>'
    + '<p>- Clinical training program owner is a reference-quality advocate</p>',

    RelationshipWeaknesses =
      '<p>- Corporate training stakeholder is disengaged and has not attended the last two reviews</p>'
    + '<p>- No single executive owns the compliance program across clinical and corporate</p>'
    + '<p>- Policy management champion left the organization; replacement not yet identified</p>',

    RelationshipOpportunities =
      '<p>- Location database and HR case SKUs are unpenetrated and map to stated 2027 priorities</p>'
    + '<p>- Consolidating the two training contracts into one agreement simplifies renewal</p>'
    + '<p>- A successful PolicyTech recovery creates a healthcare reference story</p>',

    RelationshipThreats =
      '<p>- Corporate training contract is the most likely non-renewal if sentiment does not improve</p>'
    + '<p>- Competing policy management vendor has been in conversation with the compliance team</p>'
    + '<p>- Stakeholder turnover risk in a newly reorganized compliance function</p>',

    Risk =
      '<p><strong>Primary risk:</strong> policy management is trending down and the corporate training '
    + 'program is actively dissatisfied. Both sit on contracts that renew before the core hotline '
    + 'agreement, so churn would appear earlier than the account-level renewal date suggests.</p>',

    RiskMitigation =
      '<p>- Run the PolicyTech adoption review CTA to document and sequence the outstanding feature gaps</p>'
    + '<p>- Complete the NPS detractor follow-up playbook and close the loop with the program owner</p>'
    + '<p>- Introduce a joint success plan for corporate training with an agreed completion-rate target</p>'
    + '<p>- Track health at contract and product level, not just account level, so early signals stay visible</p>',

    GoToMarketStrategy =
      '<p>Lead with program outcomes rather than product features. Anchor every conversation in '
    + 'attestation coverage, training completion and case resolution time, then map NAVEX capability '
    + 'to those measures per program owner.</p>',

    Notes =
      '<p>Health is tracked at three levels for this account: company, contract and product. '
    + 'See the Renew tab for contract and product level health and renewal risk.</p>'
);
insert p;

// ---------------------------------------------------------------- LINK CTAs
Id npsCta, policyCta;
for (ActionPlan ap : [SELECT Id, Name FROM ActionPlan WHERE TargetId = :ACCT]) {
    if (ap.Name.contains('NPS Detractor'))  npsCta = ap.Id;
    if (ap.Name.contains('PolicyTech'))     policyCta = ap.Id;
}

// ---------------------------------------------------------------- OBJECTIVES
List<AccountPlanObjective> objs = new List<AccountPlanObjective>();

objs.add(new AccountPlanObjective(
    AccountPlanId = p.Id,
    Name          = 'Recover NPS from Detractor to Passive',
    Status        = 'In Progress',
    StartDate     = Date.today().addDays(-14),
    EndDate       = Date.today().addDays(75),
    Tech_CTA__c   = npsCta,
    Description   = 'Close the loop on the latest detractor survey response and re-measure sentiment '
                  + 'with the compliance program owner before the next survey wave.',
    Tech_Objective_Strategy__c = 'Work the detractor follow-up playbook: review survey history, contact '
                  + 'the program owner, agree a remediation plan, then confirm improvement in a follow-up conversation.',
    Tech_Objective_Benefits__c = 'Restores relationship sentiment and removes the largest single detractor '
                  + 'from the account health score.'
));

objs.add(new AccountPlanObjective(
    AccountPlanId = p.Id,
    Name          = 'Raise PolicyTech product health above 70',
    Status        = 'In Progress',
    StartDate     = Date.today().addDays(-7),
    EndDate       = Date.today().addDays(120),
    Tech_CTA__c   = policyCta,
    Description   = 'Policy management currently sits at 47 with high renewal risk driven by feature gaps '
                  + 'and low utilization. Bring it back in line with the rest of the contract.',
    Tech_Objective_Strategy__c = 'Run the adoption and configuration review, document the outstanding '
                  + 'feature requirements, and sequence them against the product roadmap with a named owner.',
    Tech_Objective_Benefits__c = 'Protects the multi-product contract and removes the highest product-level '
                  + 'renewal risk on the account.'
));

objs.add(new AccountPlanObjective(
    AccountPlanId = p.Id,
    Name          = 'Align corporate training to stakeholder needs',
    Status        = 'Not Started',
    StartDate     = Date.today().addDays(14),
    EndDate       = Date.today().addDays(150),
    Description   = 'The same training product is performing well for the clinical team and poorly for the '
                  + 'corporate team. Establish a shared definition of success across both contracts.',
    Tech_Objective_Strategy__c = 'Re-engage the corporate training owner, agree a completion-rate target, '
                  + 'and borrow the enablement pattern already working for the clinical team.',
    Tech_Objective_Benefits__c = 'Addresses the most likely non-renewal on the account and opens the door to '
                  + 'consolidating two training contracts into one.'
));

objs.add(new AccountPlanObjective(
    AccountPlanId = p.Id,
    Name          = 'Secure multi-year renewal on hotline and case management',
    Status        = 'In Progress',
    StartDate     = yStart,
    EndDate       = yEnd,
    Description   = 'Hotline and case management are the healthiest products on the account. Convert that '
                  + 'strength into a longer commitment.',
    Tech_Objective_Strategy__c = 'Evidence the operational value with case volume and resolution metrics, '
                  + 'then build the renewal case with the Chief Compliance Officer.',
    Tech_Objective_Benefits__c = 'Locks in the core footprint and reduces exposure to single-year renewal cycles.'
));

objs.add(new AccountPlanObjective(
    AccountPlanId = p.Id,
    Name          = 'Establish quarterly executive business reviews',
    Status        = 'In Progress',
    StartDate     = yStart,
    EndDate       = yEnd,
    Description   = 'Move from ad hoc check-ins to a predictable executive cadence covering all programs '
                  + 'in one forum.',
    Tech_Objective_Strategy__c = 'Run one review per quarter with compliance, HR and clinical program owners '
                  + 'present, reporting health at contract and product level.',
    Tech_Objective_Benefits__c = 'Creates a single accountable forum and surfaces risk earlier than survey cycles.'
));

objs.add(new AccountPlanObjective(
    AccountPlanId = p.Id,
    Name          = 'Expand into location database and HR case management',
    Status        = 'Not Started',
    StartDate     = Date.today().addDays(60),
    EndDate       = yEnd,
    Description   = 'Two adjacent SKUs map to Meridian stated priorities and are currently unpenetrated.',
    Tech_Objective_Strategy__c = 'Sequence the expansion conversation only after PolicyTech health recovers, '
                  + 'so growth is not pursued on an unstable base.',
    Tech_Objective_Benefits__c = 'Adds incremental ARR and deepens the compliance program footprint.'
));

insert objs;

System.debug('Account Plan: ' + p.Id + ' with ' + objs.size() + ' objectives.');
System.debug('Linked CTAs -> NPS: ' + npsCta + ' | PolicyTech: ' + policyCta);
