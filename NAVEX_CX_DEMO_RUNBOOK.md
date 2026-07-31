# NAVEX Customer Experience Demo — Runbook

Native-first Customer Success demo built on the **storm** org (`HeadlessOrg`, `storm-5d03b15a3bae76.my.salesforce.com`). Hero account: **Meridian Health** (`001Hs00005wLdgKIAS`).

The demo mirrors the two things NAVEX values in Gainsight (CTAs/playbooks + a clean CSM timeline) and solves their pain points (untrusted data, product-family complexity, scattered reporting) by grounding everything in **standard Salesforce + the org's existing Customer Success SDO** — with only a handful of custom fields added.

---

## 1. What was already available (verified in-org — reused, not rebuilt)

| Capability | Native / existing feature reused |
|---|---|
| **CTAs + playbooks with task tracking** | Standard **Action Plans** (`ActionPlanTemplate` / `ActionPlan` / `ActionPlanItem` + `Task`). Org already had CS playbooks with 5–7 tasks each: `RISK: Adoption - Configuration Review (CS)`, `LIFECYCLE: Upcoming QBR`, `EXPANSION: High Product Usage (CS)`. Creating an ActionPlan from a template **auto-generates the checkable Tasks and progress** — no custom task objects needed. The org's `ActionPlan.Tech_CTA_Type__c` (Expansion/Lifecycle/Risk) already models the Gainsight "CTA type." |
| **Clean CSM activity timeline** | Standard **Activity Timeline** (`runtime_sales_activities:activityPanel`) already on the Account page, using standard `Task.Type` values (Meeting/Call/Email/Prep). |
| **Company → Contract → Product relationship** | Standard **Account → Contract** (with CPQ renewal fields already present) and standard **Asset → Product2** (with `Product2.Family` = super-product-family). |
| **Single pane of glass (health + KPIs)** | Existing **`Tech_Customer_Success_Console`** app + **`Tech_Account_Success`** Lightning record page, which already renders `force:highlightsPanel`, the Action Plans list card, the activity panel, CRM Analytics dashboards, and 21 related lists (Scorecard, Contract, Asset, Product, Renewal). Company-level health uses the existing **`Tech_Success_Scorecard__c`** (measure/score model); product-level analytics also exist in **`Tech_Account_Product_Attributes__c`**. |

**Net:** the demo surface (console + account page) and the CTA/playbook engine already existed. No new app, page, flow, or task object was created.

---

## 2. Minimal custom additions (the only new metadata)

Native Salesforce has **no health-score, NPS, renewal-risk, or Asset→Contract** concepts, and NAVEX specifically needs the **contract layer between account and product**. These gaps required the smallest possible custom fields:

| Object | Field | Type | Why native wasn't enough |
|---|---|---|---|
| Account | `Health_Score__c` | Number(3) | No standard company health score for the highlights panel. |
| Account | `NPS__c` | Number(2) | No standard "latest NPS/MPS response" field; drives the NPS→CTA story. |
| Account | `NPS_Segment__c` | Formula(Text) | Derives Detractor/Passive/Promoter (0-6 / 7-8 / 9-10) to select the playbook. |
| Contract | `Contract_Health__c` | Number(3) | No standard contract-level health for per-contract renewal assessment. |
| Contract | `Renewal_Risk__c` | Picklist (Low/Med/High) | No standard renewal-risk classification. |
| **Asset** | **`Contract__c`** | **Lookup(Contract)** | **Key gap: Salesforce has no Asset→Contract relationship. This one lookup is the junction that lets products roll up under a specific contract — enabling multi-product contracts AND the same product on multiple contracts.** |
| Asset | `Product_Health__c` | Number(3) | Product-level health granularity ("Hotline safe, PolicyTech at risk"). |
| Asset | `Renewal_Risk__c` | Picklist (Low/Med/High) | Product-level renewal risk. |

Also:
- **`NAVEX_CX_Demo`** permission set — grants field-level security to the 8 fields above (assigned to the running user).
- **`Account.Tech_Account_Layout`** compact layout — added Health/NPS so they show in the highlights panel (existing layout, 3 fields appended).

