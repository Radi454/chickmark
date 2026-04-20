import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/utils/calculation_utils.dart';

void main() {
  group('CalculationUtils', () {
    test('cvPercent([100,100,100]) == 0.0', () {
      expect(CalculationUtils.cvPercent([100, 100, 100]), 0.0);
    });
    test('cvPercent([90,100,110]) known value', () {
      expect(CalculationUtils.cvPercent([90, 100, 110]), closeTo(10.0, 0.1));
    });
    test('uniformityPercent all-in-range = 100%', () {
      expect(
        CalculationUtils.uniformityPercent([100, 100, 100], 100, 100),
        100.0,
      );
    });
    test('uniformityPercent some out-of-range', () {
      expect(
        CalculationUtils.uniformityPercent([90, 100, 110], 95, 105),
        closeTo(33.3, 0.1),
      );
    });
    test('pasgarScore(40, [2,1,0,1,2]) == 9.8', () {
      expect(CalculationUtils.pasgarScore(40, [2, 1, 0, 1, 2]), 9.8);
    });
    test('pasgarScore(40, [0,0,0,0,0]) == 10.0', () {
      expect(CalculationUtils.pasgarScore(40, [0, 0, 0, 0, 0]), 10.0);
    });
    test('hatchability(900, 1000) == 90.0', () {
      expect(CalculationUtils.hatchability(900, 1000), 90.0);
    });
    test('hatchability(0, 1000) == 0.0', () {
      expect(CalculationUtils.hatchability(0, 1000), 0.0);
    });
    test('fertility(150, 0) == 100.0', () {
      expect(CalculationUtils.fertility(150, 0), 100.0);
    });
    test('fertility(150, 15) == 90.9', () {
      expect(CalculationUtils.fertility(150, 15), 90.9);
    });
    test('hof(90.0, 95.0) known value', () {
      expect(CalculationUtils.hof(90.0, 95.0), closeTo(94.7, 0.1));
    });
    test('average([1,2,3]) == 2.0', () {
      expect(CalculationUtils.average([1, 2, 3]), 2.0);
    });
    test('stdDev known value', () {
      expect(
        CalculationUtils.stdDev([2, 4, 4, 4, 5, 5, 7, 9]),
        closeTo(2.0, 0.1),
      );
    });
  });
}
