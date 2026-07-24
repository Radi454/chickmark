import 'dart:math' as math;

import '../models/broiler_performance_models.dart';

class BroilerKpiCalculator {
  const BroilerKpiCalculator();

  BroilerPerformanceResult calculate(BroilerPerformanceInput input) {
    final days = [...input.days]
      ..sort((left, right) => left.recordDate.compareTo(right.recordDate));
    if (days.isEmpty) return _emptyResult();

    final latest = days.last;
    final ageDay = _calendarDays(input.entryDate, latest.recordDate);
    final targets = {for (final target in input.targets) target.ageDay: target};
    final latestTarget = targets[ageDay];
    final averageLiveBirds = _averageLiveBirds(latest);
    final dailyMortalityPct = _percentage(
      latest.mortality,
      latest.openingBirds,
    );
    final mortalityDirection = _mortalityDirection(days);

    final cumulativeMortality = _sumInts(days.map((day) => day.mortality));
    final cumulativeCulls = _sumInts(days.map((day) => day.culls));
    final cumulativeMortalityPct = _percentage(
      cumulativeMortality,
      input.placedBirds,
    );
    final livabilityPct =
        input.placedBirds > 0 &&
            cumulativeMortality != null &&
            cumulativeCulls != null
        ? (input.placedBirds - cumulativeMortality - cumulativeCulls) /
              input.placedBirds *
              100
        : null;

    final latestFeedKg = latest.feedConsumedKg;
    final feedPerLiveBirdG =
        latestFeedKg != null &&
            latestFeedKg >= 0 &&
            averageLiveBirds != null &&
            averageLiveBirds > 0
        ? latestFeedKg * 1000 / averageLiveBirds
        : null;
    final cumulativeFeedKg = _sumDoubles(days.map((day) => day.feedConsumedKg));
    final cumulativeFeedPerPlacedBirdG =
        cumulativeFeedKg != null && input.placedBirds > 0
        ? cumulativeFeedKg * 1000 / input.placedBirds
        : null;
    final waterPerLiveBirdMl =
        latest.waterConsumedLiters != null &&
            averageLiveBirds != null &&
            averageLiveBirds > 0
        ? latest.waterConsumedLiters! * 1000 / averageLiveBirds
        : null;
    final waterToFeedRatio =
        latest.waterConsumedLiters != null &&
            latestFeedKg != null &&
            latestFeedKg > 0
        ? latest.waterConsumedLiters! / latestFeedKg
        : null;

    final currentWeight = _weight(latest);
    final previousWeightSample = _previousWeight(days);
    final averageDailyGainG =
        currentWeight != null && previousWeightSample != null
        ? (currentWeight - previousWeightSample.weightG) /
              _calendarDays(previousWeightSample.recordDate, latest.recordDate)
        : null;
    final sampleStats = _sampleStats(latest.individualWeightsG);
    final uniformityPct = latest.uniformityPct ?? sampleStats?.uniformityPct;
    final cvPct = latest.cvPct ?? sampleStats?.cvPct;
    final weightDeviationPct =
        currentWeight != null &&
            latestTarget?.bodyWeightG != null &&
            latestTarget!.bodyWeightG! > 0
        ? (currentWeight - latestTarget.bodyWeightG!) /
              latestTarget.bodyWeightG! *
              100
        : null;

    final expectedFeedKg = _targetAdjustedFeedKg(days, input, targets);
    final cumulativeFeedDeviationPct =
        cumulativeFeedKg != null && expectedFeedKg != null && expectedFeedKg > 0
        ? (cumulativeFeedKg - expectedFeedKg) / expectedFeedKg * 100
        : null;

    final fcrResult = _fcr(
      input: input,
      latest: latest,
      currentWeightG: currentWeight,
      cumulativeFeedKg: cumulativeFeedKg,
    );
    final epefResult = _epef(
      input: input,
      ageDay: ageDay,
      livabilityPct: livabilityPct,
      currentWeightG: currentWeight,
      fcr: fcrResult.value,
    );

    final metrics = <String, PerformanceMetric>{
      'age_day': _metric('age_day', ageDay.toDouble(), 'day'),
      'average_live_birds': _metric(
        'average_live_birds',
        averageLiveBirds,
        'birds',
        missingReason: 'Opening and closing live birds are required',
      ),
      'daily_mortality_pct': _metric(
        'daily_mortality_pct',
        dailyMortalityPct,
        '%',
        direction: mortalityDirection,
        missingReason: 'Opening birds and daily mortality are required',
      ),
      'cumulative_mortality_pct': _metric(
        'cumulative_mortality_pct',
        cumulativeMortalityPct,
        '%',
        missingReason: 'Complete mortality and placement data are required',
      ),
      'livability_pct': _metric(
        'livability_pct',
        livabilityPct,
        '%',
        missingReason: 'Placed birds, mortality, and culls are required',
      ),
      'feed_per_live_bird_g': _metric(
        'feed_per_live_bird_g',
        feedPerLiveBirdG,
        'g/bird',
        targetValue: latestTarget?.dailyFeedIntakeGPerLivingBird,
        missingReason: 'Daily feed and average live birds are required',
      ),
      'cumulative_feed_kg': _metric(
        'cumulative_feed_kg',
        cumulativeFeedKg,
        'kg',
        missingReason: 'Complete daily feed data are required',
      ),
      'cumulative_feed_per_placed_bird_g': _metric(
        'cumulative_feed_per_placed_bird_g',
        cumulativeFeedPerPlacedBirdG,
        'g/placed bird',
        missingReason: 'Cumulative feed and placed birds are required',
      ),
      'water_per_live_bird_ml': _metric(
        'water_per_live_bird_ml',
        waterPerLiveBirdMl,
        'ml/bird',
        missingReason: 'Daily water and average live birds are required',
      ),
      'water_to_feed_ratio': _metric(
        'water_to_feed_ratio',
        waterToFeedRatio,
        'L/kg',
        missingReason: 'Daily water and feed are required',
      ),
      'average_daily_gain_g': _metric(
        'average_daily_gain_g',
        averageDailyGainG,
        'g/day',
        missingReason: 'Two valid body-weight samples are required',
      ),
      'uniformity_pct': _metric(
        'uniformity_pct',
        uniformityPct,
        '%',
        missingReason: 'No uniformity value or weight sample',
      ),
      'cv_pct': _metric(
        'cv_pct',
        cvPct,
        '%',
        missingReason: 'No CV value or weight sample',
      ),
      'weight_deviation_pct': _metric(
        'weight_deviation_pct',
        weightDeviationPct,
        '%',
        targetValue: latestTarget?.bodyWeightG,
        missingReason: currentWeight == null
            ? 'No current body weight'
            : 'No matching body-weight target',
      ),
      'target_adjusted_cumulative_feed_kg': _metric(
        'target_adjusted_cumulative_feed_kg',
        expectedFeedKg,
        'kg',
        missingReason:
            'Every day needs average live birds and a matching feed target',
      ),
      'cumulative_feed_deviation_pct': _metric(
        'cumulative_feed_deviation_pct',
        cumulativeFeedDeviationPct,
        '%',
        targetValue: expectedFeedKg,
        missingReason:
            'Actual and target-adjusted cumulative feed are required',
      ),
      'fcr': PerformanceMetric(
        key: 'fcr',
        value: fcrResult.value,
        unit: 'kg/kg',
        quality: fcrResult.value == null
            ? PerformanceDataQuality.unavailable
            : PerformanceDataQuality.estimated,
        targetValue: latestTarget?.fcr,
        missingReason: fcrResult.missingReason,
      ),
      'epef': PerformanceMetric(
        key: 'epef',
        value: epefResult.value,
        unit: 'index',
        quality: epefResult.value == null
            ? PerformanceDataQuality.unavailable
            : PerformanceDataQuality.estimated,
        missingReason: epefResult.missingReason,
      ),
    };
    return BroilerPerformanceResult(metrics: Map.unmodifiable(metrics));
  }

