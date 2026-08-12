import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../services/supabase/sync_meta.dart';
import '../database/database_helper.dart';

/// Generic offline-sync adapter for the operational table graph.
///
/// Domain repositories remain responsible for validation and business writes.
/// This adapter only exposes dirty rows, applies filtered cloud rows, and
/// updates device-local sync metadata in a dependency-safe table order.
///
/// The adapter began with performance monitoring and now also covers agent
/// data that depends on the customer/flock/hatchery master graph.
class PerformanceSyncRepository {
  PerformanceSyncRepository({DatabaseHelper? databaseHelper})
    : _databaseHelper = databaseHelper ?? DatabaseHelper();

  final DatabaseHelper _databaseHelper;

  /// dirtyAt cutoff per table, captured at the last getDirtyRows() call for
  /// that table (UTC); see markRowsSynced.
  final Map<String, String> _dirtyReadCutoffByTable = {};

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

  static const allPushTables = <String>[
    ...preFlockPushOrder,
    ...postFlockPushOrder,
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
    ...serverEvidencePullOrder,
    'agent_intake_sessions',
    'agent_intake_turns',
    'agent_intake_values',
  ]);

  static final List<String> deleteOrder = List<String>.unmodifiable(
    allPushTables.reversed,
  );

  static const immutableEvidenceTables = <String>{
    'broiler_daily_record_revisions',
    'broiler_daily_events',
    'daily_record_sources',
    'agent_tool_events',
  };

  static const _deviceOnlySourceColumns = <String>{
    'localPath',
    'uploadState',
    'uploadError',
  };

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
      where:
          'id IN ($placeholders) AND (dirtyAt IS NULL OR dirtyAt <= ?)',
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
    if (table == 'daily_record_sources') {
      prepared.removeWhere((key, _) => _deviceOnlySourceColumns.contains(key));
    }
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
    await db.update(table, row, where: 'id = ?', whereArgs: [row['id']]);
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
