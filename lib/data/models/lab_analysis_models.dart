enum LabTestType {
  elisa,
  pcr,
  hi,
  sensitivity;

  String get label {
    switch (this) {
      case LabTestType.elisa:
        return 'ELISA';
      case LabTestType.pcr:
        return 'PCR';
      case LabTestType.hi:
        return 'HI';
      case LabTestType.sensitivity:
        return 'Sensitivity';
    }
  }

  static LabTestType parse(Object? value) {
    final normalized = value?.toString().toLowerCase().trim();
    return LabTestType.values.firstWhere(
      (type) => type.name == normalized,
      orElse: () => LabTestType.elisa,
    );
  }
}

enum LabSeverity {
  normal,
  watch,
  alert;

  static LabSeverity parse(Object? value) {
    final normalized = value?.toString().toLowerCase().trim();
    return LabSeverity.values.firstWhere(
      (severity) => severity.name == normalized,
      orElse: () => LabSeverity.normal,
    );
  }
}

class LabAnalysisReportModel {
  final String id;
  final String customerId;
  final String flockId;
  final DateTime reportDate;
  final DateTime? receivedDate;
  final String labName;
  final String sampleType;
  final int? flockAgeWeeks;
  final String? title;
  final String? notes;
  final String? reportFileName;
  final String? reportFilePath;
  final String? reportFileRemotePath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  const LabAnalysisReportModel({
    required this.id,
    required this.customerId,
    required this.flockId,
    required this.reportDate,
    this.receivedDate,
    this.labName = '',
    this.sampleType = '',
    this.flockAgeWeeks,
    this.title,
    this.notes,
    this.reportFileName,
    this.reportFilePath,
    this.reportFileRemotePath,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  });

  factory LabAnalysisReportModel.fromMap(Map<String, dynamic> map) {
    return LabAnalysisReportModel(
      id: _asString(_value(map, 'id')) ?? '',
      customerId: _asString(_value(map, 'customerId')) ?? '',
      flockId: _asString(_value(map, 'flockId')) ?? '',
      reportDate: _asDate(_value(map, 'reportDate')) ?? DateTime.now(),
      receivedDate: _asDate(_value(map, 'receivedDate')),
      labName: _asString(_value(map, 'labName')) ?? '',
      sampleType: _asString(_value(map, 'sampleType')) ?? '',
      flockAgeWeeks: _asInt(_value(map, 'flockAgeWeeks')),
      title: _asString(_value(map, 'title')),
      notes: _asString(_value(map, 'notes')),
      reportFileName: _asString(_value(map, 'reportFileName')),
      reportFilePath: _asString(_value(map, 'reportFilePath')),
      reportFileRemotePath: _asString(_value(map, 'reportFileRemotePath')),
      createdAt: _asDate(_value(map, 'createdAt')) ?? DateTime.now(),
      updatedAt: _asDate(_value(map, 'updatedAt')) ?? DateTime.now(),
      syncStatus: _asString(_value(map, 'syncStatus')) ?? 'synced',
      dirtyAt: _asDate(_value(map, 'dirtyAt')),
      lastSyncedAt: _asDate(_value(map, 'lastSyncedAt')),
      syncError: _asString(_value(map, 'syncError')),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerId': customerId,
      'flockId': flockId,
      'reportDate': reportDate.toIso8601String(),
      'receivedDate': receivedDate?.toIso8601String(),
      'labName': labName,
      'sampleType': sampleType,
      'flockAgeWeeks': flockAgeWeeks,
      'title': title,
      'notes': notes,
      'reportFileName': reportFileName,
      'reportFilePath': reportFilePath,
      'reportFileRemotePath': reportFileRemotePath,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'syncStatus': syncStatus,
      'dirtyAt': dirtyAt?.toIso8601String(),
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'syncError': syncError,
    };
  }

