import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/govee_capture_model.dart';
import '../models/temperature_rh_model.dart';

class GoveeCaptureRepository {
  final DatabaseHelper _dbHelper;

  GoveeCaptureRepository({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  Future<GoveeDailyCaptureModel?> getCaptureForScope({
    required String customerId,
    required String hatcheryId,
    required TemperaturePlace place,
    required String captureDate,
  }) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'govee_daily_captures',
      where:
          'customerId = ? AND hatcheryId = ? AND place = ? AND captureDate = ?',
      whereArgs: [customerId, hatcheryId, place.name, captureDate],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return GoveeDailyCaptureModel.fromMap(rows.first);
  }

  Future<void> saveReplacement({
    required GoveeDailyCaptureModel capture,
    required List<GoveeSpotCaptureModel> spots,
    required List<GoveeSpotReadingModel> readings,
  }) async {
    final db = await _dbHelper.db;
    await db.transaction<void>((txn) async {
      final existing = await txn.query(
        'govee_daily_captures',
        where:
            'customerId = ? AND hatcheryId = ? AND place = ? AND captureDate = ?',
        whereArgs: [
          capture.customerId,
          capture.hatcheryId,
          capture.place.name,
          capture.captureDate,
        ],
        limit: 1,
      );

      for (final row in existing) {
        await txn.delete(
          'govee_daily_captures',
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }

      await txn.insert(
        'govee_daily_captures',
        capture.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final spot in spots) {
        await txn.insert(
          'govee_spot_captures',
          spot.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final reading in readings) {
        await txn.insert(
          'govee_spot_readings',
          reading.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<GoveeDailyCaptureModel>> getCapturesForDashboard({
    required String customerId,
    required String hatcheryId,
    String? captureDate,
  }) async {
    final db = await _dbHelper.db;
    final where = StringBuffer('customerId = ? AND hatcheryId = ?');
    final whereArgs = <Object?>[customerId, hatcheryId];
    if (captureDate != null) {
      where.write(' AND captureDate = ?');
      whereArgs.add(captureDate);
    }
    final rows = await db.query(
      'govee_daily_captures',
      where: where.toString(),
      whereArgs: whereArgs,
      orderBy: 'captureDate DESC, updatedAt DESC',
    );
    return rows.map(GoveeDailyCaptureModel.fromMap).toList();
  }

  Future<List<GoveeSpotCaptureModel>> getSpotsForCapture(
    String captureId,
  ) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'govee_spot_captures',
      where: 'captureId = ?',
      whereArgs: [captureId],
      orderBy: 'spotIndex ASC',
    );
    return rows.map(GoveeSpotCaptureModel.fromMap).toList();
  }

  Future<List<GoveeSpotReadingModel>> getReadingsForCapture(
    String captureId,
  ) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'govee_spot_readings',
      where: 'captureId = ?',
      whereArgs: [captureId],
      orderBy: 'spotId ASC, readingIndex ASC',
    );
    return rows.map(GoveeSpotReadingModel.fromMap).toList();
  }

  Future<List<GoveeSpotReadingModel>> getReadingsForSpot(String spotId) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'govee_spot_readings',
      where: 'spotId = ?',
      whereArgs: [spotId],
      orderBy: 'readingIndex ASC',
    );
    return rows.map(GoveeSpotReadingModel.fromMap).toList();
  }

  Future<List<GoveeDailyCaptureModel>> getAllCaptures() async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'govee_daily_captures',
      orderBy: 'captureDate DESC, updatedAt DESC',
    );
    return rows.map(GoveeDailyCaptureModel.fromMap).toList();
  }

  Future<List<GoveeSpotCaptureModel>> getAllSpots() async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'govee_spot_captures',
      orderBy: 'captureId ASC, spotIndex ASC',
    );
    return rows.map(GoveeSpotCaptureModel.fromMap).toList();
  }

  Future<List<GoveeSpotReadingModel>> getAllReadings() async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'govee_spot_readings',
      orderBy: 'captureId ASC, spotId ASC, readingIndex ASC',
    );
    return rows.map(GoveeSpotReadingModel.fromMap).toList();
  }

  Future<void> upsertCaptureRow(Map<String, dynamic> row) async {
    final db = await _dbHelper.db;
    await _upsertFilteredRow(db, 'govee_daily_captures', row);
  }

  Future<void> upsertSpotRow(Map<String, dynamic> row) async {
    final db = await _dbHelper.db;
    await _upsertFilteredRow(db, 'govee_spot_captures', row);
  }

  Future<void> upsertReadingRow(Map<String, dynamic> row) async {
    final db = await _dbHelper.db;
    await _upsertFilteredRow(db, 'govee_spot_readings', row);
  }

  Future<void> _upsertFilteredRow(
    Database db,
    String table,
    Map<String, dynamic> row,
  ) async {
    final columns = await _tableColumns(db, table);
    final normalized = _filterColumns(_normalizeRow(row), columns);
    await db.insert(
      table,
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
