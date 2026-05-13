import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/panel_sample_model.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';

void main() {
  test(
    'panel schema exposes one main table and one sample table per panel',
    () {
      expect(PanelSampleSchema.panels.length, 13);
      expect(
        PanelSampleSchema.panels.map((panel) => panel.tableName),
        containsAll([
          'egg_quality',
          'egg_weights',
          'chick_pasgar',
          'chick_weights',
          'fresh_egg_breakout',
          'candled_egg_breakout',
          'residue_breakout',
          'setter_optimizing',
          'hatcher_optimizing',
        ]),
      );

      for (final panel in PanelSampleSchema.panels) {
        expect(panel.sampleTableName, '${panel.tableName}_samples');
        expect(panel.allowedLayers.first, SamplingLayer.pool);
      }
    },
  );

  test('only approved panels expose tray comparison', () {
    final trayPanels = PanelSampleSchema.panels
        .where((panel) => panel.allowedLayers.contains(SamplingLayer.tray))
        .map((panel) => panel.tableName)
        .toList();

    expect(trayPanels, [
      'candled_egg_breakout',
      'residue_breakout',
      'setter_optimizing',
      'hatcher_optimizing',
    ]);
  });

  test('chick hatchery panels compare setter and hatcher together', () {
    for (final tableName in [
      'chick_pasgar',
      'chick_yfbm',
      'chick_cvt',
      'chick_pm',
    ]) {
      final panel = PanelSampleSchema.byTable(tableName);
      expect(panel.allowedLayers, contains(SamplingLayer.setterHatcher));
      expect(panel.allowedLayers, isNot(contains(SamplingLayer.tray)));
    }
  });

  test(
    'panel and sample records serialize dashboard context and scope identity',
    () {
      final panel = PanelRecord(
        id: 'panel-1',
        tableName: 'chick_pasgar',
        sessionId: 'session-1',
        auditId: 'audit-1',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: DateTime.utc(2026, 5, 13),
        hatcheryId: 'hatchery-1',
        breed: 'Ross308',
        flockAgeWeeks: 40,
        mode: PanelRecord.modeCompare,
        compareLayer: SamplingLayer.setterHatcher,
        metricsJson: '{"score":97.5}',
      );

      expect(panel.toMap()['compareLayer'], 'setter_hatcher');
      expect(panel.toMap()['date'], '2026-05-13T00:00:00.000Z');

      final sample = PanelSampleRecord(
        id: 'sample-1',
        panelId: 'panel-1',
        scopeType: SamplingLayer.setterHatcher,
        scopeLabel: 'S01 + H02',
        sampleIndex: 0,
        setterId: 'S01',
        hatcherId: 'H02',
        sampleSize: 100,
        summaryJson: '{"pasgarScore":97.5}',
      );

      expect(sample.toMap()['scopeType'], 'setter_hatcher');
      expect(sample.toMap()['setterId'], 'S01');
      expect(sample.toMap()['hatcherId'], 'H02');
    },
  );
}
