# Broiler Performance Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan.

**Goal:** Deliver the first usable ChickMark performance-monitoring vertical
slice: multi-sector customer hierarchy, multi-house Broiler flock placement,
versioned official objectives, revision-safe daily entry, KPI/alert monitoring,
diagnostic farm visits, and corrective-action effectiveness tracking.

**Architecture:** Extend the existing offline-first SQLite/Supabase architecture
additively. Stable business identities (flock, placement, daily record, concern,
visit, action) own immutable or append-only evidence. Pure Dart services calculate
KPIs and alerts; repositories persist tenant-owned state; Provider-backed Flutter
screens expose the workflow through a new Performance workspace without changing
the existing hatchery audit contracts.

**Tech Stack:** Dart 3.10.7, Flutter, Provider, sqflite /
sqflite_common_ffi_web, Supabase PostgreSQL and object storage, fl_chart, uuid,
existing ChickMark localization and UI primitives.

**Approved design:** [2026-07-24-broiler-performance-monitoring-design.md](../specs/2026-07-24-broiler-performance-monitoring-design.md)

## Global Constraints

- Treat current Flutter code as the source of truth and preserve all unrelated
  worktree changes.
- Stage only files named by the active task.
- Keep legacy hatchery audits, `audit_sessions`, and `dashboard_actions`
  behavior unchanged.
- Use additive migration version 51; legacy flocks remain valid with nullable
  new relationships.
- Use test-driven development: write one failing behavioral test, run it, add
  the smallest implementation, run it again, then refactor.
- Every tenant-owned mutable row keeps ChickMark's existing sync metadata:
  `syncStatus`, `lastSyncedAt`, `syncError`, `createdAt`, and `updatedAt`.
- Every repository write must be transactional at the logical operation level.
- Never silently infer or overwrite source facts. Daily corrections append a
  revision and retain prior evidence.
- Never label ChickMark operational alert thresholds as breed-vendor
  objectives.
- Update `docs/LIVING_SPEC.md` with behavior that is actually implemented.

## Phase A — Offline Domain and Daily Evidence

### Task 1: Freeze the v51 persistence contract

**Files:**

- Modify: `lib/data/database/database_helper.dart`
- Modify: `lib/data/database/database_schema.dart`
- Modify: `lib/data/database/database_migrations.dart`
- Create: `test/data/database/performance_monitoring_schema_test.dart`
- Modify: `test/data/database/database_helper_migration_test.dart`
- Modify: `test/data/database/database_integrity_test.dart`
- Modify: `test/data/database/surgical_schema_repair_test.dart`

**Step 1: Write the failing fresh-database contract test**

Open a test database and assert database version 51, the complete table set,
the unique placement/day constraint, and the partial active-house placement
index:

```dart
expect(
  tables,
  containsAll(<String>[
    'customer_sectors',
    'farms',
    'houses',
    'flock_placements',
    'broiler_daily_records',
    'broiler_daily_record_revisions',
    'daily_record_sources',
    'broiler_daily_events',
    'broiler_target_profiles',
    'broiler_target_rows',
    'performance_alert_rules',
    'performance_concerns',
    'farm_visit_sessions',
    'farm_visit_houses',
    'visit_investigations',
    'visit_findings',
    'cause_assessments',
    'corrective_actions',
    'action_kpi_evaluations',
  ]),
);
```

Run:

```bash
flutter test test/data/database/performance_monitoring_schema_test.dart
```

Expected: FAIL because the v51 schema does not exist.

**Step 2: Add the v51 schema**

Add nullable `farmId`, `sectorKey`, `sexProfile`, `targetProfileId`, and
`productionPhase` columns to `flocks`. Add idempotent table/index creation
helpers for all tables in Step 1. Use foreign keys and cascades from the design,
including:

```sql
CREATE UNIQUE INDEX IF NOT EXISTS
  idx_broiler_daily_records_placement_date
ON broiler_daily_records(placementId, recordDate);

CREATE UNIQUE INDEX IF NOT EXISTS
  idx_active_placement_per_house
ON flock_placements(houseId)
WHERE status = 'active' AND endedAt IS NULL;
```

Model a selected visit-house relationship in `farm_visit_houses` rather than a
serialized list. Keep attachment rows independent so upload failure never rolls
back a saved local record/finding.

**Step 3: Add migration and repair coverage**

