// ============================================================================
// NAVEX CX Demo - Meridian Health persona data loader (idempotent / re-runnable)
// Native-first: enriches the existing Customer Success SDO. Uses standard
// Account / Contract / Asset / Product2 / Task / ActionPlan + the org's
// Tech_Success_Scorecard__c. Only the minimal custom fields added by this demo
// (Health/NPS, Contract_Health/Renewal_Risk, Asset.Contract__c/Product_Health/
// Renewal_Risk) are populated on top.
// ============================================================================
Id ACCT = '001Hs00005wLdgKIAS';            // Meridian Health
Id QBR_VER  = '0PTHs000000MtCEOA0';         // LIFECYCLE: Upcoming QBR (template version)
Id RISK_VER = '0PTHs000000MtCFOA0';         // RISK: Adoption - Configuration Review (CS)

// ---- helper: colored indicator (matches existing scorecard convention) ----
Map<String,String> ind = new Map<String,String>{
  'green'  => '<img src="/img/samples/color_green.gif" alt="green" style="height:30px; width:30px;" border="0"/>',
  'yellow' => '<img src="/img/samples/color_yellow.gif" alt="yellow" style="height:30px; width:30px;" border="0"/>',
  'red'    => '<img src="/img/samples/color_red.gif" alt="red" style="height:30px; width:30px;" border="0"/>'
};

// ---------------------------------------------------------------- RESET
delete [SELECT Id FROM Asset WHERE AccountId = :ACCT];
delete [SELECT Id FROM Contract WHERE AccountId = :ACCT];
delete [SELECT Id FROM Tech_Success_Scorecard__c WHERE Tech_Account__c = :ACCT];
delete [SELECT Id FROM ActionPlan WHERE TargetId = :ACCT];
delete [SELECT Id FROM Task WHERE WhatId = :ACCT];

// ---------------------------------------------------------------- ACCOUNT
Account a = new Account(Id = ACCT, Health_Score__c = 64, NPS__c = 6); // NPS 6 => Detractor
update a;

// ---------------------------------------------------------------- PRODUCTS (reuse by name)
Map<String,String> famByName = new Map<String,String>{
  'EthicsPoint Hotline'          => 'Hotline & Incident Management',
  'Case Management'              => 'Hotline & Incident Management',
  'Location Database'            => 'Hotline & Incident Management',
  'PolicyTech Policy Management' => 'Policy & Procedure Management',
  'Compliance Training'          => 'Compliance Training'
};
Map<String,Id> prodId = new Map<String,Id>();
for (Product2 p : [SELECT Id, Name FROM Product2 WHERE Name IN :famByName.keySet()]) {
  prodId.put(p.Name, p.Id);
}
List<Product2> toIns = new List<Product2>();
for (String nm : famByName.keySet()) {
  if (!prodId.containsKey(nm)) toIns.add(new Product2(Name = nm, Family = famByName.get(nm), IsActive = true));
}
if (!toIns.isEmpty()) { insert toIns; for (Product2 p : toIns) prodId.put(p.Name, p.Id); }

// ---------------------------------------------------------------- CONTRACTS (company -> contract)
Contract c1 = new Contract(AccountId=ACCT, Status='Draft', StartDate=Date.today().addMonths(-9), ContractTerm=12,
    Contract_Health__c=72, Renewal_Risk__c='Medium', External_ID__c='NAVEX-CX-C1',
    Description='NAVEX One - Hotline & Policy Suite (multi-product: Hotline + PolicyTech)');
Contract c2 = new Contract(AccountId=ACCT, Status='Draft', StartDate=Date.today().addMonths(-4), ContractTerm=12,
    Contract_Health__c=83, Renewal_Risk__c='Low', External_ID__c='NAVEX-CX-C2',
    Description='Compliance Training - Clinical Team');
Contract c3 = new Contract(AccountId=ACCT, Status='Draft', StartDate=Date.today().addMonths(-7), ContractTerm=12,
    Contract_Health__c=51, Renewal_Risk__c='High', External_ID__c='NAVEX-CX-C3',
    Description='Compliance Training - Corporate Team');
insert new List<Contract>{ c1, c2, c3 };

