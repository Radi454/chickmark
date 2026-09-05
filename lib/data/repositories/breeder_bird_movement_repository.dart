import '../database/database_helper.dart';
import '../models/breeder_bird_movement_model.dart';

/// CRUD access to `breeder_bird_movements` (breeder-flock-performance
/// ticket 07; extended by ticket 08 for isolation-area locations). This
/// repository only persists rows whose `opening`/`closing` have already been
/// computed by `BreederBirdLedgerService` — it does not itself compute the
/// ledger arithmetic, matching the "one tested domain service" rule in
/// design doc section 7.
///
/// A movement's location-belongs-to-flock is enforced by a database trigger
/// (`trg_breeder_bird_movements_location_scope_*`), and "exactly one of
/// house/isolation area" by a CHECK constraint, so persisting a row that
/// violates either surfaces as a `DatabaseException` from the underlying
/// insert/update.
class BreederBirdMovementRepository {
  BreederBirdMovementRepository({DatabaseHelper? dbHelper})
    : dbHelper = dbHelper ?? DatabaseHelper();

  final DatabaseHelper dbHelper;

  static const table = 'breeder_bird_movements';

  String _nowStamp() => DateTime.now().toIso8601String();

  /// The single movement row identified by [id], or null if none exists —
  /// the lookup a post-approval correction path
  /// (`BreederBirdLedgerService.correctMovement`, breeder-flock-performance
  /// ticket 12) needs to find the row it is about to correct, since
  /// corrections address a specific already-recorded row rather than a
  /// (report, location, sex) key.
  Future<BreederBirdMovement?> getById(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return BreederBirdMovement.fromMap(rows.first);
  }

  Future<List<BreederBirdMovement>> getForReport(String reportId) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'reportId = ?',
      whereArgs: [reportId],
      orderBy: 'houseId ASC, isolationAreaId ASC, sex ASC',
    );
    return rows.map(BreederBirdMovement.fromMap).toList();
  }

  Future<BreederBirdMovement?> getByReportHouseSex(
    String reportId,
    String houseId,
    String sex,
  ) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'reportId = ? AND houseId = ? AND sex = ?',
      whereArgs: [reportId, houseId, sex],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BreederBirdMovement.fromMap(rows.first);
  }

  /// The isolation-area counterpart of [getByReportHouseSex]. Kept as a
  /// separate, distinctly-named method (rather than a single method taking
  /// "either" id) so a caller that only ever wants a house row cannot
  /// accidentally be handed an isolation row and vice versa.
  Future<BreederBirdMovement?> getByReportIsolationAreaSex(
    String reportId,
    String isolationAreaId,
    String sex,
  ) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'reportId = ? AND isolationAreaId = ? AND sex = ?',
      whereArgs: [reportId, isolationAreaId, sex],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BreederBirdMovement.fromMap(rows.first);
  }

  /// Inserts or updates a movement row, keyed by (reportId, location, sex)
  /// where location is whichever of houseId/isolationAreaId [movement]
  /// carries. [movement.id] is used verbatim on insert; on update, the
  /// existing row keeps its own id regardless of what [movement.id]
  /// carries, since the unique key is (reportId, location, sex), not id.
  Future<BreederBirdMovement> upsert(BreederBirdMovement movement) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    final existing = movement.isHouseMovement
        ? await getByReportHouseSex(
            movement.reportId,
            movement.houseId!,
            movement.sex,
          )
        : await getByReportIsolationAreaSex(
            movement.reportId,
            movement.isolationAreaId!,
            movement.sex,
          );

    if (existing == null) {
      final toInsert = movement;
      await db.insert(table, {
        ...toInsert.toMap(),
        'createdAt': now,
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
      });
      return toInsert;
    }

    final updated = movement.copyWith(id: existing.id);
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

  /// The closing balance of the most recent report strictly before
  /// [beforeDate] for [flockId]/[houseId]/[sex], or null if none exists —
  /// callers fall back to the house's opening counts in that case (design
  /// doc section 6: "opening balance derives from the previous ledger
  /// state, or the house opening counts on the first day").
  Future<int?> previousClosing({
    required String flockId,
    required String houseId,
    required String sex,
    required DateTime beforeDate,
  }) async {
    final db = await dbHelper.db;
    final dateKey = DateTime.utc(
      beforeDate.year,
      beforeDate.month,
      beforeDate.day,
    ).toIso8601String().substring(0, 10);
    final rows = await db.rawQuery(
      '''
      SELECT m.closing AS closing
      FROM breeder_bird_movements m
      JOIN breeder_daily_reports r ON r.id = m.reportId
      WHERE r.flockId = ? AND m.houseId = ? AND m.sex = ? AND r.reportDate < ?
      ORDER BY r.reportDate DESC
      LIMIT 1
      ''',
      [flockId, houseId, sex, dateKey],
    );
    if (rows.isEmpty) return null;
    return (rows.first['closing'] as num?)?.toInt();
  }

  /// The isolation-area counterpart of [previousClosing]. Unlike a house, an
  /// isolation area has no "opening count" of its own to fall back to —
  /// birds only ever arrive there via a transfer — so a null result here
  /// means the area's balance is 0, not "unknown", and callers do not fall
  /// back to any other source.
  Future<int?> previousClosingForIsolationArea({
    required String flockId,
    required String isolationAreaId,
    required String sex,
    required DateTime beforeDate,
  }) async {
    final db = await dbHelper.db;
    final dateKey = DateTime.utc(
      beforeDate.year,
      beforeDate.month,
      beforeDate.day,
    ).toIso8601String().substring(0, 10);
    final rows = await db.rawQuery(
      '''
      SELECT m.closing AS closing
      FROM breeder_bird_movements m
      JOIN breeder_daily_reports r ON r.id = m.reportId
      WHERE r.flockId = ? AND m.isolationAreaId = ? AND m.sex = ? AND r.reportDate < ?
      ORDER BY r.reportDate DESC
      LIMIT 1
      ''',
      [flockId, isolationAreaId, sex, dateKey],
    );
    if (rows.isEmpty) return null;
    return (rows.first['closing'] as num?)?.toInt();
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
