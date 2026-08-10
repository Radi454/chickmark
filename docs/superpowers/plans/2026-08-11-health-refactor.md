# ChickMark Health Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the structural risks found in the 2026-08-11 health review — no schema-parity safety net, a 4,863-line `AuditProvider` god object, a 2,837-line misnamed `stub_sections.dart`, always-alive global providers, and 127 MB of untracked recovery blobs — without changing any user-visible behavior.

**Architecture:** Pure-function extraction first (zero-risk moves out of `AuditProvider` into stateless logic files), then a persistence coordinator extraction, then file splits, then provider scoping. Every phase gates on `flutter analyze` + `flutter test` (1,236 tests currently green) and STOPS on failure. No schema, JSON shape, sync, or save-primitive behavior changes anywhere in this plan — moves only.

**Tech Stack:** Flutter/Dart 3.10.7, Provider, sqflite (+`sqflite_common_ffi` in tests), Supabase mirror (untouched by this plan).

## Global Constraints

- DB version stays **56**. No new migrations, no schema edits.
- No changes to saved JSON shapes, panel table row contents, or sync dirty-tracking. All extractions are verbatim code moves.
- Public API of `AuditProvider` (everything consumed by the 15 dependent files) must not change name or signature.
- Gate after every task: `flutter analyze` → "No issues found", `flutter test` → all pass. STOP on any failure; do not proceed to the next task.
- Solo-dev repo: single commits per task are fine, no branches/PRs required (per repo convention). Commit messages conventional-commit style.
- One phase at a time. Phases 1–4 are ordered; Phase 5 and 6 only after explicit go-ahead from the human.

---

## Phase 0 — Repo hygiene (10 min, zero code risk)

### Task 0.1: Stop tracking risk on recovery blobs and logs

**Files:**
- Modify: `.gitignore`
- Delete: `flutter_01.log` (stale Flutter tool log at repo root)

**Interfaces:**
- Consumes: nothing
- Produces: nothing (no code)

- [ ] **Step 1: Append ignore rules**

Append to `.gitignore`:

```gitignore
# Local recovery snapshots (127 MB of DB copies/bundles — never commit)
/ChickMark-recovery/

# Flutter tool logs
flutter_*.log
```

- [ ] **Step 2: Remove the stale log**

```bash
rm flutter_01.log
```

Do **not** delete `ChickMark-recovery/` — it holds pre-repair DB snapshots. Ignored, kept on disk.

- [ ] **Step 3: Verify**

Run: `git status --short --untracked-files=all`
Expected: `ChickMark-recovery/` entries and `flutter_01.log` no longer listed; only `docs/chickmark-architecture.excalidraw` (and this plan file) remain untracked.

- [ ] **Step 4: Commit**

```bash
git add .gitignore docs/superpowers/plans/2026-08-11-health-refactor.md
git commit -m "chore: ignore local recovery snapshots and flutter logs"
```

---

## Phase 1 — Migration parity safety net (before any refactor)

Forward migrations are real (v41→56 handlers in `_onUpgrade`, [database_helper.dart:142](../../../lib/data/database/database_helper.dart)), and per-version tests exist for v52/v54/v56. The gap: nothing proves that a **v41 DB upgraded through every handler to v56** ends with the **same schema as a fresh v56 create**. Divergence here is exactly the class of bug that already required the v54 "surgical repair" work. This test is the safety net for every later phase.

### Task 1.1: Fresh-vs-upgraded schema parity test

**Files:**
- Create: `test/data/database/schema_parity_test.dart`

**Interfaces:**
- Consumes: `DatabaseHelper` test hooks already exported at [database_helper.dart:786-870](../../../lib/data/database/database_helper.dart) (`applyV46UpgradeForTest` … `applyV56UpgradeForTest`), plus the existing pattern in `test/data/database/database_helper_migration_test.dart` for opening in-memory FFI databases and seeding a v41-era schema (reuse its v41 fixture/builder — do not invent a new one).
- Produces: a `normalizedSchema(Database db)` helper other DB tests may reuse.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Reuse the v41 fixture builder from database_helper_migration_test.dart —
// extract it into a shared test util if it is currently file-private
// (move it to test/data/database/migration_fixtures.dart and import from
// both tests; verbatim move, no edits).

