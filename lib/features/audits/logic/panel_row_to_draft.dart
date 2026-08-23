import 'dart:convert';

import '../models/egg_breakout_sample.dart';

/// Panel row -> audit-draft map merging, the read half of panel persistence.
///
/// Moved verbatim out of `_AuditSessionScreenState` so the mapping can be
/// tested directly against its write-side counterpart in
/// `panel_value_builders.dart`. The two are hand-written inverses of each
/// other and nothing could exercise them together while this half was locked
/// inside a private State class. Bodies, key names and statement order are
/// unchanged — only the enclosing scope moved.

void mergePanelRowIntoAuditMap(
  Map<String, dynamic> map,
  String table,
  Map<String, dynamic> row,
) {
  void copy(String target, String source) {
    final value = row[source];
    if (value != null) map[target] = value;
  }

  switch (table) {
    case 'egg_storage':
      copy('esEggStorageDays', 'storagePeriodDays');
      copy('es_estReadingsJson', 'estReadingsJson');
      copy('es_estAvg', 'estAvg');
      copy('es_estCv', 'estCvPct');
      copy('esTurningTimes', 'turningTimes');
      copy('es_traySpacing', 'traySpacing');
      copy('es_coolerProximity', 'coolerProximity');
      copy('es_condensation', 'condensationPresent');
      _mergeEggTraySummary(map, {'upsideDown': row['upsideDownCount']});
      break;
    case 'egg_quality':
      copy('esEggQualityStorageDays', 'storagePeriodDays');
      copy('es_uvSampleSize', 'uvTrayEggCount');
      copy('es_uvCuticleDamageCount', 'uvCuticleDamageCount');
      copy('es_uvWashingEvidenceCount', 'uvWashedCount');
      copy('es_uvFecalCount', 'uvDirtyCount');
      _mergeEggTraySummary(map, {
        'totalEggs': row['uvTrayEggCount'],
        'cuticleDamage': row['uvCuticleDamageCount'],
        'washed': row['uvWashedCount'],
        'dirty': row['uvDirtyCount'],
        'qualityTouched': true,
      });
      copy('esEggWeights', 'eggWeightsJson');
      copy('esEggSampleSize', 'eggSampleSize');
      copy('esEggAvgWeight', 'eggAvgWeight');
      copy('esEggUniformityPct', 'eggUniformityPct');
      copy('esEggCvPct', 'eggCvPct');
      copy('esEggBmkAge', 'eggBmkAgeWeeks');
      copy('esEggBmkWeight', 'eggBmkWeight');
      break;
    case 'chick_quality':
      copy('pasgarSampleSize', 'pasgarSampleSize');
      copy('pasgarReflexes', 'pasgarReflexesCount');
      copy('pasgarBeak', 'pasgarBeakCount');
      copy('pasgarNavel', 'pasgarNavelCount');
      copy('pasgarBelly', 'pasgarBellyCount');
      copy('pasgarLeg', 'pasgarLegCount');
      copy('pasgarFeatherDev', 'pasgarFeatherDevCount');
      copy('pasgarFinalScore', 'pasgarFinalScore');
      copy('yfbmPhoto', 'yfbmPhoto');
      copy('yfbmEntries', 'yfbmEntriesJson');
      copy('yfbmAvgPct', 'yfbmAvgPct');
      copy('yfbmCvPct', 'yfbmCvPct');
      copy('cvtReadingsJson', 'cvtReadingsJson');
      copy('cvtPhotosJson', 'cvtPhotosJson');
      copy('cvtSampleSize', 'cvtSampleSize');
      copy('cvtTopBasket', 'cvtTopBasket');
      copy('cvtTopTemp', 'cvtTopTemp');
      copy('cvtTopPhoto', 'cvtTopPhoto');
      copy('cvtMiddleBasket', 'cvtMiddleBasket');
      copy('cvtMiddleTemp', 'cvtMiddleTemp');
      copy('cvtMiddlePhoto', 'cvtMiddlePhoto');
      copy('cvtBottomBasket', 'cvtBottomBasket');
      copy('cvtBottomTemp', 'cvtBottomTemp');
      copy('cvtBottomPhoto', 'cvtBottomPhoto');
      copy('cvtAvg', 'cvtAvgTemp');
      copy('cvtCvPct', 'cvtCvPct');
      copy('pm_sampleSize', 'pmSampleSize');
      copy('pm_collectionPoint', 'pmCollectionPoint');
      copy('pm_omphalitisCount', 'pmOmphalitisCount');
      copy('pm_omphalitisSeverity', 'pmOmphalitisSeverity');
      copy('pm_gaseousCecaCount', 'pmGaseousCecaCount');
      copy('pm_gaseousCecaSeverity', 'pmGaseousCecaSeverity');
      copy('pm_unabsorbedYolkCount', 'pmUnabsorbedYolkCount');
      copy('pm_unabsorbedYolkSeverity', 'pmUnabsorbedYolkSeverity');
      copy('pm_perihepatitisCount', 'pmPerihepatitisCount');
      copy('pm_perihepatitisSeverity', 'pmPerihepatitisSeverity');
      copy('pm_pericarditisCount', 'pmPericarditisCount');
      copy('pm_pericarditisSeverity', 'pmPericarditisSeverity');
      copy('pm_airsacAcuteCount', 'pmAirsacAcuteCount');
      copy('pm_airsacAcuteSeverity', 'pmAirsacAcuteSeverity');
      copy('pm_airsacChronicCount', 'pmAirsacChronicCount');
      copy('pm_airsacChronicSeverity', 'pmAirsacChronicSeverity');
      copy('pm_pulmonaryGranulomaCount', 'pmPulmonaryGranulomaCount');
      copy('pm_pulmonaryGranulomaSeverity', 'pmPulmonaryGranulomaSeverity');
      copy('pm_swollenJointsCount', 'pmSwollenJointsCount');
      copy('pm_swollenJointsSeverity', 'pmSwollenJointsSeverity');
      copy('pm_stuntedOrgansCount', 'pmStuntedOrgansCount');
      copy('pm_stuntedOrgansSeverity', 'pmStuntedOrgansSeverity');
      copy('pm_pulmonaryHemorrhageCount', 'pmPulmonaryHemorrhageCount');
      copy('pm_pulmonaryHemorrhageSeverity', 'pmPulmonaryHemorrhageSeverity');
      copy('pm_gizzardErosionsCount', 'pmGizzardErosionsCount');
      copy('pm_gizzardErosionsSeverity', 'pmGizzardErosionsSeverity');
      copy('pm_airSacCaseationsCount', 'pmAirSacCaseationsCount');
      copy('pm_airSacCaseationsSeverity', 'pmAirSacCaseationsSeverity');
      copy('pm_urolithiasisCount', 'pmUrolithiasisCount');
      copy('pm_urolithiasisSeverity', 'pmUrolithiasisSeverity');
      copy('pm_nephritisCount', 'pmNephritisCount');
      copy('pm_nephritisSeverity', 'pmNephritisSeverity');
      copy('pm_generalSepticemiaCount', 'pmGeneralSepticemiaCount');
      copy('pm_generalSepticemiaSeverity', 'pmGeneralSepticemiaSeverity');
      copy('pm_otherLesionsJson', 'pmOtherLesionsJson');
      copy('pm_suspectedCauseAuto', 'pmSuspectedCauseAuto');
      copy('pm_suspectedCauseManual', 'pmSuspectedCauseManual');
      copy('pm_photosJson', 'pmPhotosJson');
      copy('culledChicksTotalEggSet', 'culledChicksTotalEggSet');
      copy('culledChicksAnalysisJson', 'culledChicksAnalysisJson');
      copy('culledChicksAffectedPct', 'culledChicksAffectedPct');
      copy('culledChicksTopCategory', 'culledChicksTopCategory');
      copy('culledChicksTopSubtype', 'culledChicksTopSubtype');
      break;
    case 'chick_weights':
      copy('chickWeights', 'weightsJson');
      copy('chickSampleSize', 'sampleSize');
      copy('chickAvgWeight', 'avgWeight');
      copy('chickUniformityPct', 'uniformityPct');
      copy('chickCvPct', 'cvPct');
      copy('chickBmkAge', 'bmkAgeWeeks');
      copy('chickBmkWeight', 'bmkWeight');
      break;
    case 'fresh_egg_breakout':
      _mergeBreakoutRow(map, row, 'freshEggBreakout');
      break;
    case 'candled_egg_breakout':
      _mergeBreakoutRow(map, row, 'candledEggBreakout');
      break;
    case 'residue_breakout':
      _mergeBreakoutRow(map, row, 'residueHatchDay');
      copy('setterId', 'setter');
      copy('hatcherId', 'hatcher');
      copy('haTotalEggsSet', 'totalEggsSet');
      copy('haHatched', 'hatchedCount');
      copy('haCulled', 'culledCount');
      copy('haDead', 'deadCount');
      copy('haHatchability', 'hatchabilityPct');
      copy('haFertility', 'fertilityPct');
      copy('haHof', 'hofPct');
      break;
    case 'setter_optimizing':
      copy('setterId', 'setter');
      copy('soSetterId', 'setter');
      copy('so_machineType', 'machineType');
      copy('so_setpointF', 'setpointF');
      copy('so_actualF', 'actualF');
      copy('so_setpointRh', 'setpointRh');
      copy('so_actualRh', 'actualRh');
      copy('so_batchSize', 'batchSize');
      copy('so_batchCount', 'batchCount');
      copy('so_totalEggsSet', 'totalEggsSet');
      copy('so_turningAngle', 'turningAngle');
      copy('soCo2', 'co2Ppm');
      copy('soCo2Photo', 'co2Photo');
      copy('soBreed', 'estBreed');
      copy('soIncubationAge', 'incubationAgeDays');
      copy('soIncubationHours', 'incubationHours');
      copy('soEstReadings', 'estReadingsJson');
      copy('soEstPhotos', 'estPhotosJson');
      copy('so_estSamplesJson', 'estSamplesJson');
      copy('soEstAvg', 'estAvg');
      copy('soEstCv', 'estCvPct');
      copy('so_machineScreenPhoto', 'machineScreenPhoto');
      break;
    case 'hatcher_optimizing':
      copy('hatcherId', 'hatcher');
      copy('hoHatcherId', 'hatcher');
      copy('ho_setpointF', 'setpointF');
      copy('ho_setpointRh', 'setpointRh');
      copy('hoIncubationAge', 'incubationAgeDays');
      copy('hoIncubationHours', 'incubationHours');
      copy('hoCo2', 'co2Ppm');
      copy('hoCo2Photo', 'co2Photo');
      copy('hoCvtReadings', 'cvtReadingsJson');
      copy('hoCvtPhotos', 'cvtPhotosJson');
      copy('hoCvtAvg', 'cvtAvg');
      copy('hoCvtCv', 'cvtCvPct');
      copy('hoChickPanting', 'chickPanting');
      copy('hoChickPantingPhoto', 'chickPantingPhoto');
      copy('ho_meconium', 'meconium');
      copy('ho_transferDay', 'transferDay');
      break;
  }
}

