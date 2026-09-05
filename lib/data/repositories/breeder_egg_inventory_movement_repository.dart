import '../database/database_helper.dart';
import '../models/breeder_daily_report_model.dart';
import '../models/breeder_egg_inventory_movement_model.dart';

/// CRUD access to `breeder_egg_inventory_movements` (breeder-flock
/// -performance ticket 11). This repository only persists rows whose fields
/// have already been validated by `BreederEggInventoryService` — it does not
/// itself validate, matching the "one tested domain service" rule in design
/// doc section 7.
///
/// [upsert] is only ever used for the four plain kinds (hatchery dispatch,
/// sale, kitchen, gift) while a report is still Draft — the partial unique
/// index (`idx_breeder_egg_inventory_movements_unique`) enforces one row per
/// (report, grade, kind) for those. Adjustments and reversals always go
/// through [insertAppend], which never updates an existing row: the ledger
/// is append-only for both (design section 8 and 14).
class BreederEggInventoryMovementRepository {
  BreederEggInventoryMovementRepository({DatabaseHelper? dbHelper})
    : dbHelper = dbHelper ?? DatabaseHelper();

  final DatabaseHelper dbHelper;

  static const table = 'breeder_egg_inventory_movements';

  String _nowStamp() => DateTime.now().toIso8601String();

  Future<List<BreederEggInventoryMovement>> getForReport(
    String reportId,
  ) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'reportId = ?',
      whereArgs: [reportId],
      orderBy: 'gradeId ASC, kind ASC, createdAt ASC',
    );
    return rows.map(BreederEggInventoryMovement.fromMap).toList();
  }

  Future<List<BreederEggInventoryMovement>> getForReportAndGrade(
    String reportId,
    String gradeId,
  ) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'reportId = ? AND gradeId = ?',
      whereArgs: [reportId, gradeId],
      orderBy: 'kind ASC, createdAt ASC',
    );
    return rows.map(BreederEggInventoryMovement.fromMap).toList();
  }

  /// The one editable-while-Draft row for (report, grade, kind), or null if
  /// none has been recorded yet. Never matches an adjustment or a reversal
  /// row (see class doc comment) — those are never looked up for editing.
  Future<BreederEggInventoryMovement?> getEditableRow(
    String reportId,
    String gradeId,
    String kind,
  ) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where:
          'reportId = ? AND gradeId = ? AND kind = ? AND reversedMovementId IS NULL',
      whereArgs: [reportId, gradeId, kind],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BreederEggInventoryMovement.fromMap(rows.first);
  }

  Future<BreederEggInventoryMovement?> getById(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return BreederEggInventoryMovement.fromMap(rows.first);
  }

  /// Every movement recorded for [flockId]/[gradeId] on a report dated
  /// strictly before [beforeDate] — the raw material
  /// `BreederEggInventoryService.previousBalance` sums into the prior ledger
  /// state (design section 14: "Opening balances derive from previous
  /// ledger state"). Joins to `breeder_daily_reports` for flock/date scope
  /// since this table does not itself carry `flockId`/`reportDate`.
  Future<List<BreederEggInventoryMovement>> getForFlockGradeBeforeDate({
    required String flockId,
    required String gradeId,
    required DateTime beforeDate,
  }) async {
    final db = await dbHelper.db;
    final rows = await db.rawQuery(
      '''
      SELECT m.* FROM $table m
      JOIN breeder_daily_reports r ON r.id = m.reportId
      WHERE r.flockId = ? AND m.gradeId = ? AND r.reportDate < ?
      ''',
      [flockId, gradeId, BreederDailyReport.dateKey(beforeDate)],
    );
    return rows.map(BreederEggInventoryMovement.fromMap).toList();
  }

  /// Inserts or updates one of the four plain movement kinds, keyed by
  /// (reportId, gradeId, kind). [movement.id] is used verbatim on insert; on
  /// update, the existing row keeps its own id.
  Future<BreederEggInventoryMovement> upsert(
    BreederEggInventoryMovement movement,
  ) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    final existing = await getEditableRow(
      movement.reportId,
      movement.gradeId,
      movement.kind,
    );

    if (existing == null) {
      await db.insert(table, {
        ...movement.toMap(),
        'createdAt': now,
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
      });
      return movement;
    }

    final updated = BreederEggInventoryMovement(
      id: existing.id,
      reportId: movement.reportId,
      gradeId: movement.gradeId,
      kind: movement.kind,
      quantity: movement.quantity,
      adjustmentDirection: movement.adjustmentDirection,
      reason: movement.reason,
      actorUserId: movement.actorUserId,
      occurredAt: movement.occurredAt,
      reversedMovementId: movement.reversedMovementId,
    );
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

  /// Always inserts a new row — never updates an existing one. The only
  /// write path for adjustments and reversals (append-only ledger, design
  /// section 8 and 14).
  Future<BreederEggInventoryMovement> insertAppend(
    BreederEggInventoryMovement movement,
  ) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    await db.insert(table, {
      ...movement.toMap(),
      'createdAt': now,
      'updatedAt': now,
      'syncStatus': 'pending',
      'dirtyAt': now,
    });
    return movement;
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
