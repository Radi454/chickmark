/// The concrete `onApprovedReportRevised` callback
/// `BreederBirdLedgerService` wires into
/// `BreederReportRevisionService.recordCorrection` by default (design
/// section 10: "wire this into ticket 12's correction paths rather than
/// building a separate hook").
///
/// Scope note (see the ticket 17 implementation report): a full recompute
/// requires knowing, for every alertable metric, how to re-derive its
/// actual value from current data. That is straightforward for the three
/// metrics `BreederWeighingService` already stores as derived session
/// figures (`body_weight_g`, `uniformity_pct`, `cv_pct` — see
/// [BreederAlertMetric]), which this hook recomputes for real. For
/// `hen_week_production_pct` and `liveability_rearing_pct` — which would
/// require re-running the egg-production and bird-ledger aggregation
/// pipelines for the alert's exact period — this hook deliberately leaves
/// the alert's existing observation untouched (neither closed nor updated)
/// rather than guess at a formula here; a follow-up ticket should extend
/// this switch once that aggregation has a ready-made "value for period"
/// entry point to call into, the same way `BreederReportPeriodService`
/// already gives alerts a ready-made completeness answer instead of
/// re-deriving one.
library;

import '../../data/models/breeder_alert_models.dart';
import '../../data/models/breeder_daily_report_model.dart';
import '../../data/repositories/breeder_alert_rule_repository.dart';
import '../../data/repositories/breeder_performance_alert_repository.dart';
import '../../data/repositories/breeder_weighing_session_repository.dart';
import 'breeder_alert_evaluation_service.dart';

Future<void> defaultBreederAlertRevisionHook(
  BreederDailyReport report,
  String reason, {
  BreederPerformanceAlertRepository? alertRepository,
  BreederAlertRuleRepository? ruleRepository,
  BreederWeighingSessionRepository? weighingSessionRepository,
}) async {
  final alerts = alertRepository ?? BreederPerformanceAlertRepository();
  final rules = ruleRepository ?? BreederAlertRuleRepository();
  final weighingRepo =
      weighingSessionRepository ?? BreederWeighingSessionRepository();
  final evaluationService = BreederAlertEvaluationService(
    alertRepository: alerts,
  );

  await evaluationService.recomputeAffectedByRevision(
    flockId: report.flockId,
    revisedDate: report.reportDate,
    revisionReason: reason,
    reevaluate: (alert) async {
      const weighingBackedMetrics = {
        BreederAlertMetric.bodyWeightG,
        BreederAlertMetric.uniformityPct,
        BreederAlertMetric.cvPct,
      };
      if (!weighingBackedMetrics.contains(alert.metricCode)) {
        // See this file's doc comment: production/liveability recompute is
        // a deferred follow-up, so the alert is left exactly as it was.
        return BreederAlertConditionCheck.holds(
          actualValue: alert.actualValue,
          deviationValue: alert.deviationValue,
          deviationPct: alert.deviationPct,
          severity: alert.severity,
        );
      }

      final sessions = await weighingRepo.listForFlock(alert.flockId);
      final inPeriod = sessions
          .where(
            (s) =>
                s.hasDerivedFigures &&
                !s.sessionDate.isBefore(alert.periodStart) &&
                !s.sessionDate.isAfter(alert.periodEnd),
          )
          .toList()
        ..sort((a, b) => a.sessionDate.compareTo(b.sessionDate));
      if (inPeriod.isEmpty) {
        // No weighing data survives in this period any more; nothing to
        // confirm the condition against either way, so leave the alert as
        // it was rather than guess.
        return BreederAlertConditionCheck.holds(
          actualValue: alert.actualValue,
          deviationValue: alert.deviationValue,
          deviationPct: alert.deviationPct,
          severity: alert.severity,
        );
      }

      final latest = inPeriod.last;
      final actualValue = switch (alert.metricCode) {
        BreederAlertMetric.uniformityPct =>
          latest.derivedUniformityPct ?? alert.actualValue,
        BreederAlertMetric.cvPct => latest.derivedCvPct ?? alert.actualValue,
        _ => latest.derivedMeanWeightG ?? alert.actualValue,
      };

      final rule = await rules.getById(alert.ruleId);
      if (rule == null) {
        // The rule that produced this alert no longer exists/is inactive;
        // there is nothing to re-judge severity against, so leave as-is.
        return BreederAlertConditionCheck.holds(
          actualValue: alert.actualValue,
          deviationValue: alert.deviationValue,
          deviationPct: alert.deviationPct,
          severity: alert.severity,
        );
      }

      final severity = evaluationService.severityFor(
        rule: rule,
        actualValue: actualValue,
        officialTargetValue: alert.officialTargetValue,
        officialLowerBound: alert.officialLowerBound,
        officialUpperBound: alert.officialUpperBound,
      );
      if (severity == null) {
        return const BreederAlertConditionCheck.cleared();
      }
      return BreederAlertConditionCheck.holds(
        actualValue: actualValue,
        deviationValue: severity.deviationValue,
        deviationPct: severity.deviationPct,
        severity: severity.severity,
      );
    },
  );
}