void _mergeEggTraySummary(
  Map<String, dynamic> auditMap,
  Map<String, Object?> values,
) {
  final merged = <String, Object?>{
    ..._firstEggTraySummary(auditMap['esUvTrays']),
    ...values,
  }..removeWhere((_, value) => value == null);
  if (merged.isEmpty) return;
  auditMap['esUvTrays'] = jsonEncode([merged]);
}

Map<String, Object?> _firstEggTraySummary(Object? raw) {
  if (raw == null) return const {};
  try {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
      return Map<String, Object?>.from(decoded.first as Map);
    }
  } catch (_) {
    return const {};
  }
  return const {};
}

void _mergeBreakoutRow(
  Map<String, dynamic> map,
  Map<String, dynamic> row,
  String breakoutType,
) {
  void copy(String target, String source) {
    final value = row[source];
    if (value != null) map[target] = value;
  }

  map['ebBreakoutType'] = breakoutType;
  copy('ebStorageDays', 'storagePeriodDays');
  copy('haStorageDays', 'storagePeriodDays');
  copy('houseId', 'house');
  copy('setterId', 'setter');
  copy('hatcherId', 'hatcher');
  copy('ebBreakoutAgeDays', 'candlingDay');
  copy('ebBmkAge', 'bmkAgeWeeks');
  copy('ebTraySize', 'traySize');
  copy('ebInfertileCount', 'infertileCount');
  copy('ebEarlyDeadCount', 'earlyDeadCount');
  copy('ebMidDeadCount', 'midDeadCount');
  copy('ebLateDeadCount', 'lateDeadCount');
  copy('ebExternalPipCount', 'externalPipCount');
  copy('ebCrackedCount', 'crackedCount');
  copy('ebContaminatedCount', 'contaminatedCount');
  if (row['early24hCount'] != null || row['early48hCount'] != null) {
    map['ebEarlyDeadCount'] = row['early24hCount'];
    map['ebMidDeadCount'] = row['early48hCount'];
    map['ebLateDeadCount'] = row['bloodRingCount'];
  }
  _mergeBreakoutTrayEntry(map, row, breakoutType);
}

