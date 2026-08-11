import 'dart:convert';

import '../../../data/models/audit_model.dart';
import '../models/egg_breakout_sample.dart';
import 'audit_value_parsing.dart';

/// Whether a blank draft of this type should still be treated as
/// "saved but incomplete" rather than empty/discarded.
bool treatBlankDraftAsSavedIncomplete(AuditModel draft) {
  return draft.auditType == 'Hatchers';
}

bool isMeaningfulPooledEggStorageValue(String key, Object? value) {
  if (value == null) return false;
  if (key == 'esEggStorageDays' && value is num) return value != 0;
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isNotEmpty && trimmed != '[]' && trimmed != '{}';
  }
  return true;
}

bool hasMeaningfulEggStorageData(AuditModel draft) {
  return isMeaningfulPooledEggStorageValue(
        'esEggStorageDays',
        draft.esEggStorageDays,
      ) ||
      hasSavableEggStorageData(draft) ||
      draft.esTurningTimes != null ||
      hasText(draft.esTraySpacing) ||
      hasText(draft.esCoolerProximity) ||
      draft.esCondensation != null ||
      hasMeaningfulEggStorageTrayData(draft.esUvTrays) ||
      hasText(draft.notes);
}

bool hasSavableEggStorageData(AuditModel draft) {
  return hasMeaningfulJsonObject(draft.esEstReadingsJson) ||
      hasMeaningfulJsonObject(draft.esEstPhotosJson) ||
      draft.esEstAvg != null ||
      draft.esEstCv != null;
}

/// `hasAnyMeaningfulChickWeightSample` mirrors the provider's original
/// `_chickWeightSamples.any((sample) => _hasMeaningfulChickWeightSample(draft, sample))`
/// check, computed by the caller since the chick-weight sample list is
/// provider state.
///
/// `contextSetterId`/`contextHatcherId` mirror the provider's original
/// `_context?.setterId`/`_context?.hatcherId` reads, also provider state.
bool hasAnyMeaningfulStationData(
  AuditModel draft, {
  required bool hasAnyMeaningfulChickWeightSample,
  required String? contextSetterId,
  required String? contextHatcherId,
}) {
  return switch (draft.auditType) {
    'Egg' =>
      hasMeaningfulEggStorageData(draft) ||
          hasMeaningfulEggQualityData(draft) ||
          hasMeaningfulEggQualityMetadata(draft),
    'Chicks' => hasMeaningfulChickData(
      draft,
      hasAnyMeaningfulChickWeightSample: hasAnyMeaningfulChickWeightSample,
    ),
    'Hatch Analysis & Egg Breakouts' => hasMeaningfulHatchData(draft),
    'Setters' => hasMeaningfulSetterData(
      draft,
      contextSetterId: contextSetterId,
    ),
    'Hatchers' => hasMeaningfulHatcherData(
      draft,
      contextHatcherId: contextHatcherId,
    ),
    _ => false,
  };
}

bool hasCoreStationData(
  AuditModel draft, {
  required bool hasAnyMeaningfulChickWeightSample,
  required String? contextSetterId,
  required String? contextHatcherId,
}) {
  return switch (draft.auditType) {
    'Egg' =>
      hasMeaningfulEggStorageCoreData(draft) ||
          hasMeaningfulEggQualityCoreData(draft),
    'Chicks' => hasMeaningfulChickCoreData(
      draft,
      hasAnyMeaningfulChickWeightSample: hasAnyMeaningfulChickWeightSample,
    ),
    'Hatch Analysis & Egg Breakouts' => hasMeaningfulHatchCompletionCoreData(
      draft,
    ),
    'Setters' => hasMeaningfulSetterCoreData(
      draft,
      contextSetterId: contextSetterId,
    ),
    'Hatchers' => hasMeaningfulHatcherCoreData(
      draft,
      contextHatcherId: contextHatcherId,
    ),
    _ => false,
  };
}

