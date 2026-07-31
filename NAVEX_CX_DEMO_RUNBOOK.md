# NAVEX Customer Experience Demo — Runbook

Native-first Customer Success demo built on the **storm** org (`HeadlessOrg`, `storm-5d03b15a3bae76.my.salesforce.com`). Hero account: **Meridian Health** (`001Hs00005wLdgKIAS`).

The demo mirrors the two things NAVEX values in Gainsight (CTAs/playbooks + a clean CSM timeline) and solves their pain points (untrusted data, product-family complexity, scattered reporting) by grounding everything in **standard Salesforce + the org's existing Customer Success SDO** — with only a handful of custom fields added.

---

## 1. What was already available (verified in-org — reused, not rebuilt)

| Capability                                    | Native / existing feature reused                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **CTAs + playbooks with task tracking**       | Standard **Action Plans** (`ActionPlanTemplate` / `ActionPlan` / `ActionPlanItem` + `Task`). Org already had CS playbooks with 5–7 tasks each: `RISK: Adoption - Configuration Review (CS)`, `LIFECYCLE: Upcoming QBR`, `EXPANSION: High Product Usage (CS)`. Creating an ActionPlan from a template **auto-generates the checkable Tasks and progress** — no custom task objects needed. The org's `ActionPlan.Tech_CTA_Type__c` (Expansion/Lifecycle/Risk) already models the Gainsight "CTA type." |
| **Clean CSM activity timeline**               | Standard **Activity Timeline** (`runtime_sales_activities:activityPanel`) already on the Account page, using standard `Task.Type` values (Meeting/Call/Email/Prep).                                                                                                                                                                                                                                                                                                                                   |
| **Company → Contract → Product relationship** | Standard **Account → Contract** (with CPQ renewal fields already present) and standard **Asset → Product2** (with `Product2.Family` = super-product-family).                                                                                                                                                                                                                                                                                                                                          |
| **Single pane of glass (health + KPIs)**      | Existing **`Tech_Customer_Success_Console`** app + **`Tech_Account_Success`** Lightning record page, which already renders `force:highlightsPanel`, the Action Plans list card, the activity panel, CRM Analytics dashboards, and 21 related lists (Scorecard, Contract, Asset, Product, Renewal). Company-level health uses the existing **`Tech_Success_Scorecard__c`** (measure/score model); product-level analytics also exist in **`Tech_Account_Product_Attributes__c`**.                      |

**Net:** the demo surface (console + account page) and the CTA/playbook engine already existed. No new app, page, flow, or task object was created.

---

## 2. Minimal custom additions (the only new metadata)

Native Salesforce has **no health-score, NPS, renewal-risk, or Asset→Contract** concepts, and NAVEX specifically needs the **contract layer between account and product**. These gaps required the smallest possible custom fields:

| Object    | Field                | Type                    | Why native wasn't enough                                                                                                                                                                                                        |
| --------- | -------------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Account   | `Health_Score__c`    | Number(3)               | No standard company health score for the highlights panel.                                                                                                                                                                      |
| Account   | `NPS__c`             | Number(2)               | No standard "latest NPS/MPS response" field; drives the NPS→CTA story.                                                                                                                                                          |
| Account   | `NPS_Segment__c`     | Formula(Text)           | Derives Detractor/Passive/Promoter (0-6 / 7-8 / 9-10) to select the playbook.                                                                                                                                                   |
| Contract  | `Contract_Health__c` | Number(3)               | No standard contract-level health for per-contract renewal assessment.                                                                                                                                                          |
| Contract  | `Renewal_Risk__c`    | Picklist (Low/Med/High) | No standard renewal-risk classification.                                                                                                                                                                                        |
| **Asset** | **`Contract__c`**    | **Lookup(Contract)**    | **Key gap: Salesforce has no Asset→Contract relationship. This one lookup is the junction that lets products roll up under a specific contract — enabling multi-product contracts AND the same product on multiple contracts.** |
| Asset     | `Product_Health__c`  | Number(3)               | Product-level health granularity ("Hotline safe, PolicyTech at risk").                                                                                                                                                          |
| Asset     | `Renewal_Risk__c`    | Picklist (Low/Med/High) | Product-level renewal risk.                                                                                                                                                                                                     |

