import '../database/database_helper.dart';
import '../models/breeder_isolation_area_model.dart';

/// CRUD access to `breeder_isolation_areas` (breeder-flock-performance
/// ticket 08). Each isolation area belongs to exactly one flock, and its
/// name is unique within that flock (case-insensitive) via a database
/// unique index — this repository does not re-check uniqueness itself; a
/// duplicate name insert/update surfaces as a `DatabaseException` from the
/// underlying insert/update, matching how `PoultryHierarchyRepository`
/// leaves house-belongs-to-flock enforcement to the database.
class BreederIsolationAreaRepository {
  BreederIsolationAreaRepository({DatabaseHelper? dbHelper})
    : dbHelper = dbHelper ?? DatabaseHelper();

  final DatabaseHelper dbHelper;

  static const table = 'breeder_isolation_areas';

  String _nowStamp() => DateTime.now().toIso8601String();

  Future<List<BreederIsolationArea>> listAreas(
    String flockId, {
    bool activeOnly = true,
  }) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: activeOnly ? 'flockId = ? AND isActive = 1' : 'flockId = ?',
      whereArgs: [flockId],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(BreederIsolationArea.fromMap).toList();
  }

  Future<BreederIsolationArea?> getById(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BreederIsolationArea.fromMap(rows.first);
  }

  /// Inserts or updates an isolation area, keyed by [area.id]. Validates the
  /// flock exists first, matching `PoultryHierarchyRepository.saveHouse`.
  Future<BreederIsolationArea> saveArea(BreederIsolationArea area) async {
    final db = await dbHelper.db;
    final flock = await db.query(
      'flocks',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [area.flockId],
      limit: 1,
    );
    if (flock.isEmpty) {
      throw ArgumentError.value(
        area.flockId,
        'flockId',
        'Flock does not exist',
      );
    }

    final now = _nowStamp();
    final existing = await getById(area.id);
    final row = {
      ...area.toMap(),
      'updatedAt': now,
      'syncStatus': 'pending',
      'dirtyAt': now,
    };

    if (existing == null) {
      await db.insert(table, {
        ...row,
        'createdAt': area.createdAt?.toUtc().toIso8601String() ?? now,
      });
      return area;
    }

    await db.update(table, row, where: 'id = ?', whereArgs: [area.id]);
    return area;
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