bool hasMeaningfulChickCoreData(
  AuditModel draft, {
  required bool hasAnyMeaningfulChickWeightSample,
}) {
  return hasMeaningfulPasgarData(draft) ||
      hasMeaningfulChickWeightData(
        draft,
        hasAnyMeaningfulChickWeightSample: hasAnyMeaningfulChickWeightSample,
      );
}

bool hasMeaningfulEggStorageCoreData(AuditModel draft) {
  return hasSavableEggStorageData(draft);
}

bool hasMeaningfulEggQualityCoreData(AuditModel draft) {
  return hasMeaningfulEggQualityData(draft);
}

bool hasMeaningfulChickData(
  AuditModel draft, {
  required bool hasAnyMeaningfulChickWeightSample,
}) {
  return hasMeaningfulChickCoreData(
        draft,
        hasAnyMeaningfulChickWeightSample: hasAnyMeaningfulChickWeightSample,
      ) ||
      hasText(draft.yfbmPhoto) ||
      hasMeaningfulJsonData(draft.yfbmEntries) ||
      draft.yfbmAvgPct != null ||
      draft.yfbmCvPct != null ||
      (draft.cvtSampleSize ?? 0) > 0 ||
      hasText(draft.cvtTopBasket) ||
      draft.cvtTopTemp != null ||
      hasText(draft.cvtTopPhoto) ||
      hasText(draft.cvtMiddleBasket) ||
      draft.cvtMiddleTemp != null ||
      hasText(draft.cvtMiddlePhoto) ||
      hasText(draft.cvtBottomBasket) ||
      draft.cvtBottomTemp != null ||
      hasText(draft.cvtBottomPhoto) ||
      draft.cvtAvg != null ||
      draft.cvtCvPct != null ||
      hasMeaningfulJsonObject(draft.cvtReadingsJson) ||
      hasMeaningfulJsonObject(draft.cvtPhotosJson) ||
      hasMeaningfulPmData(draft) ||
      (draft.culledChicksTotalEggSet ?? 0) > 0 ||
      hasMeaningfulJsonData(draft.culledChicksAnalysisJson) ||
      draft.culledChicksAffectedPct != null ||
      hasText(draft.culledChicksTopCategory) ||
      hasText(draft.culledChicksTopSubtype) ||
      hasText(draft.notes);
}

bool hasChickQualityScopeResults(AuditModel draft) {
  return hasMeaningfulPasgarData(draft) ||
      hasText(draft.yfbmPhoto) ||
      hasMeaningfulJsonData(draft.yfbmEntries) ||
      draft.yfbmAvgPct != null ||
      draft.yfbmCvPct != null ||
      draft.cvtSampleSize != null ||
      hasText(draft.cvtTopBasket) ||
      draft.cvtTopTemp != null ||
      hasText(draft.cvtTopPhoto) ||
      hasText(draft.cvtMiddleBasket) ||
      draft.cvtMiddleTemp != null ||
      hasText(draft.cvtMiddlePhoto) ||
      hasText(draft.cvtBottomBasket) ||
      draft.cvtBottomTemp != null ||
      hasText(draft.cvtBottomPhoto) ||
      draft.cvtAvg != null ||
      draft.cvtCvPct != null ||
      hasMeaningfulJsonObject(draft.cvtReadingsJson) ||
      hasMeaningfulJsonObject(draft.cvtPhotosJson) ||
      hasMeaningfulPmData(draft) ||
      draft.culledChicksTotalEggSet != null ||
      hasMeaningfulJsonData(draft.culledChicksAnalysisJson) ||
      draft.culledChicksAffectedPct != null ||
      hasText(draft.culledChicksTopCategory) ||
      hasText(draft.culledChicksTopSubtype) ||
      hasText(draft.notes);
}

bool hasMeaningfulPasgarData(AuditModel draft) {
  return (draft.pasgarSampleSize ?? 0) > 0 ||
      (draft.pasgarReflexes ?? 0) > 0 ||
      hasText(draft.pasgarReflexesPhoto) ||
      (draft.pasgarBeak ?? 0) > 0 ||
      hasText(draft.pasgarBeakPhoto) ||
      (draft.pasgarNavel ?? 0) > 0 ||
      hasText(draft.pasgarNavelPhoto) ||
      (draft.pasgarBelly ?? 0) > 0 ||
      hasText(draft.pasgarBellyPhoto) ||
      (draft.pasgarLeg ?? 0) > 0 ||
      hasText(draft.pasgarLegPhoto) ||
      (draft.pasgarFeatherDev ?? 0) > 0 ||
      hasText(draft.pasgarFeatherDevPhoto) ||
      draft.pasgarFinalScore != null;
}

