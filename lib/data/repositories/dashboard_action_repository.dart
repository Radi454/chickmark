import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/dashboard_action_model.dart';
import 'sync_tombstone_repository.dart';

class DashboardActionRepository {
  DashboardActionRepository({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  final DatabaseHelper _dbHelper;

  Future<List<DashboardActionModel>> getForScope({
    required String customerId,
    required String hatcheryId,
    String? flockId,
  }) async {
    final db = await _dbHelper.db;
    final parts = <String>['customerId = ?', 'hatcheryId = ?'];
    final args = <Object?>[customerId, hatcheryId];
    if (flockId != null) {
      parts.add('flockId = ?');
      args.add(flockId);
    }
    final rows = await db.query(
      'dashboard_actions',
      where: parts.join(' AND '),
      whereArgs: args,
      orderBy: "CASE status WHEN 'resolved' THEN 1 ELSE 0 END, updatedAt DESC",
    );
    return rows.map(DashboardActionModel.fromMap).toList();
  }

  Future<void> save(DashboardActionModel action) async {
    await _dbHelper.assertForeignKeys(
      customerId: action.customerId,
      flockId: action.flockId,
      hatcheryId: action.hatcheryId,
    );
    final db = await _dbHelper.db;
    final now = DateTime.now().toUtc();
    final row = action
        .copyWith(
          updatedAt: now,
          syncStatus: 'pending',
          dirtyAt: now,
          syncError: null,
        )
        .toMap();
    await _upsert(db, row);
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.db;
    await db.transaction<void>((txn) async {
      await SyncTombstoneRepository.queueDeleteWithExecutor(
        txn,
        'dashboard_actions',
        id,
      );
      await txn.delete('dashboard_actions', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<DashboardActionModel>> getDirtyRows() async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'dashboard_actions',
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'dirtyAt ASC',
    );
    return rows.map(DashboardActionModel.fromMap).toList();
  }

  Future<Map<String, dynamic>?> getRowById(String id) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'dashboard_actions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<void> upsertRemoteRow(Map<String, dynamic> row) async {
    final action = DashboardActionModel.fromMap(row);
    final db = await _dbHelper.db;
    await _upsert(
      db,
      action
          .copyWith(
            syncStatus: 'synced',
            dirtyAt: null,
            lastSyncedAt: DateTime.now().toUtc(),
            syncError: null,
          )
          .toMap(),
    );
  }

  Future<void> markSynced(Iterable<String> ids) => _mark(ids, {
    'syncStatus': 'synced',
    'dirtyAt': null,
    'lastSyncedAt': DateTime.now().toUtc().toIso8601String(),
    'syncError': null,
  });

  Future<void> markFailed(Iterable<String> ids, Object error) =>
      _mark(ids, {'syncStatus': 'failed', 'syncError': error.toString()});

  Future<void> _mark(Iterable<String> ids, Map<String, Object?> values) async {
    final list = ids.toList(growable: false);
    if (list.isEmpty) return;
    final db = await _dbHelper.db;
    await db.update(
      'dashboard_actions',
      values,
      where: 'id IN (${List.filled(list.length, '?').join(', ')})',
      whereArgs: list,
    );
  }

  Future<void> _upsert(DatabaseExecutor db, Map<String, dynamic> row) async {
    final inserted = await db.insert(
      'dashboard_actions',
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (inserted != 0) return;
    await db.update(
      'dashboard_actions',
      row,
      where: 'id = ?',
      whereArgs: [row['id']],
    );
  }
}
