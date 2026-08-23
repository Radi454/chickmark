# Agent BMK Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the hatchery agent answer benchmark questions from the real BMK tables — breed standards, egg-breakout standards, and per-hatchery operational standards — instead of model memory.

**Architecture:** Three new read-only agent tools plus one comparison tool, added to the shared tool catalog so the Telegram door and the in-app door both get them. `bmk_breeds` and `bmk_egg_breakout` already live in the cloud and are read directly. `bmk_operational_standards` is local-SQLite-only today, so it first gains a cloud table, RLS, and a two-way sync path.

**Tech Stack:** Supabase Postgres + RLS, Deno Edge Functions (TypeScript, `@std/assert`), Flutter/Dart + sqflite.

**Spec:** `docs/superpowers/specs/2026-08-14-agent-bmk-access-design.md`

## Global Constraints

- Deno formatting for edge-function code: **no semicolons, single quotes** (`deno.json` `fmt` block). Match the surrounding files exactly.
- Cloud column names are `snake_case`; local SQLite column names are `camelCase`. Conversion happens in `BmkRepository._normalizeRow` on pull and is a no-op on push (PostgREST accepts the local camelCase keys only where the cloud column matches — for this table the cloud columns are snake_case, so push must convert).
- Device-local sync columns (`syncStatus`, `dirtyAt`, `lastSyncedAt`, `syncError`) are never sent to the cloud. `stripSyncMeta` removes them.
- No agent tool may write BMK data. Every tool added here is read-only.
- Benchmark misses return a structured miss (`breed_not_found` / `week_out_of_range`) with coverage information. **Never** substitute a nearest week or interpolate.
- Every task that changes behaviour updates `docs/LIVING_SPEC.md` and adds a dated `docs/CHANGELOG.md` entry (`- 2026-08-14:`) in the same commit, per `CLAUDE.md`.
- Breed vocabulary is read from the `bmk_breeds` table at runtime, never hardcoded. Current contents: `Ross308, Arbo, Avian, Cobb500, Hubbard, IR`; weeks 24–65 (Cobb500 from 24, the rest from 25).
- Dart gate after every Dart task: `flutter analyze` clean, then `flutter test`.
- Deno gate after every edge-function task: `cd supabase/functions/telegram-hatchery-agent && deno test --allow-env --allow-net .`

---

## File Structure

**Create:**
- `supabase/migrations/20260814130000_bmk_operational_standards.sql` — cloud table, indexes, RLS, grants.
- `supabase/functions/telegram-hatchery-agent/bmk_lookup.ts` — pure breed/age resolution. No I/O.
- `supabase/functions/telegram-hatchery-agent/bmk_lookup_test.ts`
- `supabase/functions/telegram-hatchery-agent/bmk_tools.ts` — `AgentBmkStore`, Supabase store, tool handlers.
- `supabase/functions/telegram-hatchery-agent/bmk_tools_test.ts`
- `test/security/bmk_operational_standards_security_test.dart` — asserts the migration's RLS shape.
- `test/data/repositories/bmk_operational_sync_test.dart` — repository dirty-marking + remote upsert.
- `test/services/supabase/bmk_operational_push_test.dart` — startup-sync push/pull wiring.

**Modify:**
- `lib/data/repositories/bmk_repository.dart` — dirty-marking write, dirty-row API, remote upsert.
- `lib/services/supabase/startup_sync_service.dart` — push after hatcheries; pull wiring.
- `lib/services/supabase/supabase_service.dart` — `SupabasePullSummary` field, `pullTable` call, callback parameter.
- `supabase/functions/telegram-hatchery-agent/agent_protocol.ts` — four new `AgentToolName` members.
- `supabase/functions/telegram-hatchery-agent/agent_tools.ts` — four new tool definitions.
- `supabase/functions/telegram-hatchery-agent/index.ts` — register handlers in `createUnifiedAgentToolHandlers`.
- `supabase/functions/telegram-hatchery-agent/agent_audit_tools.ts` — auto-attached `benchmark` block.
- `supabase/functions/telegram-hatchery-agent/agent_prompt.ts` — benchmark-sourcing rules.

**Task order rationale:** Tasks 1–4 put operational standards in the cloud (nothing agent-facing works for that dataset until they land). Tasks 5–7 add the lookup tools, which only need cloud data that already exists. Task 8 depends on 5–7. Task 9 depends on 5–6. Task 10 is prompt + docs.

---

### Task 1: Cloud table, indexes, and RLS for `bmk_operational_standards`

