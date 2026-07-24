# Broiler Performance Monitoring and Diagnostic Auditing Design

Date: 2026-07-24

Status: Approved design

Branch: `002-add-flock-monitoring`

## 1. Product Direction

ChickMark will evolve from a primarily hatchery-audit application into an
offline-first poultry performance monitoring and diagnostic auditing platform.
The system will combine routine production data with periodic physical audits:

1. Farms report routine performance data.
2. A ChickMark user enters or imports the reported data.
3. ChickMark validates the data, calculates KPIs, and compares results with
   relevant targets.
4. Persistent deviations become performance concerns.
5. Concerns feed a focused farm-visit investigation list.
6. Visit measurements and observations support probable-cause assessments.
7. Corrective actions are linked to measurable KPIs and time windows.
8. Later daily records show whether each action was effective.

ChickMark is not intended to become a full farm-management ERP. Its product
definition is:

> ChickMark is an offline-first poultry performance monitoring and auditing
> platform for hatcheries, broiler farms, broiler-breeder farms, and layer
> farms. It receives routine production data, compares performance with breed
> objectives and operational limits, detects deviations and trends, guides
> physical investigations, records probable causes and corrective actions, and
> evaluates whether those actions improve performance.

This design covers the first complete vertical slice: Broiler manual daily
entry through monitoring, investigation, and corrective-action evaluation.

## 2. Approved Scope and Sequencing

### 2.1 First vertical slice

The first Broiler slice includes:

- Multi-sector customer classification.
- Farm, house, flock-batch, and house-placement hierarchy.
- Versioned official Broiler performance-objective profiles.
- Manual multi-house daily entry.
- Previous-day context during entry.
- Source, actor, verification, and correction provenance.
- Append-only record revisions.
- Core population, feed, water, weight, mortality, and FCR calculations.
- Data-quality validation.
- Configurable performance-alert rules.
- Flock, farm, and house status and trend views.
- Persistent concerns and visit-investigation suggestions.
- Farm-visit evidence, probable-cause assessments, corrective actions, and KPI
  evaluation windows.
- Offline-first persistence and mirrored Supabase sync.

### 2.2 Deferred slices

The following are intentionally deferred until the manual Broiler workflow is
validated:

- CSV and Excel column mapping and import.
- Document-, image-, PDF-, or message-assisted AI extraction.
- Broiler projections that require a separately validated forecasting method,
  including projected final weight and projected final FCR.
- Breeder daily performance entry and breeder-specific KPIs.
- Layer daily performance entry and layer-specific KPIs.
- Automatic diagnosis or unreviewed AI recommendations.
- A full farm-management ERP feature set, including inventory, procurement,
  payroll, accounting, or production scheduling.

Breed objective profiles, customer/farm hierarchy, provenance, rule evaluation,
and the concern/action model are deliberately shared foundations so later
Breeder and Layer slices do not require a second architecture.

## 3. Customer and Operational Hierarchy

### 3.1 Multiple sectors per customer

A customer can participate in any combination of:

- `breeder`
- `broiler`
- `layer`

A farm has exactly one production type and its houses and flocks inherit that
type.

Hatcheries remain associated with Breeder customers. Within the Breeder sector,
breeder farms and hatcheries are sibling operational structures:

```text
Customer
├── Breeder
│   ├── Breeder farms
│   │   └── Houses and breeder flocks
│   └── Hatcheries
├── Broiler
│   └── Broiler farms
│       └── Houses and broiler flock placements
└── Layer
    └── Layer farms
        └── Houses and layer flocks
```

### 3.2 Flock batches and placements

A commercial flock batch may span several houses. The batch and its house
placements are separate concepts:

```text
Flock batch B-2407
├── House 1 placement: 20,000 birds
├── House 2 placement: 20,000 birds
└── House 3 placement: 20,000 birds
```

Daily records belong to one house placement and one local calendar date.
ChickMark aggregates all placements to flock-batch and farm totals.

Rules:

- A house can have only one active placement at a time.
- A placement belongs to one flock batch and one house.
- Broiler placements within one flock batch use the batch placement date for
  age-day calculations.
- A flock's placed population is the sum of its placements.
- Current population is calculated from placement counts and subsequent
  mortality, culls, and explicit population adjustments.
- Historical placements remain available after depletion or sale.

## 4. Compatibility With the Existing Codebase

The current codebase uses:

- `customers`
- customer-level `flocks`
- customer-level `hatcheries`
- hatchery-specific `audit_sessions`
- hatchery-specific panel data
- hatchery-scoped `dashboard_actions`
- local SQLite mirrored to Supabase

