enum AgentSubmissionStatus {
  received('received'),
  processing('processing'),
  waitingForStaffAnswer('waiting_for_staff_answer'),
  draftReady('draft_ready'),
  needsAdminReview('needs_admin_review'),
  partiallyApproved('partially_approved'),
  approved('approved'),
  rejected('rejected'),
  failed('failed');

  const AgentSubmissionStatus(this.storageKey);

  final String storageKey;

  static AgentSubmissionStatus fromStorage(Object? value) {
    return values.firstWhere(
      (status) => status.storageKey == value?.toString(),
      orElse: () => received,
    );
  }
}

enum HatcheryDraftRowStatus {
  pending('pending'),
  needsReview('needs_review'),
  approved('approved'),
  rejected('rejected');

  const HatcheryDraftRowStatus(this.storageKey);

  final String storageKey;

  static HatcheryDraftRowStatus fromStorage(Object? value) {
    return values.firstWhere(
      (status) => status.storageKey == value?.toString(),
      orElse: () => pending,
    );
  }
}

enum AgentSourceKind {
  text('text'),
  image('image'),
  pdf('pdf'),
  spreadsheet('spreadsheet'),
  file('file');

  const AgentSourceKind(this.storageKey);

  final String storageKey;

  static AgentSourceKind fromStorage(Object? value) {
    return values.firstWhere(
      (kind) => kind.storageKey == value?.toString(),
      orElse: () => text,
    );
  }
}

enum AgentQuestionStatus {
  open('open'),
  answered('answered'),
  closed('closed');

  const AgentQuestionStatus(this.storageKey);

  final String storageKey;

  static AgentQuestionStatus fromStorage(Object? value) {
    return values.firstWhere(
      (status) => status.storageKey == value?.toString(),
      orElse: () => open,
    );
  }
}

enum TelegramStaffLinkStatus {
  pending('pending'),
  allowed('allowed'),
  revoked('revoked');

  const TelegramStaffLinkStatus(this.storageKey);

  final String storageKey;

  static TelegramStaffLinkStatus fromStorage(Object? value) {
    return values.firstWhere(
      (status) => status.storageKey == value?.toString(),
      orElse: () => pending,
    );
  }
}

enum TelegramAgentAccessRole {
  customer('customer'),
  admin('admin');

  const TelegramAgentAccessRole(this.storageKey);

  final String storageKey;

  static TelegramAgentAccessRole fromStorage(Object? value) {
    return values.firstWhere(
      (role) => role.storageKey == value?.toString(),
      orElse: () => customer,
    );
  }
}