  LabAnalysisReportModel copyWith({
    String? id,
    String? customerId,
    String? flockId,
    DateTime? reportDate,
    Object? receivedDate = _unset,
    String? labName,
    String? sampleType,
    Object? flockAgeWeeks = _unset,
    Object? title = _unset,
    Object? notes = _unset,
    Object? reportFileName = _unset,
    Object? reportFilePath = _unset,
    Object? reportFileRemotePath = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
    Object? dirtyAt = _unset,
    Object? lastSyncedAt = _unset,
    Object? syncError = _unset,
  }) {
    return LabAnalysisReportModel(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      flockId: flockId ?? this.flockId,
      reportDate: reportDate ?? this.reportDate,
      receivedDate: identical(receivedDate, _unset)
          ? this.receivedDate
          : receivedDate as DateTime?,
      labName: labName ?? this.labName,
      sampleType: sampleType ?? this.sampleType,
      flockAgeWeeks: identical(flockAgeWeeks, _unset)
          ? this.flockAgeWeeks
          : flockAgeWeeks as int?,
      title: identical(title, _unset) ? this.title : title as String?,
      notes: identical(notes, _unset) ? this.notes : notes as String?,
      reportFileName: identical(reportFileName, _unset)
          ? this.reportFileName
          : reportFileName as String?,
      reportFilePath: identical(reportFilePath, _unset)
          ? this.reportFilePath
          : reportFilePath as String?,
      reportFileRemotePath: identical(reportFileRemotePath, _unset)
          ? this.reportFileRemotePath
          : reportFileRemotePath as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      dirtyAt: identical(dirtyAt, _unset) ? this.dirtyAt : dirtyAt as DateTime?,
      lastSyncedAt: identical(lastSyncedAt, _unset)
          ? this.lastSyncedAt
          : lastSyncedAt as DateTime?,
      syncError: identical(syncError, _unset)
          ? this.syncError
          : syncError as String?,
    );
  }
}

class LabAnalysisGroupModel {
  final String id;
  final String reportId;
  final String customerId;
  final String flockId;
  final DateTime reportDate;
  final LabTestType testType;
  final String groupLabel;
  final String sampleScope;
  final String analyte;
  final String method;
  final String kitName;
  final String productCode;
  final String antigen;
  final int? sampleCount;
  final double? meanTiter;
  final double? minTiter;
  final double? maxTiter;
  final double? gmtTiter;
  final double? cvPct;
  final int? positiveCount;
  final int? negativeCount;
  final double? positivePct;
  final double? cutoffValue;
  final double? cutoffTiter;
  final double? gmLog2;
  final double? protectiveThresholdLog2;
  final int? protectiveCount;
  final double? protectivePct;
  final String interpretation;
  final LabSeverity severity;
  final String? notes;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  const LabAnalysisGroupModel({
    required this.id,
    required this.reportId,
    required this.customerId,
    required this.flockId,
    required this.reportDate,
    required this.testType,
    this.groupLabel = '',
    this.sampleScope = '',
    this.analyte = '',
    this.method = '',
    this.kitName = '',
    this.productCode = '',
    this.antigen = '',
    this.sampleCount,
    this.meanTiter,
    this.minTiter,
    this.maxTiter,
    this.gmtTiter,
    this.cvPct,
    this.positiveCount,
    this.negativeCount,
    this.positivePct,
    this.cutoffValue,
    this.cutoffTiter,
    this.gmLog2,
    this.protectiveThresholdLog2,
    this.protectiveCount,
    this.protectivePct,
    this.interpretation = '',
    this.severity = LabSeverity.normal,
    this.notes,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  });