The upgrade is additive:

- Existing hatchery tables, sessions, panel rows, and dashboards remain valid.
- Existing `flocks` remain the canonical flock-batch table and gain nullable
  sector/farm/target fields.
- Existing flock rows remain valid legacy records. The migration assigns the
  Breeder sector only when their current hatchery context makes that
  classification safe; otherwise their sector remains null until user review.
- A legacy flock does not require a farm or house.
- New farm visits use farm-specific visit tables; they do not overload the
  hatchery-specific `audit_sessions` contract.
- New farm corrective actions do not overload `dashboard_actions`, whose
  current schema requires a hatchery.
- Existing sync and workspace ownership rules remain in force.

## 5. Persistence Design

All new tenant-owned rows use UUID identifiers, timestamps, the current
offline-sync metadata, and migration-safe foreign keys.

### 5.1 Organization and placement tables

#### `customer_sectors`

- `id`
- `customerId`
- `sectorKey`: `breeder`, `broiler`, or `layer`
- `isActive`
- audit and sync timestamps

Unique key: `customerId + sectorKey`.

#### `farms`

- `id`
- `customerId`
- `sectorKey`
- `name`
- `location`
- `notes`
- active/inactive state
- audit and sync timestamps

#### `houses`

- `id`
- `farmId`
- `name`
- optional house code
- optional capacity
- notes
- active/inactive state
- audit and sync timestamps

Unique active house name/code within a farm.

#### Existing `flocks` additions

- nullable `farmId`
- nullable `sectorKey`
- `sexProfile`: `as_hatched`, `male`, or `female`
- nullable `targetProfileId`
- optional production-phase metadata
- existing `entryDate` remains the placement/age origin

For new Broiler flocks, sector, farm, sex profile, breed, placement date, and
target profile are required. `as_hatched` is the default sex profile.

#### `flock_placements`

- `id`
- `flockId`
- `houseId`
- `placedBirds`
- `placedAt`
- optional `endedAt`
- placement status
- notes
- audit and sync timestamps

A partial unique index prevents two active placements in one house.

### 5.2 Logical daily records and revisions

#### `broiler_daily_records`

This is the stable logical identity of one house/day record:

- `id`
- `placementId`
- `recordDate`
- `currentRevisionId`
- current verification status
- created/updated timestamps
- sync metadata

Unique key: `placementId + recordDate`.

`pending_entry` is normally a generated expectation for a missing house/day,
not fabricated production data. A saved draft may use the status while still
containing incomplete user input.

#### `broiler_daily_record_revisions`

Each save that changes source facts creates a new immutable revision:

- `id`
- `recordId`
- `revisionNumber`
- verification status
- data source type and description
- `reportedBy`
- `enteredBy`
- `enteredAt`
- optional `reviewedBy` / `reviewedAt`
- optional `verifiedBy` / `verifiedAt`
- correction reason
- typed production fields
- creation timestamp
- sync metadata

Supported verification states:

- `pending_entry`
- `entered`
- `reviewed`
- `verified`
- `requires_clarification`
- `corrected`

Corrections never overwrite a prior revision. Changing the current revision is
an auditable pointer update. Concurrent offline corrections preserve both
candidates and create a visible conflict for review.

#### `daily_record_sources`

- `id`
- `revisionId`
- source kind: file, image, spreadsheet, message, or other
- local path
- optional remote storage path
- original filename
- checksum when available
- upload state and error
- timestamps

A record remains locally saved if an attachment upload fails.

#### `broiler_daily_events`

Events are tied to a revision so its complete source snapshot can be
reconstructed:

- `id`
- `revisionId`
- event type
- event time or all-day flag
- optional started/stopped state
- description
- optional treatment, vaccination, feed-phase, or equipment metadata

Initial event types include clinical signs, treatment, vaccination, feed
change, feed interruption, water medication, water interruption, power
failure, equipment failure, ventilation/heat-stress incident, veterinary
observation, and other.

### 5.3 Target catalogue

#### `broiler_target_profiles`

- `id`
- brand
- breed/strain
- optional feathering variant
- sex profile
- publication/version label
- publication date when known
- source title
- source URL
- optional locally retained source file
- region/language metadata
- active date range
- active/inactive state
- sync metadata

#### `broiler_target_rows`

