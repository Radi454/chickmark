import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/station_sample_model.dart';
import 'sync_tombstone_repository.dart';

class StationSampleRepository {
  final DatabaseHelper _dbHelper;

  StationSampleRepository({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  Future<void> upsertSample(StationSampleModel sample) async {
    final db = await _dbHelper.db;
    await db.transaction<void>((txn) async {
      await upsertSampleInTransaction(txn, sample);
    });
  }

  Future<void> upsertSampleInTransaction(
    DatabaseExecutor executor,
    StationSampleModel sample,
  ) async {
    await _clearDetailRows(executor, sample.id);
    await _upsertByKey(executor, 'sample_records', _recordMap(sample), 'id');
    if (_hasHouseDetails(sample)) {
      await _upsertByKey(
        executor,
        'sample_house_details',
        _houseDetailsMap(sample),
        'sampleRecordId',
      );
    }
    if (_hasMachineDetails(sample)) {
      await _upsertByKey(
        executor,
        'sample_machine_details',
        _machineDetailsMap(sample),
        'sampleRecordId',
      );
    }
    if (_hasBatchDetails(sample)) {
      await _upsertByKey(
        executor,
        'sample_batch_details',
        _batchDetailsMap(sample),
        'sampleRecordId',
      );
    }
    if (_hasTimingDetails(sample)) {
      await _upsertByKey(
        executor,
        'sample_timing_details',
        _timingDetailsMap(sample),
        'sampleRecordId',
      );
    }
  }

  Future<StationSampleModel?> getSampleById(String id) async {
    final db = await _dbHelper.db;
    final result = await db.rawQuery(
      '$_sampleSelectSql WHERE r.id = ? LIMIT 1',
      [id],
    );
    if (result.isEmpty) return null;
    return StationSampleModel.fromMap(result.first);
  }

  Future<List<StationSampleModel>> getSamplesBySessionId(
    String auditSessionId,
  ) async {
    final db = await _dbHelper.db;
    final result = await db.rawQuery(
      '''
$_sampleSelectSql
WHERE r.auditSessionId = ?
ORDER BY r.stationType ASC, r.sectorType ASC, r.sampleIndex ASC, r.createdAt ASC
''',
      [auditSessionId],
    );
    return result.map(StationSampleModel.fromMap).toList();
  }

  Future<List<StationSampleModel>> getSamplesForStation(
    String auditSessionId,
    String stationType,
  ) async {
    final db = await _dbHelper.db;
    final result = await db.rawQuery(
      '''
$_sampleSelectSql
WHERE r.auditSessionId = ? AND r.stationType = ?
ORDER BY r.sectorType ASC, r.sampleIndex ASC, r.createdAt ASC
''',
      [auditSessionId, stationType],
    );
    return result.map(StationSampleModel.fromMap).toList();
  }

  Future<List<StationSampleModel>> getSamplesByGroupKey(
    String auditSessionId,
    String groupKey,
  ) async {
    final db = await _dbHelper.db;
    final result = await db.rawQuery(
      '''
$_sampleSelectSql
WHERE r.auditSessionId = ? AND r.groupKey = ?
ORDER BY r.sampleIndex ASC, r.createdAt ASC
''',
      [auditSessionId, groupKey],
    );
    return result.map(StationSampleModel.fromMap).toList();
  }

  Future<List<StationSampleModel>> getSamplesByLegacyAuditId(
    String legacyAuditId,
  ) async {
    final db = await _dbHelper.db;
    final result = await db.rawQuery(
      '''
$_sampleSelectSql
WHERE r.legacyAuditId = ?
ORDER BY r.sampleIndex ASC, r.createdAt ASC
''',
      [legacyAuditId],
    );
    return result.map(StationSampleModel.fromMap).toList();
  }

  Future<void> deleteSample(String id) async {
    final db = await _dbHelper.db;
    await db.transaction<void>((txn) async {
      for (final table in detailTables) {
        await SyncTombstoneRepository.queueDeleteWithExecutor(txn, table, id);
      }
      await SyncTombstoneRepository.queueDeleteWithExecutor(
        txn,
        'sample_records',
        id,
      );
      await txn.delete('sample_records', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> upsertSampleRow(Map<String, dynamic> row) async {
    final normalized = _normalizeRow(row);
    final now = DateTime.now().toIso8601String();
    normalized['id'] ??=
        '${normalized['auditSessionId']}-${normalized['stationType']}-${normalized['sampleIndex'] ?? 1}';
    normalized['sampleIndex'] ??= 1;
    normalized['sampleLabel'] ??= 'Sample ${normalized['sampleIndex']}';
    normalized['stationType'] ??= 'station';
    normalized['sampleMode'] ??= StationSampleModel.sampleModePooled;
    normalized['sectorType'] ??= _inferSectorType(normalized['stationType']);
    normalized['sampleKind'] ??= _inferSampleKind(normalized);
    normalized['createdAt'] ??= now;
    normalized['updatedAt'] ??= now;
    await upsertSample(StationSampleModel.fromMap(normalized));
  }

  Future<List<Map<String, dynamic>>> getAllSampleRecordRows() async {
    final db = await _dbHelper.db;
    final rows = await db.query('sample_records', orderBy: 'createdAt ASC');
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>?> getSampleRecordRowById(String id) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'sample_records',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<List<Map<String, dynamic>>> getAllDetailRows(String table) async {
    _assertDetailTable(table);
    final db = await _dbHelper.db;
    final rows = await db.query(table, orderBy: 'sampleRecordId ASC');
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> upsertDetailRow(String table, Map<String, dynamic> row) async {
    _assertDetailTable(table);
    final db = await _dbHelper.db;
    final normalized = _normalizeRow(row);
    await _upsertByKey(db, table, normalized, 'sampleRecordId');
  }

  Future<void> _upsertByKey(
    DatabaseExecutor executor,
    String table,
    Map<String, dynamic> row,
    String keyColumn,
  ) async {
    final inserted = await executor.insert(
      table,
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (inserted != 0) return;
    await executor.update(
      table,
      row,
      where: '$keyColumn = ?',
      whereArgs: [row[keyColumn]],
    );
  }

  static const detailTables = [
    'sample_house_details',
    'sample_machine_details',
    'sample_batch_details',
    'sample_timing_details',
  ];

  static const String _sampleSelectSql = '''
SELECT
  r.*,
  h.houseNo,
  h.houseLabel,
  m.setterNo,
  m.hatcherNo,
  b.batchNo,
  b.hatchNo,
  b.storageDays,
  b.incubationDay,
  t.eggProductionDate,
  t.settingDate,
  t.hatchDate
FROM sample_records r
LEFT JOIN sample_house_details h ON h.sampleRecordId = r.id
LEFT JOIN sample_machine_details m ON m.sampleRecordId = r.id
LEFT JOIN sample_batch_details b ON b.sampleRecordId = r.id
LEFT JOIN sample_timing_details t ON t.sampleRecordId = r.id
''';

  Future<void> _clearDetailRows(DatabaseExecutor executor, String id) async {
    for (final table in detailTables) {
      await executor.delete(
        table,
        where: 'sampleRecordId = ?',
        whereArgs: [id],
      );
    }
  }

  void _assertDetailTable(String table) {
    if (!detailTables.contains(table)) {
      throw ArgumentError('Unsupported sample detail table: $table');
    }
  }

  Map<String, dynamic> _recordMap(StationSampleModel sample) {
    return {
      'id': sample.id,
      'auditSessionId': sample.auditSessionId,
      'legacyAuditId': sample.legacyAuditId,
      'stationType': sample.stationType,
      'sectorType': sample.sectorType,
      'sampleKind': sample.sampleKind,
      'sampleMode': sample.sampleMode,
      'comparisonType': sample.comparisonType,
      'sampleIndex': sample.sampleIndex,
      'sampleLabel': sample.sampleLabel,
      'sampleType': sample.sampleType,
      'breakoutType': sample.breakoutType,
      'groupKey': sample.groupKey,
      'groupLabel': sample.groupLabel,
      'calculatedBmkAgeDays': sample.calculatedBmkAgeDays,
      'benchmarkBreed': sample.benchmarkBreed,
      'benchmarkAgeDays': sample.benchmarkAgeDays,
      'benchmarkSource': sample.benchmarkSource,
      'benchmarkSnapshotJson': sample.benchmarkSnapshotJson,
      'resultSummaryJson': sample.resultSummaryJson,
      'notes': sample.notes,
      'createdAt': sample.createdAt.toIso8601String(),
      'updatedAt': sample.updatedAt.toIso8601String(),
    };
  }

  bool _hasHouseDetails(StationSampleModel sample) {
    return sample.sampleKind == StationSampleModel.sampleKindHouse ||
        sample.houseNo != null ||
        sample.houseLabel != null;
  }

  Map<String, dynamic> _houseDetailsMap(StationSampleModel sample) {
    return {
      'sampleRecordId': sample.id,
      'houseNo': sample.houseNo,
      'houseLabel': sample.houseLabel,
    };
  }

  bool _hasMachineDetails(StationSampleModel sample) {
    return sample.sampleKind == StationSampleModel.sampleKindMachine ||
        sample.setterNo != null ||
        sample.hatcherNo != null;
  }

  Map<String, dynamic> _machineDetailsMap(StationSampleModel sample) {
    return {
      'sampleRecordId': sample.id,
      'setterNo': sample.setterNo,
      'hatcherNo': sample.hatcherNo,
    };
  }

  bool _hasBatchDetails(StationSampleModel sample) {
    return sample.sampleKind == StationSampleModel.sampleKindBatch ||
        sample.batchNo != null ||
        sample.hatchNo != null ||
        sample.storageDays != null ||
        sample.incubationDay != null;
  }

  Map<String, dynamic> _batchDetailsMap(StationSampleModel sample) {
    return {
      'sampleRecordId': sample.id,
      'batchNo': sample.batchNo,
      'hatchNo': sample.hatchNo,
      'storageDays': sample.storageDays,
      'incubationDay': sample.incubationDay,
    };
  }

  bool _hasTimingDetails(StationSampleModel sample) {
    return sample.eggProductionDate != null ||
        sample.settingDate != null ||
        sample.hatchDate != null;
  }

  Map<String, dynamic> _timingDetailsMap(StationSampleModel sample) {
    return {
      'sampleRecordId': sample.id,
      'eggProductionDate': sample.eggProductionDate?.toIso8601String(),
      'settingDate': sample.settingDate?.toIso8601String(),
      'hatchDate': sample.hatchDate?.toIso8601String(),
    };
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

  String _inferSectorType(Object? stationType) {
    return switch (stationType?.toString()) {
      'egg' => StationSampleModel.sectorEggQuality,
      'chicks' => StationSampleModel.sectorChickQuality,
      'hatch_analysis_egg_breakouts' => StationSampleModel.sectorHatchBreakout,
      'setters' => StationSampleModel.sectorSetterOptimizing,
      'hatchers' => StationSampleModel.sectorHatcherOptimizing,
      _ => StationSampleModel.sectorDefault,
    };
  }

  String _inferSampleKind(Map<String, dynamic> row) {
    if (row['houseNo'] != null || row['houseLabel'] != null) {
      return StationSampleModel.sampleKindHouse;
    }
    if (row['setterNo'] != null || row['hatcherNo'] != null) {
      return StationSampleModel.sampleKindMachine;
    }
    if (row['batchNo'] != null || row['hatchNo'] != null) {
      return StationSampleModel.sampleKindBatch;
    }
    return StationSampleModel.sampleKindPooled;
  }
}
