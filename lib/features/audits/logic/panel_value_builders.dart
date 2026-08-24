import 'dart:convert';

import '../../../data/agent/station_adapter.dart';
import '../../../data/agent/station_registry.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/station_sample_model.dart';
import '../models/culled_chicks_analysis.dart';
import '../models/egg_breakout_sample.dart';
import '../models/egg_grading.dart';
import '../models/temperature_entry_unit.dart';
import '../models/temperature_readings_payload.dart';
import 'audit_value_parsing.dart';
import 'breakout_value_builders.dart';

/// The panel tables a draft's audit type saves rows into.
List<String> panelTablesForDraft(AuditModel draft) {
  return switch (draft.auditType) {
    'Egg' => const ['egg_storage', 'egg_quality'],
    'Chicks' => const ['chick_quality'],
    'Hatch Analysis & Egg Breakouts' => [
      switch (EggBreakoutType.fromStorageValue(draft.ebBreakoutType)) {
        EggBreakoutType.freshEggBreakout => 'fresh_egg_breakout',
        EggBreakoutType.candledEggBreakout => 'candled_egg_breakout',
        EggBreakoutType.residueHatchDay => 'residue_breakout',
      },
    ],
    'Setters' => const ['setter_optimizing'],
    'Hatchers' => const ['hatcher_optimizing'],
    _ => const [],
  };
}

/// The measurement-column values for a single panel table.
///
/// The egg-breakout branches call straight into `breakout_value_builders.dart`;
/// `flockAgeWeeks`/`flockEntryDate` are threaded through as explicit
/// parameters because those builders need them but this function has no
/// provider instance to read them from.
Map<String, Object?> panelValuesForDraft(
  String tableName,
  AuditModel draft, {
  required int? flockAgeWeeks,
  required DateTime? flockEntryDate,
}) {
  return switch (tableName) {
    'egg_storage' => eggStorageValues(draft),
    'egg_quality' => eggQualityValues(draft),
    'chick_quality' => chickQualityValues(draft),
    'chick_weights' => chickWeightValues(draft),
    'fresh_egg_breakout' => freshBreakoutValues(
      draft,
      flockAgeWeeks: flockAgeWeeks,
      flockEntryDate: flockEntryDate,
    ),
    'candled_egg_breakout' => candledBreakoutValues(
      draft,
      flockAgeWeeks: flockAgeWeeks,
      flockEntryDate: flockEntryDate,
    ),
    'residue_breakout' => residueBreakoutValues(
      draft,
      flockAgeWeeks: flockAgeWeeks,
      flockEntryDate: flockEntryDate,
    ),
    'setter_optimizing' => {
      'machineType': draft.soMachineType,
      'setpointF': draft.soSetpointF,
      'actualF': draft.soActualF,
      'setpointRh': draft.soSetpointRh,
      'actualRh': draft.soActualRh,
      'batchSize': draft.soBatchSize,
      'batchCount': draft.soBatchCount,
      'totalEggsSet': draft.soTotalEggsSet,
      'turningAngle': draft.soTurningAngle,
      'co2Ppm': draft.soCo2,
      'co2Photo': draft.soCo2Photo,
      'estBreed': draft.soBreed,
      'incubationAgeDays': draft.soIncubationAge,
      'incubationHours': draft.soIncubationHours,
      'estReadingsJson': draft.soEstReadings,
      'estPhotosJson': draft.soEstPhotos,
      'estSamplesJson': draft.soEstSamplesJson,
      'estSampleSize': _decodedReadingCount(draft.soEstReadings),
      'estAvg': draft.soEstAvg,
      'estCvPct': draft.soEstCv,
      'machineScreenPhoto': draft.soMachineScreenPhoto,
    },
    'hatcher_optimizing' => {
      'setpointF': draft.hoSetpointF,
      'setpointRh': draft.hoSetpointRh,
      'incubationAgeDays': draft.hoIncubationAge,
      'incubationHours': draft.hoIncubationHours,
      'co2Ppm': draft.hoCo2,
      'co2Photo': draft.hoCo2Photo,
      'cvtReadingsJson': draft.hoCvtReadings,
      'cvtPhotosJson': draft.hoCvtPhotos,
      'cvtSampleSize': _decodedReadingCount(draft.hoCvtReadings),
      'cvtAvg': draft.hoCvtAvg,
      'cvtCvPct': draft.hoCvtCv,
      'chickPanting': _boolToInt(draft.hoChickPanting),
      'chickPantingPhoto': draft.hoChickPantingPhoto,
      'meconium': draft.hoMeconium,
      'transferDay': draft.hoTransferDay,
    },
    _ => const <String, Object?>{},
  };
}

