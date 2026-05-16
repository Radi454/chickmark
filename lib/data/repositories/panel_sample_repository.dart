import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/panel_sample_model.dart';
import '../models/panel_sample_schema.dart';
import 'sync_tombstone_repository.dart';

class PanelSampleRepository {
  PanelSampleRepository({DatabaseHelper? databaseHelper})
    : _databaseHelper = databaseHelper ?? DatabaseHelper();

  final DatabaseHelper _databaseHelper;

  Future<void> savePanelWithSamples({
    required PanelRecord panel,
    required List<PanelSampleRecord> samples,
  }) async {
    final definition = PanelSampleSchema.byTable(panel.tableName);
    _validatePanelRow(definition, panel.scopeType);
    for (final sample in samples) {
      _validatePanelRow(definition, sample.scopeType);
    }

    final database = await _databaseHelper.db;
    await database.transaction<void>((txn) async {
      if (samples.isEmpty) {
        await _upsertById(txn, definition.tableName, panel.toMap());
        return;
      }
      for (final sample in samples) {
        await _upsertById(
          txn,
          definition.tableName,
          _rowFromLegacySample(panel, sample),
        );
      }
    });
  }

  Future<void> upsertRow({
    required String tableName,
    required Map<String, Object?> row,
  }) async {
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    await _upsertById(database, definition.tableName, Map.of(row));
  }

