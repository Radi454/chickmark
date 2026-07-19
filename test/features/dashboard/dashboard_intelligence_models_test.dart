import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_intelligence_models.dart';

void main() {
  group('DashboardDataQuality', () {
    test('reports measurement and photo coverage from explicit totals', () {
      const quality = DashboardDataQuality(
        expectedMetricCount: 20,
        missingMetricCount: 5,
        expectedPhotoCount: 8,
        photoCount: 6,
      );

      expect(quality.coverage, 0.75);
      expect(quality.photoCoverage, 0.75);
    });

    test('classifies missing, future, current, aging, and stale data', () {
      final now = DateTime.utc(2026, 7, 12, 12);

      expect(
        const DashboardDataQuality().freshnessAt(now),
        DashboardFreshness.missing,
      );
      expect(
        DashboardDataQuality(
          latestAt: now.add(const Duration(minutes: 6)),
        ).freshnessAt(now),
        DashboardFreshness.invalid,
      );
      expect(
        DashboardDataQuality(
          latestAt: now.subtract(const Duration(hours: 12)),
        ).freshnessAt(now),
        DashboardFreshness.current,
      );
      expect(
        DashboardDataQuality(
          latestAt: now.subtract(const Duration(days: 4)),
        ).freshnessAt(now),
        DashboardFreshness.aging,
      );
      expect(
        DashboardDataQuality(
          latestAt: now.subtract(const Duration(days: 8)),
        ).freshnessAt(now),
        DashboardFreshness.stale,
      );
    });
  });

  test(
    'historical comparison exposes a signed delta when both values exist',
    () {
      const comparison = HistoricalMetricComparison(
        sectorId: 'egg_quality',
        metricKey: 'eggAvgWeight',
        latestValue: 62.4,
        previousValue: 61.9,
        state: MetricTrendState.improving,
      );

      expect(comparison.delta, closeTo(0.5, 0.0001));
    },
  );
}
