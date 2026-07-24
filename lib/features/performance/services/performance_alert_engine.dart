import '../../../data/models/performance_concern_models.dart';

class PerformanceAlertEngine {
  const PerformanceAlertEngine();

  PerformanceAlertDetection? evaluate(
    PerformanceAlertRule rule,
    List<PerformanceAlertObservation> observations, {
    String customerId = 'unscoped',
    String? farmId,
    String? flockId,
    String? placementId,
    String? houseId,
  }) {
    if (!rule.isEnabled) return null;
    final valid =
        observations
            .where(
              (item) =>
                  item.isValid &&
                  item.value != null &&
                  item.metricKey == rule.metricKey,
            )
            .toList()
          ..sort((left, right) => left.observedAt.compareTo(right.observedAt));
    if (valid.length < rule.minimumValidObservations) return null;

    final evaluation = _evaluateValues(rule, valid);
    if (evaluation == null) return null;
    final windowLength = rule.persistenceWindow.clamp(1, valid.length);
    final window = valid.sublist(valid.length - windowLength);
    if (!_persistent(rule, window)) return null;
    final latest = valid.last;
    return PerformanceAlertDetection(
      ruleId: rule.id,
      metricKey: rule.metricKey,
      severity: evaluation.severity,
      observedAt: latest.observedAt,
      windowStart: window.first.observedAt,
      windowEnd: latest.observedAt,
      actualValue: evaluation.actual,
      baselineValue: evaluation.baseline,
      targetValue: latest.targetValue,
      customerId: customerId,
      farmId: farmId,
      flockId: flockId,
      placementId: placementId,
      houseId: houseId,
      evidence: {
        'observations': valid.length,
        'actual': evaluation.actual,
        if (evaluation.baseline != null) 'baseline': evaluation.baseline,
        if (latest.targetValue != null) 'target': latest.targetValue,
        'direction': rule.direction.storageKey,
        'source': rule.source,
      },
      investigationKeys: _investigations(rule.metricKey),
    );
  }

  _Evaluation? _evaluateValues(
    PerformanceAlertRule rule,
    List<PerformanceAlertObservation> valid,
  ) {
    final latest = valid.last;
    final value = latest.value!;
    switch (rule.metricKey) {
      case 'cumulative_feed_decrease':
        final prior = valid[valid.length - 2].value!;
        if (value >= prior) return null;
        return _Evaluation(ConcernSeverity.critical, prior - value, prior);
      case 'repeated_identical_values':
        if (valid.any((item) => item.value != value)) return null;
        return _Evaluation(ConcernSeverity.watch, value, value);
      case 'extended_zero_mortality':
        if (valid.any((item) => item.value != 0)) return null;
        return const _Evaluation(ConcernSeverity.watch, 0, 0);
      case 'water_change_without_event':
        if (latest.hasOperationalEvent) return null;
        return _rate(rule, valid);
      case 'weekly_weight_change_implausible':
        if (latest.observedAt
                .difference(valid[valid.length - 2].observedAt)
                .inDays >
            7) {
          return null;
        }
        return _rate(rule, valid);
      case 'mortality_live_reduction_mismatch':
        final opening = latest.openingBirds;
        final closing = latest.closingBirds;
        final mortality = latest.mortality;
        if (opening == null || closing == null || mortality == null) {
          return null;
        }
        final unexplained = mortality - (opening - closing);
        if (unexplained <= 0) return null;
        final critical = rule.criticalThreshold;
        return _Evaluation(
          critical != null && unexplained >= critical
              ? ConcernSeverity.critical
              : ConcernSeverity.watch,
          unexplained.toDouble(),
          (opening - closing).toDouble(),
        );
    }

    return switch (rule.direction) {
      AlertRuleDirection.above => _above(rule, value),
      AlertRuleDirection.below => _below(rule, value),
      AlertRuleDirection.outsideRange => _outside(rule, value),
      AlertRuleDirection.rateOfChange => _rate(rule, valid),
    };
  }

  _Evaluation? _above(PerformanceAlertRule rule, double value) {
    if (rule.criticalThreshold != null && value >= rule.criticalThreshold!) {
      return _Evaluation(ConcernSeverity.critical, value, null);
    }
    if (rule.watchThreshold != null && value >= rule.watchThreshold!) {
      return _Evaluation(ConcernSeverity.watch, value, null);
    }
    return null;
  }

  _Evaluation? _below(PerformanceAlertRule rule, double value) {
    if (rule.criticalThreshold != null && value <= rule.criticalThreshold!) {
      return _Evaluation(ConcernSeverity.critical, value, null);
    }
    if (rule.watchThreshold != null && value <= rule.watchThreshold!) {
      return _Evaluation(ConcernSeverity.watch, value, null);
    }
    return null;
  }

  _Evaluation? _outside(PerformanceAlertRule rule, double value) {
    if (rule.lowerThreshold == null || rule.upperThreshold == null) {
      return null;
    }
    if (value >= rule.lowerThreshold! && value <= rule.upperThreshold!) {
      return null;
    }
    return _Evaluation(ConcernSeverity.watch, value, null);
  }

  _Evaluation? _rate(
    PerformanceAlertRule rule,
    List<PerformanceAlertObservation> valid,
  ) {
    if (valid.length < 2) return null;
    final baseline = valid[valid.length - 2].value!;
    if (baseline == 0) return null;
    final change = ((valid.last.value! - baseline) / baseline * 100).abs();
    if (rule.criticalThreshold != null && change >= rule.criticalThreshold!) {
      return _Evaluation(ConcernSeverity.critical, change, baseline);
    }
    if (rule.watchThreshold != null && change >= rule.watchThreshold!) {
      return _Evaluation(ConcernSeverity.watch, change, baseline);
    }
    return null;
  }

  bool _persistent(
    PerformanceAlertRule rule,
    List<PerformanceAlertObservation> window,
  ) {
    if (rule.persistenceWindow <= 1 ||
        {
          'cumulative_feed_decrease',
          'repeated_identical_values',
          'extended_zero_mortality',
          'water_change_without_event',
          'weekly_weight_change_implausible',
          'mortality_live_reduction_mismatch',
        }.contains(rule.metricKey)) {
      return true;
    }
    return window.every((item) {
      final value = item.value!;
      return switch (rule.direction) {
        AlertRuleDirection.above =>
          rule.watchThreshold != null && value >= rule.watchThreshold!,
        AlertRuleDirection.below =>
          rule.watchThreshold != null && value <= rule.watchThreshold!,
        AlertRuleDirection.outsideRange =>
          rule.lowerThreshold != null &&
              rule.upperThreshold != null &&
              (value < rule.lowerThreshold! || value > rule.upperThreshold!),
        AlertRuleDirection.rateOfChange => true,
      };
    });
  }

  List<String> _investigations(String metricKey) {
    return switch (metricKey) {
      'weight_deviation_pct' => const [
        'sample_weights_by_location',
        'check_feeder_distribution',
        'check_nipple_flow',
        'examine_enteric_health',
      ],
      'water_change_without_event' => const [
        'check_water_meter',
        'check_nipple_flow',
        'check_water_interruptions',
      ],
      'daily_mortality_pct' => const [
        'review_mortality_causes',
        'clinical_examination',
        'necropsy',
      ],
      _ => const ['verify_source_data'],
    };
  }
}

class _Evaluation {
  const _Evaluation(this.severity, this.actual, this.baseline);

  final ConcernSeverity severity;
  final double actual;
  final double? baseline;
}
