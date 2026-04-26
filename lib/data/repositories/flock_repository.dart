import '../models/flock_model.dart';
import '../database/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class FlockRepository {
  final dbHelper = DatabaseHelper();

  Future<void> insertFlock(FlockModel flock) async {
    final db = await dbHelper.db;
    await db.insert(
      'flocks',
      flock.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<FlockModel>> getFlocksByCustomer(String customerId) async {
    final db = await dbHelper.db;
    final result = await db.query(
      'flocks',
      where: 'customerId = ?',
      whereArgs: [customerId],
    );
    return result.map((e) => FlockModel.fromMap(e)).toList();
  }

  Future<List<FlockModel>> getAllFlocks() async {
    final db = await dbHelper.db;
    final result = await db.query('flocks', orderBy: 'entryDate DESC');
    return result.map((e) => FlockModel.fromMap(e)).toList();
  }

  Future<FlockModel?> getFlockById(String id) async {
    final db = await dbHelper.db;
    final result = await db.query('flocks', where: 'id = ?', whereArgs: [id]);
    if (result.isNotEmpty) {
      return FlockModel.fromMap(result.first);
    }
    return null;
  }

  Future<void> updateFlock(FlockModel flock) async {
    final db = await dbHelper.db;
    await db.update(
      'flocks',
      flock.toMap(),
      where: 'id = ?',
      whereArgs: [flock.id],
    );
  }

  Future<void> deleteFlock(String id) async {
    final db = await dbHelper.db;
    await db.delete('flocks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteFlocksByCustomer(String customerId) async {
    final db = await dbHelper.db;
    await db.delete('flocks', where: 'customerId = ?', whereArgs: [customerId]);
  }

  Future<void> upsertFlock(Map<String, dynamic> row) async {
    final db = await dbHelper.db;
    final columns = await _tableColumns(db, 'flocks');
    final normalized = _filterColumns(_normalizeFlockRow(row), columns);
    await db.insert(
      'flocks',
      normalized,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Set<String>> _tableColumns(Database db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((row) => row['name'] as String).toSet();
  }

  Map<String, dynamic> _filterColumns(
    Map<String, dynamic> row,
    Set<String> columns,
  ) {
    return Map.fromEntries(
      row.entries.where((entry) {
        return columns.contains(entry.key);
      }),
    );
  }

  Map<String, dynamic> _normalizeFlockRow(Map<String, dynamic> row) {
    final normalized = <String, dynamic>{};
    for (final entry in row.entries) {
      normalized[_camelize(entry.key)] = entry.value;
    }
    return normalized;
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
