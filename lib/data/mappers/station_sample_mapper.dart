import 'dart:convert';

import '../../core/utils/bmk_age_calculator.dart';
import '../models/audit_model.dart';
import '../models/audit_session_model.dart';
import '../models/sample_mode.dart';
import '../models/station_sample_model.dart';

class StationSampleMapper {
  const StationSampleMapper._();

  static StationSampleModel fromLegacyAudit(
    AuditModel audit, {
    AuditSessionModel? session,
  }) {
    final stationType = stationTypeForAuditType(audit.auditType);
    final sampleMode = SampleMode.isCompare(audit.sampleMode)
        ? StationSampleModel.sampleModeComparison
        : StationSampleModel.sampleModePooled;
    final storageDays = _storageDays(audit);
    final bmkDays = BmkAgeCalculator.calculateDays(
      currentFlockAgeDays: BmkAgeCalculator.currentFlockAgeDaysFromWeeks(
        session?.flockAgeWeeks,
      ),
      auditDate: audit.date,
      legacyBmkAgeWeeks: _legacyBmkWeeks(audit),
      storageDays: storageDays,
    );
    final breakoutType = _breakoutType(audit.ebBreakoutType);
    final now = DateTime.now();
    final sessionId = session?.id ?? audit.sessionId ?? '';

    return StationSampleModel(
      id: '${audit.id}-sample',
      auditSessionId: sessionId,
      legacyAuditId: audit.id,
      stationType: stationType,
      sectorType: _sectorType(stationType),
      sampleKind: _sampleKind(stationType),
      sampleMode: sampleMode,
      comparisonType: _comparisonType(stationType, sampleMode),
      sampleIndex: audit.hatchNumber,
      sampleLabel: _sampleLabel(stationType, audit.hatchNumber, audit),
      sampleType: _sampleType(stationType, breakoutType),
      breakoutType: breakoutType,
      groupKey: audit.compareGroupKey,
      groupLabel: _groupLabel(stationType, audit.compareGroupKey),
      batchNo: audit.hatchNumber.toString(),
      houseNo: _houseNo(stationType, audit.hatchNumber),
      houseLabel: _houseLabel(stationType, audit.hatchNumber),
      hatchNo: audit.hatchNumber.toString(),
      storageDays: storageDays,
      incubationDay: audit.soIncubationAge ?? audit.hoIncubationAge,
      setterNo: audit.setterId ?? audit.soSetterId,
      hatcherNo: audit.hatcherId ?? audit.hoHatcherId,
      calculatedBmkAgeDays: bmkDays,
      benchmarkBreed: session?.breed ?? audit.soBreed ?? audit.hoBreed,
      benchmarkAgeDays: bmkDays,
      resultSummaryJson: resultSummaryJsonForAudit(audit),
      createdAt: audit.createdAt,
      updatedAt: audit.updatedAt.isAfter(audit.createdAt)
          ? audit.updatedAt
          : now,
    );
  }

  static Map<String, dynamic> legacyAuditPatchForSample(
    StationSampleModel sample,
  ) {
    final patch = <String, dynamic>{
      'sessionId': sample.auditSessionId,
      'sampleMode': sample.sampleMode == StationSampleModel.sampleModeComparison
          ? SampleMode.compare
          : SampleMode.pool,
      'compareGroupKey':
          sample.sampleMode == StationSampleModel.sampleModeComparison
          ? sample.groupKey
          : null,
      'updatedAt': sample.updatedAt.toIso8601String(),
    };

    final hatchNumber = int.tryParse(sample.hatchNo ?? sample.batchNo ?? '');
    if (hatchNumber != null) {
      patch['hatchNumber'] = hatchNumber;
    }
    if (sample.setterNo != null) {
      patch['setterId'] = sample.setterNo;
      patch['soSetterId'] = sample.setterNo;
    }
    if (sample.hatcherNo != null) {
      patch['hatcherId'] = sample.hatcherNo;
      patch['hoHatcherId'] = sample.hatcherNo;
    }
    if (sample.storageDays != null) {
      final storageKey = _legacyStorageDaysKey(sample);
      if (storageKey != null) {
        patch[storageKey] = sample.storageDays;
      }
    }
    if (sample.incubationDay != null) {
      final incubationKey = _legacyIncubationDayKey(sample);
      if (incubationKey != null) {
        patch[incubationKey] = sample.incubationDay;
      }
    }
    final legacyWeek = _legacyWeek(sample.calculatedBmkAgeDays);
    if (legacyWeek != null) {
      final bmkKey = _legacyBmkAgeKey(sample);
      if (bmkKey != null) {
        patch[bmkKey] = legacyWeek;
      }
    }
    if (sample.breakoutType != null) {
      patch['ebBreakoutType'] = sample.breakoutType;
    }
    return patch;
  }

