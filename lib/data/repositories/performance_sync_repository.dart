import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/security/safe_debug_log.dart';
import '../../services/supabase/sync_meta.dart';
import '../database/database_helper.dart';

/// Generic offline-sync adapter for the operational table graph.
///
/// Domain repositories remain responsible for validation and business writes.
/// This adapter only exposes dirty rows, applies filtered cloud rows, and
/// updates device-local sync metadata in a dependency-safe table order.
class PerformanceSyncRepository {
  PerformanceSyncRepository({DatabaseHelper? databaseHelper})
    : _databaseHelper = databaseHelper ?? DatabaseHelper();

  final DatabaseHelper _databaseHelper;

  /// dirtyAt cutoff per table, captured at the last getDirtyRows() call for
  /// that table (UTC); see markRowsSynced.
  final Map<String, String> _dirtyReadCutoffByTable = {};

  static const preFlockPushOrder = <String>['customer_sectors'];

  // `houses` carries a FOREIGN KEY on flockId, so it must push after flocks.
  //
  // breeder-flock-performance ticket 15 adds `breeder_flock_milestones`,
  // `breeder_isolation_areas`, `breeder_weighing_sessions`/`_samples`,
  // `egg_batches`, and `egg_batch_house_sources` here — every breeder/egg
  // table whose FKs are satisfied once `flocks` and `houses` exist. The
  // four remaining child tables of the daily-report sync aggregate
  // (`breeder_bird_movements`, `breeder_feed_entries`,
  // `breeder_egg_production_entries`, `breeder_egg_inventory_movements`)
  // are deliberately absent from every list below — see
  // `breederAggregatePullOnly` and
  // `lib/services/breeder/breeder_report_sync_service.dart`'s doc comment
  // for why they push through a dedicated revision-guarded transaction
  // instead of this generic per-row path. `breeder_daily_reports` itself is
  // the fifth: also absent here for the same reason.
  //
  // Ticket 17 adds `breeder_performance_alerts` here for the same reason as
  // the ticket 15 tables above: it carries an optional FOREIGN KEY on
  // `houseId` (and a required one on `flockId`), so it must push after both
  // `flocks` and `houses` exist. Its `ruleId` FK points at
  // `breeder_alert_rules`, which needs no push-order entry at all — that
  // table is seeded reference data (see `breederReferencePullOnly` below),
  // identical on every device before either table's first row is ever
  // written, so there is no push-ordering hazard to protect against.
  static const postFlockPushOrder = <String>[
    'houses',
    'breeder_flock_milestones',
    'breeder_isolation_areas',
    'breeder_weighing_sessions',
    'breeder_weighing_samples',
    'egg_batches',
    'egg_batch_house_sources',
    'breeder_performance_alerts',
    'telegram_staff_links',
    'agent_settings',
    'agent_submissions',
    'agent_questions',
    'hatchery_draft_batches',
    'hatchery_draft_rows',
    'hatchery_agent_audit_events',
    'hatchery_daily_records',
    'agent_intake_sessions',
    'agent_intake_turns',
    'agent_intake_values',
  ];

  /// Pushed only after the daily-report sync aggregate (design section
  /// 13.1) has landed for this run, because every table here carries an FK
  /// that can point at a `breeder_daily_reports` or
  /// `breeder_egg_inventory_movements` row that only exists in the cloud
  /// once that push has succeeded: `breeder_report_revisions.reportId`,
  /// `egg_shipments.reportId`/`inventoryMovementId`/`reversalMovementId`.
  /// `breeder_report_revisions` is commercial audit history (ticket 12) and
  /// syncs normally, unlike its four aggregate-child siblings.
  static const postAggregatePushOrder = <String>[
    'breeder_report_revisions',
    'egg_shipments',
    'egg_shipment_batches',
    'egg_batch_receipts',
  ];

  static const allPushTables = <String>[
    ...preFlockPushOrder,
    ...postFlockPushOrder,
    ...postAggregatePushOrder,
  ];

  /// System-defined reference data (breeder-flock-performance tickets 03,
  /// 10, and 17): seeded locally, read-only client-side, and sync DOWN only —
  /// absent from every push list above by design, so `_assertPushTable`
  /// rejects any attempt to push them (design doc section 13: "Client roles
  /// cannot create, update, or delete published benchmark data").
  static const breederReferencePullOnly = <String>[
    'breeder_metric_definitions',
    'breeder_benchmark_profiles',
    'breeder_benchmark_values',
    'breeder_egg_grade_definitions',
    'breeder_alert_rules',
  ];