Increment the database version to 51, add `_applyV51Upgrade`, register critical
tables/columns, and call the same idempotent v51 creation path from surgical
repair. Backfill `flocks.sectorKey = 'breeder'` only for a flock with an
unambiguous existing hatchery-linked audit; leave every other legacy flock
unclassified.

Run:

```bash
flutter test test/data/database/performance_monitoring_schema_test.dart \
  test/data/database/database_helper_migration_test.dart \
  test/data/database/database_integrity_test.dart \
  test/data/database/surgical_schema_repair_test.dart
```

Expected: PASS.

**Step 4: Commit**

```bash
git add lib/data/database/database_helper.dart \
  lib/data/database/database_schema.dart \
  lib/data/database/database_migrations.dart \
  test/data/database/performance_monitoring_schema_test.dart \
  test/data/database/database_helper_migration_test.dart \
  test/data/database/database_integrity_test.dart \
  test/data/database/surgical_schema_repair_test.dart
git commit -m "feat: add performance monitoring schema"
```

### Task 2: Implement customer sectors, farms, houses, and placements

**Files:**

- Create: `lib/data/models/poultry_hierarchy_models.dart`
- Create: `lib/data/repositories/poultry_hierarchy_repository.dart`
- Modify: `lib/data/models/flock_model.dart`
- Modify: `lib/data/repositories/flock_repository.dart`
- Create: `test/data/models/poultry_hierarchy_models_test.dart`
- Create: `test/data/repositories/poultry_hierarchy_repository_test.dart`
- Modify: `test/data/repositories/flock_repository_test.dart`

**Step 1: Write failing model and repository tests**

Cover enum serialization for `breeder`, `broiler`, `layer`; a customer with
multiple sectors; a farm with exactly one sector; a flock spanning two houses;
and rejection of a second active flock placement in the same house.

```dart
await repository.createPlacement(firstPlacement);
await expectLater(
  repository.createPlacement(secondActivePlacementForSameHouse),
  throwsA(isA<ActiveHousePlacementConflict>()),
);
```

Run:

```bash
flutter test test/data/models/poultry_hierarchy_models_test.dart \
  test/data/repositories/poultry_hierarchy_repository_test.dart \
  test/data/repositories/flock_repository_test.dart
```

Expected: FAIL because the domain contract is absent.

**Step 2: Implement typed models**

Create `PoultrySector`, `FlockSexProfile`, `CustomerSectorModel`, `FarmModel`,
`HouseModel`, and `FlockPlacementModel`. Each model owns `toMap`, `fromMap`,
`copyWith`, sync fields, and validation. Extend `FlockModel` without making new
fields mandatory for legacy rows.

**Step 3: Implement transactional repository operations**

Provide:

- `listCustomerSectors(customerId)`
- `replaceCustomerSectors(customerId, sectors)`
- `listFarms(customerId, {sector})`
- `listHouses(farmId, {activeOnly})`
- `listPlacements(flockId, {activeOnly})`
- `createBroilerFlockWithPlacements(flock, placements)`
- `endPlacement(placementId, endedAt)`

Translate the partial-index SQLite exception into
`ActiveHousePlacementConflict`. Mark local writes dirty and update timestamps.

Run the tests from Step 1. Expected: PASS.

**Step 4: Commit**

```bash
git add lib/data/models/poultry_hierarchy_models.dart \
  lib/data/repositories/poultry_hierarchy_repository.dart \
  lib/data/models/flock_model.dart \
  lib/data/repositories/flock_repository.dart \
  test/data/models/poultry_hierarchy_models_test.dart \
  test/data/repositories/poultry_hierarchy_repository_test.dart \
  test/data/repositories/flock_repository_test.dart
git commit -m "feat: add poultry hierarchy and placements"
```

### Task 3: Add the versioned Broiler objective catalogue

**Files:**

- Create: `lib/data/models/broiler_target_models.dart`
- Create: `lib/data/database/seeds/broiler_target_seeds.dart`
- Create: `lib/data/repositories/broiler_target_repository.dart`
- Create: `tool/verify_broiler_target_catalog.dart`
- Create: `test/data/repositories/broiler_target_repository_test.dart`
- Create: `test/data/database/broiler_target_seed_test.dart`

**Step 1: Write failing catalogue tests**

Assert exact profile identity, sex variants, source metadata, age-day uniqueness,
and representative source values at days 0, 7, 21, 35, 42, and 56 for:

