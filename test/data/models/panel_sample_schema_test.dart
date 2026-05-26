import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/panel_sample_model.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';

void main() {
  test('panel schema exposes one storage table per panel', () {
    expect(PanelSampleSchema.panels.length, 9);
    expect(
      PanelSampleSchema.panels.map((panel) => panel.tableName),
      containsAll([
        'egg_quality',
        'chick_quality',
        'chick_weights',
        'fresh_egg_breakout',
        'candled_egg_breakout',
        'residue_breakout',
        'setter_optimizing',
        'hatcher_optimizing',
      ]),
    );
    expect(
      PanelSampleSchema.panels.map((panel) => panel.tableName),
      isNot(contains('egg_weights')),
    );
    expect(
      PanelSampleSchema.panels.map((panel) => panel.tableName),
      isNot(
        containsAll(['chick_pasgar', 'chick_yfbm', 'chick_cvt', 'chick_pm']),
      ),
    );

    for (final panel in PanelSampleSchema.panels) {
      expect(panel.measurementColumns, isNotEmpty);
    }
  });

  test('panel measurements do not duplicate common hierarchy columns', () {
    const commonColumns = {
      'house',
      'setter',
      'hatcher',
      'trolley',
      'tray',
      'position',
      'storagePeriodDays',
      'bmkAgeWeeks',
    };

    for (final panel in PanelSampleSchema.panels) {
      final measurementNames = panel.measurementColumns
          .map((definition) => definition.split(RegExp(r'\s+')).first)
          .toSet();
      expect(
        measurementNames.intersection(commonColumns),
        isEmpty,
        reason: panel.tableName,
      );
    }
  });

  test('egg quality schema consolidates shell UV and weight metrics', () {
    final panel = PanelSampleSchema.byTable('egg_quality');

    expect(
      panel.measurementColumns,
      containsAll([
        'uvTrayEggCount INTEGER',
        'uvCuticleDamageCount INTEGER',
        'uvCuticleDamagePct REAL',
        'uvWashedCount INTEGER',
        'uvWashedPct REAL',
        'uvDirtyCount INTEGER',
        'uvDirtyPct REAL',
        'uvAffectedCount INTEGER',
        'uvAffectedPct REAL',
        'eggWeightsJson TEXT',
        'eggSampleSize INTEGER',
        'eggAvgWeight REAL',
        'eggUniformityPct REAL',
        'eggCvPct REAL',
        'eggBmkAgeWeeks INTEGER',
        'eggBmkWeight REAL',
      ]),
    );
    expect(
      panel.measurementColumns,
      isNot(contains('upsideDownCount INTEGER')),
    );
    expect(panel.measurementColumns, isNot(contains('upsideDownPct REAL')));
  });

  test('egg storage schema owns upside-down score fields', () {
    final panel = PanelSampleSchema.byTable('egg_storage');

    expect(
      panel.measurementColumns,
      containsAll(['upsideDownCount INTEGER', 'upsideDownPct REAL']),
    );
  });

  test(
    'setter optimizing schema includes machine temperature and RH readings',
    () {
      final panel = PanelSampleSchema.byTable('setter_optimizing');

      expect(panel.allowedLayers, [
        SamplingLayer.setter,
        SamplingLayer.trolley,
        SamplingLayer.tray,
      ]);
      expect(panel.hierarchyColumnNames, ['setter', 'trolley', 'tray']);
      expect(
        panel.measurementColumns,
        containsAll([
          'setpointF REAL',
          'actualF REAL',
          'setpointRh REAL',
          'actualRh REAL',
          'co2Photo TEXT',
          'estPhotosJson TEXT',
          'estSamplesJson TEXT',
          'machineScreenPhoto TEXT',
        ]),
      );
    },
  );

  test('hatcher optimizing schema includes machine setpoint readings', () {
    final panel = PanelSampleSchema.byTable('hatcher_optimizing');

    expect(panel.allowedLayers, [
      SamplingLayer.hatcher,
      SamplingLayer.trolley,
      SamplingLayer.tray,
    ]);
    expect(panel.hierarchyColumnNames, ['hatcher', 'trolley', 'tray']);
    expect(
      panel.measurementColumns,
      containsAll([
        'setpointF REAL',
        'setpointRh REAL',
        'co2Photo TEXT',
        'cvtPhotosJson TEXT',
        'chickPantingPhoto TEXT',
        'transferDay INTEGER',
      ]),
    );
  });

  test('breakout schemas include current versus BMK diff columns', () {
    expect(PanelSampleSchema.byTable('fresh_egg_breakout').allowedLayers, [
      SamplingLayer.pool,
      SamplingLayer.house,
      SamplingLayer.tray,
    ]);
    expect(PanelSampleSchema.byTable('candled_egg_breakout').allowedLayers, [
      SamplingLayer.pool,
      SamplingLayer.house,
      SamplingLayer.setterHatcher,
      SamplingLayer.trolley,
      SamplingLayer.tray,
    ]);
    expect(PanelSampleSchema.byTable('residue_breakout').allowedLayers, [
      SamplingLayer.pool,
      SamplingLayer.house,
      SamplingLayer.setterHatcher,
      SamplingLayer.trolley,
      SamplingLayer.tray,
      SamplingLayer.batch,
    ]);
    expect(
      PanelSampleSchema.byTable('fresh_egg_breakout').measurementColumns,
      containsAll([
        'infertileDiffPct REAL',
        'early24hDiffPct REAL',
        'early48hDiffPct REAL',
        'bloodRingDiffPct REAL',
      ]),
    );
    expect(
      PanelSampleSchema.byTable('candled_egg_breakout').measurementColumns,
      contains('blackEyeDiffPct REAL'),
    );
    expect(
      PanelSampleSchema.byTable('residue_breakout').measurementColumns,
      containsAll([
        'infertileDiffPct REAL',
        'earlyDeadDiffPct REAL',
        'midDeadDiffPct REAL',
        'lateDeadDiffPct REAL',
        'externalPipDiffPct REAL',
        'crackedDiffPct REAL',
        'contaminatedDiffPct REAL',
      ]),
    );
  });

  test('chick quality schema consolidates optional quality checks', () {
    final panel = PanelSampleSchema.byTable('chick_quality');

    expect(panel.allowedLayers, contains(SamplingLayer.house));
    expect(panel.allowedLayers, contains(SamplingLayer.setterHatcher));
    expect(
      panel.measurementColumns,
      containsAll([
        'pasgarSampleSize INTEGER',
        'pasgarReflexesCount INTEGER',
        'pasgarFinalScore REAL',
        'co2Ppm REAL',
        'co2Photo TEXT',
        'pm10 REAL',
        'pm10Photo TEXT',
        'pm25 REAL',
        'pm25Photo TEXT',
        'airVelocitySpot1 REAL',
        'airVelocitySpot1Photo TEXT',
        'airVelocitySpot2 REAL',
        'airVelocitySpot2Photo TEXT',
        'airVelocitySpot3 REAL',
        'airVelocitySpot3Photo TEXT',
        'airInlet REAL',
        'airInletPhoto TEXT',
        'airOutlet REAL',
        'airOutletPhoto TEXT',
        'noiseLevel REAL',
        'noiseLevelPhoto TEXT',
        'yfbmPhoto TEXT',
        'yfbmEntriesJson TEXT',
        'yfbmEntryCount INTEGER',
        'yfbmAvgPct REAL',
        'yfbmCvPct REAL',
        'cvtReadingsJson TEXT',
        'cvtPhotosJson TEXT',
        'cvtSampleSize INTEGER',
        'cvtTopBasket TEXT',
        'cvtTopTemp REAL',
        'cvtTopPhoto TEXT',
        'cvtMiddleBasket TEXT',
        'cvtMiddleTemp REAL',
        'cvtMiddlePhoto TEXT',
        'cvtBottomBasket TEXT',
        'cvtBottomTemp REAL',
        'cvtBottomPhoto TEXT',
        'cvtAvgTemp REAL',
        'cvtCvPct REAL',
        'pmSampleSize INTEGER',
        'pmCollectionPoint TEXT',
        'pmPhotosJson TEXT',
        'culledChicksTotalEggSet INTEGER',
        'culledChicksAnalysisJson TEXT',
        'culledChicksAffectedPct REAL',
        'culledChicksTopCategory TEXT',
        'culledChicksTopSubtype TEXT',
      ]),
    );
    expect(panel.measurementColumns, isNot(contains('sampleSize INTEGER')));
    expect(panel.measurementColumns, isNot(contains('cvPct REAL')));
  });

  test('chick PM schema includes the revised lesion backend fields', () {
    final panel = PanelSampleSchema.byTable('chick_quality');

    expect(
      panel.measurementColumns,
      containsAll([
        'pmGizzardErosionsCount INTEGER',
        'pmGizzardErosionsSeverity TEXT',
        'pmAirSacCaseationsCount INTEGER',
        'pmAirSacCaseationsSeverity TEXT',
        'pmUrolithiasisCount INTEGER',
        'pmUrolithiasisSeverity TEXT',
        'pmNephritisCount INTEGER',
        'pmNephritisSeverity TEXT',
        'pmGeneralSepticemiaCount INTEGER',
        'pmGeneralSepticemiaSeverity TEXT',
        'pmOtherLesionsJson TEXT',
        'pmPhotosJson TEXT',
      ]),
    );
    for (final column in [
      'pmUnabsorbedYolkCount INTEGER',
      'pmUnabsorbedYolkSeverity TEXT',
      'pmPerihepatitisCount INTEGER',
      'pmPerihepatitisSeverity TEXT',
      'pmPericarditisCount INTEGER',
      'pmPericarditisSeverity TEXT',
      'pmAirsacAcuteCount INTEGER',
      'pmAirsacAcuteSeverity TEXT',
      'pmAirsacChronicCount INTEGER',
      'pmAirsacChronicSeverity TEXT',
      'pmPulmonaryGranulomaCount INTEGER',
      'pmPulmonaryGranulomaSeverity TEXT',
      'pmSwollenJointsCount INTEGER',
      'pmSwollenJointsSeverity TEXT',
      'pmStuntedOrgansCount INTEGER',
      'pmStuntedOrgansSeverity TEXT',
      'pmPulmonaryHemorrhageCount INTEGER',
      'pmPulmonaryHemorrhageSeverity TEXT',
      'pmGaspingPresent INTEGER',
      'pmGaspingType TEXT',
      'pmExposedBrainCount INTEGER',
      'pmEctopicVisceraCount INTEGER',
      'pmExtraLegsCount INTEGER',
      'pmCrossedBeakCount INTEGER',
      'pmAbsentEyeBothCount INTEGER',
      'pmAbsentEyeOneCount INTEGER',
      'pmSmallEyeCount INTEGER',
      'pmHydrocephalyCount INTEGER',
      'pmStarGazerCount INTEGER',
      'pmCurledToesCount INTEGER',
      'pmShortLegsCount INTEGER',
      'pmSpinalDeformityCount INTEGER',
      'pmCardiacAnomalyCount INTEGER',
      'pmConjoinedCount INTEGER',
      'pmOtherDeformityCount INTEGER',
      'pmOtherDeformityText TEXT',
    ]) {
      expect(panel.measurementColumns, isNot(contains(column)));
    }
  });

  test(
    'panel and sample records serialize dashboard context and hierarchy',
    () {
      final panel = PanelRecord(
        id: 'panel-1',
        tableName: 'chick_quality',
        sessionId: 'session-1',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: DateTime.utc(2026, 5, 13),
        hatcheryId: 'hatchery-1',
        breed: 'Ross308',
        flockAgeWeeks: 40,
        house: 'House A',
        setter: 'S01',
        hatcher: 'H02',
        trolley: 'T01',
        tray: 'Tray 03',
        position: 'top',
        storagePeriodDays: 4,
        bmkAgeWeeks: 40,
        values: const {'pasgarFinalScore': 97.5},
      );

      expect(panel.toMap()['house'], 'House A');
      expect(panel.toMap()['setter'], 'S01');
      expect(panel.toMap()['hatcher'], 'H02');
      expect(panel.toMap()['trolley'], 'T01');
      expect(panel.toMap()['tray'], 'Tray 03');
      expect(panel.toMap()['position'], 'top');
      expect(panel.toMap()['storagePeriodDays'], 4);
      expect(panel.toMap(), isNot(contains('bmkAgeDays')));
      expect(panel.toMap()['bmkAgeWeeks'], 40);
      expect(panel.toMap()['date'], '2026-05-13');
      expect(panel.toMap()['pasgarFinalScore'], 97.5);

      final sample = PanelSampleRecord(
        id: 'sample-1',
        panelId: 'panel-1',
        houseId: 'House A',
        setterId: 'S01',
        hatcherId: 'H02',
        trolleyId: 'T01',
        trayId: 'Tray 03',
        position: 'top',
        sampleSize: 100,
        summaryJson: '{"pasgarScore":97.5}',
      );

      expect(sample.toMap()['houseId'], 'House A');
      expect(sample.toMap()['setterId'], 'S01');
      expect(sample.toMap()['hatcherId'], 'H02');
      expect(sample.toMap()['trolleyId'], 'T01');
      expect(sample.toMap()['trayId'], 'Tray 03');
      expect(sample.toMap()['position'], 'top');
    },
  );
}
