import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/hatchery_model.dart';
import 'sync_tombstone_repository.dart';

class HatcheryRepository {
  final DatabaseHelper dbHelper = DatabaseHelper();

  Future<void> insertHatchery(HatcheryModel hatchery) async {
    await dbHelper.assertForeignKeys(customerId: hatchery.customerId);
    final db = await dbHelper.db;
    await _upsertById(db, 'hatcheries', hatchery.toMap());
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
      hatchery.toMap(),
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
    await _upsertById(db, 'hatcheries', _normalize(row));
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