/// The storage-period days a draft reports, whatever station it came from.
///
/// Moved verbatim from the provider's `_storageDaysForDraft`. It lives here
/// rather than in `services/audit_panel_save_coordinator.dart` because it has
/// callers on both sides of that split (the coordinator's panel-record builder
/// and the provider's station-sample builder), and duplicating it would let
/// the two copies drift.
int? storageDaysForDraft(AuditModel draft) {
  final storageDays =
      draft.esEggStorageDays ??
      draft.chickStorageDays ??
      draft.haStorageDays ??
      draft.ebStorageDays;
  if (storageDays != null) return storageDays;
  return switch (draft.auditType) {
    'Egg' || 'Chicks' || 'Hatch Analysis & Egg Breakouts' => 0,
    _ => null,
  };
}

/// The legacy per-station benchmark age in weeks, if the draft carries one.
///
/// Moved verbatim from the provider's `_legacyBmkWeeksForDraft`; see
/// [storageDaysForDraft] for why it lives here rather than in the coordinator.
int? legacyBmkWeeksForDraft(AuditModel draft) {
  return draft.esEggBmkAge ??
      draft.chickBmkAge ??
      draft.haBmkAge ??
      draft.ebBmkAge;
}

Map<String, Object?> eggStorageValues(AuditModel draft) {
  final trays = decodedMaps(draft.esUvTrays);
  var trayEggCount = 0;
  var upsideDown = 0;
  for (final tray in trays) {
    trayEggCount += asInt(tray['totalEggs']) ?? 0;
    upsideDown += asInt(tray['upsideDown']) ?? 0;
  }
  return {
    'storagePeriodDays': draft.esEggStorageDays ?? 0,
    'estReadingsJson': draft.esEstReadingsJson,
    'estAvg': draft.esEstAvg,
    'estCvPct': draft.esEstCv,
    'turningTimes': draft.esTurningTimes,
    'traySpacing': draft.esTraySpacing,
    'coolerProximity': draft.esCoolerProximity,
    'condensationPresent': _boolToInt(draft.esCondensation),
    'upsideDownCount': upsideDown,
    'upsideDownPct': pct(upsideDown, trayEggCount),
  };
}

Map<String, Object?> eggQualityValues(AuditModel draft) {
  final trays = decodedMaps(draft.esUvTrays);
  var trayEggCount = 0;
  var cuticleDamage = 0;
  var washed = 0;
  var dirty = 0;
  for (final tray in trays) {
    trayEggCount += asInt(tray['totalEggs']) ?? 0;
    cuticleDamage += asInt(tray['cuticleDamage']) ?? 0;
    washed += asInt(tray['washed']) ?? 0;
    dirty += asInt(tray['dirty']) ?? 0;
  }
  final affected = cuticleDamage + washed + dirty;
  final uvDenominator = trayEggCount == 0 ? draft.esUvSampleSize : trayEggCount;
  return {
    'storagePeriodDays':
        draft.esEggQualityStorageDays ?? draft.esEggStorageDays ?? 0,
    'uvTrayEggCount': uvDenominator,
    'uvCuticleDamageCount': cuticleDamage,
    'uvCuticleDamagePct': pct(cuticleDamage, uvDenominator),
    'uvWashedCount': washed,
    'uvWashedPct': pct(washed, uvDenominator),
    'uvDirtyCount': dirty,
    'uvDirtyPct': pct(dirty, uvDenominator),
    'uvAffectedCount': affected,
    'uvAffectedPct': pct(affected, uvDenominator),
    'eggWeightsJson': draft.esEggWeights,
    'eggSampleSize': draft.esEggSampleSize,
    'eggAvgWeight': draft.esEggAvgWeight,
    'eggUniformityPct': draft.esEggUniformityPct,
    'eggCvPct': draft.esEggCvPct,
    'eggBmkAgeWeeks': draft.esEggBmkAge,
    'eggBmkWeight': draft.esEggBmkWeight,
    ..._eggGradingValues(draft),
  };
}

