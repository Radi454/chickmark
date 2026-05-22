enum SamplingLayer {
  pool('pool'),
  house('house'),
  setter('setter'),
  hatcher('hatcher'),
  setterHatcher('setter_hatcher'),
  trolley('trolley'),
  tray('tray'),
  batch('batch');

  const SamplingLayer(this.dbValue);

  final String dbValue;

  static SamplingLayer fromDbValue(String value) {
    return SamplingLayer.values.firstWhere(
      (layer) => layer.dbValue == value,
      orElse: () => throw ArgumentError('Unknown sampling layer: $value'),
    );
  }
}

class PanelSampleDefinition {
  const PanelSampleDefinition({
    required this.tableName,
    required this.allowedLayers,
    required this.measurementColumns,
  });

  final String tableName;
  final List<SamplingLayer> allowedLayers;
  final List<String> measurementColumns;

  @Deprecated(
    'Panel sample child tables were removed in the panel-only cutover.',
  )
  String get sampleTableName => '${tableName}_samples';
}

class PanelSampleSchema {
  const PanelSampleSchema._();

  static const panels = <PanelSampleDefinition>[
    PanelSampleDefinition(
      tableName: 'egg_storage',
      allowedLayers: [SamplingLayer.pool, SamplingLayer.house],
      measurementColumns: [
        'estReadingsJson TEXT',
        'estAvg REAL',
        'estCvPct REAL',
        'shellTemp REAL',
        'turningTimes INTEGER',
        'traySpacing TEXT',
        'coolerProximity TEXT',
        'condensationPresent INTEGER',
        'upsideDownCount INTEGER',
        'upsideDownPct REAL',
      ],
    ),
    PanelSampleDefinition(
      tableName: 'egg_quality',
      allowedLayers: [
        SamplingLayer.pool,
        SamplingLayer.house,
        SamplingLayer.setterHatcher,
      ],
      measurementColumns: [
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
      ],
    ),
    PanelSampleDefinition(
      tableName: 'chick_quality',
      allowedLayers: [
        SamplingLayer.pool,
        SamplingLayer.house,
        SamplingLayer.setterHatcher,
      ],
      measurementColumns: [
        'pasgarSampleSize INTEGER',
        'pasgarReflexesCount INTEGER',
        'pasgarBeakCount INTEGER',
        'pasgarNavelCount INTEGER',
        'pasgarBellyCount INTEGER',
        'pasgarLegCount INTEGER',
        'pasgarFeatherDevCount INTEGER',
        'pasgarReflexesPct REAL',
        'pasgarBeakPct REAL',
        'pasgarNavelPct REAL',
        'pasgarBellyPct REAL',
        'pasgarLegPct REAL',
        'pasgarFeatherDevPct REAL',
        'pasgarFinalScore REAL',
        'yfbmEntriesJson TEXT',
        'yfbmEntryCount INTEGER',
        'yfbmAvgPct REAL',
        'yfbmCvPct REAL',
        'cvtReadingsJson TEXT',
        'cvtSampleSize INTEGER',
        'cvtAvgTemp REAL',
        'cvtCvPct REAL',
        'pmSampleSize INTEGER',
        'pmCollectionPoint TEXT',
        'pmOmphalitisCount INTEGER',
        'pmOmphalitisSeverity TEXT',
        'pmGaseousCecaCount INTEGER',
        'pmGaseousCecaSeverity TEXT',
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
        'pmSuspectedCauseAuto TEXT',
        'pmSuspectedCauseManual TEXT',
        'culledChicksTotalEggSet INTEGER',
        'culledChicksAnalysisJson TEXT',
        'culledChicksAffectedPct REAL',
        'culledChicksTopCategory TEXT',
        'culledChicksTopSubtype TEXT',
      ],
    ),
    PanelSampleDefinition(
      tableName: 'chick_weights',
      allowedLayers: [SamplingLayer.pool, SamplingLayer.house],
      measurementColumns: [
        'weightsJson TEXT',
        'sampleSize INTEGER',
        'avgWeight REAL',
        'uniformityPct REAL',
        'cvPct REAL',
        'bmkWeight REAL',
      ],
    ),
    PanelSampleDefinition(
      tableName: 'fresh_egg_breakout',
      allowedLayers: [
        SamplingLayer.pool,
        SamplingLayer.house,
        SamplingLayer.tray,
      ],
      measurementColumns: [
        'traySize INTEGER',
        'infertileCount INTEGER',
        'early24hCount INTEGER',
        'early48hCount INTEGER',
        'bloodRingCount INTEGER',
        'infertilePct REAL',
        'early24hPct REAL',
        'early48hPct REAL',
        'bloodRingPct REAL',
        'infertileDiffPct REAL',
        'early24hDiffPct REAL',
        'early48hDiffPct REAL',
        'bloodRingDiffPct REAL',
      ],
    ),
    PanelSampleDefinition(
      tableName: 'candled_egg_breakout',
      allowedLayers: [
        SamplingLayer.pool,
        SamplingLayer.house,
        SamplingLayer.setter,
        SamplingLayer.tray,
      ],
      measurementColumns: [
        'candlingDay INTEGER',
        'traySize INTEGER',
        'infertileCount INTEGER',
        'early24hCount INTEGER',
        'early48hCount INTEGER',
        'bloodRingCount INTEGER',
        'blackEyeCount INTEGER',
        'infertilePct REAL',
        'early24hPct REAL',
        'early48hPct REAL',
        'bloodRingPct REAL',
        'blackEyePct REAL',
        'infertileDiffPct REAL',
        'early24hDiffPct REAL',
        'early48hDiffPct REAL',
        'bloodRingDiffPct REAL',
        'blackEyeDiffPct REAL',
      ],
    ),
    PanelSampleDefinition(
      tableName: 'residue_breakout',
      allowedLayers: [
        SamplingLayer.pool,
        SamplingLayer.house,
        SamplingLayer.setterHatcher,
        SamplingLayer.tray,
        SamplingLayer.batch,
      ],
      measurementColumns: [
        'traySize INTEGER',
        'infertileCount INTEGER',
        'earlyDeadCount INTEGER',
        'midDeadCount INTEGER',
        'lateDeadCount INTEGER',
        'externalPipCount INTEGER',
        'crackedCount INTEGER',
        'contaminatedCount INTEGER',
        'infertilePct REAL',
        'earlyDeadPct REAL',
        'midDeadPct REAL',
        'lateDeadPct REAL',
        'externalPipPct REAL',
        'crackedPct REAL',
        'contaminatedPct REAL',
        'infertileDiffPct REAL',
        'earlyDeadDiffPct REAL',
        'midDeadDiffPct REAL',
        'lateDeadDiffPct REAL',
        'externalPipDiffPct REAL',
        'crackedDiffPct REAL',
        'contaminatedDiffPct REAL',
        'totalEggsSet INTEGER',
        'hatchedCount INTEGER',
        'culledCount INTEGER',
        'deadCount INTEGER',
        'hatchabilityPct REAL',
        'fertilityPct REAL',
        'hofPct REAL',
        'culledPct REAL',
        'deadPct REAL',
      ],
    ),
    PanelSampleDefinition(
      tableName: 'setter_optimizing',
      allowedLayers: [
        SamplingLayer.pool,
        SamplingLayer.setter,
        SamplingLayer.trolley,
        SamplingLayer.tray,
      ],
      measurementColumns: [
        'machineType TEXT',
        'setpointF REAL',
        'actualF REAL',
        'setpointRh REAL',
        'actualRh REAL',
        'batchSize INTEGER',
        'batchCount INTEGER',
        'totalEggsSet INTEGER',
        'turningAngle REAL',
        'co2Ppm REAL',
        'estBreed TEXT',
        'incubationAgeDays INTEGER',
        'incubationHours INTEGER',
        'estReadingsJson TEXT',
        'estSampleSize INTEGER',
        'estAvg REAL',
        'estCvPct REAL',
      ],
    ),
    PanelSampleDefinition(
      tableName: 'hatcher_optimizing',
      allowedLayers: [
        SamplingLayer.pool,
        SamplingLayer.hatcher,
        SamplingLayer.trolley,
        SamplingLayer.tray,
      ],
      measurementColumns: [
        'setpointF REAL',
        'setpointRh REAL',
        'incubationAgeDays INTEGER',
        'incubationHours INTEGER',
        'co2Ppm REAL',
        'cvtReadingsJson TEXT',
        'cvtSampleSize INTEGER',
        'cvtAvg REAL',
        'cvtCvPct REAL',
        'chickPanting INTEGER',
        'meconium TEXT',
      ],
    ),
  ];

  static PanelSampleDefinition byTable(String tableName) {
    return panels.firstWhere(
      (panel) => panel.tableName == tableName,
      orElse: () => throw ArgumentError('Unknown panel table: $tableName'),
    );
  }
}
