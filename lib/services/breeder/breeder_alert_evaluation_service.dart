/// Turns one metric observation into a Watch/Critical
/// `breeder_performance_alerts` row, or into an update to an already-open
/// one (breeder-flock-performance ticket 17, design doc section 10).
///
/// This service is deliberately a pure evaluator: it is handed an already
/// -computed actual value, whatever the official guide published for
/// comparison, the period's completeness (from `BreederReportPeriodService`
/// — never re-derived here), and how many consecutive qualifying
/// observations already exist, and it decides severity, dedupe, and the
/// official-vs-app-owned label. Deriving the actual value itself from raw
/// ledger/report/weighing data is each metric's own concern (bird ledger,
/// egg production, weighing) and lives outside this service, the same way
/// `BreederReportPeriodService` hands a caller completeness rather than
/// computing every possible aggregate itself.
///
/// Judgment call — consecutive observations gate CREATION, not just
/// escalation: design section 10 says both "an alert fires only after N
/// qualifying observations" and "a single bad day must not trip a Critical
/// alert if the rule requires three." Read literally together, no alert
/// row exists at all — not even at Watch — until the Nth consecutive
/// qualifying observation; from that Nth observation onward, severity is
/// judged purely by the current observation's magnitude (this call decides
/// Watch vs Critical), never by how many observations produced it. A
/// caller is responsible for counting how many of the most recent
/// consecutive periods already qualified (whatever "qualified" means is
/// this rule's own direction/threshold — the caller does not need to
/// duplicate that decision, only count how many times in a row it already
/// happened) and passing that count in; this service never persists a
/// pending, not-yet-materialized count itself; introducing a fourth alert
/// state ("pending"/"observing") to hold it would contradict design section
/// 10's fixed `new`/`seen`/`closed` vocabulary.
///
/// Judgment call — incomplete periods never fire, update, or close an
/// alert: design section 14 permits *comparing* a partial period against
/// the benchmark, visibly labelled, but says nothing about *alerting* off
/// one. Firing (or silently updating/clearing) an alert from data that is
/// known to be incomplete risks a false Critical from a period that simply
/// has not finished being reported yet, with no visible warning attached
/// to the alert itself (an alert's severity badge carries no "partial
/// data" caveat the way a comparison screen's does) — so this service
/// requires `completeness.isComplete` before it will touch an alert at
/// all. An incomplete period's call is a pure no-op: an existing open
/// alert is left exactly as it was (not updated with fresher-but-partial
/// numbers, not closed), and no new alert is ever created off it. Once the
/// period is later completed (or corrected via `recomputeAffectedByRevision`
/// after an approved report lands), the next evaluation with
/// `completeness.isComplete == true` picks up normally.
library;

import '../../data/models/breeder_alert_models.dart';
import '../../data/repositories/breeder_performance_alert_repository.dart';
import 'breeder_report_period_service.dart';

/// What a single `evaluate` call decided to do.
enum BreederAlertEvaluationOutcome {
  /// The period is incomplete; nothing was created, updated, or closed.
  skippedIncompletePeriod,

  /// The observation does not qualify as a deviation under this rule at
  /// all; any existing open alert was left untouched.
  noDeviation,

  /// The observation qualifies, but fewer than
  /// `rule.consecutiveObservationsRequired` consecutive qualifying
  /// observations have been seen yet, so no alert was created or changed.
  belowConsecutiveThreshold,

  /// A new `breeder_performance_alerts` row was inserted.
  created,

  /// An already-open alert for this exact key was updated in place.
  updated,
}

class BreederAlertEvaluationResult {
  final BreederAlertEvaluationOutcome outcome;
  final BreederPerformanceAlert? alert;

  const BreederAlertEvaluationResult(this.outcome, this.alert);
}

/// Result of a single re-evaluation attempt against fresh (post-revision)
/// data, supplied by whatever knows how to recompute this alert's specific
/// metric (see `recomputeAffectedByRevision`'s `reevaluate` parameter).
class BreederAlertConditionCheck {
  final bool stillHolds;
  final double? actualValue;
  final double? deviationValue;
  final double? deviationPct;
  final String? severity;