  factory LabAnalysisGroupModel.fromMap(Map<String, dynamic> map) {
    return LabAnalysisGroupModel(
      id: _asString(_value(map, 'id')) ?? '',
      reportId: _asString(_value(map, 'reportId')) ?? '',
      customerId: _asString(_value(map, 'customerId')) ?? '',
      flockId: _asString(_value(map, 'flockId')) ?? '',
      reportDate: _asDate(_value(map, 'reportDate')) ?? DateTime.now(),
      testType: LabTestType.parse(_value(map, 'testType')),
      groupLabel: _asString(_value(map, 'groupLabel')) ?? '',
      sampleScope: _asString(_value(map, 'sampleScope')) ?? '',
      analyte: _asString(_value(map, 'analyte')) ?? '',
      method: _asString(_value(map, 'method')) ?? '',
      kitName: _asString(_value(map, 'kitName')) ?? '',
      productCode: _asString(_value(map, 'productCode')) ?? '',
      antigen: _asString(_value(map, 'antigen')) ?? '',
      sampleCount: _asInt(_value(map, 'sampleCount')),
      meanTiter: _asDouble(_value(map, 'meanTiter')),
      minTiter: _asDouble(_value(map, 'minTiter')),
      maxTiter: _asDouble(_value(map, 'maxTiter')),
      gmtTiter: _asDouble(_value(map, 'gmtTiter')),
      cvPct: _asDouble(_value(map, 'cvPct')),
      positiveCount: _asInt(_value(map, 'positiveCount')),
      negativeCount: _asInt(_value(map, 'negativeCount')),
      positivePct: _asDouble(_value(map, 'positivePct')),
      cutoffValue: _asDouble(_value(map, 'cutoffValue')),
      cutoffTiter: _asDouble(_value(map, 'cutoffTiter')),
      gmLog2: _asDouble(_value(map, 'gmLog2')),
      protectiveThresholdLog2: _asDouble(
        _value(map, 'protectiveThresholdLog2'),
      ),
      protectiveCount: _asInt(_value(map, 'protectiveCount')),
      protectivePct: _asDouble(_value(map, 'protectivePct')),
      interpretation: _asString(_value(map, 'interpretation')) ?? '',
      severity: LabSeverity.parse(_value(map, 'severity')),
      notes: _asString(_value(map, 'notes')),
      sortOrder: _asInt(_value(map, 'sortOrder')) ?? 0,
      createdAt: _asDate(_value(map, 'createdAt')) ?? DateTime.now(),
      updatedAt: _asDate(_value(map, 'updatedAt')) ?? DateTime.now(),
      syncStatus: _asString(_value(map, 'syncStatus')) ?? 'synced',
      dirtyAt: _asDate(_value(map, 'dirtyAt')),
      lastSyncedAt: _asDate(_value(map, 'lastSyncedAt')),
      syncError: _asString(_value(map, 'syncError')),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'reportId': reportId,
      'customerId': customerId,
      'flockId': flockId,
      'reportDate': reportDate.toIso8601String(),
      'testType': testType.name,
      'groupLabel': groupLabel,
      'sampleScope': sampleScope,
      'analyte': analyte,
      'method': method,
      'kitName': kitName,
      'productCode': productCode,
      'antigen': antigen,
      'sampleCount': sampleCount,
      'meanTiter': meanTiter,
      'minTiter': minTiter,
      'maxTiter': maxTiter,
      'gmtTiter': gmtTiter,
      'cvPct': cvPct,
      'positiveCount': positiveCount,
      'negativeCount': negativeCount,
      'positivePct': positivePct,
      'cutoffValue': cutoffValue,
      'cutoffTiter': cutoffTiter,
      'gmLog2': gmLog2,
      'protectiveThresholdLog2': protectiveThresholdLog2,
      'protectiveCount': protectiveCount,
      'protectivePct': protectivePct,
      'interpretation': interpretation,
      'severity': severity.name,
      'notes': notes,
      'sortOrder': sortOrder,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'syncStatus': syncStatus,
      'dirtyAt': dirtyAt?.toIso8601String(),
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'syncError': syncError,
    };
  }

