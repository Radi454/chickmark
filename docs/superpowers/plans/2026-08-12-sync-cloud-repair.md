# Sync & Cloud Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the DB-drift repair that unblocks flock create/edit and cross-device audit sync, then fix everything the diagnostic session exposed: broken delete propagation (tombstone 403s), silent 1000-row pull truncation, one-bad-row pull aborts, tombstone backlog replay, and the 19 cloud tables that 404 on every sync.

**Architecture:** Offline-first Flutter + SQLite (camelCase) mirrored to Supabase (snake_case). `StartupSyncService` orchestrates: pull tombstones → apply local deletes → push dirty rows → push deletes → pull all tables → photos. Cloud `sync_tombstones` has a `prepare_sync_tombstone_scope()` BEFORE INSERT trigger that resolves the deleted row's customer scope and RAISEs `42501` when the target row is missing — the source of the 403s. PostgREST caps un-ranged selects at 1000 rows — the source of silent truncation.

**Tech Stack:** Flutter/Dart, sqflite (+ FFI tests), supabase_flutter/PostgREST, Supabase MCP (`apply_migration`, `execute_sql`) for cloud DDL.

## Global Constraints

- Gate every task on `flutter analyze` (zero new issues) + the task's tests. STOP on failure.
- **Runner caveat:** this session's agent sandbox may be blocked from the flutter SDK (`Operation not permitted` on `~/Documents/HOME/SDK/flutter`). Before each task's test gate, try `flutter --version`; if blocked, hand the exact gate commands to the user and wait for their pasted output. Never claim a gate passed without seeing output.
- Local sync-meta columns (`syncStatus`, `dirtyAt`, `lastSyncedAt`, `syncError`) never reach Supabase — all push paths route through `stripSyncMeta`/`prepareRemoteRow`.
- Cloud DDL goes through `mcp__supabase__apply_migration` (named migrations), never raw `execute_sql` for DDL.
- Cloud tables/columns are snake_case; every new cloud table gets RLS enabled + policies. Follow the existing convention on `flocks` (`flocks_select` SELECT / `flocks_write` ALL, both `authenticated`).
- Error-message matching against the tombstone trigger uses the exact strings raised by `chickmark_private.prepare_sync_tombstone_scope()`: `Tombstone target is missing or has no customer scope` and `Unsupported tombstone target table`.
- Don't run the `chickmark-dashboard-redesign` worktree build against the real DB while this work is in flight (it re-drops the flocks columns Task 1 heals).

## Diagnostic facts this plan is built on (verified 2026-08-12)

- Live Mac DB (`~/Library/Containers/com.hatchery.hatchaudit/Data/Documents/hatchaudit.db`): flocks table missing `depletionAgeWeeks` + `soldAt`; 8 orphan `breeder_cycle_*` triggers; `user_version` 57. Phone shows identical symptoms → same drift. Fix (Task 1) already written in working tree, verified by SQL replay on a DB copy.
- Cloud tombstone insert as the admin JWT fails with `42501: Tombstone target is missing or has no customer scope` when the target row is absent → `_pushPendingDeletes` batch fails → early `return` → **`deleteRows` never runs; remote deletes fully broken** for any device holding one poisoned tombstone.
- Cloud has 1914 tombstones; PostgREST default caps un-ranged pulls at 1000 → 914 tombstones never reach devices (their deletes never apply). Same cap threatens every large table.
- `agent_conversation_turns` pull dies on `FOREIGN KEY constraint failed`: rows arrive in arbitrary order and `replyToTurnId` is a self-referential FK (cloud parents all exist — verified 0 orphans). One bad row aborts the whole table's pull (per-table catch), which then cascades to `agent_tool_events`.
- 19 tables 404 on every sync (push marks rows failed forever, pull logs noise): `customer_sectors, farms, houses, broiler_target_profiles, broiler_target_rows, flock_placements, broiler_daily_records, broiler_daily_record_revisions, broiler_daily_events, daily_record_sources, performance_alert_rules, performance_concerns, farm_visit_sessions, farm_visit_houses, visit_investigations, visit_findings, cause_assessments, corrective_actions, action_kpi_evaluations`.
- `applyRemoteDeletes` replays all ~1900 synced tombstones inside a transaction on every sync.

