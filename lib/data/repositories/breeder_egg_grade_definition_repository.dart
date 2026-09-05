import '../database/database_helper.dart';
import '../models/breeder_egg_grade_definition_model.dart';

/// Read access to `breeder_egg_grade_definitions` (breeder-flock-performance
/// ticket 10). This table is system-defined reference data, seeded by
/// `seedBreederEggGradeDefinitions` — this repository has no write methods,
/// mirroring how `BreederBenchmarkRepository` only ever reads published
/// benchmark data.
class BreederEggGradeDefinitionRepository {
  BreederEggGradeDefinitionRepository({DatabaseHelper? dbHelper})
    : dbHelper = dbHelper ?? DatabaseHelper();

  final DatabaseHelper dbHelper;

  static const table = 'breeder_egg_grade_definitions';

  /// Every active grade, ordered by [BreederEggGradeDefinition.priority]
  /// ascending (highest priority first) — the order
  /// `BreederEggProductionService.resolveHighestPriorityGrade` and the
  /// entry screen both rely on.
  Future<List<BreederEggGradeDefinition>> listActiveGrades() async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'isActive = 1',
      orderBy: 'priority ASC',
    );
    return rows.map(BreederEggGradeDefinition.fromMap).toList();
  }

  Future<BreederEggGradeDefinition?> getById(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return BreederEggGradeDefinition.fromMap(rows.first);
  }

  Future<BreederEggGradeDefinition?> getByCode(String code) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BreederEggGradeDefinition.fromMap(rows.first);
  }
}
