import '../database/database_helper.dart';
import '../models/breeder_feed_entry_model.dart';

/// CRUD access to `breeder_feed_entries` (breeder-flock-performance ticket
/// 09). This repository only persists rows whose `feedKg` has already been
/// validated (non-negative) by `BreederBirdLedgerService` — it does not
/// itself validate, matching the "one tested domain service" rule in design
/// doc section 7.
///
/// A feed entry's location-belongs-to-flock is enforced by a database
/// trigger (`trg_breeder_feed_entries_location_scope_*`), and "exactly one
/// of house/isolation area" by a CHECK constraint, so persisting a row that
/// violates either surfaces as a `DatabaseException` from the underlying
/// insert/update.
class BreederFeedEntryRepository {
  BreederFeedEntryRepository({DatabaseHelper? dbHelper})
    : dbHelper = dbHelper ?? DatabaseHelper();

  final DatabaseHelper dbHelper;

  static const table = 'breeder_feed_entries';

  String _nowStamp() => DateTime.now().toIso8601String();

  /// The single feed-entry row identified by [id], or null if none exists
  /// — the lookup a post-approval correction path
  /// (`BreederBirdLedgerService.correctFeedEntry`, breeder-flock-performance
  /// ticket 12) needs.
  Future<BreederFeedEntry?> getById(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return BreederFeedEntry.fromMap(rows.first);
  }

  Future<List<BreederFeedEntry>> getForReport(String reportId) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'reportId = ?',
      whereArgs: [reportId],
      orderBy: 'houseId ASC, isolationAreaId ASC, sex ASC',
    );
    return rows.map(BreederFeedEntry.fromMap).toList();
  }

  Future<BreederFeedEntry?> getByReportHouseSex(
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
    return BreederFeedEntry.fromMap(rows.first);
  }

  /// The isolation-area counterpart of [getByReportHouseSex]. Kept as a
  /// separate, distinctly-named method (rather than a single method taking
  /// "either" id) so a caller that only ever wants a house row cannot
  /// accidentally be handed an isolation row and vice versa.
  Future<BreederFeedEntry?> getByReportIsolationAreaSex(
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
    return BreederFeedEntry.fromMap(rows.first);
  }

  /// Inserts or updates a feed entry, keyed by (reportId, location, sex)
  /// where location is whichever of houseId/isolationAreaId [entry] carries.
  /// [entry.id] is used verbatim on insert; on update, the existing row
  /// keeps its own id regardless of what [entry.id] carries, since the
  /// unique key is (reportId, location, sex), not id.
  Future<BreederFeedEntry> upsert(BreederFeedEntry entry) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    final existing = entry.isHouseEntry
        ? await getByReportHouseSex(entry.reportId, entry.houseId!, entry.sex)
        : await getByReportIsolationAreaSex(
            entry.reportId,
            entry.isolationAreaId!,
            entry.sex,
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
