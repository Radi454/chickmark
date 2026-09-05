import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/egg_batch_model.dart';

/// CRUD access to `egg_batches` (breeder-flock-performance ticket 14). This
/// repository only persists rows whose fields have already been validated
/// by `EggBatchDispatchService` — it does not itself validate, matching the
/// "one tested domain service" rule in design doc section 7.
class EggBatchRepository {
  EggBatchRepository({DatabaseHelper? dbHelper, Uuid uuid = const Uuid()})
    : dbHelper = dbHelper ?? DatabaseHelper(),
      _uuid = uuid;

  final DatabaseHelper dbHelper;
  final Uuid _uuid;

  static const table = 'egg_batches';

  String newId() => _uuid.v4();
  String _nowStamp() => DateTime.now().toIso8601String();

  Future<EggBatch?> getById(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return EggBatch.fromMap(rows.first);
  }

  Future<EggBatch?> getByFlockDateGrade(
    String flockId,
    DateTime collectionDate,
    String gradeId,
  ) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'flockId = ? AND collectionDate = ? AND gradeId = ?',
      whereArgs: [flockId, EggBatch.dateKey(collectionDate), gradeId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return EggBatch.fromMap(rows.first);
  }

  Future<List<EggBatch>> listForFlock(String flockId) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'flockId = ?',
      whereArgs: [flockId],
      orderBy: 'collectionDate DESC, id DESC',
    );
    return rows.map(EggBatch.fromMap).toList();
  }

  Future<EggBatch> insert(EggBatch batch) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    await db.insert(table, {
      ...batch.toMap(),
      'createdAt': now,
      'updatedAt': now,
      'syncStatus': 'pending',
      'dirtyAt': now,
    });
    return batch;
  }

  Future<void> update(EggBatch batch) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    await db.update(
      table,
      {...batch.toMap(), 'updatedAt': now, 'syncStatus': 'pending', 'dirtyAt': now},
      where: 'id = ?',
      whereArgs: [batch.id],
    );
  }

  String? _dirtyReadCutoff;

  Future<List<Map<String, dynamic>>> getDirtyRows() async {
    final db = await dbHelper.db;
    _dirtyReadCutoff = _nowStamp();
    final rows = await db.query(
      table,
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
      table,
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
      table,
      {'syncStatus': 'failed', 'syncError': error.toString()},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }
}

/// CRUD access to `egg_batch_house_sources` (breeder-flock-performance
/// ticket 14). A row's house-belongs-to-flock invariant is enforced by a
/// database trigger (`trg_egg_batch_house_sources_house_scope_*`), so
/// persisting a source whose house belongs to a different flock than its
/// batch surfaces as a `DatabaseException` from the underlying insert.
class EggBatchHouseSourceRepository {
  EggBatchHouseSourceRepository({DatabaseHelper? dbHelper, Uuid uuid = const Uuid()})
    : dbHelper = dbHelper ?? DatabaseHelper(),
      _uuid = uuid;

  final DatabaseHelper dbHelper;
  final Uuid _uuid;

  static const table = 'egg_batch_house_sources';

  String newId() => _uuid.v4();
  String _nowStamp() => DateTime.now().toIso8601String();

  Future<List<EggBatchHouseSource>> getForBatch(String batchId) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'batchId = ?',
      whereArgs: [batchId],
      orderBy: 'houseId ASC',
    );
    return rows.map(EggBatchHouseSource.fromMap).toList();
  }

  Future<EggBatchHouseSource> insert(EggBatchHouseSource source) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    await db.insert(table, {
      ...source.toMap(),
      'createdAt': now,
      'updatedAt': now,
      'syncStatus': 'pending',
      'dirtyAt': now,
    });
    return source;
  }

  String? _dirtyReadCutoff;

  Future<List<Map<String, dynamic>>> getDirtyRows() async {
    final db = await dbHelper.db;
    _dirtyReadCutoff = _nowStamp();
    final rows = await db.query(
      table,
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
      table,
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
      table,
      {'syncStatus': 'failed', 'syncError': error.toString()},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }
}