Map<String, Object?> _eggGradingValues(AuditModel draft) {
  final summary = EggGradingSummary.fromJson(
    draft.esGradingDefectsJson,
    sampleSize: draft.esGradingSampleSize ?? 0,
    rejectedCount: draft.esGradingRejectedCount ?? 0,
  );
  if (!summary.hasData) {
    return const {
      'gradingSampleSize': null,
      'gradingRejectedCount': null,
      'gradingAcceptableCount': null,
      'gradingRejectedPct': null,
      'gradingAcceptablePct': null,
      'gradingDefectsJson': null,
      'gradingTopDefectCode': null,
      'gradingTopDefectPct': null,
    };
  }
  return {
    'gradingSampleSize': summary.sampleSize,
    'gradingRejectedCount': summary.rejectedCount,
    'gradingAcceptableCount': summary.acceptableCount,
    'gradingRejectedPct': summary.rejectedPct,
    'gradingAcceptablePct': summary.acceptablePct,
    'gradingDefectsJson': summary.encodedJson,
    'gradingTopDefectCode': summary.topDefectCode,
    'gradingTopDefectPct': summary.topDefectPct,
  };
}

Map<String, Object?> chickQualityValues(AuditModel draft) {
  final size = draft.pasgarSampleSize;
  final culledChicksTotalEggSet =
      draft.culledChicksTotalEggSet ??
      (draft.culledChicksAnalysisJson == null
          ? null
          : kDefaultCulledChicksTotalEggSet);
  final culledChicksSummary = CulledChicksAnalysisSummary.fromJson(
    draft.culledChicksAnalysisJson,
    totalEggSet: culledChicksTotalEggSet,
  );
  final compatibilityValues = <String, Object?>{
    'pasgarSampleSize': size,
    'pasgarReflexesCount': draft.pasgarReflexes,
    'pasgarBeakCount': draft.pasgarBeak,
    'pasgarNavelCount': draft.pasgarNavel,
    'pasgarBellyCount': draft.pasgarBelly,
    'pasgarLegCount': draft.pasgarLeg,
    'pasgarFeatherDevCount': draft.pasgarFeatherDev,
    'pasgarReflexesPct': pct(draft.pasgarReflexes, size),
    'pasgarBeakPct': pct(draft.pasgarBeak, size),
    'pasgarNavelPct': pct(draft.pasgarNavel, size),
    'pasgarBellyPct': pct(draft.pasgarBelly, size),
    'pasgarLegPct': pct(draft.pasgarLeg, size),
    'pasgarFeatherDevPct': pct(draft.pasgarFeatherDev, size),
    'pasgarFinalScore': draft.pasgarFinalScore,
    'yfbmPhoto': draft.yfbmPhoto,
    'yfbmEntriesJson': draft.yfbmEntries,
    'yfbmEntryCount': decodedListLength(draft.yfbmEntries),
    'yfbmAvgPct': draft.yfbmAvgPct,
    'yfbmCvPct': draft.yfbmCvPct,
    'cvtReadingsJson': draft.cvtReadingsJson,
    'cvtPhotosJson': draft.cvtPhotosJson,
    'cvtSampleSize': draft.cvtSampleSize,
    'cvtTopBasket': draft.cvtTopBasket,
    'cvtTopTemp': draft.cvtTopTemp,
    'cvtTopPhoto': draft.cvtTopPhoto,
    'cvtMiddleBasket': draft.cvtMiddleBasket,
    'cvtMiddleTemp': draft.cvtMiddleTemp,
    'cvtMiddlePhoto': draft.cvtMiddlePhoto,
    'cvtBottomBasket': draft.cvtBottomBasket,
    'cvtBottomTemp': draft.cvtBottomTemp,
    'cvtBottomPhoto': draft.cvtBottomPhoto,
    'cvtAvgTemp': draft.cvtAvg,
    'cvtCvPct': draft.cvtCvPct,
    ...chickPmValues(draft),
    'culledChicksTotalEggSet': culledChicksTotalEggSet,
    'culledChicksAnalysisJson': culledChicksSummary.encodedJson,
    'culledChicksAffectedPct': culledChicksSummary.affectedPct,
    'culledChicksTopCategory': culledChicksSummary.topCategory,
    'culledChicksTopSubtype': culledChicksSummary.topSubtype,
  };
  return _registryBackedChickValues(
    compatibilityValues,
    registeredFieldValues: {
      'pasgarSampleSize': size,
      'pasgarReflexesCount': draft.pasgarReflexes,
      'pasgarBeakCount': draft.pasgarBeak,
      'pasgarNavelCount': draft.pasgarNavel,
      'pasgarBellyCount': draft.pasgarBelly,
      'pasgarLegCount': draft.pasgarLeg,
      'pasgarFeatherDevCount': draft.pasgarFeatherDev,
      'pasgarReflexesPct': pct(draft.pasgarReflexes, size),
      'pasgarBeakPct': pct(draft.pasgarBeak, size),
      'pasgarNavelPct': pct(draft.pasgarNavel, size),
      'pasgarBellyPct': pct(draft.pasgarBelly, size),
      'pasgarLegPct': pct(draft.pasgarLeg, size),
      'pasgarFeatherDevPct': pct(draft.pasgarFeatherDev, size),
      'pasgarFinalScore': draft.pasgarFinalScore,
      'yfbmEntriesJson': draft.yfbmEntries,
      'yfbmEntryCount': decodedListLength(draft.yfbmEntries),
      'yfbmAvgPct': draft.yfbmAvgPct,
      'yfbmCvPct': draft.yfbmCvPct,
      'cvtReadingsJson': draft.cvtReadingsJson,
      'cvtSampleSize': draft.cvtSampleSize,
      'cvtAvgTemp': draft.cvtAvg,
      'cvtCvPct': draft.cvtCvPct,
      'pmSampleSize': draft.pmSampleSize,
      'pmCollectionPoint': draft.pmCollectionPoint,
      'pmOmphalitisCount': draft.pmOmphalitisCount,
      'pmOmphalitisSeverity': draft.pmOmphalitisSeverity,
      'pmGaseousCecaCount': draft.pmGaseousCecaCount,
      'pmGaseousCecaSeverity': draft.pmGaseousCecaSeverity,
      'pmGizzardErosionsCount': draft.pmGizzardErosionsCount,
      'pmGizzardErosionsSeverity': draft.pmGizzardErosionsSeverity,
      'pmAirSacCaseationsCount': draft.pmAirSacCaseationsCount,
      'pmAirSacCaseationsSeverity': draft.pmAirSacCaseationsSeverity,
      'pmUrolithiasisCount': draft.pmUrolithiasisCount,
      'pmUrolithiasisSeverity': draft.pmUrolithiasisSeverity,
      'pmNephritisCount': draft.pmNephritisCount,
      'pmNephritisSeverity': draft.pmNephritisSeverity,
      'pmGeneralSepticemiaCount': draft.pmGeneralSepticemiaCount,
      'pmGeneralSepticemiaSeverity': draft.pmGeneralSepticemiaSeverity,
      'culledChicksTotalEggSet': culledChicksTotalEggSet,
      'culledChicksAnalysisJson': culledChicksSummary.encodedJson,
      'culledChicksAffectedPct': culledChicksSummary.affectedPct,
      'culledChicksTopCategory': culledChicksSummary.topCategory,
      'culledChicksTopSubtype': culledChicksSummary.topSubtype,
    },
    includeWeights: false,
  );
}

