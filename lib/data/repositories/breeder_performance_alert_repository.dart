import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/breeder_alert_models.dart';

/// CRUD access to `breeder_performance_alerts` (breeder-flock-performance
/// ticket 17, design doc section 10 and 12).
///
/// [findOpenAlert] is the dedupe lookup `BreederAlertEvaluationService`
/// consults before every insert (design section 10: "at most one open
/// alert exists per customer, flock, house, metric, and period"); the
/// schema-level partial unique index on `breeder_performance_alerts`
/// (`idx_breeder_performance_alerts_open_unique`) is the enforcement of
/// last resort if two evaluations ever race.
class BreederPerformanceAlertRepository {
  BreederPerformanceAlertRepository({DatabaseHelper? dbHelper})
    : dbHelper = dbHelper ?? DatabaseHelper();
  final DatabaseHelper dbHelper;
  final Uuid _uuid = const Uuid();

  static const _table = 'breeder_performance_alerts';

  String newId() => _uuid.v4();

  String _nowStamp() => DateTime.now().toIso8601String();

  static String _dateOnly(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).toIso8601String();

  Future<BreederPerformanceAlert?> getById(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(_table, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return BreederPerformanceAlert.fromMap(rows.first);
  }

  /// The open (non-closed) alert, if any, already recorded for this exact
  /// customer/flock/house/metric/period key — the same key the schema's
  /// partial unique index enforces.
  Future<BreederPerformanceAlert?> findOpenAlert({
    String? customerId,
    required String flockId,
    String? houseId,
    required String metricCode,
    required String periodType,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      _table,
      where:
          "COALESCE(customerId, '') = ? AND flockId = ? AND "
          "COALESCE(houseId, '') = ? AND metricCode = ? AND periodType = ? "
          "AND periodStart = ? AND periodEnd = ? AND state <> 'closed'",
      whereArgs: [
        customerId ?? '',
        flockId,
        houseId ?? '',
        metricCode,
        periodType,
        _dateOnly(periodStart),
        _dateOnly(periodEnd),
      ],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BreederPerformanceAlert.fromMap(rows.first);
  }

  Future<BreederPerformanceAlert> insert(
    BreederPerformanceAlert alert,
  ) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    await db.insert(_table, {
      ...alert.toMap(),
      'syncStatus': 'pending',
      'dirtyAt': now,
    });
    return alert;
  }

  /// Updates an existing open alert's observation in place (design section
  /// 10: "a repeat evaluation ... updates that alert's actual value,
  /// deviation, and severity instead of creating a second row") rather than
  /// inserting a second row.
  Future<BreederPerformanceAlert> updateObservation(
    String id, {
    required double actualValue,
    double? officialTargetValue,
    double? officialLowerBound,
    double? officialUpperBound,
    required bool thresholdIsOfficial,
    required double deviationValue,
    double? deviationPct,
    required String severity,
    required int consecutiveObservationCount,
    String? benchmarkProfileId,
    String? benchmarkProfileVersion,
    String? comparisonAxisKind,
    int? comparisonAxisOffsetWeeks,
    required List<DateTime> evidenceReportDates,
  }) async {
    final existing = await getById(id);
    if (existing == null) {
      throw ArgumentError.value(id, 'id', 'No such performance alert');
    }
    final updated = existing.copyWith(
      actualValue: actualValue,
      officialTargetValue: officialTargetValue,
      officialLowerBound: officialLowerBound,
      officialUpperBound: officialUpperBound,
      thresholdIsOfficial: thresholdIsOfficial,
      deviationValue: deviationValue,
      deviationPct: deviationPct,
      severity: severity,
      consecutiveObservationCount: consecutiveObservationCount,
      benchmarkProfileId: benchmarkProfileId,
      benchmarkProfileVersion: benchmarkProfileVersion,
      comparisonAxisKind: comparisonAxisKind,
      comparisonAxisOffsetWeeks: comparisonAxisOffsetWeeks,
      evidenceReportDates: evidenceReportDates,
      updatedAt: DateTime.now(),
    );
    final db = await dbHelper.db;
    final now = _nowStamp();
    await db.update(
      _table,
      {...updated.toMap(), 'syncStatus': 'pending', 'dirtyAt': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    return updated;
  }

  Future<List<BreederPerformanceAlert>> listForFlock(
    String flockId, {
    bool openOnly = false,
  }) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      _table,
      where: openOnly ? "flockId = ? AND state <> 'closed'" : 'flockId = ?',
      whereArgs: [flockId],
      orderBy: 'periodStart DESC, severity DESC',
    );
    return rows.map(BreederPerformanceAlert.fromMap).toList();
  }

  /// Every open alert for [flockId] whose evidence includes [date] — the
  /// candidate set `BreederAlertEvaluationService.recomputeAffectedByRevision`
  /// re-evaluates when an approved report for that date is revised (design
  /// section 10).
  Future<List<BreederPerformanceAlert>> findOpenCoveringEvidenceDate(
    String flockId,
    DateTime date,
  ) async {
    final alerts = await listForFlock(flockId, openOnly: true);
    final key = _dateOnly(date);
    return alerts
        .where(
          (alert) => alert.evidenceReportDates.any(
            (d) => _dateOnly(d) == key,
          ),
        )
        .toList();
  }

  Future<BreederPerformanceAlert> markSeen(String id) async {
    return _transition(id, state: BreederPerformanceAlertState.seen);
  }

  /// Closes [id] with [reason]. [reason] is required and always recorded
  /// (design section 10 lists both a user-initiated close and a
  /// system-initiated close-on-revision-clearing as the only two ways an
  /// alert ever leaves the open state; a row is never deleted).
  Future<BreederPerformanceAlert> close(
    String id, {
    required String reason,
  }) async {
    return _transition(
      id,
      state: BreederPerformanceAlertState.closed,
      closedReason: reason,
      closedAt: DateTime.now(),
    );
  }

  Future<BreederPerformanceAlert> acknowledge(
    String id, {
    required String actorUserId,
  }) async {
    return _transition(
      id,
      state: BreederPerformanceAlertState.seen,
      acknowledgedAt: DateTime.now(),
      acknowledgedBy: actorUserId,
    );
  }

  Future<BreederPerformanceAlert> _transition(
    String id, {
    required String state,
    String? closedReason,
    DateTime? closedAt,
    DateTime? acknowledgedAt,
    String? acknowledgedBy,
  }) async {
    final existing = await getById(id);
    if (existing == null) {
      throw ArgumentError.value(id, 'id', 'No such performance alert');
    }
    final updated = existing.copyWith(
      state: state,
      closedReason: closedReason,
      closedAt: closedAt,
      acknowledgedAt: acknowledgedAt,
      acknowledgedBy: acknowledgedBy,
      updatedAt: DateTime.now(),
    );
    final db = await dbHelper.db;
    final now = _nowStamp();
    await db.update(
      _table,
      {...updated.toMap(), 'syncStatus': 'pending', 'dirtyAt': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    return updated;
  }
}
