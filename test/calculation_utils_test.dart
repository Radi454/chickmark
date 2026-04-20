
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/utils/calculation_utils.dart';

void main() {
  group('pasgarScore', () {
    test('returns 0.0 when sampleSize is 0', () {
      final result = CalculationUtils.pasgarScore(0, [5, 3, 2]);
      expect(result, 0.0);
    });

    test('calculates correct score with formula ((sampleSize * 10) - sum) / sampleSize', () {
      // Example: sampleSize 40, defect counts [5, 3, 2, 4, 3] = sum 17
      // Expected: ((40 * 10) - 17) / 40 = 383 / 40 = 9.575 → 9.6
      final result = CalculationUtils.pasgarScore(40, [5, 3, 2, 4, 3]);
      expect(result, 9.6);
    });

    test('returns 10.0 when no defects', () {
      final result = CalculationUtils.pasgarScore(40, [0, 0, 0, 0, 0]);
      expect(result, 10.0);
    });

    test('handles edge case with maximum defects', () {
      // All 40 chicks have defects in all 6 categories: sum = 240
      // Expected: ((40 * 10) - 240) / 40 = 160 / 40 = 4.0
      final result = CalculationUtils.pasgarScore(40, [40, 40, 40, 40, 40, 40]);
      expect(result, 4.0);
    });
  });

  group('uniformityPercent', () {
    test('returns 0.0 when values list is empty', () {
      final result = CalculationUtils.uniformityPercent([], 38.0, 42.0);
      expect(result, 0.0);
    });

    test('calculates correct percentage of values INSIDE range', () {
      // Values: [38.0, 39.0, 40.0, 41.0, 42.0, 43.0]
      // Range: 38.0 - 42.0
      // Inside range: 38.0, 39.0, 40.0, 41.0, 42.0 (5 values)
      // Expected: (5 / 6) * 100 = 83.3%
      final result = CalculationUtils.uniformityPercent(
        [38.0, 39.0, 40.0, 41.0, 42.0, 43.0],
        38.0,
        42.0,
      );
      expect(result, 83.3);
    });

    test('returns 100.0 when all values are inside range', () {
      final result = CalculationUtils.uniformityPercent(
        [39.0, 40.0, 41.0],
        38.0,
        42.0,
      );
      expect(result, 100.0);
    });

    test('returns 0.0 when all values are outside range', () {
      final result = CalculationUtils.uniformityPercent(
        [37.0, 43.0, 44.0],
        38.0,
        42.0,
      );
      expect(result, 0.0);
    });

    test('handles boundary values correctly', () {
      // Values exactly at boundaries should be counted as inside
      final result = CalculationUtils.uniformityPercent(
        [38.0, 42.0],
        38.0,
        42.0,
      );
      expect(result, 100.0);
    });
  });
}