  const BreederAlertConditionCheck.cleared()
    : stillHolds = false,
      actualValue = null,
      deviationValue = null,
      deviationPct = null,
      severity = null;

  const BreederAlertConditionCheck.holds({
    required this.actualValue,
    required this.deviationValue,
    this.deviationPct,
    required this.severity,
  }) : stillHolds = true;
}

class BreederAlertEvaluationService {
  BreederAlertEvaluationService({
    BreederPerformanceAlertRepository? alertRepository,
  }) : alertRepository = alertRepository ?? BreederPerformanceAlertRepository();

  final BreederPerformanceAlertRepository alertRepository;

  /// Evaluates one metric observation against [rule] and either creates a
  /// new alert, updates an already-open one, or takes no action. See this
  /// file's doc comment for the incomplete-period and consecutive
  /// -observation rules.
  Future<BreederAlertEvaluationResult> evaluate({
    required BreederAlertRule rule,
    String? customerId,
    required String flockId,
    String? houseId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required BreederPeriodCompleteness completeness,
    required double actualValue,
    double? officialTargetValue,
    double? officialLowerBound,
    double? officialUpperBound,
    String? benchmarkProfileId,
    String? benchmarkProfileVersion,
    String? comparisonAxisKind,
    int? comparisonAxisOffsetWeeks,
    required int consecutiveQualifyingObservations,
    required List<DateTime> evidenceReportDates,
  }) async {
    if (!completeness.isComplete) {
      return const BreederAlertEvaluationResult(
        BreederAlertEvaluationOutcome.skippedIncompletePeriod,
        null,
      );
    }

    final severity = severityFor(
      rule: rule,
      actualValue: actualValue,
      officialTargetValue: officialTargetValue,
      officialLowerBound: officialLowerBound,
      officialUpperBound: officialUpperBound,
    );

    final existing = await alertRepository.findOpenAlert(
      customerId: customerId,
      flockId: flockId,
      houseId: houseId,
      metricCode: rule.metricCode,
      periodType: rule.periodType,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );

    if (severity == null) {
      // No qualifying deviation this period. An existing open alert is
      // left exactly as it was — a single clean period is not, by itself,
      // the revision-driven "condition no longer holds" close design
      // section 10 describes; only `recomputeAffectedByRevision` closes.
      return BreederAlertEvaluationResult(
        BreederAlertEvaluationOutcome.noDeviation,
        existing,
      );
    }

    if (consecutiveQualifyingObservations <
        rule.consecutiveObservationsRequired) {
      return BreederAlertEvaluationResult(
        BreederAlertEvaluationOutcome.belowConsecutiveThreshold,
        existing,
      );
    }

    if (existing != null) {
      final updated = await alertRepository.updateObservation(
        existing.id,
        actualValue: actualValue,
        officialTargetValue: officialTargetValue,
        officialLowerBound: officialLowerBound,
        officialUpperBound: officialUpperBound,
        thresholdIsOfficial: severity.thresholdIsOfficial,
        deviationValue: severity.deviationValue,
        deviationPct: severity.deviationPct,
        severity: severity.severity,
        consecutiveObservationCount: consecutiveQualifyingObservations,
        benchmarkProfileId: benchmarkProfileId,
        benchmarkProfileVersion: benchmarkProfileVersion,
        comparisonAxisKind: comparisonAxisKind,
        comparisonAxisOffsetWeeks: comparisonAxisOffsetWeeks,
        evidenceReportDates: evidenceReportDates,
      );
      return BreederAlertEvaluationResult(
        BreederAlertEvaluationOutcome.updated,
        updated,
      );
    }

    final now = DateTime.now();
    final created = await alertRepository.insert(
      BreederPerformanceAlert(
        id: alertRepository.newId(),
        customerId: customerId,
        flockId: flockId,
        houseId: houseId,
        ruleId: rule.id,
        metricCode: rule.metricCode,
        scope: rule.scope,
        periodType: rule.periodType,
        periodStart: periodStart,
        periodEnd: periodEnd,
        actualValue: actualValue,
        officialTargetValue: officialTargetValue,
        officialLowerBound: officialLowerBound,
        officialUpperBound: officialUpperBound,
        thresholdIsOfficial: severity.thresholdIsOfficial,
        deviationValue: severity.deviationValue,
        deviationPct: severity.deviationPct,
        severity: severity.severity,
        consecutiveObservationCount: consecutiveQualifyingObservations,
        benchmarkProfileId: benchmarkProfileId,
        benchmarkProfileVersion: benchmarkProfileVersion,
        comparisonAxisKind: comparisonAxisKind,
        comparisonAxisOffsetWeeks: comparisonAxisOffsetWeeks,
        evidenceReportDates: evidenceReportDates,
        state: BreederPerformanceAlertState.new_,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return BreederAlertEvaluationResult(
      BreederAlertEvaluationOutcome.created,
      created,
    );
  }

  /// Pure severity classification — no I/O, so directly unit-testable
  /// without a database. Returns null when [actualValue] does not qualify
  /// as a deviation under [rule] at all (wrong direction, or within
  /// tolerance).
  BreederAlertSeverityDecision? severityFor({
    required BreederAlertRule rule,
    required double actualValue,
    double? officialTargetValue,
    double? officialLowerBound,
    double? officialUpperBound,
  }) {
    if (rule.usesOfficialBound) {
      final bound = rule.direction == BreederAlertDirection.below
          ? officialLowerBound
          : officialUpperBound;
      if (bound == null) return null; // No official bound to compare to.

      final breached = rule.direction == BreederAlertDirection.below
          ? actualValue < bound
          : actualValue > bound;
      final deviationValue = actualValue - bound;
      final deviationPct = bound == 0 ? null : (deviationValue / bound) * 100;

      if (breached) {
        return BreederAlertSeverityDecision(
          severity: BreederAlertSeverity.critical,
          thresholdIsOfficial: true,
          deviationValue: deviationValue,
          deviationPct: deviationPct,
        );
      }

      // App-owned early-warning buffer approaching the official bound —
      // the guide publishes no Watch-level figure, so this half of the
      // decision is never official even though Critical, above, is.
      final bufferFraction = rule.watchDeviationPct / 100;
      final bufferBound = rule.direction == BreederAlertDirection.below
          ? bound * (1 + bufferFraction)
          : bound * (1 - bufferFraction);
      final inWatchZone = rule.direction == BreederAlertDirection.below
          ? actualValue < bufferBound
          : actualValue > bufferBound;
      if (!inWatchZone) return null;
      return BreederAlertSeverityDecision(
        severity: BreederAlertSeverity.watch,
        thresholdIsOfficial: false,
        deviationValue: deviationValue,
        deviationPct: deviationPct,
      );
    }

    if (officialTargetValue != null && officialTargetValue != 0) {
      // Relative-to-target deviation (design section 10's default case).
      final deviationValue = actualValue - officialTargetValue;
      final deviationPct = (deviationValue / officialTargetValue) * 100;
      return _relativeSeverity(rule, deviationValue, deviationPct);
    }

    // No official target at all (uniformity/CV): the rule's own
    // thresholds are absolute floors/ceilings on the actual value itself,
    // not a relative deviation from anything published.
    final belowFloor = rule.direction == BreederAlertDirection.below;
    final watchBreached = belowFloor
        ? actualValue < rule.watchDeviationPct
        : actualValue > rule.watchDeviationPct;
    if (!watchBreached) return null;
    final criticalBreached = belowFloor
        ? actualValue < rule.criticalDeviationPct
        : actualValue > rule.criticalDeviationPct;
    final breachedThreshold = criticalBreached
        ? rule.criticalDeviationPct
        : rule.watchDeviationPct;
    return BreederAlertSeverityDecision(
      severity: criticalBreached
          ? BreederAlertSeverity.critical
          : BreederAlertSeverity.watch,
      thresholdIsOfficial: false,
      deviationValue: actualValue - breachedThreshold,
      deviationPct: null,
    );
  }

  BreederAlertSeverityDecision? _relativeSeverity(
    BreederAlertRule rule,
    double deviationValue,
    double deviationPct,
  ) {
    final directional = switch (rule.direction) {
      BreederAlertDirection.below => deviationPct < 0,
      BreederAlertDirection.above => deviationPct > 0,
      _ => true,
    };
    if (!directional) return null;

    final magnitude = deviationPct.abs();
    if (magnitude >= rule.criticalDeviationPct) {
      return BreederAlertSeverityDecision(
        severity: BreederAlertSeverity.critical,
        thresholdIsOfficial: false,
        deviationValue: deviationValue,
        deviationPct: deviationPct,
      );
    }
    if (magnitude >= rule.watchDeviationPct) {
      return BreederAlertSeverityDecision(
        severity: BreederAlertSeverity.watch,
        thresholdIsOfficial: false,
        deviationValue: deviationValue,
        deviationPct: deviationPct,
      );
    }
    return null;
  }

  /// Design section 10: "when an approved report is revised, every alert
  /// whose evidence includes the revised date is recomputed." This is the
  /// one hook `BreederReportRevisionService.recordCorrection` calls after a
  /// successful correction — no separate hook is built.
  ///
  /// [reevaluate] is supplied by the caller, who alone knows how to
  /// recompute this specific alert's specific metric from current data
  /// (this service never re-derives ledger/report/weighing aggregates
  /// itself — see this file's doc comment). Returning
  /// [BreederAlertConditionCheck.cleared] closes the alert with a system
  /// reason citing [revisionReason] and [revisedDate] (design section 10:
  /// "closed with a system reason recording the revision that cleared
  /// it") — the row is always closed, never deleted. Returning `.holds(...)`
  /// updates the alert's observation in place, exactly like a normal
  /// repeat [evaluate] call.
  Future<List<BreederPerformanceAlert>> recomputeAffectedByRevision({
    required String flockId,
    required DateTime revisedDate,
    required String revisionReason,
    required Future<BreederAlertConditionCheck> Function(
      BreederPerformanceAlert alert,
    )
    reevaluate,
  }) async {
    final candidates = await alertRepository.findOpenCoveringEvidenceDate(
      flockId,
      revisedDate,
    );
    final touched = <BreederPerformanceAlert>[];
    for (final alert in candidates) {
      final check = await reevaluate(alert);
      if (!check.stillHolds) {
        final closed = await alertRepository.close(
          alert.id,
          reason:
              'Cleared by a revision to the ${_dateKey(revisedDate)} report: '
              '$revisionReason',
        );
        touched.add(closed);
        continue;
      }
      final updated = await alertRepository.updateObservation(
        alert.id,
        actualValue: check.actualValue!,
        officialTargetValue: alert.officialTargetValue,
        officialLowerBound: alert.officialLowerBound,
        officialUpperBound: alert.officialUpperBound,
        thresholdIsOfficial: alert.thresholdIsOfficial,
        deviationValue: check.deviationValue!,
        deviationPct: check.deviationPct,
        severity: check.severity!,
        consecutiveObservationCount: alert.consecutiveObservationCount,
        benchmarkProfileId: alert.benchmarkProfileId,
        benchmarkProfileVersion: alert.benchmarkProfileVersion,
        comparisonAxisKind: alert.comparisonAxisKind,
        comparisonAxisOffsetWeeks: alert.comparisonAxisOffsetWeeks,
        evidenceReportDates: alert.evidenceReportDates,
      );
      touched.add(updated);
    }
    return touched;
  }

  String _dateKey(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).toIso8601String().split(
        'T',
      )[0];

  Future<BreederPerformanceAlert> acknowledge(
    String alertId, {
    required String actorUserId,
  }) {
    return alertRepository.acknowledge(alertId, actorUserId: actorUserId);
  }

  /// A user-initiated close (design section 10's other lifecycle exit).
  /// [reason] here is a plain user-authored note, never a system reason —
  /// the two are kept textually distinguishable by which path wrote them:
  /// `close` here vs `recomputeAffectedByRevision` above.
  Future<BreederPerformanceAlert> close(
    String alertId, {
    required String reason,
  }) {
    return alertRepository.close(alertId, reason: reason);
  }
}

class BreederAlertSeverityDecision {
  final String severity;
  final bool thresholdIsOfficial;
  final double deviationValue;
  final double? deviationPct;

  const BreederAlertSeverityDecision({
    required this.severity,
    required this.thresholdIsOfficial,
    required this.deviationValue,
    this.deviationPct,
  });
}