  BroilerPerformanceResult _emptyResult() {
    const reason = 'No daily performance records';
    const keys = <String, String>{
      'age_day': 'day',
      'average_live_birds': 'birds',
      'daily_mortality_pct': '%',
      'cumulative_mortality_pct': '%',
      'livability_pct': '%',
      'feed_per_live_bird_g': 'g/bird',
      'cumulative_feed_kg': 'kg',
      'cumulative_feed_per_placed_bird_g': 'g/placed bird',
      'water_per_live_bird_ml': 'ml/bird',
      'water_to_feed_ratio': 'L/kg',
      'average_daily_gain_g': 'g/day',
      'uniformity_pct': '%',
      'cv_pct': '%',
      'weight_deviation_pct': '%',
      'target_adjusted_cumulative_feed_kg': 'kg',
      'cumulative_feed_deviation_pct': '%',
      'fcr': 'kg/kg',
      'epef': 'index',
    };
    return BroilerPerformanceResult(
      metrics: {
        for (final entry in keys.entries)
          entry.key: PerformanceMetric(
            key: entry.key,
            unit: entry.value,
            quality: PerformanceDataQuality.unavailable,
            missingReason: reason,
          ),
      },
    );
  }

  PerformanceMetric _metric(
    String key,
    double? value,
    String unit, {
    double? targetValue,
    PerformanceDirection direction = PerformanceDirection.neutral,
    String missingReason = 'Insufficient data',
  }) {
    final deviation = value != null && targetValue != null && targetValue != 0
        ? (value - targetValue) / targetValue * 100
        : null;
    return PerformanceMetric(
      key: key,
      value: value,
      unit: unit,
      quality: value == null
          ? PerformanceDataQuality.unavailable
          : PerformanceDataQuality.complete,
      targetValue: targetValue,
      deviationPct: deviation,
      direction: value == null ? PerformanceDirection.unknown : direction,
      missingReason: value == null ? missingReason : null,
    );
  }