All source lives under `force-app/main/default/` and is deployed to storm.

---

## 3. The Meridian Health data story (loaded on top of native features)

Loaded by `scripts/apex/navex_cx_demo_data.apex` (idempotent — safe to re-run).

- **Account:** Health `64`, NPS `6` → **Detractor** (the survey that triggered the lifecycle CTA).
- **Company scorecard** (`Tech_Success_Scorecard__c`): Adoption (Usage 82 / MAU 63 / NPS 40), Renewal (Likelihood 58), Service (CSAT 71 / Age of Cases 45).
- **3 Contracts → 5 Products (Assets)** — demonstrates the exact relationship NAVEX asked for:
  - **Contract 00000103 – "NAVEX One · Hotline & Policy Suite"** (Health 72, Renewal Risk Medium) → *multi-product contract*:
    - EthicsPoint Hotline — health **88**, risk Low
    - Case Management — health **84**, risk Low
    - PolicyTech Policy Management — health **47**, risk **High** ← "will renew this time, at long-term risk"
  - **Contract 00000104 – "Compliance Training · Clinical Team"** (Health 83, Low) → Training health **85**
  - **Contract 00000105 – "Compliance Training · Corporate Team"** (Health 51, **High**) → Training health **49**
  - → *Same product (Compliance Training) on two contracts with opposite sentiment* — Josh's exact scenario.
- **CTAs (Action Plans):**
  - `LIFECYCLE: NPS Detractor Follow-up – Meridian` — **In Progress, 3 of 5 tasks complete** (playbook + progress).
  - `RISK: PolicyTech Adoption Review – Meridian` — Not Started.
- **Clean CSM timeline (Tasks):** EBR meeting, PolicyTech check-in call, NPS follow-up email (all completed) + 2 open follow-ups off the EBR ("Share PolicyTech roadmap", "Schedule Corporate Training QBR") — the "meeting → to-do" pattern.

---

## 4. Demo click-path (maps to the 4 capabilities)

Open the **Tech Customer Success Console** app → **Meridian Health**.
Direct link: `https://storm-5d03b15a3bae76.my.salesforce.com/lightning/r/Account/001Hs00005wLdgKIAS/view`

1. **Single pane of glass** — Highlights panel shows Health Score 64 + NPS Detractor; Success Scorecard card shows the health breakdown by measure.
2. **Relationship: company → contract → product** — open the **Contracts** related list → **00000103** → its **Products** related list (Hotline healthy, PolicyTech High risk). Then contrast **00000104 vs 00000105** (same Training product, opposite health).
3. **CTAs + playbooks** — the **Action Plans** card: open *NPS Detractor Follow-up* → 5 checkable tasks, 60% progress. Narrate: "the NPS-6 detractor result triggered this lifecycle CTA."
4. **Clean CSM timeline** — the **Activity** panel: CSM-only engagements (EBR, call, email) + the two open follow-ups generated off the EBR meeting.

Talking point: *"Every one of these is native Salesforce on data you already own — no Gainsight sync, nothing to reconcile."*

---

## 5. Reset / reload (< 1 minute)

The data script is idempotent (it deletes Meridian's demo children, then reloads):

```bash
sf apex run --file scripts/apex/navex_cx_demo_data.apex --target-org storm
```

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
  --target-org <alias>
sf org assign permset --name NAVEX_CX_Demo --target-org <alias>
```

---

## 6. Notes / known considerations

- **Contracts are in `Draft` status** (only `AccountId` is required to insert). Activating requires the org's contract approval settings; not needed for the demo visuals.
- **Action Plan tasks generate asynchronously** after the ActionPlan is inserted — allow a few seconds before task counts/progress settle.
- **NPS-segment playbooks:** NAVEX described detractor/passive/promoter variants. Rather than author fragile `ActionPlanTemplate` metadata, the demo reuses the org's existing Lifecycle/Risk templates and narrates the NPS trigger. Additional NPS-segment templates can be created natively in **Setup → Action Plan Templates** (no code).
- **Product super-families** use the standard, unrestricted `Product2.Family` field (e.g., "Hotline & Incident Management", "Policy & Procedure Management", "Compliance Training").