  /// The daily-report sync aggregate's header and four child tables (design
  /// section 13.1). Push travels through
  /// `BreederReportAggregateRepository`/`BreederReportSyncService`'s
  /// dedicated revision-guarded transaction, never this generic per-row
  /// path — deliberately absent from `allPushTables`. Pull still uses this
  /// generic per-row path: the race the design calls out ("a stale child
  /// could land after a winning header") is a push hazard specifically,
  /// since only a push can silently overwrite another device's already
  /// -accepted revision; applying an incoming row idempotently on the way
  /// down carries no such risk.
  static const breederAggregatePullOnly = <String>[
    'breeder_daily_reports',
    'breeder_bird_movements',
    'breeder_feed_entries',
    'breeder_egg_production_entries',
    'breeder_egg_inventory_movements',
  ];

  /// Conversation, tool-call, and visit evidence is authored by the Edge
  /// agent. The Flutter admin app may pull it for review but never pushes or
  /// tombstones it.
  static const serverEvidencePullOrder = <String>[
    'agent_conversations',
    'agent_conversation_turns',
    'agent_tool_events',
    'agent_intake_visits',
  ];

  static final List<String> allPullTables = List<String>.unmodifiable([
    ...allPushTables.where(
      (table) =>
          table != 'agent_intake_sessions' &&
          table != 'agent_intake_turns' &&
          table != 'agent_intake_values',
    ),
    ...breederReferencePullOnly,
    ...breederAggregatePullOnly,
    ...serverEvidencePullOrder,
    'agent_intake_sessions',
    'agent_intake_turns',
    'agent_intake_values',
  ]);

  static final List<String> deleteOrder = List<String>.unmodifiable(
    allPushTables.reversed,
  );

  static const immutableEvidenceTables = <String>{'agent_tool_events'};

  static const _jsonColumnsByTable = <String, Set<String>>{
    'agent_conversations': {'pendingActionJson'},
    'agent_conversation_turns': {'attachmentJson'},
    'agent_tool_events': {'argumentsJson', 'resultJson'},
    'agent_intake_sessions': {
      'workingValuesJson',
      'pendingClarificationJson',
      'summarySnapshotJson',
    },
    'agent_intake_values': {'valueJson'},
  };