- Ross 308 / Ross 308 FF (2022)
- Indian River / Indian River FF (2022)
- Arbor Acres Plus / Arbor Acres Plus S (2022)
- Hubbard Efficiency Plus (V-2025-06)
- Cobb500 (2022)

Also assert that a source-absent metric remains null and that Hubbard target
water equals the published feed objective multiplied by 1.70 only where that
method is explicitly stored in the row notes.

Run:

```bash
flutter test test/data/database/broiler_target_seed_test.dart \
  test/data/repositories/broiler_target_repository_test.dart
```

Expected: FAIL because no catalogue exists.

**Step 2: Add typed target models and compact checked-in seeds**

Use versioned profile identifiers and a compact Dart seed representation with
one row per published age/sex value. Retain source title, publication version,
official URL, sex profile, units, and method notes. Do not interpolate missing
values or include Ross 308 AP.

The seed verifier must check:

```dart
for (final profile in profiles) {
  final ages = profile.rows.map((row) => row.ageDay).toSet();
  if (ages.length != profile.rows.length) {
    throw StateError('Duplicate age in ${profile.id}');
  }
}
```

**Step 3: Implement editable versioning**

Implement:

- `ensureOfficialCatalogueSeeded()`
- `listProfiles({brand, breed, sexProfile, activeOnly})`
- `getRow(profileId, ageDay)`
- `createCustomProfileVersion(...)`
- `replaceRowsInDraftVersion(...)`
- `activateVersion(profileId)`

Activation must not mutate the row set of an older profile referenced by an
existing flock.

Run:

```bash
dart run tool/verify_broiler_target_catalog.dart
flutter test test/data/database/broiler_target_seed_test.dart \
  test/data/repositories/broiler_target_repository_test.dart
```

Expected: PASS.

**Step 4: Commit**

```bash
git add lib/data/models/broiler_target_models.dart \
  lib/data/database/seeds/broiler_target_seeds.dart \
  lib/data/repositories/broiler_target_repository.dart \
  tool/verify_broiler_target_catalog.dart \
  test/data/repositories/broiler_target_repository_test.dart \
  test/data/database/broiler_target_seed_test.dart
git commit -m "feat: seed versioned broiler objectives"
```

### Task 4: Implement append-only daily records and provenance

**Files:**

- Create: `lib/data/models/broiler_daily_record_models.dart`
- Create: `lib/data/repositories/broiler_daily_record_repository.dart`
- Create: `test/data/models/broiler_daily_record_models_test.dart`
- Create: `test/data/repositories/broiler_daily_record_repository_test.dart`

**Step 1: Write failing revision tests**

Cover first entry, correction, current-revision pointer, source attachment
metadata, typed event rows, house/date uniqueness, and rollback when a revision
fails validation.

```dart
final first = await repository.saveRevision(draft);
final corrected = await repository.saveRevision(
  draft.copyWith(
    recordId: first.record.id,
    mortality: 12,
    verificationStatus: VerificationStatus.corrected,
    correctionReason: 'Checked farm mortality sheet',
  ),
);

expect(corrected.revision.revisionNumber, 2);
expect(await repository.listRevisions(first.record.id), hasLength(2));
expect(corrected.record.currentRevisionId, corrected.revision.id);
```

Run:

```bash
flutter test test/data/models/broiler_daily_record_models_test.dart \
  test/data/repositories/broiler_daily_record_repository_test.dart
```

Expected: FAIL.

**Step 2: Implement typed facts and validation**

Represent population, feed, water, optional weighing sample, environment,
mortality causes, operational events, provenance, verification, transfers, and
partial depletion. Enforce:

- non-negative facts;
- closing population arithmetic when all components are present;
- eggs are not part of Broiler daily data;
- correction reason is mandatory for `corrected`;
- verified metadata is mandatory for `verified`;
- event/source rows belong to the new revision.

**Step 3: Implement transactional append-only save**

Within one SQLite transaction:

1. create or load the stable placement/day record;
2. determine next revision number;
3. insert immutable revision;
4. insert event/source rows;
5. move `currentRevisionId`;
6. set record verification status and dirty sync metadata.

Add read methods for current house/day values, previous-day values, a flock/date
entry grid, and the full correction history.

Run the tests from Step 1. Expected: PASS.

**Step 4: Commit**

