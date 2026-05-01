import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/station_sample_model.dart';

class StationSampleRepository {
  final DatabaseHelper _dbHelper;

  StationSampleRepository({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  Future<void> upsertSample(StationSampleModel sample) async {
    final db = await _dbHelper.db;
    await db.insert(
      'station_samples',
      sample.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<StationSampleModel?> getSampleById(String id) async {
    final db = await _dbHelper.db;
    final result = await db.query(
      'station_samples',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return StationSampleModel.fromMap(result.first);
  }

  Future<List<StationSampleModel>> getSamplesBySessionId(
    String auditSessionId,
  ) async {
    final db = await _dbHelper.db;
    final result = await db.query(
      'station_samples',
      where: 'auditSessionId = ?',
      whereArgs: [auditSessionId],
      orderBy: 'stationType ASC, sampleIndex ASC, createdAt ASC',
    );
    return result.map(StationSampleModel.fromMap).toList();
  }

  Future<List<StationSampleModel>> getSamplesForStation(
    String auditSessionId,
    String stationType,
  ) async {
    final db = await _dbHelper.db;
    final result = await db.query(
      'station_samples',
      where: 'auditSessionId = ? AND stationType = ?',
      whereArgs: [auditSessionId, stationType],
      orderBy: 'sampleIndex ASC, createdAt ASC',
    );
    return result.map(StationSampleModel.fromMap).toList();
  }

  Future<List<StationSampleModel>> getSamplesByGroupKey(
    String auditSessionId,
    String groupKey,
  ) async {
    final db = await _dbHelper.db;
    final result = await db.query(
      'station_samples',
      where: 'auditSessionId = ? AND groupKey = ?',
      whereArgs: [auditSessionId, groupKey],
      orderBy: 'sampleIndex ASC, createdAt ASC',
    );
    return result.map(StationSampleModel.fromMap).toList();
  }

  Future<List<StationSampleModel>> getSamplesByLegacyAuditId(
    String legacyAuditId,
  ) async {
    final db = await _dbHelper.db;
    final result = await db.query(
      'station_samples',
      where: 'legacyAuditId = ?',
      whereArgs: [legacyAuditId],
      orderBy: 'sampleIndex ASC, createdAt ASC',
    );
    return result.map(StationSampleModel.fromMap).toList();
  }

  Future<void> deleteSample(String id) async {
    final db = await _dbHelper.db;
    await db.delete('station_samples', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> upsertSampleRow(Map<String, dynamic> row) async {
    final db = await _dbHelper.db;
    final columns = await _tableColumns(db, 'station_samples');
    final normalized = _filterColumns(_normalizeRow(row), columns);
    await db.insert(
      'station_samples',
      normalized,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Set<String>> _tableColumns(Database db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((row) => row['name'] as String).toSet();
  }

  Map<String, dynamic> _filterColumns(
    Map<String, dynamic> row,
    Set<String> columns,
  ) {
    return Map.fromEntries(
      row.entries.where((entry) => columns.contains(entry.key)),
    );
  }

  Map<String, dynamic> _normalizeRow(Map<String, dynamic> row) {
    final normalized = <String, dynamic>{};
    for (final entry in row.entries) {
      normalized[_camelize(entry.key)] = entry.value;
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
}
