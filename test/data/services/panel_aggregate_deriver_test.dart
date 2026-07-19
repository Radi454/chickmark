import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/services/panel_aggregate_deriver.dart';

void main() {
  test('egg weight cache is always derived from raw readings', () {
    final result = PanelAggregateDeriver.derive('egg_quality', {
      'eggWeightsJson': '[50, 60, 70]',
      'eggSampleSize': 999,
      'eggAvgWeight': 999,
      'eggUniformityPct': 999,
      'eggCvPct': 999,
    });

    expect(result.row['eggSampleSize'], 3);
    expect(result.row['eggAvgWeight'], 60);
    expect(result.row['eggUniformityPct'], closeTo(33.3, 0.1));
    expect(result.row['eggCvPct'], isNot(999));
  });

  test('ratio caches use the declared numerator and denominator', () {
    final result = PanelAggregateDeriver.derive('egg_quality', {
      'uvTrayEggCount': 200,
      'uvAffectedCount': 10,
      'uvAffectedPct': 99,
    });

    expect(result.row['uvAffectedPct'], 5);
  });

  test('invalid raw denominator is surfaced as a quality flag', () {
    final result = PanelAggregateDeriver.derive('residue_breakout', {
      'traySize': 0,
      'infertileCount': 4,
    });

    expect(result.row['infertilePct'], isNull);
    expect(result.qualityFlags, contains('invalid_denominator'));
  });
}