  LabAnalysisGroupModel copyWith({
    String? id,
    String? reportId,
    String? customerId,
    String? flockId,
    DateTime? reportDate,
    LabTestType? testType,
    String? groupLabel,
    String? sampleScope,
    String? analyte,
    String? method,
    String? kitName,
    String? productCode,
    String? antigen,
    Object? sampleCount = _unset,
    Object? meanTiter = _unset,
    Object? minTiter = _unset,
    Object? maxTiter = _unset,
    Object? gmtTiter = _unset,
    Object? cvPct = _unset,
    Object? positiveCount = _unset,
    Object? negativeCount = _unset,
    Object? positivePct = _unset,
    Object? cutoffValue = _unset,
    Object? cutoffTiter = _unset,
    Object? gmLog2 = _unset,
    Object? protectiveThresholdLog2 = _unset,
    Object? protectiveCount = _unset,
    Object? protectivePct = _unset,
    String? interpretation,
    LabSeverity? severity,
    Object? notes = _unset,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
    Object? dirtyAt = _unset,
    Object? lastSyncedAt = _unset,
    Object? syncError = _unset,
  }) {
    return LabAnalysisGroupModel(
      id: id ?? this.id,
      reportId: reportId ?? this.reportId,
      customerId: customerId ?? this.customerId,
      flockId: flockId ?? this.flockId,
      reportDate: reportDate ?? this.reportDate,
      testType: testType ?? this.testType,
      groupLabel: groupLabel ?? this.groupLabel,
      sampleScope: sampleScope ?? this.sampleScope,
      analyte: analyte ?? this.analyte,
      method: method ?? this.method,
      kitName: kitName ?? this.kitName,
      productCode: productCode ?? this.productCode,
      antigen: antigen ?? this.antigen,
      sampleCount: identical(sampleCount, _unset)
          ? this.sampleCount
          : sampleCount as int?,
      meanTiter: identical(meanTiter, _unset)
          ? this.meanTiter
          : meanTiter as double?,
      minTiter: identical(minTiter, _unset)
          ? this.minTiter
          : minTiter as double?,
      maxTiter: identical(maxTiter, _unset)
          ? this.maxTiter
          : maxTiter as double?,
      gmtTiter: identical(gmtTiter, _unset)
          ? this.gmtTiter
          : gmtTiter as double?,
      cvPct: identical(cvPct, _unset) ? this.cvPct : cvPct as double?,
      positiveCount: identical(positiveCount, _unset)
          ? this.positiveCount
          : positiveCount as int?,
      negativeCount: identical(negativeCount, _unset)
          ? this.negativeCount
          : negativeCount as int?,
      positivePct: identical(positivePct, _unset)
          ? this.positivePct
          : positivePct as double?,
      cutoffValue: identical(cutoffValue, _unset)
          ? this.cutoffValue
          : cutoffValue as double?,
      cutoffTiter: identical(cutoffTiter, _unset)
          ? this.cutoffTiter
          : cutoffTiter as double?,
      gmLog2: identical(gmLog2, _unset) ? this.gmLog2 : gmLog2 as double?,
      protectiveThresholdLog2: identical(protectiveThresholdLog2, _unset)
          ? this.protectiveThresholdLog2
          : protectiveThresholdLog2 as double?,
      protectiveCount: identical(protectiveCount, _unset)
          ? this.protectiveCount
          : protectiveCount as int?,
      protectivePct: identical(protectivePct, _unset)
          ? this.protectivePct
          : protectivePct as double?,
      interpretation: interpretation ?? this.interpretation,
      severity: severity ?? this.severity,
      notes: identical(notes, _unset) ? this.notes : notes as String?,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      dirtyAt: identical(dirtyAt, _unset) ? this.dirtyAt : dirtyAt as DateTime?,
      lastSyncedAt: identical(lastSyncedAt, _unset)
          ? this.lastSyncedAt
          : lastSyncedAt as DateTime?,
      syncError: identical(syncError, _unset)
          ? this.syncError
          : syncError as String?,
    );
  }
}