```bash
git add lib/data/models/broiler_daily_record_models.dart \
  lib/data/repositories/broiler_daily_record_repository.dart \
  test/data/models/broiler_daily_record_models_test.dart \
  test/data/repositories/broiler_daily_record_repository_test.dart
git commit -m "feat: add revision-safe broiler daily records"
```

### Task 5: Build the pure Broiler KPI calculator

**Files:**

- Create: `lib/features/performance/models/broiler_performance_models.dart`
- Create: `lib/features/performance/services/broiler_kpi_calculator.dart`
- Create: `test/features/performance/broiler_kpi_calculator_test.dart`

**Step 1: Write table-driven failing tests**

Cover flock age, average live birds, mortality percentages, cumulative
mortality, livability, feed/live bird, cumulative feed, water/live bird,
water-to-feed ratio, daily gain, uniformity, CV, weight deviation, target-adjusted
cumulative feed, FCR when valid, and trend direction.

Use explicit null assertions for insufficient data:

```dart
expect(result.fcr, isNull);
expect(result.missingReasons['fcr'], 'No current body weight');
```

Expected formulas:

```text
average live birds = (opening + closing) / 2
daily mortality % = mortality / opening × 100
livability % = current live / placed × 100
water:feed = water ml / feed g
weight deviation % = (actual - target) / target × 100
target-adjusted cumulative feed =
  Σ(target feed g/living bird/day × actual average live birds/day)
```

Run:

```bash
flutter test test/features/performance/broiler_kpi_calculator_test.dart
```

Expected: FAIL.

**Step 2: Implement a deterministic pure Dart service**

No database, Flutter, or clock dependency. Input carries ordered current
revisions, placements, target rows, and optional weight samples. Output carries
value, unit, data quality, comparison, direction, and missing reason.

Do not implement EPEF, projected final weight, or projected final FCR without a
separately validated projection method. End-of-cycle EPEF is allowed only when
cycle-completion facts are present.

Run the test from Step 1. Expected: PASS.

**Step 3: Commit**

```bash
git add lib/features/performance/models/broiler_performance_models.dart \
  lib/features/performance/services/broiler_kpi_calculator.dart \
  test/features/performance/broiler_kpi_calculator_test.dart
git commit -m "feat: calculate broiler performance KPIs"
```

### Task 6: Deliver manual multi-house quick entry

**Files:**

- Create: `lib/features/performance/providers/broiler_daily_entry_provider.dart`
- Create: `lib/features/performance/screens/broiler_daily_entry_screen.dart`
- Create: `lib/features/performance/widgets/house_daily_entry_card.dart`
- Create: `lib/features/performance/widgets/daily_entry_source_section.dart`
- Modify: `lib/l10n/app_localizations.dart`
- Create: `test/features/performance/broiler_daily_entry_provider_test.dart`
- Create: `test/features/performance/broiler_daily_entry_screen_test.dart`

**Step 1: Write failing provider/widget tests**

Cover:

- selector order Customer → Broiler farm → flock → date;
- all active placement houses loaded together;
- age/breed/placed/current population/target/previous day displayed;
- previous-day values never auto-saved as today;
- wide layout row and narrow layout cards;
- correction status/reason;
- partial invalid rows do not block valid rows from being reviewed, but the
  final save presents a clear per-house validation summary.

Run:

```bash
flutter test test/features/performance/broiler_daily_entry_provider_test.dart \
  test/features/performance/broiler_daily_entry_screen_test.dart
```

Expected: FAIL.

**Step 2: Implement provider state and safe save**

Keep one editable draft per placement. Load prior-day context and current saved
revision separately. Save selected valid drafts through the append-only
repository. Preserve unsaved drafts and surface attachment upload state.

**Step 3: Implement responsive UI**

Use existing `AppCard`, spacing, theme, validation, localization, and keyboard
patterns. Put population/feed/water first; progressively disclose weighing,
environment, events, causes, and sources.

Run the tests from Step 1. Expected: PASS.

**Step 4: Commit**

```bash
git add lib/features/performance/providers/broiler_daily_entry_provider.dart \
  lib/features/performance/screens/broiler_daily_entry_screen.dart \
  lib/features/performance/widgets/house_daily_entry_card.dart \
  lib/features/performance/widgets/daily_entry_source_section.dart \
  lib/l10n/app_localizations.dart \
  test/features/performance/broiler_daily_entry_provider_test.dart \
  test/features/performance/broiler_daily_entry_screen_test.dart
git commit -m "feat: add multi-house broiler quick entry"
```

