# Sampling Schema Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the additive SQLite schema and repository foundation for panel-owned sampling data without breaking the current audit screens.

**Architecture:** Phase 1 introduces explicit panel tables and one sample table per panel, while keeping the legacy `sample_records` pathway intact. The new repository writes dashboard-ready panel rows and scoped sample rows with pool as the default and comparison scope as optional panel metadata.

**Tech Stack:** Flutter, Dart, sqflite, existing `DatabaseHelper`, existing repository/test patterns, `flutter test`.

---

## Scope

This plan implements the persistence foundation only. It does not remove legacy tables, switch every screen UI to the new repository, or rebuild dashboards in this pass. Those are follow-up phases after the new tables are present and tested.

## Files

- Create: `lib/data/models/panel_sample_schema.dart`
  - Owns table names, panel definitions, comparison layers, and column contracts.
- Create: `lib/data/models/panel_sample_model.dart`
  - Owns `PanelRecord`, `PanelSampleRecord`, and conversion helpers for SQLite maps.
- Create: `lib/data/repositories/panel_sample_repository.dart`
  - Saves and reads panel rows plus their sample rows in one transaction.
- Modify: `lib/data/database/database_helper.dart`
  - Bump database version from `31` to `32`.
  - Create new panel/sample tables during fresh database creation.
  - Apply v32 schema during upgrade.
- Modify: `docs/LIVING_SPEC.md`
  - Document the implemented Phase 1 panel/sample storage foundation.
- Test: `test/data/models/panel_sample_schema_test.dart`
  - Verifies the table matrix and comparison layer contract.
- Test: `test/data/repositories/panel_sample_repository_test.dart`
  - Verifies pool and comparison saves with dashboard context duplication.
- Modify/Test: `test/data/database/database_helper_migration_test.dart`
  - Verifies v32 creates the new tables and preserves legacy sample tables.

## Table Contract

Main panel tables:

```text
egg_storage
egg_quality
egg_weights
chick_pasgar
chick_weights
chick_yfbm
chick_cvt
chick_pm
fresh_egg_breakout
candled_egg_breakout
residue_breakout
setter_optimizing
hatcher_optimizing
```

Every main panel table has:

```sql
id TEXT PRIMARY KEY
sessionId TEXT NOT NULL
auditId TEXT
customerId TEXT NOT NULL
flockId TEXT
date TEXT NOT NULL
hatcheryId TEXT
breed TEXT
flockAgeWeeks INTEGER
mode TEXT NOT NULL DEFAULT 'pool'
compareLayer TEXT
notes TEXT
metricsJson TEXT
createdAt TEXT NOT NULL
updatedAt TEXT NOT NULL
```

Sample tables:

```text
egg_storage_samples
egg_quality_samples
egg_weights_samples
chick_pasgar_samples
chick_weights_samples
chick_yfbm_samples
chick_cvt_samples
chick_pm_samples
fresh_egg_breakout_samples
candled_egg_breakout_samples
residue_breakout_samples
setter_optimizing_samples
hatcher_optimizing_samples
```

Every sample table has:

```sql
id TEXT PRIMARY KEY
panelId TEXT NOT NULL
scopeType TEXT NOT NULL
scopeLabel TEXT NOT NULL
sampleIndex INTEGER NOT NULL DEFAULT 0
houseId TEXT
houseName TEXT
setterId TEXT
hatcherId TEXT
trolleyId TEXT
trolleyLabel TEXT
trayId TEXT
trayLabel TEXT
position TEXT
sampleSize INTEGER
metricType TEXT
value REAL
unit TEXT
summaryJson TEXT
rawJson TEXT
notes TEXT
createdAt TEXT NOT NULL
updatedAt TEXT NOT NULL
```

`panelId` references the matching main table `id` with `ON DELETE CASCADE`.

## Panel Rules

