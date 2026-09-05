import '../database/database_helper.dart';
import '../models/breeder_daily_report_model.dart';
import '../models/breeder_egg_production_entry_model.dart';

/// CRUD access to `breeder_egg_production_entries` (breeder-flock
/// -performance ticket 10). This repository only persists rows whose
/// `count` has already been validated (non-negative) by
/// `BreederEggProductionService` — it does not itself validate, matching
/// the "one tested domain service" rule in design doc section 7.
///
/// A production entry's location-belongs-to-flock is enforced by a database
/// trigger (`trg_breeder_egg_production_entries_location_scope_*`), and
/// "exactly one of house/isolation area" by a CHECK constraint, so
/// persisting a row that violates either surfaces as a `DatabaseException`
/// from the underlying insert/update.
class BreederEggProductionEntryRepository {
  BreederEggProductionEntryRepository({DatabaseHelper? dbHelper})
    : dbHelper = dbHelper ?? DatabaseHelper();

  final DatabaseHelper dbHelper;

  static const table = 'breeder_egg_production_entries';

  String _nowStamp() => DateTime.now().toIso8601String();

  /// The single production-entry row identified by [id], or null if none
  /// exists — the lookup a post-approval correction path
  /// (`BreederBirdLedgerService.correctEggProductionEntry`,
  /// breeder-flock-performance ticket 12) needs.
  Future<BreederEggProductionEntry?> getById(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return BreederEggProductionEntry.fromMap(rows.first);
  }

  Future<List<BreederEggProductionEntry>> getForReport(String reportId) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'reportId = ?',
      whereArgs: [reportId],
      orderBy: 'houseId ASC, isolationAreaId ASC, gradeId ASC',
    );
    return rows.map(BreederEggProductionEntry.fromMap).toList();
  }

  /// Total eggs counted under [gradeId] across every location on
  /// [reportId] (breeder-flock-performance ticket 11) — "today's
  /// production" for that grade, summed across houses and isolation areas
  /// alike, since the egg-inventory ledger tracks physical stock rather
  /// than house-scope performance ratios.
  Future<int> sumCountForReportAndGrade(String reportId, String gradeId) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      columns: ['count'],
      where: 'reportId = ? AND gradeId = ?',
      whereArgs: [reportId, gradeId],
    );
    var total = 0;
    for (final row in rows) {
      total += (row['count'] as num?)?.toInt() ?? 0;
    }
    return total;
  }

  /// Total eggs counted under [gradeId] for [flockId] across every report
  /// dated strictly before [beforeDate] (breeder-flock-performance ticket
  /// 11) — the production side of
  /// `BreederEggInventoryService.previousBalance`'s "prior ledger state"
  /// sum. Joins to `breeder_daily_reports` for flock/date scope since this
  /// table does not itself carry `flockId`/`reportDate`.
  Future<int> sumCountForFlockGradeBeforeDate({
    required String flockId,
    required String gradeId,
    required DateTime beforeDate,
  }) async {
    final db = await dbHelper.db;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(e.count), 0) AS total FROM $table e
      JOIN breeder_daily_reports r ON r.id = e.reportId
      WHERE r.flockId = ? AND e.gradeId = ? AND r.reportDate < ?
      ''',
      [flockId, gradeId, BreederDailyReport.dateKey(beforeDate)],
    );
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<BreederEggProductionEntry?> getByReportHouseGrade(
    String reportId,
    String houseId,
    String gradeId,
  ) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'reportId = ? AND houseId = ? AND gradeId = ?',
      whereArgs: [reportId, houseId, gradeId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BreederEggProductionEntry.fromMap(rows.first);
  }

  /// The isolation-area counterpart of [getByReportHouseGrade]. Kept as a
  /// separate, distinctly-named method (rather than a single method taking
  /// "either" id) so a caller that only ever wants a house row cannot
  /// accidentally be handed an isolation row and vice versa.
  Future<BreederEggProductionEntry?> getByReportIsolationAreaGrade(
    String reportId,
    String isolationAreaId,
    String gradeId,
  ) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'reportId = ? AND isolationAreaId = ? AND gradeId = ?',
      whereArgs: [reportId, isolationAreaId, gradeId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BreederEggProductionEntry.fromMap(rows.first);
  }

  /// Inserts or updates a production entry, keyed by
  /// (reportId, location, gradeId) where location is whichever of
  /// houseId/isolationAreaId [entry] carries. [entry.id] is used verbatim on
  /// insert; on update, the existing row keeps its own id regardless of
  /// what [entry.id] carries, since the unique key is
  /// (reportId, location, gradeId), not id.
  Future<BreederEggProductionEntry> upsert(
    BreederEggProductionEntry entry,
  ) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    final existing = entry.isHouseEntry
        ? await getByReportHouseGrade(
            entry.reportId,
            entry.houseId!,
            entry.gradeId,
          )
        : await getByReportIsolationAreaGrade(
            entry.reportId,
            entry.isolationAreaId!,
            entry.gradeId,
          );

    if (existing == null) {
      final toInsert = entry;
      await db.insert(table, {
        ...toInsert.toMap(),
        'createdAt': now,
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
      });
      return toInsert;
    }

    final updated = entry.copyWith(id: existing.id);
    await db.update(
      table,
      {
        ...updated.toMap(),
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
      },
      where: 'id = ?',
      whereArgs: [existing.id],
    );
    return updated;
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
