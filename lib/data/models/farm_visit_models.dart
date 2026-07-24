import 'dart:convert';

enum FarmVisitStatus {
  planned('planned'),
  inProgress('in_progress'),
  completed('completed'),
  cancelled('cancelled');

  const FarmVisitStatus(this.storageKey);
  final String storageKey;

  static FarmVisitStatus fromStorage(Object? value) => values.firstWhere(
    (item) => item.storageKey == value?.toString(),
    orElse: () => planned,
  );
}

enum InvestigationOrigin {
  suggested('suggested'),
  manual('manual');

  const InvestigationOrigin(this.storageKey);
  final String storageKey;

  static InvestigationOrigin fromStorage(Object? value) => values.firstWhere(
    (item) => item.storageKey == value?.toString(),
    orElse: () => suggested,
  );
}

enum InvestigationStatus {
  pending('pending'),
  inProgress('in_progress'),
  completed('completed'),
  notApplicable('not_applicable');

  const InvestigationStatus(this.storageKey);
  final String storageKey;

  static InvestigationStatus fromStorage(Object? value) => values.firstWhere(
    (item) => item.storageKey == value?.toString(),
    orElse: () => pending,
  );
}

enum CauseAssessmentStatus {
  suspected('suspected'),
  probable('probable'),
  confirmed('confirmed'),
  ruledOut('ruled_out');

  const CauseAssessmentStatus(this.storageKey);
  final String storageKey;

  static CauseAssessmentStatus fromStorage(Object? value) => values.firstWhere(
    (item) => item.storageKey == value?.toString(),
    orElse: () => suspected,
  );
}

class VisitBriefingConcern {
  const VisitBriefingConcern({
    required this.concernId,
    required this.metricKey,
    required this.actualValue,
    required this.evidenceSummary,
    this.baselineValue,
    this.targetValue,
    this.investigationKeys = const [],
  });

  final String concernId;
  final String metricKey;
  final double actualValue;
  final double? baselineValue;
  final double? targetValue;
  final String evidenceSummary;
  final List<String> investigationKeys;

  Map<String, Object?> toJson() => {
    'concernId': concernId,
    'metricKey': metricKey,
    'actualValue': actualValue,
    'baselineValue': baselineValue,
    'targetValue': targetValue,
    'evidenceSummary': evidenceSummary,
    'investigationKeys': investigationKeys,
  };
}

class VisitBriefingSnapshot {
  const VisitBriefingSnapshot({
    required this.generatedAtIso,
    required this.concernIds,
    required this.evidence,
    required this.investigations,
    this.targetVersion,
    this.ruleVersion,
  });

  final String generatedAtIso;
  final List<String> concernIds;
  final Map<String, Object?> evidence;
  final List<String> investigations;
  final String? targetVersion;
  final String? ruleVersion;

  Map<String, Object?> toJson() => {
    'generatedAtIso': generatedAtIso,
    'concernIds': concernIds,
    'evidence': evidence,
    'investigations': investigations,
    'targetVersion': targetVersion,
    'ruleVersion': ruleVersion,
  };

  factory VisitBriefingSnapshot.fromJson(Map<String, Object?> json) {
    return VisitBriefingSnapshot(
      generatedAtIso: json['generatedAtIso']?.toString() ?? '',
      concernIds: _stringList(json['concernIds']),
      evidence: _objectMap(json['evidence']),
      investigations: _stringList(json['investigations']),
      targetVersion: json['targetVersion'] as String?,
      ruleVersion: json['ruleVersion'] as String?,
    );
  }

  factory VisitBriefingSnapshot.fromEncodedJson(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException('Visit briefing must be a JSON object');
    }
    return VisitBriefingSnapshot.fromJson(Map<String, Object?>.from(decoded));
  }
}

