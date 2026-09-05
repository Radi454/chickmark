import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/models/breeder_alert_models.dart';
import 'package:hatchaudit/services/breeder/breeder_alert_evaluation_service.dart';
import 'package:hatchaudit/services/breeder/breeder_report_period_service.dart';

import '../../features/breeder/fake_breeder_repositories.dart';

/// `BreederAlertEvaluationService` (breeder-flock-performance ticket 17,
/// design doc section 10). Pure-evaluator tests: no database, an in-memory
/// fake alert repository — see the service's own doc comment for the
/// incomplete-period and consecutive-observation rules this exercises.
void main() {
  final complete = BreederPeriodCompleteness(
    start: DateTime.utc(2026, 8, 3),
    end: DateTime.utc(2026, 8, 9),
    recordedDates: List.generate(
      7,
      (i) => DateTime.utc(2026, 8, 3 + i),
    ),
    missingDates: const [],
  );
  final incomplete = BreederPeriodCompleteness(
    start: DateTime.utc(2026, 8, 3),
    end: DateTime.utc(2026, 8, 9),
    recordedDates: [DateTime.utc(2026, 8, 3)],
    missingDates: List.generate(
      6,
      (i) => DateTime.utc(2026, 8, 4 + i),
    ),
  );

  BreederAlertRule relativeRule({int consecutive = 1}) => BreederAlertRule(
    id: 'rule-body-weight',
    metricCode: BreederAlertMetric.bodyWeightG,
    scope: BreederAlertScope.flock,
    periodType: BreederAlertPeriodType.weekly,
    direction: BreederAlertDirection.either,
    watchDeviationPct: 5,
    criticalDeviationPct: 10,
    consecutiveObservationsRequired: consecutive,
    usesOfficialBound: false,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  BreederAlertRule officialBoundRule() => BreederAlertRule(
    id: 'rule-liveability',
    metricCode: BreederAlertMetric.liveabilityRearingPct,
    scope: BreederAlertScope.flock,
    periodType: BreederAlertPeriodType.cumulative,
    direction: BreederAlertDirection.below,
    watchDeviationPct: 1, // 1% buffer above the official bound.
    criticalDeviationPct: 0,
    consecutiveObservationsRequired: 1,
    usesOfficialBound: true,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  BreederAlertRule absoluteFloorRule({int consecutive = 1}) =>
      BreederAlertRule(
        id: 'rule-uniformity',
        metricCode: BreederAlertMetric.uniformityPct,
        scope: BreederAlertScope.house,
        periodType: BreederAlertPeriodType.weekly,
        direction: BreederAlertDirection.below,
        watchDeviationPct: 80,
        criticalDeviationPct: 70,
        consecutiveObservationsRequired: consecutive,
        usesOfficialBound: false,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

  test('severityFor: relative deviation is directional', () {
    final service = BreederAlertEvaluationService(
      alertRepository: FakeBreederPerformanceAlertRepository(),
    );
    final rule = relativeRule();

    // 20% under target (either direction rule): critical.
    final under = service.severityFor(
      rule: rule,
      actualValue: 320,
      officialTargetValue: 400,
    );
    expect(under!.severity, BreederAlertSeverity.critical);
    expect(under.thresholdIsOfficial, isFalse);

    // 6% under target: watch.
    final watch = service.severityFor(
      rule: rule,
      actualValue: 376,
      officialTargetValue: 400,
    );
    expect(watch!.severity, BreederAlertSeverity.watch);

    // Within tolerance: no deviation.
    final ok = service.severityFor(
      rule: rule,
      actualValue: 398,
      officialTargetValue: 400,
    );
    expect(ok, isNull);
  });

  test(
    'severityFor: below-only direction ignores an over-target observation',
    () {
      final service = BreederAlertEvaluationService(
        alertRepository: FakeBreederPerformanceAlertRepository(),
      );
      final rule = BreederAlertRule(
        id: 'rule-production',
        metricCode: BreederAlertMetric.henWeekProductionPct,
        scope: BreederAlertScope.flock,
        periodType: BreederAlertPeriodType.weekly,
        direction: BreederAlertDirection.below,
        watchDeviationPct: 5,
        criticalDeviationPct: 10,
        consecutiveObservationsRequired: 1,
        usesOfficialBound: false,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final overTarget = service.severityFor(
        rule: rule,
        actualValue: 95,
        officialTargetValue: 80,
      );
      expect(overTarget, isNull);
    },
  );

  test(
    'severityFor: an official bound is cited as official only for the '
    'Critical breach, never for the Watch buffer',
    () {
      final service = BreederAlertEvaluationService(
        alertRepository: FakeBreederPerformanceAlertRepository(),
      );
      final rule = officialBoundRule();

      // Breaches Ross 308's own published 95% lower bound: Critical, and
      // the threshold cited IS the official one.
      final breached = service.severityFor(
        rule: rule,
        actualValue: 94,
        officialLowerBound: 95,
      );
      expect(breached!.severity, BreederAlertSeverity.critical);
      expect(breached.thresholdIsOfficial, isTrue);

      // Above the official bound but inside the app's own 1% early-warning
      // buffer (95 * 1.01 = 95.95): Watch, and NEVER labelled official —
      // Aviagen publishes no such buffer.
      final buffered = service.severityFor(
        rule: rule,
        actualValue: 95.5,
        officialLowerBound: 95,
      );
      expect(buffered!.severity, BreederAlertSeverity.watch);
      expect(buffered.thresholdIsOfficial, isFalse);

      // Comfortably above both: no deviation at all.
      final clear = service.severityFor(
        rule: rule,
        actualValue: 98,
        officialLowerBound: 95,
      );
      expect(clear, isNull);
    },
  );

  test(
    'severityFor: uniformity/CV have no official target, so the rule is an '
    'absolute floor/ceiling, never a relative deviation, and never official',
    () {
      final service = BreederAlertEvaluationService(
        alertRepository: FakeBreederPerformanceAlertRepository(),
      );
      final rule = absoluteFloorRule();

      final critical = service.severityFor(
        rule: rule,
        actualValue: 65,
        officialTargetValue: null,
      );
      expect(critical!.severity, BreederAlertSeverity.critical);
      expect(critical.thresholdIsOfficial, isFalse);

      final watch = service.severityFor(
        rule: rule,
        actualValue: 75,
        officialTargetValue: null,
      );
      expect(watch!.severity, BreederAlertSeverity.watch);

      final ok = service.severityFor(
        rule: rule,
        actualValue: 85,
        officialTargetValue: null,
      );
      expect(ok, isNull);
    },
  );

  test(
    'an alert fires only after the rule\'s required consecutive '
    'observations, then keeps updating the same row',
    () async {
      final repo = FakeBreederPerformanceAlertRepository();
      final service = BreederAlertEvaluationService(alertRepository: repo);
      final rule = relativeRule(consecutive: 3);

      Future<BreederAlertEvaluationResult> observe(int count) {
        return service.evaluate(
          rule: rule,
          flockId: 'flock-1',
          periodStart: complete.start,
          periodEnd: complete.end,
          completeness: complete,
          actualValue: 320, // 20% under target: critical-magnitude always.
          officialTargetValue: 400,
          benchmarkProfileId: 'profile-1',
          benchmarkProfileVersion: 'Performance Objectives 2021 EN',
          comparisonAxisKind: 'official',
          comparisonAxisOffsetWeeks: 0,
          consecutiveQualifyingObservations: count,
          evidenceReportDates: [DateTime.utc(2026, 8, 9)],
        );
      }

      final first = await observe(1);
      expect(
        first.outcome,
        BreederAlertEvaluationOutcome.belowConsecutiveThreshold,
      );
      final second = await observe(2);
      expect(
        second.outcome,
        BreederAlertEvaluationOutcome.belowConsecutiveThreshold,
      );
      expect(repo.all, isEmpty, reason: 'a single/second bad week must not '
          'trip the alert when the rule requires three');

      final third = await observe(3);
      expect(third.outcome, BreederAlertEvaluationOutcome.created);
      expect(third.alert!.severity, BreederAlertSeverity.critical);
      expect(repo.all, hasLength(1));

      // A repeat qualifying evaluation updates the SAME row rather than
      // creating a second one (design section 10's dedupe rule).
      final fourth = await observe(4);
      expect(fourth.outcome, BreederAlertEvaluationOutcome.updated);
      expect(fourth.alert!.id, third.alert!.id);
      expect(repo.all, hasLength(1));
    },
  );

  test(
    'profile version and comparison axis are recorded on the created alert',
    () async {
      final repo = FakeBreederPerformanceAlertRepository();
      final service = BreederAlertEvaluationService(alertRepository: repo);
      final result = await service.evaluate(
        rule: relativeRule(),
        flockId: 'flock-1',
        periodStart: complete.start,
        periodEnd: complete.end,
        completeness: complete,
        actualValue: 320,
        officialTargetValue: 400,
        benchmarkProfileId: 'profile-ross308',
        benchmarkProfileVersion: 'Performance Objectives 2021 EN',
        comparisonAxisKind: 'milestoneAligned',
        comparisonAxisOffsetWeeks: 2,
        consecutiveQualifyingObservations: 1,
        evidenceReportDates: [DateTime.utc(2026, 8, 9)],
      );
      expect(result.alert!.benchmarkProfileId, 'profile-ross308');
      expect(
        result.alert!.benchmarkProfileVersion,
        'Performance Objectives 2021 EN',
      );
      expect(result.alert!.comparisonAxisKind, 'milestoneAligned');
      expect(result.alert!.comparisonAxisOffsetWeeks, 2);
    },
  );

  test(
    'an incomplete period never creates, updates, or closes an alert',
    () async {
      final repo = FakeBreederPerformanceAlertRepository();
      final service = BreederAlertEvaluationService(alertRepository: repo);
      final rule = relativeRule();

      final result = await service.evaluate(
        rule: rule,
        flockId: 'flock-1',
        periodStart: incomplete.start,
        periodEnd: incomplete.end,
        completeness: incomplete,
        actualValue: 200, // 50% under target: would be Critical if complete.
        officialTargetValue: 400,
        consecutiveQualifyingObservations: 5,
        evidenceReportDates: [DateTime.utc(2026, 8, 3)],
      );
      expect(
        result.outcome,
        BreederAlertEvaluationOutcome.skippedIncompletePeriod,
      );
      expect(repo.all, isEmpty);
    },
  );

  test(
    'acknowledge and close transitions',
    () async {
      final repo = FakeBreederPerformanceAlertRepository();
      final service = BreederAlertEvaluationService(alertRepository: repo);
      final created = await service.evaluate(
        rule: relativeRule(),
        flockId: 'flock-1',
        periodStart: complete.start,
        periodEnd: complete.end,
        completeness: complete,
        actualValue: 320,
        officialTargetValue: 400,
        consecutiveQualifyingObservations: 1,
        evidenceReportDates: [DateTime.utc(2026, 8, 9)],
      );
      final alertId = created.alert!.id;
      expect(created.alert!.state, BreederPerformanceAlertState.new_);

      final acknowledged = await service.acknowledge(
        alertId,
        actorUserId: 'user-1',
      );
      expect(acknowledged.state, BreederPerformanceAlertState.seen);
      expect(acknowledged.acknowledgedBy, 'user-1');

      final closed = await service.close(alertId, reason: 'Resolved on farm');
      expect(closed.state, BreederPerformanceAlertState.closed);
      expect(closed.closedReason, 'Resolved on farm');
      // Never deleted — the row survives, closed.
      expect(await repo.getById(alertId), isNotNull);
    },
  );

  test(
    'recomputeAffectedByRevision closes a cleared alert with a system '
    'reason recording the revision, without deleting it',
    () async {
      final repo = FakeBreederPerformanceAlertRepository();
      final service = BreederAlertEvaluationService(alertRepository: repo);
      final revisedDate = DateTime.utc(2026, 8, 9);
      final created = await service.evaluate(
        rule: relativeRule(),
        flockId: 'flock-1',
        periodStart: complete.start,
        periodEnd: complete.end,
        completeness: complete,
        actualValue: 320,
        officialTargetValue: 400,
        consecutiveQualifyingObservations: 1,
        evidenceReportDates: [revisedDate],
      );
      final alertId = created.alert!.id;

      final touched = await service.recomputeAffectedByRevision(
        flockId: 'flock-1',
        revisedDate: revisedDate,
        revisionReason: 'Corrected a transposed body-weight entry',
        reevaluate: (alert) async =>
            const BreederAlertConditionCheck.cleared(),
      );

      expect(touched, hasLength(1));
      expect(touched.single.id, alertId);
      expect(touched.single.state, BreederPerformanceAlertState.closed);
      expect(touched.single.closedReason, isNotNull);
      expect(
        touched.single.closedReason,
        contains('Corrected a transposed body-weight entry'),
      );
      expect(touched.single.closedReason, contains('2026-08-09'));
      // Never deleted.
      expect(await repo.getById(alertId), isNotNull);
    },
  );

  test(
    'recomputeAffectedByRevision updates (never closes) an alert whose '
    'condition still holds under the revised data',
    () async {
      final repo = FakeBreederPerformanceAlertRepository();
      final service = BreederAlertEvaluationService(alertRepository: repo);
      final revisedDate = DateTime.utc(2026, 8, 9);
      final created = await service.evaluate(
        rule: relativeRule(),
        flockId: 'flock-1',
        periodStart: complete.start,
        periodEnd: complete.end,
        completeness: complete,
        actualValue: 320,
        officialTargetValue: 400,
        consecutiveQualifyingObservations: 1,
        evidenceReportDates: [revisedDate],
      );
      expect(created.alert, isNotNull);

      final touched = await service.recomputeAffectedByRevision(
        flockId: 'flock-1',
        revisedDate: revisedDate,
        revisionReason: 'Corrected a different field',
        reevaluate: (alert) async => const BreederAlertConditionCheck.holds(
          actualValue: 340,
          deviationValue: -60,
          deviationPct: -15,
          severity: BreederAlertSeverity.watch,
        ),
      );

      expect(touched.single.state, isNot(BreederPerformanceAlertState.closed));
      expect(touched.single.actualValue, 340);
      expect(touched.single.severity, BreederAlertSeverity.watch);
    },
  );
}