- `id`
- `profileId`
- `ageDay`
- target body weight in grams
- target daily gain in grams
- target average daily gain in grams
- target daily feed intake in grams per living bird
- target cumulative feed intake in grams per living bird
- target FCR
- optional target water in milliliters per living bird
- metric-method notes

Unique key: `profileId + ageDay`.

Null means the source does not publish that value. ChickMark must not
interpolate or substitute a different breed/sex value silently.

### 5.4 Rules, concerns, visits, and actions

#### `performance_alert_rules`

- metric key
- scope level: global or customer override
- optional customer ID
- watch/critical thresholds
- direction: above, below, outside range, or rate of change
- persistence window
- minimum valid observations
- source and rationale
- enabled state and timestamps

Official breed rows and operational alert rules are different:

- Breed rows provide age-specific genetic performance objectives.
- Operational rules determine when credible deviations become concerns.
- ChickMark-authored defaults are labeled as operational defaults, not as
  vendor-published objectives.

#### `performance_concerns`

- scope: customer, farm, flock, placement, and/or house
- metric key
- severity
- first and last observation
- evidence-window boundaries
- baseline and target values
- status: open, monitoring, assigned-to-visit, resolved, or dismissed
- resolution/dismissal metadata

A concern is persistent state. It is not a transient red dashboard tile.

#### `farm_visit_sessions`

- customer, farm, flock, and visit date
- optional selected houses
- briefing snapshot
- status
- assigned auditor
- start/completion timestamps
- notes and sync metadata

#### `visit_investigations`

- visit ID
- optional source concern ID
- house/location scope
- suggested or manually created origin
- investigation type and instruction
- completion status
- result summary

#### `visit_findings`

- visit and investigation IDs
- finding type and severity
- measured value/unit or structured observation
- house/location
- staff explanation when recorded
- author and timestamp
- evidence attachment links

#### `cause_assessments`

- visit ID
- concern ID
- probable cause
- optional alternative causes
- supporting and conflicting evidence links
- status such as suspected, probable, confirmed, or ruled out
- author and timestamp

ChickMark suggestions never become confirmed causes without a user decision.

#### `corrective_actions`

- source concern, visit, and optional cause assessment
- instruction
- owner
- due date
- implementation confirmation and timestamp
- status
- completion notes and evidence
- sync metadata

#### `action_kpi_evaluations`

- action ID
- KPI key and scope
- baseline window/value
- target rule/value
- evaluation start/end
- observed result
- effectiveness: effective, partially effective, ineffective, or not evaluated
- evaluator and timestamp

## 6. Broiler Daily Entry

The user selects:

```text
Customer → Broiler farm → Flock batch → Date
```

All active house placements for the flock appear together.

The wide layout uses one row per house and supports keyboard entry. The phone
layout uses one expandable card per house. Essential fields appear first;
environment, events, causes, and source attachments are progressively
disclosed.

### 6.1 Population

- Opening bird count
- Daily mortality
- Daily culls
- Optional mortality causes
- Explicit transfers, partial depletion, or other population adjustments when
  they occur
- Calculated closing live count

### 6.2 Feed

- Daily feed consumed
- Feed type or phase
- Feed change
- Feed interruption or shortage

### 6.3 Water

- Daily water consumption
- Flushing water when reported separately
- Water interruption
- Medication or vaccination through water

Flushing water is excluded from bird-consumption calculations.

### 6.4 Body weight

- Average body weight
- Number of birds weighed
- Uniformity
- CV%

Weight is optional on days when the farm does not sample birds.

### 6.5 Environment

- Minimum, maximum, and average temperature
- Relative humidity
- CO2
- Ammonia
- Ventilation or heat-stress incident

### 6.6 Health and operational events

The form supports the structured event types defined in
`broiler_daily_events` plus notes.

### 6.7 Entry behavior

- The prior day's value is visible beside each editable value.
- ChickMark derives flock age from the placement date.
- Breed, sex profile, placed population, and target profile come from the
  flock.
- Blocking errors prevent final confirmation but may remain in a local draft.
- Warnings require review and may be confirmed with an event or explanation.
- Valid house rows can save without discarding an incomplete house draft.
- Final confirmation writes all changed house records transactionally per
  logical record and nudges background sync.

## 7. KPI Definitions

All calculations use canonical metric units internally:

- birds as integer counts
- feed in kilograms at record level and grams per bird for comparison
- water in liters at record level and milliliters per bird for comparison
- body weight in grams
- temperature in Celsius internally

Display units may be converted by user preference.

### 7.1 Age and population

