import '../../../data/models/corrective_action_models.dart';

class ActionEffectivenessEvaluator {
  const ActionEffectivenessEvaluator();

  ActionEvaluationResult evaluate({
    required ActionKpiEvaluationDefinition definition,
    required bool implementationConfirmed,
    required DateTime evaluatedAt,
    required List<ActionKpiObservation> observations,
  }) {
    if (!implementationConfirmed) {
      return _notEvaluated(
        definition,
        'Action implementation has not been confirmed.',
      );
    }
    if (evaluatedAt.toUtc().isBefore(definition.evaluationEnd.toUtc())) {
      return _notEvaluated(
        definition,
        'The KPI evaluation window is not complete.',
      );
    }

    final valid =
        observations
            .where(
              (observation) =>
                  observation.isValid &&
                  observation.kpiKey == definition.kpiKey &&
                  _scopeMatches(definition.scope, observation.scope) &&
                  !_isBefore(
                    observation.observedAt,
                    definition.evaluationStart,
                  ) &&
                  !_isAfter(observation.observedAt, definition.evaluationEnd),
            )
            .toList()
          ..sort((left, right) => left.observedAt.compareTo(right.observedAt));
    if (valid.isEmpty) {
      return _notEvaluated(
        definition,
        'No valid KPI observations are available in the evaluation window.',
      );
    }

    final observedValue = valid.last.value;
    final effectiveness = _classify(definition, observedValue);
    return ActionEvaluationResult(
      effectiveness: effectiveness,
      baselineValue: definition.baselineValue,
      observedValue: observedValue,
      reason: _reason(definition, effectiveness),
    );
  }

  ActionEffectiveness _classify(
    ActionKpiEvaluationDefinition definition,
    double observedValue,
  ) {
    switch (definition.targetRule) {
      case ActionTargetRule.atLeast:
        if (observedValue >= definition.targetValue) {
          return ActionEffectiveness.effective;
        }
        return observedValue > definition.baselineValue
            ? ActionEffectiveness.partiallyEffective
            : ActionEffectiveness.ineffective;
      case ActionTargetRule.atMost:
        if (observedValue <= definition.targetValue) {
          return ActionEffectiveness.effective;
        }
        return observedValue < definition.baselineValue
            ? ActionEffectiveness.partiallyEffective
            : ActionEffectiveness.ineffective;
      case ActionTargetRule.increaseBy:
        final change = observedValue - definition.baselineValue;
        if (change >= definition.targetValue) {
          return ActionEffectiveness.effective;
        }
        return change > 0
            ? ActionEffectiveness.partiallyEffective
            : ActionEffectiveness.ineffective;
      case ActionTargetRule.decreaseBy:
        final change = definition.baselineValue - observedValue;
        if (change >= definition.targetValue) {
          return ActionEffectiveness.effective;
        }
        return change > 0
            ? ActionEffectiveness.partiallyEffective
            : ActionEffectiveness.ineffective;
    }
  }

  String _reason(
    ActionKpiEvaluationDefinition definition,
    ActionEffectiveness effectiveness,
  ) {
    switch (effectiveness) {
      case ActionEffectiveness.effective:
        return 'Latest valid observation met the action KPI target.';
      case ActionEffectiveness.partiallyEffective:
        return 'Latest valid observation improved from baseline but did not '
            'meet the action KPI target.';
      case ActionEffectiveness.ineffective:
        return 'Latest valid observation did not improve from baseline toward '
            'the action KPI target.';
      case ActionEffectiveness.notEvaluated:
        return 'The action KPI has not been evaluated.';
    }
  }

  ActionEvaluationResult _notEvaluated(
    ActionKpiEvaluationDefinition definition,
    String reason,
  ) {
    return ActionEvaluationResult(
      effectiveness: ActionEffectiveness.notEvaluated,
      baselineValue: definition.baselineValue,
      observedValue: null,
      reason: reason,
    );
  }

  bool _scopeMatches(
    Map<String, Object?> requiredScope,
    Map<String, Object?> observationScope,
  ) {
    return requiredScope.entries.every(
      (entry) =>
          observationScope[entry.key]?.toString() == entry.value?.toString(),
    );
  }

  bool _isBefore(DateTime value, DateTime boundary) =>
      value.toUtc().isBefore(boundary.toUtc());

  bool _isAfter(DateTime value, DateTime boundary) =>
      value.toUtc().isAfter(boundary.toUtc());
}
