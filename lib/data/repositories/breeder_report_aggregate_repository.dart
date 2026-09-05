import '../database/database_helper.dart';

/// Local-storage side of the daily-report sync aggregate
/// (breeder-flock-performance ticket 15, design doc section 13.1): "a
/// header plus bird movements, feed entries, egg production entries, and
/// inventory movements ... pushed as one aggregate ... a child row is
/// never individually dirty-pushed."
///
/// This repository deliberately does NOT reuse
/// `PerformanceSyncRepository`'s per-row `getDirtyRows`/`markRowsSynced` for
/// these five tables (`breeder_daily_reports` and the four child tables
/// below are absent from that repository's push lists — see
/// `PerformanceSyncRepository.breederAggregatePullOnly`'s doc comment). A
/// child row's own `syncStatus`/`dirtyAt` still exist and still drive
/// *whether the aggregate needs pushing at all* ([reportIdsNeedingPush]),
/// but once a push is due, every current row for that report is sent —
/// dirty or not — because the cloud replaces the whole child set in one
/// transaction; a payload built from only the dirty subset would silently
/// drop rows the cloud has never seen.
///
/// `lib/services/breeder/breeder_report_sync_service.dart` is the only
/// caller; it owns the actual push/conflict orchestration.
class BreederReportAggregateRepository {
  BreederReportAggregateRepository({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  final DatabaseHelper _dbHelper;

  static const headerTable = 'breeder_daily_reports';

  static const childTables = <String>[
    'breeder_bird_movements',
    'breeder_feed_entries',
    'breeder_egg_production_entries',
    'breeder_egg_inventory_movements',
  ];

  /// Report ids whose aggregate (header or any child row) is dirty and not
  /// currently in `Sync Conflict` — a conflicted report is excluded until a
  /// production manager resolves it; pushing it again would just be
  /// rejected a second time for the same reason.
  Future<List<String>> reportIdsNeedingPush() async {
    final db = await _dbHelper.db;
    final ids = <String>{};

    final headerRows = await db.query(
      headerTable,
      columns: const ['id'],
      where: "syncStatus IN ('pending', 'failed') AND state <> 'sync_conflict'",
    );
    ids.addAll(headerRows.map((row) => row['id']! as String));

    for (final table in childTables) {
      final rows = await db.rawQuery(
        'SELECT DISTINCT c.reportId AS reportId FROM $table c '
        'JOIN $headerTable h ON h.id = c.reportId '
        "WHERE c.syncStatus IN ('pending', 'failed') AND h.state <> 'sync_conflict'",
      );
      ids.addAll(rows.map((row) => row['reportId']! as String));
    }
    return ids.toList(growable: false);
  }

  /// Builds the full current snapshot for [reportId]: the header row plus
  /// EVERY current row (not just dirty ones) of its four child tables. Null
  /// if the header no longer exists. `cutoff` is captured at read time and
  /// reused by [markSynced] so a row edited concurrently, after this
  /// snapshot was read but before the push completed, is not incorrectly
  /// marked synced (the same cutoff-guarded pattern
  /// `PerformanceSyncRepository` uses for ordinary per-row pushes).
  Future<BreederReportAggregateSnapshot?> buildSnapshot(
    String reportId,
  ) async {
    final db = await _dbHelper.db;
    // Breeder repositories stamp dirtyAt/updatedAt with local time
    // (`_nowStamp` = `DateTime.now().toIso8601String()`, no `.toUtc()`) —
    // unlike `PerformanceSyncRepository`'s UTC cutoff. The cutoff here must
    // match that convention, or a row dirtied moments before this snapshot
    // was read could compare as "after" a UTC cutoff on a device west of
    // UTC and be skipped by markSynced's cutoff guard.
    final cutoff = DateTime.now().toIso8601String();
    final headerRows = await db.query(
      headerTable,
      where: 'id = ?',
      whereArgs: [reportId],
      limit: 1,
    );
    if (headerRows.isEmpty) return null;
    final header = Map<String, dynamic>.from(headerRows.first);

    final children = <String, List<Map<String, dynamic>>>{};
    for (final table in childTables) {
      final rows = await db.query(
        table,
        where: 'reportId = ?',
        whereArgs: [reportId],
      );
      children[table] = rows
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    }
    return BreederReportAggregateSnapshot(
      cutoff: cutoff,
      header: header,
      children: children,
    );
  }

  /// Marks the header and every child row captured in [snapshot] as synced,
  /// and records [syncToken] as the header's new `lastSyncedRevision`.
  /// [syncToken] is the cloud's `sync_token` value returned by
  /// `push_breeder_daily_report_aggregate` on success — a concurrency
  /// counter kept deliberately separate from the `revision` audit column
  /// (ticket 12). Cutoff-guarded exactly like
  /// `PerformanceSyncRepository.markRowsSynced`: a row edited again after
  /// [snapshot] was built keeps its `pending`/`failed` status so it is
  /// picked up by the next push instead of being silently marked synced
  /// with stale cloud contents.
  Future<void> markSynced(
    BreederReportAggregateSnapshot snapshot, {
    required int syncToken,
  }) async {
    final db = await _dbHelper.db;
    final now = DateTime.now().toIso8601String();
    final reportId = snapshot.header['id'] as String;
    await db.transaction((txn) async {
      await txn.update(
        headerTable,
        {
          'syncStatus': 'synced',
          'dirtyAt': null,
          'lastSyncedAt': now,
          'syncError': null,
          'lastSyncedRevision': syncToken,
        },
        where: 'id = ? AND (dirtyAt IS NULL OR dirtyAt <= ?)',
        whereArgs: [reportId, snapshot.cutoff],
      );
      for (final table in childTables) {
        final ids = (snapshot.children[table] ?? const [])
            .map((row) => row['id']?.toString())
            .whereType<String>()
            .toList(growable: false);
        if (ids.isEmpty) continue;
        final placeholders = List.filled(ids.length, '?').join(', ');
        await txn.update(
          table,
          {
            'syncStatus': 'synced',
            'dirtyAt': null,
            'lastSyncedAt': now,
            'syncError': null,
          },
          where: 'id IN ($placeholders) AND (dirtyAt IS NULL OR dirtyAt <= ?)',
          whereArgs: [...ids, snapshot.cutoff],
        );
      }
    });
  }

  /// Marks only the header as failed — mirroring
  /// `PerformanceSyncRepository.markRowsFailed`'s per-row failure marking,
  /// scoped to the one row this repository's callers key retries off of.
  /// Child rows keep whatever `syncStatus` they already had; they are
  /// bundled into this report's aggregate again on the next retry pass
  /// regardless, since [reportIdsNeedingPush]/[buildSnapshot] key off the
  /// header id, not per-child dirty status.
  Future<void> markFailed(String reportId, Object error) async {
    final db = await _dbHelper.db;
    await db.update(
      headerTable,
      {'syncStatus': 'failed', 'syncError': error.toString()},
      where: 'id = ?',
      whereArgs: [reportId],
    );
  }
}

class BreederReportAggregateSnapshot {
  const BreederReportAggregateSnapshot({
    required this.cutoff,
    required this.header,
    required this.children,
  });

  /// Local-time timestamp (matching the breeder repositories' own
  /// `dirtyAt`/`updatedAt` convention) captured when this snapshot was
  /// read; reused by [BreederReportAggregateRepository.markSynced] as the
  /// dirty-cutoff guard.
  final String cutoff;
  final Map<String, dynamic> header;
  final Map<String, List<Map<String, dynamic>>> children;

  int get rowCount =>
      1 + children.values.fold(0, (sum, rows) => sum + rows.length);
}
