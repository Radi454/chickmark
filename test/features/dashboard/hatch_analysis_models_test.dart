import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/dashboard/models/hatch_analysis_models.dart';

void main() {
  group('HatchBudgetSummary', () {
    test('calculates category percentages from total eggs set', () {
      final summary = HatchBudgetSummary(
        totalEggsSet: 1000,
        healthyHatched: 850,
        culled: 10,
        deadAtHatch: 5,
      );

      expect(summary.healthyHatchedPct, 85.0);
      expect(summary.culledPct, 1.0);
      expect(summary.deadAtHatchPct, 0.5);
    });

    test('does not emit impossible percentages above 100', () {
      final summary = HatchBudgetSummary(
        totalEggsSet: 100,
        healthyHatched: 101,
        culled: -1,
      );

      expect(summary.healthyHatchedPct, 0.0);
      expect(summary.culledPct, 0.0);
    });
  });
}