class TelegramStaffLink {
  const TelegramStaffLink({
    required this.id,
    required this.telegramUserId,
    required this.status,
    this.accessRole = TelegramAgentAccessRole.customer,
    this.customerId,
    this.telegramChatId,
    this.displayName,
    this.username,
    this.invitedBy,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String telegramUserId;
  final String? telegramChatId;
  final String? displayName;
  final String? username;
  final TelegramStaffLinkStatus status;
  final TelegramAgentAccessRole accessRole;
  final String? customerId;
  final String? invitedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory TelegramStaffLink.fromMap(Map<String, Object?> map) {
    return TelegramStaffLink(
      id: map['id']!.toString(),
      telegramUserId: map['telegramUserId']!.toString(),
      telegramChatId: _text(map['telegramChatId']),
      displayName: _text(map['displayName']),
      username: _text(map['username']),
      status: TelegramStaffLinkStatus.fromStorage(map['status']),
      accessRole: TelegramAgentAccessRole.fromStorage(map['accessRole']),
      customerId: _text(map['customerId']),
      invitedBy: _text(map['invitedBy']),
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'telegramUserId': telegramUserId,
    'telegramChatId': telegramChatId,
    'displayName': displayName,
    'username': username,
    'status': status.storageKey,
    'accessRole': accessRole.storageKey,
    'customerId': customerId,
    'invitedBy': invitedBy,
    'createdAt': _dateText(createdAt),
    'updatedAt': _dateText(updatedAt),
  };
}

class HatcheryAgentSubmission {
  const HatcheryAgentSubmission({
    required this.id,
    required this.sourceKind,
    required this.status,
    required this.submittedAt,
    this.telegramUpdateId,
    this.telegramMessageId,
    this.telegramChatId,
    this.telegramUserId,
    this.staffLinkId,
    this.sourceText,
    this.sourceFileName,
    this.sourceMimeType,
    this.sourceRemotePath,
    this.errorMessage,
    this.processedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? telegramUpdateId;
  final String? telegramMessageId;
  final String? telegramChatId;
  final String? telegramUserId;
  final String? staffLinkId;
  final AgentSourceKind sourceKind;
  final String? sourceText;
  final String? sourceFileName;
  final String? sourceMimeType;
  final String? sourceRemotePath;
  final AgentSubmissionStatus status;
  final String? errorMessage;
  final DateTime submittedAt;
  final DateTime? processedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory HatcheryAgentSubmission.fromMap(Map<String, Object?> map) {
    return HatcheryAgentSubmission(
      id: map['id']!.toString(),
      telegramUpdateId: _text(map['telegramUpdateId']),
      telegramMessageId: _text(map['telegramMessageId']),
      telegramChatId: _text(map['telegramChatId']),
      telegramUserId: _text(map['telegramUserId']),
      staffLinkId: _text(map['staffLinkId']),
      sourceKind: AgentSourceKind.fromStorage(map['sourceKind']),
      sourceText: _text(map['sourceText']),
      sourceFileName: _text(map['sourceFileName']),
      sourceMimeType: _text(map['sourceMimeType']),
      sourceRemotePath: _text(map['sourceRemotePath']),
      status: AgentSubmissionStatus.fromStorage(map['status']),
      errorMessage: _text(map['errorMessage']),
      submittedAt: _requiredDate(map['submittedAt'], 'submittedAt'),
      processedAt: _date(map['processedAt']),
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'telegramUpdateId': telegramUpdateId,
    'telegramMessageId': telegramMessageId,
    'telegramChatId': telegramChatId,
    'telegramUserId': telegramUserId,
    'staffLinkId': staffLinkId,
    'sourceKind': sourceKind.storageKey,
    'sourceText': sourceText,
    'sourceFileName': sourceFileName,
    'sourceMimeType': sourceMimeType,
    'sourceRemotePath': sourceRemotePath,
    'status': status.storageKey,
    'errorMessage': errorMessage,
    'submittedAt': _dateText(submittedAt),
    'processedAt': _dateText(processedAt),
    'createdAt': _dateText(createdAt),
    'updatedAt': _dateText(updatedAt),
  };
}

class HatcheryAgentQuestion {
  const HatcheryAgentQuestion({
    required this.id,
    required this.submissionId,
    required this.fieldKey,
    required this.questionTextEn,
    required this.questionTextAr,
    this.rowOrdinal,
    this.status = AgentQuestionStatus.open,
    this.answerText,
    this.answeredAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String submissionId;
  final int? rowOrdinal;
  final String fieldKey;
  final String questionTextEn;
  final String questionTextAr;
  final AgentQuestionStatus status;
  final String? answerText;
  final DateTime? answeredAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory HatcheryAgentQuestion.fromMap(Map<String, Object?> map) {
    return HatcheryAgentQuestion(
      id: map['id']!.toString(),
      submissionId: map['submissionId']!.toString(),
      rowOrdinal: _integer(map['rowOrdinal']),
      fieldKey: map['fieldKey']!.toString(),
      questionTextEn: map['questionTextEn']!.toString(),
      questionTextAr: map['questionTextAr']!.toString(),
      status: AgentQuestionStatus.fromStorage(map['status']),
      answerText: _text(map['answerText']),
      answeredAt: _date(map['answeredAt']),
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'submissionId': submissionId,
    'rowOrdinal': rowOrdinal,
    'fieldKey': fieldKey,
    'questionTextEn': questionTextEn,
    'questionTextAr': questionTextAr,
    'status': status.storageKey,
    'answerText': answerText,
    'answeredAt': _dateText(answeredAt),
    'createdAt': _dateText(createdAt),
    'updatedAt': _dateText(updatedAt),
  };
}

class HatcheryDraftBatch {
  const HatcheryDraftBatch({
    required this.id,
    required this.submissionId,
    required this.status,
    this.sourceSummary,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String submissionId;
  final AgentSubmissionStatus status;
  final String? sourceSummary;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory HatcheryDraftBatch.fromMap(Map<String, Object?> map) {
    return HatcheryDraftBatch(
      id: map['id']!.toString(),
      submissionId: map['submissionId']!.toString(),
      status: AgentSubmissionStatus.fromStorage(map['status']),
      sourceSummary: _text(map['sourceSummary']),
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'submissionId': submissionId,
    'status': status.storageKey,
    'sourceSummary': sourceSummary,
    'createdAt': _dateText(createdAt),
    'updatedAt': _dateText(updatedAt),
  };
}

class HatcheryDraftRow {
  const HatcheryDraftRow({
    required this.id,
    required this.batchId,
    required this.rowOrdinal,
    required this.status,
    this.customerId,
    this.customerName,
    this.flockId,
    this.flockName,
    this.hatcheryId,
    this.stationName,
    this.breed,
    this.eggsPlaced,
    this.productionDate,
    this.placementDate,
    this.eggWeightG,
    this.fertilityPct,
    this.transferWeightG,
    this.setterNumber,
    this.hatcherNumber,
    this.hatchDate,
    this.healthyChicks,
    this.secondGradeChicks,
    this.condemnedChicks,
    this.totalProduction,
    this.hatchabilityPct,
    this.confidencePct,
    this.extractionJson,
    this.warningsJson,
    this.proposedFlockAgeWeeks,
    this.approvedRecordId,
    this.reviewedBy,
    this.reviewedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String batchId;
  final int rowOrdinal;
  final HatcheryDraftRowStatus status;
  final String? customerId;
  final String? customerName;
  final String? flockId;
  final String? flockName;
  final String? hatcheryId;
  final String? stationName;
  final String? breed;
  final int? eggsPlaced;
  final DateTime? productionDate;
  final DateTime? placementDate;
  final double? eggWeightG;
  final double? fertilityPct;
  final double? transferWeightG;
  final String? setterNumber;
  final String? hatcherNumber;
  final DateTime? hatchDate;
  final int? healthyChicks;
  final int? secondGradeChicks;
  final int? condemnedChicks;
  final int? totalProduction;
  final double? hatchabilityPct;
  final double? confidencePct;
  final String? extractionJson;
  final String? warningsJson;
  final int? proposedFlockAgeWeeks;
  final String? approvedRecordId;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory HatcheryDraftRow.fromMap(Map<String, Object?> map) {
    return HatcheryDraftRow(
      id: map['id']!.toString(),
      batchId: map['batchId']!.toString(),
      rowOrdinal: _integer(map['rowOrdinal']) ?? 0,
      status: HatcheryDraftRowStatus.fromStorage(map['status']),
      customerId: _text(map['customerId']),
      customerName: _text(map['customerName']),
      flockId: _text(map['flockId']),
      flockName: _text(map['flockName']),
      hatcheryId: _text(map['hatcheryId']),
      stationName: _text(map['stationName']),
      breed: _text(map['breed']),
      eggsPlaced: _integer(map['eggsPlaced']),
      productionDate: _date(map['productionDate']),
      placementDate: _date(map['placementDate']),
      eggWeightG: _number(map['eggWeightG']),
      fertilityPct: _number(map['fertilityPct']),
      transferWeightG: _number(map['transferWeightG']),
      setterNumber: _text(map['setterNumber']),
      hatcherNumber: _text(map['hatcherNumber']),
      hatchDate: _date(map['hatchDate']),
      healthyChicks: _integer(map['healthyChicks']),
      secondGradeChicks: _integer(map['secondGradeChicks']),
      condemnedChicks: _integer(map['condemnedChicks']),
      totalProduction: _integer(map['totalProduction']),
      hatchabilityPct: _number(map['hatchabilityPct']),
      confidencePct: _number(map['confidencePct']),
      extractionJson: _text(map['extractionJson']),
      warningsJson: _text(map['warningsJson']),
      proposedFlockAgeWeeks: _integer(map['proposedFlockAgeWeeks']),
      approvedRecordId: _text(map['approvedRecordId']),
      reviewedBy: _text(map['reviewedBy']),
      reviewedAt: _date(map['reviewedAt']),
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'batchId': batchId,
    'rowOrdinal': rowOrdinal,
    'status': status.storageKey,
    'customerId': customerId,
    'customerName': customerName,
    'flockId': flockId,
    'flockName': flockName,
    'hatcheryId': hatcheryId,
    'stationName': stationName,
    'breed': breed,
    'eggsPlaced': eggsPlaced,
    'productionDate': _dateText(productionDate),
    'placementDate': _dateText(placementDate),
    'eggWeightG': eggWeightG,
    'fertilityPct': fertilityPct,
    'transferWeightG': transferWeightG,
    'setterNumber': setterNumber,
    'hatcherNumber': hatcherNumber,
    'hatchDate': _dateText(hatchDate),
    'healthyChicks': healthyChicks,
    'secondGradeChicks': secondGradeChicks,
    'condemnedChicks': condemnedChicks,
    'totalProduction': totalProduction,
    'hatchabilityPct': hatchabilityPct,
    'confidencePct': confidencePct,
    'extractionJson': extractionJson,
    'warningsJson': warningsJson,
    'proposedFlockAgeWeeks': proposedFlockAgeWeeks,
    'approvedRecordId': approvedRecordId,
    'reviewedBy': reviewedBy,
    'reviewedAt': _dateText(reviewedAt),
    'createdAt': _dateText(createdAt),
    'updatedAt': _dateText(updatedAt),
  };

  HatcheryDraftRow copyWith({
    String? id,
    String? batchId,
    int? rowOrdinal,
    HatcheryDraftRowStatus? status,
    String? customerId,
    String? customerName,
    String? flockId,
    String? flockName,
    String? hatcheryId,
    String? stationName,
    String? breed,
    int? eggsPlaced,
    DateTime? productionDate,
    DateTime? placementDate,
    double? eggWeightG,
    double? fertilityPct,
    double? transferWeightG,
    String? setterNumber,
    String? hatcherNumber,
    DateTime? hatchDate,
    int? healthyChicks,
    int? secondGradeChicks,
    int? condemnedChicks,
    int? totalProduction,
    double? hatchabilityPct,
    double? confidencePct,
    String? extractionJson,
    String? warningsJson,
    int? proposedFlockAgeWeeks,
    String? approvedRecordId,
    String? reviewedBy,
    DateTime? reviewedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return HatcheryDraftRow(
      id: id ?? this.id,
      batchId: batchId ?? this.batchId,
      rowOrdinal: rowOrdinal ?? this.rowOrdinal,
      status: status ?? this.status,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      flockId: flockId ?? this.flockId,
      flockName: flockName ?? this.flockName,
      hatcheryId: hatcheryId ?? this.hatcheryId,
      stationName: stationName ?? this.stationName,
      breed: breed ?? this.breed,
      eggsPlaced: eggsPlaced ?? this.eggsPlaced,
      productionDate: productionDate ?? this.productionDate,
      placementDate: placementDate ?? this.placementDate,
      eggWeightG: eggWeightG ?? this.eggWeightG,
      fertilityPct: fertilityPct ?? this.fertilityPct,
      transferWeightG: transferWeightG ?? this.transferWeightG,
      setterNumber: setterNumber ?? this.setterNumber,
      hatcherNumber: hatcherNumber ?? this.hatcherNumber,
      hatchDate: hatchDate ?? this.hatchDate,
      healthyChicks: healthyChicks ?? this.healthyChicks,
      secondGradeChicks: secondGradeChicks ?? this.secondGradeChicks,
      condemnedChicks: condemnedChicks ?? this.condemnedChicks,
      totalProduction: totalProduction ?? this.totalProduction,
      hatchabilityPct: hatchabilityPct ?? this.hatchabilityPct,
      confidencePct: confidencePct ?? this.confidencePct,
      extractionJson: extractionJson ?? this.extractionJson,
      warningsJson: warningsJson ?? this.warningsJson,
      proposedFlockAgeWeeks:
          proposedFlockAgeWeeks ?? this.proposedFlockAgeWeeks,
      approvedRecordId: approvedRecordId ?? this.approvedRecordId,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class HatcheryAgentAuditEvent {
  const HatcheryAgentAuditEvent({
    required this.id,
    required this.submissionId,
    required this.actorType,
    required this.eventType,
    required this.createdAt,
    this.rowId,
    this.actorId,
    this.detailsJson,
  });

  final String id;
  final String submissionId;
  final String? rowId;
  final String actorType;
  final String? actorId;
  final String eventType;
  final String? detailsJson;
  final DateTime createdAt;

  factory HatcheryAgentAuditEvent.fromMap(Map<String, Object?> map) {
    return HatcheryAgentAuditEvent(
      id: map['id']!.toString(),
      submissionId: map['submissionId']!.toString(),
      rowId: _text(map['rowId']),
      actorType: map['actorType']!.toString(),
      actorId: _text(map['actorId']),
      eventType: map['eventType']!.toString(),
      detailsJson: _text(map['detailsJson']),
      createdAt: _requiredDate(map['createdAt'], 'createdAt'),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'submissionId': submissionId,
    'rowId': rowId,
    'actorType': actorType,
    'actorId': actorId,
    'eventType': eventType,
    'detailsJson': detailsJson,
    'createdAt': _dateText(createdAt),
  };
}

class HatcheryDailyRecord {
  const HatcheryDailyRecord({
    required this.id,
    required this.customerId,
    required this.flockId,
    required this.stationName,
    required this.breed,
    required this.eggsPlaced,
    required this.hatchDate,
    required this.totalProduction,
    required this.hatchabilityPct,
    this.sourceDraftRowId,
    this.hatcheryId,
    this.productionDate,
    this.placementDate,
    this.eggWeightG,
    this.fertilityPct,
    this.transferWeightG,
    this.setterNumber,
    this.hatcherNumber,
    this.healthyChicks,
    this.secondGradeChicks,
    this.condemnedChicks,
    this.approvedBy,
    this.approvedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? sourceDraftRowId;
  final String customerId;
  final String flockId;
  final String? hatcheryId;
  final String stationName;
  final String breed;
  final int eggsPlaced;
  final DateTime? productionDate;
  final DateTime? placementDate;
  final double? eggWeightG;
  final double? fertilityPct;
  final double? transferWeightG;
  final String? setterNumber;
  final String? hatcherNumber;
  final DateTime hatchDate;
  final int? healthyChicks;
  final int? secondGradeChicks;
  final int? condemnedChicks;
  final int totalProduction;
  final double hatchabilityPct;
  final String? approvedBy;
  final DateTime? approvedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory HatcheryDailyRecord.fromMap(Map<String, Object?> map) {
    return HatcheryDailyRecord(
      id: map['id']!.toString(),
      sourceDraftRowId: _text(map['sourceDraftRowId']),
      customerId: map['customerId']!.toString(),
      flockId: map['flockId']!.toString(),
      hatcheryId: _text(map['hatcheryId']),
      stationName: map['stationName']!.toString(),
      breed: map['breed']!.toString(),
      eggsPlaced: _integer(map['eggsPlaced']) ?? 0,
      productionDate: _date(map['productionDate']),
      placementDate: _date(map['placementDate']),
      eggWeightG: _number(map['eggWeightG']),
      fertilityPct: _number(map['fertilityPct']),
      transferWeightG: _number(map['transferWeightG']),
      setterNumber: _text(map['setterNumber']),
      hatcherNumber: _text(map['hatcherNumber']),
      hatchDate: _requiredDate(map['hatchDate'], 'hatchDate'),
      healthyChicks: _integer(map['healthyChicks']),
      secondGradeChicks: _integer(map['secondGradeChicks']),
      condemnedChicks: _integer(map['condemnedChicks']),
      totalProduction: _integer(map['totalProduction']) ?? 0,
      hatchabilityPct: _number(map['hatchabilityPct']) ?? 0,
      approvedBy: _text(map['approvedBy']),
      approvedAt: _date(map['approvedAt']),
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'sourceDraftRowId': sourceDraftRowId,
    'customerId': customerId,
    'flockId': flockId,
    'hatcheryId': hatcheryId,
    'stationName': stationName,
    'breed': breed,
    'eggsPlaced': eggsPlaced,
    'productionDate': _dateText(productionDate),
    'placementDate': _dateText(placementDate),
    'eggWeightG': eggWeightG,
    'fertilityPct': fertilityPct,
    'transferWeightG': transferWeightG,
    'setterNumber': setterNumber,
    'hatcherNumber': hatcherNumber,
    'hatchDate': _dateText(hatchDate),
    'healthyChicks': healthyChicks,
    'secondGradeChicks': secondGradeChicks,
    'condemnedChicks': condemnedChicks,
    'totalProduction': totalProduction,
    'hatchabilityPct': hatchabilityPct,
    'approvedBy': approvedBy,
    'approvedAt': _dateText(approvedAt),
    'createdAt': _dateText(createdAt),
    'updatedAt': _dateText(updatedAt),
  };
}

class HatcheryHistoricalPoint {
  const HatcheryHistoricalPoint({
    required this.recordId,
    required this.hatchDate,
    required this.hatchabilityPct,
  });

  final String recordId;
  final DateTime hatchDate;
  final double hatchabilityPct;

  factory HatcheryHistoricalPoint.fromMap(Map<String, Object?> map) {
    return HatcheryHistoricalPoint(
      recordId: map['id']!.toString(),
      hatchDate: _requiredDate(map['hatchDate'], 'hatchDate'),
      hatchabilityPct: _number(map['hatchabilityPct']) ?? 0,
    );
  }
}

class AgentSettings {
  const AgentSettings({
    this.id = 1,
    this.telegramEnabled = true,
    this.hatchabilityWarningThresholdPoints = 3,
    this.minimumReadyConfidencePct = 85,
    this.updatedAt,
  });

  final int id;
  final bool telegramEnabled;
  final double hatchabilityWarningThresholdPoints;
  final double minimumReadyConfidencePct;
  final DateTime? updatedAt;

  factory AgentSettings.fromMap(Map<String, Object?> map) {
    return AgentSettings(
      id: _integer(map['id']) ?? 1,
      telegramEnabled: _boolean(map['telegramEnabled'], fallback: true),
      hatchabilityWarningThresholdPoints:
          _number(map['hatchabilityWarningThresholdPoints']) ?? 3,
      minimumReadyConfidencePct:
          _number(map['minimumReadyConfidencePct']) ?? 85,
      updatedAt: _date(map['updatedAt']),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'telegramEnabled': telegramEnabled ? 1 : 0,
    'hatchabilityWarningThresholdPoints': hatchabilityWarningThresholdPoints,
    'minimumReadyConfidencePct': minimumReadyConfidencePct,
    'updatedAt': _dateText(updatedAt),
  };
}

class HatcheryDraftBatchSummary {
  const HatcheryDraftBatchSummary({
    required this.id,
    required this.submissionId,
    required this.status,
    required this.submittedAt,
    required this.sourceKind,
    required this.rowCount,
    required this.needsReviewCount,
    required this.approvedCount,
    required this.rejectedCount,
    this.sourceSummary,
    this.sourceText,
    this.sourceFileName,
    this.staffLinkId,
    this.telegramUserId,
  });

  final String id;
  final String submissionId;
  final AgentSubmissionStatus status;
  final String? sourceSummary;
  final DateTime submittedAt;
  final AgentSourceKind sourceKind;
  final String? sourceText;
  final String? sourceFileName;
  final String? staffLinkId;
  final String? telegramUserId;
  final int rowCount;
  final int needsReviewCount;
  final int approvedCount;
  final int rejectedCount;

  factory HatcheryDraftBatchSummary.fromMap(Map<String, Object?> map) {
    return HatcheryDraftBatchSummary(
      id: map['id']!.toString(),
      submissionId: map['submissionId']!.toString(),
      status: AgentSubmissionStatus.fromStorage(map['status']),
      sourceSummary: _text(map['sourceSummary']),
      submittedAt: _requiredDate(map['submittedAt'], 'submittedAt'),
      sourceKind: AgentSourceKind.fromStorage(map['sourceKind']),
      sourceText: _text(map['sourceText']),
      sourceFileName: _text(map['sourceFileName']),
      staffLinkId: _text(map['staffLinkId']),
      telegramUserId: _text(map['telegramUserId']),
      rowCount: _integer(map['rowCount']) ?? 0,
      needsReviewCount: _integer(map['needsReviewCount']) ?? 0,
      approvedCount: _integer(map['approvedCount']) ?? 0,
      rejectedCount: _integer(map['rejectedCount']) ?? 0,
    );
  }
}

class HatcheryDraftBatchDetails {
  HatcheryDraftBatchDetails({
    required this.submission,
    required this.batch,
    required List<HatcheryDraftRow> rows,
    required List<HatcheryAgentQuestion> questions,
    required List<HatcheryAgentAuditEvent> events,
  }) : rows = List.unmodifiable(rows),
       questions = List.unmodifiable(questions),
       events = List.unmodifiable(events);

  final HatcheryAgentSubmission submission;
  final HatcheryDraftBatch batch;
  final List<HatcheryDraftRow> rows;
  final List<HatcheryAgentQuestion> questions;
  final List<HatcheryAgentAuditEvent> events;
}

DateTime? _date(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  return DateTime.tryParse(value.toString())?.toUtc();
}

DateTime _requiredDate(Object? value, String field) {
  final parsed = _date(value);
  if (parsed == null) {
    throw FormatException('Invalid or missing $field');
  }
  return parsed;
}

String? _dateText(DateTime? value) => value?.toUtc().toIso8601String();

String? _text(Object? value) => value?.toString();

int? _integer(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? _number(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

bool _boolean(Object? value, {required bool fallback}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = value.toString().toLowerCase();
  if (normalized == 'true' || normalized == '1') return true;
  if (normalized == 'false' || normalized == '0') return false;
  return fallback;
}
