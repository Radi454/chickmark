import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/audit_session_model.dart';
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
    await _upsertById(db, 'audit_sessions', session.toMap());
  }

  Future<void> updateSession(AuditSessionModel session) async {
    final db = await _dbHelper.db;
    await db.update(
      'audit_sessions',
      session.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  Future<void> deleteSession(String id) async {
    final db = await _dbHelper.db;
    await db.transaction<void>((txn) async {
      final sampleRows = await txn.query(
        'sample_records',
        columns: ['id'],
        where: 'auditSessionId = ?',
        whereArgs: [id],
      );
      final sampleIds = sampleRows
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .toList();
      for (final detailTable in const [
        'sample_house_details',
        'sample_machine_details',
        'sample_batch_details',
        'sample_timing_details',
      ]) {
        await SyncTombstoneRepository.queueDeletesWithExecutor(
          txn,
          detailTable,
          sampleIds,
        );
      }
      await SyncTombstoneRepository.queueDeletesWithExecutor(
        txn,
        'sample_records',
        sampleIds,
      );

      final auditRows = await txn.query(
        'audits',
        columns: ['id'],
        where: 'sessionId = ?',
        whereArgs: [id],
      );
      final auditIds = auditRows
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .toList();
      if (auditIds.isNotEmpty) {
        final placeholders = List.filled(auditIds.length, '?').join(',');
        final photoRows = await txn.query(
          'photos',
          columns: ['id'],
          where: 'auditId IN ($placeholders)',
          whereArgs: auditIds,
        );
        await SyncTombstoneRepository.queueDeletesWithExecutor(
          txn,
          'photos',
          photoRows.map((row) => row['id']),
        );
        await SyncTombstoneRepository.queueDeletesWithExecutor(
          txn,
          'audits',
          auditIds,
        );
      }
      await SyncTombstoneRepository.queueDeleteWithExecutor(
        txn,
        'audit_sessions',
        id,
      );
      await txn.update(
        'audits',
        {'sessionId': null},
        where: 'sessionId = ?',
        whereArgs: [id],
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
    await db.update(
      'audit_sessions',
      {
        'stationsCompleted': validCompleted.isEmpty
            ? null
            : jsonEncode(validCompleted),
        'updatedAt': DateTime.now().toIso8601String(),
        'status': isComplete ? 'completed' : 'in_progress',
        'completedAt': isComplete ? DateTime.now().toIso8601String() : null,
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
    await db.update(
      'audit_sessions',
      {
        'stationsCompleted': validStations.isEmpty
            ? null
            : jsonEncode(validStations),
        'updatedAt': DateTime.now().toIso8601String(),
        'status': isComplete ? 'completed' : 'in_progress',
        'completedAt': isComplete ? DateTime.now().toIso8601String() : null,
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

  Future<void> upsertSessionRow(Map<String, dynamic> row) async {
    final db = await _dbHelper.db;
    final normalized = _normalize(row);
    await _upsertById(db, 'audit_sessions', normalized);
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
