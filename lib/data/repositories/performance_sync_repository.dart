import 'package:sqflite/sqflite.dart';

import '../../services/supabase/sync_meta.dart';
import '../database/database_helper.dart';

/// Generic offline-sync adapter for the performance-monitoring table graph.
///
/// Domain repositories remain responsible for validation and business writes.
/// This adapter only exposes dirty rows, applies filtered cloud rows, and
/// updates device-local sync metadata in a dependency-safe table order.
class PerformanceSyncRepository {
  PerformanceSyncRepository({DatabaseHelper? databaseHelper})
    : _databaseHelper = databaseHelper ?? DatabaseHelper();

  final DatabaseHelper _databaseHelper;

  static const preFlockPushOrder = <String>[
    'customer_sectors',
    'farms',
    'houses',
    'broiler_target_profiles',
    'broiler_target_rows',
  ];

  static const postFlockPushOrder = <String>[
    'flock_placements',
    'broiler_daily_records',
    'broiler_daily_record_revisions',
    'broiler_daily_events',
    'daily_record_sources',
    'performance_alert_rules',
    'performance_concerns',
    'farm_visit_sessions',
    'farm_visit_houses',
    'visit_investigations',
    'visit_findings',
    'cause_assessments',
    'corrective_actions',
    'action_kpi_evaluations',
  ];

  static const allPushTables = <String>[
    ...preFlockPushOrder,
    ...postFlockPushOrder,
  ];

  static final List<String> deleteOrder = List<String>.unmodifiable(
    allPushTables.reversed,
  );

  static const immutableEvidenceTables = <String>{
    'broiler_daily_record_revisions',
    'broiler_daily_events',
    'daily_record_sources',
  };

  static const _deviceOnlySourceColumns = <String>{
    'localPath',
    'uploadState',
    'uploadError',
  };

  Future<List<Map<String, dynamic>>> getDirtyRows(String table) async {
    _assertTable(table);
    final db = await _databaseHelper.db;
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
    _assertTable(table);
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
    _assertTable(table);
    final db = await _databaseHelper.db;
    final columns = await _tableColumns(db, table);
    final normalized = _filterColumns(_normalizeRemoteRow(remoteRow), columns);
    final now = DateTime.now().toUtc().toIso8601String();
    final synced = <String, dynamic>{
      ...normalized,
      'syncStatus': 'synced',
      'dirtyAt': null,
      'lastSyncedAt': now,
      'syncError': null,
    };
    await _upsertById(db, table, _filterColumns(synced, columns));
  }

  Future<void> markRowsSynced(String table, Iterable<String> ids) {
    return _markRows(table, ids, {
      'syncStatus': 'synced',
      'dirtyAt': null,
      'lastSyncedAt': DateTime.now().toUtc().toIso8601String(),
      'syncError': null,
    });
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
    _assertTable(table);
    final prepared = stripSyncMeta(row);
    if (table == 'daily_record_sources') {
      prepared.removeWhere((key, _) => _deviceOnlySourceColumns.contains(key));
    }
    return prepared;
  }

  Future<bool> isEquivalentRemoteRow(
    String table,
    Map<String, dynamic> localRow,
    Map<String, dynamic> remoteRow,
  ) async {
    _assertTable(table);
    final db = await _databaseHelper.db;
    final columns = await _tableColumns(db, table);
    final local = _businessColumns(
      table,
      _filterColumns(Map<String, dynamic>.from(localRow), columns),
    );
    final remote = _businessColumns(
      table,
      _filterColumns(_normalizeRemoteRow(remoteRow), columns),
    );
    final keys = <String>{...local.keys, ...remote.keys};
    for (final key in keys) {
      if (!_equivalentValue(local[key], remote[key])) return false;
    }
    return true;
  }

  Future<String?> customerIdForSource(String sourceId) async {
    final db = await _databaseHelper.db;
    final rows = await db.rawQuery(
      '''
      SELECT f.customerId
      FROM daily_record_sources s
      INNER JOIN broiler_daily_record_revisions revision
        ON revision.id = s.revisionId
      INNER JOIN broiler_daily_records record
        ON record.id = revision.recordId
      INNER JOIN flock_placements placement
        ON placement.id = record.placementId
      INNER JOIN flocks f ON f.id = placement.flockId
      WHERE s.id = ?
      LIMIT 1
      ''',
      [sourceId],
    );
    return rows.isEmpty ? null : rows.first['customerId']?.toString();
  }

  Future<void> updateSourceUpload({
    required String sourceId,
    required String remoteStoragePath,
  }) async {
    final db = await _databaseHelper.db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'daily_record_sources',
      {
        'remoteStoragePath': remoteStoragePath,
        'uploadState': 'synced',
        'uploadError': null,
        'updatedAt': now,
        'dirtyAt': now,
        'syncStatus': 'pending',
        'syncError': null,
      },
      where: 'id = ?',
      whereArgs: [sourceId],
    );
  }

  Future<void> markSourceUploadFailed(String sourceId, Object error) async {
    final db = await _databaseHelper.db;
    await db.update(
      'daily_record_sources',
      {
        'uploadState': 'failed',
        'uploadError': error.toString(),
        'syncStatus': 'failed',
        'syncError': error.toString(),
      },
      where: 'id = ?',
      whereArgs: [sourceId],
    );
  }

  Future<void> _markRows(
    String table,
    Iterable<String> ids,
    Map<String, Object?> changes,
  ) async {
    _assertTable(table);
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
    copy.removeWhere(
      (key, _) =>
          kSyncMetaColumns.contains(key) ||
          (table == 'daily_record_sources' &&
              _deviceOnlySourceColumns.contains(key)),
    );
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

  Map<String, dynamic> _normalizeRemoteRow(Map<String, dynamic> row) {
    return row.map((key, value) => MapEntry(_camelize(key), value));
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
    await db.update(table, row, where: 'id = ?', whereArgs: [row['id']]);
  }

  void _assertTable(String table) {
    if (!allPushTables.contains(table)) {
      throw ArgumentError.value(table, 'table', 'Unsupported sync table');
    }
  }
}
