enum PerformanceDataQuality { complete, partial, estimated, unavailable }

enum PerformanceDirection { improving, worsening, stable, neutral, unknown }

class PerformanceMetric {
  const PerformanceMetric({
    required this.key,
    required this.unit,
    required this.quality,
    this.value,
    this.targetValue,
    this.deviationPct,
    this.direction = PerformanceDirection.neutral,
    this.missingReason,
  });

  final String key;
  final double? value;
  final String unit;
  final PerformanceDataQuality quality;
  final double? targetValue;
  final double? deviationPct;
  final PerformanceDirection direction;
  final String? missingReason;
}

class BroilerPerformanceDay {
  const BroilerPerformanceDay({
    required this.recordDate,
    this.openingBirds,
    this.closingBirds,
    this.mortality,
    this.culls,
    this.feedConsumedKg,
    this.waterConsumedLiters,
    this.averageBodyWeightG,
    this.uniformityPct,
    this.cvPct,
    this.individualWeightsG = const [],
  });

  final DateTime recordDate;
  final int? openingBirds;
  final int? closingBirds;
  final int? mortality;
  final int? culls;
  final double? feedConsumedKg;
  final double? waterConsumedLiters;
  final double? averageBodyWeightG;
  final double? uniformityPct;
  final double? cvPct;
  final List<double> individualWeightsG;

  BroilerPerformanceDay copyWith({
    DateTime? recordDate,
    int? openingBirds,
    int? closingBirds,
    int? mortality,
    int? culls,
    double? feedConsumedKg,
    double? waterConsumedLiters,
    double? averageBodyWeightG,
    double? uniformityPct,
    double? cvPct,
    List<double>? individualWeightsG,
    bool clearAverageBodyWeight = false,
  }) {
    return BroilerPerformanceDay(
      recordDate: recordDate ?? this.recordDate,
      openingBirds: openingBirds ?? this.openingBirds,
      closingBirds: closingBirds ?? this.closingBirds,
      mortality: mortality ?? this.mortality,
      culls: culls ?? this.culls,
      feedConsumedKg: feedConsumedKg ?? this.feedConsumedKg,
      waterConsumedLiters: waterConsumedLiters ?? this.waterConsumedLiters,
      averageBodyWeightG: clearAverageBodyWeight
          ? null
          : averageBodyWeightG ?? this.averageBodyWeightG,
      uniformityPct: uniformityPct ?? this.uniformityPct,
      cvPct: cvPct ?? this.cvPct,
      individualWeightsG: individualWeightsG ?? this.individualWeightsG,
    );
  }
}

class BroilerPerformanceTargetDay {
  const BroilerPerformanceTargetDay({
    required this.ageDay,
    this.bodyWeightG,
    this.dailyFeedIntakeGPerLivingBird,
    this.fcr,
  });

  final int ageDay;
  final double? bodyWeightG;
  final double? dailyFeedIntakeGPerLivingBird;
  final double? fcr;
}

class BroilerPerformanceInput {
  const BroilerPerformanceInput({
    required this.entryDate,
    required this.placedBirds,
    required this.days,
    required this.targets,
    this.placedChickWeightG,
    this.cycleCompleted = false,
  });

  final DateTime entryDate;
  final int placedBirds;
  final double? placedChickWeightG;
  final List<BroilerPerformanceDay> days;
  final List<BroilerPerformanceTargetDay> targets;
  final bool cycleCompleted;

  BroilerPerformanceInput copyWith({
    DateTime? entryDate,
    int? placedBirds,
    double? placedChickWeightG,
    List<BroilerPerformanceDay>? days,
    List<BroilerPerformanceTargetDay>? targets,
    bool? cycleCompleted,
  }) {
    return BroilerPerformanceInput(
      entryDate: entryDate ?? this.entryDate,
      placedBirds: placedBirds ?? this.placedBirds,
      placedChickWeightG: placedChickWeightG ?? this.placedChickWeightG,
      days: days ?? this.days,
      targets: targets ?? this.targets,
      cycleCompleted: cycleCompleted ?? this.cycleCompleted,
    );
  }
}

class BroilerPerformanceResult {
  const BroilerPerformanceResult({required this.metrics});

  final Map<String, PerformanceMetric> metrics;

  int? get ageDay => metrics['age_day']?.value?.round();
  double? get averageLiveBirds => metrics['average_live_birds']?.value;
  double? get dailyMortalityPct => metrics['daily_mortality_pct']?.value;
  double? get cumulativeMortalityPct =>
      metrics['cumulative_mortality_pct']?.value;
  double? get livabilityPct => metrics['livability_pct']?.value;
  double? get feedPerLiveBirdG => metrics['feed_per_live_bird_g']?.value;
  double? get cumulativeFeedKg => metrics['cumulative_feed_kg']?.value;
  double? get cumulativeFeedPerPlacedBirdG =>
      metrics['cumulative_feed_per_placed_bird_g']?.value;
  double? get waterPerLiveBirdMl => metrics['water_per_live_bird_ml']?.value;
  double? get waterToFeedRatio => metrics['water_to_feed_ratio']?.value;
  double? get averageDailyGainG => metrics['average_daily_gain_g']?.value;
  double? get uniformityPct => metrics['uniformity_pct']?.value;
  double? get cvPct => metrics['cv_pct']?.value;
  double? get weightDeviationPct => metrics['weight_deviation_pct']?.value;
  double? get targetAdjustedExpectedCumulativeFeedKg =>
      metrics['target_adjusted_cumulative_feed_kg']?.value;
  double? get cumulativeFeedDeviationPct =>
      metrics['cumulative_feed_deviation_pct']?.value;
  double? get fcr => metrics['fcr']?.value;
  double? get epef => metrics['epef']?.value;

  Map<String, String> get missingReasons => {
    for (final entry in metrics.entries)
      if (entry.value.missingReason != null)
        entry.key: entry.value.missingReason!,
  };
}
