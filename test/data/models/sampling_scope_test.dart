import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';

void main() {
  test('sampling configs expose the approved scope matrix', () {
    final expected = <String, List<SamplingScopeLevel>>{
      'egg_storage': [],
      'egg_quality': [SamplingScopeLevel.house],
      'chick_quality': [SamplingScopeLevel.setter, SamplingScopeLevel.hatcher],
      'chick_weights': [SamplingScopeLevel.house],
      'fresh_egg_breakout': [SamplingScopeLevel.house],
      'candled_egg_breakout': [
        SamplingScopeLevel.house,
        SamplingScopeLevel.setter,
        SamplingScopeLevel.hatcher,
        SamplingScopeLevel.trolley,
        SamplingScopeLevel.tray,
      ],
      'residue_breakout': [
        SamplingScopeLevel.house,
        SamplingScopeLevel.setter,
        SamplingScopeLevel.hatcher,
        SamplingScopeLevel.trolley,
        SamplingScopeLevel.tray,
      ],
      'setter_optimizing': [
        SamplingScopeLevel.setter,
        SamplingScopeLevel.trolley,
        SamplingScopeLevel.tray,
      ],
      'hatcher_optimizing': [
        SamplingScopeLevel.hatcher,
        SamplingScopeLevel.trolley,
        SamplingScopeLevel.tray,
      ],
    };

    expect(PanelSampleSchema.panels, hasLength(expected.length));
    for (final entry in expected.entries) {
      final config = PanelSampleSchema.byTable(entry.key).samplingConfig;
      expect(config.panelKey, entry.key);
      expect(config.levels, entry.value, reason: entry.key);
      expect(
        config.terminalLevel,
        entry.value.contains(SamplingScopeLevel.tray)
            ? SamplingScopeLevel.tray
            : SamplingScopeLevel.sample,
      );
    }
    final chick = PanelSampleSchema.byTable('chick_quality').samplingConfig;
    expect(chick.pairedLevels, [
      SamplingScopeLevel.setter,
      SamplingScopeLevel.hatcher,
    ]);
    expect(chick.parentLevelOf(SamplingScopeLevel.hatcher), isNull);
    expect(
      () => PanelSampleSchema.byTable('candled_egg_breakout').samplingConfig
          .validatePath(
            SamplingScopePath(sampleId: 'trayless', sampleNumber: 1),
          ),
      throwsArgumentError,
    );
    expect(
      () =>
          PanelSampleSchema.byTable('egg_quality').samplingConfig.validatePath(
            SamplingScopePath(
              tray: 'T1',
              sampleId: 'wrong-tray',
              sampleNumber: 1,
            ),
          ),
      throwsArgumentError,
    );
    expect(
      () => chick.validatePath(
        SamplingScopePath(
          setter: 'S2',
          sampleId: 'partial-pair',
          sampleNumber: 1,
        ),
      ),
      throwsArgumentError,
    );
  });

  test(
    'scope paths retain paired identities and explicit unknown legacy levels',
    () {
      final path = SamplingScopePath(
        house: null,
        setter: 'setter-id-2',
        hatcher: 'hatcher-id-4',
        trolley: null,
        tray: 'tray-1',
        sampleId: 'sample-id',
        sampleNumber: 3,
        unknownLevels: {SamplingScopeLevel.house},
      );

      final restored = SamplingScopePath.fromJson(path.toJson());
      expect(restored.house, isNull);
      expect(restored.setter, 'setter-id-2');
      expect(restored.hatcher, 'hatcher-id-4');
      expect(restored.tray, 'tray-1');
      expect(restored.sampleId, 'sample-id');
      expect(restored.unknownLevels, {SamplingScopeLevel.house});
    },
  );

  test('configs reject duplicate or out-of-order scope levels', () {
    expect(
      () => PanelSamplingConfig(
        panelKey: 'invalid',
        levels: [SamplingScopeLevel.house, SamplingScopeLevel.house],
        terminalLevel: SamplingScopeLevel.sample,
        registeredIdentitySource: 'flocks',
      ),
      throwsArgumentError,
    );
    expect(
      () => PanelSamplingConfig(
        panelKey: 'invalid',
        levels: [SamplingScopeLevel.tray, SamplingScopeLevel.house],
        terminalLevel: SamplingScopeLevel.tray,
        registeredIdentitySource: 'flocks',
      ),
      throwsArgumentError,
    );
  });
}