class FarmVisitSession {
  const FarmVisitSession({
    required this.id,
    required this.customerId,
    required this.farmId,
    required this.visitDate,
    required this.briefing,
    required this.status,
    this.flockId,
    this.assignedAuditorId,
    this.startedAt,
    this.completedAt,
    this.notes,
    this.createdBy,
    this.houseIds = const [],
    this.investigations = const [],
    this.findings = const [],
    this.causeAssessments = const [],
  });

  final String id;
  final String customerId;
  final String farmId;
  final String? flockId;
  final DateTime visitDate;
  final VisitBriefingSnapshot briefing;
  final FarmVisitStatus status;
  final String? assignedAuditorId;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? notes;
  final String? createdBy;
  final List<String> houseIds;
  final List<VisitInvestigation> investigations;
  final List<VisitFinding> findings;
  final List<CauseAssessment> causeAssessments;

  factory FarmVisitSession.fromMap(
    Map<String, Object?> map, {
    List<String> houseIds = const [],
    List<VisitInvestigation> investigations = const [],
    List<VisitFinding> findings = const [],
    List<CauseAssessment> causeAssessments = const [],
  }) {
    return FarmVisitSession(
      id: map['id']! as String,
      customerId: map['customerId']! as String,
      farmId: map['farmId']! as String,
      flockId: map['flockId'] as String?,
      visitDate: DateTime.parse(map['visitDate']! as String),
      briefing: VisitBriefingSnapshot.fromEncodedJson(
        map['briefingSnapshotJson']! as String,
      ),
      status: FarmVisitStatus.fromStorage(map['status']),
      assignedAuditorId: map['assignedAuditorId'] as String?,
      startedAt: _date(map['startedAt']),
      completedAt: _date(map['completedAt']),
      notes: map['notes'] as String?,
      createdBy: map['createdBy'] as String?,
      houseIds: houseIds,
      investigations: investigations,
      findings: findings,
      causeAssessments: causeAssessments,
    );
  }
}

class VisitInvestigationDraft {
  const VisitInvestigationDraft({
    required this.investigationType,
    required this.instruction,
    this.visitId,
    this.sourceConcernId,
    this.houseId,
    this.location,
    this.origin = InvestigationOrigin.suggested,
  });

  final String? visitId;
  final String? sourceConcernId;
  final String? houseId;
  final String? location;
  final InvestigationOrigin origin;
  final String investigationType;
  final String instruction;
}

class VisitInvestigation {
  const VisitInvestigation({
    required this.id,
    required this.visitId,
    required this.origin,
    required this.investigationType,
    required this.instruction,
    required this.status,
    this.sourceConcernId,
    this.houseId,
    this.location,
    this.resultSummary,
  });

  final String id;
  final String visitId;
  final String? sourceConcernId;
  final String? houseId;
  final String? location;
  final InvestigationOrigin origin;
  final String investigationType;
  final String instruction;
  final InvestigationStatus status;
  final String? resultSummary;

  factory VisitInvestigation.fromMap(Map<String, Object?> map) {
    return VisitInvestigation(
      id: map['id']! as String,
      visitId: map['visitId']! as String,
      sourceConcernId: map['sourceConcernId'] as String?,
      houseId: map['houseId'] as String?,
      location: map['location'] as String?,
      origin: InvestigationOrigin.fromStorage(map['origin']),
      investigationType: map['investigationType']! as String,
      instruction: map['instruction']! as String,
      status: InvestigationStatus.fromStorage(map['status']),
      resultSummary: map['resultSummary'] as String?,
    );
  }
}

class VisitFindingDraft {
  const VisitFindingDraft({
    required this.visitId,
    required this.findingType,
    this.investigationId,
    this.severity,
    this.measuredValue,
    this.unit,
    this.observation = const {},
    this.houseId,
    this.location,
    this.staffExplanation,
    this.attachmentRefs = const [],
    this.authoredBy,
  });

  final String visitId;
  final String? investigationId;
  final String findingType;
  final String? severity;
  final double? measuredValue;
  final String? unit;
  final Map<String, Object?> observation;
  final String? houseId;
  final String? location;
  final String? staffExplanation;
  final List<String> attachmentRefs;
  final String? authoredBy;
}