  static String? _legacyStorageDaysKey(StationSampleModel sample) {
    if (sample.stationType == 'egg') return 'esEggStorageDays';
    if (sample.stationType == 'chicks') return 'chickStorageDays';
    if (sample.stationType == 'hatch_analysis_egg_breakouts') {
      return _isEggBreakoutSample(sample) ? 'ebStorageDays' : 'haStorageDays';
    }
    return null;
  }

  static String? _legacyBmkAgeKey(StationSampleModel sample) {
    if (sample.stationType == 'egg') return 'esEggBmkAge';
    if (sample.stationType == 'chicks') return 'chickBmkAge';
    if (sample.stationType == 'hatch_analysis_egg_breakouts') {
      return _isEggBreakoutSample(sample) ? 'ebBmkAge' : 'haBmkAge';
    }
    return null;
  }

  static String? _legacyIncubationDayKey(StationSampleModel sample) {
    if (sample.stationType == 'setters') return 'soIncubationAge';
    if (sample.stationType == 'hatchers') return 'hoIncubationAge';
    return null;
  }

  static bool _isEggBreakoutSample(StationSampleModel sample) {
    if (sample.breakoutType != null) return true;
    return sample.sampleType == StationSampleModel.sampleTypeBreakoutFresh ||
        sample.sampleType == StationSampleModel.sampleTypeBreakoutCandled10d ||
        sample.sampleType == StationSampleModel.sampleTypeBreakoutResidue21d;
  }

  static String stationTypeForAuditType(String auditType) {
    switch (auditType) {
      case 'Egg':
        return 'egg';
      case 'Chicks':
        return 'chicks';
      case 'Hatch Analysis & Egg Breakouts':
        return 'hatch_analysis_egg_breakouts';
      case 'Setters':
        return 'setters';
      case 'Hatchers':
        return 'hatchers';
      default:
        return auditType.trim().toLowerCase().replaceAll(' ', '_');
    }
  }

  static String resultSummaryJsonForAudit(AuditModel audit) {
    final summary = <String, Object?>{
      'auditType': audit.auditType,
      'hatchNumber': audit.hatchNumber,
      'esEggAvgWeight': audit.esEggAvgWeight,
      'chickAvgWeight': audit.chickAvgWeight,
      'pasgarFinalScore': audit.pasgarFinalScore,
      'haHatchability': audit.haHatchability,
      'haFertility': audit.haFertility,
      'haHof': audit.haHof,
      'ebBreakoutType': audit.ebBreakoutType,
      'soEstAvg': audit.soEstAvg,
      'hoCvtAvg': audit.hoCvtAvg,
    }..removeWhere((_, value) => value == null);
    return jsonEncode(summary);
  }

  static String? _comparisonType(String stationType, String sampleMode) {
    if (sampleMode != StationSampleModel.sampleModeComparison) return null;
    switch (stationType) {
      case 'egg':
        return StationSampleModel.comparisonTypeHouse;
      case 'setters':
      case 'hatchers':
      case 'chicks':
        return StationSampleModel.comparisonTypeMachine;
      case 'hatch_analysis_egg_breakouts':
        return StationSampleModel.comparisonTypeBatch;
      default:
        return null;
    }
  }

  static String _sectorType(String stationType) {
    return switch (stationType) {
      'egg' => StationSampleModel.sectorEggQuality,
      'chicks' => StationSampleModel.sectorChickQuality,
      'hatch_analysis_egg_breakouts' => StationSampleModel.sectorHatchBreakout,
      'setters' => StationSampleModel.sectorSetterOptimizing,
      'hatchers' => StationSampleModel.sectorHatcherOptimizing,
      _ => StationSampleModel.sectorDefault,
    };
  }

  static String _sampleKind(String stationType) {
    return switch (stationType) {
      'egg' => StationSampleModel.sampleKindHouse,
      'chicks' ||
      'setters' ||
      'hatchers' => StationSampleModel.sampleKindMachine,
      'hatch_analysis_egg_breakouts' => StationSampleModel.sampleKindBatch,
      _ => StationSampleModel.sampleKindPooled,
    };
  }