```dart
final expectedPanels = {
  'egg_storage': ['pool'],
  'egg_quality': ['pool', 'house'],
  'egg_weights': ['pool', 'house'],
  'chick_pasgar': ['pool', 'setter_hatcher'],
  'chick_weights': ['pool', 'house'],
  'chick_yfbm': ['pool', 'setter_hatcher'],
  'chick_cvt': ['pool', 'setter_hatcher'],
  'chick_pm': ['pool', 'setter_hatcher'],
  'fresh_egg_breakout': ['pool', 'house'],
  'candled_egg_breakout': ['pool', 'house', 'setter', 'tray'],
  'residue_breakout': ['pool', 'house', 'setter_hatcher', 'tray'],
  'setter_optimizing': ['pool', 'setter', 'trolley', 'tray'],
  'hatcher_optimizing': ['pool', 'hatcher', 'trolley', 'tray'],
};
```

`tray` comparison is available only for breakout and machine optimizing panels. Chick sections do not compare by tray. `setter_hatcher` samples require both `setterId` and `hatcherId`.

## Task 1: Schema Contract

**Files:**
- Create: `test/data/models/panel_sample_schema_test.dart`
- Create: `lib/data/models/panel_sample_schema.dart`

- [ ] **Step 1: Write failing schema tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';

void main() {
  test('panel schema exposes one main table and one sample table per panel', () {
    expect(PanelSampleSchema.panels.length, 13);
    expect(PanelSampleSchema.panels.map((panel) => panel.tableName), containsAll([
      'egg_quality',
      'egg_weights',
      'chick_pasgar',
      'chick_weights',
      'fresh_egg_breakout',
      'candled_egg_breakout',
      'residue_breakout',
      'setter_optimizing',
      'hatcher_optimizing',
    ]));

    for (final panel in PanelSampleSchema.panels) {
      expect(panel.sampleTableName, '${panel.tableName}_samples');
      expect(panel.allowedLayers.first, SamplingLayer.pool);
    }
  });

  test('only approved panels expose tray comparison', () {
    final trayPanels = PanelSampleSchema.panels
        .where((panel) => panel.allowedLayers.contains(SamplingLayer.tray))
        .map((panel) => panel.tableName)
        .toList();

    expect(trayPanels, [
      'candled_egg_breakout',
      'residue_breakout',
      'setter_optimizing',
      'hatcher_optimizing',
    ]);
  });

  test('chick hatchery panels compare setter and hatcher together', () {
    for (final tableName in ['chick_pasgar', 'chick_yfbm', 'chick_cvt', 'chick_pm']) {
      final panel = PanelSampleSchema.byTable(tableName);
      expect(panel.allowedLayers, contains(SamplingLayer.setterHatcher));
      expect(panel.allowedLayers, isNot(contains(SamplingLayer.tray)));
    }
  });
}
```

- [ ] **Step 2: Run test and verify it fails**

Run: `flutter test test/data/models/panel_sample_schema_test.dart`

Expected: FAIL because `panel_sample_schema.dart` does not exist.

- [ ] **Step 3: Implement schema contract**

Create `lib/data/models/panel_sample_schema.dart` with:

```dart
enum SamplingLayer {
  pool('pool'),
  house('house'),
  setter('setter'),
  hatcher('hatcher'),
  setterHatcher('setter_hatcher'),
  trolley('trolley'),
  tray('tray');

  const SamplingLayer(this.dbValue);
  final String dbValue;
}

class PanelSampleDefinition {
  const PanelSampleDefinition({
    required this.tableName,
    required this.allowedLayers,
  });

  final String tableName;
  final List<SamplingLayer> allowedLayers;

  String get sampleTableName => '${tableName}_samples';
}

class PanelSampleSchema {
  const PanelSampleSchema._();

