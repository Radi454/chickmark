import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/audit_session_model.dart';
import '../models/panel_sample_schema.dart';
import 'sync_tombstone_repository.dart';

class AuditSessionRepository {
  final DatabaseHelper _dbHelper;

  AuditSessionRepository({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  Future<void> insertSession(AuditSessionModel session) async {
    await _dbHelper.assertForeignKeys(
      customerId: session.customerId,
      flockId: session.flockId,
      hatcheryId: session.hatcheryId,
    );
    final db = await _dbHelper.db;
    await _upsertById(db, 'audit_sessions', _stampDirty(session.toMap()));
  }

  Future<void> updateSession(AuditSessionModel session) async {
    final db = await _dbHelper.db;
    await db.update(
      'audit_sessions',
      _stampDirty(session.toMap()),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  Future<void> deleteSession(String id) async {
    final db = await _dbHelper.db;
    await db.transaction<void>((txn) async {
      for (final panel in PanelSampleSchema.panels) {
        final rows = await txn.query(
          panel.tableName,
          columns: ['id'],
          where: 'sessionId = ?',
          whereArgs: [id],
        );
        await SyncTombstoneRepository.queueDeletesWithExecutor(
          txn,
          panel.tableName,
          rows.map((row) => row['id']),
        );
        await txn.delete(
          panel.tableName,
          where: 'sessionId = ?',
          whereArgs: [id],
        );
      }
      final photoRows = await txn.query(
        'photos',
        columns: ['id'],
        where: 'sessionId = ?',
        whereArgs: [id],
      );
      await SyncTombstoneRepository.queueDeletesWithExecutor(
        txn,
        'photos',
        photoRows.map((row) => row['id']),
      );
      await txn.delete('photos', where: 'sessionId = ?', whereArgs: [id]);
      await SyncTombstoneRepository.queueDeleteWithExecutor(
        txn,
        'audit_sessions',
        id,
      );
      await txn.delete('audit_sessions', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<AuditSessionModel?> getSessionById(String id) async {
    final db = await _dbHelper.db;
    final result = await db.query(
      'audit_sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return AuditSessionModel.fromMap(result.first);
  }

  Future<List<AuditSessionModel>> getSessionsByCustomer(
    String customerId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _dbHelper.db;
    final result = await db.query(
      'audit_sessions',
      where: 'customerId = ?',
      whereArgs: [customerId],
      orderBy: 'date DESC, createdAt DESC',
      limit: limit,
      offset: offset,
    );
    return result.map(AuditSessionModel.fromMap).toList();
  }

  Future<List<AuditSessionModel>> getSessionsByFlock(
    String flockId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _dbHelper.db;
    final result = await db.query(
      'audit_sessions',
      where: 'flockId = ?',
      whereArgs: [flockId],
      orderBy: 'date DESC, createdAt DESC',
      limit: limit,
      offset: offset,
    );
    return result.map(AuditSessionModel.fromMap).toList();
  }

  Future<List<AuditSessionModel>> getSessionsByStatus(
    String status, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _dbHelper.db;
    final result = await db.query(
      'audit_sessions',
      where: 'status = ?',
      whereArgs: [status],
      orderBy: 'date DESC, createdAt DESC',
      limit: limit,
      offset: offset,
    );
    return result.map(AuditSessionModel.fromMap).toList();
  }

  Future<List<AuditSessionModel>> getInProgressSessions() async {
    final db = await _dbHelper.db;
    final result = await db.query(
      'audit_sessions',
      where: 'status = ?',
      whereArgs: ['in_progress'],
      orderBy: 'updatedAt DESC',
    );
    return result.map(AuditSessionModel.fromMap).toList();
  }

  Future<AuditSessionModel?> findInProgressSession({
    required String customerId,
    required String flockId,
    required String hatcheryId,
    required DateTime date,
  }) async {
    final db = await _dbHelper.db;
    final day = date.toIso8601String().split('T').first;
    final result = await db.query(
      'audit_sessions',
      where:
          'customerId = ? AND flockId = ? AND hatcheryId = ? AND status = ? AND substr(date, 1, 10) = ?',
      whereArgs: [customerId, flockId, hatcheryId, 'in_progress', day],
      orderBy: 'updatedAt DESC, createdAt DESC',
      limit: 1,
    );
    if (result.isEmpty) return null;
    return AuditSessionModel.fromMap(result.first);
  }

  Future<List<AuditSessionModel>> getCompletedSessions({
    String? customerId,
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _dbHelper.db;
    final whereParts = <String>['status = ?'];
    final args = <Object?>['completed'];
    if (customerId != null) {
      whereParts.add('customerId = ?');
      args.add(customerId);
    }
    final result = await db.query(
      'audit_sessions',
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: 'completedAt DESC, date DESC',
      limit: limit,
      offset: offset,
    );
    return result.map(AuditSessionModel.fromMap).toList();
  }

  Future<void> markStationCompleted(String sessionId, String stationKey) async {
    final db = await _dbHelper.db;
    final current = await getSessionById(sessionId);
    if (current == null) return;
    final selectedStations = normalizeStationKeys(current.selectedStationKeys);
    final updated = List<String>.from(current.stationsCompleted);
    if (!updated.contains(stationKey) &&
        selectedStations.contains(stationKey)) {
      updated.add(stationKey);
    }
    final validCompleted = _validCompletedStations(updated, selectedStations);
    final isComplete = _isComplete(validCompleted, selectedStations);
    final now = DateTime.now();
    final completedAt = isComplete
        ? current.completedAt?.toIso8601String() ?? now.toIso8601String()
        : null;
    await db.update(
      'audit_sessions',
      {
        'stationsCompleted': validCompleted.isEmpty
            ? null
            : jsonEncode(validCompleted),
        'updatedAt': now.toIso8601String(),
        'status': isComplete ? 'completed' : 'in_progress',
        'completedAt': completedAt,
        'syncStatus': 'pending',
        'dirtyAt': now.toIso8601String(),
        'syncError': null,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> updateSelectedStationKeys(
    String sessionId,
    List<String> selectedStationKeys,
  ) async {
    final db = await _dbHelper.db;
    final current = await getSessionById(sessionId);
    if (current == null) return;
    final selected = normalizeStationKeys(selectedStationKeys);
    final completed = current.stationsCompleted
        .where((stationKey) => selected.contains(stationKey))
        .toList(growable: false);
    final isComplete = _isComplete(completed, selected);
    final now = DateTime.now();
    final completedAt = isComplete
        ? current.completedAt?.toIso8601String() ?? now.toIso8601String()
        : null;
    await db.update(
      'audit_sessions',
      {
        'selectedStationKeys': jsonEncode(selected),
        'stationsCompleted': completed.isEmpty ? null : jsonEncode(completed),
        'updatedAt': now.toIso8601String(),
        'status': isComplete ? 'completed' : 'in_progress',
        'completedAt': completedAt,
        'syncStatus': 'pending',
        'dirtyAt': now.toIso8601String(),
        'syncError': null,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> updateSessionProgress(
    String sessionId,
    List<String> stationsCompleted,
  ) async {
    final db = await _dbHelper.db;
    final current = await getSessionById(sessionId);
    final selectedStations = normalizeStationKeys(current?.selectedStationKeys);
    final validStations = _validCompletedStations(
      stationsCompleted,
      selectedStations,
    );
    final isComplete = _isComplete(validStations, selectedStations);
    final now = DateTime.now();
    final completedAt = isComplete
        ? current?.completedAt?.toIso8601String() ?? now.toIso8601String()
        : null;
    await db.update(
      'audit_sessions',
      {
        'stationsCompleted': validStations.isEmpty
            ? null
            : jsonEncode(validStations),
        'updatedAt': now.toIso8601String(),
        'status': isComplete ? 'completed' : 'in_progress',
        'completedAt': completedAt,
        'syncStatus': 'pending',
        'dirtyAt': now.toIso8601String(),
        'syncError': null,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<List<AuditSessionModel>> getSessionsByDateRange(
    String dateFrom,
    String dateTo, {
    String? customerId,
    int limit = 50,
  }) async {
    final db = await _dbHelper.db;
    final whereParts = <String>['date >= ?', 'date <= ?'];
    final args = <Object?>[dateFrom, dateTo];
    if (customerId != null) {
      whereParts.add('customerId = ?');
      args.add(customerId);
    }
    final result = await db.query(
      'audit_sessions',
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC, createdAt DESC',
      limit: limit,
    );
    return result.map(AuditSessionModel.fromMap).toList();
  }

  Future<List<AuditSessionModel>> getAllSessions({
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _dbHelper.db;
    final result = await db.query(
      'audit_sessions',
      orderBy: 'date DESC, createdAt DESC',
      limit: limit,
      offset: offset,
    );
    return result.map(AuditSessionModel.fromMap).toList();
  }

  /// Sync-pull write: data coming from Supabase is, by definition, in sync with
  /// the cloud, so mark it synced rather than dirty. Only reached when the
  /// conflict check decided the remote row wins (a newer local edit short
  /// circuits before here, preserving its pending state).
  Future<void> upsertSessionRow(Map<String, dynamic> row) async {
    final db = await _dbHelper.db;
    final normalized = _markRowSynced(_normalize(row));
    await _upsertById(db, 'audit_sessions', normalized);
  }

  /// Sessions awaiting a push (locally edited or last push failed).
  Future<List<AuditSessionModel>> getDirtySessionRows() async {
    final db = await _dbHelper.db;
    final result = await db.query(
      'audit_sessions',
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'dirtyAt ASC',
    );
    return result.map(AuditSessionModel.fromMap).toList();
  }

  Future<void> markSessionsSynced(Iterable<String> ids) async {
    final idList = ids.toList(growable: false);
    if (idList.isEmpty) return;
    final db = await _dbHelper.db;
    final placeholders = List.filled(idList.length, '?').join(', ');
    await db.update(
      'audit_sessions',
      {
        'syncStatus': 'synced',
        'lastSyncedAt': DateTime.now().toIso8601String(),
        'dirtyAt': null,
        'syncError': null,
      },
      where: 'id IN ($placeholders)',
      whereArgs: idList,
    );
  }

  Future<void> markSessionsFailed(Iterable<String> ids, Object error) async {
    final idList = ids.toList(growable: false);
    if (idList.isEmpty) return;
    final db = await _dbHelper.db;
    final placeholders = List.filled(idList.length, '?').join(', ');
    await db.update(
      'audit_sessions',
      {'syncStatus': 'failed', 'syncError': error.toString()},
      where: 'id IN ($placeholders)',
      whereArgs: idList,
    );
  }

  /// Paged session query for the Audits management screen. SQL filters status /
  /// date / customer / flock; free-text search and sync-status filtering are
  /// applied in Dart on the loaded page (sync status depends on panel rows).
  Future<List<AuditSessionModel>> querySessions({
    List<String>? statuses,
    String? dateFrom,
    String? dateTo,
    String? customerId,
    String? flockId,
    int limit = 30,
    int offset = 0,
  }) async {
    final db = await _dbHelper.db;
    final where = <String>[];
    final args = <Object?>[];
    if (statuses != null && statuses.isNotEmpty) {
      where.add('status IN (${List.filled(statuses.length, '?').join(', ')})');
      args.addAll(statuses);
    }
    if (dateFrom != null) {
      where.add('substr(date, 1, 10) >= ?');
      args.add(dateFrom);
    }
    if (dateTo != null) {
      where.add('substr(date, 1, 10) <= ?');
      args.add(dateTo);
    }
    if (customerId != null) {
      where.add('customerId = ?');
      args.add(customerId);
    }
    if (flockId != null) {
      where.add('flockId = ?');
      args.add(flockId);
    }
    final result = await db.query(
      'audit_sessions',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date DESC, createdAt DESC',
      limit: limit,
      offset: offset,
    );
    return result.map(AuditSessionModel.fromMap).toList();
  }

  Map<String, dynamic> _stampDirty(Map<String, dynamic> row) {
    return {
      ...row,
      'syncStatus': 'pending',
      'dirtyAt': DateTime.now().toIso8601String(),
      'syncError': null,
    };
  }

  Map<String, dynamic> _markRowSynced(Map<String, dynamic> row) {
    return {
      ...row,
      'syncStatus': 'synced',
      'lastSyncedAt': DateTime.now().toIso8601String(),
      'dirtyAt': null,
      'syncError': null,
    };
  }

  Future<Map<String, dynamic>?> getSessionRowById(String id) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'audit_sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
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

  List<String> _validCompletedStations(
    List<String> completed,
    List<String> selectedStations,
  ) {
    final valid = <String>[];
    for (final station in completed) {
      if (!selectedStations.contains(station) || valid.contains(station)) {
        continue;
      }
      valid.add(station);
    }
    return valid;
  }

  bool _isComplete(List<String> completed, List<String> selectedStations) {
    return selectedStations.every(completed.contains);
  }

  Map<String, dynamic> _normalize(Map<String, dynamic> row) {
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
}
