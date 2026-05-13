import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/dashboard/models/egg_breakout_models.dart';

void main() {
  group('EggBreakoutAvg.fromHatchBudget', () {
    test('calculates category percentages from total eggs set', () {
      final avg = EggBreakoutAvg.fromHatchBudget({
        'haTotalEggsSet': 1000,
        'haInfertileClear': 100,
        'haEarlyDead': 50,
        'haMidDead': 25,
        'haLateDead': 10,
        'haPipped': 20,
        'haContaminatedExploders': 5,
        'haCulled': 2,
      }, 'legacy');

      expect(avg.infertilePct, 10.0);
      expect(avg.internalPipPct, 1.0);
      expect(avg.externalPipPct, 1.0);
      expect(avg.cullPct, 0.2);
    });

    test('does not emit impossible percentages above 100', () {
      final avg = EggBreakoutAvg.fromHatchBudget({
        'haTotalEggsSet': 100,
        'haInfertileClear': 101,
        'haPipped': 250,
      }, 'legacy');

      expect(avg.infertilePct, 0.0);
      expect(avg.internalPipPct, 0.0);
      expect(avg.externalPipPct, 0.0);
    });
  });

  group('EggBreakoutTrend.fromHatchBudget', () {
    test('does not emit impossible trend percentages above 100', () {
      final trend = EggBreakoutTrend.fromHatchBudget({
        'date': '2026-05-13',
        'haTotalEggsSet': 100,
        'haInfertileClear': 101,
      }, 'legacy');

      expect(trend.percentages['infertile'], 0.0);
    });
  });
}
