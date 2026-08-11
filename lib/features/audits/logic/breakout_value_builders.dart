import '../../../core/utils/bmk_age_calculator.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/panel_sample_schema.dart';
import '../../../data/models/station_sample_model.dart';
import '../models/egg_breakout_sample.dart';
import 'audit_value_parsing.dart';

/// Whether [tableName] is one of the three egg-breakout panel tables.
bool isEggBreakoutPanelTable(String tableName) {
  return tableName == 'fresh_egg_breakout' ||
      tableName == 'candled_egg_breakout' ||
      tableName == 'residue_breakout';
}

/// The [EggBreakoutType] that [tableName] saves rows for.
///
/// Not itself named in this extraction's move list, but it is used by
/// [breakoutEntriesForTable] below (which is on the list) and is a pure
/// switch with no provider state, so it is moved here rather than
/// duplicated. The provider's other two call sites are updated to call this
/// top-level function directly.
EggBreakoutType breakoutTypeForTable(String tableName) {
  return switch (tableName) {
    'fresh_egg_breakout' => EggBreakoutType.freshEggBreakout,
    'candled_egg_breakout' => EggBreakoutType.candledEggBreakout,
    'residue_breakout' => EggBreakoutType.residueHatchDay,
    _ => EggBreakoutType.fromStorageValue(null),
  };
}

/// The tray-mode sample entries recorded for [tableName] in [draft].
List<EggBreakoutSampleEntry> breakoutTrayEntriesForTable(
  String tableName,
  AuditModel draft,
) {
  return breakoutEntriesForTable(
    tableName,
    draft,
  ).where((entry) => entry.sampleMode == EggBreakoutSampleMode.tray).toList();
}

/// The pool-mode sample entries recorded for [tableName] in [draft].
List<EggBreakoutSampleEntry> breakoutPoolEntriesForTable(
  String tableName,
  AuditModel draft,
) {
  return breakoutEntriesForTable(
    tableName,
    draft,
  ).where((entry) => entry.sampleMode == EggBreakoutSampleMode.pool).toList();
}

/// The tray entries if any were recorded, otherwise the pool entries.
List<EggBreakoutSampleEntry> breakoutLeafEntriesForTable(
  String tableName,
  AuditModel draft,
) {
  final trayEntries = breakoutTrayEntriesForTable(tableName, draft);
  if (trayEntries.isNotEmpty) return trayEntries;
  return breakoutPoolEntriesForTable(tableName, draft);
}

/// All sample entries recorded for [tableName] in [draft].
List<EggBreakoutSampleEntry> breakoutEntriesForTable(
  String tableName,
  AuditModel draft,
) {
  final type = breakoutTypeForTable(tableName);
  return EggBreakoutSampleEntry.decodeList(
    draft.ebTrayBreakoutJson,
    fallbackBreakoutType: EggBreakoutType.fromStorageValue(
      draft.ebBreakoutType,
    ),
  ).where((entry) => entry.breakoutType == type).toList();
}

/// The benchmark-context columns (storage period, benchmark age) shared by
/// every breakout value map.
///
/// The original provider method read `_context?.flockAgeWeeks` and
/// `_context?.flockEntryDate` directly; those are provider instance state,
/// so they are threaded through here as explicit named parameters.
Map<String, Object?> breakoutBmkContextValues(
  AuditModel draft,
  EggBreakoutType breakoutType, {
  required int? flockAgeWeeks,
  required DateTime? flockEntryDate,
}) {
  final storageDays = draft.ebStorageDays ?? draft.haStorageDays ?? 0;
  final bmkAgeDays = breakoutType.calculateBmkAgeDays(
    currentFlockAgeDays: BmkAgeCalculator.currentFlockAgeDays(
      flockAgeWeeks: flockAgeWeeks,
      flockEntryDate: flockEntryDate,
      auditDate: draft.date,
    ),
    storageDays: storageDays,
    candlingDay: draft.ebBreakoutAgeDays ?? 10,
  );
  return {
    'storagePeriodDays': storageDays,
    'bmkAgeWeeks':
        BmkAgeCalculator.displayWeekForDays(bmkAgeDays) ??
        draft.ebBmkAge ??
        draft.haBmkAge,
  };
}