class LabAnalysisRowModel {
  final String id;
  final String groupId;
  final String reportId;
  final String customerId;
  final String flockId;
  final DateTime reportDate;
  final LabTestType testType;
  final String rowLabel;
  final String analyte;
  final String result;
  final String resultCategory;
  final double? numericValue;
  final String unit;
  final double? ctValue;
  final double? odValue;
  final double? spRatio;
  final double? titer;
  final int? titerGroup;
  final int? hiLog2;
  final int? count;
  final String antibiotic;
  final String sensitivityCategory;
  final String interpretation;
  final LabSeverity severity;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  const LabAnalysisRowModel({
    required this.id,
    required this.groupId,
    required this.reportId,
    required this.customerId,
    required this.flockId,
    required this.reportDate,
    required this.testType,
    this.rowLabel = '',
    this.analyte = '',
    this.result = '',
    this.resultCategory = '',
    this.numericValue,
    this.unit = '',
    this.ctValue,
    this.odValue,
    this.spRatio,
    this.titer,
    this.titerGroup,
    this.hiLog2,
    this.count,
    this.antibiotic = '',
    this.sensitivityCategory = '',
    this.interpretation = '',
    this.severity = LabSeverity.normal,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  });

  factory LabAnalysisRowModel.fromMap(Map<String, dynamic> map) {
    return LabAnalysisRowModel(
      id: _asString(_value(map, 'id')) ?? '',
      groupId: _asString(_value(map, 'groupId')) ?? '',
      reportId: _asString(_value(map, 'reportId')) ?? '',
      customerId: _asString(_value(map, 'customerId')) ?? '',
      flockId: _asString(_value(map, 'flockId')) ?? '',
      reportDate: _asDate(_value(map, 'reportDate')) ?? DateTime.now(),
      testType: LabTestType.parse(_value(map, 'testType')),
      rowLabel: _asString(_value(map, 'rowLabel')) ?? '',
      analyte: _asString(_value(map, 'analyte')) ?? '',
      result: _asString(_value(map, 'result')) ?? '',
      resultCategory: _asString(_value(map, 'resultCategory')) ?? '',
      numericValue: _asDouble(_value(map, 'numericValue')),
      unit: _asString(_value(map, 'unit')) ?? '',
      ctValue: _asDouble(_value(map, 'ctValue')),
      odValue: _asDouble(_value(map, 'odValue')),
      spRatio: _asDouble(_value(map, 'spRatio')),
      titer: _asDouble(_value(map, 'titer')),
      titerGroup: _asInt(_value(map, 'titerGroup')),
      hiLog2: _asInt(_value(map, 'hiLog2')),
      count: _asInt(_value(map, 'count')),
      antibiotic: _asString(_value(map, 'antibiotic')) ?? '',
      sensitivityCategory: _asString(_value(map, 'sensitivityCategory')) ?? '',
      interpretation: _asString(_value(map, 'interpretation')) ?? '',
      severity: LabSeverity.parse(_value(map, 'severity')),
      sortOrder: _asInt(_value(map, 'sortOrder')) ?? 0,
      createdAt: _asDate(_value(map, 'createdAt')) ?? DateTime.now(),
      updatedAt: _asDate(_value(map, 'updatedAt')) ?? DateTime.now(),
      syncStatus: _asString(_value(map, 'syncStatus')) ?? 'synced',
      dirtyAt: _asDate(_value(map, 'dirtyAt')),
      lastSyncedAt: _asDate(_value(map, 'lastSyncedAt')),
      syncError: _asString(_value(map, 'syncError')),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'groupId': groupId,
      'reportId': reportId,
      'customerId': customerId,
      'flockId': flockId,
      'reportDate': reportDate.toIso8601String(),
      'testType': testType.name,
      'rowLabel': rowLabel,
      'analyte': analyte,
      'result': result,
      'resultCategory': resultCategory,
      'numericValue': numericValue,
      'unit': unit,
      'ctValue': ctValue,
      'odValue': odValue,
      'spRatio': spRatio,
      'titer': titer,
      'titerGroup': titerGroup,
      'hiLog2': hiLog2,
      'count': count,
      'antibiotic': antibiotic,
      'sensitivityCategory': sensitivityCategory,
      'interpretation': interpretation,
      'severity': severity.name,
      'sortOrder': sortOrder,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'syncStatus': syncStatus,
      'dirtyAt': dirtyAt?.toIso8601String(),
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'syncError': syncError,
    };
  }

