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
        await txn.delete(
          'govee_daily_captures',
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }

      await txn.insert(
        'govee_daily_captures',
        _stampDirty(
          _captureToStorageMap(
            capture.copyWith(
              chartPointsJson: GoveePlaceReadingModel.listToJson(readings),
            ),
          ),
        ),
      );
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

  /// Sync-pull write: rows from Supabase are in sync with the cloud, so mark
  /// them synced (the conflict check already short-circuited newer local edits).
  Future<void> upsertCaptureRow(Map<String, dynamic> row) async {
    final db = await _dbHelper.db;
    await _upsertFilteredRow(db, 'govee_daily_captures', _markRowSynced(row));
  }

  /// Govee captures awaiting a push (locally edited or last push failed).
  Future<List<GoveeDailyCaptureModel>> getDirtyCaptureRows() async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'govee_daily_captures',
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'dirtyAt ASC',
    );
    return rows.map(GoveeDailyCaptureModel.fromMap).toList();
  }

  Future<void> markCapturesSynced(Iterable<String> ids) async {
    final idList = ids.toList(growable: false);
    if (idList.isEmpty) return;
    final db = await _dbHelper.db;
    final placeholders = List.filled(idList.length, '?').join(', ');
    await db.update(
      'govee_daily_captures',
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

  Future<void> markCapturesFailed(Iterable<String> ids, Object error) async {
    final idList = ids.toList(growable: false);
    if (idList.isEmpty) return;
    final db = await _dbHelper.db;
    final placeholders = List.filled(idList.length, '?').join(', ');
    await db.update(
      'govee_daily_captures',
      {'syncStatus': 'failed', 'syncError': error.toString()},
      where: 'id IN ($placeholders)',
      whereArgs: idList,
    );
  }

  /// Per-session, per-station Govee rollup for the Audits screen. Govee captures
  /// link to a visit by customer + hatchery + captureDate. Returns
  /// `"customerId|hatcheryId|captureDate" -> stationKey -> syncStatus -> count`.
  Future<Map<String, Map<String, Map<String, int>>>>
  getGoveeRollupForSessions(
    Iterable<({String customerId, String hatcheryId, String captureDate})> keys,
  ) async {
    final tuples = keys.toSet().toList(growable: false);
    final result = <String, Map<String, Map<String, int>>>{};
    if (tuples.isEmpty) return result;
    final db = await _dbHelper.db;
    final orClause = List.filled(
      tuples.length,
      '(customerId = ? AND hatcheryId = ? AND captureDate = ?)',
    ).join(' OR ');
    final args = <Object?>[];
    for (final tuple in tuples) {
      args
        ..add(tuple.customerId)
        ..add(tuple.hatcheryId)
        ..add(tuple.captureDate);
    }
    final rows = await db.rawQuery(
      'SELECT customerId, hatcheryId, captureDate, stationKey, syncStatus, '
      'COUNT(*) AS c FROM govee_daily_captures WHERE $orClause '
      'GROUP BY customerId, hatcheryId, captureDate, stationKey, syncStatus',
      args,
    );
    for (final row in rows) {
      final key =
          '${row['customerId']}|${row['hatcheryId']}|${row['captureDate']}';
      final stationKey = (row['stationKey'] as String?) ?? '';
      if (stationKey.isEmpty) continue;
      final status = (row['syncStatus'] as String?) ?? 'synced';
      final count = (row['c'] as int?) ?? 0;
      final byStation = result.putIfAbsent(key, () => {});
      final byStatus = byStation.putIfAbsent(stationKey, () => {});
      byStatus[status] = (byStatus[status] ?? 0) + count;
    }
    return result;
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