/// The display label for a breakout tray entry at [index].
String breakoutTrayLabel(EggBreakoutSampleEntry entry, int index) {
  final label = entry.label.trim();
  return label.isEmpty ? 'Tray ${index + 1}' : label;
}

/// The panel-hierarchy row id for a breakout entry at [index].
String breakoutEntryRowId(
  String baseRowId,
  int index,
  EggBreakoutSampleEntry entry,
  SamplingLayer scopeType,
) {
  if (index == 0) return baseRowId;
  final entryId = blankToNull(entry.id) ?? 'tray-${index + 1}';
  return '$baseRowId:${scopeType.dbValue}:${index + 1}:$entryId';
}

/// The display label for the given comparison [scopeType] on a breakout
/// entry, falling back to [fallbackLabel] when the entry has no value.
String breakoutScopeLabelForEntry(
  SamplingLayer scopeType,
  EggBreakoutSampleEntry entry,
  String fallbackLabel,
) {
  return switch (scopeType) {
    SamplingLayer.house => blankToNull(entry.house) ?? fallbackLabel,
    SamplingLayer.setterHatcher =>
      '${blankToNull(entry.setter) ?? ''}/${blankToNull(entry.hatcher) ?? ''}',
    SamplingLayer.setter => blankToNull(entry.setter) ?? fallbackLabel,
    SamplingLayer.hatcher => blankToNull(entry.hatcher) ?? fallbackLabel,
    SamplingLayer.trolley => blankToNull(entry.trolley) ?? fallbackLabel,
    SamplingLayer.tray => blankToNull(entry.tray) ?? fallbackLabel,
    SamplingLayer.pool => 'Random',
  };
}

/// The comparison-group heading for the given [scopeType], or `null` when
/// the scope is a plain pool (no comparison group).
String? breakoutGroupLabelForScope(SamplingLayer scopeType) {
  return switch (scopeType) {
    SamplingLayer.house => 'House comparison',
    SamplingLayer.setter ||
    SamplingLayer.hatcher ||
    SamplingLayer.setterHatcher => 'Machine comparison',
    SamplingLayer.trolley => 'Trolley comparison',
    SamplingLayer.tray => 'Tray comparison',
    SamplingLayer.pool => null,
  };
}

/// Whether [scopeType] sits at or before the trolley level in the
/// house -> setter/hatcher -> trolley -> tray hierarchy.
bool scopeBeforeTrolley(SamplingLayer scopeType) {
  return scopeType == SamplingLayer.pool ||
      scopeType == SamplingLayer.house ||
      scopeType == SamplingLayer.setter ||
      scopeType == SamplingLayer.hatcher ||
      scopeType == SamplingLayer.setterHatcher;
}

/// The measurement-column values for a single breakout sample [entry],
/// dispatched by [tableName].
///
/// See [breakoutBmkContextValues] for why `flockAgeWeeks`/`flockEntryDate`
/// are threaded through as explicit parameters.
Map<String, Object?> breakoutValuesForEntry(
  String tableName,
  AuditModel draft,
  EggBreakoutSampleEntry entry,
  Map<String, Object?>? benchmark, {
  required int? flockAgeWeeks,
  required DateTime? flockEntryDate,
}) {
  return switch (tableName) {
    'fresh_egg_breakout' => freshBreakoutValuesForEntry(
      draft,
      entry,
      benchmark,
      flockAgeWeeks: flockAgeWeeks,
      flockEntryDate: flockEntryDate,
    ),
    'candled_egg_breakout' => candledBreakoutValuesForEntry(
      draft,
      entry,
      benchmark,
      flockAgeWeeks: flockAgeWeeks,
      flockEntryDate: flockEntryDate,
    ),
    'residue_breakout' => residueBreakoutValuesForEntry(
      draft,
      entry,
      benchmark,
      flockAgeWeeks: flockAgeWeeks,
      flockEntryDate: flockEntryDate,
    ),
    _ => const <String, Object?>{},
  };
}

