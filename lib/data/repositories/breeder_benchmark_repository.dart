import '../database/database_helper.dart';
import '../models/breeder_benchmark_models.dart';

/// Read-only access to the official breeder benchmark tables
/// (`breeder_metric_definitions`, `breeder_benchmark_profiles`,
/// `breeder_benchmark_values`). There is deliberately no write method here:
/// benchmark data enters the system only through the asset-file importer
/// (see lib/data/database/seeds/breeder_benchmark_seeds.dart), and published
/// profiles are additionally immutable at the database level.
class BreederBenchmarkRepository {
  BreederBenchmarkRepository({DatabaseHelper? dbHelper})
    : dbHelper = dbHelper ?? DatabaseHelper();
  final DatabaseHelper dbHelper;

  Future<List<BreederBenchmarkProfile>> getProfiles({
    bool activeOnly = true,
  }) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'breeder_benchmark_profiles',
      where: activeOnly ? "state = 'active'" : null,
      orderBy: 'company ASC, breed ASC, guideVersion ASC',
    );
    return rows.map(BreederBenchmarkProfile.fromMap).toList();
  }

  Future<BreederBenchmarkProfile?> getProfileById(String profileId) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'breeder_benchmark_profiles',
      where: 'id = ?',
      whereArgs: [profileId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BreederBenchmarkProfile.fromMap(rows.first);
  }

  Future<List<BreederMetricDefinition>> getMetricDefinitions() async {
    final db = await dbHelper.db;
    final rows = await db.query('breeder_metric_definitions', orderBy: 'label ASC');
    return rows.map(BreederMetricDefinition.fromMap).toList();
  }

  Future<Map<String, BreederMetricDefinition>> getMetricDefinitionsById() async {
    final defs = await getMetricDefinitions();
    return {for (final d in defs) d.id: d};
  }

  Future<List<BreederBenchmarkValue>> getValuesForProfile(
    String profileId,
  ) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'breeder_benchmark_values',
      where: 'profileId = ?',
      whereArgs: [profileId],
      orderBy: 'ageDays ASC, sex ASC',
    );
    return rows.map(BreederBenchmarkValue.fromMap).toList();
  }

  /// The active benchmark profile for a flock's breed, matched by
  /// normalizing both sides (case/space/hyphen-insensitive) since flock
  /// breed labels are stored without spaces (e.g. `Ross308`) while official
  /// profiles carry the breed-company's own spacing (e.g. `Ross 308`).
  /// Returns null when no active profile matches — callers must treat that
  /// as "no benchmark data available" rather than falling back to guessing.
  Future<BreederBenchmarkProfile?> getActiveProfileForBreed(
    String breed,
  ) async {
    final normalizedTarget = _normalizeBreed(breed);
    if (normalizedTarget.isEmpty) return null;
    final profiles = await getProfiles(activeOnly: true);
    for (final profile in profiles) {
      if (_normalizeBreed(profile.breed) == normalizedTarget) {
        return profile;
      }
    }
    return null;
  }

  String _normalizeBreed(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');
  }

  /// The official production week for [profileId] at the given [ageWeek],
  /// read directly from `breeder_benchmark_values.productionWeek` rather
  /// than derived by arithmetic. `productionWeek` is stored per metric row
  /// but is a property of age itself, so any matching row is sufficient —
  /// this picks the first one found. Returns null before/outside the
  /// profile's official production range.
  Future<int?> getOfficialProductionWeek({
    required String profileId,
    required int ageWeek,
  }) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'breeder_benchmark_values',
      columns: ['productionWeek'],
      where: 'profileId = ? AND ageWeek = ? AND productionWeek IS NOT NULL',
      whereArgs: [profileId, ageWeek],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['productionWeek'] as num?)?.toInt();
  }

  /// The official age (in weeks) at which [profileId]'s production range
  /// begins — i.e. the age of the guide's first production week
  /// (production week 1, the "5% production" milestone by Aviagen-style
  /// convention). Returns null if the profile has no production-week data
  /// at all.
  Future<int?> getOfficialProductionStartAgeWeek(String profileId) async {
    final db = await dbHelper.db;
    final rows = await db.rawQuery(
      'SELECT MIN(ageWeek) AS ageWeek FROM breeder_benchmark_values '
      'WHERE profileId = ? AND productionWeek IS NOT NULL',
      [profileId],
    );
    if (rows.isEmpty) return null;
    return (rows.first['ageWeek'] as num?)?.toInt();
  }
}