## Phase B — Monitoring and Persistent Concerns

### Task 7: Implement operational alert rules and concern lifecycle

**Files:**

- Create: `lib/data/models/performance_concern_models.dart`
- Create: `lib/data/repositories/performance_concern_repository.dart`
- Create: `lib/data/database/seeds/performance_rule_seeds.dart`
- Create: `lib/features/performance/services/performance_alert_engine.dart`
- Create: `test/features/performance/performance_alert_engine_test.dart`
- Create: `test/data/repositories/performance_concern_repository_test.dart`

**Step 1: Write failing rule and lifecycle tests**

Cover global defaults, customer override precedence, minimum valid
observations, watch/critical thresholds, rate-of-change checks, data-consistency
checks, deduplication into one persistent concern, monitoring, resolution,
dismissal, and recurrence.

Initial consistency rules include:

- mortality exceeds unexplained live-bird reduction;
- cumulative feed decreases;
- water changes by 40% without an operational event;
- repeated identical values;
- implausible weekly body-weight change;
- extended zero mortality.

Run:

```bash
flutter test test/features/performance/performance_alert_engine_test.dart \
  test/data/repositories/performance_concern_repository_test.dart
```

Expected: FAIL.

**Step 2: Implement rule evaluation**

Separate objective deviations from operational/data-quality rules. Produce
structured evidence with observation window, actual, target/baseline, direction,
severity, and recommended investigation keys. Null or insufficient data cannot
trigger a performance-loss concern.

**Step 3: Persist concern state**

Upsert by stable scope + metric + rule identity while open/monitoring. Never
recreate a new concern on every dashboard load. Preserve lifecycle history and
link later recurrences.

Run the tests from Step 1. Expected: PASS.

**Step 4: Commit**

```bash
git add lib/data/models/performance_concern_models.dart \
  lib/data/repositories/performance_concern_repository.dart \
  lib/data/database/seeds/performance_rule_seeds.dart \
  lib/features/performance/services/performance_alert_engine.dart \
  test/features/performance/performance_alert_engine_test.dart \
  test/data/repositories/performance_concern_repository_test.dart
git commit -m "feat: detect and persist performance concerns"
```

### Task 8: Build the Broiler Performance workspace

**Files:**

- Create: `lib/features/performance/providers/performance_provider.dart`
- Create: `lib/features/performance/screens/performance_screen.dart`
- Create: `lib/features/performance/widgets/performance_status_grid.dart`
- Create: `lib/features/performance/widgets/performance_trend_panel.dart`
- Create: `lib/features/performance/widgets/active_concerns_panel.dart`
- Create: `lib/features/performance/widgets/performance_actions_panel.dart`
- Modify: `lib/app.dart`
- Modify: `lib/l10n/app_localizations.dart`
- Create: `test/features/performance/performance_provider_test.dart`
- Create: `test/features/performance/performance_screen_test.dart`

**Step 1: Write failing provider and screen tests**

Assert the four approved sections:

1. Current status;
2. Trends;
3. Active concerns;
4. Audits and corrective actions.

Cover customer/farm/flock scope switching, no-data states, reported/verified
badges, target source labels, date ranges, and opening quick entry from the
workspace.

Run:

```bash
flutter test test/features/performance/performance_provider_test.dart \
  test/features/performance/performance_screen_test.dart
```

Expected: FAIL.

**Step 2: Implement provider aggregation**

Load hierarchy, current revisions, targets, KPIs, concerns, visits, and actions
through repositories. Cache only immutable request snapshots; invalidate on
daily save, rule change, concern transition, visit completion, or action
evaluation.

**Step 3: Implement the responsive workspace**

Use neutral chart titles, visible units/target sources, accessible severity
labels, and compact no-data explanations. Do not show a zero for a missing KPI.

Run the tests from Step 1. Expected: PASS.

**Step 4: Commit**

```bash
git add lib/features/performance/providers/performance_provider.dart \
  lib/features/performance/screens/performance_screen.dart \
  lib/features/performance/widgets/performance_status_grid.dart \
  lib/features/performance/widgets/performance_trend_panel.dart \
  lib/features/performance/widgets/active_concerns_panel.dart \
  lib/features/performance/widgets/performance_actions_panel.dart \
  lib/app.dart lib/l10n/app_localizations.dart \
  test/features/performance/performance_provider_test.dart \
  test/features/performance/performance_screen_test.dart
git commit -m "feat: add broiler performance workspace"
```