class VisitFinding {
  const VisitFinding({
    required this.id,
    required this.visitId,
    required this.findingType,
    this.investigationId,
    this.severity,
    this.measuredValue,
    this.unit,
    this.observation = const {},
    this.houseId,
    this.location,
    this.staffExplanation,
    this.attachmentRefs = const [],
    this.authoredBy,
  });

  final String id;
  final String visitId;
  final String? investigationId;
  final String findingType;
  final String? severity;
  final double? measuredValue;
  final String? unit;
  final Map<String, Object?> observation;
  final String? houseId;
  final String? location;
  final String? staffExplanation;
  final List<String> attachmentRefs;
  final String? authoredBy;

  factory VisitFinding.fromMap(Map<String, Object?> map) {
    return VisitFinding(
      id: map['id']! as String,
      visitId: map['visitId']! as String,
      investigationId: map['investigationId'] as String?,
      findingType: map['findingType']! as String,
      severity: map['severity'] as String?,
      measuredValue: _number(map['measuredValue']),
      unit: map['unit'] as String?,
      observation: _decodeObjectMap(map['observationJson']),
      houseId: map['houseId'] as String?,
      location: map['location'] as String?,
      staffExplanation: map['staffExplanation'] as String?,
      attachmentRefs: _decodeStringList(map['attachmentRefsJson']),
      authoredBy: map['authoredBy'] as String?,
    );
  }
}

class CauseAssessmentDraft {
  const CauseAssessmentDraft({
    required this.visitId,
    required this.concernId,
    required this.probableCause,
    this.alternativeCauses = const [],
    this.supportingEvidenceIds = const [],
    this.conflictingEvidenceIds = const [],
    this.status = CauseAssessmentStatus.suspected,
    this.authoredBy,
  });

  final String visitId;
  final String concernId;
  final String probableCause;
  final List<String> alternativeCauses;
  final List<String> supportingEvidenceIds;
  final List<String> conflictingEvidenceIds;
  final CauseAssessmentStatus status;
  final String? authoredBy;
}

class CauseAssessment {
  const CauseAssessment({
    required this.id,
    required this.visitId,
    required this.concernId,
    required this.probableCause,
    required this.status,
    this.alternativeCauses = const [],
    this.supportingEvidenceIds = const [],
    this.conflictingEvidenceIds = const [],
    this.authoredBy,
  });

  final String id;
  final String visitId;
  final String concernId;
  final String probableCause;
  final List<String> alternativeCauses;
  final List<String> supportingEvidenceIds;
  final List<String> conflictingEvidenceIds;
  final CauseAssessmentStatus status;
  final String? authoredBy;

  factory CauseAssessment.fromMap(Map<String, Object?> map) {
    return CauseAssessment(
      id: map['id']! as String,
      visitId: map['visitId']! as String,
      concernId: map['concernId']! as String,
      probableCause: map['probableCause']! as String,
      alternativeCauses: _decodeStringList(map['alternativeCausesJson']),
      supportingEvidenceIds: _decodeStringList(map['supportingEvidenceJson']),
      conflictingEvidenceIds: _decodeStringList(map['conflictingEvidenceJson']),
      status: CauseAssessmentStatus.fromStorage(map['status']),
      authoredBy: map['authoredBy'] as String?,
    );
  }
}

Map<String, Object?> _objectMap(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const {};

List<String> _stringList(Object? value) =>
    value is List ? value.map((item) => item.toString()).toList() : const [];

Map<String, Object?> _decodeObjectMap(Object? value) {
  if (value == null || value.toString().isEmpty) return const {};
  final decoded = jsonDecode(value.toString());
  return _objectMap(decoded);
}

List<String> _decodeStringList(Object? value) {
  if (value == null || value.toString().isEmpty) return const [];
  return _stringList(jsonDecode(value.toString()));
}

double? _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('${value ?? ''}');

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());
