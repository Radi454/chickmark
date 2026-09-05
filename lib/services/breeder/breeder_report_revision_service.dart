/// Generic field-diff-to-immutable-audit-row engine for a correction made
/// to an already-APPROVED daily report (breeder-flock-performance ticket
/// 12, design doc section 5.3, 12, and 13.1: "Any correction after approval
/// requires a reason and creates permanent revision history containing
/// actor, time, old value, and new value ... Reports use the latest
/// approved revision for current calculations").
///
/// This service knows nothing about which report field means what — it
/// only diffs two `Map<String, dynamic>`s field by field, writes one
/// immutable row per field that actually changed, and bumps the report's
/// `revision` counter exactly once per correction save (breeder-flock
/// -performance ticket 07's optimistic-concurrency counter). Every caller
/// that lets a user correct an approved report — `BreederBirdLedgerService
/// .correctHeader` today, and any future correction path for a child
/// table (bird movements, feed entries, egg production, egg inventory) —
/// is meant to route through this one engine rather than hand-rolling its
/// own diff-and-log logic, exactly like `CalculationUtils` centralizes
/// rounding.
///
/// A correction that changes nothing writes nothing and does not touch the
/// revision counter — the counter's whole point is to mark "a correction
/// actually happened here", and a same-value resubmission is not a
/// correction (design doc section 12 lists "immutable approved revision
/// entries" as a mandatory invariant, which only has teeth if a row is
/// never written for a non-change).
library;

import '../../data/models/breeder_daily_report_model.dart';
import '../../data/models/breeder_report_revision_model.dart';
import '../../data/repositories/breeder_daily_report_repository.dart';
import '../../data/repositories/breeder_report_revision_repository.dart';

/// Thrown when a correction to an approved report is attempted without a
/// reason or an identified actor (design section 5.3: "requires a
/// reason").
class BreederReportCorrectionError extends Error {
  final String message;
  BreederReportCorrectionError(this.message);

  @override
  String toString() => 'BreederReportCorrectionError: $message';
}

class BreederReportRevisionService {
  BreederReportRevisionService({
    BreederReportRevisionRepository? revisionRepository,
    BreederDailyReportRepository? reportRepository,
    this.onApprovedReportRevised,
  }) : revisionRepository =
           revisionRepository ?? BreederReportRevisionRepository(),
       reportRepository = reportRepository ?? BreederDailyReportRepository();

  final BreederReportRevisionRepository revisionRepository;
  final BreederDailyReportRepository reportRepository;

  /// Ticket 17's single hook into this ticket's correction path (design
  /// section 10: "wire this into ticket 12's correction paths rather than
  /// building a separate hook"). Invoked once per successful correction
  /// (i.e. only when [recordCorrection] actually wrote revision rows),
  /// after the revision rows are written and the report's counter is
  /// bumped, with [report]'s date and the same [reason] the correction was
  /// made under. Left null by default so this service has no compile-time
  /// dependency on the alerts feature; production call sites construct
  /// this service with a closure that calls
  /// `BreederAlertEvaluationService.recomputeAffectedByRevision`.
  final Future<void> Function(BreederDailyReport report, String reason)?
  onApprovedReportRevised;

  /// Throws [BreederReportCorrectionError] when [reason] is missing or
  /// blank. Exposed statically so callers can validate a reason up front
  /// (e.g. before opening a confirmation dialog) without constructing a
  /// service instance.
  static void requireReason(String? reason) {
    if (reason == null || reason.trim().isEmpty) {
      throw BreederReportCorrectionError(
        'A reason is required to correct an approved report',
      );
    }
  }

  static String? _asText(dynamic value) => value?.toString();

  /// Diffs [oldValues] against [newValues] key by key (comparing via
  /// `toString()`, so `1` and `1.0` are treated as different exactly when a
  /// caller's own types make them different — this service never guesses
  /// at numeric equivalence), writes one immutable
  /// `breeder_report_revisions` row per key whose value actually changed,
  /// bumps [report]'s revision counter exactly once, and returns the
  /// updated report. Returns [report] unchanged, writing nothing and never
  /// touching the counter, when [oldValues] and [newValues] are identical
  /// for every key in [newValues].
  ///
  /// [tableName]/[rowId] identify where the corrected value actually lives
  /// (design section 12: "what changed (field/table/row identity)") — see
  /// `BreederReportRevision`'s doc comment for what each means for a
  /// header field versus a child-table row.
  Future<BreederDailyReport> recordCorrection({
    required BreederDailyReport report,
    required String tableName,
    required String rowId,
    required Map<String, dynamic> oldValues,
    required Map<String, dynamic> newValues,
    required String reason,
    required String actorUserId,
  }) async {
    requireReason(reason);
    if (actorUserId.trim().isEmpty) {
      throw BreederReportCorrectionError(
        'An identified actor is required to correct an approved report',
      );
    }

    final changedFields = <String>[
      for (final field in newValues.keys)
        if (_asText(oldValues[field]) != _asText(newValues[field])) field,
    ];
    if (changedFields.isEmpty) return report;

    final updatedReport = await reportRepository.bumpRevision(report);
    final changedAt = DateTime.now();
    for (final field in changedFields) {
      await revisionRepository.insert(
        BreederReportRevision(
          id: revisionRepository.newId(),
          reportId: report.id,
          tableName: tableName,
          rowId: rowId,
          fieldName: field,
          oldValue: _asText(oldValues[field]),
          newValue: _asText(newValues[field]),
          reason: reason,
          actorUserId: actorUserId,
          revisionAfter: updatedReport.revision,
          changedAt: changedAt,
        ),
      );
    }
    await onApprovedReportRevised?.call(updatedReport, reason);
    return updatedReport;
  }

  /// The full, ordered revision history for [reportId] (design section
  /// 5.3: "creates permanent revision history") — every row ever written
  /// for it, across every correction save, oldest first.
  Future<List<BreederReportRevision>> historyFor(String reportId) {
    return revisionRepository.getForReport(reportId);
  }
}