/// Normalized schema: table -> sorted list of "name type notnull dflt pk"
/// plus index names per table. Whitespace/case differences in CREATE
/// statements are irrelevant; PRAGMA output is canonical.
Future<Map<String, Object>> normalizedSchema(Database db) async {
  final tables = (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  ))
      .map((r) => r['name'] as String)
      .toList();
  final result = <String, Object>{};
  for (final table in tables) {
    final cols = (await db.rawQuery('PRAGMA table_info("$table")'))
        .map((c) =>
            '${c['name']} ${(c['type'] as String).toUpperCase()} '
            'nn=${c['notnull']} dflt=${c['dflt_value']} pk=${c['pk']}')
        .toList()
      ..sort();
    final indexes = (await db.rawQuery('PRAGMA index_list("$table")'))
        .map((i) => i['name'] as String)
        .where((n) => !n.startsWith('sqlite_autoindex'))
        .toList()
      ..sort();
    result[table] = {'columns': cols, 'indexes': indexes};
  }
  return result;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('v41 DB upgraded through v56 matches fresh v56 schema', () async {
    // Fresh v56: let DatabaseHelper create it in-memory.
    final fresh = await openFreshV56InMemory(); // same pattern the existing
    // migration test uses to obtain a current-schema database.
    final freshSchema = await normalizedSchema(fresh);

    // Upgraded: build v41 fixture, then run the real upgrade chain.
    final upgraded = await openV41FixtureInMemory();
    await runUpgradeChainV41ToV56(upgraded); // applyV46..V56UpgradeForTest
    final upgradedSchema = await normalizedSchema(upgraded);

    expect(upgradedSchema.keys.toSet(), freshSchema.keys.toSet(),
        reason: 'table sets diverge between fresh create and upgrade chain');
    for (final table in freshSchema.keys) {
      expect(upgradedSchema[table], freshSchema[table],
          reason: 'schema divergence in table "$table"');
    }
  });
}
```

The three helpers (`openFreshV56InMemory`, `openV41FixtureInMemory`, `runUpgradeChainV41ToV56`) wrap the exact mechanics already used in `database_helper_migration_test.dart` — copy that file's setup verbatim, don't re-derive it.

- [ ] **Step 2: Run test**

Run: `flutter test test/data/database/schema_parity_test.dart`

Two acceptable outcomes:
- **PASS** → the chain is already coherent; the net is in place. Continue.
- **FAIL with a named table divergence** → STOP. Report the diff to the human before touching anything. A real divergence is a latent v54-class bug and fixing it is its own decision (it means a new migration, which this plan is forbidden to write).

- [ ] **Step 3: Full gate**

Run: `flutter analyze && flutter test`
Expected: no issues, all pass (1,237+).

- [ ] **Step 4: Commit**

```bash
git add test/data/database/schema_parity_test.dart test/data/database/migration_fixtures.dart
git commit -m "test(db): fresh-create vs v41-upgrade schema parity net"
```

---

## Phase 2 — Extract pure functions from AuditProvider

`AuditProvider` ([audit_provider.dart](../../../lib/features/audits/providers/audit_provider.dart), 4,863 lines, ~116 methods, 29 `notifyListeners` sites) contains four large clusters of **pure functions** — no state reads, no repo calls, no notify. Moving them is mechanically safe and shrinks the file by roughly a third. Every task in this phase is a **verbatim move**: cut the function, paste it into the new file, convert `_name` → `name` (top-level functions in a new library are private-enough via import discipline; keep names otherwise identical), update call sites to the imported name. No logic edits, not even formatting "improvements".

The existing 1,236-test suite (including `test/features/audits/` provider tests) is the characterization net; each task also adds a thin direct unit test on the new file so future edits to the extracted logic don't need a provider harness.

### Task 2.1: Extract JSON/parse utilities

**Files:**
- Create: `lib/features/audits/logic/audit_value_parsing.dart`
- Modify: `lib/features/audits/providers/audit_provider.dart` (remove moved fns, add import)
- Test: `test/features/audits/logic/audit_value_parsing_test.dart`

**Interfaces:**
- Consumes: nothing (pure Dart)
- Produces (exact names, referenced by Tasks 2.2–2.4 and Phase 3):
  - `List<Map<String, dynamic>> decodedMaps(String? source)`
  - `int decodedListLength(String? source)`
  - `Map<String, Object?>? decodedMap(String? source)`
  - `double? asDouble(Object? value)`
  - `double? pct(Object? count, Object? total)`
  - `String compactJson(Map<String, Object?> value)`
  - `bool hasText(String? value)`
  - `String? blankToNull(String? value)`

- [ ] **Step 1: Create the new file with moved bodies**

Move these members from `audit_provider.dart` (current locations: `_decodedMaps` :4492, `_decodedListLength` :4506, `_asDouble` :4523, `_decodedMap` :4529, `_pct` :4554, `_compactJson` :4714, `_hasText` :4720, `_blankToNull` :4722) into `lib/features/audits/logic/audit_value_parsing.dart` as top-level functions, dropping the leading underscore. Bodies verbatim. Add only the imports the bodies need (`dart:convert`).

- [ ] **Step 2: Update the provider**

In `audit_provider.dart`: delete the moved methods, add
`import 'package:hatchaudit/features/audits/logic/audit_value_parsing.dart';`,
and rename call sites `_decodedMaps(` → `decodedMaps(` etc. (project-wide grep inside the provider file only — these were private, so no other file can reference them).

- [ ] **Step 3: Write direct unit tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/logic/audit_value_parsing.dart';

void main() {
  test('decodedMaps parses a JSON list of objects and rejects junk', () {
    expect(decodedMaps('[{"a":1},{"b":2}]'), hasLength(2));
    expect(decodedMaps(null), isEmpty);
    expect(decodedMaps('not json'), isEmpty);
    expect(decodedMaps('{"a":1}'), isEmpty); // object, not list
  });

  test('asDouble coerces num and numeric strings, else null', () {
    expect(asDouble(3), 3.0);
    expect(asDouble('2.5'), 2.5);
    expect(asDouble('x'), isNull);
    expect(asDouble(null), isNull);
  });

  test('pct divides count by total as percentage, guarding zero', () {
    expect(pct(1, 4), 25.0);
    expect(pct(1, 0), isNull);
    expect(pct(null, 4), isNull);
  });

  test('blankToNull trims and nulls empties; hasText mirrors it', () {
    expect(blankToNull('  '), isNull);
    expect(blankToNull(' a '), 'a');
    expect(hasText(''), isFalse);
    expect(hasText('x'), isTrue);
  });
}
```

Before finalizing assertions, read the moved bodies — if actual behavior differs from an assertion above (e.g. `pct` rounding), match the test to the **existing** behavior. Characterization, not specification.

- [ ] **Step 4: Gate**

Run: `flutter analyze && flutter test`
Expected: clean. STOP on failure.

- [ ] **Step 5: Commit**

```bash
git add lib/features/audits/logic/audit_value_parsing.dart lib/features/audits/providers/audit_provider.dart test/features/audits/logic/audit_value_parsing_test.dart
git commit -m "refactor(audits): extract pure value-parsing utils from AuditProvider"
```

### Task 2.2: Extract meaningfulness predicates

**Files:**
- Create: `lib/features/audits/logic/audit_meaningful_data.dart`
- Modify: `lib/features/audits/providers/audit_provider.dart`
- Test: `test/features/audits/logic/audit_meaningful_data_test.dart`

**Interfaces:**
- Consumes: `AuditModel` (`lib/data/models/audit_model.dart`), `StationSampleModel`, and Task 2.1's parsing functions.
- Produces: top-level predicates, exact former names minus underscore. The full move list (current provider line refs):
  - `treatBlankDraftAsSavedIncomplete` :989
  - `isMeaningfulPooledEggStorageValue` :2621, `hasMeaningfulEggStorageData` :2631, `hasSavableEggStorageData` :2645, `hasAnyMeaningfulStationData` :2652, `hasCoreStationData` :2666
  - `hasMeaningfulChickCoreData` :2681, `hasMeaningfulEggStorageCoreData` :2686, `hasMeaningfulEggQualityCoreData` :2690, `hasMeaningfulChickData` :2694, `hasChickQualityScopeResults` :2723, `hasMeaningfulPasgarData` :2752, `hasMeaningfulChickWeightData` :2769, `hasMeaningfulPmData` :2780
  - `hasMeaningfulHatchData` :2803, `hasHatchScopeResults` :2807, `hasMeaningfulHatchCompletionCoreData` :2846, `hasMeaningfulHatchCoreData` :2865, `hasMeaningfulBreakoutSamples` :2870
  - `hasMeaningfulSetterData` :2887, `hasSetterScopeResults` :2896, `hasSetterEstSampleResults` :2916, `hasMeaningfulSetterCoreData` :2926, `hasMeaningfulSetterEstSamples` :2946
  - `hasMeaningfulHatcherData` :2961, `hasHatcherScopeResults` :2968, `hasMeaningfulHatcherCoreData` :2986
  - `hasMeaningfulMachineId` :3007, `hasMeaningfulJsonObject` :3017, `hasMeaningfulJsonData` :3023, `hasMeaningfulEggStorageTrayData` :3032
  - `hasMeaningfulEggQualityData` :3415, `hasMeaningfulEggQualityMetadata` :3424, `hasMeaningfulEggQualityTrayData` :3434, `hasMeaningfulWeightList` :3444, `hasMeaningfulChickWeightSample` :3449, `isMeaningfulJsonValue` :3461

**Caution:** some of these call other private provider members (e.g. context checks like `_isChicksContext`). During the move, any dependency on provider **state** disqualifies verbatim extraction — instead pass the needed value as an explicit parameter (e.g. `hasMeaningfulChickData(AuditModel draft, {required bool isChicksContext})`) and adapt the provider call site. Parameterize; never copy state into the logic file.

- [ ] **Step 1: Move the functions** — verbatim bodies, underscore dropped, state-dependencies parameterized as above. Import `audit_value_parsing.dart` for any parsing calls.

- [ ] **Step 2: Update provider call sites** — delete moved methods, import the new library, rename call sites, pass explicit parameters where added.

- [ ] **Step 3: Direct unit tests (representative, not exhaustive)**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/features/audits/logic/audit_meaningful_data.dart';

void main() {
  test('blank draft has no meaningful station data', () {
    final blank = AuditModel.empty(); // use the same constructor the
    // provider tests use for a fresh draft (check existing provider tests
    // for the canonical blank-draft factory and reuse it).
    expect(hasAnyMeaningfulStationData(blank), isFalse);
  });

  test('json object meaningfulness rejects empty and blank-valued maps', () {
    expect(hasMeaningfulJsonObject(null), isFalse);
    expect(hasMeaningfulJsonObject('{}'), isFalse);
    expect(hasMeaningfulJsonObject('{"k":""}'), isFalse);
    expect(hasMeaningfulJsonObject('{"k":"v"}'), isTrue);
  });
}
```

As in 2.1: read bodies first, assert existing behavior.

- [ ] **Step 4: Gate** — `flutter analyze && flutter test`. STOP on failure.

- [ ] **Step 5: Commit**

```bash
git add lib/features/audits/logic/audit_meaningful_data.dart lib/features/audits/providers/audit_provider.dart test/features/audits/logic/audit_meaningful_data_test.dart
git commit -m "refactor(audits): extract meaningfulness predicates from AuditProvider"
```

### Task 2.3: Extract panel value builders

**Files:**
- Create: `lib/features/audits/logic/panel_value_builders.dart`
- Modify: `lib/features/audits/providers/audit_provider.dart`
- Test: `test/features/audits/logic/panel_value_builders_test.dart`

**Interfaces:**
- Consumes: `AuditModel`, Tasks 2.1–2.2 outputs.
- Produces (move list, provider line refs): `panelTablesForDraft` :3656, `panelValuesForDraft` :3703, `eggStorageValues` :3759, `eggQualityValues` :3781, `chickQualityValues` :3819, `chickWeightValues` :3873, `chickWeightValuesForSample` :3901, `emptyChickWeightValues` :3927, `chickPmValues` :3939. Same parameterization rule as Task 2.2 for any state touch.

- [ ] **Step 1: Move** (verbatim; parameterize state).
- [ ] **Step 2: Update provider call sites.**
- [ ] **Step 3: Unit test** — build one populated `AuditModel` (reuse fixtures from existing provider save tests in `test/features/audits/`), assert `panelValuesForDraft` emits the expected column keys for at least the egg-storage and chick-quality tables, and that `panelTablesForDraft` returns the correct table list for an egg-storage draft vs a chicks draft. Keys must match `database_schema.dart` panel columns — read them, don't guess.
- [ ] **Step 4: Gate** — `flutter analyze && flutter test`. STOP on failure.
- [ ] **Step 5: Commit** — `refactor(audits): extract panel value builders from AuditProvider`

### Task 2.4: Extract breakout value builders

**Files:**
- Create: `lib/features/audits/logic/breakout_value_builders.dart`
- Modify: `lib/features/audits/providers/audit_provider.dart`
- Test: `test/features/audits/logic/breakout_value_builders_test.dart`

**Interfaces:**
- Consumes: `EggBreakoutSampleEntry`, `SamplingLayer`, Tasks 2.1–2.3.
- Produces (move list, provider line refs): `isEggBreakoutPanelTable` :3964, `breakoutTrayEntriesForTable` :3979, `breakoutPoolEntriesForTable` :3989, `breakoutLeafEntriesForTable` :3999, `breakoutEntriesForTable` :4008, `breakoutBmkContextValues` :4045, `breakoutTrayLabel` :4068, `breakoutEntryRowId` :4073, `breakoutScopeLabelForEntry` :4123, `breakoutGroupLabelForScope` :4140, `scopeBeforeTrolley` :4152, `breakoutValuesForEntry` :4160, `freshBreakoutValuesForEntry` :4186, `candledBreakoutValuesForEntry` :4223, `residueBreakoutValuesForEntry` :4244, `breakoutDiffPct` :4310, `breakoutBmkColumnForCountKey` :4323, `freshBreakoutValues` :4340, `candledBreakoutValues` :4362, `residueBreakoutValues` :4383, `firstBreakoutPosition` :4472, `scopeIncludesHouse` :4669, `scopeLabelForSample` :4678.
- **Excluded:** `_breakoutBenchmarkForDraft` :4021 stays in the provider (it hits the BMK repository — persistence, Phase 3 territory).

- [ ] **Step 1: Move** (verbatim; parameterize; leave `_breakoutBenchmarkForDraft` behind).
- [ ] **Step 2: Update provider call sites.**
- [ ] **Step 3: Unit test** — `breakoutDiffPct` boundary cases, `breakoutBmkColumnForCountKey` mapping for each known count key, `isEggBreakoutPanelTable` accepts/rejects table names taken from `database_schema.dart`.
- [ ] **Step 4: Gate** — `flutter analyze && flutter test`. STOP on failure.
- [ ] **Step 5: Commit** — `refactor(audits): extract breakout value builders from AuditProvider`

**Phase 2 exit state:** `audit_provider.dart` drops from ~4,863 to roughly ~3,200 lines; four new logic files each independently unit-tested; zero behavior change.

---

## Phase 3 — Extract the panel save coordinator (highest-care task)

This phase touches save primitives, which the repo treats as hazardous (the memory rule "don't touch save primitives during refactors" exists for a reason). Mitigation: Phase 1's parity net + full suite gates + strict move-only discipline + this phase is one reviewable commit. **Get explicit human go-ahead before starting Phase 3.**

### Task 3.1: Move panel persistence into `AuditPanelSaveCoordinator`

**Files:**
- Create: `lib/features/audits/services/audit_panel_save_coordinator.dart`
- Modify: `lib/features/audits/providers/audit_provider.dart`

**Interfaces:**
- Consumes: the panel repositories the moved code already uses (`PanelSampleRepository`, `StationSampleRepository`, etc. — read the moved bodies for the exact set), plus Phase 2 logic imports.
- Produces:

```dart
class AuditPanelSaveCoordinator {
  AuditPanelSaveCoordinator({
    required this.panelSampleRepository,
    required this.stationSampleRepository,
    // ...exactly the repos the moved bodies call; enumerate during the move.
  });

  /// Single entry point the provider calls from _saveSamplesInternal.
  /// Signature mirrors the data the moved cluster consumes today:
  Future<void> savePanelTables({
    required String sessionId,
    required List<AuditModel> drafts,
    required List<StationSampleModel> samples,
    // + whatever context fields the bodies read from provider state,
    //   passed explicitly (auditType, isChicksContext, etc.)
  });
}
```

- Move list (provider line refs): `_savePanelTablesForSample` :2507, `_savePooledEggStoragePanelTable` :2522, `_scopedPanelSavePairs` :3046, `_pruneHatchBreakoutParentPairs` :3051, `_breakoutHierarchyPathsForPair` :3084, `_deleteEggQualityRowsBySessionId` :3160, `_hasMeaningfulPanelData` :3172, `_hasMeaningfulPanelTableData` :3178, `_deleteDiscardedPanelRows` :3192, `_deleteDiscardedChickWeightRows` :3210, `_deletePanelRowsForRemovedSamples` :3230, `_pruneStalePanelHierarchyRows` :3259, `_pruneStalePanelHierarchyRowsForTable` :3298, `_pruneStaleBreakoutRows` :3323, `_panelHierarchyRowForPanelSample` :3365, `_panelHierarchyRowForSample` :3380, `_saveEggBreakoutPanelTable` :3469, the panel-record loader :3483, `_savePanelTableWithSamples` :3611, `_saveChickWeightPanelSamples` :3633, `_breakoutBenchmarkForDraft` :4021, plus `_PanelSavePair` and `_BreakoutHierarchyPath` :4793 (move both private classes with the cluster).

- [ ] **Step 1: Enumerate real dependencies** — before moving, list every provider field/method the cluster reads. Each becomes either a constructor repo or an explicit `savePanelTables` parameter. Write the list into the coordinator's doc comment.
- [ ] **Step 2: Move verbatim** — bodies unchanged, ordering of operations unchanged (delete-then-insert sequences and transaction boundaries are behavior; preserve exactly).
- [ ] **Step 3: Wire the provider** — provider constructs one coordinator (lazily, with its existing repo instances) and `_saveSamplesInternal` delegates to `savePanelTables(...)`. Public provider API unchanged.
- [ ] **Step 4: Gate hard** — `flutter analyze && flutter test`, then additionally run the focused save suites: `flutter test test/features/audits/`. Expected: all green. STOP on any failure; revert the commit rather than patching forward if the failure is not an obvious rename slip.
- [ ] **Step 5: Commit** — `refactor(audits): extract AuditPanelSaveCoordinator from AuditProvider (move-only)`

**Phase 3 exit state:** `audit_provider.dart` ≈ 2,000 lines — lifecycle, drafts/tabs, chick-weight sample management, autosave, and thin delegation. That is an acceptable resting size; further splitting (chick-weight mixin) is optional and **not** in this plan (YAGNI until it hurts).

---

## Phase 4 — Split `stub_sections.dart` honestly

[stub_sections.dart](../../../lib/features/dashboard/widgets/sections/stub_sections.dart) is 2,837 lines of fully-implemented dashboard sections under a name that says "stub". Split it along its existing class boundaries; the sibling `egg_storage_station_section.dart` already models the target pattern.

### Task 4.1: One file per section, shared helpers extracted

**Files:**
- Create: `lib/features/dashboard/widgets/sections/section_shared.dart` (helpers `_sectionHeader` :22, `_metricRow` :32, `_emptySection` :66, `_photoSection` :86 → public `sectionHeader`, `metricRow`, `emptySection`, `photoSection`)
- Create: `lib/features/dashboard/widgets/sections/chick_quality_section.dart` (`ChickQualitySection` :106 + its private tabs `_WeightsTab` :171, `_PasgarTab` :223, `_PasgarInterpretationCard` :298, `_PasgarDefectRow` :343, `_CvtTab` :421, `_YfbmTab` :460, `_CulledChicksTab` :514)
- Create: `lib/features/dashboard/widgets/sections/egg_storage_section.dart` (`EggStorageSection` :598 + `_EggStorageHero` :1195, `_EstReadingsGridCard` :1313, `_EstSummaryCard` :1380, `_EstSummaryMetric` :1538, `_EstGrid` :1610, `_EstGridRow` :1685, `_EstReadingCell` :1732, `_EstPhotoPlaceholder` :1797)
- Create: `lib/features/dashboard/widgets/sections/egg_quality_section.dart` (`EggQualitySection` :698 + `_EggQualityHero` :757, `_EggWeightsQualityCard` :874, `_EggUvQualityCard` :983, `_QualitySummaryMetric` :1081, `_QualitySummaryCard` :1095, `_EggInfoValue` :1819, `_EggInfoRowCard` :1826)
- Create: additional `<name>_section.dart` files for every remaining public section class past line 1900 (enumerate with `grep -n "^class [A-Z]" stub_sections.dart` during execution; same pattern)
- Delete: `lib/features/dashboard/widgets/sections/stub_sections.dart`
- Modify: every importer (`grep -rln "stub_sections.dart" lib test`) to import the specific section files.

**Interfaces:**
- Consumes: nothing new. Produces: same public classes, new import paths.

- [ ] **Step 1: Extract `section_shared.dart`** — move the four helpers, publicize names, keep bodies verbatim.
- [ ] **Step 2: Move each public section class + its private widget satellites** into its own file, importing `section_shared.dart`. Private `_Foo` classes stay private — they move with their sole consumer.
- [ ] **Step 3: Rewrite imports at all call sites; delete `stub_sections.dart`.**
- [ ] **Step 4: Gate** — `flutter analyze && flutter test`. Dashboard widget tests must be untouched-green.
- [ ] **Step 5: Commit** — `refactor(dashboard): split stub_sections.dart into per-section files`

---

## Phase 5 — Scope audit-flow providers (needs human decision)

`app.dart:71` builds 11 root-level `ChangeNotifierProvider`s, all alive for the whole app run. The audit-flow trio (`AuditProvider`, `AuditSessionProvider`, `GoveeCaptureProvider`) is only consumed inside the audit flow + `audit_detail_screen`. Scoping them to the audit navigation subtree frees their state between audits and kills app-wide rebuild exposure.

**Decision required before executing:** current behavior means audit state **survives navigating away** (leave mid-audit, come back, state intact via root provider + autosave). Scoping changes that lifecycle: state would rebuild from DB on re-entry. Autosave (`flushAutosave`, `unsaved_changes_guard.dart`) probably makes this safe, but it is a **behavior change**, unlike everything above. Present this trade-off to the human; skip the phase entirely if mid-audit-state-survival matters more than memory/rebuild hygiene.

### Task 5.1 (if approved): Move the trio under the audit route

- [ ] **Step 1:** Identify the audit flow entry widget (`audit_context_screen.dart` / `audit_session_screen.dart` route push in `home_screen.dart` — confirm by reading navigation).
- [ ] **Step 2:** Wrap that route's builder in `MultiProvider` with the three ChangeNotifierProviders; remove them from `app.dart`.
- [ ] **Step 3:** `audit_detail_screen.dart` (customers feature) also consumes `AuditProvider` — give it its own scoped provider instance at its route push.
- [ ] **Step 4:** Manual verification in the web preview (`make restart-web`) per repo flow: start audit → enter data → navigate home → re-enter → confirm autosaved data reloads. Plus full `flutter analyze && flutter test` gate (widget tests inject fakes; per repo test conventions use bounded pumps, not `pumpAndSettle`).
- [ ] **Step 5:** Commit — `refactor(app): scope audit-flow providers to audit routes`

---

## Explicitly deferred (separate plans, on request)

- **Screen splits**: `hatch_analysis_screen.dart` (3,783), `lab_analysis_screen.dart` (2,967), `egg_storage_screen.dart` (2,715), `chick_quality_screen.dart` (2,020). Same move-only pattern as Phase 4 but each screen deserves its own plan — widget trees there interleave with provider calls and per-screen state.
- **Chick-weight sample mixin** out of `AuditProvider` (only if the ~2,000-line resting size still hurts after Phase 3).
- **`_notifyListeners` granularity** (29 call sites → selector-based rebuild narrowing). Perf work; measure first, don't assume.

## Execution order & stop rules (summary)

| Phase | Risk | Gate | Proceed condition |
|---|---|---|---|
| 0 hygiene | none | git status | always |
| 1 parity net | none (test-only) | analyze+test | STOP+report if parity fails |
| 2 pure extractions (4 tasks) | low | analyze+test per task | each task green |
| 3 save coordinator | **high-care** | analyze+test+focused suites | human go-ahead first |
| 4 sections split | low | analyze+test | after 2 (3 not required) |
| 5 provider scoping | behavior change | manual preview + suite | human decision required |
