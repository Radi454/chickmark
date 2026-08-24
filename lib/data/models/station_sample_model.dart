class StationSampleModel {
  static const String sectorDefault = 'station';
  static const String sectorEggQuality = 'egg_quality';
  static const String sectorChickQuality = 'chick_quality';
  static const String sectorChickWeights = 'chick_weights';
  static const String sectorHatchBreakout = 'hatch_breakout';
  static const String sectorSetterOptimizing = 'setter_optimizing';
  static const String sectorHatcherOptimizing = 'hatcher_optimizing';

  static const String sampleKindPooled = 'pooled';
  static const String sampleKindHouse = 'house';
  static const String sampleKindMachine = 'machine';
  static const String sampleKindBatch = 'batch';
  static const String sampleKindTray = 'tray';

  static const String sampleModePooled = 'pooled';
  static const String sampleModeComparison = 'comparison';

  static const String comparisonTypeBatch = 'batch_comparison';
  static const String comparisonTypeHouse = 'house_comparison';
  static const String comparisonTypeTray = 'tray_comparison';
  static const String comparisonTypeMachine = 'machine_comparison';
  static const String comparisonTypeProductionDate =
      'production_date_comparison';

  static const String sampleTypeDefault = 'default';
  static const String sampleTypeChickQualityHatchedBatch =
      'chicks_hatched_batch';
  static const String sampleTypeBreakoutFresh = 'breakout_fresh';
  static const String sampleTypeBreakoutCandled10d = 'breakout_candled_10d';
  static const String sampleTypeBreakoutResidue21d = 'breakout_residue_21d';

  static const String breakoutTypeFresh = 'freshEggBreakout';
  static const String breakoutTypeCandled10d = 'candledEggBreakout';
  static const String breakoutTypeResidue21d = 'residueHatchDay';

  final String id;
  final String auditSessionId;
  final String? legacyAuditId;
  final String stationType;
  final String sectorType;
  final String sampleKind;
  final String sampleMode;
  final String? comparisonType;
  final int sampleIndex;
  final String sampleLabel;
  final String sampleType;
  final String? breakoutType;
  final String? groupKey;
  final String? groupLabel;
  final String? batchNo;
  final String? houseNo;
  final String? houseLabel;
  final String? hatchNo;
  final DateTime? eggProductionDate;
  final DateTime? settingDate;
  final DateTime? hatchDate;
  final int? storageDays;
  final int? incubationDay;
  final String? setterNo;
  final String? hatcherNo;
  final int? calculatedBmkAgeDays;
  final String? benchmarkBreed;
  final int? benchmarkAgeDays;
  final String? benchmarkSource;
  final String? benchmarkSnapshotJson;
  final String? resultSummaryJson;
  final String? sampleKey;
  final String? qualityStatus;
  final String? qualityFlags;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  StationSampleModel({
    required this.id,
    required this.auditSessionId,
    this.legacyAuditId,
    required this.stationType,
    String? sectorType,
    String? sampleKind,
    String? sampleMode,
    this.comparisonType,
    required this.sampleIndex,
    String? sampleLabel,
    String? sampleType,
    this.breakoutType,
    this.groupKey,
    this.groupLabel,
    this.batchNo,
    this.houseNo,
    this.houseLabel,
    this.hatchNo,
    this.eggProductionDate,
    this.settingDate,
    this.hatchDate,
    this.storageDays,
    this.incubationDay,
    this.setterNo,
    this.hatcherNo,
    this.calculatedBmkAgeDays,
    this.benchmarkBreed,
    this.benchmarkAgeDays,
    this.benchmarkSource,
    this.benchmarkSnapshotJson,
    this.resultSummaryJson,
    this.sampleKey,
    this.qualityStatus,
    this.qualityFlags,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  }) : sectorType = normalizeSectorType(sectorType),
       sampleKind = normalizeSampleKind(sampleKind),
       sampleMode = normalizeSampleMode(sampleMode),
       sampleType = normalizeSampleType(sampleType),
       sampleLabel = sampleLabel ?? 'Sample $sampleIndex';

  factory StationSampleModel.fromMap(Map<String, dynamic> map) {
    return StationSampleModel(
      id: map['id'] as String,
      auditSessionId: map['auditSessionId'] as String,
      legacyAuditId: map['legacyAuditId'] as String?,
      stationType: map['stationType'] as String,
      sectorType: map['sectorType'] as String?,
      sampleKind: map['sampleKind'] as String?,
      sampleMode: map['sampleMode'] as String?,
      comparisonType: map['comparisonType'] as String?,
      sampleIndex: _asInt(map['sampleIndex']) ?? 1,
      sampleLabel: map['sampleLabel'] as String?,
      sampleType: map['sampleType'] as String?,
      breakoutType: map['breakoutType'] as String?,
      groupKey: map['groupKey'] as String?,
      groupLabel: map['groupLabel'] as String?,
      batchNo: map['batchNo'] as String?,
      houseNo: map['houseNo'] as String?,
      houseLabel: map['houseLabel'] as String?,
      hatchNo: map['hatchNo'] as String?,
      eggProductionDate: _parseDate(map['eggProductionDate']),
      settingDate: _parseDate(map['settingDate']),
      hatchDate: _parseDate(map['hatchDate']),
      storageDays: _asInt(map['storageDays']),
      incubationDay: _asInt(map['incubationDay']),
      setterNo: map['setterNo'] as String?,
      hatcherNo: map['hatcherNo'] as String?,
      calculatedBmkAgeDays: _asInt(map['calculatedBmkAgeDays']),
      benchmarkBreed: map['benchmarkBreed'] as String?,
      benchmarkAgeDays: _asInt(map['benchmarkAgeDays']),
      benchmarkSource: map['benchmarkSource'] as String?,
      benchmarkSnapshotJson: map['benchmarkSnapshotJson'] as String?,
      resultSummaryJson: map['resultSummaryJson'] as String?,
      sampleKey: map['sampleKey'] as String?,
      qualityStatus: map['qualityStatus'] as String?,
      qualityFlags: map['qualityFlags'] as String?,
      notes: map['notes'] as String?,
      createdAt: _parseDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(map['updatedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'auditSessionId': auditSessionId,
      'legacyAuditId': legacyAuditId,
      'stationType': stationType,
      'sectorType': sectorType,
      'sampleKind': sampleKind,
      'sampleMode': sampleMode,
      'comparisonType': comparisonType,
      'sampleIndex': sampleIndex,
      'sampleLabel': sampleLabel,
      'sampleType': sampleType,
      'breakoutType': breakoutType,
      'groupKey': groupKey,
      'groupLabel': groupLabel,
      'batchNo': batchNo,
      'houseNo': houseNo,
      'houseLabel': houseLabel,
      'hatchNo': hatchNo,
      'eggProductionDate': eggProductionDate?.toIso8601String(),
      'settingDate': settingDate?.toIso8601String(),
      'hatchDate': hatchDate?.toIso8601String(),
      'storageDays': storageDays,
      'incubationDay': incubationDay,
      'setterNo': setterNo,
      'hatcherNo': hatcherNo,
      'calculatedBmkAgeDays': calculatedBmkAgeDays,
      'benchmarkBreed': benchmarkBreed,
      'benchmarkAgeDays': benchmarkAgeDays,
      'benchmarkSource': benchmarkSource,
      'benchmarkSnapshotJson': benchmarkSnapshotJson,
      'resultSummaryJson': resultSummaryJson,
      'sampleKey': sampleKey,
      'qualityStatus': qualityStatus,
      'qualityFlags': qualityFlags,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  StationSampleModel copyWith({
    String? id,
    String? auditSessionId,
    String? legacyAuditId,
    String? stationType,
    String? sectorType,
    String? sampleKind,
    String? sampleMode,
    String? comparisonType,
    int? sampleIndex,
    String? sampleLabel,
    String? sampleType,
    String? breakoutType,
    String? groupKey,
    String? groupLabel,
    String? batchNo,
    String? houseNo,
    String? houseLabel,
    String? hatchNo,
    DateTime? eggProductionDate,
    DateTime? settingDate,
    DateTime? hatchDate,
    int? storageDays,
    int? incubationDay,
    String? setterNo,
    String? hatcherNo,
    int? calculatedBmkAgeDays,
    String? benchmarkBreed,
    int? benchmarkAgeDays,
    String? benchmarkSource,
    String? benchmarkSnapshotJson,
    String? resultSummaryJson,
    String? sampleKey,
    String? qualityStatus,
    String? qualityFlags,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StationSampleModel(
      id: id ?? this.id,
      auditSessionId: auditSessionId ?? this.auditSessionId,
      legacyAuditId: legacyAuditId ?? this.legacyAuditId,
      stationType: stationType ?? this.stationType,
      sectorType: sectorType ?? this.sectorType,
      sampleKind: sampleKind ?? this.sampleKind,
      sampleMode: sampleMode ?? this.sampleMode,
      comparisonType: comparisonType ?? this.comparisonType,
      sampleIndex: sampleIndex ?? this.sampleIndex,
      sampleLabel: sampleLabel ?? this.sampleLabel,
      sampleType: sampleType ?? this.sampleType,
      breakoutType: breakoutType ?? this.breakoutType,
      groupKey: groupKey ?? this.groupKey,
      groupLabel: groupLabel ?? this.groupLabel,
      batchNo: batchNo ?? this.batchNo,
      houseNo: houseNo ?? this.houseNo,
      houseLabel: houseLabel ?? this.houseLabel,
      hatchNo: hatchNo ?? this.hatchNo,
      eggProductionDate: eggProductionDate ?? this.eggProductionDate,
      settingDate: settingDate ?? this.settingDate,
      hatchDate: hatchDate ?? this.hatchDate,
      storageDays: storageDays ?? this.storageDays,
      incubationDay: incubationDay ?? this.incubationDay,
      setterNo: setterNo ?? this.setterNo,
      hatcherNo: hatcherNo ?? this.hatcherNo,
      calculatedBmkAgeDays: calculatedBmkAgeDays ?? this.calculatedBmkAgeDays,
      benchmarkBreed: benchmarkBreed ?? this.benchmarkBreed,
      benchmarkAgeDays: benchmarkAgeDays ?? this.benchmarkAgeDays,
      benchmarkSource: benchmarkSource ?? this.benchmarkSource,
      benchmarkSnapshotJson:
          benchmarkSnapshotJson ?? this.benchmarkSnapshotJson,
      resultSummaryJson: resultSummaryJson ?? this.resultSummaryJson,
      sampleKey: sampleKey ?? this.sampleKey,
      qualityStatus: qualityStatus ?? this.qualityStatus,
      qualityFlags: qualityFlags ?? this.qualityFlags,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String normalizeSampleMode(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == sampleModeComparison || normalized == 'compare') {
      return sampleModeComparison;
    }
    return sampleModePooled;
  }

  static String normalizeSectorType(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return sectorDefault;
    return normalized;
  }

  static String normalizeSampleKind(String? value) {
    final normalized = value?.trim().toLowerCase();
    return switch (normalized) {
      sampleKindHouse => sampleKindHouse,
      sampleKindMachine => sampleKindMachine,
      sampleKindBatch => sampleKindBatch,
      sampleKindTray => sampleKindTray,
      _ => sampleKindPooled,
    };
  }

  static String normalizeSampleType(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return sampleTypeDefault;
    return normalized;
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw.toString());
  }

  static int? _asInt(Object? raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    return int.tryParse(raw.toString());
  }
}