Also:

- **`NAVEX_CX_Demo`** permission set — grants field-level security to the 8 fields above (assigned to the running user).
- **`Account.Tech_Account_Layout`** compact layout — added Health/NPS so they show in the highlights panel (existing layout, 3 fields appended).
- **`Tech_Account_Success` FlexiPage** — two `lst:dynamicRelatedList` components appended to the **Renew** tab so the custom Asset/Contract fields are actually visible (the standard `force:relatedListSingleContainer` on the Service tab takes its columns from the page layout and therefore cannot show them):
  - **Product Health by Contract** (Assets) — Asset Name, Product Health, Renewal Risk, Contract, Status
  - **Contract Health** (Contracts) — Contract Number, Contract Health, Renewal Risk, Contract End Date, Status

  This is the only change made to the SDO page. Nothing existing was moved, removed, or reformatted — the page was retrieved as-is into `force-app/main/default/flexipages/Tech_Account_Success.flexipage-meta.xml` and the two components were inserted as new `itemInstances` in the Renew facet (128 added lines, zero removed). To revert, delete both `lst_dynamicRelatedList2` / `lst_dynamicRelatedList3` `itemInstances` blocks and redeploy, or remove the two components in Lightning App Builder.

All source lives under `force-app/main/default/` and is deployed to storm.

---

## 3. The Meridian Health data story (loaded on top of native features)

Loaded by `scripts/apex/navex_cx_demo_data.apex` (idempotent — safe to re-run).

- **Account:** Health `64`, NPS `6` → **Detractor** (the survey that triggered the lifecycle CTA). `External_ID__c` = **`Tech.955`** — the SDO's account join key (existing org values are `Account.001`–`Account.030` plus `Tech.953` = CTW Partners and `Tech.954` = Verde).
- **Product analytics** (`Tech_Account_Product_Attributes__c`): 50 rows = 5 products × 10 monthly snapshots, joined to the account by `Account_Ext_ID__c` = `Tech.955`. PolicyTech trends 72 → 47 and Corporate Training 74 → 49 over the series; Hotline/Case Management/Clinical Training stay flat and healthy. Utilization, predicted churn, propensity-to-buy and renewal dates move with health. All dates are relative to load time.
- **Company scorecard** (`Tech_Success_Scorecard__c`): Adoption (Usage 82 / MAU 63 / NPS 40), Renewal (Likelihood 58), Service (CSAT 71 / Age of Cases 45).
- **3 Contracts → 5 Products (Assets)** — demonstrates the exact relationship NAVEX asked for. _Contract numbers are auto-numbered and increment on every reload — read them off the page rather than quoting the numbers below._
  - **Contract 1 – "NAVEX One · Hotline & Policy Suite"** (Health 72, Renewal Risk Medium) → _multi-product contract_:
    - EthicsPoint Hotline — health **88**, risk Low
    - Case Management — health **84**, risk Low
    - PolicyTech Policy Management — health **47**, risk **High** ← "will renew this time, at long-term risk"
  - **Contract 2 – "Compliance Training · Clinical Team"** (Health 83, Low) → Training health **85**
  - **Contract 3 – "Compliance Training · Corporate Team"** (Health 51, **High**) → Training health **49**
  - → _Same product (Compliance Training) on two contracts with opposite sentiment_ — Josh's exact scenario.
- **CTAs (Action Plans):**
  - `LIFECYCLE: NPS Detractor Follow-up – Meridian` — **In Progress, 3 of 5 tasks complete** (playbook + progress).
  - `RISK: PolicyTech Adoption Review – Meridian` — Not Started.
- **Clean CSM timeline (Tasks):** EBR meeting, PolicyTech check-in call, NPS follow-up email (all completed) + 2 open follow-ups off the EBR ("Share PolicyTech roadmap", "Schedule Corporate Training QBR") — the "meeting → to-do" pattern.

---

## 4. Demo click-path (maps to the 4 capabilities)

**App Launcher → "Customer Success"** (API name `Tech_Customer_Success_Console`, console navigation) → **Accounts** → **Meridian Health**.
Direct link: `https://storm-5d03b15a3bae76.my.salesforce.com/lightning/r/Account/001Hs00005wLdgKIAS/view`

