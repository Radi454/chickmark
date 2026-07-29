import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/panel_sample_schema.dart';
import '../models/sync_tombstone_model.dart';
import 'performance_sync_repository.dart';

class SyncTombstoneRepository {
  SyncTombstoneRepository({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  final DatabaseHelper _dbHelper;

  static const tableName = 'sync_tombstones';

  static const baseDeleteOrder = [
    'photos',
    'dashboard_actions',
    'lab_analysis_rows',
    'lab_analysis_groups',
    'lab_analysis_reports',
    'audit_sessions',
    'govee_daily_captures',
    'flocks',
    'hatcheries',
    'customers',
  ];

  static List<String> get deleteOrder {
    final panels = PanelSampleSchema.panels
        .map((panel) => panel.tableName)
        .toList();
    return [
      ...panels,
      ...PerformanceSyncRepository.deleteOrder,
      ...baseDeleteOrder,
    ];
  }

  Future<List<SyncTombstone>> getPendingDeletes() async {
    final db = await _dbHelper.db;
    final columns = await _SyncTombstoneColumns.forExecutor(db);
    final rows = await db.query(
      tableName,
      where: '${columns.syncedAtReadExpression} IS NULL',
      orderBy: '${columns.createdAtReadExpression} ASC',
    );
    return rows.map((row) => SyncTombstone.fromMap(Map.from(row))).toList();
  }

  Future<void> markSynced(String id) async {
    final db = await _dbHelper.db;
    final columns = await _SyncTombstoneColumns.forExecutor(db);
    await db.update(
      tableName,
      columns.toSyncSuccessUpdateMap(DateTime.now()),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markFailed(String id, Object error) async {
    final db = await _dbHelper.db;
    final columns = await _SyncTombstoneColumns.forExecutor(db);
    await db.update(
      tableName,
      columns.toSyncFailureUpdateMap(error),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> upsertRemoteTombstone(Map<String, dynamic> row) async {
    final db = await _dbHelper.db;
    final columns = await _SyncTombstoneColumns.forExecutor(db);
    final tombstone = SyncTombstone.fromMap(row);
    final existing = await db.query(
      tableName,
      where: 'id = ? AND ${columns.syncedAtReadExpression} IS NULL',
      whereArgs: [tombstone.id],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    await db.insert(
      tableName,
      columns.toInsertMap(
        tombstone.copyWith(syncedAt: tombstone.syncedAt ?? DateTime.now()),
      ),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> applyRemoteDeletes() async {
    final db = await _dbHelper.db;
    final columns = await _SyncTombstoneColumns.forExecutor(db);
    final rows = await db.query(
      tableName,
      where: '${columns.syncedAtReadExpression} IS NOT NULL',
      orderBy: '${columns.deletedAtReadExpression} ASC',
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
    final columns = await _SyncTombstoneColumns.forExecutor(executor);
    await executor.insert(
      tableName,
      columns.toInsertMap(tombstone),
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

  static String idColumnForTable(String _) => 'id';

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

class _SyncTombstoneColumns {
  const _SyncTombstoneColumns(this._names);

  final Set<String> _names;

  static Future<_SyncTombstoneColumns> forExecutor(
    DatabaseExecutor executor,
  ) async {
    final rows = await executor.rawQuery(
      'PRAGMA table_info(${SyncTombstoneRepository.tableName})',
    );
    return _SyncTombstoneColumns(
      rows.map((row) => row['name']?.toString()).whereType<String>().toSet(),
    );
  }

  String get syncedAtReadExpression => _readExpression('syncedAt', 'synced_at');

  String get createdAtReadExpression =>
      _readExpression('createdAt', 'created_at');

  String get deletedAtReadExpression =>
      _readExpression('deletedAt', 'deleted_at');

  Map<String, dynamic> toInsertMap(SyncTombstone tombstone) {
    final map = <String, dynamic>{'id': tombstone.id};
    _addVariant(map, 'tableName', 'table_name', tombstone.tableName);
    _addVariant(map, 'rowId', 'row_id', tombstone.rowId);
    _addVariant(
      map,
      'deletedAt',
      'deleted_at',
      tombstone.deletedAt.toIso8601String(),
    );
    _addVariant(
      map,
      'createdAt',
      'created_at',
      tombstone.createdAt.toIso8601String(),
    );
    _addVariant(
      map,
      'syncedAt',
      'synced_at',
      tombstone.syncedAt?.toIso8601String(),
    );
    _addVariant(map, 'lastError', 'last_error', tombstone.lastError);
    return map;
  }

  Map<String, dynamic> toSyncSuccessUpdateMap(DateTime syncedAt) {
    final map = <String, dynamic>{};
    _addVariant(map, 'syncedAt', 'synced_at', syncedAt.toIso8601String());
    _addVariant(map, 'lastError', 'last_error', null);
    return map;
  }

  Map<String, dynamic> toSyncFailureUpdateMap(Object error) {
    final map = <String, dynamic>{};
    _addVariant(map, 'lastError', 'last_error', error.toString());
    return map;
  }

  String _readExpression(String camelCaseColumn, String snakeCaseColumn) {
    final hasCamelCase = _names.contains(camelCaseColumn);
    final hasSnakeCase = _names.contains(snakeCaseColumn);
    if (hasCamelCase && hasSnakeCase) {
      return 'COALESCE($camelCaseColumn, $snakeCaseColumn)';
    }
    if (hasCamelCase) return camelCaseColumn;
    if (hasSnakeCase) return snakeCaseColumn;
    return camelCaseColumn;
  }

  void _addVariant(
    Map<String, dynamic> map,
    String camelCaseColumn,
    String snakeCaseColumn,
    Object? value,
  ) {
    var wrote = false;
    if (_names.contains(camelCaseColumn)) {
      map[camelCaseColumn] = value;
      wrote = true;
    }
    if (_names.contains(snakeCaseColumn)) {
      map[snakeCaseColumn] = value;
      wrote = true;
    }
    if (!wrote) map[camelCaseColumn] = value;
  }
}
