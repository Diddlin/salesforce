# RC Deal Desk Agent — Migration Package

Everything needed to migrate the **RC Deal Desk Agent - New** (`RC_Deal_Desk_Agent_New`)
Agentforce agent from the source org to another org.

Source org: `davids test org` (General Org, `storm.amplitude27@salesforce.com`)

> ✅ **Deployed & active** in `HeadlessOrg` (`storm.5d03b15a3bae76@salesforce.com`) on 2026-06-26 —
> dependencies (with passing Apex tests), agent (Bot + planner v1, **Active**), and the permission set
> all live. See the cross-org `<source>` fix note under **Deploy**.

## What's in this package

| Component | API Name | Type | Notes |
|---|---|---|---|
| Agent | `RC_Deal_Desk_Agent_New` | Bot + BotVersion (`v1`) | The agent definition + context variables (incl. `Quote Id`) |
| Planner | `RC_Deal_Desk_Agent_New` | GenAiPlannerBundle | Self-contained — topics & actions are embedded as `localTopics`/`localActions` |
| Prompt template | `RC_DealDesk_Agent_v2` | GenAiPromptTemplate | Flex template that scores a Quote (used by the scoring flow) |
| Action flow | `Get_Open_Quotes_For_Account` | Flow | Topic *Quote Search* |
| Action flow | `RC_DealDesk_Score_Quote_5` | Flow | Topic *RC Score My Quote* — calls the prompt template + Apex |
| Action flow | `RC_DealDesk_Apply_Discounts_Flow` | Flow | Topic *RC Score My Quote* — applies discounts |
| Apex | `GetOpenQuotesForAccount` | ApexClass | Invocable used by Get Open Quotes flow |
| Apex | `RC_DealDeskDiscountExtractor` | ApexClass | Parses model output into recommendations |
| Apex | `RC_DealDeskDiscountApplier` | ApexClass | Writes discounts back to quote lines |
| Apex | `RC_DealDeskJsonTrimmer` | ApexClass | Helper to trim model JSON |
| Apex tests | `*Test` + `RC_DealDeskTestDataFactory` | ApexClass | Test coverage for all 4 classes (87% / 88% / 83% / 78%) |
| Permission Set | `RC_Deal_Desk_Agent_Access` | PermissionSet | Grants object/field/Apex/flow access — assign to admins/users |
| Custom object | `RC_DealDesk_Recommendation__c` | CustomObject | Stores recommendations (incl. all 9 fields + lookup to Quote) |
| Quote fields | `RC_Quote_DealDeskFullJson__c`, `RC_ARRComments__c`, `RC_MRRComments__c`, `RC_CommissionComments__c`, `RC_OneTimeChargeComments__c` | CustomField | On standard **Quote** |
| QuoteLineItem fields | `RC_PriceTermUnit__c`, `RC_ProductName__c`, `RLM_ProductName__c` | CustomField | On standard **QuoteLineItem** |

### Dependency map
```
Bot: RC_Deal_Desk_Agent_New
└── GenAiPlannerBundle: RC_Deal_Desk_Agent_New
    ├── Topic: Quote_Search
    │   └── Get_Open_Quotes_For_Account (Flow) ──> GetOpenQuotesForAccount (Apex)
    ├── Topic: RC_Score_My_Quote
    │   ├── RC_DealDesk_Score_Quote_5 (Flow)
    │   │   ├── RC_DealDesk_Agent_v2 (Prompt Template)
    │   │   ├── RC_DealDeskDiscountExtractor (Apex)
    │   │   └── RC_DealDeskJsonTrimmer (Apex)
    │   └── RC_DealDesk_Apply_Discounts_Flow (Flow) ──> RC_DealDeskDiscountApplier (Apex)
    └── Planner action: AnswerQuestionsWithKnowledge  [standard EmployeeCopilot pkg — NOT in package]

Data: RC_DealDesk_Recommendation__c  +  custom fields on Quote / QuoteLineItem
```

## Target-org prerequisites (must exist BEFORE deploy)

1. **Agentforce / Einstein Generative AI** enabled (Einstein Copilot / Agentforce turned on).
2. **Employee Agent (EmployeeCopilot) features** — the planner uses the standard
   `EmployeeCopilot__AnswerQuestionsWithKnowledge` action. The two core topics work without it,
   but the knowledge planner action will be unresolved if EmployeeCopilot isn't available.
