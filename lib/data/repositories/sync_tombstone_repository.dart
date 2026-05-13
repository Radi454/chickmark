import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/panel_sample_schema.dart';
import '../models/sync_tombstone_model.dart';

class SyncTombstoneRepository {
  SyncTombstoneRepository({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  final DatabaseHelper _dbHelper;

  static const tableName = 'sync_tombstones';

  static const baseDeleteOrder = [
    'sample_house_details',
    'sample_machine_details',
    'sample_batch_details',
    'sample_timing_details',
    'sample_records',
    'photos',
    'audits',
    'audit_sessions',
    'flocks',
    'hatcheries',
    'customers',
  ];

  static List<String> get deleteOrder {
    final panelSamples = PanelSampleSchema.panels
        .map((panel) => panel.sampleTableName)
        .toList();
    final panels = PanelSampleSchema.panels
        .map((panel) => panel.tableName)
        .toList();
    return [...panelSamples, ...panels, ...baseDeleteOrder];
  }

  Future<List<SyncTombstone>> getPendingDeletes() async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      tableName,
      where: 'syncedAt IS NULL',
      orderBy: 'createdAt ASC',
    );
    return rows.map((row) => SyncTombstone.fromMap(Map.from(row))).toList();
  }

  Future<void> markSynced(String id) async {
    final db = await _dbHelper.db;
    await db.update(
      tableName,
      {'syncedAt': DateTime.now().toIso8601String(), 'lastError': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markFailed(String id, Object error) async {
    final db = await _dbHelper.db;
    await db.update(
      tableName,
      {'lastError': error.toString()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> upsertRemoteTombstone(Map<String, dynamic> row) async {
    final db = await _dbHelper.db;
    final tombstone = SyncTombstone.fromMap(row);
    final existing = await db.query(
      tableName,
      where: 'id = ? AND syncedAt IS NULL',
      whereArgs: [tombstone.id],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    await db.insert(
      tableName,
      tombstone
          .copyWith(syncedAt: tombstone.syncedAt ?? DateTime.now())
          .toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> applyRemoteDeletes() async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      tableName,
      where: 'syncedAt IS NOT NULL',
      orderBy: 'deletedAt ASC',
    );
    final tombstones = rows
        .map((row) => SyncTombstone.fromMap(Map.from(row)))
        .toList();
    if (tombstones.isEmpty) return;
    await db.transaction<void>((txn) async {
      for (final table in deleteOrder) {
        if (!await _tableExists(txn, table)) continue;
        final ids = tombstones
            .where((tombstone) => tombstone.tableName == table)
            .map((tombstone) => tombstone.rowId)
            .toSet();
        for (final id in ids) {
          await deleteRow(txn, table, id);
        }
      }
    });
  }

  Future<void> queueDelete(String deletedTableName, String rowId) async {
    final db = await _dbHelper.db;
    await queueDeleteWithExecutor(db, deletedTableName, rowId);
  }

  static Future<void> queueDeleteWithExecutor(
    DatabaseExecutor executor,
    String deletedTableName,
    Object? rowId,
  ) async {
    final id = rowId?.toString();
    if (id == null || id.isEmpty) return;
    final now = DateTime.now();
    final tombstone = SyncTombstone(
      id: SyncTombstone.makeId(deletedTableName, id),
      tableName: deletedTableName,
      rowId: id,
      deletedAt: now,
      createdAt: now,
    );
    await executor.insert(
      tableName,
      tombstone.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> queueDeletesWithExecutor(
    DatabaseExecutor executor,
    String deletedTableName,
    Iterable<Object?> rowIds,
  ) async {
    for (final rowId in rowIds) {
      await queueDeleteWithExecutor(executor, deletedTableName, rowId);
    }
  }

  static Future<void> deleteRow(
    DatabaseExecutor executor,
    String deletedTableName,
    Object? rowId,
  ) async {
    final id = rowId?.toString();
    if (id == null || id.isEmpty) return;
    await executor.delete(
      deletedTableName,
      where: '${idColumnForTable(deletedTableName)} = ?',
      whereArgs: [id],
    );
  }

  static String idColumnForTable(String deletedTableName) {
    if (deletedTableName.startsWith('sample_') &&
        deletedTableName.endsWith('_details')) {
      return 'sampleRecordId';
    }
    if (deletedTableName.endsWith('_samples')) return 'id';
    return 'id';
  }

  static Future<bool> _tableExists(
    DatabaseExecutor executor,
    String table,
  ) async {
    final rows = await executor.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }
}
