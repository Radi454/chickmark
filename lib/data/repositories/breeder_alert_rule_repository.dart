import '../database/database_helper.dart';
import '../models/breeder_alert_models.dart';

/// Read-only access to `breeder_alert_rules` (breeder-flock-performance
/// ticket 17). There is deliberately no write method here, mirroring
/// `BreederBenchmarkRepository`: these rows are seeded reference data (see
/// `seedBreederAlertRules`) and client roles never create, edit, or delete
/// them.
class BreederAlertRuleRepository {
  BreederAlertRuleRepository({DatabaseHelper? dbHelper})
    : dbHelper = dbHelper ?? DatabaseHelper();
  final DatabaseHelper dbHelper;

  Future<List<BreederAlertRule>> getActiveRules() async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'breeder_alert_rules',
      where: 'isActive = 1',
      orderBy: 'metricCode ASC, scope ASC, periodType ASC',
    );
    return rows.map(BreederAlertRule.fromMap).toList();
  }

  Future<BreederAlertRule?> getById(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'breeder_alert_rules',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BreederAlertRule.fromMap(rows.first);
  }

  /// The single active rule matching [metricCode]/[scope]/[periodType]/
  /// [direction], or null when no such rule is seeded/active. Matches the
  /// unique index on `breeder_alert_rules`, so at most one row can ever
  /// match.
  Future<BreederAlertRule?> findRule({
    required String metricCode,
    required String scope,
    required String periodType,
    required String direction,
  }) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'breeder_alert_rules',
      where:
          'metricCode = ? AND scope = ? AND periodType = ? AND direction = ? '
          'AND isActive = 1',
      whereArgs: [metricCode, scope, periodType, direction],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BreederAlertRule.fromMap(rows.first);
  }
}