  Future<List<Map<String, dynamic>>> getDirtyRows(String table) async {
    _assertPushTable(table);
    final db = await _databaseHelper.db;
    _dirtyReadCutoffByTable[table] = DateTime.now().toUtc().toIso8601String();
    final rows = await db.query(
      table,
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'dirtyAt ASC, id ASC',
    );
    return rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> getRowById(String table, String id) async {
    _assertPullTable(table);
    final db = await _databaseHelper.db;
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<void> upsertRemoteRow(
    String table,
    Map<String, dynamic> remoteRow,
  ) async {
    _assertPullTable(table);
    final db = await _databaseHelper.db;
    final columns = await _tableColumns(db, table);
    final normalized = _filterColumns(
      _normalizeRemoteRow(table, remoteRow),
      columns,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final synced = <String, dynamic>{
      ...normalized,
      'syncStatus': 'synced',
      'dirtyAt': null,
      'lastSyncedAt': now,
      'syncError': null,
    };
    final filtered = _filterColumns(synced, columns);
    if (immutableEvidenceTables.contains(table)) {
      await db.insert(
        table,
        filtered,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return;
    }
    await _upsertById(db, table, filtered);
  }

  Future<void> markRowsSynced(String table, Iterable<String> ids) async {
    _assertPushTable(table);
    final uniqueIds = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (uniqueIds.isEmpty) return;
    final db = await _databaseHelper.db;
    final cutoff =
        _dirtyReadCutoffByTable[table] ??
        DateTime.now().toUtc().toIso8601String();
    final placeholders = List.filled(uniqueIds.length, '?').join(', ');
    await db.update(
      table,
      {
        'syncStatus': 'synced',
        'dirtyAt': null,
        'lastSyncedAt': DateTime.now().toUtc().toIso8601String(),
        'syncError': null,
      },
      where: 'id IN ($placeholders) AND (dirtyAt IS NULL OR dirtyAt <= ?)',
      whereArgs: [...uniqueIds, cutoff],
    );
  }

  Future<void> markRowsFailed(
    String table,
    Iterable<String> ids,
    Object error,
  ) {
    return _markRows(table, ids, {
      'syncStatus': 'failed',
      'dirtyAt': DateTime.now().toUtc().toIso8601String(),
      'syncError': error.toString(),
    });
  }

  Map<String, dynamic> prepareRemoteRow(
    String table,
    Map<String, dynamic> row,
  ) {
    _assertPushTable(table);
    final prepared = stripSyncMeta(row);
    for (final column in _jsonColumnsByTable[table] ?? const <String>{}) {
      final value = prepared[column];
      if (value is! String) continue;
      try {
        prepared[column] = jsonDecode(value);
      } on FormatException {
        // Preserve malformed evidence for server-side validation and review.
      }
    }
    return prepared;
  }

  Future<bool> isEquivalentRemoteRow(
    String table,
    Map<String, dynamic> localRow,
    Map<String, dynamic> remoteRow,
  ) async {
    _assertPullTable(table);
    final db = await _databaseHelper.db;
    final columns = await _tableColumns(db, table);
    final local = _businessColumns(
      table,
      _filterColumns(Map<String, dynamic>.from(localRow), columns),
    );
    final remote = _businessColumns(
      table,
      _filterColumns(_normalizeRemoteRow(table, remoteRow), columns),
    );
    final keys = <String>{...local.keys, ...remote.keys};
    for (final key in keys) {
      if (!_equivalentValue(local[key], remote[key])) return false;
    }
    return true;
  }

  Future<void> _markRows(
    String table,
    Iterable<String> ids,
    Map<String, Object?> changes,
  ) async {
    _assertPushTable(table);
    final uniqueIds = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (uniqueIds.isEmpty) return;
    final db = await _databaseHelper.db;
    final placeholders = List.filled(uniqueIds.length, '?').join(', ');
    await db.update(
      table,
      changes,
      where: 'id IN ($placeholders)',
      whereArgs: uniqueIds,
    );
  }

  Map<String, dynamic> _businessColumns(
    String table,
    Map<String, dynamic> row,
  ) {
    final copy = Map<String, dynamic>.from(row);
    copy.removeWhere((key, _) => kSyncMetaColumns.contains(key));
    return copy;
  }

  bool _equivalentValue(Object? left, Object? right) {
    if (left == right) return true;
    if (left is num && right is num) return left.toDouble() == right.toDouble();
    final leftDate = left == null ? null : DateTime.tryParse(left.toString());
    final rightDate = right == null
        ? null
        : DateTime.tryParse(right.toString());
    if (leftDate != null && rightDate != null) {
      return leftDate.toUtc() == rightDate.toUtc();
    }
    return false;
  }

  Map<String, dynamic> _normalizeRemoteRow(
    String table,
    Map<String, dynamic> row,
  ) {
    final normalized = row.map((key, value) => MapEntry(_camelize(key), value));
    for (final column in _jsonColumnsByTable[table] ?? const <String>{}) {
      final value = normalized[column];
      if (value != null && value is! String) {
        normalized[column] = jsonEncode(value);
      }
    }
    return normalized;
  }

  String _camelize(String key) {
    if (!key.contains('_')) return key;
    final parts = key.split('_');
    return parts.first +
        parts.skip(1).map((part) {
          if (part.isEmpty) return part;
          return part[0].toUpperCase() + part.substring(1);
        }).join();
  }

  Future<Set<String>> _tableColumns(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name']! as String).toSet();
  }

  Map<String, dynamic> _filterColumns(
    Map<String, dynamic> row,
    Set<String> columns,
  ) {
    return Map<String, dynamic>.fromEntries(
      row.entries.where((entry) => columns.contains(entry.key)),
    );
  }

  Future<void> _upsertById(
    Database db,
    String table,
    Map<String, dynamic> row,
  ) async {
    final inserted = await db.insert(
      table,
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (inserted != 0) return;
    final updated = await db.update(
      table,
      row,
      where: 'id = ?',
      whereArgs: [row['id']],
    );
    if (updated != 0) return;
    // Neither branch touched a row: `INSERT OR IGNORE` swallowed a NOT NULL,
    // UNIQUE or CHECK violation (it does not swallow foreign-key errors), so
    // the row does not exist and never will. Silence here is what let an
    // app-channel staff link vanish locally while its child rows kept failing
    // their foreign key on every sync.
    safeDebugLog(
      'Supabase pull dropped $table row ${row['id']}: local schema rejected it',
    );
  }

  void _assertPushTable(String table) {
    if (!allPushTables.contains(table)) {
      throw ArgumentError.value(table, 'table', 'Unsupported push table');
    }
  }

  void _assertPullTable(String table) {
    if (!allPullTables.contains(table)) {
      throw ArgumentError.value(table, 'table', 'Unsupported pull table');
    }
  }
}
