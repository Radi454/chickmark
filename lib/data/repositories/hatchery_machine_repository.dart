import '../database/database_helper.dart';
import '../models/hatchery_machine_model.dart';

class HatcheryMachineRepository {
  HatcheryMachineRepository({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  static const tableName = 'hatchery_machines';

  final DatabaseHelper _dbHelper;
  String? _dirtyReadCutoff;

  String _nowStamp() => DateTime.now().toUtc().toIso8601String();

  Future<List<HatcheryMachineModel>> getByHatchery(
    String hatcheryId, {
    String? kind,
  }) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      tableName,
      where: kind == null ? 'hatcheryId = ?' : 'hatcheryId = ? AND kind = ?',
      whereArgs: kind == null ? [hatcheryId] : [hatcheryId, kind],
      orderBy: 'code COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(HatcheryMachineModel.fromMap).toList(growable: false);
  }

  Future<HatcheryMachineModel?> getById(String id) async {
    final row = await getRowById(id);
    return row == null ? null : HatcheryMachineModel.fromMap(row);
  }

  Future<Map<String, dynamic>?> getRowById(String id) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.single);
  }

  Future<void> saveMachine(HatcheryMachineModel machine) async {
    final db = await _dbHelper.db;
    await db.transaction<void>((txn) async {
      final hatchery = await txn.query(
        'hatcheries',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [machine.hatcheryId],
        limit: 1,
      );
      if (hatchery.isEmpty) {
        throw ArgumentError.value(
          machine.hatcheryId,
          'hatcheryId',
          'Hatchery does not exist',
        );
      }
      final existing = await txn.query(
        tableName,
        columns: ['hatcheryId', 'kind'],
        where: 'id = ?',
        whereArgs: [machine.id],
        limit: 1,
      );
      if (existing.isNotEmpty &&
          (existing.single['hatcheryId'] != machine.hatcheryId ||
              existing.single['kind'] != machine.kind)) {
        throw ArgumentError(
          'A registered machine cannot be moved to another hatchery or kind.',
        );
      }
      final duplicates = await txn.query(
        tableName,
        columns: ['id'],
        where:
            'hatcheryId = ? AND kind = ? AND UPPER(TRIM(code)) = ? AND id <> ?',
        whereArgs: [machine.hatcheryId, machine.kind, machine.code, machine.id],
        limit: 1,
      );
      if (duplicates.isNotEmpty) {
        throw ArgumentError('Machine code already exists for this hatchery.');
      }
      final now = _nowStamp();
      final row = {
        ...machine.toMap(),
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
        'lastSyncedAt': null,
        'syncError': null,
      };
      if (existing.isEmpty) {
        await txn.insert(tableName, {
          ...row,
          'createdAt': machine.createdAt?.toIso8601String() ?? now,
        });
      } else {
        await txn.update(
          tableName,
          row,
          where: 'id = ?',
          whereArgs: [machine.id],
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> getDirtyRows() async {
    final db = await _dbHelper.db;
    _dirtyReadCutoff = _nowStamp();
    final rows = await db.query(
      tableName,
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'dirtyAt ASC, id ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> markRowsSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await _dbHelper.db;
    final cutoff = _dirtyReadCutoff ?? _nowStamp();
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      tableName,
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
    final db = await _dbHelper.db;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      tableName,
      {'syncStatus': 'failed', 'syncError': error.toString()},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<String?> getRowSyncStatus(String id) async {
    final row = await getRowById(id);
    return row?['syncStatus']?.toString();
  }

  Future<void> upsertRemoteRow(Map<String, dynamic> row) async {
    final machine = HatcheryMachineModel.fromMap(_camelizeMap(row));
    final db = await _dbHelper.db;
    final existing = await db.query(
      tableName,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [machine.id],
      limit: 1,
    );
    final now = _nowStamp();
    final values = {
      ...machine.toMap(),
      'createdAt': machine.createdAt?.toIso8601String() ?? now,
      'updatedAt': machine.updatedAt?.toIso8601String() ?? now,
      'syncStatus': 'synced',
      'dirtyAt': null,
      'lastSyncedAt': now,
      'syncError': null,
    };
    if (existing.isEmpty) {
      await db.insert(tableName, values);
    } else {
      await db.update(
        tableName,
        values,
        where: 'id = ?',
        whereArgs: [machine.id],
      );
    }
  }

  Map<String, dynamic> _camelizeMap(Map<String, dynamic> row) => row.map(
    (key, value) => MapEntry(
      key.contains('_')
          ? key.split('_').first +
                key.split('_').skip(1).map((part) {
                  if (part.isEmpty) return part;
                  return part[0].toUpperCase() + part.substring(1);
                }).join()
          : key,
      value,
    ),
  );
}
