import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/lab_analysis_models.dart';
import 'sync_tombstone_repository.dart';

class LabAnalysisRepository {
  LabAnalysisRepository({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  final DatabaseHelper _dbHelper;

  static const reportsTable = 'lab_analysis_reports';
  static const groupsTable = 'lab_analysis_groups';
  static const rowsTable = 'lab_analysis_rows';
  static const syncTables = [reportsTable, groupsTable, rowsTable];

  Future<void> saveBatch({
    required LabAnalysisReportModel report,
    required LabAnalysisGroupModel group,
    required List<LabAnalysisRowModel> rows,
  }) async {
    await _dbHelper.assertForeignKeys(
      customerId: report.customerId,
      flockId: report.flockId,
    );
    final now = DateTime.now();
    final preparedRows = _prepareRows(group, rows, now);
    final preparedGroup = _prepareGroup(group, preparedRows, now);
    final preparedReport = report.copyWith(
      updatedAt: now,
      syncStatus: 'pending',
      dirtyAt: now,
      syncError: null,
    );

    final db = await _dbHelper.db;
    await db.transaction<void>((txn) async {
      await _upsertById(txn, reportsTable, preparedReport.toMap());
      await _upsertById(txn, groupsTable, preparedGroup.toMap());
      await txn.delete(rowsTable, where: 'groupId = ?', whereArgs: [group.id]);
      for (final row in preparedRows) {
        await _upsertById(txn, rowsTable, row.toMap());
      }
    });
  }

  Future<List<LabAnalysisBatch>> getBatches({
    String? customerId,
    String? flockId,
    int limit = 50,
  }) async {
    final db = await _dbHelper.db;
    final clauses = <String>[];
    final args = <Object?>[];
    if (customerId != null) {
      clauses.add('customerId = ?');
      args.add(customerId);
    }
    if (flockId != null) {
      clauses.add('flockId = ?');
      args.add(flockId);
    }
    final reportRows = await db.query(
      reportsTable,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'reportDate DESC, updatedAt DESC',
      limit: limit,
    );
    final batches = <LabAnalysisBatch>[];
    for (final row in reportRows) {
      final report = LabAnalysisReportModel.fromMap(Map.from(row));
      final groups = await getGroupsForReport(report.id);
      final rowsByGroupId = <String, List<LabAnalysisRowModel>>{};
      for (final group in groups) {
        rowsByGroupId[group.id] = await getRowsForGroup(group.id);
      }
      batches.add(
        LabAnalysisBatch(
          report: report,
          groups: groups,
          rowsByGroupId: rowsByGroupId,
        ),
      );
    }
    return batches;
  }

  Future<List<LabAnalysisGroupModel>> getGroupsForReport(
    String reportId,
  ) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      groupsTable,
      where: 'reportId = ?',
      whereArgs: [reportId],
      orderBy: 'sortOrder ASC, updatedAt DESC',
    );
    return rows
        .map((row) => LabAnalysisGroupModel.fromMap(Map.from(row)))
        .toList();
  }

