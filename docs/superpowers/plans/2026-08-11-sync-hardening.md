# Sync Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the three critical sync data-loss bugs (photo false-synced, tombstone false-synced, bulk-push clobber) plus the two high-severity issues (whole-sync abort on one bad row, mark-synced race).

**Architecture:** The app is offline-first Flutter + SQLite (camelCase) mirrored to Supabase (snake_case). `StartupSyncService._run` orders: pull tombstones → apply local deletes → push dirty rows → push deletes → pull all tables → photo sync. Fixes stay inside this flow: make silent no-ops throw so callers' existing failure paths engage; extend the established per-row dirty tracking (`syncStatus`/`dirtyAt`/`lastSyncedAt`/`syncError`) to the three reference tables (customers, hatcheries, flocks) that still bulk-push; guard mark-synced with a dirty-read cutoff so mid-push edits survive.

**Tech Stack:** Flutter/Dart, sqflite (+ `sqflite_common_ffi` for tests), `supabase_flutter`, `mocktail`.

## Global Constraints

- DB version goes 56 → 57. One migration only (`_applyV57Upgrade`), using the existing `_ensureColumns` helper in `lib/data/database/database_migrations.dart`.
- Never push device-local sync columns to Supabase. `toSupabaseUpsertPayload`/`stripSyncMeta` already strip `kSyncMetaColumns` (`syncStatus`, `dirtyAt`, `lastSyncedAt`, `syncError`) — new code must route pushes through `upsertRowsStrict` so this keeps holding.
- Gate every task on: `flutter analyze` (zero new issues) and the task's tests passing. STOP on failure; do not proceed to the next task.
- Do not change the Supabase cloud schema. All changes are local.
- SQLite columns are camelCase locally; remote rows arrive snake_case. Repos already normalize via `_camelize` — keep that pattern.
- Run the full test suite (`flutter test`) at the end of Task 6.

## Background for the implementer (read first)