```text
ageDay = local calendar days between recordDate and flock.entryDate

closingLiveBirds =
  openingBirds
  - mortality
  - culls
  + transferIn
  - transferOut
  - otherDepletion

averageLiveBirds = (openingBirds + closingLiveBirds) / 2
```

The next day's opening count is compared with the prior closing count.
Differences require an explicit population adjustment or clarification.

### 7.2 Mortality and livability

```text
dailyMortalityPct = mortality / openingBirds × 100

cumulativeMortalityPct =
  cumulativeMortality / totalPlacedBirds × 100

livabilityPct =
  (totalPlacedBirds - cumulativeMortality - cumulativeCulls)
  / totalPlacedBirds × 100
```

Planned depletion and transfer do not count as mortality.

### 7.3 Feed and water

```text
feedPerLiveBirdG =
  dailyFeedKg × 1000 / averageLiveBirds

cumulativeFeedPerPlacedBirdG =
  cumulativeFeedKg × 1000 / totalPlacedBirds

targetAdjustedExpectedCumulativeFeedKg =
  sum(targetDailyFeedPerLiveBirdG × actualAverageLiveBirdsForDay)
  / 1000

cumulativeFeedDeviationPct =
  (cumulativeFeedKg - targetAdjustedExpectedCumulativeFeedKg)
  / targetAdjustedExpectedCumulativeFeedKg
  × 100

waterPerLiveBirdMl =
  birdConsumptionWaterL × 1000 / averageLiveBirds

waterToFeedRatio =
  birdConsumptionWaterL / dailyFeedKg
```

`cumulativeFeedPerPlacedBirdG` is a management-context KPI. Vendor cumulative
feed objectives are published per living bird, so ChickMark compares total
actual feed with the target-adjusted expected total built from each day's
target and actual average live population. It does not compare a per-placed
actual directly with a per-living-bird vendor target.

### 7.4 Weight

```text
weightDeviationPct =
  (actualWeightG - targetWeightG) / targetWeightG × 100

averageDailyGainG =
  (currentWeightG - priorValidWeightG)
  / daysBetweenSamples
```

The UI shows both the absolute and percentage difference from target.

### 7.5 FCR

The vendor target profile preserves the vendor's published method notes. The
initial actual FCR is explicitly labeled **estimated** unless mortality/removal
weight is known:

```text
estimatedLiveWeightGainKg =
  currentLiveBiomassKg - placedChickBiomassKg

estimatedFcr =
  cumulativeFeedKg / estimatedLiveWeightGainKg
```

The KPI is unavailable when required placement, population, cumulative feed,
or weight inputs are missing or invalid. ChickMark does not present a
misleading zero.

### 7.6 End-of-cycle efficiency

When a flock closes and the necessary inputs exist:

```text
EPEF =
  livabilityPct × finalAverageWeightKg
  / (cycleAgeDays × finalFcr)
  × 100
```

The report states the exact formula and inputs. If a customer uses a different
PEF convention, it is a separately named configurable metric rather than an
undocumented formula change.

### 7.7 Aggregation

- House KPIs use the house placement.
- Flock and farm counts and volumes are summed.
- Flock and farm per-bird rates use weighted denominators; house percentages
  are never averaged naively.
- Missing house data lowers completeness and is shown explicitly.
- A target comparison is unavailable when the flock lacks a matching
  breed/version/sex/age row.

## 8. Official Broiler Objective Catalogue

The initial seed set excludes Ross 308 AP and includes:

1. Ross 308 / Ross 308 FF, 2022
2. Indian River / Indian River FF, 2022
3. Arbor Acres Plus / Arbor Acres Plus S, 2022
4. Hubbard Efficiency Plus, version V-2025-06
5. Cobb500 Broiler Performance and Nutrition Supplement, 2022

Official sources:

- Ross:
  <https://aviagen.com/assets/Tech_Center/Ross_Broiler/RossxRoss308-BroilerPerformanceObjectives2022-EN.pdf>
- Indian River:
  <https://aviagen.com/assets/Tech_Center/LIR_Broiler/IndianRiver-BroilerPerformanceObjectives2022-EN.pdf>
- Arbor Acres:
  <https://aviagen.com/assets/Tech_Center/AA_Broiler/ArborAcres-BroilerPerformanceObjectives2022-EN.pdf>
- Hubbard:
  <https://www.hubbardbreeders.com/media/broiler-performance-objectives-hep-enfres-1.pdf>
- Cobb500:
  <https://www.cobbgenetics.com/assets/Cobb-Files/2022-Cobb500-Broiler-Performance-Nutrition-Supplement.pdf>