/// `hasAnyMeaningfulChickWeightSample` replaces the original
/// `_chickWeightSamples.any((sample) => _hasMeaningfulChickWeightSample(draft, sample))`
/// call — `_chickWeightSamples` is provider state, so the caller computes
/// this boolean (per-draft, since each sample is evaluated with `draft` as
/// its fallback) and passes it in.
bool hasMeaningfulChickWeightData(
  AuditModel draft, {
  required bool hasAnyMeaningfulChickWeightSample,
}) {
  return hasMeaningfulWeightList(draft.chickWeights) ||
      (draft.chickSampleSize ?? 0) > 0 ||
      draft.chickAvgWeight != null ||
      draft.chickUniformityPct != null ||
      draft.chickCvPct != null ||
      hasAnyMeaningfulChickWeightSample;
}

bool hasMeaningfulPmData(AuditModel draft) {
  return (draft.pmSampleSize ?? 0) > 0 ||
      hasText(draft.pmCollectionPoint) ||
      (draft.pmOmphalitisCount ?? 0) > 0 ||
      hasText(draft.pmOmphalitisSeverity) ||
      (draft.pmGaseousCecaCount ?? 0) > 0 ||
      hasText(draft.pmGaseousCecaSeverity) ||
      (draft.pmGizzardErosionsCount ?? 0) > 0 ||
      hasText(draft.pmGizzardErosionsSeverity) ||
      (draft.pmAirSacCaseationsCount ?? 0) > 0 ||
      hasText(draft.pmAirSacCaseationsSeverity) ||
      (draft.pmUrolithiasisCount ?? 0) > 0 ||
      hasText(draft.pmUrolithiasisSeverity) ||
      (draft.pmNephritisCount ?? 0) > 0 ||
      hasText(draft.pmNephritisSeverity) ||
      (draft.pmGeneralSepticemiaCount ?? 0) > 0 ||
      hasText(draft.pmGeneralSepticemiaSeverity) ||
      hasMeaningfulJsonObject(draft.pmOtherLesionsJson) ||
      hasText(draft.pmSuspectedCauseAuto) ||
      hasText(draft.pmSuspectedCauseManual) ||
      hasMeaningfulJsonData(draft.pmPhotosJson);
}

bool hasMeaningfulHatchData(AuditModel draft) {
  return hasMeaningfulHatchCoreData(draft) || hasText(draft.notes);
}

bool hasHatchScopeResults(AuditModel draft) {
  final breakoutSamples = EggBreakoutSampleEntry.decodeList(
    draft.ebTrayBreakoutJson,
    fallbackBreakoutType: EggBreakoutType.fromStorageValue(
      draft.ebBreakoutType,
    ),
  );
  return ((draft.haTotalEggsSet ?? 19200) != 19200) ||
      draft.haHatched != null ||
      draft.haCulled != null ||
      draft.haDead != null ||
      draft.haHatchability != null ||
      draft.haFertility != null ||
      draft.haHof != null ||
      hasMeaningfulJsonData(draft.haTrays) ||
      draft.haPipped != null ||
      draft.haInfertileClear != null ||
      draft.haEarlyDead != null ||
      draft.haMidDead != null ||
      draft.haMidLateDead != null ||
      draft.haLateDead != null ||
      draft.haContaminatedExploders != null ||
      hasMeaningfulJsonData(draft.haBenchmarkStatusesJson) ||
      breakoutSamples.any((sample) => sample.hasEnteredResults) ||
      draft.ebInfertileCount != null ||
      draft.ebEarlyDeadCount != null ||
      draft.ebMidDeadCount != null ||
      draft.ebLateDeadCount != null ||
      draft.ebInternalPipCount != null ||
      draft.ebExternalPipCount != null ||
      draft.ebCrackedCount != null ||
      draft.ebContaminatedCount != null ||
      draft.ebMalpositionCount != null ||
      draft.ebExposedBrainCount != null ||
      draft.ebCrossedBeakCount != null ||
      draft.ebCulledDeadCount != null ||
      hasText(draft.notes);
}