  static const panels = <PanelSampleDefinition>[
    PanelSampleDefinition(tableName: 'egg_storage', allowedLayers: [SamplingLayer.pool]),
    PanelSampleDefinition(tableName: 'egg_quality', allowedLayers: [SamplingLayer.pool, SamplingLayer.house]),
    PanelSampleDefinition(tableName: 'egg_weights', allowedLayers: [SamplingLayer.pool, SamplingLayer.house]),
    PanelSampleDefinition(tableName: 'chick_pasgar', allowedLayers: [SamplingLayer.pool, SamplingLayer.setterHatcher]),
    PanelSampleDefinition(tableName: 'chick_weights', allowedLayers: [SamplingLayer.pool, SamplingLayer.house]),
    PanelSampleDefinition(tableName: 'chick_yfbm', allowedLayers: [SamplingLayer.pool, SamplingLayer.setterHatcher]),
    PanelSampleDefinition(tableName: 'chick_cvt', allowedLayers: [SamplingLayer.pool, SamplingLayer.setterHatcher]),
    PanelSampleDefinition(tableName: 'chick_pm', allowedLayers: [SamplingLayer.pool, SamplingLayer.setterHatcher]),
    PanelSampleDefinition(tableName: 'fresh_egg_breakout', allowedLayers: [SamplingLayer.pool, SamplingLayer.house]),
    PanelSampleDefinition(tableName: 'candled_egg_breakout', allowedLayers: [SamplingLayer.pool, SamplingLayer.house, SamplingLayer.setter, SamplingLayer.tray]),
    PanelSampleDefinition(tableName: 'residue_breakout', allowedLayers: [SamplingLayer.pool, SamplingLayer.house, SamplingLayer.setterHatcher, SamplingLayer.tray]),
    PanelSampleDefinition(tableName: 'setter_optimizing', allowedLayers: [SamplingLayer.pool, SamplingLayer.setter, SamplingLayer.trolley, SamplingLayer.tray]),
    PanelSampleDefinition(tableName: 'hatcher_optimizing', allowedLayers: [SamplingLayer.pool, SamplingLayer.hatcher, SamplingLayer.trolley, SamplingLayer.tray]),
  ];

  static PanelSampleDefinition byTable(String tableName) {
    return panels.firstWhere((panel) => panel.tableName == tableName);
  }
}
```

- [ ] **Step 4: Run test and verify it passes**

Run: `flutter test test/data/models/panel_sample_schema_test.dart`

Expected: PASS.

## Task 2: Database v32 Tables

**Files:**
- Modify: `lib/data/database/database_helper.dart`
- Modify/Test: `test/data/database/database_helper_migration_test.dart`

- [ ] **Step 1: Write failing migration test**

Add this test to `test/data/database/database_helper_migration_test.dart`:

```dart
test('v32 upgrade creates panel-owned sample tables and preserves legacy samples', () async {
  final helper = DatabaseHelper.instance;
  final db = await openDatabase(inMemoryDatabasePath, version: 31, onCreate: (db, version) async {
    await db.execute('CREATE TABLE sample_records (id TEXT PRIMARY KEY)');
  });

  await helper.applyV32UpgradeForTest(db);

  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
  );
  final names = tables.map((row) => row['name']).cast<String>().toSet();

  expect(names, contains('sample_records'));
  expect(names, contains('chick_pasgar'));
  expect(names, contains('chick_pasgar_samples'));
  expect(names, contains('egg_quality'));
  expect(names, contains('egg_quality_samples'));
  expect(names, contains('residue_breakout'));
  expect(names, contains('residue_breakout_samples'));
});
```

- [ ] **Step 2: Run test and verify it fails**

Run: `flutter test test/data/database/database_helper_migration_test.dart --plain-name "v32 upgrade creates panel-owned sample tables and preserves legacy samples"`

Expected: FAIL because `applyV32UpgradeForTest` does not exist.

- [ ] **Step 3: Implement v32 upgrade**

In `database_helper.dart`:

```dart
static const int _databaseVersion = 32;
```

Add the v32 hook in `_onUpgrade`:

```dart
if (oldVersion < 32) {
  await _applyV32Upgrade(db);
}
```

Call table creation from `_onCreate` after legacy sample tables:

```dart
await _createPanelSampleSchemaTables(db);
```

Add a test-only method:

```dart
@visibleForTesting
Future<void> applyV32UpgradeForTest(Database db) => _applyV32Upgrade(db);
```

Create `_applyV32Upgrade`, `_createPanelSampleSchemaTables`, `_createPanelTable`, and `_createPanelSampleTable`. Use `CREATE TABLE IF NOT EXISTS` and create indexes:

```sql
CREATE INDEX IF NOT EXISTS idx_${table}_session ON $table(sessionId)
CREATE INDEX IF NOT EXISTS idx_${table}_dashboard ON $table(customerId, flockId, date)
CREATE INDEX IF NOT EXISTS idx_${sampleTable}_panel ON $sampleTable(panelId)
CREATE INDEX IF NOT EXISTS idx_${sampleTable}_scope ON $sampleTable(scopeType, scopeLabel)
```

- [ ] **Step 4: Run migration test**

Run: `flutter test test/data/database/database_helper_migration_test.dart --plain-name "v32 upgrade creates panel-owned sample tables and preserves legacy samples"`

Expected: PASS.

## Task 3: Panel Models

**Files:**
- Create: `lib/data/models/panel_sample_model.dart`
- Create/Extend: `test/data/models/panel_sample_schema_test.dart`

- [ ] **Step 1: Write failing model test**

Add to `panel_sample_schema_test.dart`:

```dart
import 'package:hatchaudit/data/models/panel_sample_model.dart';