### Page map (`Tech_Account_Success`)

Everything below is on one record page. Top-level tabs run across the centre column; four of them have their own nested sub-tabs.

| Top-level tab    | Sub-tabs                                             | What's in it                                                                                  |
| ---------------- | ---------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| **Details**      | —                                                    | Standard field sections + Account Team Members                                                |
| **Intelligence** | **Health**, Whitespace                               | Two CRM Analytics dashboards (see the warning below)                                          |
| **Success**      | Account Plans, **CTAs**, **Scorecards**, Red Account | Action Plans list card, `Tech_Success_Scorecard__c`, red-account records                      |
| **Renew**        | —                                                    | **Contract Health**, **Product Health by Contract**, Renewals, Quotes, Orders, Territories    |
| **Contacts**     | —                                                    | Account Contact Relationships, Users                                                          |
| **Service**      | —                                                    | Cases, **Assets**, **Contracts** (standard related lists — layout columns only), Entitlements |
| **Sales**        | **Opportunities**, Commerce, **Subscriptions**       | Pipeline, commerce, invoices/subscriptions                                                    |

Outside the tabs: the **highlights panel** and the headline analytics card sit above them; the **right sidebar** carries NBA / Engagement / **Activity**; the **left sidebar** carries the Customer 360 profile.

### The four capabilities

1. **CTAs + playbooks** — **Success** tab → **CTAs** sub-tab. Open _LIFECYCLE: NPS Detractor Follow-up – Meridian_ → 5 checkable tasks, 3 complete. Narrate: "the NPS-6 detractor result triggered this lifecycle CTA." _RISK: PolicyTech Adoption Review_ sits underneath, Not Started.
2. **Clean CSM timeline** — **right sidebar → Activity** tab. CSM-only engagements (EBR meeting, PolicyTech call, NPS email — all completed) plus the two open follow-ups generated off the EBR.
3. **Company → contract → product** — **Renew** tab. **Contract Health** lists all three contracts with health and renewal risk; **Product Health by Contract** lists all five products with Product Health, Renewal Risk and the parent Contract in one grid. Point at PolicyTech (47 / High) sitting on the _same_ contract as Hotline (88 / Low), then at Compliance Training appearing twice with opposite health on two different contracts. Drill into a contract to see its own products if you want the hierarchy click-through.
4. **Single pane of glass (health + KPIs)** — the **highlights panel** shows Health Score 64 and NPS Segment Detractor; **Success → Scorecards** breaks company health down by measure (Adoption / Renewal / Service).

Talking point: _"Every one of these is native Salesforce on data you already own — no Gainsight sync, nothing to reconcile."_

### ⚠️ Do not demo the headline analytics card as "our data"

The large card directly under the highlights panel is the CRM Analytics dashboard **`NEW_Tech_Success_Account_Summary`** ("Health Score", "Product Portfolio", "Total Cases", "Pipeline", "Revenue Trend"). Same for **Intelligence → Health / Whitespace**.

These are **not** driven by `Account.Health_Score__c` or by any Salesforce object. They read pre-built CRM Analytics datasets (`CS_Account_Summary_ZTQ`, `Tech_Health_Data_MAY`, `Tech_Expand_Data_CSO`) that ship with the SDO, and they are filtered by `ExternalId == $External_ID__c`. `CS_Account_Summary_ZTQ` contains data for exactly one account — **Verde** (`Tech.954`) — so for Meridian Health the **Product Portfolio treemap shows "No results found"**, and it cannot be fixed with SObject data. See §6 for the details and the options.

**Demo accordingly:** scroll past the analytics card, or collapse the browser window so it isn't in frame. Use the **highlights panel + Success → Scorecards + Renew** for health, which _are_ driven by the Meridian data this demo loads.

---

## 5. Reset / reload (< 1 minute)

