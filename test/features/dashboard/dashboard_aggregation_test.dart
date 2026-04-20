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
  });
}