test('panel and sample records serialize dashboard context and scope identity', () {
  final panel = PanelRecord(
    id: 'panel-1',
    tableName: 'chick_pasgar',
    sessionId: 'session-1',
    auditId: 'audit-1',
    customerId: 'customer-1',
    flockId: 'flock-1',
    date: DateTime.utc(2026, 5, 13),
    hatcheryId: 'hatchery-1',
    breed: 'Ross308',
    flockAgeWeeks: 40,
    mode: 'compare',
    compareLayer: SamplingLayer.setterHatcher,
    metricsJson: '{"score":97.5}',
  );

  expect(panel.toMap()['compareLayer'], 'setter_hatcher');
  expect(panel.toMap()['date'], '2026-05-13T00:00:00.000Z');

  final sample = PanelSampleRecord(
    id: 'sample-1',
    panelId: 'panel-1',
    scopeType: SamplingLayer.setterHatcher,
    scopeLabel: 'S01 + H02',
    sampleIndex: 0,
    setterId: 'S01',
    hatcherId: 'H02',
    sampleSize: 100,
    summaryJson: '{"pasgarScore":97.5}',
  );

  expect(sample.toMap()['scopeType'], 'setter_hatcher');
  expect(sample.toMap()['setterId'], 'S01');
  expect(sample.toMap()['hatcherId'], 'H02');
});
```

- [ ] **Step 2: Run test and verify it fails**

Run: `flutter test test/data/models/panel_sample_schema_test.dart --plain-name "panel and sample records serialize dashboard context and scope identity"`

Expected: FAIL because `panel_sample_model.dart` does not exist.

- [ ] **Step 3: Implement models**

Create immutable model classes with `toMap()` and `fromMap()`:

```dart
class PanelRecord { ... }
class PanelSampleRecord { ... }
```

Default `mode` is `pool`. Default sample `scopeType` is `SamplingLayer.pool`, and default `scopeLabel` is `Random`.

- [ ] **Step 4: Run model tests**

Run: `flutter test test/data/models/panel_sample_schema_test.dart`

Expected: PASS.

## Task 4: Repository Save Path

**Files:**
- Create: `lib/data/repositories/panel_sample_repository.dart`
- Create: `test/data/repositories/panel_sample_repository_test.dart`

- [ ] **Step 1: Write failing repository tests**

Create tests for:

```dart
test('savePanelWithSamples writes one pool sample by default', () async { ... });
test('savePanelWithSamples writes setter+hatcher comparison with both machine ids', () async { ... });
test('savePanelWithSamples rejects disallowed tray comparison for chick weights', () async { ... });
```

The first test inserts `PanelRecord(tableName: 'egg_quality', mode: 'pool')` with one default `PanelSampleRecord(pool, Random)`, then reads from `egg_quality` and `egg_quality_samples`.

The second test inserts `PanelRecord(tableName: 'chick_pasgar', mode: 'compare', compareLayer: SamplingLayer.setterHatcher)` with a sample containing both `setterId` and `hatcherId`, then verifies both values are saved.

The third test uses `tableName: 'chick_weights'` and `scopeType: SamplingLayer.tray`, expecting `ArgumentError`.

- [ ] **Step 2: Run tests and verify they fail**

Run: `flutter test test/data/repositories/panel_sample_repository_test.dart`

Expected: FAIL because `PanelSampleRepository` does not exist.

- [ ] **Step 3: Implement repository**

Create methods:

```dart
class PanelSampleRepository {
  PanelSampleRepository({DatabaseHelper? databaseHelper});

