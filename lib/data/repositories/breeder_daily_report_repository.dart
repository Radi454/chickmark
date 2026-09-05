import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/breeder_daily_report_model.dart';

/// CRUD access to `breeder_daily_reports` (breeder-flock-performance ticket
/// 07). Enforces "one report per flock per calendar date" at create time in
/// addition to the DB's own unique index, and never creates a report except
/// in response to an explicit user action — a missing day stays missing.
class BreederDailyReportRepository {
  BreederDailyReportRepository({DatabaseHelper? dbHelper, Uuid? uuid})
    : dbHelper = dbHelper ?? DatabaseHelper(),
      _uuid = uuid ?? const Uuid();

  final DatabaseHelper dbHelper;
  final Uuid _uuid;

  static const table = 'breeder_daily_reports';

  String _nowStamp() => DateTime.now().toIso8601String();

  /// Creates a new Draft report for [flockId] on [reportDate]. Throws
  /// [StateError] if a report already exists for that flock and calendar
  /// date — callers must never silently reuse or overwrite an existing
  /// report.
  Future<BreederDailyReport> createDraft({
    required String flockId,
    required DateTime reportDate,
    double? insideTemperature,
    double? outsideTemperature,
    double? lightHours,
    String? notes,
    String? createdBy,
  }) async {
    final existing = await getByFlockAndDate(flockId, reportDate);
    if (existing != null) {
      throw StateError(
        'A report already exists for flock $flockId on '
        '${BreederDailyReport.dateKey(reportDate)}',
      );
    }

    final db = await dbHelper.db;
    final now = _nowStamp();
    final report = BreederDailyReport(
      id: _uuid.v4(),
      flockId: flockId,
      reportDate: reportDate,
      insideTemperature: insideTemperature,
      outsideTemperature: outsideTemperature,
      lightHours: lightHours,
      notes: notes,
      state: BreederDailyReportState.draft,
      revision: 1,
      createdBy: createdBy,
    );
    await db.insert(table, {
      ...report.toMap(),
      'createdAt': now,
      'updatedAt': now,
      'syncStatus': 'pending',
      'dirtyAt': now,
    });
    return report;
  }

  Future<BreederDailyReport?> getById(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return BreederDailyReport.fromMap(rows.first);
  }

