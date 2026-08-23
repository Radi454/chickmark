# Egg Quality Sampling Stability and Egg Grading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Egg Quality comparison rows keep their identity and values across add / switch / rename / remove / save / reopen, and add a per-sample visual egg-grading section that reuses that same sample identity.

**Architecture:** Phase A (v61) persists the sample metadata that is currently re-derived on reopen, and makes the `egg_quality` panel row keyed by its own stable id instead of by its hierarchy columns. Phase B (v62) adds grading on top: summary columns and a JSON mirror on `egg_quality`, a seeded local defect catalogue, and a denormalized child table `egg_quality_defect_counts` joined by defect **code** for later analytics.

**Tech Stack:** Flutter, Dart, `provider`, `sqflite` (device) / `sqflite_common_ffi` (tests), `mocktail`, Supabase Postgres + PostgREST.

**Spec:** `docs/superpowers/specs/2026-08-23-egg-quality-sampling-and-grading-design.md`

## Global Constraints

- Local SQLite columns are **camelCase**. The Supabase mirror is **snake_case**. Conversion is automatic via `toSupabaseUpsertPayload` / `_supabaseSnakeCase` — never hand-write a mapper.
- A local column with no matching cloud column makes PostgREST reject the **entire batch** for that table. Every cloud migration in this plan is applied **before** the client code that writes the column ships.
- Every new column in this plan is **nullable**. No `NOT NULL` without a default, no backfill, no destructive migration, no table rebuild.
- Panel-table columns are reconciled on every database open by `_ensurePanelSampleSchemaColumns`, so adding to `PanelSampleSchema` or `_panelContextColumnDefinitions` needs no version bump — but this plan still bumps the version so the change is diagnosable.
- Schema version: currently `60` in `lib/data/database/database_helper.dart:47`. Phase A → `61`. Phase B → `62`.
- A new non-panel table MUST be registered in **both** `DatabaseHelper._criticalTables` (line 191) and `DatabaseHelper._criticalColumns` (line 250), or it can silently fail to exist after a repair pass.
- SQLite `ON DELETE CASCADE` does **not** queue sync tombstones. Child-row deletes go through the repository, which calls `SyncTombstoneRepository.queueDeletesWithExecutor`.
- `docs/LIVING_SPEC.md` and `docs/CHANGELOG.md` must be updated **in the same commit** as any behaviour change (project CLAUDE.md rule). Each task below that changes behaviour includes the doc edit in its commit step.
- **Do not change `egg_storage` measurement logic.** Do not enable tray, trolley, or machine comparison scopes for the egg station.
- Run the full test file after each task: `flutter test <path>`. Run `flutter analyze` before each commit; it must be clean.

---

# Phase A — v61 Sampling Stability

### Task A1: Panel metadata columns and schema version 61

**Files:**
- Modify: `lib/data/database/database_schema.dart:228-231` (`_panelContextColumnDefinitions`)
- Modify: `lib/data/database/database_helper.dart:47` (version), `:180-186` (`_onUpgrade` chain)
- Test: `test/data/database/panel_metadata_columns_test.dart` (create)
- Modify: `docs/LIVING_SPEC.md`, `docs/CHANGELOG.md`

**Interfaces:**
- Consumes: nothing.
- Produces: seven columns present on every panel table — `sampleMode TEXT`, `scopeType TEXT`, `sampleLabel TEXT`, `sampleIndex INTEGER`, `sourceDomain TEXT`, `actionDomain TEXT`, `recommendationTarget TEXT`. Every later task assumes these exist.

- [ ] **Step 1: Write the failing test**

Create `test/data/database/panel_metadata_columns_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    await useIsolatedAppDatabase();
  });

  tearDown(resetAppDatabase);

  test('every panel table carries the sample and domain metadata columns',
      () async {
    final db = await DatabaseHelper().db;
    const expected = {
      'sampleMode',
      'scopeType',
      'sampleLabel',
      'sampleIndex',
      'sourceDomain',
      'actionDomain',
      'recommendationTarget',
    };
    for (final panel in PanelSampleSchema.panels) {
      final columns = (await db.rawQuery(
        'PRAGMA table_info(${panel.tableName})',
      )).map((row) => row['name'] as String).toSet();
      expect(
        columns.containsAll(expected),
        isTrue,
        reason: '${panel.tableName} is missing ${expected.difference(columns)}',
      );
    }
  });

  test('database version is 61', () async {
    final db = await DatabaseHelper().db;
    expect(await db.getVersion(), 61);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/database/panel_metadata_columns_test.dart`
Expected: FAIL — missing columns, and version is 60.

- [ ] **Step 3: Add the columns**

In `lib/data/database/database_schema.dart`, replace `_panelContextColumnDefinitions`:

```dart
const _panelContextColumnDefinitions = [
  'storagePeriodDays INTEGER',
  'bmkAgeWeeks INTEGER',
  // v61: what this row represents, recorded explicitly instead of being
  // re-inferred from the hierarchy columns on reopen.
  'sampleMode TEXT',
  'scopeType TEXT',
  'sampleLabel TEXT',
  'sampleIndex INTEGER',
  // v61: which side of the operation owns the measurement, the fix, and the
  // recommendation. Free text so the vocabulary can grow without a migration.
  'sourceDomain TEXT',
  'actionDomain TEXT',
  'recommendationTarget TEXT',
];
```

- [ ] **Step 4: Bump the version and add the upgrade hop**

In `lib/data/database/database_helper.dart`, change `version: 60` to `version: 61`, then append to the `_onUpgrade` chain after the `oldVersion < 60` block:

```dart
    if (oldVersion < 61) {
      await _applyV61Upgrade(db);
    }
```

And add the handler alongside the other `_applyVNNUpgrade` methods:

```dart
  /// v61 adds the panel sample-metadata and domain columns. They are nullable
  /// and land through the same reconciliation pass that runs on every open, so
  /// this hop only has to make sure the pass runs before the app reads them.
  Future<void> _applyV61Upgrade(Database db) async {
    await ensurePanelSampleSchemaColumns(db);
  }
```

If `ensurePanelSampleSchemaColumns` is still private in `database_schema.dart` (`_ensurePanelSampleSchemaColumns`), export it by renaming to the public name and updating its call sites in that file.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/data/database/panel_metadata_columns_test.dart`
Expected: PASS (both tests).

- [ ] **Step 6: Update the schema-parity test**

`test/data/database/schema_parity_test.dart` names v60 in its test description and fixture. Update the description and target version to 61 so the "upgraded matches fresh create" guarantee still covers the new hop.

Run: `flutter test test/data/database/schema_parity_test.dart`
Expected: PASS.

- [ ] **Step 7: Docs and commit**

In `docs/LIVING_SPEC.md` and `docs/DATABASE_SPEC.md`, update the stated schema version to 61 and describe the seven new panel columns. Add to `docs/CHANGELOG.md` at the top:

```markdown
- 2026-08-23: Panel tables now record what each saved row represents
  (`sampleMode`, `scopeType`, `sampleLabel`, `sampleIndex`) and which side of
  the operation owns it (`sourceDomain`, `actionDomain`,
  `recommendationTarget`). All nullable; schema version 61.
```

```bash
flutter analyze
git add lib/data/database/database_schema.dart lib/data/database/database_helper.dart test/data/database/panel_metadata_columns_test.dart test/data/database/schema_parity_test.dart docs/
git commit -m "feat(db): add panel sample and domain metadata columns (v61)"
```

---

### Task A2: Cloud columns for the panel metadata

**Files:**
- Create: `supabase/migrations/20260823090000_panel_sample_metadata.sql`

**Interfaces:**
- Consumes: the column names from Task A1.
- Produces: matching snake_case columns on every mirrored panel table, so Task A4's writes can push.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260823090000_panel_sample_metadata.sql`:

```sql
-- v61 mirror: explicit sample identity and domain ownership on panel rows.
-- Additive and nullable. Local camelCase maps to these names automatically
-- through _supabaseSnakeCase, so the column names must match exactly.
do $$
declare
  panel text;
begin
  foreach panel in array array[
    'egg_storage',
    'egg_quality',
    'chick_quality',
    'chick_weights',
    'fresh_egg_breakout',
    'candled_egg_breakout',
    'residue_breakout',
    'setter_optimizing',
    'hatcher_optimizing'
  ]
  loop
    execute format('alter table public.%I
      add column if not exists sample_mode text,
      add column if not exists scope_type text,
      add column if not exists sample_label text,
      add column if not exists sample_index integer,
      add column if not exists source_domain text,
      add column if not exists action_domain text,
      add column if not exists recommendation_target text', panel);
  end loop;
end $$;
```

- [ ] **Step 2: Verify the panel list matches the code**

Run: `grep -n "tableName: '" lib/data/models/panel_sample_schema.dart`
Expected: exactly the nine names listed in the migration. Fix the migration if they differ.

- [ ] **Step 3: Apply the migration**

Apply via the Supabase MCP `apply_migration` tool with name `panel_sample_metadata`.

- [ ] **Step 4: Verify remotely**

Query via MCP `execute_sql`:

```sql
select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'egg_quality'
  and column_name in ('sample_mode','scope_type','sample_label','sample_index',
                      'source_domain','action_domain','recommendation_target')
order by column_name;
```
Expected: seven rows.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260823090000_panel_sample_metadata.sql
git commit -m "feat(cloud): mirror panel sample and domain metadata columns"
```

---

### Task A3: Make `egg_quality` keyed by row id, not by hierarchy

**Files:**
- Modify: `lib/data/repositories/panel_sample_repository.dart` (`_upsertById`, and add the id-keyed table set)
- Modify: `lib/data/database/database_schema.dart` (`_ensurePanelUniqueRowIndexes`, `_createPanelTable`)
- Test: `test/data/repositories/panel_sample_identity_test.dart` (create)

**Interfaces:**
- Consumes: nothing from A1/A2.
- Produces: `PanelSampleRepository.idKeyedPanelTables` — `Set<String>` containing `'egg_quality'`. `_upsertById` treats those tables as id-keyed: no hierarchy lookup, no hierarchy-based update, no identity merge.

- [ ] **Step 1: Write the failing test**

Create `test/data/repositories/panel_sample_identity_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

