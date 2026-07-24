import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/performance_concern_models.dart';
import 'package:hatchaudit/features/performance/services/performance_alert_engine.dart';

void main() {
  const engine = PerformanceAlertEngine();

  test('objective deviations respect minimum observations and severity', () {
    const rule = PerformanceAlertRule(
      id: 'weight-rule',
      metricKey: 'weight_deviation_pct',
      scopeLevel: AlertRuleScope.global,
      direction: AlertRuleDirection.below,
      watchThreshold: -3,
      criticalThreshold: -5,
      persistenceWindow: 2,
      minimumValidObservations: 2,
      source: 'ChickMark operational default',
    );
    final observations = [
      _observation('weight_deviation_pct', 1, -4),
      _observation('weight_deviation_pct', 2, -5.9, target: 1000),
    ];

    final detection = engine.evaluate(rule, observations);

    expect(detection, isNotNull);
    expect(detection!.severity, ConcernSeverity.critical);
    expect(detection.actualValue, -5.9);
    expect(detection.targetValue, 1000);
    expect(detection.investigationKeys, contains('sample_weights_by_location'));
    expect(engine.evaluate(rule, observations.take(1).toList()), isNull);
  });

  test('water change requires 40 percent and no operational event', () {
    const rule = PerformanceAlertRule(
      id: 'water-change',
      metricKey: 'water_change_without_event',
      scopeLevel: AlertRuleScope.global,
      direction: AlertRuleDirection.rateOfChange,
      watchThreshold: 25,
      criticalThreshold: 40,
      minimumValidObservations: 2,
      source: 'ChickMark data-quality rule',
    );
    final changed = [
      _observation('water_change_without_event', 1, 100),
      _observation('water_change_without_event', 2, 55),
    ];

    expect(engine.evaluate(rule, changed)!.severity, ConcernSeverity.critical);
    expect(
      engine.evaluate(rule, [
        changed.first,
        changed.last.copyWith(hasOperationalEvent: true),
      ]),
      isNull,
    );
  });

  test('consistency rules catch decreases, repeats, and zero mortality', () {
    expect(
      engine.evaluate(_rule('cumulative_feed_decrease'), [
        _observation('cumulative_feed_decrease', 1, 1200),
        _observation('cumulative_feed_decrease', 2, 1100),
      ]),
      isNotNull,
    );
    expect(
      engine.evaluate(
        _rule('repeated_identical_values', minimum: 4),
        List.generate(
          4,
          (index) => _observation('repeated_identical_values', index, 87),
        ),
      ),
      isNotNull,
    );
    expect(
      engine.evaluate(
        _rule('extended_zero_mortality', minimum: 5),
        List.generate(
          5,
          (index) => _observation('extended_zero_mortality', index, 0),
        ),
      ),
      isNotNull,
    );
  });

  test('null and invalid observations never create performance loss', () {
    final rule = _rule('daily_mortality_pct');
    expect(
      engine.evaluate(rule, [
        PerformanceAlertObservation(
          metricKey: 'daily_mortality_pct',
          observedAt: DateTime.utc(2026, 7, 1),
          value: null,
          isValid: false,
        ),
      ]),
      isNull,
    );
  });
}

PerformanceAlertRule _rule(String metricKey, {int minimum = 2}) {
  return PerformanceAlertRule(
    id: '$metricKey-rule',
    metricKey: metricKey,
    scopeLevel: AlertRuleScope.global,
    direction: AlertRuleDirection.above,
    watchThreshold: 0,
    criticalThreshold: 1,
    minimumValidObservations: minimum,
    source: 'test',
  );
}

PerformanceAlertObservation _observation(
  String metric,
  int day,
  double? value, {
  double? target,
}) {
  return PerformanceAlertObservation(
    metricKey: metric,
    observedAt: DateTime.utc(2026, 7, day + 1),
    value: value,
    targetValue: target,
  );
}
