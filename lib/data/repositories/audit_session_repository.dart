import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/audit_session_model.dart';

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
    await db.insert(
      'audit_sessions',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
    await db.delete('audit_sessions', where: 'id = ?', whereArgs: [id]);
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
    final updated = List<String>.from(current.stationsCompleted);
    if (!updated.contains(stationKey) &&
        supportedStationKeys.contains(stationKey)) {
      updated.add(stationKey);
    }
    final isComplete = updated.length == supportedStationKeys.length;
    await db.update(
      'audit_sessions',
      {
        'stationsCompleted': updated.isEmpty ? null : jsonEncode(updated),
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
    final validStations = stationsCompleted
        .where((s) => supportedStationKeys.contains(s))
        .toList();
    final isComplete = validStations.length == supportedStationKeys.length;
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
    await db.insert(
      'audit_sessions',
      normalized,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