  LabAnalysisRowModel copyWith({
    String? id,
    String? groupId,
    String? reportId,
    String? customerId,
    String? flockId,
    DateTime? reportDate,
    LabTestType? testType,
    String? rowLabel,
    String? analyte,
    String? result,
    String? resultCategory,
    Object? numericValue = _unset,
    String? unit,
    Object? ctValue = _unset,
    Object? odValue = _unset,
    Object? spRatio = _unset,
    Object? titer = _unset,
    Object? titerGroup = _unset,
    Object? hiLog2 = _unset,
    Object? count = _unset,
    String? antibiotic,
    String? sensitivityCategory,
    String? interpretation,
    LabSeverity? severity,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
    Object? dirtyAt = _unset,
    Object? lastSyncedAt = _unset,
    Object? syncError = _unset,
  }) {
    return LabAnalysisRowModel(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      reportId: reportId ?? this.reportId,
      customerId: customerId ?? this.customerId,
      flockId: flockId ?? this.flockId,
      reportDate: reportDate ?? this.reportDate,
      testType: testType ?? this.testType,
      rowLabel: rowLabel ?? this.rowLabel,
      analyte: analyte ?? this.analyte,
      result: result ?? this.result,
      resultCategory: resultCategory ?? this.resultCategory,
      numericValue: identical(numericValue, _unset)
          ? this.numericValue
          : numericValue as double?,
      unit: unit ?? this.unit,
      ctValue: identical(ctValue, _unset) ? this.ctValue : ctValue as double?,
      odValue: identical(odValue, _unset) ? this.odValue : odValue as double?,
      spRatio: identical(spRatio, _unset) ? this.spRatio : spRatio as double?,
      titer: identical(titer, _unset) ? this.titer : titer as double?,
      titerGroup: identical(titerGroup, _unset)
          ? this.titerGroup
          : titerGroup as int?,
      hiLog2: identical(hiLog2, _unset) ? this.hiLog2 : hiLog2 as int?,
      count: identical(count, _unset) ? this.count : count as int?,
      antibiotic: antibiotic ?? this.antibiotic,
      sensitivityCategory: sensitivityCategory ?? this.sensitivityCategory,
      interpretation: interpretation ?? this.interpretation,
      severity: severity ?? this.severity,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      dirtyAt: identical(dirtyAt, _unset) ? this.dirtyAt : dirtyAt as DateTime?,
      lastSyncedAt: identical(lastSyncedAt, _unset)
          ? this.lastSyncedAt
          : lastSyncedAt as DateTime?,
      syncError: identical(syncError, _unset)
          ? this.syncError
          : syncError as String?,
    );
  }
}

class LabAnalysisDashboardSummary {
  final LabAnalysisReportModel report;
  final LabAnalysisGroupModel group;
  final List<LabAnalysisRowModel> rows;

  const LabAnalysisDashboardSummary({
    required this.report,
    required this.group,
    required this.rows,
  });

  int get alertCount =>
      rows.where((row) => row.severity == LabSeverity.alert).length +
      (group.severity == LabSeverity.alert ? 1 : 0);

  int get watchCount =>
      rows.where((row) => row.severity == LabSeverity.watch).length +
      (group.severity == LabSeverity.watch ? 1 : 0);
}

class LabAnalysisBatch {
  final LabAnalysisReportModel report;
  final List<LabAnalysisGroupModel> groups;
  final Map<String, List<LabAnalysisRowModel>> rowsByGroupId;

  const LabAnalysisBatch({
    required this.report,
    required this.groups,
    required this.rowsByGroupId,
  });
}

class LabInterpretationRules {
  LabInterpretationRules._();

