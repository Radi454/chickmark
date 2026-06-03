import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/bmk_breed_model.dart';
import '../models/bmk_egg_breakout_model.dart';

class BmkRepository {
  final DatabaseHelper dbHelper;

  BmkRepository({DatabaseHelper? dbHelper})
    : dbHelper = dbHelper ?? DatabaseHelper();

  Future<List<int>> getBreedAges(String breed) async {
    final db = await dbHelper.db;
    final results = await db.rawQuery(
      '''
      SELECT DISTINCT ageWeek
      FROM bmk_breeds
      WHERE breed = ?
      ORDER BY ageWeek ASC
      ''',
      [breed],
    );
    return results.map((row) => row['ageWeek'] as int).toList();
  }

  Future<BmkBreedModel?> getBreedBenchmark(String breed, int ageWeek) async {
    final db = await dbHelper.db;
    final results = await db.query(
      'bmk_breeds',
      where: 'breed = ? AND ageWeek = ?',
      whereArgs: [breed, ageWeek],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return BmkBreedModel.fromMap(results.first);
  }

  Future<List<int>> getEggBreakoutAges() async {
    final db = await dbHelper.db;
    final results = await db.rawQuery(
      'SELECT DISTINCT ageWeek FROM bmk_egg_breakout ORDER BY ageWeek ASC',
    );
    return results.map((row) => row['ageWeek'] as int).toList();
  }

  Future<BmkEggBreakoutModel?> getEggBreakoutBenchmark(int ageWeek) async {
    final db = await dbHelper.db;
    final results = await db.query(
      'bmk_egg_breakout',
      where: 'ageWeek = ?',
      whereArgs: [ageWeek],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return BmkEggBreakoutModel.fromMap(results.first);
  }

  Future<void> upsertBmkBreed(Map<String, dynamic> row) async {
    final db = await dbHelper.db;
    final columns = await _tableColumns(db, 'bmk_breeds');
    final normalized = _filterColumns(_normalizeRow(row), columns);
    normalized['id'] ??= '${normalized['breed']}-${normalized['ageWeek']}';
    await db.insert(
      'bmk_breeds',
      normalized,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertBmkEggBreakout(Map<String, dynamic> row) async {
    final db = await dbHelper.db;
    final columns = await _tableColumns(db, 'bmk_egg_breakout');
    final normalized = _filterColumns(_normalizeRow(row), columns);
    normalized['id'] ??= 'eb-${normalized['ageWeek']}';
    await db.insert(
      'bmk_egg_breakout',
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

  Map<String, dynamic> _normalizeRow(Map<String, dynamic> row) {
    final normalized = <String, dynamic>{};
    for (final entry in row.entries) {
      normalized[_camelize(entry.key)] = entry.value;
    }
    _copyAlias(normalized, from: 'ageWeeks', to: 'ageWeek');
    _copyAlias(normalized, from: 'pippedExternalPct', to: 'externalPipPct');
    return normalized;
  }

  void _copyAlias(
    Map<String, dynamic> row, {
    required String from,
    required String to,
  }) {
    if (!row.containsKey(to) && row.containsKey(from)) {
      row[to] = row[from];
    }
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