3. **Quotes enabled** (Setup → Quotes) — `Quote` / `QuoteLineItem` and the `RC_Quote__c` lookup require it.
4. A **prompt-template-capable** org (Prompt Builder) for `RC_DealDesk_Agent_v2`.

> Not included (intentionally): standard/managed components (`EmployeeCopilot__*`, CPQ `SBQQ`/`sbaa`),
> profiles/permission sets, and end-user UI assignments. Add a Permission Set separately if you want
> to grant object/field/Apex/flow access in the target org.

## Deploy

> This folder ships its own `sfdx-project.json` (registers `src/` as the package dir) so
> the manifests below resolve when you `cd` into it. Run all commands from
> `migration/RC_Deal_Desk_Agent/`.

A single combined deploy is **atomic**, and the agent (Bot + planner) depends on the flows/Apex/fields
existing first. Deploy in **two steps**:

**Step 1 — dependencies (with tests):**
```bash
cd migration/RC_Deal_Desk_Agent
sf project deploy start --manifest manifest/package-deps.xml \
  --test-level RunSpecifiedTests \
  --tests GetOpenQuotesForAccountTest RC_DealDeskDiscountApplierTest RC_DealDeskDiscountExtractorTest RC_DealDeskJsonTrimmerTest \
  --target-org <TARGET_ORG_ALIAS>
```

**Step 2 — the agent (Bot + planner):**
```bash
sf project deploy start --manifest manifest/package-agent.xml \
  --target-org <TARGET_ORG_ALIAS>
```

Manifests: `package-deps.xml` (everything except the agent), `package-agent.xml` (Bot + planner only),
and `package.xml` (the full set, for reference).

### ⚠️ Cross-org fix already applied: planner `<source>` elements removed
When this planner is retrieved from its origin org, the custom inline topic/actions carry
`<source>` pointers (e.g. `<source>Quote_Search</source>`) that reference **GenAiPlugin/GenAiFunction
definitions that only exist in the origin org**. Deploying as-is fails with:

> `Generative AI Plugin Definition ID: bad value for restricted picklist field: Quote_Search`
> and `Required fields are missing: [PlannerId]` on the BotVersion (downstream symptom).

Fix: delete those `<source>...</source>` lines from the custom `localTopics`/`localActions` in
`src/genAiPlannerBundles/RC_Deal_Desk_Agent_New/RC_Deal_Desk_Agent_New.genAiPlannerBundle`
(the inline definitions are self-contained; `invocationTarget` does the wiring). **Keep** the managed
`EmployeeCopilot__AnswerQuestionsWithKnowledge` source. This has already been done in this package.

### Apex tests (included)
Test classes are bundled and validated against the source org — all pass with coverage above 75%:

| Class | Coverage |
|---|---|
| `GetOpenQuotesForAccount` | 87% |
| `RC_DealDeskJsonTrimmer` | 88% |
| `RC_DealDeskDiscountExtractor` | 83% |
| `RC_DealDeskDiscountApplier` | 78% |

This makes the package **production-deployable**. For a production target add
`--test-level RunLocalTests` (or `RunSpecifiedTests` with the four `*Test` classes) to the deploy command.

### Known gotcha: "Can't edit an active bot version"
If you deploy to an org where `RC_Deal_Desk_Agent_New` **already exists and is active**, the Bot/BotVersion
update is rejected. Deactivate first (`sf agent deactivate --api-name RC_Deal_Desk_Agent_New`) then redeploy.
This does **not** happen on a fresh target org (the bot is created new).

## Post-deploy steps
1. **Assign the permission set** to the admins/users who will use the agent:
   ```bash
   sf org assign permset --name RC_Deal_Desk_Agent_Access --target-org <TARGET_ORG_ALIAS>
   ```
   (System Administrators still need this for field-level security on the new fields.)
2. **Activate the agent**: `sf agent activate --api-name RC_Deal_Desk_Agent_New --target-org <TARGET_ORG_ALIAS> --json`
   (or activate in Agent Builder).
3. Confirm the prompt template `RC_DealDesk_Agent_v2` is **Active** in Prompt Builder.
4. Smoke test: open a Quote and try "Score my quote" and "Find open quotes for this account".
```