Extraction and seed rules:

- Metric values are stored for age day 0 through 56.
- `as_hatched`, `male`, and `female` remain separate target profiles.
- The source files publish body weight, gain, feed intake, cumulative intake,
  and FCR with source-specific availability.
- Hubbard publishes water as feed multiplied by 1.70; that relationship belongs
  only to the relevant Hubbard profile.
- Hubbard sex-specific body-weight and FCR values begin later than its
  as-hatched values. Earlier missing sex-specific values remain null.
- Vendor FCR notes are retained, including whether mortality is excluded.
- Extraction is verified visually against the original PDF tables.
- Seed tests check representative age days 0, 7, 24, 35, and 56 for every
  breed/sex profile.
- Imported source values are immutable within a profile version. A later
  publication creates a new version rather than rewriting historical targets.

Mortality and environmental limits are not presented as genetic performance
objectives unless an official source explicitly provides them. They are
maintained as cited, editable operational rules.

## 9. Validation and Monitoring

### 9.1 Blocking validation

Examples:

- Negative counts or consumption.
- Mortality plus culls exceeding the available population without a matching
  adjustment.
- Closing live birds below zero.
- Duplicate current record for the same placement/date.
- Record date before placement or after a closed placement without an explicit
  correction workflow.
- Invalid verification transition or missing correction reason.

### 9.2 Non-blocking data-quality warnings

Examples:

- Opening count differs from the prior closing count.
- Feed or water changes beyond a configured rate without an operational event.
- Cumulative feed decreases.
- Zero mortality is repeated for an unusually long configured period.
- Identical values repeat suspiciously.
- Weight changes implausibly between valid samples.
- Source attachment and entered totals disagree during review.

Warnings mark the record for review. They do not invent corrected values.

### 9.3 Performance concerns

A performance concern requires:

- credible current data,
- enough valid observations,
- a configured threshold,
- and the rule's persistence window.

Examples:

- Weight below target.
- Feed intake below target for several days.
- Declining water-to-feed ratio.
- Accelerating mortality.
- Poor or worsening uniformity.

Global operational defaults may be overridden per customer. The agreed example
weight defaults are watch at -3% and critical at -5%, labeled as editable
ChickMark operational defaults rather than vendor objectives.

## 10. Performance Workspace

`Performance` becomes the monitoring workspace in the main navigation.

Primary areas:

### 10.1 Current status

- Age and phase
- Live population and livability
- Weight versus target
- Mortality status
- Feed versus target
- Water and water-to-feed trend
- Current data completeness and verification status

### 10.2 Trends

- Daily and cumulative mortality
- Feed consumption
- Water consumption
- Body weight
- ADG
- Uniformity and CV%
- Estimated FCR
- Actual and target series

### 10.3 Active concerns

Each concern shows:

- scope and severity,
- first and last observation,
- supporting trend,
- data verification state,
- suggested next investigation,
- visit/action linkage,
- and current status.

### 10.4 Visits and corrective actions

- Last visit
- Open investigations
- Probable causes
- Open and overdue actions
- Baseline and recovery KPI windows
- Effectiveness decision

The existing hatchery dashboard remains functional while the UI evolves toward
sector-aware monitoring.

## 11. Diagnostic Visit and Corrective-Action Flow

### 11.1 Visit briefing

ChickMark assembles:

- flock, farm, house, age, breed, and sex context,
- relevant target profile,
- current concerns,
- trend and data-quality evidence,
- prior visit findings,
- open actions,
- suggested physical checks.

Suggestions are editable drafts. The user confirms the visit plan.

### 11.2 During the visit

The first farm-visit structure supports:

- actual and individual bird weights,
- sample count, uniformity, and CV%,
- environmental measurements,
- feed and water measurements,
- bird behavior and litter assessment,
- clinical and necropsy observations,
- equipment and management observations,
- photos and source documents,
- staff explanations.

Every measurement records scope, location, author, and timestamp.

### 11.3 Probable cause

A cause assessment links:

- the performance problem,
- daily-data evidence,
- visit measurements and observations,
- alternative explanations,
- and the responsible user's conclusion.

The system distinguishes suspected, probable, confirmed, and ruled-out causes.

### 11.4 Corrective action and evaluation

Each action links to:

- a concern and optional cause assessment,
- an owner and due date,
- implementation confirmation,
- one or more KPIs,
- baseline and target values,
- an evaluation window,
- and an effectiveness result.