  static ({String message, LabSeverity severity}) interpretGroup(
    LabAnalysisGroupModel group,
    List<LabAnalysisRowModel> rows,
  ) {
    switch (group.testType) {
      case LabTestType.elisa:
        return _interpretElisa(group);
      case LabTestType.pcr:
        return _interpretPcrGroup(rows);
      case LabTestType.hi:
        return _interpretHi(group);
      case LabTestType.sensitivity:
        return _interpretSensitivity(rows);
    }
  }

  static ({String message, LabSeverity severity}) interpretRow(
    LabAnalysisRowModel row,
  ) {
    switch (row.testType) {
      case LabTestType.pcr:
        return _interpretPcrRow(row);
      case LabTestType.sensitivity:
        return _interpretSensitivityRow(row);
      case LabTestType.elisa:
        return _interpretElisaRow(row);
      case LabTestType.hi:
        return _interpretHiRow(row);
    }
  }

  static double protectiveThresholdForAntigen(String antigen) {
    final value = antigen.toLowerCase();
    if (value.contains('h9')) return 6;
    if (value.contains('h5')) return 4;
    if (value.contains('nd') || value.contains('lasota')) return 4;
    return 4;
  }

  static ({String message, LabSeverity severity}) _interpretElisa(
    LabAnalysisGroupModel group,
  ) {
    final cv = group.cvPct;
    final positivePct = group.positivePct;
    if (cv != null && cv > 60) {
      return (
        message:
            'High ELISA CV%: antibody response is non-uniform; review vaccination/exposure history.',
        severity: LabSeverity.alert,
      );
    }
    if (cv != null && cv > 40) {
      return (
        message:
            'Moderate ELISA CV%: response uniformity needs follow-up against this flock baseline.',
        severity: LabSeverity.watch,
      );
    }
    if (positivePct != null && positivePct > 0) {
      return (
        message:
            'Seropositive ELISA result: interpret with vaccination history and confirm active infection with PCR/RSA when needed.',
        severity: LabSeverity.watch,
      );
    }
    return (
      message: 'ELISA summary is within the saved interpretation guardrails.',
      severity: LabSeverity.normal,
    );
  }

  static ({String message, LabSeverity severity}) _interpretElisaRow(
    LabAnalysisRowModel row,
  ) {
    final category = row.resultCategory.toLowerCase();
    if (category == 'positive' || category == 'p' || row.result == '+VE') {
      return (message: 'ELISA positive sample.', severity: LabSeverity.watch);
    }
    return (message: 'ELISA negative sample.', severity: LabSeverity.normal);
  }

  static ({String message, LabSeverity severity}) _interpretPcrGroup(
    List<LabAnalysisRowModel> rows,
  ) {
    final positive = rows.where(_isPositivePcr).toList();
    if (positive.isEmpty) {
      return (
        message: 'PCR targets were not detected in the saved rows.',
        severity: LabSeverity.normal,
      );
    }
    final lowCt = positive.any((row) => (row.ctValue ?? 99) <= 30);
    return (
      message: lowCt
          ? 'PCR positive with low Ct signal; prioritize this flock/house for follow-up.'
          : 'PCR positive; Ct should be interpreted against lab cutoffs and clinical context.',
      severity: LabSeverity.alert,
    );
  }

  static ({String message, LabSeverity severity}) _interpretPcrRow(
    LabAnalysisRowModel row,
  ) {
    if (!_isPositivePcr(row)) {
      return (message: 'Target not detected.', severity: LabSeverity.normal);
    }
    final ct = row.ctValue;
    if (ct == null) {
      return (message: 'PCR target detected.', severity: LabSeverity.alert);
    }
    if (ct <= 30) {
      return (
        message: 'PCR positive with low Ct signal.',
        severity: LabSeverity.alert,
      );
    }
    if (ct <= 35) {
      return (
        message: 'PCR positive; compare with lab cutoff and history.',
        severity: LabSeverity.alert,
      );
    }
    return (
      message:
          'Low-level PCR positive; confirm with lab cutoff and repeat/context.',
      severity: LabSeverity.watch,
    );
  }

