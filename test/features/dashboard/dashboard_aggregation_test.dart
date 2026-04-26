import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/utils/calculation_utils.dart';
import 'package:hatchaudit/core/utils/temp_converter.dart';
import 'package:hatchaudit/features/dashboard/models/hatch_analysis_models.dart';

void main() {
  group('Dashboard aggregation helpers', () {
    test('HatchAnalysisAvg reads averaged raw rows', () {
      final avg = HatchAnalysisAvg.fromMap({
        'hatchabilityPct': 89.5,
        'fertilityPct': 94.0,
        'hofPct': 95.2,
        'culledPct': 0.8,
        'deadPct': 0.1,
      });

      expect(avg.hatchabilityPct, 89.5);
      expect(avg.fertilityPct, 94.0);
      expect(avg.hofPct, 95.2);
      expect(avg.culledPct, 0.8);
      expect(avg.deadPct, 0.1);
    });

    test('CV% formula uses sample standard deviation', () {
      expect(CalculationUtils.cvPercent([90, 100, 110]), closeTo(10.0, 0.1));
    });

    test('Temperature conversion F to C', () {
      expect(TempConverter.toCelsius(104), closeTo(40, 0.01));
    });

    test('Temperature conversion C to F', () {
      expect(TempConverter.toFahrenheit(40), closeTo(104, 0.01));
    });

    test('Breakout severity OK/Medium/High thresholds', () {
      String severity(double actual, double bmk) {
        if (actual <= bmk) return 'OK';
        if (actual <= bmk + 3) return 'Medium';
        return 'High';
      }

      expect(severity(1.0, 1.0), 'OK');
      expect(severity(3.5, 1.0), 'Medium');
      expect(severity(4.1, 1.0), 'High');
    });

    test('all single-category percentages compute correctly', () {
      expect(_hatchPct(8500, 10000), closeTo(85.0, 0.01));
      expect(_hatchPct(500, 10000), closeTo(5.0, 0.01));
      expect(_hatchPct(0, 10000), 0.0);
      expect(_hatchPct(0, 0), 0.0);
    });
  });

  group('Hatch benchmark status calculation', () {
    test('returns OK when actual percentage is at or below BMK', () {
      String status(double actualPct, double bmkPct) {
        if (actualPct <= bmkPct) return 'OK';
        if (actualPct <= bmkPct + 3.0) return 'Medium';
        return 'High';
      }

      expect(status(1.0, 1.5), 'OK');
      expect(status(3.0, 3.0), 'OK');
      expect(status(0.0, 1.0), 'OK');
    });

    test('returns Medium when actual is within 3% above BMK', () {
      String status(double actualPct, double bmkPct) {
        if (actualPct <= bmkPct) return 'OK';
        if (actualPct <= bmkPct + 3.0) return 'Medium';
        return 'High';
      }

      expect(status(3.5, 1.0), 'Medium');
      expect(status(4.0, 1.0), 'Medium');
      expect(status(1.1, 0.5), 'Medium');
    });

    test('returns High when actual exceeds BMK + 3%', () {
      String status(double actualPct, double bmkPct) {
        if (actualPct <= bmkPct) return 'OK';
        if (actualPct <= bmkPct + 3.0) return 'Medium';
        return 'High';
      }

      expect(status(4.1, 1.0), 'High');
      expect(status(10.0, 1.0), 'High');
      expect(status(5.0, 1.5), 'High');
    });

    test('handles BMK of zero', () {
      String status(double actualPct, double bmkPct) {
        if (actualPct <= bmkPct) return 'OK';
        if (actualPct <= bmkPct + 3.0) return 'Medium';
        return 'High';
      }

      expect(status(0.0, 0.0), 'OK');
      expect(status(2.0, 0.0), 'Medium');
      expect(status(4.0, 0.0), 'High');
    });

    test('culledPct 1% BMK threshold', () {
      String culledStatus(double actualPct) {
        const bmk = 1.0;
        if (actualPct <= bmk) return 'OK';
        if (actualPct <= bmk + 3.0) return 'Medium';
        return 'High';
      }

      expect(culledStatus(0.5), 'OK');
      expect(culledStatus(1.0), 'OK');
      expect(culledStatus(3.0), 'Medium');
      expect(culledStatus(5.0), 'High');
    });

    test('deadPct 0.2% BMK threshold', () {
      String deadStatus(double actualPct) {
        const bmk = 0.2;
        if (actualPct <= bmk) return 'OK';
        if (actualPct <= bmk + 3.0) return 'Medium';
        return 'High';
      }

      expect(deadStatus(0.1), 'OK');
      expect(deadStatus(0.2), 'OK');
      expect(deadStatus(2.0), 'Medium');
      expect(deadStatus(4.0), 'High');
    });
  });
}

double _hatchPct(int count, int total) {
  if (total <= 0) return 0.0;
  return (count / total) * 100;
}