---

### Task 1: Land the local DB drift repair (already coded, uncommitted)

**Files (already modified in working tree — review, gate, commit):**
- Modify: `lib/data/database/database_helper.dart` (`_criticalColumns['flocks']` += `depletionAgeWeeks`/`soldAt`; `_dropForeignTriggers` with `breeder_cycle_` prefix, called as Step 1b of `_surgicalSchemaRepair`)
- Test: `test/data/database/surgical_schema_repair_test.dart` (drift-reproduction test appended)
- Test: `test/data/repositories/flock_create_real_db_test.dart` (real-schema create/edit regression)

**Interfaces:**
- Produces: surgical repair heals any DB touched by the redesign branch on next open. No API changes.

- [ ] **Step 1: Review the diff**

Run: `git diff lib/data/database/database_helper.dart test/data/database/surgical_schema_repair_test.dart` and confirm it contains exactly: the two new `_criticalColumns['flocks']` entries, the `_foreignTriggerPrefixes`/`_dropForeignTriggers` addition, the Step 1b call, and the new test. No other hunks.

- [ ] **Step 2: Run the gate**

Run: `flutter test test/data/database/surgical_schema_repair_test.dart test/data/repositories/flock_create_real_db_test.dart && flutter analyze lib/data test/data`
Expected: all tests pass (including the new `breeder-cycle branch drift is healed` test), analyze clean. (Runner caveat from Global Constraints applies.)

- [ ] **Step 3: Commit**

```bash
git add lib/data/database/database_helper.dart test/data/database/surgical_schema_repair_test.dart test/data/repositories/flock_create_real_db_test.dart
git commit -m "fix(db): surgical repair heals breeder-cycle branch drift (flocks columns + foreign triggers)"
```

- [ ] **Step 4: Live verify on the Mac**

Ask the user to hot-restart the running app (press `R` in `flutter run`) and confirm: console shows `[DB REPAIR] columns added: flocks.depletionAgeWeeks, flocks.soldAt | foreign triggers dropped: breeder_cycle_...`, and a flock can be created and edited. Record the outcome in the ledger before proceeding.

---

### Task 2: Tombstone push — per-row isolation, no early return, missing-target = already-deleted

