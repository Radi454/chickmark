enum SamplingLayer {
  pool('pool'),
  house('house'),
  setter('setter'),
  hatcher('hatcher'),
  setterHatcher('setter_hatcher'),
  trolley('trolley'),
  tray('tray');

  const SamplingLayer(this.dbValue);

  final String dbValue;

  static SamplingLayer fromDbValue(String value) {
    return SamplingLayer.values.firstWhere(
      (layer) => layer.dbValue == value,
      orElse: () => throw ArgumentError('Unknown sampling layer: $value'),
    );
  }
}

const kPanelHierarchyColumnDefinitions = [
  'house TEXT',
  'setter TEXT',
  'hatcher TEXT',
  'trolley TEXT',
  'tray TEXT',
  'position TEXT',
];

class PanelSampleDefinition {
  const PanelSampleDefinition({
    required this.tableName,
    required this.allowedLayers,
    required this.measurementColumns,
    this.hierarchyColumnDefinitions = kPanelHierarchyColumnDefinitions,
  });

  final String tableName;
  final List<SamplingLayer> allowedLayers;
  final List<String> measurementColumns;
  final List<String> hierarchyColumnDefinitions;

  List<String> get hierarchyColumnNames => hierarchyColumnDefinitions
      .map((definition) => definition.trim().split(RegExp(r'\s+')).first)
      .toList(growable: false);

  @Deprecated(
    'Panel sample child tables were removed in the panel-only cutover.',
  )
  String get sampleTableName => '${tableName}_samples';
}

class PanelSampleSchema {
  const PanelSampleSchema._();

  /// Panel tables whose row identity is the row id itself, not the hierarchy
  /// tuple. `egg_quality` is here because a comparison row may legitimately
  /// have a blank or duplicated house, and matching on hierarchy makes two
  /// such rows overwrite each other.
  ///
  /// Defined here (rather than on `PanelSampleRepository`, which is where
  /// callers reference it as `PanelSampleRepository.idKeyedPanelTables`) to
  /// avoid an import cycle: `database_schema.dart` is a `part of
  /// database_helper.dart`, and `panel_sample_repository.dart` imports
  /// `database_helper.dart`.
  static const Set<String> idKeyedPanelTables = {'egg_quality'};

  static const panels = <PanelSampleDefinition>[
    PanelSampleDefinition(
      tableName: 'egg_storage',
      allowedLayers: [SamplingLayer.pool],
      measurementColumns: [
        'estReadingsJson TEXT',
        'estAvg REAL',
        'estCvPct REAL',
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
      allowedLayers: [SamplingLayer.pool, SamplingLayer.house],
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
      allowedLayers: [SamplingLayer.pool, SamplingLayer.setterHatcher],
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
        'pmPhotosJson TEXT',
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
        SamplingLayer.setterHatcher,
        SamplingLayer.trolley,
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
        SamplingLayer.trolley,
        SamplingLayer.tray,
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
      allowedLayers: [SamplingLayer.setter],
      hierarchyColumnDefinitions: ['setter TEXT'],
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
        'co2Photo TEXT',
        'estBreed TEXT',
        'incubationAgeDays INTEGER',
        'incubationHours INTEGER',
        'estReadingsJson TEXT',
        'estPhotosJson TEXT',
        'estSamplesJson TEXT',
        'estSampleSize INTEGER',
        'estAvg REAL',
        'estCvPct REAL',
        'machineScreenPhoto TEXT',
      ],
    ),
    PanelSampleDefinition(
      tableName: 'hatcher_optimizing',
      allowedLayers: [SamplingLayer.hatcher],
      hierarchyColumnDefinitions: ['hatcher TEXT'],
      measurementColumns: [
        'setpointF REAL',
        'setpointRh REAL',
        'incubationAgeDays INTEGER',
        'incubationHours INTEGER',
        'co2Ppm REAL',
        'co2Photo TEXT',
        'cvtReadingsJson TEXT',
        'cvtPhotosJson TEXT',
        'cvtSampleSize INTEGER',
        'cvtAvg REAL',
        'cvtCvPct REAL',
        'chickPanting INTEGER',
        'chickPantingPhoto TEXT',
        'meconium TEXT',
        'transferDay INTEGER',
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