Map<String, Object?> freshBreakoutValuesForEntry(
  AuditModel draft,
  EggBreakoutSampleEntry entry,
  Map<String, Object?>? benchmark, {
  EggBreakoutType breakoutType = EggBreakoutType.freshEggBreakout,
  required int? flockAgeWeeks,
  required DateTime? flockEntryDate,
}) {
  final total = entry.totalSample;
  final infertilePct = pct(entry.counts['infertile'], total);
  final early24hPct = pct(entry.counts['early24h'], total);
  final early48hPct = pct(entry.counts['early48h'], total);
  final bloodRingPct = pct(entry.counts['early72hBloodRing'], total);
  return {
    ...breakoutBmkContextValues(
      draft,
      breakoutType,
      flockAgeWeeks: flockAgeWeeks,
      flockEntryDate: flockEntryDate,
    ),
    'traySize': total ?? entry.traySize,
    'infertileCount': entry.counts['infertile'],
    'early24hCount': entry.counts['early24h'],
    'early48hCount': entry.counts['early48h'],
    'bloodRingCount': entry.counts['early72hBloodRing'],
    'infertilePct': infertilePct,
    'early24hPct': early24hPct,
    'early48hPct': early48hPct,
    'bloodRingPct': bloodRingPct,
    'infertileDiffPct': breakoutDiffPct(benchmark, 'infertile', infertilePct),
    'early24hDiffPct': breakoutDiffPct(benchmark, 'early24h', early24hPct),
    'early48hDiffPct': breakoutDiffPct(benchmark, 'early48h', early48hPct),
    'bloodRingDiffPct': breakoutDiffPct(
      benchmark,
      'early72hBloodRing',
      bloodRingPct,
    ),
  };
}

Map<String, Object?> candledBreakoutValuesForEntry(
  AuditModel draft,
  EggBreakoutSampleEntry entry,
  Map<String, Object?>? benchmark, {
  required int? flockAgeWeeks,
  required DateTime? flockEntryDate,
}) {
  final blackEyePct = pct(entry.counts['blackEye'], entry.totalSample);
  return {
    ...freshBreakoutValuesForEntry(
      draft,
      entry,
      benchmark,
      breakoutType: EggBreakoutType.candledEggBreakout,
      flockAgeWeeks: flockAgeWeeks,
      flockEntryDate: flockEntryDate,
    ),
    'candlingDay': draft.ebBreakoutAgeDays,
    'position': blankToNull(entry.position),
    'blackEyeCount': entry.counts['blackEye'],
    'blackEyePct': blackEyePct,
    'blackEyeDiffPct': breakoutDiffPct(benchmark, 'blackEye', blackEyePct),
  };
}