void _mergeBreakoutTrayEntry(
  Map<String, dynamic> map,
  Map<String, dynamic> row,
  String breakoutType,
) {
  final type = EggBreakoutType.fromStorageValue(breakoutType);
  final counts = <String, int>{};
  void addCount(String key, String column) {
    final value = panelRowAsInt(row[column]);
    if (value != null && value > 0) counts[key] = value;
  }

  addCount('infertile', 'infertileCount');
  if (type == EggBreakoutType.residueHatchDay) {
    addCount('earlyDead', 'earlyDeadCount');
    addCount('midDead', 'midDeadCount');
    addCount('lateDead', 'lateDeadCount');
    addCount('externalPip', 'externalPipCount');
    addCount('cracked', 'crackedCount');
    addCount('contaminated', 'contaminatedCount');
  } else {
    addCount('early24h', 'early24hCount');
    addCount('early48h', 'early48hCount');
    addCount('early72hBloodRing', 'bloodRingCount');
    if (type == EggBreakoutType.candledEggBreakout) {
      addCount('blackEye', 'blackEyeCount');
    }
  }

  final existing = EggBreakoutSampleEntry.decodeList(
    map['ebTrayBreakoutJson']?.toString(),
    fallbackBreakoutType: type,
  );
  final label =
      panelRowAsText(row['tray']) ??
      panelRowAsText(row['scopeLabel']) ??
      'Tray ${existing.length + 1}';
  final next = EggBreakoutSampleEntry.tray(
    id: panelRowAsText(row['id']) ?? 'tray-${existing.length + 1}',
    label: label,
    house: panelRowAsText(row['house']),
    setter: panelRowAsText(row['setter']),
    hatcher: panelRowAsText(row['hatcher']),
    trolley: panelRowAsText(row['trolley']),
    tray: panelRowAsText(row['tray']) ?? label,
    position: panelRowAsText(row['position']),
    traySize: panelRowAsInt(row['traySize']),
    breakoutType: type,
    counts: counts,
  );
  map['ebTrayBreakoutJson'] = EggBreakoutSampleEntry.encodeList([
    ...existing,
    next,
  ]);
}

/// Moved verbatim from `_AuditSessionScreenState._asInt`. It is public rather
/// than private because the State class still calls it from the panel-row
/// code that stayed behind; exporting the one implementation avoids leaving a
/// second copy behind to drift.
int? panelRowAsInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

/// Moved verbatim from `_AuditSessionScreenState._asText`; see
/// [panelRowAsInt] for why it is public.
String? panelRowAsText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