## Phase C — Diagnostic Visits and Action Effectiveness

### Task 9: Implement visit briefing and diagnostic evidence

**Files:**

- Create: `lib/data/models/farm_visit_models.dart`
- Create: `lib/data/repositories/farm_visit_repository.dart`
- Create: `lib/features/performance/services/visit_briefing_builder.dart`
- Create: `test/data/repositories/farm_visit_repository_test.dart`
- Create: `test/features/performance/visit_briefing_builder_test.dart`

**Step 1: Write failing briefing and repository tests**

Given weight, feed, water, mortality, and previous rear-house concerns, assert
that a briefing snapshot includes the deviations and matching investigations,
then persists unchanged even if later daily data changes.

Cover manual investigations, source-concern linkage, visit-house selection,
measured findings, staff explanations, attachment metadata, and cause statuses
`suspected`, `probable`, `confirmed`, and `ruled_out`.

Run:

```bash
flutter test test/data/repositories/farm_visit_repository_test.dart \
  test/features/performance/visit_briefing_builder_test.dart
```

Expected: FAIL.

**Step 2: Implement deterministic briefing construction**

Map structured concern/investigation keys to localized investigation
instructions. The snapshot records source concern IDs, evidence windows, current
values, targets, recommended checks, generation time, and target/rule versions.

**Step 3: Implement transactional visit repository**

Provide create/start/complete visit, selected houses, investigation completion,
finding entry, and cause assessment. A suggested probable cause remains
`suspected` until a user explicitly changes its status.

Run the tests from Step 1. Expected: PASS.

**Step 4: Commit**

```bash
git add lib/data/models/farm_visit_models.dart \
  lib/data/repositories/farm_visit_repository.dart \
  lib/features/performance/services/visit_briefing_builder.dart \
  test/data/repositories/farm_visit_repository_test.dart \
  test/features/performance/visit_briefing_builder_test.dart
git commit -m "feat: add diagnostic farm visit evidence"
```

### Task 10: Implement corrective actions and KPI evaluation

**Files:**

- Create: `lib/data/models/corrective_action_models.dart`
- Create: `lib/data/repositories/corrective_action_repository.dart`
- Create: `lib/features/performance/services/action_effectiveness_evaluator.dart`
- Create: `test/data/repositories/corrective_action_repository_test.dart`
- Create: `test/features/performance/action_effectiveness_evaluator_test.dart`

**Step 1: Write failing action tests**

Cover action linkage to concern/visit/cause, owner, due date, implementation
confirmation, one or more target KPIs, immutable baseline window, evaluation
window, and all effectiveness outcomes.

```dart
expect(result.effectiveness, ActionEffectiveness.effective);
expect(result.baselineValue, 1.51);
expect(result.observedValue, greaterThanOrEqualTo(1.70));
```

Run:

```bash
flutter test test/data/repositories/corrective_action_repository_test.dart \
  test/features/performance/action_effectiveness_evaluator_test.dart
```

Expected: FAIL.

**Step 2: Implement repository and evaluator**

Store evaluation definitions when the action is issued. Evaluate only from
valid daily observations in the requested scope/window. Return `notEvaluated`
with a reason when implementation is unconfirmed, the window is incomplete, or
data is insufficient.

Run the tests from Step 1. Expected: PASS.

**Step 3: Commit**

```bash
git add lib/data/models/corrective_action_models.dart \
  lib/data/repositories/corrective_action_repository.dart \
  lib/features/performance/services/action_effectiveness_evaluator.dart \
  test/data/repositories/corrective_action_repository_test.dart \
  test/features/performance/action_effectiveness_evaluator_test.dart
git commit -m "feat: evaluate corrective action effectiveness"
```

### Task 11: Deliver visit and action workflow screens

**Files:**

- Create: `lib/features/performance/providers/farm_visit_provider.dart`
- Create: `lib/features/performance/screens/farm_visit_screen.dart`
- Create: `lib/features/performance/screens/corrective_action_screen.dart`
- Create: `lib/features/performance/widgets/visit_briefing_card.dart`
- Create: `lib/features/performance/widgets/visit_investigation_card.dart`
- Create: `lib/features/performance/widgets/cause_assessment_card.dart`
- Create: `lib/features/performance/widgets/action_evaluation_card.dart`
- Modify: `lib/l10n/app_localizations.dart`
- Create: `test/features/performance/farm_visit_screen_test.dart`
- Create: `test/features/performance/corrective_action_screen_test.dart`