void main() {
  late Database db;
  late PanelSampleRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final helper = _MockDatabaseHelper();
    when(() => helper.db).thenAnswer((_) async => db);
    await db.execute('''CREATE TABLE egg_quality (
      id TEXT PRIMARY KEY,
      sessionId TEXT NOT NULL,
      customerId TEXT NOT NULL,
      date TEXT NOT NULL,
      house TEXT,
      setter TEXT,
      hatcher TEXT,
      trolley TEXT,
      tray TEXT,
      position TEXT,
      eggSampleSize INTEGER,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL,
      syncStatus TEXT NOT NULL DEFAULT 'pending',
      dirtyAt TEXT,
      lastSyncedAt TEXT,
      syncError TEXT
    )''');
    await db.execute('''CREATE TABLE sync_tombstones (
      id TEXT PRIMARY KEY,
      tableName TEXT NOT NULL,
      rowId TEXT NOT NULL,
      deletedAt TEXT NOT NULL,
      createdAt TEXT NOT NULL,
      syncedAt TEXT,
      lastError TEXT
    )''');
    repository = PanelSampleRepository(databaseHelper: helper);
  });

  tearDown(() async => db.close());

  Map<String, Object?> row(String id, {String? house, int? size}) => {
        'id': id,
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'date': '2026-08-23',
        'house': house,
        'eggSampleSize': size,
        'createdAt': '2026-08-23T00:00:00.000Z',
        'updatedAt': '2026-08-23T00:00:00.000Z',
      };

  test('two blank-house egg_quality rows in one session stay separate',
      () async {
    await repository.upsertRow('egg_quality', row('row-a', size: 10));
    await repository.upsertRow('egg_quality', row('row-b', size: 20));

    final saved = await db.query('egg_quality', orderBy: 'id ASC');
    expect(saved.map((r) => r['id']), ['row-a', 'row-b']);
    expect(saved.map((r) => r['eggSampleSize']), [10, 20]);
  });

  test('renaming a house updates the same row rather than creating one',
      () async {
    await repository.upsertRow('egg_quality', row('row-a', house: 'H1', size: 10));
    await repository.upsertRow('egg_quality', row('row-a', house: 'H7', size: 10));

    final saved = await db.query('egg_quality');
    expect(saved, hasLength(1));
    expect(saved.single['id'], 'row-a');
    expect(saved.single['house'], 'H7');
  });

  test('two rows may share a house without merging', () async {
    await repository.upsertRow('egg_quality', row('row-a', house: 'H1', size: 10));
    await repository.upsertRow('egg_quality', row('row-b', house: 'H1', size: 20));

    final saved = await db.query('egg_quality', orderBy: 'id ASC');
    expect(saved, hasLength(2));
    expect(saved.map((r) => r['eggSampleSize']), [10, 20]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/panel_sample_identity_test.dart`
Expected: FAIL — rows merge, because `_upsertById` resolves identity through `_rowIdForPanelIdentity` before falling back to the id.

- [ ] **Step 3: Add the id-keyed table set and short-circuit the hierarchy path**

In `lib/data/repositories/panel_sample_repository.dart`, add near the top of the class:

```dart
  /// Panel tables whose row identity is the row id itself, not the hierarchy
  /// tuple. `egg_quality` is here because a comparison row may legitimately
  /// have a blank or duplicated house, and matching on hierarchy makes two
  /// such rows overwrite each other.
  static const Set<String> idKeyedPanelTables = {'egg_quality'};
```

Then in `_upsertById`, immediately after `if (rowId == null) return;`, insert:

```dart
    if (idKeyedPanelTables.contains(table)) {
      final inserted = await executor.insert(
        table,
        filtered,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (inserted != 0) return;
      await executor.update(
        table,
        filtered,
        where: 'id = ?',
        whereArgs: [rowId],
      );
      return;
    }
```

Leave the existing hierarchy path untouched below it — every other panel table keeps today's behaviour.

- [ ] **Step 4: Stop creating the hierarchy unique index for `egg_quality`**

In `lib/data/database/database_schema.dart`, guard both index-creating sites. In `_createPanelTable`, change the unique-index block to:

```dart
  final uniqueIndexColumns = {'sessionId', ...panel.hierarchyColumnNames};
  if (!PanelSampleRepository.idKeyedPanelTables.contains(tableName) &&
      columns.containsAll(uniqueIndexColumns)) {
    await db.execute(_panelUniqueRowIndexSql(panel));
  }
```

In `_ensurePanelUniqueRowIndexes`, skip the same tables, and drop any index left over from before v61:

```dart
Future<void> _ensurePanelUniqueRowIndexes(DatabaseExecutor db) async {
  for (final panel in PanelSampleSchema.panels) {
    if (!await _tableExists(db, panel.tableName)) continue;
    if (PanelSampleRepository.idKeyedPanelTables.contains(panel.tableName)) {
      // Pre-v61 databases carry this index; it is what made two comparison
      // rows with a blank or duplicate house collide.
      await db.execute(
        'DROP INDEX IF EXISTS idx_${panel.tableName}_unique_row',
      );
      continue;
    }
    // ...existing body unchanged...
  }
}
```

Add the import for `panel_sample_repository.dart` if the file does not already have it. If that creates an import cycle, move `idKeyedPanelTables` onto `PanelSampleSchema` in `lib/data/models/panel_sample_schema.dart` instead and reference it from both places.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/data/repositories/panel_sample_identity_test.dart test/data/database/`
Expected: PASS. `schema_parity_test.dart` compares upgraded-vs-fresh, and both sides now lack the index, so it stays green.

- [ ] **Step 6: Docs and commit**

`docs/DATABASE_SPEC.md`: note that `egg_quality` is id-keyed and carries no hierarchy unique index. `docs/CHANGELOG.md`:

```markdown
- 2026-08-23: Egg Quality panel rows are now identified by their own row id
  instead of by their house/setter/hatcher values. Two comparison rows with a
  blank or repeated house no longer overwrite each other.
```

```bash
flutter analyze
git add lib/data/repositories/panel_sample_repository.dart lib/data/database/database_schema.dart test/data/repositories/panel_sample_identity_test.dart docs/
git commit -m "fix(egg): key egg_quality panel rows by row id"
```

---

### Task A4: Write the sample and domain metadata on save

**Files:**
- Modify: `lib/features/audits/services/audit_panel_save_coordinator.dart` (`_panelRecordForSamples`, `_panelSampleRecordForStationSample`, and the row builder)
- Modify: `lib/features/audits/logic/panel_value_builders.dart` (if the values are threaded through `panelValuesForDraft`)
- Test: `test/features/audits/egg_station_panel_persistence_test.dart` (extend)

**Interfaces:**
- Consumes: `PanelSampleRepository.idKeyedPanelTables` (A3), the seven columns (A1).
- Produces: saved `egg_quality` rows whose `id` equals `sample.id`, and whose `sampleMode` / `scopeType` / `sampleLabel` / `sampleIndex` / `sourceDomain` / `actionDomain` / `recommendationTarget` are populated. Task A5 reads them back.

- [ ] **Step 1: Write the failing test**

Append to `test/features/audits/egg_station_panel_persistence_test.dart`, inside the existing `main()` (the harness at the top of that file already builds the panel tables, the session, and the provider):

```dart
  test('saved egg_quality rows carry explicit sample and domain metadata',
      () async {
    provider.updateField('esEggSampleSize', 12);
    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.updateSampleMetadata({'houseNo': 'H4', 'houseLabel': 'House 4'});
    provider.updateField('esEggSampleSize', 34);
    await provider.saveSamplesWithResult(tabIndex: 0);

    final saved = await db.query('egg_quality', orderBy: 'sampleIndex ASC');
    expect(saved, hasLength(2));
    expect(saved.map((r) => r['sampleMode']),
        ['comparison', 'comparison']);
    expect(saved.map((r) => r['scopeType']), ['house', 'house']);
    expect(saved.map((r) => r['sampleIndex']), [1, 2]);
    expect(saved.last['sampleLabel'], 'H4');
    for (final row in saved) {
      expect(row['sourceDomain'], 'hatchery');
      expect(row['actionDomain'], 'farm');
      expect(row['recommendationTarget'], 'farm');
    }

    final storage = await db.query('egg_storage');
    for (final row in storage) {
      expect(row['sampleMode'], 'pooled');
      expect(row['scopeType'], 'pool');
      expect(row['sourceDomain'], 'hatchery');
      expect(row['actionDomain'], 'hatchery');
      expect(row['recommendationTarget'], 'hatchery');
    }
  });

  test('egg_quality row id is the station sample id', () async {
    provider.updateField('esEggSampleSize', 12);
    await provider.saveSamplesWithResult(tabIndex: 0);

    final saved = await db.query('egg_quality');
    expect(saved.single['id'], provider.activeStationSample.id);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/audits/egg_station_panel_persistence_test.dart`
Expected: FAIL — the metadata columns are null and the row id is the composed `<panelId>:<sampleId>` string.

- [ ] **Step 3: Add the domain lookup**

In `lib/features/audits/services/audit_panel_save_coordinator.dart`, add a top-level helper near the other classification helpers:

```dart
/// Which side of the operation a panel's measurement, corrective action, and
/// recommendation belong to. Egg storage is measured and fixed inside the
/// hatchery; egg quality is measured in the hatchery but caused and fixed at
/// the breeder farm, so its recommendations target the farm.
({String source, String action, String target})? _domainsForPanel(
  String tableName,
) {
  return switch (tableName) {
    'egg_storage' => (
        source: 'hatchery',
        action: 'hatchery',
        target: 'hatchery',
      ),
    'egg_quality' => (source: 'hatchery', action: 'farm', target: 'farm'),
    _ => null,
  };
}
```

- [ ] **Step 4: Write the metadata into the saved row**

In `_panelSampleRecordForStationSample`, change the id line from the composed form to the sample id for id-keyed tables:

```dart
    final rowId = PanelSampleRepository.idKeyedPanelTables.contains(tableName)
        ? sample.id
        : '$panelId:${sample.id}';
```

and use `rowId` for `PanelSampleRecord.id`.

Then, in the place where the panel row map is assembled for writing (the `values` passed to `savePanelWithSamples`), merge in:

```dart
    final domains = _domainsForPanel(tableName);
    final metadata = <String, Object?>{
      'sampleMode': sample.sampleMode,
      'scopeType': _scopeTypeForPanel(tableName, sample, draft).dbValue,
      'sampleLabel': sample.sampleLabel,
      'sampleIndex': sample.sampleIndex,
      if (domains != null) ...{
        'sourceDomain': domains.source,
        'actionDomain': domains.action,
        'recommendationTarget': domains.target,
      },
    };
```

For `egg_storage`, which is pool-only, `_scopeTypeForPanel` already returns `SamplingLayer.pool` and the sample mode is `pooled`, so no special case is needed — do not add one.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/audits/egg_station_panel_persistence_test.dart`
Expected: PASS.

- [ ] **Step 6: Run the neighbouring suites for regressions**

Run: `flutter test test/features/audits/ test/data/repositories/`
Expected: PASS. The chick, breakout, setter, and hatcher persistence tests must stay green — they share this coordinator.

- [ ] **Step 7: Docs and commit**

`docs/LIVING_SPEC.md`: describe what the egg station now writes. `docs/CHANGELOG.md`:

```markdown
- 2026-08-23: Saved egg panel rows now record their sampling mode, scope,
  label, and order, plus which side of the operation owns the measurement,
  the fix, and the recommendation.
```

```bash
flutter analyze
git add lib/features/audits/services/audit_panel_save_coordinator.dart test/features/audits/egg_station_panel_persistence_test.dart docs/
git commit -m "feat(egg): persist sample and domain metadata on egg panel rows"
```

---

### Task A5: Read the metadata back on reopen, with fallback inference

**Files:**
- Modify: `lib/features/audits/screens/audit_session_screen.dart:1677-1745` (`_sampleFromPanelRow`, `_auditMapFromPanelRows`, `_eggAuditDraftsFromPanelRows`)
- Modify: `lib/data/repositories/panel_sample_repository.dart` (`_panelOrderByForColumns`)
- Test: `test/features/audits/egg_quality_reopen_test.dart` (create)

**Interfaces:**
- Consumes: rows written by A4.
- Produces: reopen that restores mode, scope, label, and order from the columns when present, and reproduces today's inference when they are null.

- [ ] **Step 1: Write the failing test**

Create `test/features/audits/egg_quality_reopen_test.dart`. Reuse the in-memory harness from `egg_station_panel_persistence_test.dart` (copy the `setUp` block verbatim), then:

```dart
  test('reopen restores saved mode, scope, label and order', () async {
    provider.updateField('esEggSampleSize', 11);
    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.updateSampleMetadata({'houseNo': 'H9', 'houseLabel': 'House 9'});
    provider.updateField('esEggSampleSize', 22);
    await provider.saveSamplesWithResult(tabIndex: 0);

    final reopened = await reopenEggStation(db, 'session-egg-db');

    expect(reopened.stationSamples.map((s) => s.sampleLabel), ['H1', 'H9']);
    expect(reopened.stationSamples.map((s) => s.sampleIndex), [1, 2]);
    expect(
      reopened.stationSamples.map((s) => s.sampleMode),
      ['comparison', 'comparison'],
    );
    expect(reopened.stationAudits.map((a) => a.esEggSampleSize), [11, 22]);
  });

  test('legacy rows with null metadata still reopen by inference', () async {
    await db.insert('egg_quality', {
      'id': 'legacy-1',
      'sessionId': 'session-egg-db',
      'customerId': 'customer-egg-db',
      'flockId': 'flock-egg-db',
      'date': '2026-05-15',
      'house': 'H3',
      'eggSampleSize': 44,
      'createdAt': '2026-05-15T00:00:00.000Z',
      'updatedAt': '2026-05-15T00:00:00.000Z',
    });

    final reopened = await reopenEggStation(db, 'session-egg-db');

    expect(reopened.stationSamples.single.sampleMode, 'comparison');
    expect(reopened.stationSamples.single.sampleKind, 'house');
    expect(reopened.stationSamples.single.sampleLabel, 'H3');
  });

  test('a blank-house comparison row does not reopen as pooled', () async {
    await db.insert('egg_quality', {
      'id': 'explicit-1',
      'sessionId': 'session-egg-db',
      'customerId': 'customer-egg-db',
      'flockId': 'flock-egg-db',
      'date': '2026-05-15',
      'house': null,
      'sampleMode': 'comparison',
      'scopeType': 'house',
      'sampleLabel': 'H1',
      'sampleIndex': 1,
      'eggSampleSize': 55,
      'createdAt': '2026-05-15T00:00:00.000Z',
      'updatedAt': '2026-05-15T00:00:00.000Z',
    });

    final reopened = await reopenEggStation(db, 'session-egg-db');

    expect(reopened.stationSamples.single.sampleMode, 'comparison');
    expect(reopened.stationSamples.single.sampleLabel, 'H1');
  });
```

The reconstruction logic currently lives in the private `_StationFrameState`, which a unit test cannot reach.

- [ ] **Step 2: Extract the reconstruction into a testable unit**

Create `lib/features/audits/logic/egg_station_reconstruction.dart` and move these members out of `_StationFrameState` in `audit_session_screen.dart` as top-level functions, unchanged in behaviour: `_auditDraftsFromPanelRows`, `_auditMapFromPanelRows`, `_eggAuditDraftsFromPanelRows`, `_mergePanelRowIntoAuditMap`, `_stationSamplesFromPanelRows`, `_stationSampleSourceRows`, `_sampleFromPanelRow`, `_panelRowIdentityKey`, `_rowHasHierarchy`, `_scopeTypeForRow`, `_sampleLabelForRow`, `_sectorTypeForTable`, `_sampleKindForScope`, `_comparisonTypeForScope`, `_sampleTypeForTable`, `_breakoutTypeForTable`, and the `_asInt` / `_asText` / `_parseDate` helpers they use.

Give the module one public entry point:

```dart
class StationReconstruction {
  const StationReconstruction({
    required this.stationAudits,
    required this.stationSamples,
  });

  final List<AuditModel> stationAudits;
  final List<StationSampleModel> stationSamples;
}

StationReconstruction reconstructStation({
  required String stationKey,
  required String sessionId,
  required AuditContextData context,
  required Map<String, List<Map<String, dynamic>>> rowsByPanel,
}) { /* the moved bodies, called in the same order as _loadInitialData */ }
```

`_StationFrameState._loadInitialData` then calls `reconstructStation(...)` and keeps its existing try/catch and `safeDebugLog` degradation. Also add to the new file:

```dart
Future<StationReconstruction> reopenEggStation(
  Database db,
  String sessionId, {
  AuditContextData? context,
}) async { /* query egg_storage + egg_quality, then call reconstructStation */ }
```

This is a pure move plus one wrapper. Do not change any behaviour in this step.

Run: `flutter test test/features/audits/`
Expected: PASS — the move is behaviour-neutral.

- [ ] **Step 3: Run the new test to verify it fails**

Run: `flutter test test/features/audits/egg_quality_reopen_test.dart`
Expected: FAIL — order and label come from position and the raw house value, and the blank-house comparison row reopens as pooled.

- [ ] **Step 4: Prefer the explicit columns**

In `egg_station_reconstruction.dart`, change `_sampleFromPanelRow`:

```dart
  final inferredScope = _scopeTypeForRow(row);
  final scopeType = _asText(row['scopeType']) ?? inferredScope;
  final sampleMode = _asText(row['sampleMode']) ??
      (_rowHasHierarchy(row)
          ? StationSampleModel.sampleModeComparison
          : StationSampleModel.sampleModePooled);
  final sampleIndex = _asInt(row['sampleIndex']) ?? fallbackIndex;
  final sampleLabel =
      _asText(row['sampleLabel']) ?? _sampleLabelForRow(row) ?? 'Sample $sampleIndex';
```

and in `_auditMapFromPanelRows` change the mode line:

```dart
    final mode = _asText(first['sampleMode']) ??
        (_rowHasHierarchy(first) ? 'comparison' : 'pool');
```

Note the two vocabularies: `StationSampleModel` uses `pooled`, `AuditModel.sampleMode` uses `pool`. Map `comparison` → `comparison` and anything else → `pool` when writing the draft map; do not pass `pooled` through.

- [ ] **Step 5: Order by the saved index**

In `lib/data/repositories/panel_sample_repository.dart`, extend `_panelOrderByForColumns` so that when the table has a `sampleIndex` column it orders `sampleIndex ASC, createdAt ASC, id ASC`, and otherwise keeps today's ordering. In `_eggAuditDraftsFromPanelRows`, sort `qualityRows` by that same key before building drafts, so drafts and samples share one order.

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/features/audits/egg_quality_reopen_test.dart test/features/audits/`
Expected: PASS.

- [ ] **Step 7: Docs and commit**

`docs/LIVING_SPEC.md`: describe the explicit-first, infer-as-fallback read path. `docs/CHANGELOG.md`:

```markdown
- 2026-08-23: Reopening an Egg audit now restores each sample's mode, scope,
  label and order from what was saved. Audits saved before this change still
  reopen using the old inference.
```

```bash
flutter analyze
git add lib/features/audits/logic/egg_station_reconstruction.dart lib/features/audits/screens/audit_session_screen.dart lib/data/repositories/panel_sample_repository.dart test/features/audits/egg_quality_reopen_test.dart docs/
git commit -m "feat(egg): restore sample identity from saved metadata on reopen"
```

---

### Task A6: Stop the provider re-deriving house identity

**Files:**
- Modify: `lib/features/audits/providers/audit_provider.dart:1942-2060` (`_syncStationSampleFromDraft`), `:1050-1130` (`_removeEggQualityScopeIndexes`), `:1163-1200` (`removeActiveSample`)
- Test: `test/features/audits/audit_provider_sample_mode_test.dart` (extend)

**Interfaces:**
- Consumes: nothing new.
- Produces: house identity owned by the sample. A single remaining Egg Quality house row keeps `sampleMode == 'comparison'`.

- [ ] **Step 1: Write the failing test**

Append to `test/features/audits/audit_provider_sample_mode_test.dart`:

```dart
  test('a house named like a generated default is not regenerated', () {
    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.switchSample(1);
    provider.updateSampleMetadata({'houseNo': 'H1', 'houseLabel': 'House 1'});
    provider.updateField('esEggSampleSize', 7);

    expect(provider.stationSamples[1].houseNo, 'H1');
    expect(provider.stationSamples[1].sampleLabel, 'H1');
  });

  test('removing down to one house row keeps comparison mode', () {
    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.switchSample(1);
    provider.removeActiveEggQualityScopeSample(
      StationSampleModel.sampleKindHouse,
    );

    expect(provider.stationSamples, hasLength(1));
    expect(
      provider.stationSamples.single.sampleMode,
      StationSampleModel.sampleModeComparison,
    );
    expect(provider.stationSamples.single.sampleKind,
        StationSampleModel.sampleKindHouse);
  });

  test('switching houses does not move entered values between rows', () {
    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.updateField('esEggSampleSize', 10);
    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.updateField('esEggSampleSize', 20);
    provider.switchSample(0);

    expect(provider.activeDraft.esEggSampleSize, 10);
    provider.switchSample(1);
    expect(provider.activeDraft.esEggSampleSize, 20);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/audits/audit_provider_sample_mode_test.dart`
Expected: FAIL on the first two — `H1` at index 1 is treated as a generated default and regenerated, and the last remaining row collapses to pooled.

- [ ] **Step 3: Own the house identity on the sample**

In `_syncStationSampleFromDraft`, replace the `keepCustomEggHouseMetadata` logic. For an Egg comparison house sample, keep the existing `houseNo`, `houseLabel`, and `sampleLabel` **whenever the existing sample already has a house value**, with no default-value sniffing:

```dart
    final keepCustomEggHouseMetadata =
        keepGeneratedEggHouseMetadata && hasText(existing.houseNo);
```

Delete `_defaultEggHouseNo` and `_defaultEggHouseLabel` and every remaining reference to them. Leave the chick-weight equivalents (`_defaultOrBlankHouseNo`, `_defaultOrBlankHouseLabel`) alone — they belong to a different station.

- [ ] **Step 4: Stop the forced collapse to pooled**

In `_removeEggQualityScopeIndexes`, the `legacyMode` calculation currently collapses to `SampleMode.pool` when one row remains and no house sample survives. Change the Egg branch so that a surviving house sample keeps `SampleMode.compare` regardless of count:

```dart
    final legacyMode = keepsEggQualityScope || _drafts.length > 1
        ? SampleMode.compare
        : SampleMode.pool;
```

In `removeActiveSample`, apply the same rule for the Egg context:

```dart
    final keepsEggHouseScope = _context?.auditType == 'Egg' &&
        _stationSamples.any(
          (sample) => sample.sampleKind == StationSampleModel.sampleKindHouse,
        );
    final legacyMode = _drafts.length == 1 && !keepsEggHouseScope
        ? SampleMode.pool
        : SampleMode.compare;
```

- [ ] **Step 4a: Recheck the empty case**

`_removeEggQualityScopeIndexes` still calls `_resetEggQualityToPooled` when **no** rows are retained. That path is correct and must stay: zero comparison rows genuinely means pooled.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/audits/audit_provider_sample_mode_test.dart test/features/audits/sample_mode_controls_test.dart test/features/audits/sample_mode_test.dart`
Expected: PASS.

- [ ] **Step 6: Run the wider suite**

Run: `flutter test test/features/audits/`
Expected: PASS.

- [ ] **Step 7: Docs and commit**

`docs/CHANGELOG.md`:

```markdown
- 2026-08-23: An Egg Quality house sample keeps the house number the auditor
  typed, even when it matches the number the app would have generated, and the
  last remaining house sample no longer silently turns back into a pooled one.
```

```bash
flutter analyze
git add lib/features/audits/providers/audit_provider.dart test/features/audits/ docs/
git commit -m "fix(egg): let the sample own its house identity"
```

---

### Task A7: Sample Mode bar and the Compare → Pooled confirmation

**Files:**
- Modify: `lib/features/audits/screens/egg_storage_screen.dart` (`_buildEggSampleControls` at :1027, `_buildSampleControlCard` at :1045, `_hasDuplicateEggHouse` at :1411)
- Modify: `lib/features/audits/providers/audit_provider.dart` (`setStationSampleMode` at :432)
- Test: `test/features/audits/egg_sample_mode_bar_test.dart` (create)

**Interfaces:**
- Consumes: provider state from A6.
- Produces: `_buildSampleModeBar({required bool editable})` in the Egg screen, and a `confirmDiscardHouses` callback the provider consults before collapsing.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/audits/egg_sample_mode_bar_test.dart`. Follow the existing pattern in `test/features/audits/egg_storage_screen_test.dart` — inject fake repositories and use bounded `pump()` calls, never `pumpAndSettle()`, because a real `sqflite` database inside `testWidgets` hangs under `FakeAsync`.

```dart
  testWidgets('egg storage shows a disabled pool-only sample mode bar',
      (tester) async {
    await pumpEggStation(tester);

    expect(find.text('Sample mode'), findsWidgets);
    expect(find.text('Pool'), findsWidgets);
    expect(
      find.text('Egg storage is always measured as one pool.'),
      findsOneWidget,
    );
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Pool').first,
    );
    expect(chip.onSelected, isNull);
  });

  testWidgets('egg quality offers exactly pooled and compare by house',
      (tester) async {
    await pumpEggStation(tester);
    await tester.tap(find.text('Egg quality'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.widgetWithText(ChoiceChip, 'Pooled'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Compare by house'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Compare by tray'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Compare by trolley'), findsNothing);
  });

  testWidgets('switching back to pooled asks before discarding houses',
      (tester) async {
    await pumpEggStation(tester);
    await tester.tap(find.text('Egg quality'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Compare by house'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Pooled'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('will be discarded'), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/audits/egg_sample_mode_bar_test.dart`
Expected: FAIL — no such bar exists.

- [ ] **Step 3: Build the bar**

In `egg_storage_screen.dart`, add:

```dart
  Widget _buildSampleModeBar(
    AuditProvider auditProvider, {
    required bool editable,
  }) {
    final isCompare = editable && auditProvider.isCompareMode;
    return _buildSampleControlCard(
      title: 'Sample mode',
      note: editable ? null : 'Egg storage is always measured as one pool.',
      child: Row(
        children: [
          if (!editable)
            ChoiceChip(label: const Text('Pool'), selected: true)
          else ...[
            ChoiceChip(
              label: const Text('Pooled'),
              selected: !isCompare,
              onSelected: auditProvider.isReadOnly
                  ? null
                  : (_) => _requestPooledMode(auditProvider),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Compare by house'),
              selected: isCompare,
              onSelected: auditProvider.isReadOnly
                  ? null
                  : (_) => auditProvider.addEggQualityScopeSample(
                        StationSampleModel.sampleKindHouse,
                      ),
            ),
          ],
        ],
      ),
    );
  }
```

`ChoiceChip` with a null `onSelected` renders disabled, which is what the Egg Storage test asserts.

Render `_buildSampleModeBar(auditProvider, editable: false)` above the Egg Storage fields, and `_buildSampleModeBar(auditProvider, editable: true)` directly above the existing `_buildEggSampleControls` house-chip strip in Egg Quality. Show the house-chip strip only when `auditProvider.isCompareMode`.

- [ ] **Step 4: Add the confirmation**

```dart
  Future<void> _requestPooledMode(AuditProvider auditProvider) async {
    if (!auditProvider.isCompareMode) return;
    final houseCount = auditProvider.stationSamples
        .where((s) => s.sampleKind == StationSampleModel.sampleKindHouse)
        .length;
    if (houseCount > 1) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Switch to a pooled sample?'),
          content: Text(
            '$houseCount house samples are recorded. The first one is kept as '
            'the pooled sample and the other ${houseCount - 1} will be '
            'discarded.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard and pool'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    auditProvider.setStationSampleMode(StationSampleModel.sampleModePooled);
  }
```

`setStationSampleMode` already keeps `_drafts.first`, records the dropped ids in `_removedStationSampleIds`, and lets the save path delete their rows. No provider change is needed for the discard itself.

- [ ] **Step 5: Wire duplicate-house validation**

The Egg Quality house identity field at `egg_storage_screen.dart:1221` currently calls `auditProvider.updateSampleMetadata({'houseNo': value.trim()})` unconditionally. Guard it with the existing `_hasDuplicateEggHouse(provider, value)` helper, and show the same inline error the scope dialog uses at `:1396`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/features/audits/egg_sample_mode_bar_test.dart test/features/audits/egg_storage_screen_test.dart`
Expected: PASS.

- [ ] **Step 7: Docs and commit**

`docs/LIVING_SPEC.md`: document both bars. `docs/CHANGELOG.md`:

```markdown
- 2026-08-23: Egg Storage now shows a greyed-out "Pool" sample-mode bar so it
  is clear it is always one pool, and Egg Quality has a real Pooled /
  Compare by house switch. Switching back to Pooled asks first, and duplicate
  house numbers are rejected as they are typed.
```

```bash
flutter analyze
git add lib/features/audits/screens/egg_storage_screen.dart test/features/audits/egg_sample_mode_bar_test.dart docs/
git commit -m "feat(egg): add sample mode bars to the egg station"
```

---

# Phase B — v62 Egg Grading

### Task B1: Cloud schema for grading

**Files:**
- Create: `supabase/migrations/20260823100000_egg_grading.sql`

**Interfaces:**
- Consumes: the `egg_quality` cloud table.
- Produces: eight grading columns on `egg_quality` and the `egg_quality_defect_counts` table with RLS and a `customer_id` trigger. Task B6 pushes into them.

- [ ] **Step 1: Read the existing tenant-child trigger**

Run: `grep -rn "customer_id" supabase/migrations/20260722143914_storage_rls_and_fk_indexes.sql | head -20`

Copy whatever trigger-function pattern that file uses for deriving `customer_id` from a parent edge. Do not invent a new one.

- [ ] **Step 2: Write the migration**

Create `supabase/migrations/20260823100000_egg_grading.sql`:

```sql
-- v62: visual egg grading, owned by an egg_quality sample row.
alter table public.egg_quality
  add column if not exists grading_sample_size integer,
  add column if not exists grading_rejected_count integer,
  add column if not exists grading_acceptable_count integer,
  add column if not exists grading_rejected_pct double precision,
  add column if not exists grading_acceptable_pct double precision,
  add column if not exists grading_defects_json text,
  add column if not exists grading_top_defect_code text,
  add column if not exists grading_top_defect_pct double precision;

create table if not exists public.egg_quality_defect_counts (
  id text primary key,
  egg_quality_id text not null,
  session_id text not null,
  customer_id text not null,
  flock_id text,
  hatchery_id text,
  date text not null,
  scope_type text,
  house_key text,
  sample_label text,
  defect_code text not null,
  defect_category text,
  is_reject integer,
  count integer not null default 0,
  pct_of_sample double precision,
  notes text,
  sort_order integer not null default 0,
  created_at text not null,
  updated_at text not null,
  unique (egg_quality_id, defect_code),
  foreign key (egg_quality_id) references public.egg_quality(id) on delete cascade,
  foreign key (session_id) references public.audit_sessions(id) on delete cascade,
  foreign key (customer_id) references public.customers(id) on delete cascade,
  foreign key (flock_id) references public.flocks(id) on delete cascade
);

create index if not exists idx_eqdc_parent
  on public.egg_quality_defect_counts(egg_quality_id);
create index if not exists idx_eqdc_dashboard
  on public.egg_quality_defect_counts(customer_id, flock_id, date, defect_code);

alter table public.egg_quality_defect_counts enable row level security;
create policy authenticated_all on public.egg_quality_defect_counts
  for all to authenticated using (true) with check (true);
```

Then append the `customer_id` before-write trigger, in the exact shape found in Step 1, deriving `customer_id` from `egg_quality.customer_id` via `new.egg_quality_id`.

- [ ] **Step 3: Apply and verify**

Apply via MCP `apply_migration` with name `egg_grading`. Then verify with MCP `execute_sql`:

```sql
select column_name from information_schema.columns
where table_schema='public' and table_name='egg_quality_defect_counts'
order by ordinal_position;
```
Expected: every column above.

- [ ] **Step 4: Check the advisors**

Run MCP `get_advisors` with type `security`. Expected: no new findings for `egg_quality_defect_counts`. If RLS is flagged, fix it in this migration before moving on.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260823100000_egg_grading.sql
git commit -m "feat(cloud): add egg grading columns and defect-count table"
```

---

### Task B2: Defect catalogue and local schema (v62)

**Files:**
- Create: `lib/features/audits/models/egg_grading.dart`
- Create: `lib/data/database/seeds/egg_defect_type_seeds.dart`
- Modify: `lib/data/database/database_schema.dart` (create the two tables)
- Modify: `lib/data/database/database_helper.dart` (version 62, `_criticalTables`, `_criticalColumns`, upgrade hop)
- Modify: `lib/data/models/panel_sample_schema.dart` (`egg_quality` measurement columns)
- Test: `test/features/audits/egg_grading_model_test.dart`, `test/data/database/egg_grading_schema_test.dart` (create both)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `kEggDefectTypes` — `List<EggDefectType>`, each with `code`, `name`, `category`, `isReject`, `description`, `imageAsset`, `sortOrder`.
  - `EggGradingSummary.fromCounts({required int sampleSize, required int rejectedCount, required Map<String, int> counts})` with fields `sampleSize`, `rejectedCount`, `acceptableCount`, `rejectedPct`, `acceptablePct`, `topDefectCode`, `topDefectPct`, and `String? get encodedJson`, plus `EggGradingSummary.fromJson(String? source, {int? sampleSize, int? rejectedCount})`.
  - `EggGradingValidation.validate(...)` returning `List<String>` of messages.
  - Tables `egg_defect_types` and `egg_quality_defect_counts`; the eight `egg_quality` grading columns.

- [ ] **Step 1: Write the failing model test**

Create `test/features/audits/egg_grading_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/models/egg_grading.dart';

void main() {
  test('catalogue codes are unique and non-empty', () {
    final codes = kEggDefectTypes.map((d) => d.code).toList();
    expect(codes.toSet(), hasLength(codes.length));
    expect(codes.any((c) => c.trim().isEmpty), isFalse);
    expect(codes, contains('dirty'));
    expect(codes, contains('hairline_crack'));
    expect(codes, contains('other'));
  });

  test('summary derives acceptable counts and percentages', () {
    final summary = EggGradingSummary.fromCounts(
      sampleSize: 100,
      rejectedCount: 12,
      counts: {'dirty': 4, 'cracked': 3, 'wrinkled': 2, 'thin_shell': 3},
    );

    expect(summary.acceptableCount, 88);
    expect(summary.rejectedPct, closeTo(12.0, 0.001));
    expect(summary.acceptablePct, closeTo(88.0, 0.001));
    expect(summary.topDefectCode, 'dirty');
    expect(summary.topDefectPct, closeTo(4.0, 0.001));
  });

  test('a defect sum above the sample size is allowed', () {
    final errors = EggGradingValidation.validate(
      sampleSize: 100,
      rejectedCount: 40,
      counts: {'dirty': 60, 'cracked': 55},
    );
    expect(errors, isEmpty);
  });

  test('negative counts, oversized defects and oversized rejects are rejected',
      () {
    expect(
      EggGradingValidation.validate(
          sampleSize: 100, rejectedCount: 0, counts: {'dirty': -1}),
      isNotEmpty,
    );
    expect(
      EggGradingValidation.validate(
          sampleSize: 100, rejectedCount: 0, counts: {'dirty': 101}),
      isNotEmpty,
    );
    expect(
      EggGradingValidation.validate(
          sampleSize: 100, rejectedCount: 101, counts: const {}),
      isNotEmpty,
    );
  });

  test('summary round-trips through JSON', () {
    final summary = EggGradingSummary.fromCounts(
      sampleSize: 50,
      rejectedCount: 5,
      counts: {'dirty': 2, 'ridged': 1},
    );
    final restored = EggGradingSummary.fromJson(
      summary.encodedJson,
      sampleSize: 50,
      rejectedCount: 5,
    );
    expect(restored.counts, {'dirty': 2, 'ridged': 1});
    expect(restored.topDefectCode, 'dirty');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/audits/egg_grading_model_test.dart`
Expected: FAIL — the file does not exist.

- [ ] **Step 3: Write the model**

Create `lib/features/audits/models/egg_grading.dart`, mirroring the structure of `lib/features/audits/models/culled_chicks_analysis.dart`:

```dart
import 'dart:convert';

class EggDefectType {
  const EggDefectType({
    required this.code,
    required this.name,
    required this.category,
    required this.isReject,
    required this.description,
    required this.sortOrder,
    this.imageAsset,
  });

  final String code;
  final String name;
  final String category;
  final bool isReject;
  final String description;
  final int sortOrder;
  final String? imageAsset;
}

const String kEggDefectCategoryContamination = 'Shell contamination';
const String kEggDefectCategoryIntegrity = 'Shell integrity';
const String kEggDefectCategoryQuality = 'Shell quality';
const String kEggDefectCategoryShape = 'Shape and size';
const String kEggDefectCategoryOther = 'Other';

const List<EggDefectType> kEggDefectTypes = [
  EggDefectType(
    code: 'dirty',
    name: 'Dirty',
    category: kEggDefectCategoryContamination,
    isReject: true,
    description: 'Faecal or litter contamination on the shell.',
    sortOrder: 10,
  ),
  EggDefectType(
    code: 'yolk_stained',
    name: 'Yolk stained',
    category: kEggDefectCategoryContamination,
    isReject: true,
    description: 'Yolk from a broken egg dried onto the shell.',
    sortOrder: 20,
  ),
  EggDefectType(
    code: 'blood_stained',
    name: 'Blood stained',
    category: kEggDefectCategoryContamination,
    isReject: true,
    description: 'Blood smeared on the shell at lay.',
    sortOrder: 30,
  ),
  EggDefectType(
    code: 'stained',
    name: 'Stained',
    category: kEggDefectCategoryContamination,
    isReject: true,
    description: 'Any other surface staining.',
    sortOrder: 40,
  ),
  EggDefectType(
    code: 'cracked',
    name: 'Cracked',
    category: kEggDefectCategoryIntegrity,
    isReject: true,
    description: 'Visible shell fracture.',
    sortOrder: 50,
  ),
  EggDefectType(
    code: 'hairline_crack',
    name: 'Hairline crack',
    category: kEggDefectCategoryIntegrity,
    isReject: true,
    description: 'Fine crack, usually only visible when candled.',
    sortOrder: 60,
  ),
  EggDefectType(
    code: 'toe_hole',
    name: 'Toe hole',
    category: kEggDefectCategoryIntegrity,
    isReject: true,
    description: 'Puncture from a hen treading on the egg.',
    sortOrder: 70,
  ),
  EggDefectType(
    code: 'thin_shell',
    name: 'Thin shell',
    category: kEggDefectCategoryQuality,
    isReject: true,
    description: 'Translucent, weak shell.',
    sortOrder: 80,
  ),
  EggDefectType(
    code: 'wrinkled',
    name: 'Wrinkled',
    category: kEggDefectCategoryQuality,
    isReject: true,
    description: 'Corrugated shell surface.',
    sortOrder: 90,
  ),
  EggDefectType(
    code: 'ridged',
    name: 'Ridged',
    category: kEggDefectCategoryQuality,
    isReject: true,
    description: 'Raised band or ridge around the shell.',
    sortOrder: 100,
  ),
  EggDefectType(
    code: 'calcium_deposit',
    name: 'Calcium deposit',
    category: kEggDefectCategoryQuality,
    isReject: true,
    description: 'Chalky calcium lumps on the shell.',
    sortOrder: 110,
  ),
  EggDefectType(
    code: 'membrane',
    name: 'Membrane',
    category: kEggDefectCategoryQuality,
    isReject: true,
    description: 'Exposed membrane where shell is missing.',
    sortOrder: 120,
  ),
  EggDefectType(
    code: 'round',
    name: 'Round',
    category: kEggDefectCategoryShape,
    isReject: true,
    description: 'Round rather than oval; hatches less well.',
    sortOrder: 130,
  ),
  EggDefectType(
    code: 'elongated',
    name: 'Elongated',
    category: kEggDefectCategoryShape,
    isReject: true,
    description: 'Abnormally long egg.',
    sortOrder: 140,
  ),
  EggDefectType(
    code: 'slab_sided',
    name: 'Slab sided',
    category: kEggDefectCategoryShape,
    isReject: true,
    description: 'Flattened side from pressure before shell set.',
    sortOrder: 150,
  ),
  EggDefectType(
    code: 'small',
    name: 'Small',
    category: kEggDefectCategoryShape,
    isReject: true,
    description: 'Below the acceptable weight range.',
    sortOrder: 160,
  ),
  EggDefectType(
    code: 'double_yolk',
    name: 'Double yolk',
    category: kEggDefectCategoryShape,
    isReject: true,
    description: 'Oversized egg with two yolks.',
    sortOrder: 170,
  ),
  EggDefectType(
    code: 'other',
    name: 'Other',
    category: kEggDefectCategoryOther,
    isReject: true,
    description: 'Any defect not listed above; use the note field.',
    sortOrder: 180,
  ),
];

EggDefectType? eggDefectTypeForCode(String code) {
  for (final defect in kEggDefectTypes) {
    if (defect.code == code) return defect;
  }
  return null;
}

class EggGradingSummary {
  const EggGradingSummary({
    required this.sampleSize,
    required this.rejectedCount,
    required this.counts,
  });

  final int sampleSize;
  final int rejectedCount;
  final Map<String, int> counts;

  int get acceptableCount => (sampleSize - rejectedCount).clamp(0, sampleSize);
  double get rejectedPct => _pct(rejectedCount);
  double get acceptablePct => _pct(acceptableCount);

  String? get topDefectCode {
    String? top;
    var best = 0;
    for (final entry in counts.entries) {
      if (entry.value > best) {
        best = entry.value;
        top = entry.key;
      }
    }
    return top;
  }

  double? get topDefectPct {
    final code = topDefectCode;
    return code == null ? null : _pct(counts[code] ?? 0);
  }

  double pctFor(String code) => _pct(counts[code] ?? 0);

  bool get hasData => sampleSize > 0 || counts.values.any((v) => v > 0);

  double _pct(int value) =>
      sampleSize <= 0 ? 0 : (value * 100) / sampleSize;

  String? get encodedJson {
    final positive = {
      for (final entry in counts.entries)
        if (entry.value > 0) entry.key: entry.value,
    };
    if (positive.isEmpty) return null;
    return jsonEncode([
      for (final entry in positive.entries)
        {
          'code': entry.key,
          'name': eggDefectTypeForCode(entry.key)?.name ?? entry.key,
          'category': eggDefectTypeForCode(entry.key)?.category,
          'isReject': eggDefectTypeForCode(entry.key)?.isReject ?? true,
          'count': entry.value,
        },
    ]);
  }

  factory EggGradingSummary.fromCounts({
    required int sampleSize,
    required int rejectedCount,
    required Map<String, int> counts,
  }) {
    return EggGradingSummary(
      sampleSize: sampleSize,
      rejectedCount: rejectedCount,
      counts: {
        for (final entry in counts.entries)
          if (entry.value > 0) entry.key: entry.value,
      },
    );
  }

  factory EggGradingSummary.fromJson(
    String? source, {
    int? sampleSize,
    int? rejectedCount,
  }) {
    final counts = <String, int>{};
    if (source != null && source.isNotEmpty) {
      final decoded = jsonDecode(source);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is! Map) continue;
          final code = item['code']?.toString();
          final count = item['count'];
          if (code == null || count is! num) continue;
          if (count.toInt() > 0) counts[code] = count.toInt();
        }
      }
    }
    return EggGradingSummary(
      sampleSize: sampleSize ?? 0,
      rejectedCount: rejectedCount ?? 0,
      counts: counts,
    );
  }
}

class EggGradingValidation {
  const EggGradingValidation._();

  /// One egg may carry several defects, so the defect counts are occurrences
  /// and their sum may legitimately exceed the sample size. Only per-defect
  /// and rejected-count ceilings are enforced.
  static List<String> validate({
    required int sampleSize,
    required int rejectedCount,
    required Map<String, int> counts,
  }) {
    final errors = <String>[];
    if (sampleSize < 0) errors.add('Eggs inspected cannot be negative.');
    if (rejectedCount < 0) errors.add('Eggs rejected cannot be negative.');
    if (sampleSize > 0 && rejectedCount > sampleSize) {
      errors.add('Eggs rejected cannot exceed eggs inspected.');
    }
    for (final entry in counts.entries) {
      final name = eggDefectTypeForCode(entry.key)?.name ?? entry.key;
      if (entry.value < 0) {
        errors.add('$name count cannot be negative.');
      } else if (sampleSize > 0 && entry.value > sampleSize) {
        errors.add('$name count cannot exceed eggs inspected.');
      }
    }
    return errors;
  }
}
```

- [ ] **Step 4: Run the model test to verify it passes**

Run: `flutter test test/features/audits/egg_grading_model_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the failing schema test**

Create `test/data/database/egg_grading_schema_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/features/audits/models/egg_grading.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    await useIsolatedAppDatabase();
  });

  tearDown(resetAppDatabase);

  test('egg_quality carries the grading summary columns', () async {
    final db = await DatabaseHelper().db;
    final columns = (await db.rawQuery('PRAGMA table_info(egg_quality)'))
        .map((row) => row['name'] as String)
        .toSet();
    expect(
      columns.containsAll({
        'gradingSampleSize',
        'gradingRejectedCount',
        'gradingAcceptableCount',
        'gradingRejectedPct',
        'gradingAcceptablePct',
        'gradingDefectsJson',
        'gradingTopDefectCode',
        'gradingTopDefectPct',
      }),
      isTrue,
    );
  });

  test('the defect catalogue is seeded from the Dart catalogue', () async {
    final db = await DatabaseHelper().db;
    final seeded = await db.query('egg_defect_types');
    expect(seeded, hasLength(kEggDefectTypes.length));
    expect(
      seeded.map((row) => row['code']).toSet(),
      kEggDefectTypes.map((d) => d.code).toSet(),
    );
  });

  test('egg_quality_defect_counts exists with its uniqueness rule', () async {
    final db = await DatabaseHelper().db;
    const base = {
      'id': 'count-1',
      'eggQualityId': 'eq-1',
      'sessionId': 'session-1',
      'customerId': 'customer-1',
      'date': '2026-08-23',
      'defectCode': 'dirty',
      'count': 4,
      'createdAt': '2026-08-23T00:00:00.000Z',
      'updatedAt': '2026-08-23T00:00:00.000Z',
    };
    await db.insert('egg_quality_defect_counts', base);
    expect(
      () => db.insert('egg_quality_defect_counts', {...base, 'id': 'count-2'}),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('database version is 62', () async {
    final db = await DatabaseHelper().db;
    expect(await db.getVersion(), 62);
  });
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `flutter test test/data/database/egg_grading_schema_test.dart`
Expected: FAIL — no such columns, tables, or version.

- [ ] **Step 7: Add the grading columns to the panel schema**

In `lib/data/models/panel_sample_schema.dart`, append to the `egg_quality` `measurementColumns` list:

```dart
        'gradingSampleSize INTEGER',
        'gradingRejectedCount INTEGER',
        'gradingAcceptableCount INTEGER',
        'gradingRejectedPct REAL',
        'gradingAcceptablePct REAL',
        'gradingDefectsJson TEXT',
        'gradingTopDefectCode TEXT',
        'gradingTopDefectPct REAL',
```

- [ ] **Step 8: Create the two new tables**

In `lib/data/database/database_schema.dart`, add:

```dart
Future<void> createEggGradingTables(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS egg_defect_types (
    id TEXT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    isReject INTEGER NOT NULL DEFAULT 1,
    description TEXT,
    imageAsset TEXT,
    sortOrder INTEGER NOT NULL DEFAULT 0,
    isActive INTEGER NOT NULL DEFAULT 1,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL
  )''');

  await db.execute('''CREATE TABLE IF NOT EXISTS egg_quality_defect_counts (
    id TEXT PRIMARY KEY,
    eggQualityId TEXT NOT NULL,
    sessionId TEXT NOT NULL,
    customerId TEXT NOT NULL,
    flockId TEXT,
    hatcheryId TEXT,
    date TEXT NOT NULL,
    scopeType TEXT,
    houseKey TEXT,
    sampleLabel TEXT,
    defectCode TEXT NOT NULL,
    defectCategory TEXT,
    isReject INTEGER,
    count INTEGER NOT NULL DEFAULT 0,
    pctOfSample REAL,
    notes TEXT,
    sortOrder INTEGER NOT NULL DEFAULT 0,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (eggQualityId) REFERENCES egg_quality(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_eqdc_unique_defect '
    'ON egg_quality_defect_counts (eggQualityId, defectCode)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_eqdc_parent '
    'ON egg_quality_defect_counts (eggQualityId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_eqdc_dashboard '
    'ON egg_quality_defect_counts (customerId, flockId, date, defectCode)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_eqdc_sync '
    'ON egg_quality_defect_counts (syncStatus, dirtyAt)',
  );
}
```

Call it from the same place the other table-group creators are called during `_onCreate`.

**Note:** `egg_quality_defect_counts` is not in `PanelSampleSchema.panels`, so it does not get the panel context columns and is not reconciled by the panel pass. It is a plain table.

- [ ] **Step 9: Seed the catalogue**

Create `lib/data/database/seeds/egg_defect_type_seeds.dart`:

```dart
import 'package:sqflite/sqflite.dart';

import '../../../features/audits/models/egg_grading.dart';

/// Seeds `egg_defect_types` from the Dart catalogue. Idempotent: re-running it
/// refreshes names and descriptions but never removes a code, because saved
/// defect counts join on `code` and must keep resolving.
Future<void> seedEggDefectTypes(DatabaseExecutor db) async {
  final now = DateTime.now().toIso8601String();
  final batch = db.batch();
  for (final defect in kEggDefectTypes) {
    batch.insert(
      'egg_defect_types',
      {
        'id': 'egg-defect-${defect.code}',
        'code': defect.code,
        'name': defect.name,
        'category': defect.category,
        'isReject': defect.isReject ? 1 : 0,
        'description': defect.description,
        'imageAsset': defect.imageAsset,
        'sortOrder': defect.sortOrder,
        'isActive': 1,
        'createdAt': now,
        'updatedAt': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  await batch.commit(noResult: true);
}
```

Call `seedEggDefectTypes(db)` from `_onCreate` after the tables exist, and from the v62 upgrade hop.

- [ ] **Step 10: Bump to v62 and register the new table**

In `database_helper.dart`: change `version: 61` to `version: 62`; append to the upgrade chain:

```dart
    if (oldVersion < 62) {
      await _applyV62Upgrade(db);
    }
```

```dart
  /// v62 adds visual egg grading: summary columns on the egg_quality panel
  /// (handled by the panel reconciliation pass), plus the defect catalogue and
  /// the per-sample defect-count child table.
  Future<void> _applyV62Upgrade(Database db) async {
    await createEggGradingTables(db);
    await seedEggDefectTypes(db);
    await ensurePanelSampleSchemaColumns(db);
  }
```

Add `'egg_defect_types'` and `'egg_quality_defect_counts'` to `_criticalTables`, and add their column lists to `_criticalColumns` in the same format the neighbouring `lab_analysis_rows` entry uses (column definitions **excluding** `id`).

- [ ] **Step 11: Run tests to verify they pass**

Run: `flutter test test/data/database/egg_grading_schema_test.dart test/data/database/`
Expected: PASS, including `surgical_schema_repair_test.dart` and `schema_parity_test.dart` (update its version reference to 62).

- [ ] **Step 12: Docs and commit**

`docs/DATABASE_SPEC.md`: document both new tables and the eight grading columns. `docs/LIVING_SPEC.md`: describe the grading data model. `docs/CHANGELOG.md`:

```markdown
- 2026-08-23: Added the egg-defect catalogue and per-sample defect-count
  storage behind the Egg Quality station, plus grading summary fields on the
  egg quality panel. Schema version 62.
```

```bash
flutter analyze
git add lib/features/audits/models/egg_grading.dart lib/data/database/ lib/data/models/panel_sample_schema.dart test/ docs/
git commit -m "feat(egg): add egg grading schema, catalogue and summary model"
```

---

### Task B3: Grading repository

**Files:**
- Create: `lib/data/repositories/egg_grading_repository.dart`
- Test: `test/data/repositories/egg_grading_repository_test.dart` (create)

**Interfaces:**
- Consumes: the tables from B2.
- Produces:
  - `EggGradingRepository({DatabaseHelper? databaseHelper})`
  - `Future<Map<String, int>> countsForSample(String eggQualityId)`
  - `Future<Map<String, Map<String, int>>> countsForSession(String sessionId)` — keyed by `eggQualityId`
  - `Future<void> replaceCountsForSample({required String eggQualityId, required String sessionId, required String customerId, String? flockId, String? hatcheryId, required String date, String? scopeType, String? houseKey, String? sampleLabel, required int sampleSize, required Map<String, int> counts})`
  - `Future<void> deleteCountsForSamples(Iterable<String> eggQualityIds)`
  - `Future<List<Map<String, dynamic>>> getDirtyRows()`, `Future<void> markRowsSynced(Iterable<String> ids)`, `Future<void> markRowsFailed(Iterable<String> ids, Object error)`
  - `static const String table = 'egg_quality_defect_counts';`

- [ ] **Step 1: Write the failing test**

Create `test/data/repositories/egg_grading_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/repositories/egg_grading_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

void main() {
  late Database db;
  late EggGradingRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final helper = _MockDatabaseHelper();
    when(() => helper.db).thenAnswer((_) async => db);
    await db.execute('''CREATE TABLE egg_quality_defect_counts (
      id TEXT PRIMARY KEY,
      eggQualityId TEXT NOT NULL,
      sessionId TEXT NOT NULL,
      customerId TEXT NOT NULL,
      flockId TEXT,
      hatcheryId TEXT,
      date TEXT NOT NULL,
      scopeType TEXT,
      houseKey TEXT,
      sampleLabel TEXT,
      defectCode TEXT NOT NULL,
      defectCategory TEXT,
      isReject INTEGER,
      count INTEGER NOT NULL DEFAULT 0,
      pctOfSample REAL,
      notes TEXT,
      sortOrder INTEGER NOT NULL DEFAULT 0,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL,
      syncStatus TEXT NOT NULL DEFAULT 'pending',
      dirtyAt TEXT,
      lastSyncedAt TEXT,
      syncError TEXT
    )''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_eqdc_unique_defect '
      'ON egg_quality_defect_counts (eggQualityId, defectCode)',
    );
    await db.execute('''CREATE TABLE sync_tombstones (
      id TEXT PRIMARY KEY,
      tableName TEXT NOT NULL,
      rowId TEXT NOT NULL,
      deletedAt TEXT NOT NULL,
      createdAt TEXT NOT NULL,
      syncedAt TEXT,
      lastError TEXT
    )''');
    repository = EggGradingRepository(databaseHelper: helper);
  });

  tearDown(() async => db.close());

  Future<void> save(String sampleId, Map<String, int> counts) {
    return repository.replaceCountsForSample(
      eggQualityId: sampleId,
      sessionId: 'session-1',
      customerId: 'customer-1',
      flockId: 'flock-1',
      date: '2026-08-23',
      scopeType: 'house',
      houseKey: sampleId == 'eq-1' ? 'H1' : 'H2',
      sampleLabel: sampleId == 'eq-1' ? 'H1' : 'H2',
      sampleSize: 100,
      counts: counts,
    );
  }

  test('counts are stored and read back per sample', () async {
    await save('eq-1', {'dirty': 4, 'cracked': 3});
    await save('eq-2', {'wrinkled': 2});

    expect(await repository.countsForSample('eq-1'), {'dirty': 4, 'cracked': 3});
    expect(await repository.countsForSample('eq-2'), {'wrinkled': 2});
  });

  test('replacing drops removed defects and keeps the rest', () async {
    await save('eq-1', {'dirty': 4, 'cracked': 3});
    await save('eq-1', {'dirty': 6});

    expect(await repository.countsForSample('eq-1'), {'dirty': 6});
    final tombstones = await db.query('sync_tombstones');
    expect(tombstones, hasLength(1));
    expect(tombstones.single['tableName'], 'egg_quality_defect_counts');
  });

  test('zero counts are not stored', () async {
    await save('eq-1', {'dirty': 0, 'cracked': 3});
    expect(await repository.countsForSample('eq-1'), {'cracked': 3});
  });

  test('pctOfSample is derived from the sample size', () async {
    await save('eq-1', {'dirty': 4});
    final row = (await db.query('egg_quality_defect_counts')).single;
    expect(row['pctOfSample'], closeTo(4.0, 0.001));
  });

  test('deleting a sample removes its counts and queues tombstones', () async {
    await save('eq-1', {'dirty': 4, 'cracked': 3});
    await repository.deleteCountsForSamples(['eq-1']);

    expect(await repository.countsForSample('eq-1'), isEmpty);
    expect(await db.query('sync_tombstones'), hasLength(2));
  });

  test('countsForSession groups by owning sample', () async {
    await save('eq-1', {'dirty': 4});
    await save('eq-2', {'wrinkled': 2});
    expect(await repository.countsForSession('session-1'), {
      'eq-1': {'dirty': 4},
      'eq-2': {'wrinkled': 2},
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/egg_grading_repository_test.dart`
Expected: FAIL — the repository does not exist.

- [ ] **Step 3: Write the repository**

Create `lib/data/repositories/egg_grading_repository.dart`. Model it on `lib/data/repositories/lab_analysis_repository.dart` for the dirty/synced/failed methods. `replaceCountsForSample` runs in one transaction: read the existing ids for that `eggQualityId`, upsert every count greater than zero (deterministic id `'$eggQualityId:$defectCode'`), then delete the rows whose codes are no longer present — **through `SyncTombstoneRepository.queueDeletesWithExecutor` before the delete**, so the cloud learns about them. `deleteCountsForSamples` does the same for every row of the named samples.

Set `pctOfSample` to `sampleSize <= 0 ? null : count * 100 / sampleSize`, and copy `defectCategory` and `isReject` from `eggDefectTypeForCode(code)` at write time so a later catalogue edit cannot rewrite history.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/repositories/egg_grading_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
flutter analyze
git add lib/data/repositories/egg_grading_repository.dart test/data/repositories/egg_grading_repository_test.dart
git commit -m "feat(egg): add the egg grading repository"
```

---

### Task B4: Grading in the draft, the save path, and reopen

**Files:**
- Modify: `lib/data/models/audit_model.dart` (three fields)
- Modify: `lib/features/audits/logic/panel_value_builders.dart` (`eggQualityValues`)
- Modify: `lib/features/audits/logic/audit_meaningful_data.dart` (`hasMeaningfulEggQualityData`)
- Modify: `lib/features/audits/services/audit_panel_save_coordinator.dart`
- Modify: `lib/features/audits/providers/audit_provider.dart`
- Modify: `lib/features/audits/logic/egg_station_reconstruction.dart`
- Test: `test/features/audits/egg_grading_persistence_test.dart` (create)

**Interfaces:**
- Consumes: `EggGradingSummary`, `EggGradingValidation` (B2); `EggGradingRepository` (B3).
- Produces: `AuditModel.esGradingSampleSize` (`int?`), `esGradingRejectedCount` (`int?`), `esGradingDefectsJson` (`String?`); child rows written on save; grading restored on reopen.

- [ ] **Step 1: Write the failing test**

Create `test/features/audits/egg_grading_persistence_test.dart`, reusing the in-memory harness from `egg_station_panel_persistence_test.dart` plus the `egg_quality_defect_counts` table from B3's test:

```dart
  test('grading is saved per sample and does not bleed between houses',
      () async {
    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.updateSampleMetadata({'houseNo': 'H1', 'houseLabel': 'House 1'});
    provider.updateField('esGradingSampleSize', 100);
    provider.updateField('esGradingRejectedCount', 9);
    provider.updateGradingCounts({'dirty': 4, 'cracked': 3});

    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.updateSampleMetadata({'houseNo': 'H2', 'houseLabel': 'House 2'});
    provider.updateField('esGradingSampleSize', 100);
    provider.updateField('esGradingRejectedCount', 2);
    provider.updateGradingCounts({'wrinkled': 2});

    await provider.saveSamplesWithResult(tabIndex: 0);

    final panels = await db.query('egg_quality', orderBy: 'sampleIndex ASC');
    expect(panels.map((r) => r['gradingRejectedCount']), [9, 2]);
    expect(panels.map((r) => r['gradingAcceptableCount']), [91, 98]);
    expect(panels.first['gradingTopDefectCode'], 'dirty');

    final counts = await db.query('egg_quality_defect_counts',
        orderBy: 'eggQualityId ASC, defectCode ASC');
    expect(counts, hasLength(3));
    expect(
      counts.where((r) => r['eggQualityId'] == panels.first['id'])
          .map((r) => r['defectCode']),
      ['cracked', 'dirty'],
    );
  });

  Future<void> gradeTwoHouses() async {
    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.updateSampleMetadata({'houseNo': 'H1', 'houseLabel': 'House 1'});
    provider.updateField('esGradingSampleSize', 100);
    provider.updateField('esGradingRejectedCount', 9);
    provider.updateGradingCounts({'dirty': 4, 'cracked': 3});
    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.updateSampleMetadata({'houseNo': 'H2', 'houseLabel': 'House 2'});
    provider.updateField('esGradingSampleSize', 100);
    provider.updateField('esGradingRejectedCount', 2);
    provider.updateGradingCounts({'wrinkled': 2});
    await provider.saveSamplesWithResult(tabIndex: 0);
  }

  test('reopen restores grading for every sample', () async {
    await gradeTwoHouses();
    final reopened = await reopenEggStation(db, 'session-egg-db');
    expect(
      reopened.stationAudits.map((a) => a.esGradingRejectedCount),
      [9, 2],
    );
    final restored = EggGradingSummary.fromJson(
      reopened.stationAudits.first.esGradingDefectsJson,
      sampleSize: 100,
      rejectedCount: 9,
    );
    expect(restored.counts, {'dirty': 4, 'cracked': 3});
  });

  test('a panel row without child rows falls back to its JSON mirror',
      () async {
    await gradeTwoHouses();
    await db.delete('egg_quality_defect_counts');

    final reopened = await reopenEggStation(db, 'session-egg-db');
    final restored = EggGradingSummary.fromJson(
      reopened.stationAudits.first.esGradingDefectsJson,
      sampleSize: 100,
      rejectedCount: 9,
    );
    expect(restored.counts, {'dirty': 4, 'cracked': 3});
  });

  test('removing a sample removes its grading rows', () async {
    await gradeTwoHouses();
    provider.switchSample(1);
    provider.removeActiveEggQualityScopeSample(
      StationSampleModel.sampleKindHouse,
    );
    await provider.saveSamplesWithResult(tabIndex: 0);

    final counts = await db.query('egg_quality_defect_counts');
    expect(counts.map((r) => r['defectCode']), ['cracked', 'dirty']);
    expect(await db.query('sync_tombstones'), isNotEmpty);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/audits/egg_grading_persistence_test.dart`
Expected: FAIL — no such draft fields or provider method.

- [ ] **Step 3: Add the draft fields**

In `lib/data/models/audit_model.dart`, add `esGradingSampleSize` (`int?`), `esGradingRejectedCount` (`int?`), and `esGradingDefectsJson` (`String?`) exactly the way `culledChicksAnalysisJson` is threaded — field declaration, constructor parameter, `fromMap` entry, `toMap` entry, and `copyWith` if the class has one.

Run: `flutter test test/features/audits/audit_model_roundtrip_test.dart`
Expected: PASS.

- [ ] **Step 4: Add the provider entry point**

In `AuditProvider`:

```dart
  /// Grading counts for the active sample. Held on the draft as JSON, which is
  /// already per-sample, so switching houses cannot move them.
  Map<String, int> get activeGradingCounts {
    return EggGradingSummary.fromJson(
      activeDraft.esGradingDefectsJson,
      sampleSize: activeDraft.esGradingSampleSize ?? 0,
      rejectedCount: activeDraft.esGradingRejectedCount ?? 0,
    ).counts;
  }

  void updateGradingCounts(Map<String, int> counts) {
    if (_isReadOnly) return;
    final summary = EggGradingSummary.fromCounts(
      sampleSize: activeDraft.esGradingSampleSize ?? 0,
      rejectedCount: activeDraft.esGradingRejectedCount ?? 0,
      counts: counts,
    );
    final map = activeDraft.toMap()
      ..['esGradingDefectsJson'] = summary.encodedJson
      ..['updatedAt'] = DateTime.now().toIso8601String();
    _drafts[_activeHatchIndex] = AuditModel.fromMap(map);
    _syncStationSampleFromDraft(_activeHatchIndex);
    _markDirtyAndScheduleAutosave();
    notifyListeners();
  }
```

- [ ] **Step 5: Write the summary columns**

In `eggQualityValues` in `panel_value_builders.dart`, append to the returned map:

```dart
    ..._eggGradingValues(draft),
```

with:

```dart
Map<String, Object?> _eggGradingValues(AuditModel draft) {
  final summary = EggGradingSummary.fromJson(
    draft.esGradingDefectsJson,
    sampleSize: draft.esGradingSampleSize ?? 0,
    rejectedCount: draft.esGradingRejectedCount ?? 0,
  );
  if (!summary.hasData) return const {};
  return {
    'gradingSampleSize': summary.sampleSize,
    'gradingRejectedCount': summary.rejectedCount,
    'gradingAcceptableCount': summary.acceptableCount,
    'gradingRejectedPct': summary.rejectedPct,
    'gradingAcceptablePct': summary.acceptablePct,
    'gradingDefectsJson': summary.encodedJson,
    'gradingTopDefectCode': summary.topDefectCode,
    'gradingTopDefectPct': summary.topDefectPct,
  };
}
```

Extend `hasMeaningfulEggQualityData` so a sample with only grading data still saves:

```dart
      (draft.esGradingSampleSize ?? 0) > 0 ||
      (draft.esGradingRejectedCount ?? 0) > 0 ||
      hasText(draft.esGradingDefectsJson) ||
```

- [ ] **Step 6: Write the child rows**

Give `AuditPanelSaveCoordinator` an `EggGradingRepository` (constructor-injected, defaulting to a new instance so existing call sites keep compiling). After the `egg_quality` panel write for a pair, call `replaceCountsForSample` with that sample's id, session, customer, flock, hatchery, date, `scopeType`, `houseKey` (the sample's `houseNo`), `sampleLabel`, `sampleSize`, and the decoded counts. When a sample carries no grading data, call it with an empty map so any previous rows are removed.

In `_deletePanelRowsForRemovedSamples`, also call `deleteCountsForSamples(removedStationSampleIds)`. Since the `egg_quality` row id is now the sample id (A4), the ids line up directly.

- [ ] **Step 7: Restore on reopen**

In `egg_station_reconstruction.dart`, `_mergePanelRowIntoAuditMap` case `'egg_quality'`, add:

```dart
        copy('esGradingSampleSize', 'gradingSampleSize');
        copy('esGradingRejectedCount', 'gradingRejectedCount');
        copy('esGradingDefectsJson', 'gradingDefectsJson');
```

Extend `reopenEggStation` to also read `egg_quality_defect_counts` for the session and, where child rows exist for a sample, rebuild `esGradingDefectsJson` from them — child rows win, the panel JSON is the fallback for a cloud-pulled row whose children have not arrived.

- [ ] **Step 8: Run tests to verify they pass**

Run: `flutter test test/features/audits/egg_grading_persistence_test.dart test/features/audits/`
Expected: PASS.

- [ ] **Step 9: Docs and commit**

`docs/LIVING_SPEC.md`: describe the grading save and reopen path. `docs/CHANGELOG.md`:

```markdown
- 2026-08-23: Egg grading results are saved against the individual Egg Quality
  sample they were entered on, and come back on the right sample when the
  audit is reopened. Removing a sample removes its grading with it.
```

```bash
flutter analyze
git add lib/data/models/audit_model.dart lib/features/audits/ test/features/audits/egg_grading_persistence_test.dart docs/
git commit -m "feat(egg): persist egg grading per sample"
```

---

### Task B5: Grading UI section

**Files:**
- Modify: `lib/features/audits/screens/egg_storage_screen.dart`
- Create: `lib/features/audits/widgets/tabs/egg_grading_section.dart`
- Test: `test/features/audits/egg_grading_section_test.dart` (create)

**Interfaces:**
- Consumes: `AuditProvider.activeGradingCounts`, `updateGradingCounts`, the `esGrading*` draft fields, `EggGradingSummary`, `EggGradingValidation`.
- Produces: `EggGradingSection` widget, rendered inside the Egg Quality sample scope.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/audits/egg_grading_section_test.dart`, following the bounded-`pump` pattern from `culled_chicks_analysis` and `egg_storage_screen` tests:

```dart
  testWidgets('entering counts updates the summary strip', (tester) async {
    await pumpEggGrading(tester);

    await tester.enterText(find.byKey(const Key('egg-grading-sample-size')), '100');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const Key('egg-grading-rejected')), '12');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const Key('egg-grading-count-dirty')), '4');
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Acceptable 88 (88.0%)'), findsOneWidget);
    expect(find.text('Rejected 12 (12.0%)'), findsOneWidget);
    expect(find.textContaining('Dirty'), findsWidgets);
  });

  testWidgets('a defect count above the sample size shows an error',
      (tester) async {
    await pumpEggGrading(tester);
    await tester.enterText(find.byKey(const Key('egg-grading-sample-size')), '50');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const Key('egg-grading-count-dirty')), '80');
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('cannot exceed eggs inspected'), findsOneWidget);
  });

  testWidgets('a defect sum above the sample size is accepted', (tester) async {
    await pumpEggGrading(tester);
    await tester.enterText(find.byKey(const Key('egg-grading-sample-size')), '100');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const Key('egg-grading-count-dirty')), '60');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const Key('egg-grading-count-cracked')), '55');
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('cannot exceed'), findsNothing);
  });

  testWidgets('switching house samples swaps the counts', (tester) async {
    await pumpEggGradingWithTwoHouses(tester);
    expect(
      tester.widget<TextField>(find.byKey(const Key('egg-grading-count-dirty')))
          .controller!.text,
      '4',
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'H2'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<TextField>(find.byKey(const Key('egg-grading-count-dirty')))
          .controller!.text,
      '',
    );
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/audits/egg_grading_section_test.dart`
Expected: FAIL — no such widget.

- [ ] **Step 3: Build the section**

Create `lib/features/audits/widgets/tabs/egg_grading_section.dart`, structured like `culled_chicks_analysis_tab.dart`: a `StatefulWidget` owning one `TextEditingController` per defect code plus two for sample size and rejected count; a summary strip; then defects grouped by `category` in `sortOrder`. Each row renders a leading image slot — `defect.imageAsset == null ? const SizedBox(width: 40, height: 40) : Image.asset(defect.imageAsset!, width: 40, height: 40)` — the name, the count field keyed `Key('egg-grading-count-${defect.code}')`, and the derived percentage.

Rebuild all controllers from the draft in `didUpdateWidget` whenever the active sample id changes. This is what makes the house-switch test pass; without it the controllers keep the previous sample's text.

Render errors from `EggGradingValidation.validate(...)` beneath the summary strip.

- [ ] **Step 4: Mount it in the Egg Quality tab**

Add the section to `egg_storage_screen.dart` below the existing UV and egg-weight blocks, inside the active-sample scope, with a heading "Egg grading / visual quality". Pass `key: ValueKey('egg-grading-${auditProvider.activeStationSample.id}')` so a sample switch rebuilds it.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/audits/egg_grading_section_test.dart test/features/audits/egg_storage_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Docs and commit**

`docs/LIVING_SPEC.md`: describe the section and its validation rules. `docs/CHANGELOG.md`:

```markdown
- 2026-08-23: Egg Quality now has an egg grading section: enter how many eggs
  were inspected and rejected, then the count for each defect, and see the
  acceptable and rejected percentages update live. Because one egg can have
  more than one defect, the defect counts are allowed to add up to more than
  the number of eggs inspected.
```

```bash
flutter analyze
git add lib/features/audits/widgets/tabs/egg_grading_section.dart lib/features/audits/screens/egg_storage_screen.dart test/features/audits/egg_grading_section_test.dart docs/
git commit -m "feat(egg): add the egg grading UI section"
```

---

### Task B6: Sync the grading child table

**Files:**
- Modify: `lib/services/supabase/startup_sync_service.dart` (push)
- Modify: `lib/services/supabase/supabase_service.dart` (pull + `SupabasePullSummary`)
- Test: `test/services/egg_grading_sync_test.dart` (create)

**Interfaces:**
- Consumes: `EggGradingRepository.getDirtyRows` / `markRowsSynced` / `markRowsFailed` (B3).
- Produces: `_pushDirtyEggGrading()` in the push sequence, and `eggGradingCounts` on `SupabasePullSummary`.

- [ ] **Step 1: Write the failing test**

Create `test/services/egg_grading_sync_test.dart`, following the shape of the existing sync tests in `test/services/`. Assert that:

```dart
  test('grading rows are pushed after panel rows', () async {
    // record the order of upsertRowsStrict table names on a fake SupabaseService
    expect(
      pushedTables.indexOf('egg_quality_defect_counts'),
      greaterThan(pushedTables.indexOf('egg_quality')),
    );
  });

  test('sync metadata is stripped before upload', () async {
    expect(
      uploadedRows.first.keys,
      isNot(contains(anyOf('syncStatus', 'dirtyAt', 'lastSyncedAt', 'syncError'))),
    );
  });

  test('local camelCase columns map to snake_case', () {
    final payload = toSupabaseUpsertPayload('egg_quality_defect_counts', {
      'id': 'c1',
      'eggQualityId': 'eq-1',
      'defectCode': 'dirty',
      'pctOfSample': 4.0,
    });
    expect(payload.keys, containsAll(
        ['egg_quality_id', 'defect_code', 'pct_of_sample']));
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/egg_grading_sync_test.dart`
Expected: FAIL — nothing pushes the table.

- [ ] **Step 3: Add the push**

In `startup_sync_service.dart`, add after `_pushDirtyPanelRows()`:

```dart
    progress(0.54, 'Uploading egg grading');
    pushed += await _pushDirtyEggGrading();
```

```dart
  /// Child rows must follow their parent egg_quality rows, or the remote
  /// foreign key rejects the batch.
  Future<int> _pushDirtyEggGrading() async {
    final dirty = await _eggGradingRepository.getDirtyRows();
    if (dirty.isEmpty) return 0;
    final ids = dirty
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .toList(growable: false);
    return _pushBatch(
      EggGradingRepository.table,
      dirty.length,
      upload: () => _supabaseService.upsertRowsStrict(
        EggGradingRepository.table,
        dirty.map(stripSyncMeta).toList(),
      ),
      markSynced: () => _eggGradingRepository.markRowsSynced(ids),
      markFailed: (error) => _eggGradingRepository.markRowsFailed(ids, error),
    );
  }
```

Inject `EggGradingRepository` through the constructor the same way `_panelSampleRepository` is injected.

- [ ] **Step 4: Add the pull**

In `supabase_service.dart`, add an `eggGradingCounts` int to `SupabasePullSummary` — field, `total` sum, `copyWith` — and an `upsertEggGradingCount` callback pulled right after the panel loop, matching the `lab_analysis` block's shape.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/services/`
Expected: PASS.

- [ ] **Step 6: Verify against the real project**

Confirm the cloud table from B1 exists and is empty:

MCP `execute_sql`: `select count(*) from public.egg_quality_defect_counts;`
Expected: `0` and no error. An error here means B1 was not applied and the push would have stuck every dirty row.

- [ ] **Step 7: Docs and commit**

`docs/DATABASE_SPEC.md`: add the table to the push order section. `docs/CHANGELOG.md`:

```markdown
- 2026-08-23: Egg grading results now sync to the cloud alongside the rest of
  the audit.
```

```bash
flutter analyze
git add lib/services/supabase/ test/services/egg_grading_sync_test.dart docs/
git commit -m "feat(sync): push and pull egg grading defect counts"
```

---

### Task B7: Full-station regression pass

**Files:**
- Test: `test/features/audits/full_audit_panel_smoke_test.dart` (extend)

**Interfaces:**
- Consumes: everything above.
- Produces: nothing new; this is the gate.

- [ ] **Step 1: Extend the smoke test**

Add an Egg-station scenario to `test/features/audits/full_audit_panel_smoke_test.dart` that walks the whole journey in one test: pooled entry → switch to compare by house → add three houses with distinct UV, weight, and grading values → rename house 2 → remove house 1 → save → reopen → assert every surviving house still owns its own values and grading.

- [ ] **Step 2: Run the whole suite**

Run: `flutter test`
Expected: PASS, no skips introduced.

- [ ] **Step 3: Analyze**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 4: Commit**

```bash
git add test/features/audits/full_audit_panel_smoke_test.dart
git commit -m "test(egg): end-to-end egg sampling and grading journey"
```

---

## Notes for the implementer

- **Never** use `pumpAndSettle()` in a `testWidgets` test that touches a real database — it hangs under `FakeAsync`. Use bounded `pump(Duration(...))` calls.
- The two sample-mode vocabularies are a real trap: `StationSampleModel` uses `pooled` / `comparison`; `AuditModel.sampleMode` (via `SampleMode`) uses `pool` / `compare`. Convert deliberately, never pass one through where the other is expected.
- `egg_storage` is pool-only and single-row. If a change makes you touch its measurement logic, you have gone outside this plan's scope — stop and ask.
- The existing dashboard join between `egg_storage` and `egg_quality` matches on hierarchy equality, so a pooled storage row never joins a per-house quality row. That is pre-existing and deliberately **not** fixed here. Do not "fix" it as a drive-by.