bool hasMeaningfulHatchCompletionCoreData(AuditModel draft) {
  return (draft.haHatched ?? 0) > 0 ||
      (draft.haCulled ?? 0) > 0 ||
      (draft.haDead ?? 0) > 0 ||
      draft.haHatchability != null ||
      draft.haFertility != null ||
      draft.haHof != null ||
      hasMeaningfulJsonData(draft.haTrays) ||
      (draft.haPipped ?? 0) > 0 ||
      (draft.haInfertileClear ?? 0) > 0 ||
      (draft.haEarlyDead ?? 0) > 0 ||
      (draft.haMidDead ?? 0) > 0 ||
      (draft.haMidLateDead ?? 0) > 0 ||
      (draft.haLateDead ?? 0) > 0 ||
      (draft.haContaminatedExploders ?? 0) > 0 ||
      hasMeaningfulJsonData(draft.haBenchmarkStatusesJson) ||
      hasMeaningfulBreakoutSamples(draft);
}

bool hasMeaningfulHatchCoreData(AuditModel draft) {
  return (draft.haTotalEggsSet ?? 0) > 0 ||
      hasMeaningfulHatchCompletionCoreData(draft);
}

bool hasMeaningfulBreakoutSamples(AuditModel draft) {
  if (hasMeaningfulJsonData(draft.ebTrayBreakoutJson)) return true;
  return (draft.ebTraySize ?? 0) > 0 ||
      (draft.ebInfertileCount ?? 0) > 0 ||
      (draft.ebEarlyDeadCount ?? 0) > 0 ||
      (draft.ebMidDeadCount ?? 0) > 0 ||
      (draft.ebLateDeadCount ?? 0) > 0 ||
      (draft.ebInternalPipCount ?? 0) > 0 ||
      (draft.ebExternalPipCount ?? 0) > 0 ||
      (draft.ebCrackedCount ?? 0) > 0 ||
      (draft.ebContaminatedCount ?? 0) > 0 ||
      (draft.ebMalpositionCount ?? 0) > 0 ||
      (draft.ebExposedBrainCount ?? 0) > 0 ||
      (draft.ebCrossedBeakCount ?? 0) > 0 ||
      (draft.ebCulledDeadCount ?? 0) > 0;
}

/// `contextSetterId` mirrors the provider's original `_context?.setterId`
/// read, which is provider state; the caller passes it explicitly.
bool hasMeaningfulSetterData(
  AuditModel draft, {
  required String? contextSetterId,
}) {
  return hasMeaningfulSetterCoreData(
        draft,
        contextSetterId: contextSetterId,
      ) ||
      draft.soActualF != null ||
      draft.soActualRh != null ||
      hasText(draft.soBreed) ||
      hasText(draft.soMachineScreenPhoto) ||
      hasText(draft.notes);
}

bool hasSetterScopeResults(AuditModel draft) {
  return draft.soCo2 != null ||
      hasText(draft.soCo2Photo) ||
      hasMeaningfulJsonObject(draft.soEstReadings) ||
      hasMeaningfulJsonObject(draft.soEstPhotos) ||
      draft.soEstAvg != null ||
      draft.soEstCv != null ||
      draft.soTurningAngle != null ||
      draft.soSetpointF != null ||
      draft.soActualF != null ||
      draft.soSetpointRh != null ||
      draft.soActualRh != null ||
      hasText(draft.soMachineScreenPhoto) ||
      ((draft.soBatchSize ?? 19200) != 19200) ||
      ((draft.soBatchCount ?? 1) != 1) ||
      ((draft.soTotalEggsSet ?? 19200) != 19200) ||
      hasSetterEstSampleResults(draft) ||
      hasText(draft.notes);
}