Map<String, Object?> residueBreakoutValuesForEntry(
  AuditModel draft,
  EggBreakoutSampleEntry entry,
  Map<String, Object?>? benchmark, {
  required int? flockAgeWeeks,
  required DateTime? flockEntryDate,
}) {
  final total = entry.totalSample;
  final infertilePct = pct(entry.counts['infertile'], total);
  final earlyDeadPct = pct(entry.counts['earlyDead'], total);
  final midDeadPct = pct(entry.counts['midDead'], total);
  final lateDeadPct = pct(entry.counts['lateDead'], total);
  final externalPipPct = pct(entry.counts['externalPip'], total);
  final crackedPct = pct(entry.counts['cracked'], total);
  final contaminatedPct = pct(entry.counts['contaminated'], total);
  return {
    ...breakoutBmkContextValues(
      draft,
      EggBreakoutType.residueHatchDay,
      flockAgeWeeks: flockAgeWeeks,
      flockEntryDate: flockEntryDate,
    ),
    'position': blankToNull(entry.position),
    'traySize': total ?? entry.traySize,
    'infertileCount': entry.counts['infertile'],
    'earlyDeadCount': entry.counts['earlyDead'],
    'midDeadCount': entry.counts['midDead'],
    'lateDeadCount': entry.counts['lateDead'],
    'externalPipCount': entry.counts['externalPip'],
    'crackedCount': entry.counts['cracked'],
    'contaminatedCount': entry.counts['contaminated'],
    'infertilePct': infertilePct,
    'earlyDeadPct': earlyDeadPct,
    'midDeadPct': midDeadPct,
    'lateDeadPct': lateDeadPct,
    'externalPipPct': externalPipPct,
    'crackedPct': crackedPct,
    'contaminatedPct': contaminatedPct,
    'infertileDiffPct': breakoutDiffPct(benchmark, 'infertile', infertilePct),
    'earlyDeadDiffPct': breakoutDiffPct(benchmark, 'earlyDead', earlyDeadPct),
    'midDeadDiffPct': breakoutDiffPct(benchmark, 'midDead', midDeadPct),
    'lateDeadDiffPct': breakoutDiffPct(benchmark, 'lateDead', lateDeadPct),
    'externalPipDiffPct': breakoutDiffPct(
      benchmark,
      'externalPip',
      externalPipPct,
    ),
    'crackedDiffPct': breakoutDiffPct(benchmark, 'cracked', crackedPct),
    'contaminatedDiffPct': breakoutDiffPct(
      benchmark,
      'contaminated',
      contaminatedPct,
    ),
    'totalEggsSet': draft.haTotalEggsSet,
    'hatchedCount': draft.haHatched,
    'culledCount': draft.haCulled,
    'deadCount': draft.haDead,
    'hatchabilityPct': draft.haHatchability,
    'fertilityPct': draft.haFertility,
    'hofPct': draft.haHof,
    'culledPct': pct(draft.haCulled, draft.haTotalEggsSet),
    'deadPct': pct(draft.haDead, draft.haTotalEggsSet),
  };
}

/// The difference between the current percentage and the benchmark
/// percentage for [countKey], or `null` when either side is unavailable.
double? breakoutDiffPct(
  Map<String, Object?>? benchmark,
  String countKey,
  double? currentPct,
) {
  if (benchmark == null || currentPct == null) return null;
  final column = breakoutBmkColumnForCountKey(countKey);
  if (column == null) return null;
  final bmkPct = asDouble(benchmark[column]);
  if (bmkPct == null) return null;
  return currentPct - bmkPct;
}

/// The benchmark row's column name for a given breakout [countKey].
String? breakoutBmkColumnForCountKey(String countKey) {
  return switch (countKey) {
    'early72hBloodRing' => 'bloodRingPct',
    'externalPip' => 'externalPipPct',
    'contaminated' => 'contamPct',
    'infertile' ||
    'early24h' ||
    'early48h' ||
    'blackEye' ||
    'earlyDead' ||
    'midDead' ||
    'lateDead' ||
    'cracked' => '${countKey}Pct',
    _ => null,
  };
}

Map<String, Object?> freshBreakoutValues(
  AuditModel draft, {
  EggBreakoutType breakoutType = EggBreakoutType.freshEggBreakout,
  required int? flockAgeWeeks,
  required DateTime? flockEntryDate,
}) {
  final rollup = breakoutRollup(draft, breakoutType: breakoutType);
  return {
    ...breakoutBmkContextValues(
      draft,
      breakoutType,
      flockAgeWeeks: flockAgeWeeks,
      flockEntryDate: flockEntryDate,
    ),
    'traySize': rollup.totalSample ?? draft.ebTraySize,
    'infertileCount': rollup.counts['infertile'] ?? draft.ebInfertileCount,
    'early24hCount': rollup.counts['early24h'],
    'early48hCount': rollup.counts['early48h'],
    'bloodRingCount': rollup.counts['early72hBloodRing'],
    'infertilePct': pct(rollup.counts['infertile'], rollup.totalSample),
    'early24hPct': pct(rollup.counts['early24h'], rollup.totalSample),
    'early48hPct': pct(rollup.counts['early48h'], rollup.totalSample),
    'bloodRingPct': pct(
      rollup.counts['early72hBloodRing'],
      rollup.totalSample,
    ),
  };
}