  static String _sampleType(String stationType, String? breakoutType) {
    if (stationType == 'chicks') {
      return StationSampleModel.sampleTypeChickQualityHatchedBatch;
    }
    if (stationType == 'hatch_analysis_egg_breakouts') {
      switch (breakoutType) {
        case StationSampleModel.breakoutTypeFresh:
          return StationSampleModel.sampleTypeBreakoutFresh;
        case StationSampleModel.breakoutTypeCandled10d:
          return StationSampleModel.sampleTypeBreakoutCandled10d;
        case StationSampleModel.breakoutTypeResidue21d:
          return StationSampleModel.sampleTypeBreakoutResidue21d;
      }
    }
    return StationSampleModel.sampleTypeDefault;
  }

  static String _sampleLabel(
    String stationType,
    int sampleIndex,
    AuditModel audit,
  ) {
    if (stationType == 'egg') return 'H$sampleIndex';
    if (stationType == 'chicks') {
      return _chickMachineSampleLabel(
        setterNo: audit.setterId ?? audit.soSetterId,
        hatcherNo: audit.hatcherId ?? audit.hoHatcherId,
        fallbackIndex: sampleIndex,
      );
    }
    if (stationType == 'setters') {
      return _machineSampleLabel(
        audit.setterId ?? audit.soSetterId,
        prefix: 'S',
        fallbackIndex: sampleIndex,
      );
    }
    if (stationType == 'hatchers') {
      return _machineSampleLabel(
        audit.hatcherId ?? audit.hoHatcherId,
        prefix: 'H',
        fallbackIndex: sampleIndex,
      );
    }
    return 'Sample $sampleIndex';
  }

  static String? _groupLabel(String stationType, String? groupKey) {
    if (groupKey == null || groupKey.isEmpty) return null;
    if (stationType == 'egg') return 'House comparison';
    if (stationType == 'chicks') return 'Machine comparison';
    if (stationType == 'setters') return 'Setter comparison';
    if (stationType == 'hatchers') return 'Hatcher comparison';
    return 'Comparison';
  }

  static String _machineSampleLabel(
    String? raw, {
    required String prefix,
    required int fallbackIndex,
  }) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return '$prefix$fallbackIndex';
    final digits = RegExp(
      r'\d+',
    ).allMatches(trimmed).map((match) => match.group(0)).join();
    if (digits.isNotEmpty) return '$prefix$digits';
    final withoutPrefix = trimmed.toLowerCase().startsWith(prefix.toLowerCase())
        ? trimmed.substring(1).trim()
        : trimmed;
    return '$prefix$withoutPrefix';
  }

  static String _chickMachineSampleLabel({
    required String? setterNo,
    required String? hatcherNo,
    required int fallbackIndex,
  }) {
    final setterLabel = _machineSampleLabel(
      setterNo,
      prefix: 'S',
      fallbackIndex: fallbackIndex,
    );
    final hatcherLabel = _machineSampleLabel(
      hatcherNo,
      prefix: 'H',
      fallbackIndex: fallbackIndex,
    );
    return '$setterLabel$hatcherLabel';
  }

  static String? _houseNo(String stationType, int sampleIndex) {
    if (stationType == 'egg') return 'H$sampleIndex';
    return null;
  }

  static String? _houseLabel(String stationType, int sampleIndex) {
    if (stationType == 'egg') return 'House $sampleIndex';
    return null;
  }

  static String? _breakoutType(String? value) {
    final normalized = value?.trim().toLowerCase().replaceAll(' ', '_');
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized == 'fresheggbreakout' || normalized.contains('fresh')) {
      return StationSampleModel.breakoutTypeFresh;
    }
    if (normalized == 'candledeggbreakout' ||
        normalized.contains('candled') ||
        normalized.contains('10')) {
      return StationSampleModel.breakoutTypeCandled10d;
    }
    if (normalized == 'residuehatchday' ||
        normalized.contains('residue') ||
        normalized.contains('hatch') ||
        normalized.contains('21')) {
      return StationSampleModel.breakoutTypeResidue21d;
    }
    return normalized;
  }

  static int? _storageDays(AuditModel audit) {
    return audit.esEggStorageDays ??
        audit.chickStorageDays ??
        audit.haStorageDays ??
        audit.ebStorageDays;
  }

  static int? _legacyBmkWeeks(AuditModel audit) {
    return audit.esEggBmkAge ??
        audit.chickBmkAge ??
        audit.haBmkAge ??
        audit.ebBmkAge;
  }

  static int? _legacyWeek(int? calculatedBmkAgeDays) {
    return BmkAgeCalculator.displayWeekForDays(calculatedBmkAgeDays);
  }
}