Map<String, Object?> chickWeightValues(AuditModel draft) {
  return _registryBackedChickValues(
    {'bmkAgeWeeks': draft.chickBmkAge, 'bmkWeight': draft.chickBmkWeight},
    registeredFieldValues: {
      'weightsJson': draft.chickWeights,
      'sampleSize': draft.chickSampleSize,
      'avgWeight': draft.chickAvgWeight,
      'uniformityPct': draft.chickUniformityPct,
      'cvPct': draft.chickCvPct,
    },
    includeWeights: true,
  );
}

Map<String, Object?> _registryBackedChickValues(
  Map<String, Object?> compatibilityValues, {
  required Map<String, Object?> registeredFieldValues,
  required bool includeWeights,
}) {
  final schemas = AgentStationRegistry.schemas.where(
    (schema) =>
        schema.schemaKey.startsWith('chicks.') &&
        (schema.schemaKey == 'chicks.weights') == includeWeights,
  );
  final registeredColumns = <String>{};
  final generatedValues = <String, Object?>{};
  for (final schema in schemas) {
    for (final field in schema.fields) {
      final localColumn = field.persistence['localColumn']?.toString();
      if (localColumn == null) continue;
      registeredColumns.add(localColumn);
    }
    for (final calculation in schema.calculations) {
      final localColumn = calculation.persistence['localColumn']?.toString();
      if (localColumn != null) registeredColumns.add(localColumn);
    }
    generatedValues.addAll(
      AgentStationAdapter.localPersistenceValuesUnchecked(
        schema,
        registeredFieldValues,
        recomputeCalculations: false,
      ),
    );
  }
  return {
    for (final entry in compatibilityValues.entries)
      if (!registeredColumns.contains(entry.key)) entry.key: entry.value,
    ...generatedValues,
  };
}