Map<String, Object?> candledBreakoutValues(
  AuditModel draft, {
  required int? flockAgeWeeks,
  required DateTime? flockEntryDate,
}) {
  final values = freshBreakoutValues(
    draft,
    breakoutType: EggBreakoutType.candledEggBreakout,
    flockAgeWeeks: flockAgeWeeks,
    flockEntryDate: flockEntryDate,
  );
  final rollup = breakoutRollup(
    draft,
    breakoutType: EggBreakoutType.candledEggBreakout,
  );
  return {
    ...values,
    'candlingDay': draft.ebBreakoutAgeDays,
    'position': firstBreakoutPosition(
      draft,
      breakoutType: EggBreakoutType.candledEggBreakout,
    ),
    'blackEyeCount': rollup.counts['blackEye'],
    'blackEyePct': pct(rollup.counts['blackEye'], rollup.totalSample),
  };
}

Map<String, Object?> residueBreakoutValues(
  AuditModel draft, {
  required int? flockAgeWeeks,
  required DateTime? flockEntryDate,
}) {
  final rollup = breakoutRollup(
    draft,
    breakoutType: EggBreakoutType.residueHatchDay,
  );
  return {
    ...breakoutBmkContextValues(
      draft,
      EggBreakoutType.residueHatchDay,
      flockAgeWeeks: flockAgeWeeks,
      flockEntryDate: flockEntryDate,
    ),
    'position': firstBreakoutPosition(
      draft,
      breakoutType: EggBreakoutType.residueHatchDay,
    ),
    'traySize': rollup.totalSample ?? draft.ebTraySize,
    'infertileCount': rollup.counts['infertile'] ?? draft.ebInfertileCount,
    'earlyDeadCount': rollup.counts['earlyDead'] ?? draft.ebEarlyDeadCount,
    'midDeadCount': rollup.counts['midDead'] ?? draft.ebMidDeadCount,
    'lateDeadCount': rollup.counts['lateDead'] ?? draft.ebLateDeadCount,
    'externalPipCount':
        rollup.counts['externalPip'] ?? draft.ebExternalPipCount,
    'crackedCount': rollup.counts['cracked'] ?? draft.ebCrackedCount,
    'contaminatedCount':
        rollup.counts['contaminated'] ?? draft.ebContaminatedCount,
    'infertilePct': pct(rollup.counts['infertile'], rollup.totalSample),
    'earlyDeadPct': pct(rollup.counts['earlyDead'], rollup.totalSample),
    'midDeadPct': pct(rollup.counts['midDead'], rollup.totalSample),
    'lateDeadPct': pct(rollup.counts['lateDead'], rollup.totalSample),
    'externalPipPct': pct(rollup.counts['externalPip'], rollup.totalSample),
    'crackedPct': pct(rollup.counts['cracked'], rollup.totalSample),
    'contaminatedPct': pct(
      rollup.counts['contaminated'],
      rollup.totalSample,
    ),
    'totalEggsSet': draft.haTotalEggsSet,
    'hatchedCount': draft.haHatched,
    'culledCount': draft.haCulled,
    'deadCount': draft.haDead,
    'hatchabilityPct': draft.haHatchability,
    'fertilityPct': draft.haFertility,
    'hofPct': draft.haHof,
    'culledPct': pct(draft.haCulled, draft.haTotalEggsSet),
    'deadPct': pct(draft.haDead, draft.haTotalEggsSet),
  };
}

