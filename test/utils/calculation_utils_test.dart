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
    test('stdDev uses sample standard deviation by default', () {
      expect(CalculationUtils.stdDev([70, 72, 74]), closeTo(2.0, 0.001));
    });
    test('cvPercent uses sample standard deviation', () {
      expect(CalculationUtils.cvPercent([70, 72, 74]), 2.8);
    });
    test('percentOf rejects invalid counts unless over 100 is allowed', () {
      expect(CalculationUtils.percentOf(101, 100), isNull);
      expect(CalculationUtils.percentOf(101, 100, allowAbove100: true), 101.0);
      expect(CalculationUtils.percentOf(-1, 100), isNull);
      expect(CalculationUtils.percentOf(1, 0), isNull);
    });
    test(
      'divideOrNull returns null for a missing, zero, or negative '
      'denominator (breeder-flock-performance ticket 09, design section '
      '7.2)',
      () {
        expect(CalculationUtils.divideOrNull(100, null), isNull);
        expect(CalculationUtils.divideOrNull(100, 0), isNull);
        expect(CalculationUtils.divideOrNull(100, -5), isNull);
        expect(CalculationUtils.divideOrNull(null, 100), isNull);
      },
    );
    test('divideOrNull computes and rounds a normal division', () {
      // Feed grams per bird: 25 kg * 1000 / 200 birds = 125 g/bird.
      expect(CalculationUtils.divideOrNull(25 * 1000, 200), 125.0);
      expect(
        CalculationUtils.divideOrNull(10, 3, decimalPlaces: 2),
        closeTo(3.33, 0.001),
      );
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
    test('stdDev known sample value', () {
      expect(
        CalculationUtils.stdDev([2, 4, 4, 4, 5, 5, 7, 9]),
        closeTo(2.138, 0.001),
      );
    });
    test('populationStdDev remains available for full-population datasets', () {
      expect(
        CalculationUtils.populationStdDev([2, 4, 4, 4, 5, 5, 7, 9]),
        closeTo(2.0, 0.1),
      );
    });

    group('shellTempZone / shellTempStatus', () {
      test('optimal at 19.0 °C', () {
        expect(CalculationUtils.shellTempZone(19.0), 'Optimal');
        expect(
          CalculationUtils.shellTempStatus(19.0),
          TemperatureStatus.optimal,
        );
      });
      test('optimal at 21.0 °C', () {
        expect(CalculationUtils.shellTempZone(21.0), 'Optimal');
        expect(
          CalculationUtils.shellTempStatus(21.0),
          TemperatureStatus.optimal,
        );
      });
      test('optimal at 20.0 °C', () {
        expect(CalculationUtils.shellTempZone(20.0), 'Optimal');
        expect(
          CalculationUtils.shellTempStatus(20.0),
          TemperatureStatus.optimal,
        );
      });
      test('low below 19.0 °C', () {
        expect(CalculationUtils.shellTempZone(18.5), 'Low');
        expect(CalculationUtils.shellTempStatus(18.5), TemperatureStatus.low);
      });
      test('high above 21.0 °C', () {
        expect(CalculationUtils.shellTempZone(22.0), 'High');
        expect(CalculationUtils.shellTempStatus(22.0), TemperatureStatus.high);
      });
      test('boundary: exactly 19.0 still optimal', () {
        expect(CalculationUtils.shellTempZone(19.0), 'Optimal');
      });
      test('boundary: exactly 21.0 still optimal', () {
        expect(CalculationUtils.shellTempZone(21.0), 'Optimal');
      });
    });

    group('estZone / estStatus', () {
      test('optimal at 100.0 °F', () {
        expect(CalculationUtils.estZone(100.0), 'Optimal');
        expect(CalculationUtils.estStatus(100.0), TemperatureStatus.optimal);
      });
      test('optimal at 101.0 °F', () {
        expect(CalculationUtils.estZone(101.0), 'Optimal');
        expect(CalculationUtils.estStatus(101.0), TemperatureStatus.optimal);
      });
      test('low below 100.0 °F', () {
        expect(CalculationUtils.estZone(99.5), 'Low');
        expect(CalculationUtils.estStatus(99.5), TemperatureStatus.low);
      });
      test('high above 101.0 °F', () {
        expect(CalculationUtils.estZone(102.0), 'High');
        expect(CalculationUtils.estStatus(102.0), TemperatureStatus.high);
      });
    });

    group('setterEstZone / setterEstStatus', () {
      test('optimal from 100.0 to 101.0 °F', () {
        expect(CalculationUtils.setterEstZone(100.0), 'Optimal');
        expect(
          CalculationUtils.setterEstStatus(100.0),
          TemperatureStatus.optimal,
        );
        expect(CalculationUtils.setterEstZone(101.0), 'Optimal');
        expect(
          CalculationUtils.setterEstStatus(101.0),
          TemperatureStatus.optimal,
        );
      });

      test('allowed outside optimum from 99.5 to 102.0 °F', () {
        expect(CalculationUtils.setterEstZone(99.5), 'Allowed');
        expect(CalculationUtils.setterEstStatus(99.5), TemperatureStatus.low);
        expect(CalculationUtils.setterEstZone(99.9), 'Allowed');
        expect(CalculationUtils.setterEstStatus(99.9), TemperatureStatus.low);
        expect(CalculationUtils.setterEstZone(101.5), 'Allowed');
        expect(CalculationUtils.setterEstStatus(101.5), TemperatureStatus.high);
        expect(CalculationUtils.setterEstZone(102.0), 'Allowed');
        expect(CalculationUtils.setterEstStatus(102.0), TemperatureStatus.high);
      });

      test('out of allowed range below 99.5 or above 102.0 °F', () {
        expect(CalculationUtils.setterEstZone(99.4), 'Low');
        expect(CalculationUtils.setterEstStatus(99.4), TemperatureStatus.low);
        expect(CalculationUtils.setterEstZone(102.1), 'High');
        expect(CalculationUtils.setterEstStatus(102.1), TemperatureStatus.high);
      });
    });

    group('cvtZone / cvtStatus', () {
      test('optimal at 103.0 °F', () {
        expect(CalculationUtils.cvtZone(103.0), 'Optimal');
        expect(CalculationUtils.cvtStatus(103.0), TemperatureStatus.optimal);
      });
      test('optimal at 105.0 °F', () {
        expect(CalculationUtils.cvtZone(105.0), 'Optimal');
        expect(CalculationUtils.cvtStatus(105.0), TemperatureStatus.optimal);
      });
      test('low below 103.0 °F', () {
        expect(CalculationUtils.cvtZone(102.0), 'Low');
        expect(CalculationUtils.cvtStatus(102.0), TemperatureStatus.low);
      });
      test('high above 105.0 °F', () {
        expect(CalculationUtils.cvtZone(106.0), 'High');
        expect(CalculationUtils.cvtStatus(106.0), TemperatureStatus.high);
      });
    });

    group('uvAffectedPct', () {
      test('returns 0.0 when sampleSize is 0', () {
        expect(CalculationUtils.uvAffectedPct(5, 0), 0.0);
      });
      test('calculates affected percentage', () {
        expect(CalculationUtils.uvAffectedPct(5, 100), 5.0);
      });
      test('handles 0 affected', () {
        expect(CalculationUtils.uvAffectedPct(0, 50), 0.0);
      });
      test('handles 100% affected', () {
        expect(CalculationUtils.uvAffectedPct(50, 50), 100.0);
      });
      test('rounds to one decimal', () {
        expect(CalculationUtils.uvAffectedPct(1, 3), closeTo(33.3, 0.1));
      });
    });

    group('overallUvAffectedAvg', () {
      test('returns 0.0 when list is empty', () {
        expect(CalculationUtils.overallUvAffectedAvg([]), 0.0);
      });
      test('calculates average of percentages', () {
        expect(CalculationUtils.overallUvAffectedAvg([5.0, 10.0, 15.0]), 10.0);
      });
      test('handles single value', () {
        expect(CalculationUtils.overallUvAffectedAvg([7.5]), 7.5);
      });
    });
  });
}