// ---------------------------------------------------------------- ASSETS (contract -> product, with product-level health)
List<Asset> assets = new List<Asset>{
  new Asset(Name='EthicsPoint Hotline', AccountId=ACCT, Product2Id=prodId.get('EthicsPoint Hotline'),
            Contract__c=c1.Id, Status='Installed', Product_Health__c=88, Renewal_Risk__c='Low'),
  new Asset(Name='Case Management', AccountId=ACCT, Product2Id=prodId.get('Case Management'),
            Contract__c=c1.Id, Status='Installed', Product_Health__c=84, Renewal_Risk__c='Low'),
  new Asset(Name='PolicyTech Policy Management', AccountId=ACCT, Product2Id=prodId.get('PolicyTech Policy Management'),
            Contract__c=c1.Id, Status='Installed', Product_Health__c=47, Renewal_Risk__c='High'),
  new Asset(Name='Compliance Training (Clinical Team)', AccountId=ACCT, Product2Id=prodId.get('Compliance Training'),
            Contract__c=c2.Id, Status='Installed', Product_Health__c=85, Renewal_Risk__c='Low'),
  new Asset(Name='Compliance Training (Corporate Team)', AccountId=ACCT, Product2Id=prodId.get('Compliance Training'),
            Contract__c=c3.Id, Status='Installed', Product_Health__c=49, Renewal_Risk__c='High')
};
insert assets;

// ---------------------------------------------------------------- SCORECARD (company-level health breakdown)
List<Tech_Success_Scorecard__c> sc = new List<Tech_Success_Scorecard__c>{
  new Tech_Success_Scorecard__c(Tech_Account__c=ACCT, Measure__c='Total Platform Usage', Measure_Category__c='Adoption', Score__c=82, Date_Modified__c=Date.today()),
  new Tech_Success_Scorecard__c(Tech_Account__c=ACCT, Measure__c='Monthly Active Users %', Measure_Category__c='Adoption', Score__c=63, Date_Modified__c=Date.today()),
  new Tech_Success_Scorecard__c(Tech_Account__c=ACCT, Measure__c='NPS', Measure_Category__c='Adoption', Score__c=40, Date_Modified__c=Date.today()),
  new Tech_Success_Scorecard__c(Tech_Account__c=ACCT, Measure__c='Likelihood to Renew', Measure_Category__c='Renewal', Score__c=58, Date_Modified__c=Date.today()),
  new Tech_Success_Scorecard__c(Tech_Account__c=ACCT, Measure__c='CSAT', Measure_Category__c='Service', Score__c=71, Date_Modified__c=Date.today()),
  new Tech_Success_Scorecard__c(Tech_Account__c=ACCT, Measure__c='Age of Cases', Measure_Category__c='Service', Score__c=45, Date_Modified__c=Date.today())
};
insert sc;

// ---------------------------------------------------------------- CSM ACTIVITY (clean timeline + meeting->follow-ups)
Id me = UserInfo.getUserId();
List<Task> tasks = new List<Task>{
  new Task(WhatId=ACCT, OwnerId=me, Subject='EBR - Q2 Business Review with Meridian', Type='Meeting', Status='Completed', Priority='Normal', ActivityDate=Date.today().addDays(-5), Description='Reviewed adoption across Hotline, PolicyTech and Training. PolicyTech feature gaps raised by compliance team.'),
  new Task(WhatId=ACCT, OwnerId=me, Subject='Check-in: PolicyTech adoption concerns', Type='Call', Status='Completed', Priority='High', ActivityDate=Date.today().addDays(-12)),
  new Task(WhatId=ACCT, OwnerId=me, Subject='Sent NPS detractor follow-up note', Type='Email', Status='Completed', Priority='Normal', ActivityDate=Date.today().addDays(-3)),
  // follow-ups generated off the EBR meeting (the "meeting -> to-do" story)
  new Task(WhatId=ACCT, OwnerId=me, Subject='Follow-up: Share PolicyTech feature roadmap', Type='Prep', Status='Not Started', Priority='High', ActivityDate=Date.today().addDays(3)),
  new Task(WhatId=ACCT, OwnerId=me, Subject='Follow-up: Schedule Corporate Training QBR', Type='Prep', Status='Not Started', Priority='Normal', ActivityDate=Date.today().addDays(5))
};
insert tasks;

// ---------------------------------------------------------------- CTAs (Action Plans from native templates)
List<ActionPlan> aps = new List<ActionPlan>{
  new ActionPlan(Name='LIFECYCLE: NPS Detractor Follow-up - Meridian', ActionPlanTemplateVersionId=QBR_VER,
                 TargetId=ACCT, ActionPlanType='Sales', ActionPlanState='In Progress',
                 Tech_CTA_Type__c='Lifecycle', StartDate=Date.today().addDays(-2)),
  new ActionPlan(Name='RISK: PolicyTech Adoption Review - Meridian', ActionPlanTemplateVersionId=RISK_VER,
                 TargetId=ACCT, ActionPlanType='Sales', ActionPlanState='Not Started',
                 Tech_CTA_Type__c='Risk', StartDate=Date.today())
};
insert aps;

System.debug('NAVEX_CX_DONE Account=' + ACCT + ' Contracts=' + new List<Id>{c1.Id,c2.Id,c3.Id} + ' Assets=' + assets.size() + ' Scorecards=' + sc.size() + ' Tasks=' + tasks.size() + ' ActionPlans=' + aps.size());