Currently one poisoned tombstone fails the whole batch AND aborts the delete phase. Fix: batch first; on failure, fall back per-tombstone; a `42501` scope-trigger rejection means the target row no longer exists in cloud (or its table isn't cloud-scoped) → the delete is moot → mark synced. Always continue to `deleteRows` for the survivors.

**Files:**
- Modify: `lib/services/supabase/startup_sync_service.dart` (`_pushPendingDeletes`, lines ~451-487)
- Test: `test/services/supabase/startup_sync_service_test.dart`

**Interfaces:**
- Consumes: `SyncTombstoneRepository.markSynced(id)` / `markFailed(id, error)`, `SupabaseService.upsertRowsStrict`, `deleteRows`.
- Produces: `_pushPendingDeletes` never early-returns; per-tombstone outcomes.

- [ ] **Step 1: Write the failing tests**

In `startup_sync_service_test.dart` (reuse its existing tombstone stubs — see `reports pending deletes when remote row deletion fails`):

```dart
  test('a scope-rejected tombstone is marked synced and others still delete',
      () async {
    final poisoned = SyncTombstone(
      id: 'flocks:gone', tableName: 'flocks', rowId: 'gone',
      deletedAt: DateTime(2026, 8, 1), createdAt: DateTime(2026, 8, 1));
    final healthy = SyncTombstone(
      id: 'customers:c9', tableName: 'customers', rowId: 'c9',
      deletedAt: DateTime(2026, 8, 2), createdAt: DateTime(2026, 8, 2));
    when(() => tombstones.getPendingDeletes())
        .thenAnswer((_) async => [poisoned, healthy]);
    // Batch push fails, then per-row: poisoned row raises the scope error,
    // healthy row succeeds.
    var batchCall = 0;
    when(() => supabase.upsertRowsStrict(SyncTombstoneRepository.tableName, any()))
        .thenAnswer((invocation) async {
      final rows = invocation.positionalArguments[1] as List;
      if (rows.length > 1) throw PostgrestException(
          message: 'Tombstone target is missing or has no customer scope',
          code: '42501');
      final id = (rows.single as Map)['id'];
      if (id == 'flocks:gone') {
        throw PostgrestException(
            message: 'Tombstone target is missing or has no customer scope',
            code: '42501');
      }
      batchCall++;
    });

    await service().run();

    verify(() => tombstones.markSynced('flocks:gone')).called(1);
    // Healthy tombstone's remote delete still executed.
    verify(() => supabase.deleteRows('customers', ['c9'])).called(1);
    expect(batchCall, 1);
  });

  test('a genuinely failed tombstone push does not block other tables\' deletes',
      () async {
    // Same two tombstones; per-row push: poisoned fails with a NON-scope error.
    // Expect markFailed for it, deleteRows still called for the healthy table.
    // (Mirror the stub above but throw PostgrestException(message: 'network',
    // code: '500') for the poisoned row; verify markFailed('flocks:gone', any())
    // and deleteRows('customers', ['c9']).)
  });
```

(Write the second test in full — the comment describes it; the implementation is the same stub shape with the different error and `markFailed` verify.)

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/services/supabase/startup_sync_service_test.dart`
Expected: new tests FAIL (current code marks all failed and returns early).

- [ ] **Step 3: Implement**

Replace `_pushPendingDeletes` body:

```dart
  /// Trigger messages from cloud prepare_sync_tombstone_scope() that mean the
  /// deletion is moot: the target row is already gone from the cloud, or its
  /// table has no cloud scope. Retrying can never succeed; the tombstone's
  /// job is done.
  static const _mootTombstonePushErrors = [
    'Tombstone target is missing or has no customer scope',
    'Unsupported tombstone target table',
  ];

  bool _isMootTombstonePush(Object error) {
    final text = error.toString();
    return _mootTombstonePushErrors.any(text.contains);
  }

  Future<void> _pushPendingDeletes(
    void Function(double value, String message) progress,
  ) async {
    progress(0.70, 'Syncing deletes');
    final pending = await _syncTombstoneRepository.getPendingDeletes();
    if (pending.isEmpty) return;

    // Tombstones whose insert reached the cloud (other devices will see them)
    // or whose target is already gone — both proceed to the delete phase.
    final deletable = <SyncTombstone>[];
    try {
      await _supabaseService.upsertRowsStrict(
        SyncTombstoneRepository.tableName,
        pending.map((tombstone) => tombstone.toMap()).toList(),
      );
      deletable.addAll(pending);
    } catch (_) {
      // Batch failed — isolate per tombstone so one poisoned row cannot block
      // every other delete (the exact failure observed in production).
      for (final tombstone in pending) {
        try {
          await _supabaseService.upsertRowsStrict(
            SyncTombstoneRepository.tableName,
            [tombstone.toMap()],
          );
          deletable.add(tombstone);
        } catch (error) {
          if (_isMootTombstonePush(error)) {
            await _syncTombstoneRepository.markSynced(tombstone.id);
          } else {
            await _syncTombstoneRepository.markFailed(tombstone.id, error);
          }
        }
      }
    }

    for (final table in SyncTombstoneRepository.deleteOrder) {
      final tombstones = deletable
          .where((tombstone) => tombstone.tableName == table)
          .toList();
      if (tombstones.isEmpty) continue;
      try {
        await _supabaseService.deleteRows(
          table,
          tombstones.map((tombstone) => tombstone.rowId).toList(),
        );
        for (final tombstone in tombstones) {
          await _syncTombstoneRepository.markSynced(tombstone.id);
        }
      } catch (error) {
        for (final tombstone in tombstones) {
          await _syncTombstoneRepository.markFailed(tombstone.id, error);
        }
      }
    }
  }
```

- [ ] **Step 4: Gate + commit**

Run: `flutter test test/services/supabase/ && flutter analyze lib/services test/services`

```bash
git add lib/services/supabase/startup_sync_service.dart test/services/supabase/startup_sync_service_test.dart
git commit -m "fix(sync): per-tombstone push isolation; moot tombstones resolve instead of poisoning deletes"
```

---

### Task 3: Pull pagination + per-row pull isolation with a forward-ref retry pass

Two defects, one surface: (a) un-ranged `.select()` truncates at 1000 rows silently; (b) one bad row aborts the rest of its table's pull (the `replyToTurnId` forward-reference FK failure).

**Files:**
- Modify: `lib/services/supabase/supabase_service.dart` (`pullFromSupabase`'s inner `pullTable`, `pullSyncTombstones`, `pullOperationalRows`)
- Test: `test/services/supabase/supabase_service_pull_test.dart` (create)

**Interfaces:**
- Produces: `_selectAllPaged(String table)` — pages via `.range(offset, offset + _pullPageSize - 1)` until a short page; `_applyRowsWithRetry(rows, upsert)` — per-row try/catch, failed rows retried once after the first pass (resolves forward references), returns applied count. Both used by all three pull entry points.

- [ ] **Step 1: Write the failing tests**

`supabase_service_pull_test.dart` — unit-test the retry helper directly (it is pure Dart; make it `@visibleForTesting` static or a top-level function):

```dart
  test('a row failing on first pass succeeds on the retry pass', () async {
    final applied = <String>[];
    final rows = [
      {'id': 'child', 'parent': 'parent-1'}, // fails until parent applied
      {'id': 'parent-1'},
    ];
    Future<void> upsert(Map<String, dynamic> row) async {
      if (row['id'] == 'child' && !applied.contains('parent-1')) {
        throw StateError('FOREIGN KEY constraint failed');
      }
      applied.add(row['id'] as String);
    }

    final count = await applyRowsWithRetry(rows, upsert);
    expect(count, 2);
    expect(applied, containsAll(['parent-1', 'child']));
  });

  test('a permanently bad row is skipped without aborting the rest', () async {
    final applied = <String>[];
    final rows = [
      {'id': 'bad'},
      {'id': 'good'},
    ];
    Future<void> upsert(Map<String, dynamic> row) async {
      if (row['id'] == 'bad') throw StateError('boom');
      applied.add(row['id'] as String);
    }

    final count = await applyRowsWithRetry(rows, upsert);
    expect(count, 1);
    expect(applied, ['good']);
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/services/supabase/supabase_service_pull_test.dart`
Expected: FAIL — helper doesn't exist.

- [ ] **Step 3: Implement**

In `supabase_service.dart`:

```dart
const _pullPageSize = 1000;

/// Applies [rows] one at a time; rows that throw are retried once after the
/// first pass so forward references (a row pointing at a later row in the
/// same page, e.g. agent_conversation_turns.replyToTurnId) resolve. Rows that
/// fail both passes are skipped and logged — one bad row must not abort the
/// table. Returns the number of rows applied.
Future<int> applyRowsWithRetry(
  List<Map<String, dynamic>> rows,
  Future<void> Function(Map<String, dynamic> row) upsert,
) async {
  var applied = 0;
  final failed = <Map<String, dynamic>>[];
  for (final row in rows) {
    try {
      await upsert(row);
      applied++;
    } catch (_) {
      failed.add(row);
    }
  }
  for (final row in failed) {
    try {
      await upsert(row);
      applied++;
    } catch (error) {
      safeDebugLog('Pull row skipped (id=${row['id']})', error: error);
    }
  }
  return applied;
}
```

and inside `SupabaseService`:

```dart
  Future<List<Map<String, dynamic>>> _selectAllPaged(String table) async {
    final all = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await _client
          .from(table)
          .select()
          .range(offset, offset + _pullPageSize - 1);
      all.addAll(page.map((row) => Map<String, dynamic>.from(row)));
      if (page.length < _pullPageSize) break;
      offset += _pullPageSize;
    }
    return all;
  }
```

Rewire all three pull entry points to `final rows = await _selectAllPaged(table);` + `return applyRowsWithRetry(rows, upsert);` (keeping each existing per-table catch for table-level errors like 404s). `pullSyncTombstones` and `pullOperationalRows` get the same treatment.

- [ ] **Step 4: Gate + commit**

Run: `flutter test test/services/supabase/ && flutter analyze lib/services test/services`

```bash
git add lib/services/supabase/supabase_service.dart test/services/supabase/supabase_service_pull_test.dart
git commit -m "fix(sync): paginate pulls past the 1000-row cap; per-row isolation with forward-ref retry"
```

---

### Task 4: Tombstone hygiene — applied-flag + 90-day prune (local and cloud)

`applyRemoteDeletes` replays ~1900 tombstones every sync, and both stores grow forever.

**Files:**
- Modify: `lib/data/database/database_helper.dart` (version 57 → 58; `_applyV58Upgrade`; `_criticalColumns['sync_tombstones']` entry)
- Modify: `lib/data/database/database_migrations.dart` (`_applyV58Upgrade`)
- Modify: `lib/data/database/database_schema.dart` (`_createSyncTombstoneTable` gains `appliedAt TEXT`)
- Modify: `lib/data/repositories/sync_tombstone_repository.dart` (`applyRemoteDeletes` filters + stamps `appliedAt`; new `pruneApplied(Duration age)`)
- Modify: `lib/services/supabase/startup_sync_service.dart` (call `pruneApplied(const Duration(days: 90))` at the end of `_run`)
- Cloud: migration `prune_sync_tombstones` (one-off delete + note to re-run periodically)
- Test: `test/features/audits/sync_tracking_repository_test.dart` or a new `test/data/repositories/sync_tombstone_hygiene_test.dart`

**Interfaces:**
- Produces: `sync_tombstones.appliedAt` (camelCase, local only — it is device state, but it does NOT go through `stripSyncMeta`; tombstone pushes build their payload via `_SyncTombstoneColumns.toInsertMap`, so add `appliedAt` to the columns class but NEVER to `toInsertMap`).

- [ ] **Step 1: Failing tests**

```dart
  test('applyRemoteDeletes processes a tombstone once', () async {
    // Arrange: insert a synced tombstone for an existing row.
    // Act: applyRemoteDeletes twice; re-insert the row between calls.
    // Assert: row deleted after first call, still present after second
    // (appliedAt set → not replayed).
  });

  test('pruneApplied removes only old applied tombstones', () async {
    // One applied 100 days ago, one applied yesterday, one un-applied.
    // pruneApplied(90 days) → only the first is gone.
  });
```

Write these in full against the FFI harness of `sync_tracking_repository_test.dart` (hand-built `sync_tombstones` table now includes `appliedAt TEXT`).

- [ ] **Step 2: Implement local**

v58 migration (`_ensureColumns(db, 'sync_tombstones', const ['appliedAt TEXT'])`), schema parity in `_createSyncTombstoneTable`, `_criticalColumns['sync_tombstones'] = ['appliedAt TEXT']`, version 58, `_onUpgrade` chain entry — the exact 3-way parity discipline from the v57 task. Then:

```dart
  Future<void> applyRemoteDeletes() async {
    final db = await _dbHelper.db;
    final columns = await _SyncTombstoneColumns.forExecutor(db);
    final rows = await db.query(
      tableName,
      where:
          '${columns.syncedAtReadExpression} IS NOT NULL AND appliedAt IS NULL',
      orderBy: '${columns.deletedAtReadExpression} ASC',
    );
    // ... existing delete loop unchanged ...
    // After the transaction, stamp the processed ids:
    // UPDATE sync_tombstones SET appliedAt = <nowIso> WHERE id IN (...)
  }

  Future<int> pruneApplied(Duration age) async {
    final db = await _dbHelper.db;
    final cutoff = DateTime.now().subtract(age).toIso8601String();
    return db.delete(
      tableName,
      where: 'appliedAt IS NOT NULL AND appliedAt < ?',
      whereArgs: [cutoff],
    );
  }
```

Guard: `appliedAt` may be missing on drifted DBs — repair map covers it; `applyRemoteDeletes` runs after open (repair already ran).

Note the re-pull loop: pruned tombstones re-arrive on the next pull (cloud keeps them 90 days too, Step 3) and `upsertRemoteTombstone` re-inserts them synced with `appliedAt` NULL → they replay once, delete nothing (rows already gone), and get stamped again. Acceptable; full dedup would need remote-id memory, out of scope.

- [ ] **Step 3: Cloud prune migration**

Via `mcp__supabase__apply_migration`, name `prune_sync_tombstones`:

```sql
delete from public.sync_tombstones
 where deleted_at < (now() - interval '90 days')::text;
```

(`deleted_at` is stored as ISO-8601 text; lexicographic comparison against an ISO string is valid. Confirm the produced literal is ISO-formatted, e.g. `to_char(now() - interval '90 days', 'YYYY-MM-DD"T"HH24:MI:SS')`.)

- [ ] **Step 4: Gate + commit**

Run: `flutter test test/data/ test/features/audits/ test/services/supabase/ && flutter analyze`

```bash
git add -u lib test
git commit -m "feat(sync): tombstone applied-flag stops replay; 90-day prune local and cloud"
```

---

### Task 5: Create the 19 missing cloud tables + extend the tombstone scope trigger

Stops the per-sync 404 storm and lets operational rows actually sync. DDL is generated from the local schema, not hand-written.

**Files:**
- Create: `docs/superpowers/plans/artifacts/2026-08-12-operational-mirror.sql` (generated, reviewed, then applied)
- Cloud: migration `operational_tables_mirror` via `mcp__supabase__apply_migration`
- Cloud: migration `tombstone_scope_operational_tables` (extend trigger allowlist)

**Interfaces:**
- Consumes: local schema as source of truth (`PRAGMA table_info` per table).
- Produces: cloud snake_case mirrors with RLS for exactly the 19 tables listed in Diagnostic facts.

- [ ] **Step 1: Generate DDL from the local schema**

For each of the 19 tables, run `sqlite3 <db> "PRAGMA table_info(<table>)"` against a fresh test DB (or read the CREATE TABLE blocks in `lib/data/database/database_schema.dart` / `database_migrations.dart`). Transform per rule:
- camelCase → snake_case column names; table name unchanged.
- SQLite TEXT→`text`, INTEGER→`bigint`, REAL→`double precision`.
- Columns listed for that table in `PerformanceSyncRepository._jsonColumnsByTable` → `jsonb` (the push path `prepareRemoteRow` sends decoded JSON for them).
- Drop the four sync-meta columns and any columns in `PerformanceSyncRepository._deviceOnlySourceColumns` (they are stripped before push).
- `id text primary key` (for every table whose local PK is `id`); all other columns nullable (defaults enforced app-side).

Example output shape (farms):

```sql
create table if not exists public.farms (
  id text primary key,
  customer_id text,
  name text,
  location text,
  notes text,
  is_active bigint,
  sector_key text,
  created_by text,
  created_at text,
  updated_at text
);
alter table public.farms enable row level security;
create policy farms_select on public.farms for select to authenticated using (true);
create policy farms_write on public.farms for all to authenticated using (true) with check (true);
```

(Adjust the column list to what PRAGMA actually reports — the example is the shape, the PRAGMA is the truth. Repeat the table+RLS block for all 19.)

- [ ] **Step 2: Review pass**

Read the generated SQL top to bottom: every table present, no sync-meta columns, jsonb columns match `_jsonColumnsByTable`, every table has the RLS enable + two policies. Diff the column count per table against PRAGMA output.

- [ ] **Step 3: Apply + extend the tombstone trigger**

Apply `operational_tables_mirror` via `apply_migration`. Then apply `tombstone_scope_operational_tables`: recreate `chickmark_private.prepare_sync_tombstone_scope()` with the customer-scoped operational tables added to the `= any (array[...])` branch — exactly those of the 19 that have a `customer_id` column (from Step 1's PRAGMA data; expected: `customer_sectors, farms, farm_visit_sessions, performance_concerns`, verify the rest). Tables without `customer_id` stay unsupported — their tombstones resolve as moot via Task 2, and their remote rows are removed by `deleteRows` before the tombstone is marked, which is acceptable for device-authored operational data.

- [ ] **Step 4: Verify end-to-end**

Trigger a sync in the running app (or wait for the next `AppSyncCoordinator` nudge) and check cloud logs:

Use `mcp__supabase__query_logs` with `select substring(event_message,1,90) as req, count(*) n from logs where source='edge_logs' and event_message like '%404%' group by req order by n desc limit 20` — Expected: no `farms`/`customer_sectors`/broiler 404s in the new window. Then `select count(*) from farms;` via `execute_sql` — Expected: the device's farm rows arrived.

- [ ] **Step 5: Record**

No app code changed in this task. Note the migration names + verification results in the ledger; update the `supabase-cloud-wiring` memory (remaining-tables TODO is now done).

---

### Task 6: Final regression + live cross-device verification

- [ ] **Step 1: Full gates**

Run: `flutter analyze && flutter test`
Expected: clean, all green (suite was 1281+ before this plan).

- [ ] **Step 2: Live verification checklist (user-assisted)**

1. Mac: hot-restart → `[DB REPAIR]` line appears at most once more (healed DBs log nothing); create + edit a flock; both succeed.
2. Mac console: sync completes with NO `Supabase pull failed`, no `sync_tombstones` 403, no 404 storm, no `FOREIGN KEY constraint failed` on agent tables.
3. Phone: rebuild + install; create/edit flock; enter a test audit; confirm it appears on the phone dashboard.
4. Cross-device: after a Mac sync, the phone's test audit is visible on the Mac (pull no longer aborts at flocks).
5. Delete a test record on one device; after both devices sync, it is gone from the other (tombstone pipeline restored).

- [ ] **Step 3: Cleanup + memory**

Delete the scratchpad DB copy (`repro.db`). Update memory: `per-row-sync-dirty-tracking` (tombstone pipeline + pagination now hardened; deferred items resolved: tombstone prune, per-row pull isolation), and add the branch-switch DB-drift hazard + `_dropForeignTriggers` mechanism to a memory note.

```bash
git add -A docs/superpowers/plans/2026-08-12-sync-cloud-repair.md
git commit -m "docs: sync & cloud repair plan"
```

---

## Non-Goals

- Incremental pull watermark (`updated_at >= lastSync`) — still the biggest perf win, still separate: most cloud tables (e.g. flocks) have no `updated_at` column yet; watermark needs a cloud schema pass of its own.
- Redesign-branch reconciliation (merging breeder-cycle schema properly) — happens on that branch's merge; this plan only defends against its drift.
- Poison-row age-out for reference-table pull blackouts (deferred from the sync-hardening plan; unchanged).
- Cloud `updated_at` columns / conflict-check upgrades for reference tables.

## Self-Review Notes

- Coverage vs diagnosed defects: drift (T1), tombstone 403 + delete-phase abort (T2), 1000-row truncation (T3), per-row pull aborts incl. `replyToTurnId` (T3), tombstone replay/backlog both stores (T4), 19 missing cloud tables + trigger allowlist (T5), end-to-end proof (T6). The `farms` POST 404 rows currently stuck `failed` self-heal after T5: failed rows are re-pushed every sync by design.
- Type consistency: `applyRowsWithRetry(List<Map<String, dynamic>>, Future<void> Function(Map<String, dynamic>))` used by all three pull paths; `SyncTombstone` fields match `sync_tombstone_model.dart`; `pruneApplied(Duration)` named consistently in repo and service call.
- Ordering: T1 independent and urgent (do first). T2–T4 app-side, sequential (T4's schema bump last to keep one migration). T5 cloud-only, can run parallel to T2–T4 but before T6. T6 last.