  Future<List<LabAnalysisRowModel>> getRowsForGroup(String groupId) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      rowsTable,
      where: 'groupId = ?',
      whereArgs: [groupId],
      orderBy: 'sortOrder ASC, rowLabel ASC',
    );
    return rows
        .map((row) => LabAnalysisRowModel.fromMap(Map.from(row)))
        .toList();
  }

  Future<List<LabAnalysisDashboardSummary>> getDashboardSummaries({
    String? customerId,
    String? flockId,
    int limit = 120,
  }) async {
    final db = await _dbHelper.db;
    final clauses = <String>[];
    final args = <Object?>[];
    if (customerId != null) {
      clauses.add('customerId = ?');
      args.add(customerId);
    }
    if (flockId != null) {
      clauses.add('flockId = ?');
      args.add(flockId);
    }
    final groupRows = await db.query(
      groupsTable,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'reportDate DESC, testType ASC, sortOrder ASC',
      limit: limit,
    );
    final summaries = <LabAnalysisDashboardSummary>[];
    for (final row in groupRows) {
      final group = LabAnalysisGroupModel.fromMap(Map.from(row));
      final report = await getReportById(group.reportId);
      if (report == null) continue;
      summaries.add(
        LabAnalysisDashboardSummary(
          report: report,
          group: group,
          rows: await getRowsForGroup(group.id),
        ),
      );
    }
    return summaries;
  }

  Future<LabAnalysisReportModel?> getReportById(String id) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      reportsTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LabAnalysisReportModel.fromMap(Map.from(rows.first));
  }

  Future<void> deleteReport(String id) async {
    final db = await _dbHelper.db;
    await db.transaction<void>((txn) async {
      final groupRows = await txn.query(
        groupsTable,
        columns: ['id'],
        where: 'reportId = ?',
        whereArgs: [id],
      );
      final rowRows = await txn.query(
        rowsTable,
        columns: ['id'],
        where: 'reportId = ?',
        whereArgs: [id],
      );
      await SyncTombstoneRepository.queueDeletesWithExecutor(
        txn,
        rowsTable,
        rowRows.map((row) => row['id']),
      );
      await SyncTombstoneRepository.queueDeletesWithExecutor(
        txn,
        groupsTable,
        groupRows.map((row) => row['id']),
      );
      await SyncTombstoneRepository.queueDeleteWithExecutor(
        txn,
        reportsTable,
        id,
      );
      await txn.delete(rowsTable, where: 'reportId = ?', whereArgs: [id]);
      await txn.delete(groupsTable, where: 'reportId = ?', whereArgs: [id]);
      await txn.delete(reportsTable, where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> deleteRecordsByCustomer(String customerId) async {
    final db = await _dbHelper.db;
    await db.transaction<void>((txn) async {
      await _deleteScope(txn, 'customerId = ?', [customerId]);
    });
  }

  Future<void> deleteRecordsByFlock(String flockId) async {
    final db = await _dbHelper.db;
    await db.transaction<void>((txn) async {
      await _deleteScope(txn, 'flockId = ?', [flockId]);
    });
  }

  Future<List<Map<String, dynamic>>> getDirtyRows(String table) async {
    _assertSyncTable(table);
    final db = await _dbHelper.db;
    final rows = await db.query(
      table,
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'dirtyAt ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>?> getRowById(String table, String id) async {
    _assertSyncTable(table);
    final db = await _dbHelper.db;
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<void> upsertRemoteRow(String table, Map<String, dynamic> row) async {
    _assertSyncTable(table);
    final db = await _dbHelper.db;
    final columns = await _tableColumns(db, table);
    final normalized = _normalizeRemoteRow(table, row);
    final synced = {
      ...normalized,
      'syncStatus': 'synced',
      'dirtyAt': null,
      'lastSyncedAt': DateTime.now().toIso8601String(),
      'syncError': null,
    };
    await _upsertById(db, table, _filterColumns(synced, columns));
  }

  Future<void> markRowsSynced(String table, Iterable<String> ids) {
    _assertSyncTable(table);
    return _markRows(table, ids, {
      'syncStatus': 'synced',
      'dirtyAt': null,
      'lastSyncedAt': DateTime.now().toIso8601String(),
      'syncError': null,
    });
  }

  Future<void> markRowsFailed(
    String table,
    Iterable<String> ids,
    Object error,
  ) {
    _assertSyncTable(table);
    return _markRows(table, ids, {
      'syncStatus': 'failed',
      'syncError': error.toString(),
    });
  }

  Future<void> updateReportFileRemotePath({
    required String reportId,
    String? fileName,
    required String remotePath,
  }) async {
    final db = await _dbHelper.db;
    final values = {
      'reportFileRemotePath': remotePath,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (fileName != null) values['reportFileName'] = fileName;
    await db.update(
      reportsTable,
      values,
      where: 'id = ?',
      whereArgs: [reportId],
    );
  }

  Future<void> _deleteScope(
    DatabaseExecutor txn,
    String where,
    List<Object?> args,
  ) async {
    final rowRows = await txn.query(
      rowsTable,
      columns: ['id'],
      where: where,
      whereArgs: args,
    );
    final groupRows = await txn.query(
      groupsTable,
      columns: ['id'],
      where: where,
      whereArgs: args,
    );
    final reportRows = await txn.query(
      reportsTable,
      columns: ['id'],
      where: where,
      whereArgs: args,
    );
    await SyncTombstoneRepository.queueDeletesWithExecutor(
      txn,
      rowsTable,
      rowRows.map((row) => row['id']),
    );
    await SyncTombstoneRepository.queueDeletesWithExecutor(
      txn,
      groupsTable,
      groupRows.map((row) => row['id']),
    );
    await SyncTombstoneRepository.queueDeletesWithExecutor(
      txn,
      reportsTable,
      reportRows.map((row) => row['id']),
    );
    await txn.delete(rowsTable, where: where, whereArgs: args);
    await txn.delete(groupsTable, where: where, whereArgs: args);
    await txn.delete(reportsTable, where: where, whereArgs: args);
  }

  LabAnalysisGroupModel _prepareGroup(
    LabAnalysisGroupModel group,
    List<LabAnalysisRowModel> rows,
    DateTime now,
  ) {
    var prepared = group;
    if (group.testType == LabTestType.hi) {
      final total = rows.fold<int>(0, (sum, row) => sum + (row.count ?? 0));
      final threshold =
          group.protectiveThresholdLog2 ??
          LabInterpretationRules.protectiveThresholdForAntigen(group.antigen);
      final protective = rows.fold<int>(0, (sum, row) {
        final log2 = row.hiLog2;
        if (log2 == null || log2 < threshold) return sum;
        return sum + (row.count ?? 0);
      });
      prepared = prepared.copyWith(
        sampleCount: group.sampleCount ?? (total == 0 ? null : total),
        protectiveThresholdLog2: threshold,
        protectiveCount: protective,
        protectivePct: total == 0 ? null : protective * 100 / total,
      );
    } else if (group.testType == LabTestType.pcr) {
      final positive = rows.where((row) {
        final value = '${row.result} ${row.resultCategory}'.toLowerCase();
        return value.contains('+ve') ||
            value.contains('positive') ||
            value.contains('detected');
      }).length;
      prepared = prepared.copyWith(
        sampleCount: rows.length,
        positiveCount: positive,
        negativeCount: rows.length - positive,
        positivePct: rows.isEmpty ? null : positive * 100 / rows.length,
      );
    } else if (group.testType == LabTestType.culture) {
      final positive = rows.where((row) {
        final value = '${row.resultCategory} ${row.result}'.toLowerCase();
        if (value.contains('negative') ||
            value.contains('not isolated') ||
            value.contains('no growth')) {
          return false;
        }
        return value.contains('positive') ||
            value.contains('isolated') ||
            value.contains('growth');
      }).length;
      prepared = prepared.copyWith(
        sampleCount: rows.length,
        positiveCount: positive,
        negativeCount: rows.length - positive,
        positivePct: rows.isEmpty ? null : positive * 100 / rows.length,
      );
    } else if (group.testType == LabTestType.sensitivity) {
      prepared = prepared.copyWith(sampleCount: rows.length);
    } else if (group.testType == LabTestType.elisa) {
      final sampleCount = group.sampleCount ?? rows.length;
      final positiveCount =
          group.positiveCount ??
          rows.where((row) {
            final value = '${row.result} ${row.resultCategory}'.toLowerCase();
            return value.contains('p') ||
                value.contains('+ve') ||
                value.contains('positive');
          }).length;
      prepared = prepared.copyWith(
        sampleCount: sampleCount,
        positiveCount: positiveCount,
        negativeCount: sampleCount - positiveCount,
        positivePct: sampleCount == 0
            ? null
            : positiveCount * 100 / sampleCount,
      );
    }

    final interpreted = LabInterpretationRules.interpretGroup(prepared, rows);
    return prepared.copyWith(
      interpretation: interpreted.message,
      severity: interpreted.severity,
      updatedAt: now,
      syncStatus: 'pending',
      dirtyAt: now,
      syncError: null,
    );
  }

  List<LabAnalysisRowModel> _prepareRows(
    LabAnalysisGroupModel group,
    List<LabAnalysisRowModel> rows,
    DateTime now,
  ) {
    return [
      for (final row in rows)
        _prepareRow(
          row.copyWith(
            groupId: group.id,
            reportId: group.reportId,
            customerId: group.customerId,
            flockId: group.flockId,
            reportDate: group.reportDate,
            testType: group.testType,
          ),
          now,
        ),
    ];
  }

  LabAnalysisRowModel _prepareRow(LabAnalysisRowModel row, DateTime now) {
    final interpreted = LabInterpretationRules.interpretRow(row);
    return row.copyWith(
      interpretation: interpreted.message,
      severity: interpreted.severity,
      updatedAt: now,
      syncStatus: 'pending',
      dirtyAt: now,
      syncError: null,
    );
  }

  Future<void> _markRows(
    String table,
    Iterable<String> ids,
    Map<String, Object?> values,
  ) async {
    final idList = ids.toList(growable: false);
    if (idList.isEmpty) return;
    final db = await _dbHelper.db;
    await db.update(
      table,
      values,
      where: 'id IN (${List.filled(idList.length, '?').join(', ')})',
      whereArgs: idList,
    );
  }

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

  Future<Set<String>> _tableColumns(DatabaseExecutor db, String table) async {
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

  Map<String, dynamic> _normalizeRemoteRow(
    String table,
    Map<String, dynamic> row,
  ) {
    switch (table) {
      case reportsTable:
        return LabAnalysisReportModel.fromMap(row).toMap();
      case groupsTable:
        return LabAnalysisGroupModel.fromMap(row).toMap();
      case rowsTable:
        return LabAnalysisRowModel.fromMap(row).toMap();
      default:
        throw ArgumentError.value(table, 'table');
    }
  }

  void _assertSyncTable(String table) {
    if (!syncTables.contains(table)) {
      throw ArgumentError.value(table, 'table', 'Unsupported lab sync table');
    }
  }
}