  double? _averageLiveBirds(BroilerPerformanceDay day) {
    final opening = day.openingBirds;
    final closing = day.closingBirds;
    if (opening == null || closing == null || opening < 0 || closing < 0) {
      return null;
    }
    return (opening + closing) / 2;
  }

  double? _percentage(num? numerator, num? denominator) {
    if (numerator == null || denominator == null || denominator <= 0) {
      return null;
    }
    return numerator / denominator * 100;
  }

  int? _sumInts(Iterable<int?> values) {
    var total = 0;
    for (final value in values) {
      if (value == null) return null;
      total += value;
    }
    return total;
  }

  double? _sumDoubles(Iterable<double?> values) {
    var total = 0.0;
    for (final value in values) {
      if (value == null) return null;
      total += value;
    }
    return total;
  }

  double? _weight(BroilerPerformanceDay day) {
    if (day.averageBodyWeightG != null) return day.averageBodyWeightG;
    if (day.individualWeightsG.isEmpty) return null;
    return day.individualWeightsG.reduce((left, right) => left + right) /
        day.individualWeightsG.length;
  }

  _WeightSample? _previousWeight(List<BroilerPerformanceDay> days) {
    for (var index = days.length - 2; index >= 0; index -= 1) {
      final weight = _weight(days[index]);
      if (weight != null) {
        return _WeightSample(days[index].recordDate, weight);
      }
    }
    return null;
  }

  _SampleStats? _sampleStats(List<double> weights) {
    if (weights.isEmpty) return null;
    final mean = weights.reduce((left, right) => left + right) / weights.length;
    if (mean <= 0) return null;
    final variance =
        weights
            .map((weight) => math.pow(weight - mean, 2))
            .reduce((left, right) => left + right) /
        weights.length;
    final lower = mean * 0.9;
    final upper = mean * 1.1;
    final uniform = weights
        .where((weight) => weight >= lower && weight <= upper)
        .length;
    return _SampleStats(
      uniformityPct: uniform / weights.length * 100,
      cvPct: math.sqrt(variance) / mean * 100,
    );
  }