bool hasSetterEstSampleResults(AuditModel draft) {
  return decodedMaps(draft.soEstSamplesJson).any(
    (sample) =>
        isMeaningfulJsonValue(sample['estReadings']) ||
        isMeaningfulJsonValue(sample['estPhotos']) ||
        sample['estAvg'] != null ||
        sample['estCv'] != null,
  );
}

/// `contextSetterId` mirrors the provider's original `_context?.setterId`
/// read, which is provider state; the caller passes it explicitly.
bool hasMeaningfulSetterCoreData(
  AuditModel draft, {
  required String? contextSetterId,
}) {
  return hasMeaningfulMachineId(
        draft.soSetterId,
        defaultValue: 'S',
        contextValue: contextSetterId,
      ) ||
      draft.soCo2 != null ||
      hasText(draft.soCo2Photo) ||
      hasMeaningfulJsonObject(draft.soEstReadings) ||
      hasMeaningfulJsonObject(draft.soEstPhotos) ||
      draft.soEstAvg != null ||
      draft.soEstCv != null ||
      ((draft.soIncubationAge ?? 1) != 1) ||
      ((draft.soIncubationHours ?? 0) != 0) ||
      draft.soTurningAngle != null ||
      draft.soSetpointF != null ||
      draft.soSetpointRh != null ||
      hasMeaningfulSetterEstSamples(draft);
}

bool hasMeaningfulSetterEstSamples(AuditModel draft) {
  for (final sample in decodedMaps(draft.soEstSamplesJson)) {
    if (hasText(sample['breed'] as String?) && sample['breed'] != 'Ross308') {
      return true;
    }
    if ((asInt(sample['incubationAge']) ?? 1) != 1) return true;
    if ((asInt(sample['incubationHours']) ?? 0) != 0) return true;
    if (isMeaningfulJsonValue(sample['estReadings'])) return true;
    if (isMeaningfulJsonValue(sample['estPhotos'])) return true;
    if (sample['estAvg'] != null || sample['estCv'] != null) return true;
  }
  return false;
}

/// `contextHatcherId` mirrors the provider's original `_context?.hatcherId`
/// read, which is provider state; the caller passes it explicitly.
bool hasMeaningfulHatcherData(
  AuditModel draft, {
  required String? contextHatcherId,
}) {
  return hasMeaningfulHatcherCoreData(
        draft,
        contextHatcherId: contextHatcherId,
      ) ||
      hasText(draft.hoBreed) ||
      draft.hoTransferDay != null ||
      hasText(draft.notes);
}

bool hasHatcherScopeResults(AuditModel draft) {
  return ((draft.hoIncubationAge ?? 18) != 18) ||
      ((draft.hoIncubationHours ?? 0) != 0) ||
      draft.hoSetpointF != null ||
      draft.hoSetpointRh != null ||
      draft.hoCo2 != null ||
      hasText(draft.hoCo2Photo) ||
      hasMeaningfulJsonObject(draft.hoCvtReadings) ||
      hasMeaningfulJsonObject(draft.hoCvtPhotos) ||
      draft.hoCvtAvg != null ||
      draft.hoCvtCv != null ||
      draft.hoChickPanting != null ||
      hasText(draft.hoChickPantingPhoto) ||
      hasText(draft.hoMeconium) ||
      draft.hoTransferDay != null ||
      hasText(draft.notes);
}

/// `contextHatcherId` mirrors the provider's original `_context?.hatcherId`
/// read, which is provider state; the caller passes it explicitly.
bool hasMeaningfulHatcherCoreData(
  AuditModel draft, {
  required String? contextHatcherId,
}) {
  return hasMeaningfulMachineId(
        draft.hoHatcherId,
        defaultValue: 'H',
        contextValue: contextHatcherId,
      ) ||
      ((draft.hoIncubationAge ?? 18) != 18) ||
      ((draft.hoIncubationHours ?? 0) != 0) ||
      draft.hoSetpointF != null ||
      draft.hoSetpointRh != null ||
      draft.hoCo2 != null ||
      hasText(draft.hoCo2Photo) ||
      hasMeaningfulJsonObject(draft.hoCvtReadings) ||
      hasMeaningfulJsonObject(draft.hoCvtPhotos) ||
      draft.hoCvtAvg != null ||
      draft.hoCvtCv != null ||
      draft.hoChickPanting != null ||
      hasText(draft.hoChickPantingPhoto) ||
      hasText(draft.hoMeconium);
}