Map<String, Object?> chickWeightValuesForSample(
  StationSampleModel sample, {
  required AuditModel fallback,
}) {
  final summary = decodedMap(sample.resultSummaryJson);
  if (summary == null) {
    if (sample.sampleMode == StationSampleModel.sampleModeComparison) {
      return emptyChickWeightValues(fallback);
    }
    return chickWeightValues(fallback);
  }

  final weights = summary['chickWeights'];
  return {
    'weightsJson': weights is List ? jsonEncode(weights) : null,
    'sampleSize': weights is List ? weightSampleSizeFromDecoded(weights) : null,
    'avgWeight': asDouble(summary['chickAvgWeight']),
    'uniformityPct': asDouble(summary['chickUniformityPct']),
    'cvPct': asDouble(summary['chickCvPct']),
    'bmkAgeWeeks': fallback.chickBmkAge,
    'bmkWeight': fallback.chickBmkWeight,
  };
}

Map<String, Object?> emptyChickWeightValues(AuditModel fallback) {
  return {
    'weightsJson': null,
    'sampleSize': null,
    'avgWeight': null,
    'uniformityPct': null,
    'cvPct': null,
    'bmkAgeWeeks': fallback.chickBmkAge,
    'bmkWeight': fallback.chickBmkWeight,
  };
}

Map<String, Object?> chickPmValues(AuditModel draft) {
  return {
    'pmSampleSize': draft.pmSampleSize,
    'pmCollectionPoint': draft.pmCollectionPoint,
    'pmOmphalitisCount': draft.pmOmphalitisCount,
    'pmOmphalitisSeverity': draft.pmOmphalitisSeverity,
    'pmGaseousCecaCount': draft.pmGaseousCecaCount,
    'pmGaseousCecaSeverity': draft.pmGaseousCecaSeverity,
    'pmGizzardErosionsCount': draft.pmGizzardErosionsCount,
    'pmGizzardErosionsSeverity': draft.pmGizzardErosionsSeverity,
    'pmAirSacCaseationsCount': draft.pmAirSacCaseationsCount,
    'pmAirSacCaseationsSeverity': draft.pmAirSacCaseationsSeverity,
    'pmUrolithiasisCount': draft.pmUrolithiasisCount,
    'pmUrolithiasisSeverity': draft.pmUrolithiasisSeverity,
    'pmNephritisCount': draft.pmNephritisCount,
    'pmNephritisSeverity': draft.pmNephritisSeverity,
    'pmGeneralSepticemiaCount': draft.pmGeneralSepticemiaCount,
    'pmGeneralSepticemiaSeverity': draft.pmGeneralSepticemiaSeverity,
    'pmOtherLesionsJson': draft.pmOtherLesionsJson,
    'pmSuspectedCauseAuto': draft.pmSuspectedCauseAuto,
    'pmSuspectedCauseManual': draft.pmSuspectedCauseManual,
    'pmPhotosJson': draft.pmPhotosJson,
  };
}

/// Moved verbatim from the provider's `_decodedReadingCount`. Not itself
/// named in this extraction's move list, but it was only ever called from
/// the `setter_optimizing`/`hatcher_optimizing` branches of
/// [panelValuesForDraft], so it has no remaining callers left in the
/// provider and is moved here (not duplicated) to avoid leaving dead code
/// behind.
int? _decodedReadingCount(String? source) {
  if (source == null || source.trim().isEmpty) return null;
  return TemperatureReadingsPayload.decode(
    source,
    legacyUnit: TemperatureEntryUnit.fahrenheit,
  ).count;
}

/// Moved verbatim from the provider's `_boolToInt`; see
/// [_decodedReadingCount] above for why it is moved rather than duplicated
/// (its only callers were `esCondensation` in [eggStorageValues] and
/// `hoChickPanting` in [panelValuesForDraft], both moved here).
int? _boolToInt(bool? value) {
  if (value == null) return null;
  return value ? 1 : 0;
}
