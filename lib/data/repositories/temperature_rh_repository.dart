import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/temperature_rh_model.dart';

class TemperatureRhRepository {
  final DatabaseHelper dbHelper = DatabaseHelper();

  Future<void> upsertSession(TemperatureSessionModel session) async {
    final db = await dbHelper.db;
    await db.insert(
      'temperature_sessions',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertSessionRow(Map<String, dynamic> row) async {
    final db = await dbHelper.db;
    await db.insert(
      'temperature_sessions',
      _normalize(row),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertReading(TemperatureReadingModel reading) async {
    final db = await dbHelper.db;
    await db.insert(
      'temperature_readings',
      reading.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertReadingRow(Map<String, dynamic> row) async {
    final db = await dbHelper.db;
    await db.insert(
      'temperature_readings',
      _normalize(row),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertReadings(List<TemperatureReadingModel> readings) async {
    if (readings.isEmpty) return;
    final db = await dbHelper.db;
    final batch = db.batch();
    for (final reading in readings) {
      batch.insert(
        'temperature_readings',
        reading.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<TemperatureReadingModel>> getRecentReadings(
    String sessionId, {
    int limit = 300,
  }) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'temperature_readings',
      where: 'sessionId = ?',
      whereArgs: [sessionId],
      orderBy: 'recordedAt DESC',
      limit: limit,
    );
    return rows.reversed.map(TemperatureReadingModel.fromMap).toList();
  }

  Future<List<TemperatureReadingModel>> getReadingsForSession(
    String sessionId,
  ) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'temperature_readings',
      where: 'sessionId = ?',
      whereArgs: [sessionId],
      orderBy: 'recordedAt ASC',
    );
    return rows.map(TemperatureReadingModel.fromMap).toList();
  }

  Future<List<TemperatureReadingModel>> getReadingsForSessions(
    List<String> sessionIds,
  ) async {
    if (sessionIds.isEmpty) return const [];
    final db = await dbHelper.db;
    final placeholders = List.filled(sessionIds.length, '?').join(',');
    final rows = await db.query(
      'temperature_readings',
      where: 'sessionId IN ($placeholders)',
      whereArgs: sessionIds,
      orderBy: 'recordedAt ASC',
    );
    return rows.map(TemperatureReadingModel.fromMap).toList();
  }

  Future<List<TemperatureSessionModel>> getSessionsByHatchery(
    String hatcheryId, {
    int limit = 50,
  }) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'temperature_sessions',
      where: 'hatcheryId = ?',
      whereArgs: [hatcheryId],
      orderBy: 'startedAt DESC',
      limit: limit,
    );
    return rows.map(TemperatureSessionModel.fromMap).toList();
  }

  Future<List<TemperatureSessionModel>> getCompletedSessionsByHatchery(
    String hatcheryId, {
    int limit = 50,
  }) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'temperature_sessions',
      where: 'hatcheryId = ? AND status != ?',
      whereArgs: [hatcheryId, 'active'],
      orderBy: 'startedAt DESC',
      limit: limit,
    );
    return rows.map(TemperatureSessionModel.fromMap).toList();
  }

  Future<List<TemperatureSessionModel>> getAllSessions() async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'temperature_sessions',
      orderBy: 'startedAt DESC',
    );
    return rows.map(TemperatureSessionModel.fromMap).toList();
  }

  Future<List<TemperatureSessionModel>> getSessionsByAuditSession(
    String auditSessionId,
  ) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'temperature_sessions',
      where: 'auditSessionId = ?',
      whereArgs: [auditSessionId],
      orderBy: 'startedAt ASC',
    );
    return rows.map(TemperatureSessionModel.fromMap).toList();
  }

  Future<List<TemperatureSessionModel>> getCompletedSummariesByAuditSession(
    String auditSessionId,
  ) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'temperature_sessions',
      where: 'auditSessionId = ? AND status = ?',
      whereArgs: [auditSessionId, 'completed'],
      orderBy: 'startedAt ASC',
    );
    return rows.map(TemperatureSessionModel.fromMap).toList();
  }

  Future<TemperatureSessionModel?> getSessionById(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'temperature_sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return TemperatureSessionModel.fromMap(rows.first);
  }

  Future<List<TemperatureSessionModel>> getSessionsByPlace(
    TemperaturePlace place, {
    int limit = 50,
  }) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'temperature_sessions',
      where: 'activePlace = ?',
      whereArgs: [place.name],
      orderBy: 'startedAt DESC',
      limit: limit,
    );
    return rows.map(TemperatureSessionModel.fromMap).toList();
  }

  Future<List<TemperatureSessionModel>> getCompletedSessionsByPlace(
    TemperaturePlace place, {
    int limit = 50,
  }) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'temperature_sessions',
      where: 'activePlace = ? AND status != ?',
      whereArgs: [place.name, 'active'],
      orderBy: 'startedAt DESC',
      limit: limit,
    );
    return rows.map(TemperatureSessionModel.fromMap).toList();
  }

  Future<void> persistSessionSummary(TemperatureSessionModel session) async {
    await upsertSession(session);
  }

  Future<void> bulkUpsertSessions(
    List<TemperatureSessionModel> sessions,
  ) async {
    if (sessions.isEmpty) return;
    final db = await dbHelper.db;
    final batch = db.batch();
    for (final session in sessions) {
      batch.insert(
        'temperature_sessions',
        session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteSession(String id) async {
    final db = await dbHelper.db;
    await db.transaction((txn) async {
      await txn.delete(
        'temperature_readings',
        where: 'sessionId = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'temperature_sessions',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<TemperatureReadingModel>> getAllReadings() async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'temperature_readings',
      orderBy: 'recordedAt ASC',
    );
    return rows.map(TemperatureReadingModel.fromMap).toList();
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