The evaluation result is `effective`, `partially_effective`, `ineffective`, or
`not_evaluated`. ChickMark may calculate supporting KPI changes, but a user
confirms the final evaluation.

## 12. Offline, Sync, and Security

- Every workflow is usable without connectivity.
- Saves commit locally before sync is attempted.
- Sync state is visible for records, revisions, sources, concerns, visits, and
  actions.
- Background sync retries failed rows without blocking entry.
- Attachments have independent upload state.
- Remote conflicts preserve both revisions and enter review.
- New tables participate in workspace ownership, sign-out retention, customer
  deletion, tombstones, incoming sync, outgoing sync, and security tests.
- Customer-role users can access only data for their assigned customer.
- Data-entry, verification, target administration, cause confirmation, and
  action management permissions remain role-gated.
- Supabase tables and storage paths receive matching RLS and foreign-key
  policies before remote sync is enabled.

## 13. Migration Strategy

The next implementation uses the next available SQLite schema version and
matching Supabase migrations.

Migration rules:

- Add tables and nullable legacy columns before enforcing new Broiler-only
  requirements in application code.
- Preserve every existing customer, flock, hatchery, audit, panel row, photo,
  action, and sync marker.
- Backfill existing flock sector to Breeder only where the legacy hatchery
  context makes that classification safe; otherwise leave it null for review.
- Do not invent farms, houses, or placements for legacy data.
- Create indexes for active house placements, house/date records, current
  revisions, target lookup, open concerns, due actions, and sync queues.
- Run schema repair idempotently without resetting the database.
- Add every tenant-owned table to customer deletion and workspace cleanup.
- Enable Supabase sync only after the local migration, repository tests, RLS,
  and remote migration pass.

## 14. Error Handling

- Missing optional data produces unavailable KPIs, not zeros.
- Missing targets produce an explicit “target unavailable” state.
- Invalid denominators suppress the KPI and provide a reason.
- Warnings preserve draft data and user explanations.
- Source-file failures keep the record and retry the attachment.
- Partial multi-house entry keeps completed rows and incomplete drafts.
- Calculation errors do not discard raw evidence.
- Sync errors identify the table/record and remain retryable.
- Concurrent corrections never silently discard a revision.
- Future AI extraction creates a reviewable draft and never finalizes data
  silently.

## 15. Verification Strategy

### 15.1 Database and migrations

- Clean database creation.
- Upgrade from the current schema with representative legacy data.
- Idempotent schema repair.
- Foreign-key, uniqueness, and active-placement constraints.
- Customer deletion, tombstones, and workspace cleanup.

### 15.2 Target catalogue

- Source metadata and version tests.
- Representative target values at age days 0, 7, 24, 35, and 56.
- Sex-specific profile selection.
- Missing source values remain null.
- No Ross 308 AP profile.
- PDF table extraction receives a visual spot-check.

### 15.3 Formulas

- Counts, units, rounding, and zero/invalid denominators.
- Daily and cumulative mortality.
- Livability with transfer/depletion exclusions.
- Feed and water per bird.
- Water-to-feed ratio excluding flushing.
- Weight deviation and multi-day ADG.
- Estimated FCR availability rules.
- EPEF at cycle completion.
- Weighted house-to-flock aggregation.

### 15.4 Repositories and sync

- Logical-record uniqueness.
- Append-only revisions and current pointer.
- Verification-state transitions.
- Conflict preservation.
- Source attachment retry.
- Incoming/outgoing Supabase round trips.
- Row-level access and role permissions.

### 15.5 Providers and UI

- Multi-house quick entry.
- Previous-day context.
- Blocking errors versus warnings.
- Draft retention.
- Phone and wide layouts.
- Target selection by breed/version/sex/age.
- Trend and concern generation.
- Missing-data and missing-target states.

### 15.6 End-to-end workflow

One authenticated scenario will verify:

1. Create customer sectors, farm, houses, flock, and placements.
2. Enter several daily records while offline.
3. Correct and verify a record without losing the original.
4. Sync the records.
5. Observe KPI trends and an active concern.
6. Add the concern to a visit briefing.
7. Capture evidence and a probable cause.
8. Issue and implement a corrective action.
9. Enter later daily data.
10. Evaluate the action against its KPI window.

## 16. Documentation and Delivery

Every meaningful implementation change updates `docs/LIVING_SPEC.md` to
describe implemented behavior only. Implementation is delivered in
migration-safe increments and validated with the narrowest relevant tests
before broader analysis and integration checks.