  Future<List<Map<String, dynamic>>> getRowsBySessionId(
    String tableName,
    String sessionId,
  ) async {
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    final rows = await database.query(
      definition.tableName,
      where: 'sessionId = ?',
      whereArgs: [sessionId],
      orderBy: 'mode ASC, sampleIndex ASC, scopeLabel ASC, createdAt ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> getRowsBySessionIdAndMode(
    String tableName,
    String sessionId,
    String mode,
  ) async {
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    final rows = await database.query(
      definition.tableName,
      where: 'sessionId = ? AND mode = ?',
      whereArgs: [sessionId, mode],
      orderBy: 'sampleIndex ASC, scopeLabel ASC, createdAt ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> getComparisonRows(
    String tableName,
    String sessionId,
  ) {
    return getRowsBySessionIdAndMode(
      tableName,
      sessionId,
      PanelRecord.modeComparison,
    );
  }

  Future<void> deleteRowsBySessionId(String tableName, String sessionId) async {
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    await database.transaction<void>((txn) async {
      final rows = await txn.query(
        definition.tableName,
        columns: ['id'],
        where: 'sessionId = ?',
        whereArgs: [sessionId],
      );
      await SyncTombstoneRepository.queueDeletesWithExecutor(
        txn,
        definition.tableName,
        rows.map((row) => row['id']),
      );
      await txn.delete(
        definition.tableName,
        where: 'sessionId = ?',
        whereArgs: [sessionId],
      );
    });
  }

  Future<void> deleteRow(String tableName, String id) async {
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    await database.transaction<void>((txn) async {
      await SyncTombstoneRepository.queueDeletesWithExecutor(
        txn,
        definition.tableName,
        [id],
      );
      await txn.delete(definition.tableName, where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<Map<String, dynamic>>> getDashboardRows(
    String tableName, {
    String? customerId,
    String? flockId,
    int? limit,
  }) async {
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    final where = <String>[];
    final args = <Object?>[];
    if (customerId != null) {
      where.add('customerId = ?');
      args.add(customerId);
    }
    if (flockId != null) {
      where.add('flockId = ?');
      args.add(flockId);
    }
    final rows = await database.query(
      definition.tableName,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date DESC, updatedAt DESC',
      limit: limit,
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, Object?>>> getPanelSamples({
    required String panelTable,
    required String panelId,
  }) async {
    final definition = PanelSampleSchema.byTable(panelTable);
    final database = await _databaseHelper.db;
    return database.query(
      definition.tableName,
      where: 'id = ?',
      whereArgs: [panelId],
      orderBy: 'sampleIndex ASC, createdAt ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllPanelRows(String panelTable) async {
    final definition = PanelSampleSchema.byTable(panelTable);
    final database = await _databaseHelper.db;
    final rows = await database.query(
      definition.tableName,
      orderBy: 'createdAt ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  @Deprecated('Panel sample child tables were removed.')
  Future<List<Map<String, dynamic>>> getAllPanelSampleRows(
    String panelTable,
  ) async {
    return const [];
  }

  Future<Map<String, dynamic>?> getRowById(String tableName, String id) async {
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    final rows = await database.query(
      definition.tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<void> upsertPanelRow(
    String tableName,
    Map<String, dynamic> row,
  ) async {
    await upsertRow(tableName: tableName, row: _normalizeRow(row));
  }

  @Deprecated('Panel sample child tables were removed.')
  Future<void> upsertPanelSampleRow(
    String sampleTableName,
    Map<String, dynamic> row,
  ) async {}

  Future<void> _upsertById(
    DatabaseExecutor executor,
    String table,
    Map<String, Object?> row,
  ) async {
    final columns = await _tableColumns(executor, table);
    final filtered = Map<String, Object?>.fromEntries(
      _normalizeRow(row).entries.where((entry) => columns.contains(entry.key)),
    );
    if (filtered['id'] == null) return;
    final inserted = await executor.insert(
      table,
      filtered,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (inserted != 0) return;
    final updatedById = await executor.update(
      table,
      filtered,
      where: 'id = ?',
      whereArgs: [filtered['id']],
    );
    if (updatedById != 0) return;
    await _updateByPanelIdentity(executor, table, filtered);
  }

  Future<void> _updateByPanelIdentity(
    DatabaseExecutor executor,
    String table,
    Map<String, Object?> row,
  ) async {
    final sessionId = row['sessionId'];
    final mode = row['mode'];
    final scopeType = row['scopeType'];
    final scopeLabel = row['scopeLabel'];
    final sampleIndex = row['sampleIndex'];
    if (sessionId == null ||
        mode == null ||
        scopeType == null ||
        scopeLabel == null ||
        sampleIndex == null) {
      return;
    }

    final updateValues = Map<String, Object?>.from(row)..remove('id');
    if (updateValues.isEmpty) return;
    await executor.update(
      table,
      updateValues,
      where: '''
        sessionId = ?
        AND mode = ?
        AND scopeType = ?
        AND scopeLabel = ?
        AND sampleIndex = ?
        AND IFNULL(groupKey, '') = ?
      ''',
      whereArgs: [
        sessionId,
        mode,
        scopeType,
        scopeLabel,
        sampleIndex,
        row['groupKey'] ?? '',
      ],
    );
  }

  Map<String, Object?> _rowFromLegacySample(
    PanelRecord panel,
    PanelSampleRecord sample,
  ) {
    return {
      ...panel.toMap(),
      'id': sample.id,
      'mode': panel.mode,
      'scopeType': sample.scopeType.dbValue,
      'scopeLabel': sample.scopeLabel,
      'sampleIndex': sample.sampleIndex,
      'sampleSize': sample.sampleSize,
      'notes': sample.notes ?? panel.notes,
      'createdAt': sample.createdAt.toUtc().toIso8601String(),
      'updatedAt': sample.updatedAt.toUtc().toIso8601String(),
    };
  }

  void _validatePanelRow(
    PanelSampleDefinition definition,
    SamplingLayer scopeType,
  ) {
    if (!definition.allowedLayers.contains(scopeType)) {
      throw ArgumentError(
        '${definition.tableName} does not allow ${scopeType.dbValue} rows',
      );
    }
  }

  Future<Set<String>> _tableColumns(
    DatabaseExecutor executor,
    String table,
  ) async {
    final rows = await executor.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name'] as String).toSet();
  }

  Map<String, Object?> _normalizeRow(Map<dynamic, dynamic> row) {
    return row.map((key, value) => MapEntry(_camelize(key.toString()), value));
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
