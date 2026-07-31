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

// Account external key used by the Customer Success SDO. Tech_Account_Product_Attributes__c
// rows join to the account through Account_Ext_ID__c == Account.External_ID__c, and the
// NEW_Tech_Success_Account_Summary CRM Analytics dashboard is filtered on the same key.
// Existing org values run Account.001-Account.030 plus Tech.953 (CTW) / Tech.954 (Verde).
String ACCT_EXT_ID = 'Tech.955';           // Meridian Health

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
delete [SELECT Id FROM Tech_Account_Product_Attributes__c WHERE Account_Ext_ID__c = :ACCT_EXT_ID];

// ---------------------------------------------------------------- ACCOUNT
Account a = new Account(Id = ACCT, Health_Score__c = 64, NPS__c = 6, // NPS 6 => Detractor
                        External_ID__c = ACCT_EXT_ID);
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

// ------------------------------------------- PRODUCT PORTFOLIO (Tech_Account_Product_Attributes__c)
// The Customer Success SDO stores per-product analytics on this object, joined to the account
// by Account_Ext_ID__c (text) rather than a lookup. Ten monthly snapshots per product so any
// trend/sparkline has a series to draw. Declining products (PolicyTech, Corporate Training)
// start healthy and degrade; healthy products stay flat.
//   product name | PROD_External_ID__c | health start->end | util start->end | churn | ptb | renewal (months out) | ARR
List<List<Object>> portfolio = new List<List<Object>>{
  new List<Object>{ 'EthicsPoint Hotline',                  'Tech.RCA.9001', 84, 88, 0.78, 0.86,  8, 62,  9, 148000 },
  new List<Object>{ 'Case Management',                      'Tech.RCA.9002', 80, 84, 0.71, 0.79, 12, 58,  9,  96000 },
  new List<Object>{ 'PolicyTech Policy Management',         'Tech.RCA.9003', 72, 47, 0.62, 0.31, 62, 18,  3, 121000 },
  new List<Object>{ 'Compliance Training (Clinical Team)',  'Tech.RCA.9004', 81, 85, 0.76, 0.83, 10, 55,  8,  74000 },
  new List<Object>{ 'Compliance Training (Corporate Team)', 'Tech.RCA.9005', 74, 49, 0.68, 0.34, 58, 15,  2,  69000 }
};
Integer MONTHS = 10;
List<Tech_Account_Product_Attributes__c> portRows = new List<Tech_Account_Product_Attributes__c>();
Integer seq = 0;
for (List<Object> p : portfolio) {
  String  pName   = (String)  p[0];
  String  pExtId  = (String)  p[1];
  Decimal hStart  = (Decimal) Decimal.valueOf(String.valueOf(p[2]));
  Decimal hEnd    = (Decimal) Decimal.valueOf(String.valueOf(p[3]));
  Decimal uStart  = (Decimal) Decimal.valueOf(String.valueOf(p[4]));
  Decimal uEnd    = (Decimal) Decimal.valueOf(String.valueOf(p[5]));
  Decimal churn   = (Decimal) Decimal.valueOf(String.valueOf(p[6]));
  Decimal ptb     = (Decimal) Decimal.valueOf(String.valueOf(p[7]));
  Integer renewMo = (Integer) p[8];
  Decimal arr     = (Decimal) Decimal.valueOf(String.valueOf(p[9]));
  Date    renewal = Date.today().addMonths(renewMo);
  for (Integer i = 0; i < MONTHS; i++) {
    // i = 0 is the oldest snapshot, i = MONTHS-1 is the current month
    Decimal t = Decimal.valueOf(i).divide(MONTHS - 1, 4);           // 0.0 -> 1.0
    Decimal health = (hStart + (hEnd - hStart) * t).setScale(0);
    Decimal util   = (uStart + (uEnd - uStart) * t).setScale(4);
    // churn/propensity only reach their headline value at the latest snapshot
    Decimal churnI = (churn * (0.55 + 0.45 * t)).setScale(0);
    Decimal ptbI   = (ptb   * (0.70 + 0.30 * t)).setScale(0);
    seq++;
    portRows.add(new Tech_Account_Product_Attributes__c(
      Name                         = 'Tech.Account.Prod.Id.9' + String.valueOf(1000 + seq),
      TECH_ACCT_PROD_ID__c         = 'Tech.Account.Prod.Id.9' + String.valueOf(1000 + seq),
      Account_Ext_ID__c            = ACCT_EXT_ID,
      PROD_External_ID__c          = pExtId,
      Product_Name__c              = pName,
      Industry__c                  = 'Healthcare',
      Date__c                      = Date.today().addMonths(i - (MONTHS - 1)),
      Renewal_Date__c              = renewal,
      Customer_Health_Score__c     = health,
      Predicted_Customer_Health__c = (health - (100 - health) / 8).setScale(0),
      Utilization__c               = util,
      consumption__c               = (util * 0.94).setScale(2),
      Engagement__c                = (util * 1.02 > 1 ? 1 : util * 1.02).setScale(2),
      Predicted_Churn__c           = churnI,
      Propensity_to_Buy__c         = ptbI,
      Cases__c                     = health < 60 ? 7 : 2,
      Revenue_To_Date__c           = (arr / 12 * (i + 1)).setScale(2),
      Revenue_Type__c              = 'Existing'
    ));
  }
}
insert portRows;

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

System.debug('NAVEX_CX_DONE Account=' + ACCT + ' ExtId=' + ACCT_EXT_ID + ' Contracts=' + new List<Id>{c1.Id,c2.Id,c3.Id} + ' Assets=' + assets.size() + ' PortfolioRows=' + portRows.size() + ' Scorecards=' + sc.size() + ' Tasks=' + tasks.size() + ' ActionPlans=' + aps.size());