  double? _targetAdjustedFeedKg(
    List<BroilerPerformanceDay> days,
    BroilerPerformanceInput input,
    Map<int, BroilerPerformanceTargetDay> targets,
  ) {
    var expectedGrams = 0.0;
    for (final day in days) {
      final averageLive = _averageLiveBirds(day);
      final target = targets[_calendarDays(input.entryDate, day.recordDate)]
          ?.dailyFeedIntakeGPerLivingBird;
      if (averageLive == null || target == null) return null;
      expectedGrams += averageLive * target;
    }
    return expectedGrams / 1000;
  }

  _ValueOrReason _fcr({
    required BroilerPerformanceInput input,
    required BroilerPerformanceDay latest,
    required double? currentWeightG,
    required double? cumulativeFeedKg,
  }) {
    if (currentWeightG == null) {
      return const _ValueOrReason.missing('No current body weight');
    }
    if (latest.closingBirds == null || latest.closingBirds! <= 0) {
      return const _ValueOrReason.missing('No current live population');
    }
    if (input.placedBirds <= 0) {
      return const _ValueOrReason.missing('No placed bird count');
    }
    if (input.placedChickWeightG == null || input.placedChickWeightG! <= 0) {
      return const _ValueOrReason.missing('No placed chick weight');
    }
    if (cumulativeFeedKg == null || cumulativeFeedKg <= 0) {
      return const _ValueOrReason.missing('No cumulative feed');
    }
    final liveBiomassKg = latest.closingBirds! * currentWeightG / 1000;
    final placedBiomassKg =
        input.placedBirds * input.placedChickWeightG! / 1000;
    final estimatedGainKg = liveBiomassKg - placedBiomassKg;
    if (estimatedGainKg <= 0) {
      return const _ValueOrReason.missing(
        'Estimated live weight gain is not positive',
      );
    }
    return _ValueOrReason(cumulativeFeedKg / estimatedGainKg);
  }

  _ValueOrReason _epef({
    required BroilerPerformanceInput input,
    required int ageDay,
    required double? livabilityPct,
    required double? currentWeightG,
    required double? fcr,
  }) {
    if (!input.cycleCompleted) {
      return const _ValueOrReason.missing('Cycle is not complete');
    }
    if (ageDay <= 0 ||
        livabilityPct == null ||
        currentWeightG == null ||
        fcr == null ||
        fcr <= 0) {
      return const _ValueOrReason.missing(
        'Final age, livability, weight, and FCR are required',
      );
    }
    return _ValueOrReason(
      livabilityPct * (currentWeightG / 1000) / (ageDay * fcr) * 100,
    );
  }

  PerformanceDirection _mortalityDirection(List<BroilerPerformanceDay> days) {
    if (days.length < 2) return PerformanceDirection.unknown;
    final current = _percentage(days.last.mortality, days.last.openingBirds);
    final previous = _percentage(
      days[days.length - 2].mortality,
      days[days.length - 2].openingBirds,
    );
    if (current == null || previous == null) {
      return PerformanceDirection.unknown;
    }
    if ((current - previous).abs() < 0.000001) {
      return PerformanceDirection.stable;
    }
    return current < previous
        ? PerformanceDirection.improving
        : PerformanceDirection.worsening;
  }

  int _calendarDays(DateTime start, DateTime end) {
    final startDate = DateTime.utc(start.year, start.month, start.day);
    final endDate = DateTime.utc(end.year, end.month, end.day);
    return endDate.difference(startDate).inDays;
  }
}

class _WeightSample {
  const _WeightSample(this.recordDate, this.weightG);

  final DateTime recordDate;
  final double weightG;
}

class _SampleStats {
  const _SampleStats({required this.uniformityPct, required this.cvPct});

  final double uniformityPct;
  final double cvPct;
}

class _ValueOrReason {
  const _ValueOrReason(this.value) : missingReason = null;
  const _ValueOrReason.missing(this.missingReason) : value = null;

  final double? value;
  final String? missingReason;
}