  static ({String message, LabSeverity severity}) _interpretHi(
    LabAnalysisGroupModel group,
  ) {
    final protectivePct = group.protectivePct;
    final threshold = group.protectiveThresholdLog2 ?? 4;
    final gm = group.gmLog2;
    if (gm != null && gm < threshold) {
      return (
        message: 'HI GMT is below the saved protective threshold.',
        severity: LabSeverity.alert,
      );
    }
    if (protectivePct != null && protectivePct < 70) {
      return (
        message: 'HI protection distribution is low for this antigen.',
        severity: LabSeverity.alert,
      );
    }
    if (protectivePct != null && protectivePct < 85) {
      return (
        message: 'HI protection distribution is borderline; monitor trend.',
        severity: LabSeverity.watch,
      );
    }
    return (
      message: 'HI distribution is protective by the saved threshold.',
      severity: LabSeverity.normal,
    );
  }

  static ({String message, LabSeverity severity}) _interpretHiRow(
    LabAnalysisRowModel row,
  ) {
    return (
      message: 'HI distribution bin saved.',
      severity: LabSeverity.normal,
    );
  }

  static ({String message, LabSeverity severity}) _interpretSensitivity(
    List<LabAnalysisRowModel> rows,
  ) {
    final sensitive = rows.where((row) {
      return _normalizedSensitivity(row.sensitivityCategory) == 's';
    }).length;
    final resistant = rows.where((row) {
      return _normalizedSensitivity(row.sensitivityCategory) == 'r';
    }).length;
    if (sensitive == 0 && rows.isNotEmpty) {
      return (
        message: 'No sensitive antibiotic was recorded for this sample.',
        severity: LabSeverity.alert,
      );
    }
    if (resistant > sensitive) {
      return (
        message: 'Resistance dominates this sensitivity panel.',
        severity: LabSeverity.watch,
      );
    }
    return (
      message: 'Sensitivity panel has at least one sensitive option recorded.',
      severity: LabSeverity.normal,
    );
  }

  static ({String message, LabSeverity severity}) _interpretSensitivityRow(
    LabAnalysisRowModel row,
  ) {
    switch (_normalizedSensitivity(row.sensitivityCategory)) {
      case 'r':
        return (
          message: 'Resistant: high likelihood of treatment failure.',
          severity: LabSeverity.alert,
        );
      case 'i':
        return (
          message: 'Intermediate: needs veterinary dosing/context.',
          severity: LabSeverity.watch,
        );
      default:
        return (
          message: 'Sensitive: recorded as an in-vitro option.',
          severity: LabSeverity.normal,
        );
    }
  }

  static bool _isPositivePcr(LabAnalysisRowModel row) {
    final category = row.resultCategory.toLowerCase();
    final result = row.result.toLowerCase();
    return category == 'positive' ||
        category == '+ve' ||
        result == '+ve' ||
        result == 'positive' ||
        result == 'detected';
  }

  static String _normalizedSensitivity(String value) {
    final normalized = value.toLowerCase().trim();
    if (normalized.startsWith('r')) return 'r';
    if (normalized.startsWith('i')) return 'i';
    return 's';
  }
}

const _unset = Object();

Object? _value(Map<String, dynamic> map, String key) {
  if (map.containsKey(key)) return map[key];
  final snake = _snakeCase(key);
  if (map.containsKey(snake)) return map[snake];
  return null;
}

String _snakeCase(String key) {
  final buffer = StringBuffer();
  for (var i = 0; i < key.length; i++) {
    final char = key[i];
    final isUpper = char.toUpperCase() == char && char.toLowerCase() != char;
    if (isUpper && i > 0) buffer.write('_');
    buffer.write(char.toLowerCase());
  }
  return buffer.toString();
}

String? _asString(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return text;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _asDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse((value?.toString() ?? '').replaceAll(',', ''));
}

DateTime? _asDate(Object? value) {
  if (value is DateTime) return value;
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
