import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/panel_sample_model.dart';
import '../models/panel_sample_schema.dart';

class PanelSampleRepository {
  PanelSampleRepository({DatabaseHelper? databaseHelper})
    : _databaseHelper = databaseHelper ?? DatabaseHelper();

  final DatabaseHelper _databaseHelper;

  Future<void> savePanelWithSamples({
    required PanelRecord panel,
    required List<PanelSampleRecord> samples,
  }) async {
    final definition = PanelSampleSchema.byTable(panel.tableName);
    _validatePanel(panel, definition);
    for (final sample in samples) {
      _validateSample(panel, definition, sample);
    }

    final database = await _databaseHelper.db;
    await database.transaction<void>((txn) async {
      await _upsertById(txn, definition.tableName, panel.toMap());
      await txn.delete(
        definition.sampleTableName,
        where: 'panelId = ?',
        whereArgs: [panel.id],
      );
      for (final sample in samples) {
        await _upsertById(txn, definition.sampleTableName, sample.toMap());
      }
    });
  }

  Future<List<Map<String, Object?>>> getPanelSamples({
    required String panelTable,
    required String panelId,
  }) async {
    final definition = PanelSampleSchema.byTable(panelTable);
    final database = await _databaseHelper.db;
    return database.query(
      definition.sampleTableName,
      where: 'panelId = ?',
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

  Future<List<Map<String, dynamic>>> getAllPanelSampleRows(
    String panelTable,
  ) async {
    final definition = PanelSampleSchema.byTable(panelTable);
    final database = await _databaseHelper.db;
    final rows = await database.query(
      definition.sampleTableName,
      orderBy: 'panelId ASC, sampleIndex ASC, createdAt ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>?> getRowById(String tableName, String id) async {
    _validateKnownTable(tableName);
    final database = await _databaseHelper.db;
    final rows = await database.query(
      tableName,
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
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    await _upsertById(database, definition.tableName, _normalizeRow(row));
  }

  Future<void> upsertPanelSampleRow(
    String sampleTableName,
    Map<String, dynamic> row,
  ) async {
    final definition = PanelSampleSchema.panels.firstWhere(
      (panel) => panel.sampleTableName == sampleTableName,
      orElse: () =>
          throw ArgumentError('Unknown panel sample table: $sampleTableName'),
    );
    final database = await _databaseHelper.db;
    await _upsertById(database, definition.sampleTableName, _normalizeRow(row));
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

  void _validatePanel(PanelRecord panel, PanelSampleDefinition definition) {
    final compareLayer = panel.compareLayer;
    if (compareLayer != null &&
        !definition.allowedLayers.contains(compareLayer)) {
      throw ArgumentError(
        '${definition.tableName} does not allow ${compareLayer.dbValue} comparison',
      );
    }
  }

  void _validateSample(
    PanelRecord panel,
    PanelSampleDefinition definition,
    PanelSampleRecord sample,
  ) {
    if (sample.panelId != panel.id) {
      throw ArgumentError(
        'Sample ${sample.id} belongs to ${sample.panelId}, not ${panel.id}',
      );
    }
    if (!definition.allowedLayers.contains(sample.scopeType)) {
      throw ArgumentError(
        '${definition.tableName} does not allow ${sample.scopeType.dbValue} samples',
      );
    }
    if (sample.scopeType == SamplingLayer.setterHatcher &&
        (_isBlank(sample.setterId) || _isBlank(sample.hatcherId))) {
      throw ArgumentError(
        'setter_hatcher samples require setterId and hatcherId',
      );
    }
  }

  bool _isBlank(String? value) => value == null || value.trim().isEmpty;

  void _validateKnownTable(String tableName) {
    for (final panel in PanelSampleSchema.panels) {
      if (panel.tableName == tableName || panel.sampleTableName == tableName) {
        return;
      }
    }
    throw ArgumentError('Unknown panel table: $tableName');
  }

  Map<String, dynamic> _normalizeRow(Map<String, dynamic> row) {
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
