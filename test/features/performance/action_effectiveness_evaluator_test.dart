import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/corrective_action_models.dart';
import 'package:hatchaudit/features/performance/services/action_effectiveness_evaluator.dart';

void main() {
  const evaluator = ActionEffectivenessEvaluator();

  test('reports effective when the completed window reaches its target', () {
    final definition = _definition();
    final result = evaluator.evaluate(
      definition: definition,
      implementationConfirmed: true,
      evaluatedAt: DateTime.utc(2026, 7, 28, 12),
      observations: [
        _observation(DateTime.utc(2026, 7, 26), 1.62),
        _observation(DateTime.utc(2026, 7, 27), 1.71),
        _observation(DateTime.utc(2026, 7, 28), 1.74),
      ],
    );

    expect(result.effectiveness, ActionEffectiveness.effective);
    expect(result.baselineValue, 1.51);
    expect(result.observedValue, greaterThanOrEqualTo(1.70));
  });

  test('distinguishes partial and ineffective movement', () {
    final definition = _definition();

    final partial = evaluator.evaluate(
      definition: definition,
      implementationConfirmed: true,
      evaluatedAt: DateTime.utc(2026, 7, 28, 12),
      observations: [_observation(DateTime.utc(2026, 7, 28), 1.61)],
    );
    final ineffective = evaluator.evaluate(
      definition: definition,
      implementationConfirmed: true,
      evaluatedAt: DateTime.utc(2026, 7, 28, 12),
      observations: [_observation(DateTime.utc(2026, 7, 28), 1.49)],
    );

    expect(partial.effectiveness, ActionEffectiveness.partiallyEffective);
    expect(ineffective.effectiveness, ActionEffectiveness.ineffective);
  });

  test('does not evaluate unconfirmed incomplete or insufficient evidence', () {
    final definition = _definition();

    final unconfirmed = evaluator.evaluate(
      definition: definition,
      implementationConfirmed: false,
      evaluatedAt: DateTime.utc(2026, 7, 28, 12),
      observations: [_observation(DateTime.utc(2026, 7, 28), 1.74)],
    );
    final incomplete = evaluator.evaluate(
      definition: definition,
      implementationConfirmed: true,
      evaluatedAt: DateTime.utc(2026, 7, 27, 12),
      observations: [_observation(DateTime.utc(2026, 7, 27), 1.74)],
    );
    final insufficient = evaluator.evaluate(
      definition: definition,
      implementationConfirmed: true,
      evaluatedAt: DateTime.utc(2026, 7, 28, 12),
      observations: [
        _observation(DateTime.utc(2026, 7, 28), 1.74, isValid: false),
      ],
    );

    expect(unconfirmed.effectiveness, ActionEffectiveness.notEvaluated);
    expect(unconfirmed.reason, contains('implementation'));
    expect(incomplete.effectiveness, ActionEffectiveness.notEvaluated);
    expect(incomplete.reason, contains('window'));
    expect(insufficient.effectiveness, ActionEffectiveness.notEvaluated);
    expect(insufficient.reason, contains('valid'));
  });
}

ActionKpiEvaluationDefinition _definition() {
  return ActionKpiEvaluationDefinition(
    kpiKey: 'water_to_feed_ratio',
    scope: const {'houseId': 'house-1'},
    baselineWindowStart: DateTime.utc(2026, 7, 22),
    baselineWindowEnd: DateTime.utc(2026, 7, 24),
    baselineValue: 1.51,
    targetRule: ActionTargetRule.atLeast,
    targetValue: 1.70,
    evaluationStart: DateTime.utc(2026, 7, 26),
    evaluationEnd: DateTime.utc(2026, 7, 28),
  );
}

ActionKpiObservation _observation(
  DateTime observedAt,
  double value, {
  bool isValid = true,
}) {
  return ActionKpiObservation(
    kpiKey: 'water_to_feed_ratio',
    scope: const {'houseId': 'house-1'},
    observedAt: observedAt,
    value: value,
    isValid: isValid,
  );
}