- `SupabaseService._prepareRemoteAccess()` returns `false` when offline/unconfigured. Several methods do `if (!await _prepareRemoteAccess()) return;` — a **silent no-op** — and callers then record success. That is bug class #1.
- `lib/services/supabase/startup_sync_service.dart` `_pushLocalData` pushes **all** customers/hatcheries/flocks every run (no dirty filter). A device with a stale copy overwrites newer remote edits before the pull happens; the pull then reads back the clobbered data, so the conflict check never fires. That is bug #3.
- Dirty-tracked tables (sessions, panels, govee, dashboard actions, lab analysis, performance tables) all follow the same repo pattern: `getDirty*` returns rows `WHERE syncStatus IN ('pending','failed')`, push, then `mark*Synced(ids)` / `mark*Failed(ids, error)`. The mark-synced update is unconditional by id — an edit landing between the dirty read and the mark gets stamped `synced` and is never pushed (bug #5).
- The test conventions to copy:
  - Repo tests: real SQLite via FFI, hand-built schema, mocked `DatabaseHelper` — see `test/features/audits/sync_tracking_repository_test.dart`.
  - Sync-service tests: mocktail mocks for every repo + `SupabaseService` — see `test/services/supabase/startup_sync_service_test.dart`.
  - `SupabaseService` has `...ForTesting` constructor injectables for config/network/init/client.

---

### Task 1: `uploadPhoto` throws when Supabase is unavailable

Bug: `uploadPhoto` silently returns when offline; `PhotoSyncService.syncPending` then marks the photo `synced`, permanently removing it from the upload queue.

**Files:**
- Modify: `lib/services/supabase/supabase_service.dart:462-464`
- Test: `test/services/photo/photo_sync_service_offline_test.dart` (create)

**Interfaces:**
- Produces: `uploadPhoto(PhotoModel)` now throws `StateError('Supabase sync is not available')` instead of silently returning. Caller `PhotoSyncService.syncPending` already catches and marks `failed` — no caller changes needed.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hatchaudit/data/models/photo_model.dart';
import 'package:hatchaudit/data/repositories/photo_repository.dart';
import 'package:hatchaudit/services/photo/photo_sync_service.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';

class _MockPhotoRepository extends Mock implements PhotoRepository {}

class _MockSupabaseService extends Mock implements SupabaseService {}

void main() {
  late _MockPhotoRepository repo;
  late _MockSupabaseService supabase;
  late PhotoSyncService service;

  final photo = PhotoModel(
    id: 'photo-1',
    filePath: '/tmp/does-not-matter.jpg',
    createdAt: DateTime(2026, 8, 1),
    sessionId: 'session-1',
    panelName: 'egg_storage',
    panelRowId: 'row-1',
    fieldKey: 'photo',
    uploadStatus: 'local',
  );

  setUp(() {
    repo = _MockPhotoRepository();
    supabase = _MockSupabaseService();
    service = PhotoSyncService(
      repository: repo,
      supabase: supabase,
      fileSyncSupported: true,
    );
    when(() => supabase.refreshAvailability()).thenAnswer((_) async => true);
    when(() => repo.getByStatus('local')).thenAnswer((_) async => [photo]);
    when(() => repo.getByStatus('failed')).thenAnswer((_) async => const []);
    when(() => repo.updateStatus(any(), any())).thenAnswer((_) async {});
  });

  test('a photo is marked failed, not synced, when upload throws offline',
      () async {
    when(() => supabase.uploadPhoto(photo))
        .thenThrow(StateError('Supabase sync is not available'));

    await service.syncPending();

    verify(() => repo.updateStatus('photo-1', 'failed')).called(1);
    verifyNever(() => repo.updateStatus('photo-1', 'synced'));
  });
}
```

Note: `syncPending` checks `File(photo.filePath).exists()` before uploading. The test file path must exist for the flow to reach `uploadPhoto` — create it in `setUp`:

```dart
import 'dart:io';
// in setUp(), before the test body runs:
File('/tmp/does-not-matter.jpg').writeAsBytesSync([1, 2, 3]);
```

(If sandboxed tmp is a problem, use `Directory.systemTemp.createTempSync()` and build the photo's `filePath` from it.)

- [ ] **Step 2: Run test to verify current state**

Run: `flutter test test/services/photo/photo_sync_service_offline_test.dart`
Expected: PASS already (mock throws). This test pins the *caller* contract. The real bug is in `SupabaseService`; the mock proves the caller handles a throw correctly. Keep the test; the behavioral change is Step 3.

- [ ] **Step 3: Make `uploadPhoto` throw instead of silently returning**

In `lib/services/supabase/supabase_service.dart`, change:

```dart
  Future<void> uploadPhoto(PhotoModel photo) async {
    if (!await _prepareRemoteAccess()) return;
```

to:

```dart
  Future<void> uploadPhoto(PhotoModel photo) async {
    if (!await _prepareRemoteAccess()) {
      throw StateError('Supabase sync is not available');
    }
```

- [ ] **Step 4: Verify no other caller breaks**

Run: `grep -rn "uploadPhoto(" lib --include="*.dart" | grep -v supabase_service.dart`
Expected: only `lib/services/photo/photo_sync_service.dart:105` (inside its try/catch that marks `failed`). If any other caller appears, wrap it in try/catch with an explicit failure path before proceeding.

- [ ] **Step 5: Analyze + test + commit**

Run: `flutter analyze lib/services test/services && flutter test test/services/photo/`
Expected: clean, all pass.

```bash
git add -A && git commit -m "fix(sync): uploadPhoto throws when offline so photos are not falsely marked synced"
```

---

### Task 2: `deleteRows` throws when Supabase is unavailable

Bug: `deleteRows` silently returns when offline; `_pushPendingDeletes` then marks tombstones `synced`. The remote row is never deleted → every later sync re-pulls it, local applies the tombstone again, and other devices never see the delete (zombie row).

**Files:**
- Modify: `lib/services/supabase/supabase_service.dart:407-419`
- Test: `test/services/supabase/supabase_service_offline_test.dart` (create)

**Interfaces:**
- Produces: `deleteRows(String table, List<String> ids)` still returns silently for empty ids, but throws `StateError('Supabase sync is not available')` when remote access is unavailable. Caller `StartupSyncService._pushPendingDeletes` already try/catches per table and calls `markFailed` — no caller changes needed (existing test `reports pending deletes when remote row deletion fails` covers that path).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/services/supabase/supabase_service.dart';

void main() {
  SupabaseService offlineService() => SupabaseService(
        isConfiguredForTesting: () => true,
        reloadConfigForTesting: () async {},
        initializeSupabaseForTesting: () async => false,
        checkNetworkAvailableForTesting: () async => false,
        clientForTesting: () => throw StateError('client must not be touched'),
      );

  test('deleteRows throws when Supabase is unavailable', () async {
    await expectLater(
      offlineService().deleteRows('audit_sessions', ['row-1']),
      throwsStateError,
    );
  });

  test('deleteRows still no-ops silently for empty id lists', () async {
    await offlineService().deleteRows('audit_sessions', const []);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/supabase/supabase_service_offline_test.dart`
Expected: first test FAILS (completes normally instead of throwing).

- [ ] **Step 3: Make `deleteRows` throw**

In `lib/services/supabase/supabase_service.dart`, change:

```dart
  Future<void> deleteRows(String table, List<String> ids) async {
    final rowIds = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (rowIds.isEmpty || !await _prepareRemoteAccess()) return;
```

to:

```dart
  Future<void> deleteRows(String table, List<String> ids) async {
    final rowIds = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (rowIds.isEmpty) return;
    if (!await _prepareRemoteAccess()) {
      throw StateError('Supabase sync is not available');
    }
```

- [ ] **Step 4: Verify callers**

Run: `grep -rn "\.deleteRows(" lib --include="*.dart" | grep -v panel_sample_repository | grep -v Session`
Expected: only `startup_sync_service.dart:474` (already inside try/catch → `markFailed`). The `deleteRowsBySessionId*` hits are a different (local) API — ignore them.

- [ ] **Step 5: Analyze + test + commit**

Run: `flutter analyze lib/services test/services && flutter test test/services/supabase/`
Expected: clean; existing `startup_sync_service_test.dart` still passes (its delete-failure test already models a throwing `deleteRows`).

```bash
git add -A && git commit -m "fix(sync): deleteRows throws when offline so tombstones are not falsely marked synced"
```

---

### Task 3: v57 migration — sync columns for customers & hatcheries, `lastSyncedAt` for flocks

Prepares the schema for dirty-tracking the three reference tables. `flocks` already has `updatedAt`, `syncStatus`, `dirtyAt`, `syncError` (since v51) — it only lacks `lastSyncedAt`. `customers` and `hatcheries` have none of them.

Decision locked in: new columns default `syncStatus = 'pending'`, so every existing row pushes once on the first post-upgrade sync — identical net effect to today's bulk push, then it settles to incremental.

**Files:**
- Modify: `lib/data/database/database_helper.dart` (version 47 → `version: 57` at line ~47; `_onUpgrade` chain; `_criticalColumns` map)
- Modify: `lib/data/database/database_migrations.dart` (add `_applyV57Upgrade`)
- Modify: `lib/data/database/database_schema.dart` (CREATE TABLE for `customers`, `flocks`, `hatcheries`)
- Test: `test/data/database/database_helper_migration_test.dart` (extend)

**Interfaces:**
- Produces: local tables `customers` and `hatcheries` gain `syncStatus TEXT NOT NULL DEFAULT 'pending'`, `dirtyAt TEXT`, `lastSyncedAt TEXT`, `syncError TEXT`; `flocks` gains `lastSyncedAt TEXT`. Task 4 repos rely on these exact camelCase names.

- [ ] **Step 1: Write the failing migration test**

Open `test/data/database/database_helper_migration_test.dart`, follow its existing pattern for asserting post-upgrade columns (open a v56-shaped DB, run `_onUpgrade` via `DatabaseHelper`, assert via `PRAGMA table_info`). Add:

```dart
test('v57 adds sync tracking columns to reference tables', () async {
  // Use the test file's existing harness for opening a legacy DB and
  // upgrading to the current version, then:
  Future<Set<String>> cols(String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((row) => row['name'] as String).toSet();
  }

  for (final table in ['customers', 'hatcheries']) {
    final names = await cols(table);
    expect(names, containsAll(['syncStatus', 'dirtyAt', 'lastSyncedAt', 'syncError']),
        reason: '$table should carry sync tracking columns after v57');
  }
  expect(await cols('flocks'), contains('lastSyncedAt'));
});
```

(Adapt variable names to the harness in that file — it already opens/upgrades a DB; do not invent a new harness.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/database/database_helper_migration_test.dart`
Expected: FAIL — columns missing.

- [ ] **Step 3: Implement the migration**

In `lib/data/database/database_migrations.dart`, append (mirroring `_applyV51Upgrade`'s style):

```dart
Future<void> _applyV57Upgrade(Database db) async {
  if (await _tableExists(db, 'customers')) {
    await _ensureColumns(db, 'customers', const [
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ]);
  }
  if (await _tableExists(db, 'hatcheries')) {
    await _ensureColumns(db, 'hatcheries', const [
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ]);
  }
  if (await _tableExists(db, 'flocks')) {
    await _ensureColumns(db, 'flocks', const ['lastSyncedAt TEXT']);
  }
}
```

In `lib/data/database/database_helper.dart`:
1. `version: 56` → `version: 57`.
2. In `_onUpgrade`, after the `oldVersion < 56` block:

```dart
    if (oldVersion < 57) {
      await _applyV57Upgrade(db);
    }
```

3. In `_criticalColumns` (surgical repair map), add/extend entries so drifted DBs self-heal:

```dart
    'customers': [
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
    'hatcheries': [
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
```

and append `'lastSyncedAt TEXT'` to the existing `flocks` entry.

- [ ] **Step 4: Keep fresh-install schema in parity**

In `lib/data/database/database_schema.dart`:
- `customers` CREATE TABLE: after `createdBy TEXT`, add

```sql
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT
```

- `flocks` CREATE TABLE: add `lastSyncedAt TEXT,` next to the existing `dirtyAt TEXT,`.
- `hatcheries` CREATE TABLE (in `_createHatcheryTables`): after `createdBy TEXT`, add the same four columns as customers.

(Mind trailing commas before the `FOREIGN KEY` lines.)

- [ ] **Step 5: Run migration + integrity + parity tests**

Run: `flutter test test/data/database/`
Expected: all pass — including the create-vs-upgrade parity coverage in this directory. If parity fails, the CREATE TABLE edits in Step 4 don't match the migration in Step 3; fix until identical column sets.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(db): v57 adds sync tracking columns to customers, hatcheries, flocks"
```

---

### Task 4: Dirty-tracking API in customer, hatchery, and flock repositories

Wire the write paths to stamp rows dirty, remote upserts to stamp them synced, and add the dirty-read/mark API the sync service will consume in Task 5. Race-safe from day one: `markRowsSynced` only clears rows whose `dirtyAt` hasn't moved past the value captured at `getDirtyRows` time.

**Files:**
- Modify: `lib/data/repositories/customer_repository.dart`
- Modify: `lib/data/repositories/hatchery_repository.dart`
- Modify: `lib/data/repositories/flock_repository.dart`
- Test: `test/data/repositories/reference_dirty_tracking_test.dart` (create)

**Interfaces:**
- Consumes: Task 3 columns.
- Produces (identical shape on all three repos; sync service in Task 5 calls exactly these):
  - `Future<List<Map<String, dynamic>>> getDirtyRows()` — raw table maps `WHERE syncStatus IN ('pending','failed')`, ordered `dirtyAt ASC, id ASC`; records the dirty-read cutoff internally.
  - `Future<void> markRowsSynced(List<String> ids)` — clears only rows still at-or-before the recorded cutoff.
  - `Future<void> markRowsFailed(List<String> ids, Object error)`.
  - `Future<String?> getRowSyncStatus(String id)` — for the pull-side dirty guard.
  - Local write paths (`insertCustomer`, `updateCustomer`, `insertHatchery`, `updateHatchery`, `insertFlock`, `updateFlock`) stamp `syncStatus='pending'`, `dirtyAt=now`.
  - Remote upserts (`upsertCustomer`, `upsertHatchery`, `upsertFlock` — the pull path) stamp `syncStatus='synced'`, `dirtyAt=null`, `lastSyncedAt=now`, `syncError=null`.

- [ ] **Step 1: Write the failing tests**

Create `test/data/repositories/reference_dirty_tracking_test.dart` following the FFI pattern of `test/features/audits/sync_tracking_repository_test.dart` (in-memory FFI DB, hand-built schema with the Task 3 columns, mocktail `DatabaseHelper`). Note: `CustomerRepository` currently constructs `DatabaseHelper()` directly (`final dbHelper = DatabaseHelper();`) — add an injectable constructor matching the other repos:

```dart
CustomerRepository({DatabaseHelper? dbHelper})
    : dbHelper = dbHelper ?? DatabaseHelper();
final DatabaseHelper dbHelper;
```

(Check hatchery/flock repos: if they also hard-construct, give them the same injectable constructor.)

Test cases (write all six per repo via a shared `for` loop over table configs, or write them for `CustomerRepository` and copy for the other two — do not skip any repo):

```dart
test('insert stamps the row pending with a dirtyAt', () async {
  await repo.insertCustomer(_customer('c1'));
  final row = await rowById('customers', 'c1');
  expect(row['syncStatus'], 'pending');
  expect(row['dirtyAt'], isNotNull);
});

test('remote upsert stamps the row synced', () async {
  await repo.upsertCustomer({
    'id': 'c1',
    'name': 'Remote',
    'created_at': '2026-08-01T00:00:00.000',
    'created_by': 'cloud',
  });
  final row = await rowById('customers', 'c1');
  expect(row['syncStatus'], 'synced');
  expect(row['dirtyAt'], isNull);
});

test('a local edit re-dirties a previously synced row', () async {
  await repo.upsertCustomer({'id': 'c1', 'name': 'Remote'});
  await repo.updateCustomer(_customer('c1'));
  final row = await rowById('customers', 'c1');
  expect(row['syncStatus'], 'pending');
});

test('getDirtyRows returns only pending/failed rows', () async {
  await repo.insertCustomer(_customer('c1'));
  await repo.upsertCustomer({'id': 'c2', 'name': 'Remote'});
  final dirty = await repo.getDirtyRows();
  expect(dirty.map((row) => row['id']), ['c1']);
});

test('markRowsSynced clears dirty state', () async {
  await repo.insertCustomer(_customer('c1'));
  await repo.getDirtyRows();
  await repo.markRowsSynced(['c1']);
  final row = await rowById('customers', 'c1');
  expect(row['syncStatus'], 'synced');
  expect(row['dirtyAt'], isNull);
  expect(row['lastSyncedAt'], isNotNull);
});

test('an edit during the push window survives markRowsSynced', () async {
  await repo.insertCustomer(_customer('c1'));
  await repo.getDirtyRows();               // capture cutoff
  await Future<void>.delayed(const Duration(milliseconds: 5));
  await repo.updateCustomer(_customer('c1', name: 'Edited mid-push'));
  await repo.markRowsSynced(['c1']);       // must NOT clear the newer edit
  final row = await rowById('customers', 'c1');
  expect(row['syncStatus'], 'pending');
  expect(row['dirtyAt'], isNotNull);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/data/repositories/reference_dirty_tracking_test.dart`
Expected: FAIL — methods don't exist / stamps missing.

- [ ] **Step 3: Implement — CustomerRepository (canonical implementation, copy to the other two)**

```dart
  static const _table = 'customers';

  String _nowStamp() => DateTime.now().toIso8601String();

  /// dirtyAt value captured at the last getDirtyRows() call. markRowsSynced
  /// only clears rows whose dirtyAt is at or before this cutoff, so an edit
  /// landing while a push is in flight stays pending.
  String? _dirtyReadCutoff;

  Future<List<Map<String, dynamic>>> getDirtyRows() async {
    final db = await dbHelper.db;
    _dirtyReadCutoff = _nowStamp();
    final rows = await db.query(
      _table,
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'dirtyAt ASC, id ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> markRowsSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await dbHelper.db;
    final cutoff = _dirtyReadCutoff ?? _nowStamp();
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      _table,
      {
        'syncStatus': 'synced',
        'dirtyAt': null,
        'lastSyncedAt': _nowStamp(),
        'syncError': null,
      },
      where:
          'id IN ($placeholders) AND (dirtyAt IS NULL OR dirtyAt <= ?)',
      whereArgs: [...ids, cutoff],
    );
  }

  Future<void> markRowsFailed(List<String> ids, Object error) async {
    if (ids.isEmpty) return;
    final db = await dbHelper.db;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      _table,
      {'syncStatus': 'failed', 'syncError': error.toString()},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<String?> getRowSyncStatus(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      _table,
      columns: ['syncStatus'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['syncStatus']?.toString();
  }
```

Stamp the write paths:

```dart
  Future<void> insertCustomer(CustomerModel customer) async {
    final db = await dbHelper.db;
    await _upsertById(db, 'customers', {
      ...customer.toMap(),
      'syncStatus': 'pending',
      'dirtyAt': _nowStamp(),
    });
  }

  Future<void> updateCustomer(CustomerModel customer) async {
    final db = await dbHelper.db;
    await db.update(
      'customers',
      {
        ...customer.toMap(),
        'syncStatus': 'pending',
        'dirtyAt': _nowStamp(),
      },
      where: 'id = ?',
      whereArgs: [customer.id],
    );
  }
```

Stamp the remote path (pull) as synced — in `upsertCustomer`, after `normalized` is built:

```dart
  Future<void> upsertCustomer(Map<String, dynamic> row) async {
    final db = await dbHelper.db;
    final columns = await _tableColumns(db, 'customers');
    final normalized = _filterColumns(_normalizeCustomerRow(row), columns)
      ..addAll({
        'syncStatus': 'synced',
        'dirtyAt': null,
        'lastSyncedAt': _nowStamp(),
        'syncError': null,
      });
    await _upsertById(db, 'customers', normalized);
  }
```

- [ ] **Step 4: Implement — HatcheryRepository and FlockRepository**

Same code, adjusted:
- Hatchery: `_table = 'hatcheries'`; stamp `insertHatchery`/`updateHatchery`; synced-stamp `upsertHatchery` (it already normalizes via `_normalize(row)` — add the same `..addAll` synced stamps after column filtering).
- Flock: `_table = 'flocks'`; stamp `insertFlock`/`updateFlock`; synced-stamp `upsertFlock`. Flock's model already carries `updatedAt` — do not touch it; only add the sync-meta stamps.
- If any of these repos' remote upsert lacks the column-filter step customers has, keep that repo's existing normalization and just add the stamps.

- [ ] **Step 5: Run tests**

Run: `flutter test test/data/repositories/reference_dirty_tracking_test.dart`
Expected: all pass.

- [ ] **Step 6: Check for other write-path callers that bypass the repos**

Run: `grep -rn "insert('customers'\|insert('hatcheries'\|insert('flocks'\|update('customers'\|update('hatcheries'\|update('flocks'" lib --include="*.dart" | grep -v repositories`
Expected: no hits (all writes go through the repos). Any hit must be routed through the repo or given the same stamps.

- [ ] **Step 7: Analyze + commit**

Run: `flutter analyze lib/data test/data && flutter test test/data/`

```bash
git add -A && git commit -m "feat(sync): dirty tracking for customers, hatcheries, flocks"
```

---

### Task 5: Sync service — dirty-only reference push, per-table failure isolation, pull dirty-guard, honest counts

Replaces the three bulk pushes with dirty-only pushes (fixes the clobber, bug #3), wraps each reference push in its own try/catch so one bad table no longer aborts the entire sync including the pull (bug #4), skips pull-overwrites of locally-dirty reference rows, and stops counting unchanged rows/photos as "pushed".

**Files:**
- Modify: `lib/services/supabase/startup_sync_service.dart` (`_pushLocalData`, `_pullRemoteData`, pull upsert callbacks)
- Test: `test/services/supabase/startup_sync_service_test.dart` (modify existing expectations + add cases)

**Interfaces:**
- Consumes: Task 4 repo API (`getDirtyRows`, `markRowsSynced`, `markRowsFailed`, `getRowSyncStatus`) on customer/hatchery/flock repos.
- Produces: `SyncOutcome.pushed` now counts only rows actually uploaded this run (dirty rows; photo queue no longer inflates it). Push order preserved: customers → pre-flock operational → hatcheries → flocks → post-flock operational → sessions → panels → govee → dashboard → lab.

- [ ] **Step 1: Update the existing tests that pin old behavior**

In `test/services/supabase/startup_sync_service_test.dart`:

1. Wire the three new repo mocks (defaults in the shared setup):

```dart
    when(() => customers.getDirtyRows()).thenAnswer((_) async => const []);
    when(() => customers.markRowsSynced(any())).thenAnswer((_) async {});
    when(() => customers.markRowsFailed(any(), any())).thenAnswer((_) async {});
    when(() => customers.getRowSyncStatus(any())).thenAnswer((_) async => 'synced');
    // same four stubs for hatcheries and flocks
```

2. Replace `test('surfaces a blocked customer upload before dependent rows', ...)` (line ~384) — the abort-on-failure contract is intentionally gone. New contract:

```dart
  test('a failed customer push marks rows failed and the sync continues', () async {
    when(() => customers.getDirtyRows()).thenAnswer(
      (_) async => [
        {'id': 'customer-1', 'name': 'Customer 1', 'syncStatus': 'pending'},
      ],
    );
    when(() => supabase.upsertRowsStrict('customers', any()))
        .thenThrow(StateError('customer insert was not persisted'));

    final outcome = await service().run();

    expect(outcome.online, isTrue);
    verify(() => customers.markRowsFailed(['customer-1'], any())).called(1);
    // The pull still ran:
    verify(() => supabase.pullFromSupabase(
          upsertCustomer: any(named: 'upsertCustomer'),
          upsertFlock: any(named: 'upsertFlock'),
          upsertHatchery: any(named: 'upsertHatchery'),
          upsertAuditSession: any(named: 'upsertAuditSession'),
          upsertPhoto: any(named: 'upsertPhoto'),
          upsertBmkBreed: any(named: 'upsertBmkBreed'),
          upsertBmkEggBreakout: any(named: 'upsertBmkEggBreakout'),
          upsertGoveeDailyCapture: any(named: 'upsertGoveeDailyCapture'),
          upsertDashboardAction: any(named: 'upsertDashboardAction'),
          upsertLabAnalysisRow: any(named: 'upsertLabAnalysisRow'),
          upsertPanelRow: any(named: 'upsertPanelRow'),
          upsertSyncTombstone: any(named: 'upsertSyncTombstone'),
        )).called(1);
  });
```

(Match the `pullFromSupabase` verify signature to how the file already verifies it elsewhere — reuse its helper if one exists.)

3. Update any test stubbing `getAllCustomers`/`getAllHatcheries`/`getAllFlocks` for push purposes to stub `getDirtyRows` instead. `getAllCustomers` may still be stubbed where the *pull*/reload path needs it.

4. Add the clobber-prevention test (the core of bug #3):

```dart
  test('clean reference rows are not pushed', () async {
    // all three getDirtyRows return [] (default stubs)
    await service().run();
    verifyNever(() => supabase.upsertRowsStrict('customers', any()));
    verifyNever(() => supabase.upsertRowsStrict('hatcheries', any()));
    verifyNever(() => supabase.upsertRowsStrict('flocks', any()));
  });

  test('locally dirty reference rows are not overwritten by the pull', () async {
    when(() => customers.getRowSyncStatus('customer-1'))
        .thenAnswer((_) async => 'pending');
    // Capture the upsertCustomer callback passed to pullFromSupabase, invoke it
    // with a remote row for customer-1 (the file already uses this capture
    // pattern for other pull tests), then:
    verifyNever(() => customers.upsertCustomer(any()));
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/supabase/startup_sync_service_test.dart`
Expected: new/updated tests FAIL (service still bulk-pushes and rethrows).

- [ ] **Step 3: Implement the push changes**

In `startup_sync_service.dart`, replace the three bulk blocks in `_pushLocalData` with dirty pushes. Add this helper (mirrors `_pushDirtyOperationalRows`):

```dart
  Future<int> _pushDirtyReferenceRows(
    String table, {
    required Future<List<Map<String, dynamic>>> Function() getDirtyRows,
    required Future<void> Function(List<String> ids) markSynced,
    required Future<void> Function(List<String> ids, Object error) markFailed,
  }) async {
    final dirty = await getDirtyRows();
    if (dirty.isEmpty) return 0;
    final ids = dirty
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .toList(growable: false);
    try {
      await _supabaseService.upsertRowsStrict(
        table,
        dirty.map(stripSyncMeta).toList(growable: false),
      );
      await markSynced(ids);
      return dirty.length;
    } catch (error) {
      await markFailed(ids, error);
      return 0;
    }
  }
```

Then in `_pushLocalData`:

```dart
    progress(0.12, 'Uploading customers');
    pushed += await _pushDirtyReferenceRows(
      'customers',
      getDirtyRows: _customerRepository.getDirtyRows,
      markSynced: _customerRepository.markRowsSynced,
      markFailed: _customerRepository.markRowsFailed,
    );
```

…and the equivalent for `hatcheries` (progress 0.22) and `flocks` (progress 0.32), deleting the `getAllCustomers`/`getAllHatcheries`/`getAllFlocks` bulk pushes.

Fix the photo count inflation at the end of `_pushLocalData` — delete:

```dart
    final photos = await _photoRepository.getAllPhotos();
    pushed += photos.length;
```

(keep the `progress(0.69, ...)` line; the actual photo upload work happens later in `_photoSyncService.syncPending()`).

FK-ordering note (leave as a comment in the code): if the customers push fails, dependent pushes (hatcheries/flocks/sessions) may fail remotely on FK violations — each marks its own rows failed and everything retries next sync once customers goes through. That is intended degradation, not a bug.

- [ ] **Step 4: Implement the pull dirty-guard**

In `_pullRemoteData`, the three reference callbacks currently route through `_upsertRemoteRow`. Change them to skip locally-dirty rows:

```dart
      upsertCustomer: (row) => _upsertReferenceRow(
        'customers',
        row,
        getSyncStatus: _customerRepository.getRowSyncStatus,
        upsert: (value) => _customerRepository.upsertCustomer(value),
      ),
```

(same shape for `upsertHatchery` and `upsertFlock`), with:

```dart
  /// Reference tables have no updatedAt conflict check (customers/hatcheries
  /// don't carry updatedAt). Guard instead: while a local edit is pending or
  /// failed, the local row wins; it will be pushed on this or the next run.
  Future<void> _upsertReferenceRow(
    String table,
    Map<String, dynamic> remoteRow, {
    required Future<String?> Function(String id) getSyncStatus,
    required Future<void> Function(Map<String, dynamic> row) upsert,
  }) async {
    if (_hasPendingLocalDelete(table, remoteRow)) return;
    final id = _rowId(remoteRow);
    if (id != null) {
      final status = await getSyncStatus(id);
      if (status == 'pending' || status == 'failed') return;
    }
    await upsert(remoteRow);
  }
```

- [ ] **Step 5: Run the full sync-service suite**

Run: `flutter test test/services/supabase/`
Expected: all pass, including `startup_sync_incoming_test.dart`.

- [ ] **Step 6: Analyze + commit**

Run: `flutter analyze lib/services test/services`

```bash
git add -A && git commit -m "fix(sync): dirty-only reference push, per-table failure isolation, pull dirty-guard"
```

---

### Task 6: Race-proof mark-synced in the six existing dirty-tracked repos

Same race as Task 4 fixed for reference tables, now for the repos that already dirty-track: an edit landing between `getDirty*` and `mark*Synced` currently gets stamped `synced` and never pushes. Apply the dirty-read-cutoff guard everywhere.

**Files:**
- Modify: `lib/data/repositories/performance_sync_repository.dart`
- Modify: `lib/data/repositories/audit_session_repository.dart`
- Modify: `lib/data/repositories/panel_sample_repository.dart`
- Modify: `lib/data/repositories/govee_capture_repository.dart`
- Modify: `lib/data/repositories/dashboard_action_repository.dart`
- Modify: `lib/data/repositories/lab_analysis_repository.dart`
- Test: `test/features/audits/sync_tracking_repository_test.dart` (extend)

**Interfaces:**
- Consumes: nothing new. No public signature changes — the cutoff is recorded internally when the dirty read happens.
- Produces: `mark*Synced` on all six repos only clears rows whose `dirtyAt` is `NULL` or `<=` the cutoff recorded at the last dirty read (per table where the repo serves multiple tables).

Timestamp format warning (critical for the string comparison to work): each repo must generate its cutoff with the SAME expression it uses to stamp `dirtyAt`:
- `audit_session_repository`, `panel_sample_repository`, `govee_capture_repository`, `lab_analysis_repository`: `DateTime.now().toIso8601String()` (local time, no suffix).
- `performance_sync_repository`, `dashboard_action_repository`: `DateTime.now().toUtc().toIso8601String()` (Z suffix).
Never mix — a local-format cutoff compared against a Z-suffixed `dirtyAt` string is meaningless.

- [ ] **Step 1: Verify every repo's write path stamps `dirtyAt`**

Run: `grep -n "'dirtyAt'" lib/data/repositories/dashboard_action_repository.dart lib/data/repositories/lab_analysis_repository.dart lib/data/models/dashboard_action_model.dart lib/data/models/lab_analysis_models.dart 2>/dev/null`

Audit/panel/govee/performance verified already (they stamp `dirtyAt` on every dirty write). For dashboard and lab: if their dirty writes set `syncStatus: 'pending'` without a `dirtyAt` stamp (whether in repo code or model `toMap`), add `'dirtyAt': <repo's now-format>` at those write sites in this step. Rows left with `dirtyAt = NULL` pass the `dirtyAt IS NULL` arm of the guard and keep today's (racy) behavior — no regression, but no protection either, hence the stamps.

- [ ] **Step 2: Write the failing race tests**

Extend `test/features/audits/sync_tracking_repository_test.dart` (harness already builds `audit_sessions`, panel tables, and govee tables with dirty columns):

```dart
  group('mark-synced race protection', () {
    test('a session edited mid-push stays pending after markSessionsSynced',
        () async {
      await sessionRepo.insertSession(_session('s1'));
      await sessionRepo.getDirtySessionRows();           // capture cutoff
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await sessionRepo.updateSession(_session('s1'));   // mid-push edit
      await sessionRepo.markSessionsSynced(['s1']);
      final row = await sessionRow('s1');
      expect(row['syncStatus'], 'pending');
      expect(row['dirtyAt'], isNotNull);
    });

    test('an unedited session is cleared by markSessionsSynced', () async {
      await sessionRepo.insertSession(_session('s1'));
      await sessionRepo.getDirtySessionRows();
      await sessionRepo.markSessionsSynced(['s1']);
      final row = await sessionRow('s1');
      expect(row['syncStatus'], 'synced');
    });
  });
```

(Adapt `_session`/`updateSession` names to the helpers already in that file.) Add the same pair for the panel repo and the govee repo using their existing helpers. For performance/dashboard/lab repos, add the same pair in this file or a sibling test file if their tables aren't in this harness — follow whichever file already tests those repos (`grep -rln "PerformanceSyncRepository\|DashboardActionRepository\|LabAnalysisRepository" test`).

- [ ] **Step 3: Run tests to verify the race tests fail**

Run: `flutter test test/features/audits/sync_tracking_repository_test.dart`
Expected: the "stays pending" tests FAIL (row gets stamped synced).

- [ ] **Step 4: Implement the guard, repo by repo**

Pattern (single-table repo, e.g. `govee_capture_repository.dart`):

```dart
  /// dirtyAt cutoff captured when the dirty rows were last read; see
  /// markCapturesSynced.
  String? _dirtyReadCutoff;
```

In `getDirtyCaptureRows()`, first line after obtaining the db:

```dart
    _dirtyReadCutoff = DateTime.now().toIso8601String();
```

In `markCapturesSynced`, extend the update's WHERE clause:

```dart
    final cutoff = _dirtyReadCutoff ?? DateTime.now().toIso8601String();
    await db.update(
      'govee_daily_captures',
      {
        'syncStatus': 'synced',
        'lastSyncedAt': DateTime.now().toIso8601String(),
        'dirtyAt': null,
        'syncError': null,
      },
      where:
          'id IN ($placeholders) AND (dirtyAt IS NULL OR dirtyAt <= ?)',
      whereArgs: [...idList, cutoff],
    );
```

Apply identically to:
- `audit_session_repository.markSessionsSynced` (cutoff recorded in `getDirtySessionRows`; local-ISO format),
- `dashboard_action_repository.markSynced` (cutoff in `getDirtyRows`; **UTC** format `DateTime.now().toUtc().toIso8601String()`).

Multi-table repos record the cutoff per table:

```dart
  final Map<String, String> _dirtyReadCutoffByTable = {};
```

- `panel_sample_repository`: set `_dirtyReadCutoffByTable[tableName] = DateTime.now().toIso8601String();` in `getDirtyRows(tableName)`; read it in `markRowsSynced(tableName, ids)` (local-ISO).
- `lab_analysis_repository`: same keyed pattern in `getDirtyRows(table)` / `markRowsSynced(table, ids)` (local-ISO).
- `performance_sync_repository`: same keyed pattern in `getDirtyRows(table)` / `markRowsSynced(table, ids)` (**UTC** format).

`mark*Failed` methods stay unconditional — a failed batch should always re-queue.

- [ ] **Step 5: Run the affected suites**

Run: `flutter test test/features/audits/ test/services/supabase/ test/data/`
Expected: all pass (sync-service tests mock these repos, so only repo-level tests exercise the guard).

- [ ] **Step 6: Full suite + analyze + commit**

Run: `flutter analyze && flutter test`
Expected: clean, all green. STOP and investigate any failure before committing.

```bash
git add -A && git commit -m "fix(sync): mark-synced guards against edits landing mid-push"
```

---

## Non-Goals (deliberately out of scope — separate efforts)

- Incremental pull watermark (`updated_at >= lastSync`) — biggest perf win, separate plan.
- Tombstone pruning / applied-flag (unbounded `applyRemoteDeletes` replay).
- Removing the camelCase/snake_case fallback dance once the cloud schema is pinned.
- `run()` coalescing ignoring `canPush`/`collectIncoming` of the second caller.
- Consolidating the multiple `SupabaseService` instances per sync run.
- Wall-clock LWW conflict strategy (would need server timestamps / vector clocks).

## Self-Review Notes

- Spec coverage: review findings #1 (Task 1), #2 (Task 2), #3 (Tasks 3–5), #4 (Task 5 per-table isolation), #5 (Tasks 4 & 6), plus the "pushed count lies" medium folded into Task 5. Mediums intentionally in Non-Goals.
- Type consistency: `getDirtyRows()` → `List<Map<String, dynamic>>`, `markRowsSynced(List<String>)`, `markRowsFailed(List<String>, Object)`, `getRowSyncStatus(String) → Future<String?>` used identically in Tasks 4 and 5. `_pushDirtyReferenceRows` consumes exactly these.
- Ordering hazard: Task 5 depends on Task 4 which depends on Task 3. Tasks 1, 2, 6 are independent and can run in any order.