**Files:**
- Create: `supabase/migrations/20260814130000_bmk_operational_standards.sql`
- Test: `test/security/bmk_operational_standards_security_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: cloud table `public.bmk_operational_standards` with columns `id, hatchery_id, station_key, sector_key, metric_key, metric_label, unit, min_value, max_value, target_value, source, source_url, source_photo_path, source_photo_remote_path, notes, sort_order, updated_at`.

- [ ] **Step 1: Write the failing test**

Create `test/security/bmk_operational_standards_security_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;

  setUpAll(() {
    migration = File(
      'supabase/migrations/20260814130000_bmk_operational_standards.sql',
    ).readAsStringSync();
  });

  test('creates the table with every mirrored column', () {
    expect(
      migration,
      contains('create table if not exists public.bmk_operational_standards'),
    );
    const columns = [
      'id',
      'hatchery_id',
      'station_key',
      'sector_key',
      'metric_key',
      'metric_label',
      'unit',
      'min_value',
      'max_value',
      'target_value',
      'source',
      'source_url',
      'source_photo_path',
      'source_photo_remote_path',
      'notes',
      'sort_order',
      'updated_at',
    ];
    for (final column in columns) {
      expect(migration, contains(column), reason: column);
    }
  });

  test('enables RLS and revokes anon access', () {
    expect(
      migration,
      contains(
        'alter table public.bmk_operational_standards '
        'enable row level security',
      ),
    );
    expect(migration, contains('revoke all on public.bmk_operational_standards from anon'));
  });

  test('global rows are readable by all authenticated, writable by admin only',
      () {
    expect(migration, contains('bmk_operational_global_read'));
    expect(migration, contains('bmk_operational_global_write'));
    expect(migration, contains('chickmark_private.app_is_admin()'));
    expect(migration, contains('hatchery_id is null'));
  });

  test('hatchery rows are scoped through the owning customer', () {
    expect(migration, contains('bmk_operational_scoped_read'));
    expect(migration, contains('bmk_operational_scoped_write'));
    expect(
      migration,
      contains('chickmark_private.app_can_read_customer(h.customer_id)'),
    );
    expect(
      migration,
      contains('chickmark_private.app_can_write_customer(h.customer_id)'),
    );
    // The write policy must also constrain the inserted row, otherwise a row
    // can be re-pointed into a hatchery the caller cannot write.
    expect(migration, contains('with check'));
  });

  test('indexes the lookup scope', () {
    expect(migration, contains('idx_bmk_operational_scope'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/security/bmk_operational_standards_security_test.dart
```

Expected: FAIL — `PathNotFoundException` on the migration file.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260814130000_bmk_operational_standards.sql`:

```sql
-- bmk_operational_standards: cloud mirror of the local SQLite table.
--
-- A row is either GLOBAL (hatchery_id is null) or OWNED by one hatchery, and
-- therefore one customer. The table has no customer_id column, so ownership is
-- resolved by joining public.hatcheries -- the same shape the photos policies
-- use to reach audit_sessions (0003).
--
-- Global rows behave like the other bmk_* reference tables: read by every
-- authenticated user, written by admins only. Owned rows follow the normal
-- customer scope helpers.
--
-- Device-local sync columns (syncStatus/dirtyAt/lastSyncedAt/syncError) are
-- intentionally absent: they are stripped before push.

create table if not exists public.bmk_operational_standards (
  id                       text primary key,
  hatchery_id              text references public.hatcheries(id) on delete cascade,
  station_key              text not null,
  sector_key               text not null,
  metric_key               text not null,
  metric_label             text not null,
  unit                     text default '',
  min_value                double precision,
  max_value                double precision,
  target_value             double precision,
  source                   text,
  source_url               text,
  source_photo_path        text,
  source_photo_remote_path text,
  notes                    text,
  sort_order               integer not null default 0,
  updated_at               text
);

create index if not exists idx_bmk_operational_scope
  on public.bmk_operational_standards (hatchery_id, station_key, sector_key, metric_key);

alter table public.bmk_operational_standards enable row level security;

revoke all on public.bmk_operational_standards from anon;
grant select, insert, update, delete on public.bmk_operational_standards to authenticated;

drop policy if exists bmk_operational_global_read   on public.bmk_operational_standards;
drop policy if exists bmk_operational_global_write  on public.bmk_operational_standards;
drop policy if exists bmk_operational_scoped_read   on public.bmk_operational_standards;
drop policy if exists bmk_operational_scoped_write  on public.bmk_operational_standards;

create policy bmk_operational_global_read
  on public.bmk_operational_standards for select to authenticated
  using (hatchery_id is null);

create policy bmk_operational_global_write
  on public.bmk_operational_standards for all to authenticated
  using (hatchery_id is null and chickmark_private.app_is_admin())
  with check (hatchery_id is null and chickmark_private.app_is_admin());

create policy bmk_operational_scoped_read
  on public.bmk_operational_standards for select to authenticated
  using (
    exists (
      select 1 from public.hatcheries h
      where h.id = hatchery_id
        and chickmark_private.app_can_read_customer(h.customer_id)
    )
  );

create policy bmk_operational_scoped_write
  on public.bmk_operational_standards for all to authenticated
  using (
    exists (
      select 1 from public.hatcheries h
      where h.id = hatchery_id
        and chickmark_private.app_can_write_customer(h.customer_id)
    )
  )
  with check (
    exists (
      select 1 from public.hatcheries h
      where h.id = hatchery_id
        and chickmark_private.app_can_write_customer(h.customer_id)
    )
  );
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/security/bmk_operational_standards_security_test.dart
```

Expected: PASS (5 tests).

- [ ] **Step 5: Apply the migration to the remote project**

Use the Supabase MCP `apply_migration` tool with name `bmk_operational_standards` and the SQL above, then confirm:

```sql
select count(*) from public.bmk_operational_standards;
```

Expected: `0` rows, no error.

- [ ] **Step 6: Update docs and commit**

Add to `docs/LIVING_SPEC.md` (cloud schema section): `bmk_operational_standards` mirrors the local table; global rows are reference data, hatchery rows are customer-scoped.

Add to the top of `docs/CHANGELOG.md`:

```markdown
- 2026-08-14: Added the cloud `bmk_operational_standards` table with split RLS — global rows read-all/write-admin, hatchery rows scoped through the owning customer.
```

```bash
git add supabase/migrations/20260814130000_bmk_operational_standards.sql test/security/bmk_operational_standards_security_test.dart docs/LIVING_SPEC.md docs/CHANGELOG.md
git commit -m "feat(sync): add cloud bmk_operational_standards table with scoped RLS"
```

---

### Task 2: Local repository — dirty marking and remote upsert

**Files:**
- Modify: `lib/data/repositories/bmk_repository.dart`
- Test: `test/data/repositories/bmk_operational_sync_test.dart`

**Interfaces:**
- Consumes: cloud table from Task 1.
- Produces, on `BmkRepository`:
  - `Future<List<Map<String, dynamic>>> getDirtyOperationalRows()`
  - `Future<void> markOperationalRowsSynced(List<String> ids)`
  - `Future<void> markOperationalRowsFailed(List<String> ids, Object error)`
  - `Future<String?> getOperationalRowSyncStatus(String id)`
  - `Future<void> upsertOperationalStandardRow(Map<String, dynamic> row)` — raw snake_case cloud row in, local row out.
  - `upsertOperationalStandard(BmkOperationalStandardModel)` now marks the row `pending` / `dirtyAt = now`.

- [ ] **Step 1: Write the failing test**

Create `test/data/repositories/bmk_operational_sync_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/bmk_operational_standard_model.dart';
import 'package:hatchaudit/data/repositories/bmk_repository.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  tearDown(resetAppDatabase);

  BmkOperationalStandardModel standard(String id, {String? hatcheryId}) {
    return BmkOperationalStandardModel(
      id: id,
      hatcheryId: hatcheryId,
      stationKey: 'setter',
      sectorKey: 'incubation',
      metricKey: 'setter_temp',
      metricLabel: 'Setter temperature',
      unit: 'F',
      minValue: 99.0,
      maxValue: 100.5,
      targetValue: 99.8,
      sortOrder: 1,
    );
  }

  test('local edits are marked dirty and returned by getDirtyOperationalRows',
      () async {
    final repo = BmkRepository();
    await repo.upsertOperationalStandard(standard('std-1'));

    final dirty = await repo.getDirtyOperationalRows();

    expect(dirty, hasLength(1));
    expect(dirty.single['id'], 'std-1');
    expect(dirty.single['syncStatus'], 'pending');
    expect(dirty.single['dirtyAt'], isNotNull);
  });

  test('markOperationalRowsSynced clears the dirty flag', () async {
    final repo = BmkRepository();
    await repo.upsertOperationalStandard(standard('std-1'));
    await repo.getDirtyOperationalRows();

    await repo.markOperationalRowsSynced(['std-1']);

    expect(await repo.getDirtyOperationalRows(), isEmpty);
    expect(await repo.getOperationalRowSyncStatus('std-1'), 'synced');
  });

  test('markOperationalRowsFailed records the error and keeps the row dirty',
      () async {
    final repo = BmkRepository();
    await repo.upsertOperationalStandard(standard('std-1'));
    await repo.getDirtyOperationalRows();

    await repo.markOperationalRowsFailed(['std-1'], StateError('boom'));

    expect(await repo.getOperationalRowSyncStatus('std-1'), 'failed');
    expect(await repo.getDirtyOperationalRows(), hasLength(1));
  });

  test('upsertOperationalStandardRow converts a snake_case cloud row',
      () async {
    final repo = BmkRepository();

    await repo.upsertOperationalStandardRow({
      'id': 'std-cloud',
      'hatchery_id': null,
      'station_key': 'hatcher',
      'sector_key': 'incubation',
      'metric_key': 'hatcher_humidity',
      'metric_label': 'Hatcher humidity',
      'unit': '%',
      'min_value': 50.0,
      'max_value': 60.0,
      'target_value': 55.0,
      'sort_order': 2,
      'updated_at': '2026-08-14T00:00:00.000Z',
    });

    final rows = await repo.getOperationalStandards();
    expect(rows, hasLength(1));
    expect(rows.single.metricKey, 'hatcher_humidity');
    expect(rows.single.targetValue, 55.0);
  });

  test('a pulled row is not dirty', () async {
    final repo = BmkRepository();

    await repo.upsertOperationalStandardRow({
      'id': 'std-cloud',
      'station_key': 'hatcher',
      'sector_key': 'incubation',
      'metric_key': 'hatcher_humidity',
      'metric_label': 'Hatcher humidity',
      'sort_order': 0,
    });

    expect(await repo.getDirtyOperationalRows(), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/data/repositories/bmk_operational_sync_test.dart
```

Expected: FAIL — `getDirtyOperationalRows` is not defined on `BmkRepository`.

- [ ] **Step 3: Implement in `lib/data/repositories/bmk_repository.dart`**

Add near the top of the class body:

```dart
  static const _operationalTable = 'bmk_operational_standards';

  String _nowStamp() => DateTime.now().toIso8601String();

  /// dirtyAt value captured at the last getDirtyOperationalRows() call.
  /// markOperationalRowsSynced only clears rows whose dirtyAt is at or before
  /// this cutoff, so an edit landing while a push is in flight stays pending.
  String? _operationalDirtyReadCutoff;
```

Replace the body of `upsertOperationalStandard` so the write marks the row dirty:

```dart
  Future<void> upsertOperationalStandard(
    BmkOperationalStandardModel row,
  ) async {
    final db = await dbHelper.db;
    await db.insert(
      _operationalTable,
      {
        ...row.copyWith(updatedAt: _nowStamp()).toMap(),
        'syncStatus': 'pending',
        'dirtyAt': _nowStamp(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
```

Add the sync API:

```dart
  Future<List<Map<String, dynamic>>> getDirtyOperationalRows() async {
    final db = await dbHelper.db;
    _operationalDirtyReadCutoff = _nowStamp();
    final rows = await db.query(
      _operationalTable,
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'dirtyAt ASC, id ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> markOperationalRowsSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await dbHelper.db;
    final cutoff = _operationalDirtyReadCutoff ?? _nowStamp();
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      _operationalTable,
      {
        'syncStatus': 'synced',
        'dirtyAt': null,
        'lastSyncedAt': _nowStamp(),
        'syncError': null,
      },
      where: 'id IN ($placeholders) AND (dirtyAt IS NULL OR dirtyAt <= ?)',
      whereArgs: [...ids, cutoff],
    );
  }

  Future<void> markOperationalRowsFailed(
    List<String> ids,
    Object error,
  ) async {
    if (ids.isEmpty) return;
    final db = await dbHelper.db;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      _operationalTable,
      {'syncStatus': 'failed', 'syncError': error.toString()},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<String?> getOperationalRowSyncStatus(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      _operationalTable,
      columns: ['syncStatus'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['syncStatus'] as String?;
  }

  /// Apply one snake_case cloud row. Pulled rows are clean by definition, so
  /// the sync columns are reset rather than left at whatever the pull carried.
  Future<void> upsertOperationalStandardRow(Map<String, dynamic> row) async {
    final db = await dbHelper.db;
    final columns = await _tableColumns(db, _operationalTable);
    final normalized = _filterColumns(_normalizeRow(row), columns);
    normalized['syncStatus'] = 'synced';
    normalized['dirtyAt'] = null;
    normalized['lastSyncedAt'] = _nowStamp();
    normalized['syncError'] = null;
    await db.insert(
      _operationalTable,
      normalized,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/data/repositories/bmk_operational_sync_test.dart
```

Expected: PASS (5 tests).

- [ ] **Step 5: Run the gate**

```bash
flutter analyze && flutter test
```

Expected: analyze clean, whole suite green. If the BMK screen's provider tests fail because standards are now dirty on write, that is the intended new behaviour — update those expectations, do not revert the dirty marking.

- [ ] **Step 6: Update docs and commit**

`docs/CHANGELOG.md`:

```markdown
- 2026-08-14: BMK operational standards are now dirty-tracked on edit and can be applied from a cloud row.
```

```bash
git add lib/data/repositories/bmk_repository.dart test/data/repositories/bmk_operational_sync_test.dart docs/CHANGELOG.md docs/LIVING_SPEC.md
git commit -m "feat(sync): dirty-track bmk operational standards"
```

---

### Task 3: Push dirty operational standards on sync

**Files:**
- Modify: `lib/services/supabase/startup_sync_service.dart` (inside `_pushLocalData`, after the hatcheries push at ~line 237)
- Test: `test/services/supabase/bmk_operational_push_test.dart`

**Interfaces:**
- Consumes: `BmkRepository.getDirtyOperationalRows / markOperationalRowsSynced / markOperationalRowsFailed` from Task 2.
- Produces: dirty operational rows reach `public.bmk_operational_standards` on every sync.

The push must convert camelCase local keys to the snake_case cloud columns. Add a private helper in the service rather than mutating the repository, so the repository stays cloud-agnostic.

- [ ] **Step 1: Write the failing test**

Create `test/services/supabase/bmk_operational_push_test.dart`. Model it on the fake `SupabaseService` used by the existing startup-sync tests — read `test/services/supabase/startup_sync_service_test.dart` first and reuse its fake/harness rather than inventing a second one.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/bmk_operational_standard_model.dart';
import 'package:hatchaudit/data/repositories/bmk_repository.dart';

import '../../support/test_database.dart';
// Reuse the fake service + harness already defined for startup sync tests.
import 'startup_sync_service_test.dart' as harness;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  tearDown(resetAppDatabase);

  test('pushes dirty operational standards with snake_case columns', () async {
    final repo = BmkRepository();
    await repo.upsertOperationalStandard(
      BmkOperationalStandardModel(
        id: 'std-1',
        hatcheryId: 'hatchery-a',
        stationKey: 'setter',
        sectorKey: 'incubation',
        metricKey: 'setter_temp',
        metricLabel: 'Setter temperature',
        unit: 'F',
        minValue: 99.0,
        maxValue: 100.5,
        targetValue: 99.8,
        sortOrder: 1,
      ),
    );

    final service = harness.buildService();
    await service.run();

    final pushed = harness.fakeSupabase.upserts['bmk_operational_standards'];
    expect(pushed, hasLength(1));
    expect(pushed!.single['station_key'], 'setter');
    expect(pushed.single['hatchery_id'], 'hatchery-a');
    expect(pushed.single['target_value'], 99.8);
    // Device-local sync columns never leave the device.
    expect(pushed.single.containsKey('syncStatus'), isFalse);
    expect(pushed.single.containsKey('dirtyAt'), isFalse);

    expect(await repo.getOperationalRowSyncStatus('std-1'), 'synced');
  });

  test('a failed push marks rows failed without aborting the sync', () async {
    final repo = BmkRepository();
    await repo.upsertOperationalStandard(
      BmkOperationalStandardModel(
        id: 'std-1',
        stationKey: 'setter',
        sectorKey: 'incubation',
        metricKey: 'setter_temp',
        metricLabel: 'Setter temperature',
        sortOrder: 0,
      ),
    );

    final service = harness.buildService(
      failUpsertsFor: {'bmk_operational_standards'},
    );
    await service.run();

    expect(await repo.getOperationalRowSyncStatus('std-1'), 'failed');
  });
}
```

If `startup_sync_service_test.dart` does not export a reusable `buildService` / `fakeSupabase`, extract them into `test/services/supabase/startup_sync_harness.dart` first and import that from both files. Do not duplicate the fake.

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/services/supabase/bmk_operational_push_test.dart
```

Expected: FAIL — no `bmk_operational_standards` entry in the recorded upserts.

- [ ] **Step 3: Implement the push**

In `lib/services/supabase/startup_sync_service.dart`, immediately after the hatcheries push block inside `_pushLocalData`:

```dart
    progress(0.24, 'Uploading benchmark standards');
    pushed += await _pushDirtyReferenceRows(
      'bmk_operational_standards',
      getDirtyRows: () async {
        final rows = await _bmkRepository.getDirtyOperationalRows();
        return rows.map(_operationalStandardToRemote).toList(growable: false);
      },
      markSynced: _bmkRepository.markOperationalRowsSynced,
      markFailed: _bmkRepository.markOperationalRowsFailed,
    );
```

It sits after hatcheries so the `hatchery_id` FK resolves. Global rows (null `hatchery_id`) have no FK dependency and ride along in the same batch.

Add the column mapper as a private method on the service:

```dart
  /// The local table is camelCase, the cloud table is snake_case. Only the
  /// mirrored columns are sent; the sync columns are dropped by stripSyncMeta
  /// in _pushDirtyReferenceRows.
  static const _operationalRemoteColumns = <String, String>{
    'id': 'id',
    'hatcheryId': 'hatchery_id',
    'stationKey': 'station_key',
    'sectorKey': 'sector_key',
    'metricKey': 'metric_key',
    'metricLabel': 'metric_label',
    'unit': 'unit',
    'minValue': 'min_value',
    'maxValue': 'max_value',
    'targetValue': 'target_value',
    'source': 'source',
    'sourceUrl': 'source_url',
    'sourcePhotoPath': 'source_photo_path',
    'sourcePhotoRemotePath': 'source_photo_remote_path',
    'notes': 'notes',
    'sortOrder': 'sort_order',
    'updatedAt': 'updated_at',
  };

  Map<String, dynamic> _operationalStandardToRemote(
    Map<String, dynamic> row,
  ) {
    final remote = <String, dynamic>{};
    for (final entry in _operationalRemoteColumns.entries) {
      if (row.containsKey(entry.key)) remote[entry.value] = row[entry.key];
    }
    return remote;
  }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/services/supabase/bmk_operational_push_test.dart
```

Expected: PASS (2 tests).

- [ ] **Step 5: Run the gate**

```bash
flutter analyze && flutter test
```

- [ ] **Step 6: Update docs and commit**

`docs/LIVING_SPEC.md`: add `bmk_operational_standards` to the documented push order (after hatcheries). `docs/CHANGELOG.md`:

```markdown
- 2026-08-14: Sync now pushes dirty BMK operational standards to the cloud, after hatcheries so the hatchery FK resolves.
```

```bash
git add lib/services/supabase/startup_sync_service.dart test/services/supabase/bmk_operational_push_test.dart docs/LIVING_SPEC.md docs/CHANGELOG.md
git commit -m "feat(sync): push dirty bmk operational standards"
```

---

### Task 4: Pull operational standards from the cloud

**Files:**
- Modify: `lib/services/supabase/supabase_service.dart` (`SupabasePullSummary` ~line 25, `pullTable` call site ~line 846)
- Modify: `lib/services/supabase/startup_sync_service.dart` (callback wiring ~line 578)
- Test: `test/services/supabase/bmk_operational_push_test.dart` (extend)

**Interfaces:**
- Consumes: `BmkRepository.upsertOperationalStandardRow` and `getOperationalRowSyncStatus` from Task 2.
- Produces: `SupabasePullSummary.bmkOperationalStandards` (int), and a new optional `upsertBmkOperationalStandard` callback parameter on the pull entry point.

- [ ] **Step 1: Write the failing test**

Append to `test/services/supabase/bmk_operational_push_test.dart`:

```dart
  test('pulls cloud operational standards into local', () async {
    final service = harness.buildService(
      remoteRows: {
        'bmk_operational_standards': [
          {
            'id': 'std-cloud',
            'hatchery_id': null,
            'station_key': 'hatcher',
            'sector_key': 'incubation',
            'metric_key': 'hatcher_humidity',
            'metric_label': 'Hatcher humidity',
            'unit': '%',
            'min_value': 50.0,
            'max_value': 60.0,
            'target_value': 55.0,
            'sort_order': 2,
            'updated_at': '2026-08-14T00:00:00.000Z',
          },
        ],
      },
    );
    await service.run();

    final rows = await BmkRepository().getOperationalStandards();
    expect(rows.map((row) => row.metricKey), contains('hatcher_humidity'));
  });

  test('a locally dirty row is not overwritten by the pull', () async {
    final repo = BmkRepository();
    await repo.upsertOperationalStandard(
      BmkOperationalStandardModel(
        id: 'std-cloud',
        stationKey: 'hatcher',
        sectorKey: 'incubation',
        metricKey: 'hatcher_humidity',
        metricLabel: 'Hatcher humidity',
        targetValue: 57.0,
        sortOrder: 0,
      ),
    );

    final service = harness.buildService(
      canPush: true,
      failUpsertsFor: {'bmk_operational_standards'},
      remoteRows: {
        'bmk_operational_standards': [
          {
            'id': 'std-cloud',
            'station_key': 'hatcher',
            'sector_key': 'incubation',
            'metric_key': 'hatcher_humidity',
            'metric_label': 'Hatcher humidity',
            'target_value': 55.0,
            'sort_order': 0,
          },
        ],
      },
    );
    await service.run();

    final rows = await repo.getOperationalStandards();
    // The local edit survived the pull because the push had not succeeded.
    expect(rows.single.targetValue, 57.0);
  });
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/services/supabase/bmk_operational_push_test.dart
```

Expected: FAIL — the pulled row never reaches local storage.

- [ ] **Step 3: Wire the pull**

In `lib/services/supabase/supabase_service.dart`, add `bmkOperationalStandards` to `SupabasePullSummary` (field, constructor default `0`, `copyWith`, and the `total` getter sum) exactly as `bmkEggBreakout` is declared.

Add the callback parameter next to `upsertBmkEggBreakout` on the pull entry point:

```dart
    Future<void> Function(Map<String, dynamic>)? upsertBmkOperationalStandard,
```

And the call site, immediately after the `bmk_egg_breakout` block:

```dart
      if (upsertBmkOperationalStandard != null) {
        summary = summary.copyWith(
          bmkOperationalStandards: await pullTable(
            'bmk_operational_standards',
            upsertBmkOperationalStandard,
          ),
        );
      }
```

In `lib/services/supabase/startup_sync_service.dart`, next to the existing bmk callbacks (~line 578), route through the shared dirty guard so a locally-edited row that has not pushed yet is preserved:

```dart
      upsertBmkOperationalStandard: (row) => _upsertReferenceRow(
        'bmk_operational_standards',
        row,
        canPush: canPush,
        getSyncStatus: _bmkRepository.getOperationalRowSyncStatus,
        upsert: (value) =>
            _bmkRepository.upsertOperationalStandardRow(value),
      ),
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/services/supabase/bmk_operational_push_test.dart
```

Expected: PASS (4 tests).

- [ ] **Step 5: Run the gate**

```bash
flutter analyze && flutter test
```

- [ ] **Step 6: Update docs and commit**

`docs/CHANGELOG.md`:

```markdown
- 2026-08-14: Sync now pulls BMK operational standards from the cloud, behind the same dirty-row guard as the other reference tables.
```

```bash
git add lib/services/supabase/supabase_service.dart lib/services/supabase/startup_sync_service.dart test/services/supabase/bmk_operational_push_test.dart docs/LIVING_SPEC.md docs/CHANGELOG.md
git commit -m "feat(sync): pull bmk operational standards"
```

---

### Task 5: `bmk_lookup.ts` — breed and age resolution

**Files:**
- Create: `supabase/functions/telegram-hatchery-agent/bmk_lookup.ts`
- Test: `supabase/functions/telegram-hatchery-agent/bmk_lookup_test.ts`

**Interfaces:**
- Consumes: nothing (pure module, no I/O).
- Produces:
  - `normalizeBreedKey(value: string): string`
  - `resolveBreed(requested: string, vocabulary: readonly string[]): string | null`
  - `type BreedCoverage = { breed: string; minWeek: number; maxWeek: number }`
  - `coverageFor(breed: string, rows: readonly { breed: string; ageWeek: number }[]): BreedCoverage | null`

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/telegram-hatchery-agent/bmk_lookup_test.ts`:

```ts
import { assertEquals } from '@std/assert'

import {
  coverageFor,
  normalizeBreedKey,
  resolveBreed,
} from './bmk_lookup.ts'

const vocabulary = ['Ross308', 'Arbo', 'Avian', 'Cobb500', 'Hubbard', 'IR']

Deno.test('normalizeBreedKey strips case, spaces, hyphens and dots', () => {
  assertEquals(normalizeBreedKey('Ross 308'), 'ross308')
  assertEquals(normalizeBreedKey('ROSS-308'), 'ross308')
  assertEquals(normalizeBreedKey('  cobb.500 '), 'cobb500')
})

Deno.test('resolveBreed matches exactly after normalization', () => {
  assertEquals(resolveBreed('Ross308', vocabulary), 'Ross308')
  assertEquals(resolveBreed('ross 308', vocabulary), 'Ross308')
  assertEquals(resolveBreed('ir', vocabulary), 'IR')
})

Deno.test('resolveBreed accepts a unique prefix', () => {
  assertEquals(resolveBreed('ross', vocabulary), 'Ross308')
  assertEquals(resolveBreed('cobb', vocabulary), 'Cobb500')
})

Deno.test('resolveBreed refuses an ambiguous prefix', () => {
  assertEquals(resolveBreed('a', vocabulary), null)
})

Deno.test('resolveBreed refuses an unknown breed', () => {
  assertEquals(resolveBreed('leghorn', vocabulary), null)
  assertEquals(resolveBreed('', vocabulary), null)
})

Deno.test('coverageFor reports the per-breed week range', () => {
  const rows = [
    { breed: 'Ross308', ageWeek: 25 },
    { breed: 'Ross308', ageWeek: 65 },
    { breed: 'Cobb500', ageWeek: 24 },
    { breed: 'Cobb500', ageWeek: 65 },
  ]
  assertEquals(coverageFor('Ross308', rows), {
    breed: 'Ross308',
    minWeek: 25,
    maxWeek: 65,
  })
  assertEquals(coverageFor('Cobb500', rows), {
    breed: 'Cobb500',
    minWeek: 24,
    maxWeek: 65,
  })
  assertEquals(coverageFor('Hubbard', rows), null)
})
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd supabase/functions/telegram-hatchery-agent && deno test --allow-env --allow-net bmk_lookup_test.ts
```

Expected: FAIL — module not found.

- [ ] **Step 3: Write the module**

Create `supabase/functions/telegram-hatchery-agent/bmk_lookup.ts`:

```ts
// Pure breed/age resolution for the BMK benchmark tools.
//
// The vocabulary is always passed in -- it comes from the bmk_breeds table at
// runtime, never from a hardcoded list, so a new breed row is answerable the
// moment it lands.

export interface BreedCoverage {
  breed: string
  minWeek: number
  maxWeek: number
}

/** Lowercase, alphanumeric only. 'Ross 308', 'ROSS-308' -> 'ross308'. */
export function normalizeBreedKey(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]/g, '')
}

/**
 * Exact normalized match first, then a UNIQUE prefix match. A prefix matching
 * more than one breed resolves to null so the caller can ask instead of
 * guessing.
 */
export function resolveBreed(
  requested: string,
  vocabulary: readonly string[],
): string | null {
  const key = normalizeBreedKey(requested ?? '')
  if (!key) return null

  const exact = vocabulary.find((breed) => normalizeBreedKey(breed) === key)
  if (exact) return exact

  const prefixed = vocabulary.filter((breed) =>
    normalizeBreedKey(breed).startsWith(key)
  )
  return prefixed.length === 1 ? prefixed[0] : null
}

/** Week coverage for one resolved breed. Coverage differs per breed. */
export function coverageFor(
  breed: string,
  rows: readonly { breed: string; ageWeek: number }[],
): BreedCoverage | null {
  const weeks = rows
    .filter((row) => row.breed === breed)
    .map((row) => row.ageWeek)
    .filter((week) => Number.isFinite(week))
  if (weeks.length === 0) return null
  return {
    breed,
    minWeek: Math.min(...weeks),
    maxWeek: Math.max(...weeks),
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd supabase/functions/telegram-hatchery-agent && deno test --allow-env --allow-net bmk_lookup_test.ts
```

Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/telegram-hatchery-agent/bmk_lookup.ts supabase/functions/telegram-hatchery-agent/bmk_lookup_test.ts
git commit -m "feat(agent): add pure BMK breed and age resolution"
```

---

### Task 6: `get_breed_benchmark` and `get_egg_breakout_benchmark`

**Files:**
- Create: `supabase/functions/telegram-hatchery-agent/bmk_tools.ts`
- Create: `supabase/functions/telegram-hatchery-agent/bmk_tools_test.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_protocol.ts` (`AgentToolName` union)
- Modify: `supabase/functions/telegram-hatchery-agent/agent_tools.ts` (`AGENT_TOOL_DEFINITIONS`)
- Modify: `supabase/functions/telegram-hatchery-agent/index.ts` (`createUnifiedAgentToolHandlers`, ~line 1153)

**Interfaces:**
- Consumes: `resolveBreed`, `coverageFor` from Task 5; `AgentToolHandler` from `agent_tools.ts`; `ok(...)` result shape `{ ok: true, code: 'ok', data }`.
- Produces:
```ts
export interface BmkBreedBenchmarkRow {
  breed: string
  ageWeek: number
  hatchabilityPct: number | null
  fertilityPct: number | null
  hofPct: number | null
  productionPct: number | null
  eggWeightG: number | null
  chickWeightG: number | null
}

export interface BmkEggBreakoutBenchmarkRow {
  ageWeek: number
  infertilePct: number | null
  early24hPct: number | null
  early48hPct: number | null
  bloodRingPct: number | null
  blackEyePct: number | null
  earlyDeadPct: number | null
  midDeadPct: number | null
  lateDeadPct: number | null
  externalPipPct: number | null
  crackedPct: number | null
  contamPct: number | null
}

export interface AgentBmkStore {
  listBreedCoverage(): Promise<readonly { breed: string; ageWeek: number }[]>
  findBreedBenchmark(
    breed: string,
    ageWeek: number,
  ): Promise<BmkBreedBenchmarkRow | null>
  listEggBreakoutWeeks(): Promise<readonly number[]>
  findEggBreakoutBenchmark(
    ageWeek: number,
  ): Promise<BmkEggBreakoutBenchmarkRow | null>
}

export function createSupabaseAgentBmkStore(client: AgentBmkClient): AgentBmkStore
export function createAgentBmkToolHandlers(
  store: AgentBmkStore,
): Partial<Record<AgentToolName, AgentToolHandler>>
```
Later tasks add `listOperationalStandards` to `AgentBmkStore` (Task 7) and reuse `findBreedBenchmark` / `findEggBreakoutBenchmark` (Tasks 8 and 9).

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/telegram-hatchery-agent/bmk_tools_test.ts`:

```ts
import { assertEquals } from '@std/assert'

import type { AgentScope } from './agent_protocol.ts'
import {
  type AgentBmkStore,
  createAgentBmkToolHandlers,
} from './bmk_tools.ts'

const scope: AgentScope = {
  staffLinkId: 'staff-a',
  accessRole: 'customer',
  allowedCustomerIds: ['customer-a'],
}

function fixtureStore(): AgentBmkStore {
  return {
    listBreedCoverage: () =>
      Promise.resolve([
        { breed: 'Ross308', ageWeek: 25 },
        { breed: 'Ross308', ageWeek: 35 },
        { breed: 'Ross308', ageWeek: 65 },
        { breed: 'Cobb500', ageWeek: 24 },
        { breed: 'Cobb500', ageWeek: 65 },
      ]),
    findBreedBenchmark: (breed, ageWeek) =>
      Promise.resolve(
        breed === 'Ross308' && ageWeek === 35
          ? {
            breed: 'Ross308',
            ageWeek: 35,
            hatchabilityPct: 90,
            fertilityPct: 95,
            hofPct: 86,
            productionPct: 83,
            eggWeightG: 67,
            chickWeightG: 48,
          }
          : null,
      ),
    listEggBreakoutWeeks: () => Promise.resolve([25, 35, 65]),
    findEggBreakoutBenchmark: (ageWeek) =>
      Promise.resolve(
        ageWeek === 35
          ? {
            ageWeek: 35,
            infertilePct: 4,
            early24hPct: 1,
            early48hPct: 1,
            bloodRingPct: 0.5,
            blackEyePct: 0.5,
            earlyDeadPct: 2,
            midDeadPct: 1,
            lateDeadPct: 2,
            externalPipPct: 0.5,
            crackedPct: 1,
            contamPct: 0.5,
          }
          : null,
      ),
  }
}

function call(
  name: string,
  args: Record<string, unknown>,
) {
  const handlers = createAgentBmkToolHandlers(fixtureStore())
  const handler = handlers[name as keyof typeof handlers]!
  return handler({
    scope,
    conversationId: 'conversation-a',
    activeVisitId: null,
    arguments: args,
  })
}

Deno.test('get_breed_benchmark returns the standard for a resolved breed',
  async () => {
    const result = await call('get_breed_benchmark', {
      breed: 'ross',
      ageWeek: 35,
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.breed, 'Ross308')
    assertEquals(result.data?.ageWeek, 35)
    assertEquals(result.data?.hatchabilityPct, 90)
  })

Deno.test('get_breed_benchmark reports an unknown breed with the vocabulary',
  async () => {
    const result = await call('get_breed_benchmark', {
      breed: 'leghorn',
      ageWeek: 35,
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.status, 'breed_not_found')
    assertEquals(result.data?.availableBreeds, ['Cobb500', 'Ross308'])
  })

Deno.test('get_breed_benchmark reports an out-of-range week with coverage',
  async () => {
    const result = await call('get_breed_benchmark', {
      breed: 'Ross308',
      ageWeek: 70,
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.status, 'week_out_of_range')
    assertEquals(result.data?.breed, 'Ross308')
    assertEquals(result.data?.coveredWeeks, { min: 25, max: 65 })
    // No substituted value.
    assertEquals(result.data?.hatchabilityPct, undefined)
  })

Deno.test('get_breed_benchmark reports coverage per breed', async () => {
  const result = await call('get_breed_benchmark', {
    breed: 'cobb',
    ageWeek: 70,
  })
  assertEquals(result.data?.coveredWeeks, { min: 24, max: 65 })
})

Deno.test('get_egg_breakout_benchmark returns the defect targets', async () => {
  const result = await call('get_egg_breakout_benchmark', { ageWeek: 35 })
  assertEquals(result.ok, true)
  assertEquals(result.data?.ageWeek, 35)
  assertEquals(result.data?.infertilePct, 4)
  assertEquals(result.data?.contamPct, 0.5)
})

Deno.test('get_egg_breakout_benchmark reports an out-of-range week',
  async () => {
    const result = await call('get_egg_breakout_benchmark', { ageWeek: 70 })
    assertEquals(result.data?.status, 'week_out_of_range')
    assertEquals(result.data?.coveredWeeks, { min: 25, max: 65 })
  })
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd supabase/functions/telegram-hatchery-agent && deno test --allow-env --allow-net bmk_tools_test.ts
```

Expected: FAIL — `./bmk_tools.ts` not found.

- [ ] **Step 3: Add the two tool names**

In `agent_protocol.ts`, append to the `AgentToolName` union (after `'get_selected_audit_breakouts'`):

```ts
  | 'get_breed_benchmark'
  | 'get_egg_breakout_benchmark'
```

- [ ] **Step 4: Add the two tool definitions**

In `agent_tools.ts`, add near the other read definitions (before `propose_intake`), and add the shared rule above `AGENT_TOOL_DEFINITIONS`:

```ts
const ageWeekRule: ArgumentRule = {
  type: 'integer',
  minimum: 1,
  maximum: 120,
}
const breedRule: ArgumentRule = {
  type: 'string',
  minLength: 1,
  maxLength: 60,
}
```

```ts
    definition(
      'get_breed_benchmark',
      'Look up the published breed standard (hatchability, fertility, HOF, production, egg weight, chick weight) for one breed at one flock age in weeks. Always use this instead of stating a benchmark from memory.',
      { breed: breedRule, ageWeek: ageWeekRule },
      ['breed', 'ageWeek'],
    ),
    definition(
      'get_egg_breakout_benchmark',
      'Look up the published egg-breakout standard (infertile, early/mid/late dead, blood ring, black eye, external pip, cracked, contaminated) for one flock age in weeks.',
      { ageWeek: ageWeekRule },
      ['ageWeek'],
    ),
```

- [ ] **Step 5: Write `bmk_tools.ts`**

Create `supabase/functions/telegram-hatchery-agent/bmk_tools.ts`:

```ts
// Benchmark (BMK) read tools.
//
// bmk_breeds and bmk_egg_breakout are global reference tables with
// read-all-authenticated policies, so they are read with no customer filter.
// Operational standards are scoped -- see get_operational_standards.

import type {
  AgentToolExecutionInput,
  AgentToolName,
  AgentToolResult,
} from './agent_protocol.ts'
import type { AgentToolHandler } from './agent_tools.ts'
import { coverageFor, resolveBreed } from './bmk_lookup.ts'

export interface BmkBreedBenchmarkRow {
  breed: string
  ageWeek: number
  hatchabilityPct: number | null
  fertilityPct: number | null
  hofPct: number | null
  productionPct: number | null
  eggWeightG: number | null
  chickWeightG: number | null
}

export interface BmkEggBreakoutBenchmarkRow {
  ageWeek: number
  infertilePct: number | null
  early24hPct: number | null
  early48hPct: number | null
  bloodRingPct: number | null
  blackEyePct: number | null
  earlyDeadPct: number | null
  midDeadPct: number | null
  lateDeadPct: number | null
  externalPipPct: number | null
  crackedPct: number | null
  contamPct: number | null
}

export interface AgentBmkStore {
  listBreedCoverage(): Promise<readonly { breed: string; ageWeek: number }[]>
  findBreedBenchmark(
    breed: string,
    ageWeek: number,
  ): Promise<BmkBreedBenchmarkRow | null>
  listEggBreakoutWeeks(): Promise<readonly number[]>
  findEggBreakoutBenchmark(
    ageWeek: number,
  ): Promise<BmkEggBreakoutBenchmarkRow | null>
}

export function createAgentBmkToolHandlers(
  store: AgentBmkStore,
): Partial<Record<AgentToolName, AgentToolHandler>> {
  return {
    get_breed_benchmark: (input) => getBreedBenchmark(store, input),
    get_egg_breakout_benchmark: (input) =>
      getEggBreakoutBenchmark(store, input),
  }
}

/**
 * Resolve a requested breed name and age week against the table's own
 * vocabulary. Returns either the benchmark row or a structured miss -- never a
 * substituted or interpolated value.
 */
export async function resolveBreedBenchmark(
  store: AgentBmkStore,
  requestedBreed: string,
  ageWeek: number,
): Promise<
  | { status: 'ok'; row: BmkBreedBenchmarkRow }
  | { status: 'breed_not_found'; availableBreeds: string[] }
  | {
    status: 'week_out_of_range'
    breed: string
    coveredWeeks: { min: number; max: number }
  }
> {
  const coverage = await store.listBreedCoverage()
  const vocabulary = [...new Set(coverage.map((row) => row.breed))].sort()
  const breed = resolveBreed(requestedBreed, vocabulary)
  if (!breed) {
    return { status: 'breed_not_found', availableBreeds: vocabulary }
  }

  const row = await store.findBreedBenchmark(breed, ageWeek)
  if (row) return { status: 'ok', row }

  const range = coverageFor(breed, coverage)
  return {
    status: 'week_out_of_range',
    breed,
    coveredWeeks: range
      ? { min: range.minWeek, max: range.maxWeek }
      : { min: 0, max: 0 },
  }
}

/** Same contract as resolveBreedBenchmark, for the age-only breakout table. */
export async function resolveEggBreakoutBenchmark(
  store: AgentBmkStore,
  ageWeek: number,
): Promise<
  | { status: 'ok'; row: BmkEggBreakoutBenchmarkRow }
  | {
    status: 'week_out_of_range'
    coveredWeeks: { min: number; max: number }
  }
> {
  const row = await store.findEggBreakoutBenchmark(ageWeek)
  if (row) return { status: 'ok', row }
  const weeks = await store.listEggBreakoutWeeks()
  return {
    status: 'week_out_of_range',
    coveredWeeks: weeks.length === 0
      ? { min: 0, max: 0 }
      : { min: Math.min(...weeks), max: Math.max(...weeks) },
  }
}

async function getBreedBenchmark(
  store: AgentBmkStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const resolved = await resolveBreedBenchmark(
    store,
    input.arguments.breed as string,
    input.arguments.ageWeek as number,
  )
  if (resolved.status === 'ok') return ok({ ...resolved.row })
  const { status, ...rest } = resolved
  return ok({ status, ...rest })
}

async function getEggBreakoutBenchmark(
  store: AgentBmkStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const resolved = await resolveEggBreakoutBenchmark(
    store,
    input.arguments.ageWeek as number,
  )
  if (resolved.status === 'ok') return ok({ ...resolved.row })
  const { status, ...rest } = resolved
  return ok({ status, ...rest })
}

function ok(data: Record<string, unknown>): AgentToolResult {
  return { ok: true, code: 'ok', data }
}
```

- [ ] **Step 6: Run test to verify it passes**

```bash
cd supabase/functions/telegram-hatchery-agent && deno test --allow-env --allow-net bmk_tools_test.ts
```

Expected: PASS (6 tests).

- [ ] **Step 7: Add the Supabase-backed store and register the handlers**

Append to `bmk_tools.ts`:

```ts
interface BmkDatabaseResult<T> {
  data: T | null
  error: { message: string } | null
}

interface BmkQuery {
  select(columns: string): BmkQuery
  eq(column: string, value: unknown): BmkQuery
  is(column: string, value: unknown): BmkQuery
  order(column: string, options: { ascending: boolean }): BmkQuery
  limit(count: number): Promise<BmkDatabaseResult<Record<string, unknown>[]>>
  maybeSingle(): Promise<BmkDatabaseResult<Record<string, unknown>>>
}

export interface AgentBmkClient {
  from(table: string): BmkQuery
}

const MAX_BMK_ROWS = 1000

export function createSupabaseAgentBmkStore(
  client: AgentBmkClient,
): AgentBmkStore {
  return {
    async listBreedCoverage() {
      const result = await client
        .from('bmk_breeds')
        .select('breed, age_week')
        .order('breed', { ascending: true })
        .limit(MAX_BMK_ROWS)
      throwIfBmkError(result)
      return (result.data ?? []).map((row) => ({
        breed: String(row.breed ?? ''),
        ageWeek: Number(row.age_week ?? 0),
      })).filter((row) => row.breed !== '' && Number.isFinite(row.ageWeek))
    },
    async findBreedBenchmark(breed, ageWeek) {
      const result = await client
        .from('bmk_breeds')
        .select(
          'breed, age_week, hatchability_pct, fertility_pct, hof_pct, ' +
            'production_pct, egg_weight_g, chick_weight_g',
        )
        .eq('breed', breed)
        .eq('age_week', ageWeek)
        .maybeSingle()
      throwIfBmkError(result)
      const row = result.data
      if (!row) return null
      return {
        breed: String(row.breed ?? breed),
        ageWeek: Number(row.age_week ?? ageWeek),
        hatchabilityPct: optionalNumber(row.hatchability_pct),
        fertilityPct: optionalNumber(row.fertility_pct),
        hofPct: optionalNumber(row.hof_pct),
        productionPct: optionalNumber(row.production_pct),
        eggWeightG: optionalNumber(row.egg_weight_g),
        chickWeightG: optionalNumber(row.chick_weight_g),
      }
    },
    async listEggBreakoutWeeks() {
      const result = await client
        .from('bmk_egg_breakout')
        .select('age_week')
        .order('age_week', { ascending: true })
        .limit(MAX_BMK_ROWS)
      throwIfBmkError(result)
      return (result.data ?? [])
        .map((row) => Number(row.age_week ?? 0))
        .filter((week) => Number.isFinite(week) && week > 0)
    },
    async findEggBreakoutBenchmark(ageWeek) {
      const result = await client
        .from('bmk_egg_breakout')
        .select(
          'age_week, infertile_pct, early24h_pct, early48h_pct, ' +
            'blood_ring_pct, black_eye_pct, early_dead_pct, mid_dead_pct, ' +
            'late_dead_pct, external_pip_pct, cracked_pct, contam_pct',
        )
        .eq('age_week', ageWeek)
        .maybeSingle()
      throwIfBmkError(result)
      const row = result.data
      if (!row) return null
      return {
        ageWeek: Number(row.age_week ?? ageWeek),
        infertilePct: optionalNumber(row.infertile_pct),
        early24hPct: optionalNumber(row.early24h_pct),
        early48hPct: optionalNumber(row.early48h_pct),
        bloodRingPct: optionalNumber(row.blood_ring_pct),
        blackEyePct: optionalNumber(row.black_eye_pct),
        earlyDeadPct: optionalNumber(row.early_dead_pct),
        midDeadPct: optionalNumber(row.mid_dead_pct),
        lateDeadPct: optionalNumber(row.late_dead_pct),
        externalPipPct: optionalNumber(row.external_pip_pct),
        crackedPct: optionalNumber(row.cracked_pct),
        contamPct: optionalNumber(row.contam_pct),
      }
    },
  }
}

function optionalNumber(value: unknown): number | null {
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : null
}

function throwIfBmkError(result: { error: { message: string } | null }) {
  if (result.error) throw new Error('Could not read benchmark data')
}
```

In `index.ts`, import and register inside `createUnifiedAgentToolHandlers`:

```ts
import {
  type AgentBmkClient,
  createAgentBmkToolHandlers,
  createSupabaseAgentBmkStore,
} from './bmk_tools.ts'
```

```ts
  const bmkStore = createSupabaseAgentBmkStore(
    adminClient as unknown as AgentBmkClient,
  )
  return {
    ...createAgentReadToolHandlers(readStore),
    ...createAgentAuditToolHandlers(auditStore),
    ...createAgentBmkToolHandlers(bmkStore),
    // ...existing spreads unchanged
```

- [ ] **Step 8: Run the full Deno gate**

```bash
cd supabase/functions/telegram-hatchery-agent && deno test --allow-env --allow-net .
cd ../app-hatchery-agent && deno test --allow-env --allow-net .
```

Expected: PASS. If `agent_acceptance_test.ts` asserts an exact tool-name list, add the two new names to its expectation.

- [ ] **Step 9: Update docs and commit**

`docs/LIVING_SPEC.md`: add both tools to the documented agent tool catalog. `docs/CHANGELOG.md`:

```markdown
- 2026-08-14: The agent can look up breed and egg-breakout benchmarks from bmk_breeds / bmk_egg_breakout, with structured misses instead of guessed values.
```

```bash
git add supabase/functions/telegram-hatchery-agent docs/LIVING_SPEC.md docs/CHANGELOG.md
git commit -m "feat(agent): add breed and egg-breakout benchmark tools"
```

---

### Task 7: `get_operational_standards`

**Files:**
- Modify: `supabase/functions/telegram-hatchery-agent/bmk_tools.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/bmk_tools_test.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_protocol.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_tools.ts`

**Interfaces:**
- Consumes: `AgentBmkStore` from Task 6; `assertCustomerAllowed` and `AgentScopeError` from `agent_scope.ts`.
- Produces, added to `AgentBmkStore`:
```ts
  findHatcheryCustomerId(hatcheryId: string): Promise<string | null>
  listOperationalStandards(
    hatcheryId: string | null,
  ): Promise<readonly BmkOperationalStandardRow[]>
```
with
```ts
export interface BmkOperationalStandardRow {
  id: string
  hatcheryId: string | null
  stationKey: string
  sectorKey: string
  metricKey: string
  metricLabel: string
  unit: string
  minValue: number | null
  maxValue: number | null
  targetValue: number | null
  source: string | null
  notes: string | null
  sortOrder: number
}
```

- [ ] **Step 1: Write the failing test**

Append to `bmk_tools_test.ts`. Extend `fixtureStore()` with the two new methods first:

```ts
// Add to the object returned by fixtureStore():
    findHatcheryCustomerId: (hatcheryId) =>
      Promise.resolve(
        hatcheryId === 'hatchery-a'
          ? 'customer-a'
          : hatcheryId === 'hatchery-b'
          ? 'customer-b'
          : null,
      ),
    listOperationalStandards: (hatcheryId) =>
      Promise.resolve(
        hatcheryId === null
          ? [
            {
              id: 'g-1',
              hatcheryId: null,
              stationKey: 'setter',
              sectorKey: 'incubation',
              metricKey: 'setter_temp',
              metricLabel: 'Setter temperature',
              unit: 'F',
              minValue: 99.0,
              maxValue: 100.5,
              targetValue: 99.8,
              source: 'Aviagen',
              notes: null,
              sortOrder: 1,
            },
            {
              id: 'g-2',
              hatcheryId: null,
              stationKey: 'hatcher',
              sectorKey: 'incubation',
              metricKey: 'hatcher_humidity',
              metricLabel: 'Hatcher humidity',
              unit: '%',
              minValue: 50,
              maxValue: 60,
              targetValue: 55,
              source: null,
              notes: null,
              sortOrder: 2,
            },
          ]
          : [
            {
              id: 'h-1',
              hatcheryId: 'hatchery-a',
              stationKey: 'setter',
              sectorKey: 'incubation',
              metricKey: 'setter_temp',
              metricLabel: 'Setter temperature',
              unit: 'F',
              minValue: 99.2,
              maxValue: 100.0,
              targetValue: 99.6,
              source: 'Site SOP',
              notes: 'House override',
              sortOrder: 1,
            },
          ],
      ),
```

Then the tests:

```ts
Deno.test('get_operational_standards returns global rows when unscoped',
  async () => {
    const result = await call('get_operational_standards', {})
    assertEquals(result.ok, true)
    const standards = result.data?.standards as Record<string, unknown>[]
    assertEquals(standards.length, 2)
    assertEquals(standards[0].metricKey, 'setter_temp')
    assertEquals(standards[0].targetValue, 99.8)
  })

Deno.test('hatchery rows override global rows on metricKey', async () => {
  const result = await call('get_operational_standards', {
    hatcheryId: 'hatchery-a',
  })
  const standards = result.data?.standards as Record<string, unknown>[]
  assertEquals(standards.length, 2)
  assertEquals(standards[0].metricKey, 'setter_temp')
  // Overridden by the hatchery row.
  assertEquals(standards[0].targetValue, 99.6)
  assertEquals(standards[0].hatcheryId, 'hatchery-a')
  // Untouched global row still present.
  assertEquals(standards[1].metricKey, 'hatcher_humidity')
  assertEquals(standards[1].targetValue, 55)
})

Deno.test('stationKey filters the merged result', async () => {
  const result = await call('get_operational_standards', {
    hatcheryId: 'hatchery-a',
    stationKey: 'hatcher',
  })
  const standards = result.data?.standards as Record<string, unknown>[]
  assertEquals(standards.length, 1)
  assertEquals(standards[0].metricKey, 'hatcher_humidity')
})

Deno.test('a hatchery outside scope is rejected, not returned empty',
  async () => {
    const result = await call('get_operational_standards', {
      hatcheryId: 'hatchery-b',
    })
    assertEquals(result.ok, false)
    assertEquals(result.code, 'scope_denied')
  })

Deno.test('an unknown hatchery is rejected', async () => {
  const result = await call('get_operational_standards', {
    hatcheryId: 'hatchery-zzz',
  })
  assertEquals(result.ok, false)
  assertEquals(result.code, 'scope_denied')
})
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd supabase/functions/telegram-hatchery-agent && deno test --allow-env --allow-net bmk_tools_test.ts
```

Expected: FAIL — `get_operational_standards` handler is undefined.

- [ ] **Step 3: Add the tool name and definition**

`agent_protocol.ts`, in the union:

```ts
  | 'get_operational_standards'
```

`agent_tools.ts`, beside the other two benchmark definitions:

```ts
    definition(
      'get_operational_standards',
      'Look up operational target ranges (temperature, humidity, airflow and similar) for a station. Global standards apply everywhere; a hatchery may override any of them. Pass hatcheryId to get that hatchery\'s effective standards.',
      {
        stationKey: measureKeyRule,
        sectorKey: measureKeyRule,
        hatcheryId: idRule,
      },
      [],
    ),
```

- [ ] **Step 4: Implement the handler**

In `bmk_tools.ts`, add the row type and store methods to the interfaces declared in Task 6, add the handler to `createAgentBmkToolHandlers`:

```ts
    get_operational_standards: (input) =>
      getOperationalStandards(store, input),
```

and the implementation:

```ts
/**
 * Global standards overlaid by that hatchery's rows, keyed on metricKey --
 * the same precedence BmkRepository.getOperationalStandards implements in the
 * app, so the agent and the BMK screen never disagree.
 */
async function getOperationalStandards(
  store: AgentBmkStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const hatcheryId = optionalIdentifier(input.arguments.hatcheryId)
  if (hatcheryId) {
    const customerId = await store.findHatcheryCustomerId(hatcheryId)
    if (!customerId) return scopeDenied()
    try {
      assertCustomerAllowed(input.scope, customerId)
    } catch (error) {
      if (error instanceof AgentScopeError) return scopeDenied()
      throw error
    }
  }

  const merged = new Map<string, BmkOperationalStandardRow>()
  for (const row of await store.listOperationalStandards(null)) {
    merged.set(row.metricKey, row)
  }
  if (hatcheryId) {
    for (const row of await store.listOperationalStandards(hatcheryId)) {
      merged.set(row.metricKey, row)
    }
  }

  const stationKey = optionalIdentifier(input.arguments.stationKey)
  const sectorKey = optionalIdentifier(input.arguments.sectorKey)
  const standards = [...merged.values()]
    .filter((row) => !stationKey || row.stationKey === stationKey)
    .filter((row) => !sectorKey || row.sectorKey === sectorKey)
    .sort((left, right) =>
      left.sortOrder - right.sortOrder ||
      left.metricLabel.localeCompare(right.metricLabel)
    )

  return ok({ hatcheryId: hatcheryId ?? null, standards })
}

function optionalIdentifier(value: unknown): string | null {
  if (typeof value !== 'string') return null
  const text = value.trim()
  return text ? text : null
}

function scopeDenied(): AgentToolResult {
  return { ok: false, code: 'scope_denied', data: null }
}
```

Add the import:

```ts
import { AgentScopeError, assertCustomerAllowed } from './agent_scope.ts'
```

- [ ] **Step 5: Run test to verify it passes**

```bash
cd supabase/functions/telegram-hatchery-agent && deno test --allow-env --allow-net bmk_tools_test.ts
```

Expected: PASS (11 tests).

- [ ] **Step 6: Add the Supabase store methods**

In `createSupabaseAgentBmkStore`:

```ts
    async findHatcheryCustomerId(hatcheryId) {
      const result = await client
        .from('hatcheries')
        .select('id, customer_id')
        .eq('id', hatcheryId)
        .maybeSingle()
      throwIfBmkError(result)
      const customerId = result.data?.customer_id
      return typeof customerId === 'string' && customerId ? customerId : null
    },
    async listOperationalStandards(hatcheryId) {
      const base = client
        .from('bmk_operational_standards')
        .select(
          'id, hatchery_id, station_key, sector_key, metric_key, ' +
            'metric_label, unit, min_value, max_value, target_value, ' +
            'source, notes, sort_order',
        )
      const filtered = hatcheryId === null
        ? base.is('hatchery_id', null)
        : base.eq('hatchery_id', hatcheryId)
      const result = await filtered
        .order('sort_order', { ascending: true })
        .limit(MAX_BMK_ROWS)
      throwIfBmkError(result)
      return (result.data ?? []).map((row) => ({
        id: String(row.id ?? ''),
        hatcheryId: typeof row.hatchery_id === 'string'
          ? row.hatchery_id
          : null,
        stationKey: String(row.station_key ?? ''),
        sectorKey: String(row.sector_key ?? ''),
        metricKey: String(row.metric_key ?? ''),
        metricLabel: String(row.metric_label ?? ''),
        unit: String(row.unit ?? ''),
        minValue: optionalNumber(row.min_value),
        maxValue: optionalNumber(row.max_value),
        targetValue: optionalNumber(row.target_value),
        source: typeof row.source === 'string' ? row.source : null,
        notes: typeof row.notes === 'string' ? row.notes : null,
        sortOrder: Number(row.sort_order ?? 0),
      }))
    },
```

- [ ] **Step 7: Run the full Deno gate**

```bash
cd supabase/functions/telegram-hatchery-agent && deno test --allow-env --allow-net .
cd ../app-hatchery-agent && deno test --allow-env --allow-net .
```

- [ ] **Step 8: Update docs and commit**

```markdown
- 2026-08-14: The agent can read operational standards, merging global rows with the requesting hatchery's overrides and rejecting hatcheries outside the caller's scope.
```

```bash
git add supabase/functions/telegram-hatchery-agent docs/LIVING_SPEC.md docs/CHANGELOG.md
git commit -m "feat(agent): add scoped operational standards tool"
```

---

### Task 8: `compare_selected_audit_to_benchmark`

**Files:**
- Modify: `supabase/functions/telegram-hatchery-agent/bmk_tools.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/bmk_tools_test.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_protocol.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_tools.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/index.ts` (pass the audit store into the BMK handlers)

**Interfaces:**
- Consumes: `resolveBreedBenchmark` / `resolveEggBreakoutBenchmark` (Task 6); `AgentAuditStore` from `agent_audit_tools.ts`; `sampleWeightedMean` from `agent_metrics.ts`.
- Produces: `createAgentBmkToolHandlers(store: AgentBmkStore, auditStore?: AgentAuditStore)` — the second argument is optional so the existing Task 6/7 tests keep working; when it is absent the compare handler is not registered.

**Semantics to implement exactly:**

- Operates on the audit already selected in the conversation. No arguments — same contract as `get_selected_audit_breakouts`.
- Actuals come from the audit's breakout rows, aggregated with `sampleWeightedMean(rows, valueKey, 'traySize')`. Report `observedRows` per metric.
- Compared metrics:
  - From `bmk_breeds`: `hatchabilityPct`, `fertilityPct`, `hofPct` (breakout rows carry all three). `productionPct`, `eggWeightG`, `chickWeightG` have no actual on a breakout row — emit them with `reason: 'no_actual'`.
  - From `bmk_egg_breakout`: all eleven defect percentages. The audit field for contamination is `contaminatedPct`; the benchmark field is `contamPct`. Map explicitly.
- `delta = actual - standard`, rounded to one decimal via `roundTo`.
- A metric with no benchmark coverage emits `reason: 'no_benchmark'`; a metric with no actual emits `reason: 'no_actual'`. Neither is dropped.

- [ ] **Step 1: Write the failing test**

Append to `bmk_tools_test.ts`:

```ts
import type { AgentAuditStore } from './agent_audit_tools.ts'

function fixtureAuditStore(): AgentAuditStore {
  const audit = {
    id: 'audit-1',
    customerId: 'customer-a',
    flockId: 'flock-a',
    hatcheryId: 'hatchery-a',
    date: '2026-08-01',
    status: 'completed',
    customerName: 'Customer A',
    flockName: 'Flock A',
    hatcheryName: 'Hatchery A',
    selectedStationKeys: null,
    stationsCompleted: null,
    createdAt: null,
    completedAt: null,
    breed: 'Ross308',
    flockAgeWeeks: 35,
    findings: null,
    scorecard: null,
    notes: null,
  }
  return {
    findFlockCustomerId: () => Promise.resolve('customer-a'),
    findLatestAuditListResult: () => Promise.resolve(null),
    findLatestSelectedAuditResult: () => Promise.resolve(null),
    loadConversationContext: () =>
      Promise.resolve({
        customerId: 'customer-a',
        flockId: 'flock-a',
        auditId: 'audit-1',
      }),
    findAudit: () => Promise.resolve(audit),
    listAudits: () => Promise.resolve({ rows: [audit], truncated: false }),
    listAuditBreakouts: () =>
      Promise.resolve({
        rows: [
          {
            breakoutType: 'fresh' as const,
            id: 'b-1',
            sessionId: 'audit-1',
            customerId: 'customer-a',
            flockId: 'flock-a',
            hatcheryId: 'hatchery-a',
            date: '2026-08-01',
            house: null,
            setter: null,
            hatcher: null,
            trolley: null,
            tray: null,
            position: null,
            traySize: 100,
            infertileCount: null,
            infertilePct: 6,
            early24hPct: 1,
            early48hPct: 1,
            bloodRingPct: 0.5,
            blackEyePct: 0.5,
            earlyDeadPct: 2,
            midDeadPct: 1,
            lateDeadPct: 2,
            externalPipPct: 0.5,
            crackedPct: 1,
            contaminatedPct: 1.5,
            hatchabilityPct: 86,
            fertilityPct: 94,
            hofPct: 84,
            culledPct: null,
            deadPct: null,
          },
        ],
        truncated: false,
      }),
  } as unknown as AgentAuditStore
}

Deno.test('compare_selected_audit_to_benchmark returns per-metric deltas',
  async () => {
    const handlers = createAgentBmkToolHandlers(
      fixtureStore(),
      fixtureAuditStore(),
    )
    const result = await handlers.compare_selected_audit_to_benchmark!({
      scope,
      conversationId: 'conversation-a',
      activeVisitId: null,
      arguments: {},
    })

    assertEquals(result.ok, true)
    assertEquals(result.data?.breed, 'Ross308')
    assertEquals(result.data?.ageWeek, 35)

    const rows = result.data?.comparisons as Record<string, unknown>[]
    const byKey = new Map(rows.map((row) => [row.metricKey, row]))

    assertEquals(byKey.get('hatchabilityPct')?.actual, 86)
    assertEquals(byKey.get('hatchabilityPct')?.standard, 90)
    assertEquals(byKey.get('hatchabilityPct')?.delta, -4)

    // Audit contaminatedPct maps onto benchmark contamPct.
    assertEquals(byKey.get('contamPct')?.actual, 1.5)
    assertEquals(byKey.get('contamPct')?.standard, 0.5)
    assertEquals(byKey.get('contamPct')?.delta, 1)

    // No actual exists for these on a breakout row -- reported, not dropped.
    assertEquals(byKey.get('eggWeightG')?.reason, 'no_actual')
    assertEquals(byKey.get('productionPct')?.reason, 'no_actual')
  })

Deno.test('compare reports a missing benchmark rather than dropping metrics',
  async () => {
    const store = fixtureStore()
    const emptyBenchmarks: AgentBmkStore = {
      ...store,
      findBreedBenchmark: () => Promise.resolve(null),
      findEggBreakoutBenchmark: () => Promise.resolve(null),
    }
    const handlers = createAgentBmkToolHandlers(
      emptyBenchmarks,
      fixtureAuditStore(),
    )
    const result = await handlers.compare_selected_audit_to_benchmark!({
      scope,
      conversationId: 'conversation-a',
      activeVisitId: null,
      arguments: {},
    })

    assertEquals(result.data?.status, 'week_out_of_range')
    assertEquals(result.data?.breed, 'Ross308')
  })

Deno.test('compare requires a selected audit', async () => {
  const auditStore = {
    ...fixtureAuditStore(),
    loadConversationContext: () => Promise.resolve(null),
  } as unknown as AgentAuditStore
  const handlers = createAgentBmkToolHandlers(fixtureStore(), auditStore)
  const result = await handlers.compare_selected_audit_to_benchmark!({
    scope,
    conversationId: 'conversation-a',
    activeVisitId: null,
    arguments: {},
  })
  assertEquals(result.ok, false)
})
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd supabase/functions/telegram-hatchery-agent && deno test --allow-env --allow-net bmk_tools_test.ts
```

Expected: FAIL — `compare_selected_audit_to_benchmark` is undefined.

- [ ] **Step 3: Add the tool name and definition**

`agent_protocol.ts`:

```ts
  | 'compare_selected_audit_to_benchmark'
```

`agent_tools.ts`:

```ts
    definition(
      'compare_selected_audit_to_benchmark',
      'Compare the audit already selected in this conversation against the published breed and egg-breakout standards for that flock\'s breed and age. Returns actual, standard and delta per metric. Never supply or reconstruct an audit ID.',
    ),
```

- [ ] **Step 4: Implement the handler**

In `bmk_tools.ts`, change the factory signature and register the handler:

```ts
export function createAgentBmkToolHandlers(
  store: AgentBmkStore,
  auditStore?: AgentAuditStore,
): Partial<Record<AgentToolName, AgentToolHandler>> {
  const handlers: Partial<Record<AgentToolName, AgentToolHandler>> = {
    get_breed_benchmark: (input) => getBreedBenchmark(store, input),
    get_egg_breakout_benchmark: (input) =>
      getEggBreakoutBenchmark(store, input),
    get_operational_standards: (input) =>
      getOperationalStandards(store, input),
  }
  if (auditStore) {
    handlers.compare_selected_audit_to_benchmark = (input) =>
      compareSelectedAuditToBenchmark(store, auditStore, input)
  }
  return handlers
}
```

Add the metric maps and the handler:

```ts
/** Breakout-row field -> breed-benchmark field. */
const BREED_METRIC_SOURCES: readonly {
  metricKey: keyof BmkBreedBenchmarkRow
  actualKey: string | null
  label: string
  unit: string
}[] = [
  { metricKey: 'hatchabilityPct', actualKey: 'hatchabilityPct', label: 'Hatchability', unit: '%' },
  { metricKey: 'fertilityPct', actualKey: 'fertilityPct', label: 'Fertility', unit: '%' },
  { metricKey: 'hofPct', actualKey: 'hofPct', label: 'Hatch of fertile', unit: '%' },
  { metricKey: 'productionPct', actualKey: null, label: 'Production', unit: '%' },
  { metricKey: 'eggWeightG', actualKey: null, label: 'Egg weight', unit: 'g' },
  { metricKey: 'chickWeightG', actualKey: null, label: 'Chick weight', unit: 'g' },
]

/**
 * Breakout-row field -> breakout-benchmark field. The audit column is
 * contaminatedPct while the benchmark column is contamPct, so the mapping is
 * explicit rather than by name.
 */
const BREAKOUT_METRIC_SOURCES: readonly {
  metricKey: keyof BmkEggBreakoutBenchmarkRow
  actualKey: string
  label: string
}[] = [
  { metricKey: 'infertilePct', actualKey: 'infertilePct', label: 'Infertile' },
  { metricKey: 'early24hPct', actualKey: 'early24hPct', label: 'Early dead 24h' },
  { metricKey: 'early48hPct', actualKey: 'early48hPct', label: 'Early dead 48h' },
  { metricKey: 'bloodRingPct', actualKey: 'bloodRingPct', label: 'Blood ring' },
  { metricKey: 'blackEyePct', actualKey: 'blackEyePct', label: 'Black eye' },
  { metricKey: 'earlyDeadPct', actualKey: 'earlyDeadPct', label: 'Early dead' },
  { metricKey: 'midDeadPct', actualKey: 'midDeadPct', label: 'Mid dead' },
  { metricKey: 'lateDeadPct', actualKey: 'lateDeadPct', label: 'Late dead' },
  { metricKey: 'externalPipPct', actualKey: 'externalPipPct', label: 'External pip' },
  { metricKey: 'crackedPct', actualKey: 'crackedPct', label: 'Cracked' },
  { metricKey: 'contamPct', actualKey: 'contaminatedPct', label: 'Contaminated' },
]

async function compareSelectedAuditToBenchmark(
  store: AgentBmkStore,
  auditStore: AgentAuditStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const context = auditStore.loadConversationContext
    ? await auditStore.loadConversationContext(input.conversationId)
    : null
  if (
    !context?.customerId || !context.auditId ||
    !input.scope.allowedCustomerIds.includes(context.customerId)
  ) {
    return { ok: false, code: 'audit_selection_required', data: null }
  }

  const audit = await auditStore.findAudit(
    context.auditId,
    input.scope.allowedCustomerIds,
  )
  if (!audit || audit.customerId !== context.customerId) return scopeDenied()

  const ageWeek = audit.flockAgeWeeks
  if (!audit.breed || ageWeek === null) {
    return ok({
      status: 'unavailable',
      reason: audit.breed ? 'missing_flock_age' : 'missing_breed',
      auditId: audit.id,
    })
  }

  const breedResult = await resolveBreedBenchmark(store, audit.breed, ageWeek)
  if (breedResult.status !== 'ok') {
    const { status, ...rest } = breedResult
    return ok({ status, auditId: audit.id, ageWeek, ...rest })
  }
  const breakoutResult = await resolveEggBreakoutBenchmark(store, ageWeek)

  const page = await auditStore.listAuditBreakouts({
    auditId: audit.id,
    customerId: audit.customerId,
  })
  const rows = page.rows.filter((row) =>
    row.sessionId === audit.id && row.customerId === audit.customerId
  ) as unknown as Record<string, unknown>[]

  const comparisons: Record<string, unknown>[] = []

  for (const metric of BREED_METRIC_SOURCES) {
    const standard = breedResult.row[metric.metricKey]
    comparisons.push(
      comparison({
        metricKey: metric.metricKey,
        label: metric.label,
        unit: metric.unit,
        standard: typeof standard === 'number' ? standard : null,
        aggregate: metric.actualKey === null
          ? { value: null, observedRows: 0, weight: null }
          : sampleWeightedMean(rows, metric.actualKey, 'traySize'),
      }),
    )
  }

  for (const metric of BREAKOUT_METRIC_SOURCES) {
    const standard = breakoutResult.status === 'ok'
      ? breakoutResult.row[metric.metricKey]
      : null
    comparisons.push(
      comparison({
        metricKey: metric.metricKey,
        label: metric.label,
        unit: '%',
        standard: typeof standard === 'number' ? standard : null,
        aggregate: sampleWeightedMean(rows, metric.actualKey, 'traySize'),
      }),
    )
  }

  return ok({
    auditId: audit.id,
    breed: breedResult.row.breed,
    ageWeek,
    breakoutBenchmarkAvailable: breakoutResult.status === 'ok',
    comparisons,
  })
}

function comparison(input: {
  metricKey: string
  label: string
  unit: string
  standard: number | null
  aggregate: { value: number | null; observedRows: number }
}): Record<string, unknown> {
  const actual = input.aggregate.value
  const base = {
    metricKey: input.metricKey,
    label: input.label,
    unit: input.unit,
    actual,
    standard: input.standard,
    observedRows: input.aggregate.observedRows,
  }
  if (actual === null) return { ...base, delta: null, reason: 'no_actual' }
  if (input.standard === null) {
    return { ...base, delta: null, reason: 'no_benchmark' }
  }
  return { ...base, delta: roundTo(actual - input.standard) }
}
```

Add the imports:

```ts
import type { AgentAuditStore } from './agent_audit_tools.ts'
import { roundTo, sampleWeightedMean } from './agent_metrics.ts'
```

- [ ] **Step 5: Run test to verify it passes**

```bash
cd supabase/functions/telegram-hatchery-agent && deno test --allow-env --allow-net bmk_tools_test.ts
```

Expected: PASS (14 tests).

- [ ] **Step 6: Pass the audit store through in `index.ts`**

```ts
    ...createAgentBmkToolHandlers(bmkStore, auditStore),
```

- [ ] **Step 7: Run the full Deno gate**

```bash
cd supabase/functions/telegram-hatchery-agent && deno test --allow-env --allow-net .
cd ../app-hatchery-agent && deno test --allow-env --allow-net .
```

- [ ] **Step 8: Update docs and commit**

```markdown
- 2026-08-14: The agent can compare the selected audit against breed and egg-breakout standards, with deltas computed server-side and unmatched metrics reported rather than dropped.
```

```bash
git add supabase/functions/telegram-hatchery-agent docs/LIVING_SPEC.md docs/CHANGELOG.md
git commit -m "feat(agent): compare selected audit against BMK standards"
```

---

### Task 9: Auto-attach benchmarks to audit reads

**Files:**
- Modify: `supabase/functions/telegram-hatchery-agent/agent_audit_tools.ts` (`getAuditSummary` ~line 420, `getSelectedAuditBreakouts` ~line 498, `auditSummary` ~line 561)
- Modify: `supabase/functions/telegram-hatchery-agent/index.ts` (pass the BMK store into the audit handlers)
- Test: `supabase/functions/telegram-hatchery-agent/agent_audit_tools_test.ts`

**Interfaces:**
- Consumes: `resolveBreedBenchmark`, `resolveEggBreakoutBenchmark`, `AgentBmkStore` from Task 6.
- Produces: `createAgentAuditToolHandlers(store: AgentAuditStore, options?: { bmkStore?: AgentBmkStore })` — optional so existing call sites and tests keep compiling; without it the `benchmark` block is `{ status: 'unavailable', reason: 'benchmark_unavailable' }`.

The block appears on both `get_audit_summary` and `get_selected_audit_breakouts` results:

```ts
benchmark: {
  status: 'ok',
  breed: 'Ross308',
  ageWeek: 35,
  breedStandard: { /* BmkBreedBenchmarkRow */ },
  breakoutStandard: { /* BmkEggBreakoutBenchmarkRow */ } | null,
}
```

or

```ts
benchmark: { status: 'unavailable', reason: 'missing_breed' | 'missing_flock_age' | 'breed_not_found' | 'week_out_of_range' | 'benchmark_unavailable' }
```

It is always present. Never omit it silently.

- [ ] **Step 1: Write the failing test**

Append to `agent_audit_tools_test.ts` (reuse the fixtures already in that file for the audit store; add a small BMK stub):

```ts
Deno.test('get_audit_summary attaches the matching benchmark', async () => {
  const handlers = createAgentAuditToolHandlers(fixtureStore(), {
    bmkStore: {
      listBreedCoverage: () =>
        Promise.resolve([{ breed: 'Ross308', ageWeek: 35 }]),
      findBreedBenchmark: () =>
        Promise.resolve({
          breed: 'Ross308',
          ageWeek: 35,
          hatchabilityPct: 90,
          fertilityPct: 95,
          hofPct: 86,
          productionPct: 83,
          eggWeightG: 67,
          chickWeightG: 48,
        }),
      listEggBreakoutWeeks: () => Promise.resolve([35]),
      findEggBreakoutBenchmark: () =>
        Promise.resolve({
          ageWeek: 35,
          infertilePct: 4,
          early24hPct: 1,
          early48hPct: 1,
          bloodRingPct: 0.5,
          blackEyePct: 0.5,
          earlyDeadPct: 2,
          midDeadPct: 1,
          lateDeadPct: 2,
          externalPipPct: 0.5,
          crackedPct: 1,
          contamPct: 0.5,
        }),
      findHatcheryCustomerId: () => Promise.resolve(null),
      listOperationalStandards: () => Promise.resolve([]),
    },
  })

  const result = await handlers.get_audit_summary!({
    scope,
    conversationId: 'conversation-a',
    activeVisitId: null,
    arguments: {},
  })

  const benchmark = result.data?.benchmark as Record<string, unknown>
  assertEquals(benchmark.status, 'ok')
  assertEquals(benchmark.breed, 'Ross308')
  assertEquals(benchmark.ageWeek, 35)
})

Deno.test('the benchmark block is present and explicit when unavailable',
  async () => {
    const handlers = createAgentAuditToolHandlers(fixtureStore())
    const result = await handlers.get_audit_summary!({
      scope,
      conversationId: 'conversation-a',
      activeVisitId: null,
      arguments: {},
    })
    const benchmark = result.data?.benchmark as Record<string, unknown>
    assertEquals(benchmark.status, 'unavailable')
    assertEquals(benchmark.reason, 'benchmark_unavailable')
  })
```

Adjust the fixture audit's `breed` / `flockAgeWeeks` to `'Ross308'` / `35` if the existing fixture leaves them null.

- [ ] **Step 2: Run test to verify it fails**

```bash
cd supabase/functions/telegram-hatchery-agent && deno test --allow-env --allow-net agent_audit_tools_test.ts
```

Expected: FAIL — `createAgentAuditToolHandlers` takes one argument; `benchmark` is undefined.

- [ ] **Step 3: Implement the attachment**

In `agent_audit_tools.ts`, add the options parameter and a resolver:

```ts
import {
  type AgentBmkStore,
  resolveBreedBenchmark,
  resolveEggBreakoutBenchmark,
} from './bmk_tools.ts'

export interface AgentAuditToolOptions {
  bmkStore?: AgentBmkStore
}

/**
 * The benchmark block for one audit. Always returned -- an unresolvable
 * benchmark is reported with a reason so the agent can say the standard is
 * unknown instead of quietly answering without one.
 */
async function auditBenchmark(
  audit: AgentAuditReadRow,
  bmkStore: AgentBmkStore | undefined,
): Promise<Record<string, unknown>> {
  if (!bmkStore) {
    return { status: 'unavailable', reason: 'benchmark_unavailable' }
  }
  if (!audit.breed) {
    return { status: 'unavailable', reason: 'missing_breed' }
  }
  if (audit.flockAgeWeeks === null) {
    return { status: 'unavailable', reason: 'missing_flock_age' }
  }
  const breed = await resolveBreedBenchmark(
    bmkStore,
    audit.breed,
    audit.flockAgeWeeks,
  )
  if (breed.status !== 'ok') {
    return { status: 'unavailable', reason: breed.status }
  }
  const breakout = await resolveEggBreakoutBenchmark(
    bmkStore,
    audit.flockAgeWeeks,
  )
  return {
    status: 'ok',
    breed: breed.row.breed,
    ageWeek: audit.flockAgeWeeks,
    breedStandard: breed.row,
    breakoutStandard: breakout.status === 'ok' ? breakout.row : null,
  }
}
```

Thread `options.bmkStore` from `createAgentAuditToolHandlers` into `getAuditSummary` and `getSelectedAuditBreakouts`. In `getAuditSummary`, `auditSummary(audit)` becomes:

```ts
  return ok({
    ...(auditSummary(audit).data ?? {}),
    benchmark: await auditBenchmark(audit, bmkStore),
  })
```

and in `getSelectedAuditBreakouts` add `benchmark: await auditBenchmark(audit, bmkStore)` to the returned `ok({...})`.

- [ ] **Step 4: Run test to verify it passes**

```bash
cd supabase/functions/telegram-hatchery-agent && deno test --allow-env --allow-net agent_audit_tools_test.ts
```

Expected: PASS.

- [ ] **Step 5: Wire the store in `index.ts`**

```ts
    ...createAgentAuditToolHandlers(auditStore, { bmkStore }),
```

`bmkStore` is already declared above from Task 6. Move its declaration above the `return` if it is not already.

- [ ] **Step 6: Run the full Deno gate**

```bash
cd supabase/functions/telegram-hatchery-agent && deno test --allow-env --allow-net .
cd ../app-hatchery-agent && deno test --allow-env --allow-net .
```

- [ ] **Step 7: Update docs and commit**

```markdown
- 2026-08-14: Audit summary and selected-breakout reads now carry the matching breed and breakout benchmark, or an explicit reason it is unavailable.
```

```bash
git add supabase/functions/telegram-hatchery-agent docs/LIVING_SPEC.md docs/CHANGELOG.md
git commit -m "feat(agent): attach BMK benchmarks to audit reads"
```

---

### Task 10: Prompt rules and deployment

**Files:**
- Modify: `supabase/functions/telegram-hatchery-agent/agent_prompt.ts`
- Modify: `docs/LIVING_SPEC.md`, `docs/CHANGELOG.md`

**Interfaces:**
- Consumes: every tool from Tasks 6–9.
- Produces: nothing consumed downstream.

- [ ] **Step 1: Read the current prompt**

```bash
cat supabase/functions/telegram-hatchery-agent/agent_prompt.ts
```

Find the rules block listing tool-usage constraints. If `agent_prompt_test.ts` (or a prompt assertion inside `agent_acceptance_test.ts`) pins the prompt text, note it — Step 2 updates that expectation first.

- [ ] **Step 2: Write the failing test**

Add to whichever test file already asserts prompt content (create `agent_prompt_test.ts` if none exists):

```ts
import { assert } from '@std/assert'

import { buildAgentSystemPrompt } from './agent_prompt.ts'

Deno.test('the prompt forbids benchmark figures from memory', () => {
  const prompt = buildAgentSystemPrompt()
  assert(prompt.includes('get_breed_benchmark'))
  assert(prompt.includes('never state a benchmark from memory'))
})
```

Use the real exported prompt-builder name from Step 1 — do not invent one.

- [ ] **Step 3: Run test to verify it fails**

```bash
cd supabase/functions/telegram-hatchery-agent && deno test --allow-env --allow-net agent_prompt_test.ts
```

Expected: FAIL.

- [ ] **Step 4: Add the rules**

Insert into the prompt's rules list:

```
- Benchmark figures come only from get_breed_benchmark, get_egg_breakout_benchmark and get_operational_standards; never state a benchmark from memory.
- Always state the breed and the age in weeks alongside any benchmark figure.
- If a tool reports breed_not_found or week_out_of_range, say what is covered and ask; never interpolate, extrapolate, or answer with a nearby week.
- To judge how an audit performed, call compare_selected_audit_to_benchmark rather than subtracting numbers yourself.
```

- [ ] **Step 5: Run test to verify it passes**

```bash
cd supabase/functions/telegram-hatchery-agent && deno test --allow-env --allow-net agent_prompt_test.ts
```

Expected: PASS.

- [ ] **Step 6: Full gate across both doors and Flutter**

```bash
cd supabase/functions/telegram-hatchery-agent && deno test --allow-env --allow-net .
cd ../app-hatchery-agent && deno test --allow-env --allow-net .
```

```bash
flutter analyze && flutter test
```

Expected: all green.

- [ ] **Step 7: Deploy both edge functions**

Use the Supabase MCP `deploy_edge_function` tool for `telegram-hatchery-agent` and `app-hatchery-agent`.

- [ ] **Step 8: Verify end to end**

In the in-app assistant chat, ask: *"What is the hatchability of Ross at week 35?"*

Expected: the agent calls `get_breed_benchmark`, then answers `90%`, naming the breed as Ross308 and the age as week 35. Confirm the tool call was recorded:

```sql
select tool_name, arguments, status
from public.agent_tool_events
order by created_at desc
limit 5;
```

Then ask: *"And at week 80?"* — expected: the agent reports the covered range (25–65 for Ross308) instead of a number.

- [ ] **Step 9: Update docs and commit**

`docs/LIVING_SPEC.md`: the agent's benchmark-sourcing rules. `docs/CHANGELOG.md`:

```markdown
- 2026-08-14: The agent prompt now requires benchmark figures to come from the BMK tools, with the breed and age week always stated.
```

```bash
git add supabase/functions/telegram-hatchery-agent docs/LIVING_SPEC.md docs/CHANGELOG.md
git commit -m "feat(agent): require BMK tools for benchmark answers"
```

---

## Self-Review Notes

Spec coverage check, section by section:

| Spec section | Task |
|---|---|
| 1. Cloud schema + split RLS | 1 |
| 2. Sync push | 3 |
| 2. Sync pull + dirty guard | 4 |
| 2. Dirty-marking on edit | 2 |
| 3. `get_breed_benchmark` | 6 |
| 3. `get_egg_breakout_benchmark` | 6 |
| 3. `get_operational_standards` | 7 |
| 3. `compare_selected_audit_to_benchmark` | 8 |
| 3. Reference data unscoped | 6 (store reads with no customer filter) |
| 4. Breed/age resolution | 5 |
| 5. Auto-attached benchmarks | 9 |
| 6. Prompt | 10 |
| 7. Testing | every task |
| 8. Docs | every task |

Known deliberate choices:

- `createAgentBmkToolHandlers` and `createAgentAuditToolHandlers` take their extra collaborators as optional arguments so each task lands green without rewriting the previous task's tests.
- The compare tool aggregates breakout rows with `sampleWeightedMean(..., 'traySize')` rather than a plain mean, matching how the rest of the agent aggregates sampled station data.
- `productionPct`, `eggWeightG`, and `chickWeightG` have no actual on a breakout row and are always reported with `reason: 'no_actual'`. If an actual source for these is wanted later, it comes from egg-quality and chick-weight panels — a separate change, not this plan.