The data script is idempotent (it deletes Meridian's demo children, then reloads):

```bash
sf apex run --file scripts/apex/navex_cx_demo_data.apex --target-org HeadlessOrg
```

It resets and reloads Meridian's Assets, Contracts, Scorecards, Action Plans, Tasks and `Tech_Account_Product_Attributes__c` rows, and re-stamps `Account.External_ID__c = Tech.955`. Contract numbers are auto-numbered, so they increment on every run.

Then re-set CTA progress (optional, marks 3 of the QBR tasks complete once Action-Plan tasks finish generating — wait ~20s after the load):

```bash
# see scripts/apex/ — mark first 3 LIFECYCLE action-plan tasks Completed
```

Re-deploy metadata if moving to a new org:

```bash
sf project deploy start \
  --source-dir force-app/main/default/objects/Account \
  --source-dir force-app/main/default/objects/Contract \
  --source-dir force-app/main/default/objects/Asset \
  --source-dir force-app/main/default/permissionsets/NAVEX_CX_Demo.permissionset-meta.xml \
  --source-dir force-app/main/default/flexipages/Tech_Account_Success.flexipage-meta.xml \
  --target-org <alias>
sf org assign permset --name NAVEX_CX_Demo --target-org <alias>
```

> The FlexiPage is a full copy of the SDO's very large `Tech_Account_Success` page. Only deploy it to an org whose copy of that page is unmodified, otherwise it will overwrite local edits. Safer alternative in an unfamiliar org: add the two dynamic related lists by hand in Lightning App Builder.

---

## 6. Notes / known considerations

### The "Product Portfolio" card cannot be populated from Salesforce data

Worth understanding before anyone else tries to fix it.

- The card is a **treemap in the CRM Analytics dashboard `NEW_Tech_Success_Account_Summary`** (step `Product_Portfolio_2`): `group by Product`, `sum(Revenue)`, over the dataset **`CS_Account_Summary_ZTQ`**.
- The FlexiPage passes it a filter of `CS_Account_Summary_ZTQ.ExternalId in [$External_ID__c]`. So the card only draws for accounts whose `External_ID__c` exists in that dataset.
- That dataset holds **100 rows total**: 27 for Verde (`ExternalId = Tech.954`) and 73 with a null `ExternalId` (Accusage, Inc.). It is a **static CSV snapshot** (connector `CSV`, `dataRefreshDate` 2024-09-23) with **no recipe or dataflow behind it** — nothing rebuilds it from `Tech_Account_Product_Attributes__c`. Creating SObject rows therefore has no effect on the card.
- **Appending Meridian rows via the Analytics External Data API is not possible.** The API rejects numeric fields without a `defaultValue`, but the existing dataset's numeric fields (`Revenue`, `Pipeline`, `Value`, `Cases`, `Case_Age`) were created with an _empty_ default, so any `Append` fails schema validation either way:
  - `defaultValue` omitted/null → `Numeric field [Revenue] ... must have a default value.`
  - `defaultValue: "0"` → `The schema attributes [precision: 18, scale: 1, defaultValue: 0] ... don't match ... [precision: 18, scale: 1, defaultValue: ]`

**Options, if the card must render:**

1. **Leave it** and demo the native Renew tab instead (what this runbook recommends). The native grids carry the same story with data the customer can actually trust — which is the demo's whole argument.
2. **Overwrite the dataset** with the existing 100 rows plus Meridian rows. This works, but it rewrites Verde's and Accusage's rows and touches shared SDO content, so it was deliberately not done here. Roll back via Analytics Studio → dataset → version history if you try it.
3. **Build a recipe** in Analytics Studio over `Tech_Account_Product_Attributes__c` (the 50 Meridian rows are already there, with the right `Account_Ext_ID__c`) into a new dataset, and repoint the dashboard step at it. Cleanest long-term, but it edits a shared SDO dashboard.

### Other notes

- **Contracts are in `Draft` status** (only `AccountId` is required to insert). Activating requires the org's contract approval settings; not needed for the demo visuals.
- **Action Plan tasks generate asynchronously** after the ActionPlan is inserted — allow a few seconds before task counts/progress settle.
- **NPS-segment playbooks:** NAVEX described detractor/passive/promoter variants. Rather than author fragile `ActionPlanTemplate` metadata, the demo reuses the org's existing Lifecycle/Risk templates and narrates the NPS trigger. Additional NPS-segment templates can be created natively in **Setup → Action Plan Templates** (no code).
- **Product super-families** use the standard, unrestricted `Product2.Family` field (e.g., "Hotline & Incident Management", "Policy & Procedure Management", "Compliance Training").
