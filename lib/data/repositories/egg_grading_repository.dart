import 'package:sqflite/sqflite.dart';

import '../../features/audits/models/egg_grading.dart';
import '../database/database_helper.dart';
import 'sync_tombstone_repository.dart';

/// Reads and writes per-sample defect counts for visual egg grading.
///
/// One egg may carry several defects, so counts are occurrences, not a
/// partition of the sample — there is deliberately no
/// `SUM(counts) <= sampleSize` rule here or anywhere downstream.
class EggGradingRepository {
  EggGradingRepository({DatabaseHelper? databaseHelper})
    : _dbHelper = databaseHelper ?? DatabaseHelper();

  final DatabaseHelper _dbHelper;

  static const String table = 'egg_quality_defect_counts';

  /// dirtyAt cutoff captured at the last getDirtyRows() call; see
  /// markRowsSynced. Mirrors LabAnalysisRepository's per-table cutoff map,
  /// but this repository only ever owns one table.
  String? _dirtyReadCutoff;

  Future<Map<String, int>> countsForSample(String eggQualityId) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      table,
      where: 'eggQualityId = ?',
      whereArgs: [eggQualityId],
    );
    return {
      for (final row in rows) row['defectCode'] as String: row['count'] as int,
    };
  }

  Future<Map<String, Map<String, int>>> countsForSession(
    String sessionId,
  ) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      table,
      where: 'sessionId = ?',
      whereArgs: [sessionId],
    );
    final result = <String, Map<String, int>>{};
    for (final row in rows) {
      final sampleId = row['eggQualityId'] as String;
      final code = row['defectCode'] as String;
      final count = row['count'] as int;
      (result[sampleId] ??= <String, int>{})[code] = count;
    }
    return result;
  }

  Future<void> replaceCountsForSample({
    required String eggQualityId,
    required String sessionId,
    required String customerId,
    String? flockId,
    String? hatcheryId,
    required String date,
    String? scopeType,
    String? houseKey,
    String? sampleLabel,
    required int sampleSize,
    required Map<String, int> counts,
  }) async {
    final db = await _dbHelper.db;
    final now = DateTime.now().toIso8601String();
    await db.transaction<void>((txn) async {
      final existingRows = await txn.query(
        table,
        columns: ['id', 'defectCode'],
        where: 'eggQualityId = ?',
        whereArgs: [eggQualityId],
      );
      final existingIdByCode = <String, String>{
        for (final row in existingRows)
          row['defectCode'] as String: row['id'] as String,
      };

      final keptCodes = <String>{};
      var sortOrder = 0;
      for (final entry in counts.entries) {
        if (entry.value <= 0) continue;
        final code = entry.key;
        keptCodes.add(code);
        final defectType = eggDefectTypeForCode(code);
        final existingId = existingIdByCode[code];
        final id = existingId ?? '$eggQualityId:$code';
        final row = {
          'id': id,
          'eggQualityId': eggQualityId,
          'sessionId': sessionId,
          'customerId': customerId,
          'flockId': flockId,
          'hatcheryId': hatcheryId,
          'date': date,
          'scopeType': scopeType,
          'houseKey': houseKey,
          'sampleLabel': sampleLabel,
          'defectCode': code,
          'defectCategory': defectType?.category,
          'isReject': defectType == null ? null : (defectType.isReject ? 1 : 0),
          'count': entry.value,
          'pctOfSample': sampleSize <= 0
              ? null
              : entry.value * 100 / sampleSize,
          'sortOrder': defectType?.sortOrder ?? sortOrder,
          'updatedAt': now,
          'syncStatus': 'pending',
          'dirtyAt': now,
          'syncError': null,
        };
        if (existingId == null) {
          // New row: set createdAt once. Existing rows keep their original
          // createdAt — _upsertById's update path never touches it.
          await _upsertById(txn, table, {...row, 'createdAt': now});
        } else {
          await _upsertById(txn, table, row);
        }
        sortOrder++;
      }

      final removedIds = <String>[
        for (final entry in existingIdByCode.entries)
          if (!keptCodes.contains(entry.key)) entry.value,
      ];
      if (removedIds.isNotEmpty) {
        await SyncTombstoneRepository.queueDeletesWithExecutor(
          txn,
          table,
          removedIds,
        );
        await txn.delete(
          table,
          where: 'id IN (${List.filled(removedIds.length, '?').join(', ')})',
          whereArgs: removedIds,
        );
      }
    });
  }

  Future<void> deleteCountsForSamples(Iterable<String> eggQualityIds) async {
    final ids = eggQualityIds.toList(growable: false);
    if (ids.isEmpty) return;
    final db = await _dbHelper.db;
    await db.transaction<void>((txn) async {
      final rows = await txn.query(
        table,
        columns: ['id'],
        where: 'eggQualityId IN (${List.filled(ids.length, '?').join(', ')})',
        whereArgs: ids,
      );
      final rowIds = rows.map((row) => row['id']).toList();
      await SyncTombstoneRepository.queueDeletesWithExecutor(
        txn,
        table,
        rowIds,
      );
      await txn.delete(
        table,
        where: 'eggQualityId IN (${List.filled(ids.length, '?').join(', ')})',
        whereArgs: ids,
      );
    });
  }

  Future<List<Map<String, dynamic>>> getDirtyRows() async {
    final db = await _dbHelper.db;
    _dirtyReadCutoff = DateTime.now().toIso8601String();
    final rows = await db.query(
      table,
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'dirtyAt ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>?> getRowById(String id) async {
    final db = await _dbHelper.db;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.single);
  }

  /// Stores a Supabase row as locally synced. Supabase returns snake_case
  /// columns while SQLite uses camelCase; unknown remote fields are ignored so
  /// a newer cloud schema cannot prevent otherwise-valid count rows from
  /// arriving on an older device.
  Future<void> upsertRemoteRow(Map<String, dynamic> row) async {
    final db = await _dbHelper.db;
    final columns = (await db.rawQuery(
      'PRAGMA table_info($table)',
    )).map((column) => column['name']?.toString()).whereType<String>().toSet();
    final normalized = <String, dynamic>{
      for (final entry in row.entries)
        _toLocalColumn(entry.key): entry.value is bool
            ? (entry.value ? 1 : 0)
            : entry.value,
    };
    final synced = <String, dynamic>{
      ...normalized,
      'syncStatus': 'synced',
      'dirtyAt': null,
      'lastSyncedAt': DateTime.now().toIso8601String(),
      'syncError': null,
    };
    final supported = <String, dynamic>{
      for (final entry in synced.entries)
        if (columns.contains(entry.key)) entry.key: entry.value,
    };
    if (supported['id'] == null) return;
    await _upsertById(db, table, supported);
  }

  static String _toLocalColumn(String column) {
    return column.replaceAllMapped(
      RegExp(r'_([a-zA-Z0-9])'),
      (match) => match.group(1)!.toUpperCase(),
    );
  }

  Future<void> markRowsSynced(Iterable<String> ids) async {
    final idList = ids.toList(growable: false);
    if (idList.isEmpty) return;
    final db = await _dbHelper.db;
    final cutoff = _dirtyReadCutoff ?? DateTime.now().toIso8601String();
    await db.update(
      table,
      {
        'syncStatus': 'synced',
        'dirtyAt': null,
        'lastSyncedAt': DateTime.now().toIso8601String(),
        'syncError': null,
      },
      where:
          'id IN (${List.filled(idList.length, '?').join(', ')}) '
          'AND (dirtyAt IS NULL OR dirtyAt <= ?)',
      whereArgs: [...idList, cutoff],
    );
  }

  Future<void> markRowsFailed(Iterable<String> ids, Object error) async {
    final idList = ids.toList(growable: false);
    if (idList.isEmpty) return;
    final db = await _dbHelper.db;
    await db.update(
      table,
      {'syncStatus': 'failed', 'syncError': error.toString()},
      where: 'id IN (${List.filled(idList.length, '?').join(', ')})',
      whereArgs: idList,
    );
  }

  /// Upserts by id. Relies on sqflite's `insert` returning `0` for a
  /// conflicting row under `ConflictAlgorithm.ignore` (no rowid is assigned
  /// when the insert is skipped), which signals us to fall through to an
  /// update instead. This is a plain insert-then-update, not
  /// `INSERT ... ON CONFLICT(id) DO UPDATE`, so it takes two statements.
  Future<void> _upsertById(
    DatabaseExecutor executor,
    String table,
    Map<String, dynamic> row,
  ) async {
    final inserted = await executor.insert(
      table,
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (inserted != 0) return;
    await executor.update(table, row, where: 'id = ?', whereArgs: [row['id']]);
  }
}