  Future<void> savePanelWithSamples({
    required PanelRecord panel,
    required List<PanelSampleRecord> samples,
  });

  Future<List<Map<String, Object?>>> getPanelSamples({
    required String panelTable,
    required String panelId,
  });
}
```

Validation:

```dart
final definition = PanelSampleSchema.byTable(panel.tableName);
for (final sample in samples) {
  if (!definition.allowedLayers.contains(sample.scopeType)) throw ArgumentError(...);
  if (sample.scopeType == SamplingLayer.setterHatcher &&
      ((sample.setterId == null || sample.setterId!.isEmpty) ||
       (sample.hatcherId == null || sample.hatcherId!.isEmpty))) {
    throw ArgumentError('setter_hatcher samples require setterId and hatcherId');
  }
}
```

Write panel and samples in one transaction using `ConflictAlgorithm.replace`.

- [ ] **Step 4: Run repository tests**

Run: `flutter test test/data/repositories/panel_sample_repository_test.dart`

Expected: PASS.

## Task 5: Compatibility Smoke

**Files:**
- Existing legacy code only unless tests need setup helpers.

- [ ] **Step 1: Run current narrow legacy tests**

Run:

```bash
flutter test test/data/repositories/station_sample_repository_test.dart
flutter test test/data/database/database_helper_migration_test.dart
```

Expected: PASS or pre-existing failures identified before any production edits.

- [ ] **Step 2: If a new failure is caused by v32 schema changes, fix the v32 additive code only**

Allowed fixes:

```text
Missing import
Invalid SQL type
Index name collision
Foreign key syntax issue
Test helper visibility issue
```

Do not rewrite `StationSampleRepository` in this phase.

## Task 6: Living Spec and Verification

**Files:**
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Update implemented behavior**

Add a short section:

```markdown
## Sampling Storage Foundation

Panel-owned sample storage exists alongside the legacy station sample tables. Each implemented panel has a main table for dashboard context and a `{panel}_samples` table for pool or comparison samples. Pool is saved as `scopeType=pool` and `scopeLabel=Random`. Comparison samples store the selected scope identity, including house, setter, hatcher, trolley, and tray fields only when relevant.
```

- [ ] **Step 2: Run final validation**

Run:

```bash
flutter test test/data/models/panel_sample_schema_test.dart test/data/repositories/panel_sample_repository_test.dart test/data/database/database_helper_migration_test.dart
```

Expected: PASS.

## Self-Review

Spec coverage:

- Panel-owned main/sample tables are covered by Tasks 1 and 2.
- Pool default and comparison layer rules are covered by Tasks 1, 3, and 4.
- Dashboard duplicated context is covered by Tasks 2, 3, and 4.
- Legacy compatibility is covered by Task 5.
- Living documentation is covered by Task 6.

Placeholder scan:

- This plan intentionally avoids unfinished-marker language and defers UI/dashboard migration as a named follow-up phase outside this plan.

Type consistency:

- `SamplingLayer.setterHatcher` serializes to `setter_hatcher` in every model, schema, and repository task.
- `PanelRecord.tableName` determines the main table and matching sample table through `PanelSampleSchema.byTable`.
