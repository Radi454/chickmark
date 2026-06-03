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
    String? stationKey,
    String? machineId,
    required String captureDate,
  }) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'govee_daily_captures',
      where:
          'customerId = ? AND hatcheryId = ? AND place = ? AND machineId = ? AND captureDate = ?',
      whereArgs: [
        customerId,
        hatcheryId,
        place.name,
        _storedMachineId(machineId),
        captureDate,
      ],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return GoveeDailyCaptureModel.fromMap(rows.first);
  }

  Future<void> saveReplacement({
    required GoveeDailyCaptureModel capture,
    required List<GoveePlaceReadingModel> readings,
    List<GoveePlaceReadingModel> rawReadings = const [],
  }) async {
    final db = await _dbHelper.db;
    await db.transaction<void>((txn) async {
      final existing = await txn.query(
        'govee_daily_captures',
        where:
            'customerId = ? AND hatcheryId = ? AND place = ? AND machineId = ? AND captureDate = ?',
        whereArgs: [
          capture.customerId,
          capture.hatcheryId,
          capture.place.name,
          _storedMachineId(capture.machineId),
          capture.captureDate,
        ],
        limit: 1,
      );

      for (final row in existing) {
        final existingId = row['id'];
        await txn.delete(
          'govee_capture_readings',
          where: 'captureId = ?',
          whereArgs: [existingId],
        );
        await txn.delete(
          'govee_daily_captures',
          where: 'id = ?',
          whereArgs: [existingId],
        );
      }

      await txn.insert(
        'govee_daily_captures',
        _captureToStorageMap(
          capture.copyWith(
            chartPointsJson: GoveePlaceReadingModel.listToJson(readings),
          ),
        ),
      );

      for (final reading in rawReadings) {
        await txn.insert(
          'govee_capture_readings',
          _rawReadingToStorageMap(capture.id, reading),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<GoveeDailyCaptureModel>> getCapturesForDashboard({
    String? customerId,
    String? hatcheryId,
    String? captureDate,
  }) async {
    final db = await _dbHelper.db;
    final clauses = <String>[];
    final whereArgs = <Object?>[];
    if (customerId != null) {
      clauses.add('customerId = ?');
      whereArgs.add(customerId);
    }
    if (hatcheryId != null) {
      clauses.add('hatcheryId = ?');
      whereArgs.add(hatcheryId);
    }
    if (captureDate != null) {
      clauses.add('captureDate = ?');
      whereArgs.add(captureDate);
    }
    final rows = await db.query(
      'govee_daily_captures',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy:
          'captureDate DESC, stationKey ASC, place ASC, machineId ASC, updatedAt DESC',
    );
    return rows.map(GoveeDailyCaptureModel.fromMap).toList();
  }

  Future<List<GoveePlaceReadingModel>> getReadingsForCapture(
    String captureId,
  ) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'govee_daily_captures',
      where: 'id = ?',
      whereArgs: [captureId],
      limit: 1,
    );
    if (rows.isEmpty) return const [];
    return GoveeDailyCaptureModel.fromMap(rows.first).chartReadings;
  }

  Future<List<GoveeDailyCaptureModel>> getAllCaptures() async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'govee_daily_captures',
      orderBy: 'captureDate DESC, updatedAt DESC',
    );
    return rows.map(GoveeDailyCaptureModel.fromMap).toList();
  }

  Future<void> upsertCaptureRow(Map<String, dynamic> row) async {
    final db = await _dbHelper.db;
    await _upsertFilteredRow(db, 'govee_daily_captures', row);
  }

  Future<Map<String, dynamic>?> getCaptureRowById(String id) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'govee_daily_captures',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<void> _upsertFilteredRow(
    Database db,
    String table,
    Map<String, dynamic> row,
  ) async {
    final columns = await _tableColumns(db, table);
    final normalized = _normalizeRow(row);
    if (table == 'govee_daily_captures') {
      _normalizeCaptureStorageRow(normalized);
    }
    await _upsertById(db, table, _filterColumns(normalized, columns));
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
    if (normalized.containsKey('place')) {
      normalized['place'] = temperaturePlaceFromName(
        normalized['place'] as String?,
      ).name;
    }
    if (normalized.containsKey('activePlace')) {
      normalized['activePlace'] = temperaturePlaceFromName(
        normalized['activePlace'] as String?,
      ).name;
    }
    if (normalized.containsKey('machineId')) {
      normalized['machineId'] = _storedMachineId(normalized['machineId']);
    }
    if (normalized.containsKey('stationKey')) {
      normalized['stationKey'] = '${normalized['stationKey'] ?? ''}'.trim();
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

  Map<String, dynamic> _captureToStorageMap(GoveeDailyCaptureModel capture) {
    final row = capture.toMap();
    _normalizeCaptureStorageRow(row);
    return row;
  }

  Map<String, dynamic> _rawReadingToStorageMap(
    String captureId,
    GoveePlaceReadingModel reading,
  ) {
    return {
      'id': reading.id,
      'captureId': captureId,
      'recordedAtMs': reading.recordedAt.millisecondsSinceEpoch,
      'temperatureFahrenheit': reading.temperatureFahrenheit,
      'humidity': reading.humidity,
    };
  }

  void _normalizeCaptureStorageRow(Map<String, dynamic> row) {
    final place = temperaturePlaceFromName(row['place'] as String?);
    row['place'] = place.name;
    final stationKey = '${row['stationKey'] ?? ''}'.trim();
    row['stationKey'] = stationKey.isEmpty
        ? goveeStationKeyForTemperaturePlace(place)
        : stationKey;
    row['machineId'] = _storedMachineId(row['machineId']);
  }

  String _storedMachineId(Object? machineId) {
    if (machineId == null) return '';
    return machineId.toString().trim();
  }
}