bool hasMeaningfulMachineId(
  String? value, {
  required String defaultValue,
  String? contextValue,
}) {
  final id = blankToNull(value);
  final contextId = blankToNull(contextValue);
  return id != null && id != defaultValue && id != contextId;
}

bool hasMeaningfulJsonObject(String? source) {
  final decoded = decodedMap(source);
  if (decoded == null || decoded.isEmpty) return false;
  return decoded.values.any(isMeaningfulJsonValue);
}

bool hasMeaningfulJsonData(String? source) {
  if (source == null || source.trim().isEmpty) return false;
  try {
    return isMeaningfulJsonValue(jsonDecode(source));
  } catch (_) {
    return false;
  }
}

bool hasMeaningfulEggStorageTrayData(String? source) {
  return decodedMaps(source).any((tray) {
    return (asInt(tray['totalEggs']) ?? 0) > 0 ||
        (asInt(tray['upsideDown']) ?? 0) > 0 ||
        isMeaningfulJsonValue(tray['photoPath']);
  });
}

bool hasMeaningfulEggQualityData(AuditModel draft) {
  return hasMeaningfulEggQualityTrayData(draft.esUvTrays) ||
      hasMeaningfulWeightList(draft.esEggWeights) ||
      (draft.esEggSampleSize ?? 0) > 0 ||
      draft.esEggAvgWeight != null ||
      draft.esEggUniformityPct != null ||
      draft.esEggCvPct != null;
}

bool hasMeaningfulEggQualityMetadata(AuditModel draft) {
  return isMeaningfulPooledEggStorageValue(
        'esEggQualityStorageDays',
        draft.esEggQualityStorageDays,
      ) ||
      draft.esEggBmkAge != null ||
      draft.esEggBmkWeight != null ||
      hasText(draft.notes);
}

bool hasMeaningfulEggQualityTrayData(String? source) {
  return decodedMaps(source).any((tray) {
    return tray['qualityTouched'] == true ||
        (asInt(tray['cuticleDamage']) ?? 0) > 0 ||
        (asInt(tray['washed']) ?? 0) > 0 ||
        (asInt(tray['dirty']) ?? 0) > 0 ||
        isMeaningfulJsonValue(tray['photoPath']);
  });
}

/// The provider's original `_hasMeaningfulWeightList` decoded `source` via
/// two provider-private helpers (`_decodedWeights` +
/// `_weightSampleSizeFromDecoded`) that are not part of this extraction; the
/// equivalent decode-and-count logic now goes through the shared
/// [weightSampleSizeFromDecoded] helper (a null sample size corresponds
/// exactly to a zero count of positive weights).
bool hasMeaningfulWeightList(String? source) {
  if (source == null || source.trim().isEmpty) return false;
  Object? decoded;
  try {
    decoded = jsonDecode(source);
  } catch (_) {
    decoded = null;
  }
  return weightSampleSizeFromDecoded(decoded) != null;
}

/// Takes the already-resolved chick-weight `values` map (as produced by the
/// provider's `_chickWeightValuesForSample`) rather than `(draft, sample)`,
/// since computing that map requires provider-resident helpers outside this
/// extraction's scope.
bool hasMeaningfulChickWeightSample(Map<String, Object?> values) {
  return hasMeaningfulWeightList(values['weightsJson'] as String?) ||
      (asInt(values['sampleSize']) ?? 0) > 0 ||
      values['avgWeight'] != null ||
      values['uniformityPct'] != null ||
      values['cvPct'] != null;
}

bool isMeaningfulJsonValue(Object? value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is Iterable) return value.any(isMeaningfulJsonValue);
  if (value is Map) return value.values.any(isMeaningfulJsonValue);
  return true;
}