**Step 1: Write failing workflow tests**

Cover concern → briefing → visit → finding → user-confirmed probable cause →
corrective action → KPI evaluation. Verify that daily-entry facts are displayed
as evidence and are not redundantly re-entered in the visit form.

Run:

```bash
flutter test test/features/performance/farm_visit_screen_test.dart \
  test/features/performance/corrective_action_screen_test.dart
```

Expected: FAIL.

**Step 2: Implement responsive workflow UI**

Provide:

- pre-visit briefing and selected houses;
- investigation checklist;
- measured/observed findings and attachment metadata;
- explicit user control over cause status;
- action owner/due/implementation data;
- before/after KPI evidence and effectiveness reason.

Run the tests from Step 1. Expected: PASS.

**Step 3: Commit**

```bash
git add lib/features/performance/providers/farm_visit_provider.dart \
  lib/features/performance/screens/farm_visit_screen.dart \
  lib/features/performance/screens/corrective_action_screen.dart \
  lib/features/performance/widgets/visit_briefing_card.dart \
  lib/features/performance/widgets/visit_investigation_card.dart \
  lib/features/performance/widgets/cause_assessment_card.dart \
  lib/features/performance/widgets/action_evaluation_card.dart \
  lib/l10n/app_localizations.dart \
  test/features/performance/farm_visit_screen_test.dart \
  test/features/performance/corrective_action_screen_test.dart
git commit -m "feat: add visit and corrective action workflow"
```

## Phase D — Product Integration and Reliability

### Task 12: Integrate hierarchy management and navigation

**Files:**

- Modify: `lib/providers/customers_provider.dart`
- Modify: `lib/features/customers/screens/customers_screen.dart`
- Create: `lib/features/customers/widgets/customer_sector_management_sheet.dart`
- Create: `lib/features/customers/widgets/farm_management_sheet.dart`
- Create: `lib/features/customers/widgets/house_management_sheet.dart`
- Modify: `lib/features/home/widgets/main_shell.dart`
- Modify: `lib/features/home/screens/home_screen.dart`
- Modify: `lib/app.dart`
- Modify: `lib/l10n/app_localizations.dart`
- Create: `test/features/customers/customer_hierarchy_test.dart`
- Modify: `test/features/home/home_screen_test.dart`

**Step 1: Write failing integration tests**

Assert:

- one customer can enable Breeder, Broiler, and Layer concurrently;
- each farm selects exactly one enabled customer sector;
- hatchery management remains available only under Breeder;
- a Performance destination is visible to authorized users;
- existing navigation indices and role filtering remain stable.

Run:

```bash
flutter test test/features/customers/customer_hierarchy_test.dart \
  test/features/home/home_screen_test.dart
```

Expected: FAIL.

**Step 2: Implement management sheets and destination**

Add sector/farm/house management to the existing customer flow. Add the
Performance workspace through the shell's typed tab list; never hard-code an
index outside the tab definition.

Run the tests from Step 1 plus:

```bash
flutter test test/features/customers test/features/home
```

Expected: PASS.

**Step 3: Commit**

```bash
git add lib/providers/customers_provider.dart \
  lib/features/customers/screens/customers_screen.dart \
  lib/features/customers/widgets/customer_sector_management_sheet.dart \
  lib/features/customers/widgets/farm_management_sheet.dart \
  lib/features/customers/widgets/house_management_sheet.dart \
  lib/features/home/widgets/main_shell.dart \
  lib/features/home/screens/home_screen.dart \
  lib/app.dart lib/l10n/app_localizations.dart \
  test/features/customers/customer_hierarchy_test.dart \
  test/features/home/home_screen_test.dart
git commit -m "feat: integrate poultry hierarchy and performance navigation"
```

### Task 13: Extend offline sync, workspace cleanup, and Supabase security

**Files:**

- Create: `supabase/migrations/0017_performance_monitoring.sql`
- Modify: `lib/services/supabase/startup_sync_service.dart`
- Modify: `lib/services/supabase/supabase_service.dart`
- Modify: `lib/services/auth/account_workspace_service.dart`
- Modify: `lib/data/repositories/customer_repository.dart`
- Modify: `lib/data/repositories/sync_tombstone_repository.dart`
- Modify: `test/services/supabase/startup_sync_service_test.dart`
- Modify: `test/services/supabase/startup_sync_incoming_test.dart`
- Modify: `test/data/repositories/sync_tombstone_repository_test.dart`
- Modify: `test/security/supabase_security_hardening_test.dart`
- Modify: `scripts/test_supabase_security_hardening.sh`

