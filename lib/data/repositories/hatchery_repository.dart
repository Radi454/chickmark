import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/hatchery_model.dart';
import 'sync_tombstone_repository.dart';

class HatcheryRepository {
  HatcheryRepository({DatabaseHelper? dbHelper})
    : dbHelper = dbHelper ?? DatabaseHelper();
  final DatabaseHelper dbHelper;

  static const _table = 'hatcheries';

  String _nowStamp() => DateTime.now().toIso8601String();

  /// dirtyAt value captured at the last getDirtyRows() call. markRowsSynced
  /// only clears rows whose dirtyAt is at or before this cutoff, so an edit
  /// landing while a push is in flight stays pending.
  String? _dirtyReadCutoff;

  Future<List<Map<String, dynamic>>> getDirtyRows() async {
    final db = await dbHelper.db;
    _dirtyReadCutoff = _nowStamp();
    final rows = await db.query(
      _table,
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'dirtyAt ASC, id ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> markRowsSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await dbHelper.db;
    final cutoff = _dirtyReadCutoff ?? _nowStamp();
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      _table,
      {
        'syncStatus': 'synced',
        'dirtyAt': null,
        'lastSyncedAt': _nowStamp(),
        'syncError': null,
      },
      where: 'id IN ($placeholders) AND (dirtyAt IS NULL OR dirtyAt <= ?)',
      whereArgs: [...ids, cutoff],
    );
  }

  Future<void> markRowsFailed(List<String> ids, Object error) async {
    if (ids.isEmpty) return;
    final db = await dbHelper.db;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      _table,
      {'syncStatus': 'failed', 'syncError': error.toString()},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<String?> getRowSyncStatus(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      _table,
      columns: ['syncStatus'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['syncStatus']?.toString();
  }

  Future<void> insertHatchery(HatcheryModel hatchery) async {
    await dbHelper.assertForeignKeys(customerId: hatchery.customerId);
    final db = await dbHelper.db;
    await _upsertById(db, 'hatcheries', {
      ...hatchery.toMap(),
      'syncStatus': 'pending',
      'dirtyAt': _nowStamp(),
    });
  }

  Future<List<HatcheryModel>> getHatcheriesByCustomer(String customerId) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'hatcheries',
      where: 'customerId = ?',
      whereArgs: [customerId],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(HatcheryModel.fromMap).toList();
  }

  Future<List<HatcheryModel>> getAllHatcheries() async {
    final db = await dbHelper.db;
    final rows = await db.query('hatcheries', orderBy: 'name COLLATE NOCASE');
    return rows.map(HatcheryModel.fromMap).toList();
  }

  Future<void> updateHatchery(HatcheryModel hatchery) async {
    final db = await dbHelper.db;
    await db.update(
      'hatcheries',
      {
        ...hatchery.toMap(),
        'syncStatus': 'pending',
        'dirtyAt': _nowStamp(),
      },
      where: 'id = ?',
      whereArgs: [hatchery.id],
    );
  }

  Future<void> deleteHatcheriesByCustomer(String customerId) async {
    final db = await dbHelper.db;
    await db.transaction<void>((txn) async {
      final rows = await txn.query(
        'hatcheries',
        columns: ['id'],
        where: 'customerId = ?',
        whereArgs: [customerId],
      );
      await SyncTombstoneRepository.queueDeletesWithExecutor(
        txn,
        'hatcheries',
        rows.map((row) => row['id']),
      );
      await txn.delete(
        'hatcheries',
        where: 'customerId = ?',
        whereArgs: [customerId],
      );
    });
  }

  Future<void> deleteHatchery(String id) async {
    final db = await dbHelper.db;
    await db.transaction<void>((txn) async {
      await SyncTombstoneRepository.queueDeleteWithExecutor(
        txn,
        'hatcheries',
        id,
      );
      await txn.delete('hatcheries', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> upsertHatchery(Map<String, dynamic> row) async {
    final db = await dbHelper.db;
    final normalized = _normalize(row)
      ..addAll({
        'syncStatus': 'synced',
        'dirtyAt': null,
        'lastSyncedAt': _nowStamp(),
        'syncError': null,
      });
    await _upsertById(db, 'hatcheries', normalized);
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

  Map<String, dynamic> _normalize(Map<String, dynamic> row) {
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
