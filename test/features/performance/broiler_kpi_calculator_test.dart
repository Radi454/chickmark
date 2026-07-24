import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/performance/models/broiler_performance_models.dart';
import 'package:hatchaudit/features/performance/services/broiler_kpi_calculator.dart';

void main() {
  const calculator = BroilerKpiCalculator();

  BroilerPerformanceInput completeInput() {
    return BroilerPerformanceInput(
      entryDate: DateTime.utc(2026, 7, 1),
      placedBirds: 1000,
      placedChickWeightG: 44,
      days: [
        BroilerPerformanceDay(
          recordDate: DateTime.utc(2026, 7, 8),
          openingBirds: 1000,
          closingBirds: 994,
          mortality: 5,
          culls: 1,
          feedConsumedKg: 35,
          waterConsumedLiters: 59.5,
          averageBodyWeightG: 210,
          individualWeightsG: const [180, 190, 200, 210, 220, 230, 240],
        ),
        BroilerPerformanceDay(
          recordDate: DateTime.utc(2026, 7, 9),
          openingBirds: 994,
          closingBirds: 990,
          mortality: 3,
          culls: 1,
          feedConsumedKg: 40,
          waterConsumedLiters: 68,
          averageBodyWeightG: 250,
          individualWeightsG: const [225, 235, 245, 250, 255, 265, 275],
        ),
      ],
      targets: const [
        BroilerPerformanceTargetDay(
          ageDay: 7,
          bodyWeightG: 213,
          dailyFeedIntakeGPerLivingBird: 35,
        ),
        BroilerPerformanceTargetDay(
          ageDay: 8,
          bodyWeightG: 249,
          dailyFeedIntakeGPerLivingBird: 39,
        ),
      ],
    );
  }

  test('calculates population, mortality, feed, and water KPIs', () {
    final result = calculator.calculate(completeInput());

    expect(result.ageDay, 8);
    expect(result.averageLiveBirds, 992);
    expect(result.dailyMortalityPct, closeTo(3 / 994 * 100, 0.0001));
    expect(result.cumulativeMortalityPct, closeTo(0.8, 0.0001));
    expect(result.livabilityPct, closeTo(99, 0.0001));
    expect(result.feedPerLiveBirdG, closeTo(40000 / 992, 0.0001));
    expect(result.cumulativeFeedKg, 75);
    expect(result.cumulativeFeedPerPlacedBirdG, 75);
    expect(result.waterPerLiveBirdMl, closeTo(68000 / 992, 0.0001));
    expect(result.waterToFeedRatio, closeTo(1.7, 0.0001));
  });

  test('calculates weight sampling, target comparison, and adjusted feed', () {
    final result = calculator.calculate(completeInput());
    const weights = [225.0, 235.0, 245.0, 250.0, 255.0, 265.0, 275.0];
    final mean = weights.reduce((left, right) => left + right) / weights.length;
    final variance =
        weights
            .map((weight) => math.pow(weight - mean, 2))
            .reduce((left, right) => left + right) /
        weights.length;
    final expectedCv = math.sqrt(variance) / mean * 100;
    final expectedTargetFeedKg = (35 * 997 + 39 * 992) / 1000;

    expect(result.averageDailyGainG, 40);
    expect(result.uniformityPct, 100);
    expect(result.cvPct, closeTo(expectedCv, 0.0001));
    expect(result.weightDeviationPct, closeTo((250 - 249) / 249 * 100, 0.0001));
    expect(
      result.targetAdjustedExpectedCumulativeFeedKg,
      closeTo(expectedTargetFeedKg, 0.0001),
    );
    expect(
      result.cumulativeFeedDeviationPct,
      closeTo((75 - expectedTargetFeedKg) / expectedTargetFeedKg * 100, 0.0001),
    );
  });

  test('estimated FCR and trend direction are explicit', () {
    final result = calculator.calculate(completeInput());
    final expectedFcr = 75 / ((990 * 250 - 1000 * 44) / 1000);

    expect(result.fcr, closeTo(expectedFcr, 0.0001));
    expect(result.metrics['fcr']!.quality, PerformanceDataQuality.estimated);
    expect(
      result.metrics['daily_mortality_pct']!.direction,
      PerformanceDirection.improving,
    );
  });

  test('insufficient data returns null with a precise missing reason', () {
    final input = completeInput();
    final days = [...input.days];
    days[days.length - 1] = days.last.copyWith(
      clearAverageBodyWeight: true,
      individualWeightsG: const [],
    );

    final result = calculator.calculate(input.copyWith(days: days));

    expect(result.fcr, isNull);
    expect(result.missingReasons['fcr'], 'No current body weight');
    expect(result.weightDeviationPct, isNull);
    expect(
      result.metrics['weight_deviation_pct']!.quality,
      PerformanceDataQuality.unavailable,
    );
  });

  test('EPEF is withheld until cycle completion is explicit', () {
    final open = calculator.calculate(completeInput());
    final closed = calculator.calculate(
      completeInput().copyWith(cycleCompleted: true),
    );

    expect(open.epef, isNull);
    expect(open.missingReasons['epef'], 'Cycle is not complete');
    expect(closed.epef, isNotNull);
  });
}
