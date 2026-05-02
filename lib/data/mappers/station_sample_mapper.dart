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
      sampleMode: sampleMode,
      comparisonType: _comparisonType(stationType, sampleMode),
      sampleIndex: audit.hatchNumber,
      sampleLabel: _sampleLabel(stationType, audit.hatchNumber),
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
      patch['esEggStorageDays'] = sample.storageDays;
      patch['chickStorageDays'] = sample.storageDays;
      patch['haStorageDays'] = sample.storageDays;
      patch['ebStorageDays'] = sample.storageDays;
    }
    if (sample.incubationDay != null) {
      patch['soIncubationAge'] = sample.incubationDay;
      patch['hoIncubationAge'] = sample.incubationDay;
    }
    final legacyWeek = _legacyWeek(sample.calculatedBmkAgeDays);
    if (legacyWeek != null) {
      patch['esEggBmkAge'] = legacyWeek;
      patch['chickBmkAge'] = legacyWeek;
      patch['haBmkAge'] = legacyWeek;
      patch['ebBmkAge'] = legacyWeek;
    }
    if (sample.breakoutType != null) {
      patch['ebBreakoutType'] = sample.breakoutType;
    }
    return patch;
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
        return StationSampleModel.comparisonTypeMachine;
      case 'chicks':
      case 'hatch_analysis_egg_breakouts':
        return StationSampleModel.comparisonTypeBatch;
      default:
        return null;
    }
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

  static String _sampleLabel(String stationType, int sampleIndex) {
    if (stationType == 'egg') return 'H$sampleIndex';
    return 'Sample $sampleIndex';
  }

  static String? _groupLabel(String stationType, String? groupKey) {
    if (groupKey == null || groupKey.isEmpty) return null;
    if (stationType == 'egg') return 'House comparison';
    return 'Comparison';
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
    if (calculatedBmkAgeDays == null) return null;
    return (calculatedBmkAgeDays / 7.0).ceil();
  }
}
