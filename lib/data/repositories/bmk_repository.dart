import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/bmk_breed_model.dart';
import '../models/bmk_egg_breakout_model.dart';
import '../models/bmk_operational_standard_model.dart';

class BmkRepository {
  final DatabaseHelper dbHelper;

  BmkRepository({DatabaseHelper? dbHelper})
    : dbHelper = dbHelper ?? DatabaseHelper();

  static const _operationalTable = 'bmk_operational_standards';

  String _nowStamp() => DateTime.now().toIso8601String();

  /// dirtyAt value captured at the last getDirtyOperationalRows() call.
  /// markOperationalRowsSynced only clears rows whose dirtyAt is at or before
  /// this cutoff, so an edit landing while a push is in flight stays pending.
  String? _operationalDirtyReadCutoff;

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

  Future<List<BmkOperationalStandardModel>> getOperationalStandards({
    String? hatcheryId,
  }) async {
    final db = await dbHelper.db;
    final globalRows = await db.query(
      'bmk_operational_standards',
      where: 'hatcheryId IS NULL',
      orderBy: 'sortOrder ASC, metricLabel ASC',
    );
    final standards = {
      for (final row in globalRows)
        row['metricKey'] as String: BmkOperationalStandardModel.fromMap(row),
    };

    if (hatcheryId != null && hatcheryId.isNotEmpty) {
      final hatcheryRows = await db.query(
        'bmk_operational_standards',
        where: 'hatcheryId = ?',
        whereArgs: [hatcheryId],
        orderBy: 'sortOrder ASC, metricLabel ASC',
      );
      for (final row in hatcheryRows) {
        standards[row['metricKey'] as String] =
            BmkOperationalStandardModel.fromMap(row);
      }
    }

    final rows = standards.values.toList()
      ..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        if (byOrder != 0) return byOrder;
        return a.metricLabel.compareTo(b.metricLabel);
      });
    return rows;
  }

  Future<List<BmkOperationalHatcheryOption>> getOperationalHatcheries() async {
    final db = await dbHelper.db;
    final rows = await db.rawQuery('''
      SELECT h.id AS id, h.name AS hatcheryName, c.name AS customerName
      FROM hatcheries h
      LEFT JOIN customers c ON c.id = h.customerId
      ORDER BY c.name COLLATE NOCASE ASC, h.name COLLATE NOCASE ASC
      ''');
    return rows.map((row) {
      final hatcheryName = row['hatcheryName'] as String? ?? 'Hatchery';
      final customerName = row['customerName'] as String?;
      final label = customerName == null || customerName.isEmpty
          ? hatcheryName
          : '$customerName · $hatcheryName';
      return BmkOperationalHatcheryOption(
        id: row['id'] as String,
        label: label,
      );
    }).toList();
  }

  Future<void> upsertOperationalStandard(
    BmkOperationalStandardModel row,
  ) async {
    final db = await dbHelper.db;
    await db.insert(
      _operationalTable,
      {
        ...row.copyWith(updatedAt: _nowStamp()).toMap(),
        'syncStatus': 'pending',
        'dirtyAt': _nowStamp(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getDirtyOperationalRows() async {
    final db = await dbHelper.db;
    _operationalDirtyReadCutoff = _nowStamp();
    final rows = await db.query(
      _operationalTable,
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'dirtyAt ASC, id ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> markOperationalRowsSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await dbHelper.db;
    final cutoff = _operationalDirtyReadCutoff ?? _nowStamp();
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      _operationalTable,
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

  Future<void> markOperationalRowsFailed(
    List<String> ids,
    Object error,
  ) async {
    if (ids.isEmpty) return;
    final db = await dbHelper.db;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      _operationalTable,
      {'syncStatus': 'failed', 'syncError': error.toString()},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<String?> getOperationalRowSyncStatus(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      _operationalTable,
      columns: ['syncStatus'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['syncStatus'] as String?;
  }

  /// Apply one snake_case cloud row. Pulled rows are clean by definition, so
  /// the sync columns are reset rather than left at whatever the pull carried.
  Future<void> upsertOperationalStandardRow(Map<String, dynamic> row) async {
    final db = await dbHelper.db;
    final columns = await _tableColumns(db, _operationalTable);
    final normalized = _filterColumns(_normalizeRow(row), columns);
    normalized['syncStatus'] = 'synced';
    normalized['dirtyAt'] = null;
    normalized['lastSyncedAt'] = _nowStamp();
    normalized['syncError'] = null;
    await db.insert(
      _operationalTable,
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