/// The aggregate counts and total sample size across every breakout entry
/// (optionally filtered to a single [breakoutType]), falling back to the
/// draft's legacy scalar count fields when no entries were recorded.
///
/// Not itself named in this extraction's move list, but it has no callers
/// left in the provider once [freshBreakoutValues], [candledBreakoutValues],
/// and [residueBreakoutValues] (its only callers) move here, so it is moved
/// rather than duplicated.
({Map<String, int> counts, int? totalSample}) breakoutRollup(
  AuditModel draft, {
  EggBreakoutType? breakoutType,
}) {
  final allEntries = EggBreakoutSampleEntry.decodeList(
    draft.ebTrayBreakoutJson,
    fallbackBreakoutType: EggBreakoutType.fromStorageValue(
      draft.ebBreakoutType,
    ),
  );
  final entries = breakoutType == null
      ? allEntries
      : allEntries.where((entry) => entry.breakoutType == breakoutType).toList();
  final counts = <String, int>{};
  var total = 0;
  for (final entry in entries) {
    total += entry.totalSample ?? 0;
    for (final item in entry.counts.entries) {
      counts[item.key] = (counts[item.key] ?? 0) + item.value;
    }
  }
  if (counts.isEmpty && allEntries.isEmpty) {
    counts.addAll({
      if (draft.ebInfertileCount != null) 'infertile': draft.ebInfertileCount!,
      if (draft.ebEarlyDeadCount != null)
        'earlyDead': draft.ebEarlyDeadCount!,
      if (draft.ebMidDeadCount != null) 'midDead': draft.ebMidDeadCount!,
      if (draft.ebLateDeadCount != null) 'lateDead': draft.ebLateDeadCount!,
      if (draft.ebExternalPipCount != null)
        'externalPip': draft.ebExternalPipCount!,
      if (draft.ebCrackedCount != null) 'cracked': draft.ebCrackedCount!,
      if (draft.ebContaminatedCount != null)
        'contaminated': draft.ebContaminatedCount!,
    });
  }
  return (
    counts: counts,
    totalSample: total == 0
        ? (allEntries.isEmpty ? draft.ebTraySize : null)
        : total,
  );
}

/// The first non-blank tray position recorded across breakout entries
/// (optionally filtered to a single [breakoutType]).
String? firstBreakoutPosition(
  AuditModel draft, {
  EggBreakoutType? breakoutType,
}) {
  final allEntries = EggBreakoutSampleEntry.decodeList(
    draft.ebTrayBreakoutJson,
    fallbackBreakoutType: EggBreakoutType.fromStorageValue(
      draft.ebBreakoutType,
    ),
  );
  final entries = breakoutType == null
      ? allEntries
      : allEntries.where((entry) => entry.breakoutType == breakoutType);
  for (final entry in entries) {
    final position = entry.position?.trim();
    if (position != null && position.isNotEmpty) return position;
  }
  return null;
}

/// Whether [scopeType] carries house-level information (house itself, or
/// any layer scoped beneath a house: setter/hatcher/trolley/tray).
bool scopeIncludesHouse(SamplingLayer scopeType) {
  return scopeType == SamplingLayer.house ||
      scopeType == SamplingLayer.setter ||
      scopeType == SamplingLayer.hatcher ||
      scopeType == SamplingLayer.setterHatcher ||
      scopeType == SamplingLayer.trolley ||
      scopeType == SamplingLayer.tray;
}

/// The display label for a station sample at the given comparison
/// [scopeType].
String scopeLabelForSample(
  SamplingLayer scopeType,
  StationSampleModel sample,
) {
  return switch (scopeType) {
    SamplingLayer.house =>
      blankToNull(sample.houseLabel) ??
          blankToNull(sample.houseNo) ??
          sample.sampleLabel,
    SamplingLayer.setterHatcher =>
      '${sample.setterNo ?? ''}/${sample.hatcherNo ?? ''}',
    SamplingLayer.setter => blankToNull(sample.setterNo) ?? sample.sampleLabel,
    SamplingLayer.hatcher =>
      blankToNull(sample.hatcherNo) ?? sample.sampleLabel,
    SamplingLayer.tray || SamplingLayer.trolley => sample.sampleLabel,
    SamplingLayer.pool => 'Random',
  };
}