**Step 1: Write failing sync/security tests**

Cover upload/download order, per-row conflict handling, tombstone delete order,
account-switch cleanup, customer cascade cleanup, RLS isolation, immutable daily
revision rejection, and attachment failure isolation.

Run:

```bash
flutter test test/services/supabase/startup_sync_service_test.dart \
  test/services/supabase/startup_sync_incoming_test.dart \
  test/data/repositories/sync_tombstone_repository_test.dart \
  test/security/supabase_security_hardening_test.dart
```

Expected: FAIL.

**Step 2: Add remote schema and policies**

Mirror v51 using PostgreSQL types, checks, indexes, foreign keys, `updated_at`
triggers, tenant-aware RLS, and storage paths. Add a trigger that rejects update
or delete of a daily revision except through the correction/tombstone policy
explicitly defined for authorized sync.

**Step 3: Extend ordered sync**

Push/pull parents before children:

```text
customers → customer_sectors → farms → houses → target profiles/rows
→ flocks → placements → daily records → revisions → events/sources
→ rules → concerns → visits → investigations/findings/causes
→ actions → evaluations
```

Delete in the reverse dependency order. Reuse existing conflict recording,
batching, dirty/synced/failed transitions, and retry behavior.

Run the tests from Step 1 and:

```bash
bash scripts/test_supabase_security_hardening.sh
```

Expected: PASS, or a clearly reported environment skip where existing tests
already support it.

**Step 4: Commit**

```bash
git add supabase/migrations/0017_performance_monitoring.sql \
  lib/services/supabase/startup_sync_service.dart \
  lib/services/supabase/supabase_service.dart \
  lib/services/auth/account_workspace_service.dart \
  lib/data/repositories/customer_repository.dart \
  lib/data/repositories/sync_tombstone_repository.dart \
  test/services/supabase/startup_sync_service_test.dart \
  test/services/supabase/startup_sync_incoming_test.dart \
  test/data/repositories/sync_tombstone_repository_test.dart \
  test/security/supabase_security_hardening_test.dart \
  scripts/test_supabase_security_hardening.sh
git commit -m "feat: sync and secure performance monitoring data"
```

### Task 14: Prove the vertical workflow and update the living specification

**Files:**

- Create: `test/features/performance/broiler_monitoring_workflow_test.dart`
- Modify: `docs/LIVING_SPEC.md`

**Step 1: Write the end-to-end local workflow test**

The test must:

1. create a multi-sector customer and Broiler farm;
2. create two houses and one flock placed in both;
3. select a seeded objective profile;
4. enter five daily records;
5. correct one source record and retain revision 1;
6. calculate a persistent water/feed concern;
7. generate a visit briefing;
8. record rear-line flow and rear-house weight findings;
9. mark a probable cause through explicit user state;
10. issue and implement a corrective action;
11. enter post-action daily data;
12. evaluate effectiveness.

Run:

```bash
flutter test test/features/performance/broiler_monitoring_workflow_test.dart
```

Expected: PASS.

**Step 2: Update implemented product behavior**

Document only delivered behavior in `docs/LIVING_SPEC.md`, including hierarchy,
target-source/version handling, revision semantics, calculation methods, alert
rule separation, concern lifecycle, visit evidence, action evaluation, sync,
and known deferred items.

**Step 3: Run focused and broad verification**

```bash
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test test/data/database \
  test/data/repositories \
  test/features/performance \
  test/features/customers \
  test/features/home \
  test/services/supabase \
  test/security
flutter test
```

Record any pre-existing failures separately from failures introduced by this
branch.

**Step 4: Commit**

```bash
git add test/features/performance/broiler_monitoring_workflow_test.dart \
  docs/LIVING_SPEC.md
git commit -m "test: prove broiler monitoring workflow"
```

## Completion Gate

Before asking for human review:

- Verify all required files are tracked and `.superpowers/`, downloaded PDFs,
  browser state, and `tmp/` are not staged.
- Run `git diff --check`.
- Run `git status --short --branch` and list any unrelated pre-existing changes.
- Do not call the product task complete. Present the branch, commits, commands,
  observed results, assumptions, deferred scope, and request human approval.
