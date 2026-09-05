import 'package:sqflite/sqflite.dart';

import '../../models/breeder_alert_models.dart';

/// Default `breeder_alert_rules` rows (breeder-flock-performance ticket 17,
/// design doc section 10) — the app's own operational judgement about when
/// a metric's drift from the official benchmark deserves interrupting a
/// user. Ids are fixed, human-readable slugs (not generated UUIDs) so this
/// seed is trivially idempotent by primary key and stable across every
/// device and reseed, matching how `bmk_breeds`/`bmk_egg_breakout` seed
/// rows are keyed in `database_helper.dart` — never re-derive these from a
/// vendor asset file, since they are this app's judgement, not a published
/// figure.
///
/// Every value below is a deliberate, documented judgment call (see the
/// ticket 17 implementation report for the reasoning); none of them may
/// ever be presented in the UI as an Aviagen/Cobb/breed-company figure
/// (design section 10's central rule) — see [BreederAlertRule
/// .usesOfficialBound]'s doc comment for the one metric where part of the
/// threshold genuinely is official.
final List<BreederAlertRule> kDefaultBreederAlertRules = [
  BreederAlertRule(
    id: 'rule-body_weight_g-flock-weekly-either',
    metricCode: BreederAlertMetric.bodyWeightG,
    scope: BreederAlertScope.flock,
    periodType: BreederAlertPeriodType.weekly,
    direction: BreederAlertDirection.either,
    // Body weight is unhealthy both under- and over-target; a flock can
    // recover from one bad week (illness, a scale miscalibration, a feed
    // delivery delay), so two consecutive weekly weighings must confirm the
    // deviation before it interrupts anyone.
    watchDeviationPct: 5,
    criticalDeviationPct: 10,
    consecutiveObservationsRequired: 2,
    usesOfficialBound: false,
    notes:
        'App-owned: Ross 308 publishes a body-weight target only, no bound.',
    createdAt: _seedTimestamp,
    updatedAt: _seedTimestamp,
  ),
  BreederAlertRule(
    id: 'rule-hen_week_production_pct-flock-weekly-below',
    metricCode: BreederAlertMetric.henWeekProductionPct,
    scope: BreederAlertScope.flock,
    periodType: BreederAlertPeriodType.weekly,
    direction: BreederAlertDirection.below,
    // Production is HEN-WEEK, never hen-day (design section 10 / ticket
    // 03's metricProvenance). Only a shortfall is a deviation worth
    // flagging; a week that outperforms the guide is not a problem.
    watchDeviationPct: 5,
    criticalDeviationPct: 10,
    consecutiveObservationsRequired: 1,
    usesOfficialBound: false,
    notes:
        'App-owned: Ross 308 publishes a Hen-Week (%) target only, no bound.',
    createdAt: _seedTimestamp,
    updatedAt: _seedTimestamp,
  ),
  BreederAlertRule(
    id: 'rule-liveability_rearing_pct-flock-cumulative-below',
    metricCode: BreederAlertMetric.liveabilityRearingPct,
    scope: BreederAlertScope.flock,
    periodType: BreederAlertPeriodType.cumulative,
    direction: BreederAlertDirection.below,
    // The ONE metric in this ticket where the guide itself publishes a
    // bound (95-96% cumulative rearing liveability). watchDeviationPct is
    // read as a percentage-OF-the-bound early-warning buffer above the
    // official lower bound (see BreederAlertEvaluationService), never as a
    // second official figure; criticalDeviationPct is unused in this mode
    // (usesOfficialBound == true: Critical is simply "breached the
    // official 95% lower bound").
    watchDeviationPct: 1,
    criticalDeviationPct: 0,
    consecutiveObservationsRequired: 1,
    usesOfficialBound: true,
    notes:
        'Critical threshold is Ross 308\'s own published 95% lower bound; '
        'the Watch buffer above it is app-owned.',
    createdAt: _seedTimestamp,
    updatedAt: _seedTimestamp,
  ),
  BreederAlertRule(
    id: 'rule-uniformity_pct-house-weekly-below',
    metricCode: BreederAlertMetric.uniformityPct,
    scope: BreederAlertScope.house,
    periodType: BreederAlertPeriodType.weekly,
    direction: BreederAlertDirection.below,
    // Ross 308 publishes no uniformity target at all, so there is no
    // "target" to deviate from — this rule instead reads
    // watchDeviationPct/criticalDeviationPct as absolute uniformity
    // percentage-point floors handled by
    // BreederAlertEvaluationService's no-target branch.
    watchDeviationPct: 80,
    criticalDeviationPct: 70,
    consecutiveObservationsRequired: 2,
    usesOfficialBound: false,
    notes: 'App-owned in full: Ross 308 publishes no uniformity target.',
    createdAt: _seedTimestamp,
    updatedAt: _seedTimestamp,
  ),
  BreederAlertRule(
    id: 'rule-cv_pct-house-weekly-above',
    metricCode: BreederAlertMetric.cvPct,
    scope: BreederAlertScope.house,
    periodType: BreederAlertPeriodType.weekly,
    direction: BreederAlertDirection.above,
    // As uniformity above: no official CV target exists, so these are
    // absolute CV percentage-point ceilings, not relative deviations.
    watchDeviationPct: 8,
    criticalDeviationPct: 12,
    consecutiveObservationsRequired: 2,
    usesOfficialBound: false,
    notes: 'App-owned in full: Ross 308 publishes no CV target.',
    createdAt: _seedTimestamp,
    updatedAt: _seedTimestamp,
  ),
];

final DateTime _seedTimestamp = DateTime.utc(2026, 8, 27);

/// Seeds [kDefaultBreederAlertRules], skipping any id already present so a
/// device that has since edited... (it cannot: client roles never mutate
/// this table — see `createBreederAlertRulesTable`'s doc comment) — is left
/// untouched on every reseed. Safe to call on every app open, exactly like
/// `importBreederBenchmarks`.
Future<void> seedBreederAlertRules(DatabaseExecutor db) async {
  for (final rule in kDefaultBreederAlertRules) {
    final existing = await db.query(
      'breeder_alert_rules',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [rule.id],
      limit: 1,
    );
    if (existing.isNotEmpty) continue;
    await db.insert('breeder_alert_rules', {
      ...rule.toMap(),
      'syncStatus': 'synced',
    });
  }
}