  /// The full raw row (including `createdAt`/`updatedAt`/sync bookkeeping),
  /// used by `BreederReportAggregateRepository` to build a push payload —
  /// [BreederDailyReport.toMap] deliberately omits those columns.
  Future<Map<String, dynamic>?> getRawById(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<BreederDailyReport?> getByFlockAndDate(
    String flockId,
    DateTime reportDate,
  ) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'flockId = ? AND reportDate = ?',
      whereArgs: [flockId, BreederDailyReport.dateKey(reportDate)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BreederDailyReport.fromMap(rows.first);
  }

  /// Reports for a flock, most recent calendar date first. A missing day
  /// simply does not appear — callers must not backfill gaps.
  Future<List<BreederDailyReport>> listForFlock(String flockId) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'flockId = ?',
      whereArgs: [flockId],
      orderBy: 'reportDate DESC',
    );
    return rows.map(BreederDailyReport.fromMap).toList();
  }

  /// Persists header field edits (temperatures, light hours, notes). Only
  /// meaningful on a Draft report; callers enforce that via
  /// `BreederBirdLedgerService.updateHeader`.
  Future<void> updateHeader(BreederDailyReport report) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    await db.update(
      table,
      {
        'insideTemperature': report.insideTemperature,
        'outsideTemperature': report.outsideTemperature,
        'lightHours': report.lightHours,
        'notes': report.notes,
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
      },
      where: 'id = ?',
      whereArgs: [report.id],
    );
  }

  /// Persists a state transition (Draft -> Submitted -> Approved) plus the
  /// actor/timestamp columns for that transition, and bumps [revision].
  Future<BreederDailyReport> applyTransition(
    BreederDailyReport report, {
    required String newState,
    String? submittedBy,
    DateTime? submittedAt,
    String? approvedBy,
    DateTime? approvedAt,
    int? eggProductionDenominatorFemales,
    String? benchmarkProfileVersionAtApproval,
    String? comparisonAxisAtApproval,
  }) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    final updated = report.copyWith(
      state: newState,
      revision: report.revision + 1,
      submittedBy: submittedBy ?? report.submittedBy,
      submittedAt: submittedAt ?? report.submittedAt,
      approvedBy: approvedBy ?? report.approvedBy,
      approvedAt: approvedAt ?? report.approvedAt,
      eggProductionDenominatorFemales:
          eggProductionDenominatorFemales ??
          report.eggProductionDenominatorFemales,
      benchmarkProfileVersionAtApproval:
          benchmarkProfileVersionAtApproval ??
          report.benchmarkProfileVersionAtApproval,
      comparisonAxisAtApproval:
          comparisonAxisAtApproval ?? report.comparisonAxisAtApproval,
    );
    await db.update(
      table,
      {
        'state': updated.state,
        'revision': updated.revision,
        'submittedBy': updated.submittedBy,
        'submittedAt': updated.submittedAt?.toIso8601String(),
        'approvedBy': updated.approvedBy,
        'approvedAt': updated.approvedAt?.toIso8601String(),
        'eggProductionDenominatorFemales':
            updated.eggProductionDenominatorFemales,
        'benchmarkProfileVersionAtApproval':
            updated.benchmarkProfileVersionAtApproval,
        'comparisonAxisAtApproval': updated.comparisonAxisAtApproval,
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
      },
      where: 'id = ?',
      whereArgs: [report.id],
    );
    return updated;
  }

  /// Increments [report.revision] by one without touching [report.state]
  /// (breeder-flock-performance ticket 12, design doc section 5.3: "The
  /// report's revision counter increments on each approved-report
  /// correction"). Unlike [applyTransition], which bumps the counter as a
  /// side effect of a state change, this is the counter's *only* other
  /// mover — a correction to an already-Approved report never changes
  /// [BreederDailyReport.state] itself.
  Future<BreederDailyReport> bumpRevision(BreederDailyReport report) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    final updated = report.copyWith(revision: report.revision + 1);
    await db.update(
      table,
      {
        'revision': updated.revision,
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
      },
      where: 'id = ?',
      whereArgs: [report.id],
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

  // ---------------------------------------------------------------------
  // Sync-aggregate optimistic concurrency (breeder-flock-performance
  // ticket 15, design doc section 5.3 and 13.1). See
  // `BreederReportAggregateRepository`/`BreederReportSyncService`/
  // `BreederReportConflictService` for the push/conflict orchestration that
  // calls these.
  // ---------------------------------------------------------------------

  /// Records the cloud's `sync_token` this device last confirmed —
  /// despite the column's name, this is NOT this table's own `revision`
  /// (ticket 12's audit counter); the two are kept deliberately separate
  /// (see database_schema.dart's `createBreederDailyReportTables` doc
  /// comment). Local-only bookkeeping — never touches `syncStatus`/
  /// `dirtyAt`, since this column is stripped from every cloud payload and
  /// updating it must not itself mark the header dirty for another push.
  Future<void> setLastSyncedRevision(String id, int revision) async {
    final db = await dbHelper.db;
    await db.update(
      table,
      {'lastSyncedRevision': revision},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Moves [report] into [BreederDailyReportState.syncConflict], recording
  /// its current state as [BreederDailyReport.previousState] so
  /// [resolveConflict] can restore it exactly. Local-only: does not touch
  /// `syncStatus`/`dirtyAt` — a conflicted report is excluded from the next
  /// aggregate push attempt by state alone (see
  /// `BreederReportAggregateRepository.reportIdsNeedingPush`), and this
  /// state transition itself is never pushed to the cloud.
  Future<BreederDailyReport> enterConflict(BreederDailyReport report) async {
    final db = await dbHelper.db;
    final updated = report.copyWith(
      state: BreederDailyReportState.syncConflict,
      previousState: report.state,
    );
    await db.update(
      table,
      {
        'state': updated.state,
        'previousState': updated.previousState,
        'updatedAt': _nowStamp(),
      },
      where: 'id = ?',
      whereArgs: [report.id],
    );
    return updated;
  }

  /// Restores [report] from [BreederDailyReportState.syncConflict] back to
  /// its recorded [BreederDailyReport.previousState] (design doc section
  /// 5.3: "Resolving a conflict returns the report to the state it held
  /// before the conflict was detected"), and clears `previousState`.
  ///
  /// [markDirtyForRetry] should be true when the resolution keeps this
  /// device's local data as the winner (it must be re-pushed against the
  /// now-known cloud revision) and false when it adopts the cloud's data
  /// (already in sync, nothing to push).
  Future<BreederDailyReport> resolveConflict(
    BreederDailyReport report, {
    required bool markDirtyForRetry,
  }) async {
    if (!report.isSyncConflict) {
      throw StateError(
        'resolveConflict called on a report that is not in Sync Conflict '
        '(was ${report.state})',
      );
    }
    final restoredState =
        report.previousState ?? BreederDailyReportState.draft;
    final db = await dbHelper.db;
    final now = _nowStamp();
    final updated = report.copyWith(
      state: restoredState,
      clearPreviousState: true,
    );
    final changes = <String, Object?>{
      'state': updated.state,
      'previousState': null,
      'updatedAt': now,
    };
    if (markDirtyForRetry) {
      changes['syncStatus'] = 'pending';
      changes['dirtyAt'] = now;
    }
    await db.update(table, changes, where: 'id = ?', whereArgs: [report.id]);
    return updated;
  }
}
