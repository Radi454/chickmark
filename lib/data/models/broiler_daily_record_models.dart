import 'dart:convert';

enum VerificationStatus {
  pendingEntry('pending_entry'),
  entered('entered'),
  reviewed('reviewed'),
  verified('verified'),
  requiresClarification('requires_clarification'),
  corrected('corrected');

  const VerificationStatus(this.storageKey);

  final String storageKey;

  static VerificationStatus fromStorage(Object? value) {
    final key = value?.toString();
    return values.firstWhere(
      (status) => status.storageKey == key,
      orElse: () => VerificationStatus.pendingEntry,
    );
  }
}

enum DailyDataSourceType {
  manual('manual'),
  csvImport('csv_import'),
  spreadsheet('spreadsheet'),
  documentAssisted('document_assisted'),
  message('message');

  const DailyDataSourceType(this.storageKey);

  final String storageKey;

  static DailyDataSourceType fromStorage(Object? value) {
    final key = value?.toString();
    return values.firstWhere(
      (type) => type.storageKey == key,
      orElse: () => DailyDataSourceType.manual,
    );
  }
}

enum DailyRecordSourceKind {
  spreadsheet('spreadsheet'),
  csv('csv'),
  image('image'),
  pdf('pdf'),
  message('message'),
  other('other');

  const DailyRecordSourceKind(this.storageKey);

  final String storageKey;

  static DailyRecordSourceKind fromStorage(Object? value) {
    final key = value?.toString();
    return values.firstWhere(
      (kind) => kind.storageKey == key,
      orElse: () => DailyRecordSourceKind.other,
    );
  }
}

enum BroilerDailyEventType {
  clinicalSign('clinical_sign'),
  treatment('treatment'),
  vaccination('vaccination'),
  feedChange('feed_change'),
  waterFailure('water_failure'),
  powerFailure('power_failure'),
  equipmentFailure('equipment_failure'),
  veterinaryObservation('veterinary_observation'),
  other('other');

  const BroilerDailyEventType(this.storageKey);

  final String storageKey;

  static BroilerDailyEventType fromStorage(Object? value) {
    final key = value?.toString();
    return values.firstWhere(
      (type) => type.storageKey == key,
      orElse: () => BroilerDailyEventType.other,
    );
  }
}

enum DailyEventState {
  started('started'),
  stopped('stopped'),
  ongoing('ongoing'),
  resolved('resolved'),
  observed('observed');

  const DailyEventState(this.storageKey);

  final String storageKey;

  static DailyEventState? fromStorage(Object? value) {
    final key = value?.toString();
    if (key == null || key.isEmpty) return null;
    for (final state in values) {
      if (state.storageKey == key) return state;
    }
    return null;
  }
}

class BroilerDailyRecord {
  const BroilerDailyRecord({
    required this.id,
    required this.placementId,
    required this.recordDate,
    required this.verificationStatus,
    this.currentRevisionId,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  });

  final String id;
  final String placementId;
  final DateTime recordDate;
  final String? currentRevisionId;
  final VerificationStatus verificationStatus;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  factory BroilerDailyRecord.fromMap(Map<String, Object?> map) {
    return BroilerDailyRecord(
      id: map['id']! as String,
      placementId: map['placementId']! as String,
      recordDate: DateTime.parse(map['recordDate']! as String),
      currentRevisionId: map['currentRevisionId'] as String?,
      verificationStatus: VerificationStatus.fromStorage(
        map['verificationStatus'],
      ),
      createdBy: map['createdBy'] as String?,
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
      syncStatus: map['syncStatus']?.toString() ?? 'pending',
      dirtyAt: _date(map['dirtyAt']),
      lastSyncedAt: _date(map['lastSyncedAt']),
      syncError: map['syncError'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'placementId': placementId,
      'recordDate': dateKey(recordDate),
      'currentRevisionId': currentRevisionId,
      'verificationStatus': verificationStatus.storageKey,
      'createdBy': createdBy,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'syncStatus': syncStatus,
      'dirtyAt': dirtyAt?.toIso8601String(),
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'syncError': syncError,
    };
  }
}

class BroilerDailyRecordDraft {
  const BroilerDailyRecordDraft({
    required this.placementId,
    required this.recordDate,
    required this.verificationStatus,
    required this.enteredBy,
    required this.enteredAt,
    this.recordId,
    this.dataSourceType = DailyDataSourceType.manual,
    this.sourceDescription,
    this.reportedBy,
    this.reviewedBy,
    this.reviewedAt,
    this.verifiedBy,
    this.verifiedAt,
    this.correctionReason,
    this.openingBirdCount,
    this.dailyMortality,
    this.dailyCulls,
    this.transfersIn,
    this.transfersOut,
    this.partialDepletion,
    this.otherPopulationAdjustment,
    this.mortalityCauses = const {},
    this.closingLiveBirdCount,
    this.dailyFeedConsumedKg,
    this.feedType,
    this.feedPhase,
    this.feedChange,
    this.feedInterruptionMinutes,
    this.feedShortage,
    this.waterConsumedLiters,
    this.flushingWaterLiters,
    this.waterInterruptionMinutes,
    this.waterMedication,
    this.waterVaccination,
    this.averageBodyWeightG,
    this.birdsWeighed,
    this.uniformityPct,
    this.cvPct,
    this.individualWeightsG = const [],
    this.minTemperatureC,
    this.maxTemperatureC,
    this.averageTemperatureC,
    this.relativeHumidityPct,
    this.co2Ppm,
    this.ammoniaPpm,
    this.environmentIncident,
    this.clinicalSigns,
    this.treatmentStarted,
    this.treatmentStopped,
    this.vaccination,
    this.powerFailure,
    this.equipmentFailure,
    this.veterinaryObservation,
    this.notes,
    this.sources = const [],
    this.events = const [],
  });

  final String? recordId;
  final String placementId;
  final DateTime recordDate;
  final VerificationStatus verificationStatus;
  final DailyDataSourceType dataSourceType;
  final String? sourceDescription;
  final String? reportedBy;
  final String enteredBy;
  final DateTime enteredAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final String? correctionReason;
  final int? openingBirdCount;
  final int? dailyMortality;
  final int? dailyCulls;
  final int? transfersIn;
  final int? transfersOut;
  final int? partialDepletion;
  final int? otherPopulationAdjustment;
  final Map<String, int> mortalityCauses;
  final int? closingLiveBirdCount;
  final double? dailyFeedConsumedKg;
  final String? feedType;
  final String? feedPhase;
  final String? feedChange;
  final int? feedInterruptionMinutes;
  final bool? feedShortage;
  final double? waterConsumedLiters;
  final double? flushingWaterLiters;
  final int? waterInterruptionMinutes;
  final String? waterMedication;
  final String? waterVaccination;
  final double? averageBodyWeightG;
  final int? birdsWeighed;
  final double? uniformityPct;
  final double? cvPct;
  final List<double> individualWeightsG;
  final double? minTemperatureC;
  final double? maxTemperatureC;
  final double? averageTemperatureC;
  final double? relativeHumidityPct;
  final double? co2Ppm;
  final double? ammoniaPpm;
  final String? environmentIncident;
  final String? clinicalSigns;
  final String? treatmentStarted;
  final String? treatmentStopped;
  final String? vaccination;
  final bool? powerFailure;
  final String? equipmentFailure;
  final String? veterinaryObservation;
  final String? notes;
  final List<DailyRecordSourceDraft> sources;
  final List<BroilerDailyEventDraft> events;

  void validate() {
    final errors = <String>[];
    if (placementId.trim().isEmpty) errors.add('Placement is required.');
    if (enteredBy.trim().isEmpty) errors.add('Entered by is required.');
    if (verificationStatus == VerificationStatus.corrected &&
        (correctionReason == null || correctionReason!.trim().isEmpty)) {
      errors.add('A correction reason is required.');
    }
    if (verificationStatus == VerificationStatus.verified &&
        ((verifiedBy == null || verifiedBy!.trim().isEmpty) ||
            verifiedAt == null)) {
      errors.add('Verified by and verification time are required.');
    }

    final nonNegative = <String, num?>{
      'opening bird count': openingBirdCount,
      'daily mortality': dailyMortality,
      'daily culls': dailyCulls,
      'transfers in': transfersIn,
      'transfers out': transfersOut,
      'partial depletion': partialDepletion,
      'other population adjustment': otherPopulationAdjustment,
      'closing live bird count': closingLiveBirdCount,
      'daily feed': dailyFeedConsumedKg,
      'feed interruption': feedInterruptionMinutes,
      'daily water': waterConsumedLiters,
      'flushing water': flushingWaterLiters,
      'water interruption': waterInterruptionMinutes,
      'average body weight': averageBodyWeightG,
      'birds weighed': birdsWeighed,
      'uniformity': uniformityPct,
      'CV': cvPct,
      'relative humidity': relativeHumidityPct,
      'CO2': co2Ppm,
      'ammonia': ammoniaPpm,
    };
    for (final entry in nonNegative.entries) {
      if (entry.value != null && entry.value! < 0) {
        errors.add('${entry.key} cannot be negative.');
      }
    }
    for (final entry in mortalityCauses.entries) {
      if (entry.key.trim().isEmpty || entry.value < 0) {
        errors.add('Mortality causes require a name and non-negative count.');
      }
    }
    if (individualWeightsG.any((weight) => weight < 0)) {
      errors.add('Individual weights cannot be negative.');
    }
    for (final entry in {
      'uniformity': uniformityPct,
      'relative humidity': relativeHumidityPct,
    }.entries) {
      if (entry.value != null && entry.value! > 100) {
        errors.add('${entry.key} cannot exceed 100%.');
      }
    }
    if (minTemperatureC != null &&
        maxTemperatureC != null &&
        minTemperatureC! > maxTemperatureC!) {
      errors.add('Minimum temperature cannot exceed maximum temperature.');
    }

    final populationFacts = [
      openingBirdCount,
      dailyMortality,
      dailyCulls,
      transfersIn,
      transfersOut,
      partialDepletion,
      otherPopulationAdjustment,
      closingLiveBirdCount,
    ];
    if (populationFacts.every((value) => value != null)) {
      final expectedClosing =
          openingBirdCount! -
          dailyMortality! -
          dailyCulls! +
          transfersIn! -
          transfersOut! -
          partialDepletion! +
          otherPopulationAdjustment!;
      if (closingLiveBirdCount != expectedClosing) {
        errors.add(
          'Closing live birds must equal opening birds adjusted for '
          'mortality, culls, transfers, and depletion.',
        );
      }
    }

    if (errors.isNotEmpty) {
      throw DailyRecordValidationException(errors);
    }
  }

  Map<String, Object?> toRevisionMap() {
    return {
      'verificationStatus': verificationStatus.storageKey,
      'dataSourceType': dataSourceType.storageKey,
      'sourceDescription': sourceDescription,
      'reportedBy': reportedBy,
      'enteredBy': enteredBy,
      'enteredAt': enteredAt.toUtc().toIso8601String(),
      'reviewedBy': reviewedBy,
      'reviewedAt': reviewedAt?.toUtc().toIso8601String(),
      'verifiedBy': verifiedBy,
      'verifiedAt': verifiedAt?.toUtc().toIso8601String(),
      'correctionReason': correctionReason,
      'openingBirdCount': openingBirdCount,
      'dailyMortality': dailyMortality,
      'dailyCulls': dailyCulls,
      'transfersIn': transfersIn,
      'transfersOut': transfersOut,
      'partialDepletion': partialDepletion,
      'otherPopulationAdjustment': otherPopulationAdjustment,
      'mortalityCausesJson': mortalityCauses.isEmpty
          ? null
          : jsonEncode(mortalityCauses),
      'closingLiveBirdCount': closingLiveBirdCount,
      'dailyFeedConsumedKg': dailyFeedConsumedKg,
      'feedType': feedType,
      'feedPhase': feedPhase,
      'feedChange': feedChange,
      'feedInterruptionMinutes': feedInterruptionMinutes,
      'feedShortage': _databaseBool(feedShortage),
      'waterConsumedLiters': waterConsumedLiters,
      'flushingWaterLiters': flushingWaterLiters,
      'waterInterruptionMinutes': waterInterruptionMinutes,
      'waterMedication': waterMedication,
      'waterVaccination': waterVaccination,
      'averageBodyWeightG': averageBodyWeightG,
      'birdsWeighed': birdsWeighed,
      'uniformityPct': uniformityPct,
      'cvPct': cvPct,
      'individualWeightsJson': individualWeightsG.isEmpty
          ? null
          : jsonEncode(individualWeightsG),
      'minTemperatureC': minTemperatureC,
      'maxTemperatureC': maxTemperatureC,
      'averageTemperatureC': averageTemperatureC,
      'relativeHumidityPct': relativeHumidityPct,
      'co2Ppm': co2Ppm,
      'ammoniaPpm': ammoniaPpm,
      'environmentIncident': environmentIncident,
      'clinicalSigns': clinicalSigns,
      'treatmentStarted': treatmentStarted,
      'treatmentStopped': treatmentStopped,
      'vaccination': vaccination,
      'powerFailure': _databaseBool(powerFailure),
      'equipmentFailure': equipmentFailure,
      'veterinaryObservation': veterinaryObservation,
      'notes': notes,
    };
  }

  factory BroilerDailyRecordDraft.fromRevisionMap(
    Map<String, Object?> map, {
    required String placementId,
    required DateTime recordDate,
  }) {
    return BroilerDailyRecordDraft(
      recordId: map['recordId'] as String?,
      placementId: placementId,
      recordDate: recordDate,
      verificationStatus: VerificationStatus.fromStorage(
        map['verificationStatus'],
      ),
      dataSourceType: DailyDataSourceType.fromStorage(map['dataSourceType']),
      sourceDescription: map['sourceDescription'] as String?,
      reportedBy: map['reportedBy'] as String?,
      enteredBy: map['enteredBy']! as String,
      enteredAt: DateTime.parse(map['enteredAt']! as String),
      reviewedBy: map['reviewedBy'] as String?,
      reviewedAt: _date(map['reviewedAt']),
      verifiedBy: map['verifiedBy'] as String?,
      verifiedAt: _date(map['verifiedAt']),
      correctionReason: map['correctionReason'] as String?,
      openingBirdCount: _integer(map['openingBirdCount']),
      dailyMortality: _integer(map['dailyMortality']),
      dailyCulls: _integer(map['dailyCulls']),
      transfersIn: _integer(map['transfersIn']),
      transfersOut: _integer(map['transfersOut']),
      partialDepletion: _integer(map['partialDepletion']),
      otherPopulationAdjustment: _integer(map['otherPopulationAdjustment']),
      mortalityCauses: _intMap(map['mortalityCausesJson']),
      closingLiveBirdCount: _integer(map['closingLiveBirdCount']),
      dailyFeedConsumedKg: _number(map['dailyFeedConsumedKg']),
      feedType: map['feedType'] as String?,
      feedPhase: map['feedPhase'] as String?,
      feedChange: map['feedChange'] as String?,
      feedInterruptionMinutes: _integer(map['feedInterruptionMinutes']),
      feedShortage: _bool(map['feedShortage']),
      waterConsumedLiters: _number(map['waterConsumedLiters']),
      flushingWaterLiters: _number(map['flushingWaterLiters']),
      waterInterruptionMinutes: _integer(map['waterInterruptionMinutes']),
      waterMedication: map['waterMedication'] as String?,
      waterVaccination: map['waterVaccination'] as String?,
      averageBodyWeightG: _number(map['averageBodyWeightG']),
      birdsWeighed: _integer(map['birdsWeighed']),
      uniformityPct: _number(map['uniformityPct']),
      cvPct: _number(map['cvPct']),
      individualWeightsG: _doubleList(map['individualWeightsJson']),
      minTemperatureC: _number(map['minTemperatureC']),
      maxTemperatureC: _number(map['maxTemperatureC']),
      averageTemperatureC: _number(map['averageTemperatureC']),
      relativeHumidityPct: _number(map['relativeHumidityPct']),
      co2Ppm: _number(map['co2Ppm']),
      ammoniaPpm: _number(map['ammoniaPpm']),
      environmentIncident: map['environmentIncident'] as String?,
      clinicalSigns: map['clinicalSigns'] as String?,
      treatmentStarted: map['treatmentStarted'] as String?,
      treatmentStopped: map['treatmentStopped'] as String?,
      vaccination: map['vaccination'] as String?,
      powerFailure: _bool(map['powerFailure']),
      equipmentFailure: map['equipmentFailure'] as String?,
      veterinaryObservation: map['veterinaryObservation'] as String?,
      notes: map['notes'] as String?,
    );
  }

  BroilerDailyRecordDraft copyWith({
    String? recordId,
    String? placementId,
    DateTime? recordDate,
    VerificationStatus? verificationStatus,
    DailyDataSourceType? dataSourceType,
    String? sourceDescription,
    String? reportedBy,
    String? enteredBy,
    DateTime? enteredAt,
    String? reviewedBy,
    DateTime? reviewedAt,
    String? verifiedBy,
    DateTime? verifiedAt,
    String? correctionReason,
    int? openingBirdCount,
    int? mortality,
    int? dailyMortality,
    int? dailyCulls,
    int? transfersIn,
    int? transfersOut,
    int? partialDepletion,
    int? otherPopulationAdjustment,
    Map<String, int>? mortalityCauses,
    int? closingLiveBirdCount,
    double? dailyFeedConsumedKg,
    String? feedType,
    String? feedPhase,
    String? feedChange,
    int? feedInterruptionMinutes,
    bool? feedShortage,
    double? waterConsumedLiters,
    double? flushingWaterLiters,
    int? waterInterruptionMinutes,
    String? waterMedication,
    String? waterVaccination,
    double? averageBodyWeightG,
    int? birdsWeighed,
    double? uniformityPct,
    double? cvPct,
    List<double>? individualWeightsG,
    double? minTemperatureC,
    double? maxTemperatureC,
    double? averageTemperatureC,
    double? relativeHumidityPct,
    double? co2Ppm,
    double? ammoniaPpm,
    String? environmentIncident,
    String? clinicalSigns,
    String? treatmentStarted,
    String? treatmentStopped,
    String? vaccination,
    bool? powerFailure,
    String? equipmentFailure,
    String? veterinaryObservation,
    String? notes,
    List<DailyRecordSourceDraft>? sources,
    List<BroilerDailyEventDraft>? events,
  }) {
    return BroilerDailyRecordDraft(
      recordId: recordId ?? this.recordId,
      placementId: placementId ?? this.placementId,
      recordDate: recordDate ?? this.recordDate,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      dataSourceType: dataSourceType ?? this.dataSourceType,
      sourceDescription: sourceDescription ?? this.sourceDescription,
      reportedBy: reportedBy ?? this.reportedBy,
      enteredBy: enteredBy ?? this.enteredBy,
      enteredAt: enteredAt ?? this.enteredAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      verifiedBy: verifiedBy ?? this.verifiedBy,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      correctionReason: correctionReason ?? this.correctionReason,
      openingBirdCount: openingBirdCount ?? this.openingBirdCount,
      dailyMortality: dailyMortality ?? mortality ?? this.dailyMortality,
      dailyCulls: dailyCulls ?? this.dailyCulls,
      transfersIn: transfersIn ?? this.transfersIn,
      transfersOut: transfersOut ?? this.transfersOut,
      partialDepletion: partialDepletion ?? this.partialDepletion,
      otherPopulationAdjustment:
          otherPopulationAdjustment ?? this.otherPopulationAdjustment,
      mortalityCauses: mortalityCauses ?? this.mortalityCauses,
      closingLiveBirdCount: closingLiveBirdCount ?? this.closingLiveBirdCount,
      dailyFeedConsumedKg: dailyFeedConsumedKg ?? this.dailyFeedConsumedKg,
      feedType: feedType ?? this.feedType,
      feedPhase: feedPhase ?? this.feedPhase,
      feedChange: feedChange ?? this.feedChange,
      feedInterruptionMinutes:
          feedInterruptionMinutes ?? this.feedInterruptionMinutes,
      feedShortage: feedShortage ?? this.feedShortage,
      waterConsumedLiters: waterConsumedLiters ?? this.waterConsumedLiters,
      flushingWaterLiters: flushingWaterLiters ?? this.flushingWaterLiters,
      waterInterruptionMinutes:
          waterInterruptionMinutes ?? this.waterInterruptionMinutes,
      waterMedication: waterMedication ?? this.waterMedication,
      waterVaccination: waterVaccination ?? this.waterVaccination,
      averageBodyWeightG: averageBodyWeightG ?? this.averageBodyWeightG,
      birdsWeighed: birdsWeighed ?? this.birdsWeighed,
      uniformityPct: uniformityPct ?? this.uniformityPct,
      cvPct: cvPct ?? this.cvPct,
      individualWeightsG: individualWeightsG ?? this.individualWeightsG,
      minTemperatureC: minTemperatureC ?? this.minTemperatureC,
      maxTemperatureC: maxTemperatureC ?? this.maxTemperatureC,
      averageTemperatureC: averageTemperatureC ?? this.averageTemperatureC,
      relativeHumidityPct: relativeHumidityPct ?? this.relativeHumidityPct,
      co2Ppm: co2Ppm ?? this.co2Ppm,
      ammoniaPpm: ammoniaPpm ?? this.ammoniaPpm,
      environmentIncident: environmentIncident ?? this.environmentIncident,
      clinicalSigns: clinicalSigns ?? this.clinicalSigns,
      treatmentStarted: treatmentStarted ?? this.treatmentStarted,
      treatmentStopped: treatmentStopped ?? this.treatmentStopped,
      vaccination: vaccination ?? this.vaccination,
      powerFailure: powerFailure ?? this.powerFailure,
      equipmentFailure: equipmentFailure ?? this.equipmentFailure,
      veterinaryObservation:
          veterinaryObservation ?? this.veterinaryObservation,
      notes: notes ?? this.notes,
      sources: sources ?? this.sources,
      events: events ?? this.events,
    );
  }
}

class BroilerDailyRevision {
  const BroilerDailyRevision({
    required this.id,
    required this.recordId,
    required this.revisionNumber,
    required this.facts,
    required this.createdAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  });

  final String id;
  final String recordId;
  final int revisionNumber;
  final BroilerDailyRecordDraft facts;
  final DateTime createdAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  VerificationStatus get verificationStatus => facts.verificationStatus;
  int? get openingBirdCount => facts.openingBirdCount;
  int? get dailyMortality => facts.dailyMortality;
  int? get dailyCulls => facts.dailyCulls;
  int? get closingLiveBirdCount => facts.closingLiveBirdCount;
  double? get dailyFeedConsumedKg => facts.dailyFeedConsumedKg;
  double? get waterConsumedLiters => facts.waterConsumedLiters;
  double? get averageBodyWeightG => facts.averageBodyWeightG;
  String? get correctionReason => facts.correctionReason;

  factory BroilerDailyRevision.fromMap(
    Map<String, Object?> map, {
    required String placementId,
    required DateTime recordDate,
  }) {
    return BroilerDailyRevision(
      id: map['id']! as String,
      recordId: map['recordId']! as String,
      revisionNumber: _integer(map['revisionNumber'])!,
      facts: BroilerDailyRecordDraft.fromRevisionMap(
        map,
        placementId: placementId,
        recordDate: recordDate,
      ),
      createdAt: DateTime.parse(map['createdAt']! as String),
      syncStatus: map['syncStatus']?.toString() ?? 'pending',
      dirtyAt: _date(map['dirtyAt']),
      lastSyncedAt: _date(map['lastSyncedAt']),
      syncError: map['syncError'] as String?,
    );
  }
}

class DailyRecordSourceDraft {
  const DailyRecordSourceDraft({
    required this.sourceKind,
    this.localPath,
    this.remoteStoragePath,
    this.originalFilename,
    this.checksum,
    this.uploadState = 'local',
    this.uploadError,
  });

  final DailyRecordSourceKind sourceKind;
  final String? localPath;
  final String? remoteStoragePath;
  final String? originalFilename;
  final String? checksum;
  final String uploadState;
  final String? uploadError;

  factory DailyRecordSourceDraft.fromMap(Map<String, Object?> map) {
    return DailyRecordSourceDraft(
      sourceKind: DailyRecordSourceKind.fromStorage(map['sourceKind']),
      localPath: map['localPath'] as String?,
      remoteStoragePath: map['remoteStoragePath'] as String?,
      originalFilename: map['originalFilename'] as String?,
      checksum: map['checksum'] as String?,
      uploadState: map['uploadState']?.toString() ?? 'local',
      uploadError: map['uploadError'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'sourceKind': sourceKind.storageKey,
      'localPath': localPath,
      'remoteStoragePath': remoteStoragePath,
      'originalFilename': originalFilename,
      'checksum': checksum,
      'uploadState': uploadState,
      'uploadError': uploadError,
    };
  }
}

class DailyRecordSource extends DailyRecordSourceDraft {
  const DailyRecordSource({
    required this.id,
    required this.revisionId,
    required super.sourceKind,
    super.localPath,
    super.remoteStoragePath,
    super.originalFilename,
    super.checksum,
    super.uploadState,
    super.uploadError,
    this.createdAt,
    this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  });

  final String id;
  final String revisionId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  factory DailyRecordSource.fromMap(Map<String, Object?> map) {
    final draft = DailyRecordSourceDraft.fromMap(map);
    return DailyRecordSource(
      id: map['id']! as String,
      revisionId: map['revisionId']! as String,
      sourceKind: draft.sourceKind,
      localPath: draft.localPath,
      remoteStoragePath: draft.remoteStoragePath,
      originalFilename: draft.originalFilename,
      checksum: draft.checksum,
      uploadState: draft.uploadState,
      uploadError: draft.uploadError,
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
      syncStatus: map['syncStatus']?.toString() ?? 'pending',
      dirtyAt: _date(map['dirtyAt']),
      lastSyncedAt: _date(map['lastSyncedAt']),
      syncError: map['syncError'] as String?,
    );
  }
}

class BroilerDailyEventDraft {
  const BroilerDailyEventDraft({
    required this.eventType,
    this.eventAt,
    this.isAllDay = true,
    this.eventState,
    this.description,
    this.treatment,
    this.vaccination,
    this.feedPhase,
    this.equipment,
  });

  final BroilerDailyEventType eventType;
  final DateTime? eventAt;
  final bool isAllDay;
  final DailyEventState? eventState;
  final String? description;
  final String? treatment;
  final String? vaccination;
  final String? feedPhase;
  final String? equipment;

  factory BroilerDailyEventDraft.fromMap(Map<String, Object?> map) {
    return BroilerDailyEventDraft(
      eventType: BroilerDailyEventType.fromStorage(map['eventType']),
      eventAt: _date(map['eventAt']),
      isAllDay: _bool(map['isAllDay']) ?? true,
      eventState: DailyEventState.fromStorage(map['eventState']),
      description: map['description'] as String?,
      treatment: map['treatment'] as String?,
      vaccination: map['vaccination'] as String?,
      feedPhase: map['feedPhase'] as String?,
      equipment: map['equipment'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'eventType': eventType.storageKey,
      'eventAt': eventAt?.toUtc().toIso8601String(),
      'isAllDay': isAllDay ? 1 : 0,
      'eventState': eventState?.storageKey,
      'description': description,
      'treatment': treatment,
      'vaccination': vaccination,
      'feedPhase': feedPhase,
      'equipment': equipment,
    };
  }
}

class BroilerDailyEvent extends BroilerDailyEventDraft {
  const BroilerDailyEvent({
    required this.id,
    required this.revisionId,
    required super.eventType,
    super.eventAt,
    super.isAllDay,
    super.eventState,
    super.description,
    super.treatment,
    super.vaccination,
    super.feedPhase,
    super.equipment,
    required this.createdAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  });

  final String id;
  final String revisionId;
  final DateTime createdAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  factory BroilerDailyEvent.fromMap(Map<String, Object?> map) {
    final draft = BroilerDailyEventDraft.fromMap(map);
    return BroilerDailyEvent(
      id: map['id']! as String,
      revisionId: map['revisionId']! as String,
      eventType: draft.eventType,
      eventAt: draft.eventAt,
      isAllDay: draft.isAllDay,
      eventState: draft.eventState,
      description: draft.description,
      treatment: draft.treatment,
      vaccination: draft.vaccination,
      feedPhase: draft.feedPhase,
      equipment: draft.equipment,
      createdAt: DateTime.parse(map['createdAt']! as String),
      syncStatus: map['syncStatus']?.toString() ?? 'pending',
      dirtyAt: _date(map['dirtyAt']),
      lastSyncedAt: _date(map['lastSyncedAt']),
      syncError: map['syncError'] as String?,
    );
  }
}

class SavedBroilerDailyRevision {
  const SavedBroilerDailyRevision({
    required this.record,
    required this.revision,
    this.sources = const [],
    this.events = const [],
  });

  final BroilerDailyRecord record;
  final BroilerDailyRevision revision;
  final List<DailyRecordSource> sources;
  final List<BroilerDailyEvent> events;
}

class BroilerDailyEntryGridRow {
  const BroilerDailyEntryGridRow({
    required this.placementId,
    required this.houseId,
    required this.houseName,
    required this.current,
  });

  final String placementId;
  final String houseId;
  final String houseName;
  final SavedBroilerDailyRevision? current;
}

class DailyRecordValidationException implements Exception {
  const DailyRecordValidationException(this.errors);

  final List<String> errors;

  @override
  String toString() => errors.join(' ');
}

String dateKey(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

DateTime? _date(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

double? _number(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int? _integer(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

bool? _bool(Object? value) {
  if (value == null) return null;
  return value == true || value == 1 || value.toString() == '1';
}

int? _databaseBool(bool? value) {
  if (value == null) return null;
  return value ? 1 : 0;
}

Map<String, int> _intMap(Object? value) {
  if (value == null || value.toString().isEmpty) return const {};
  final decoded = jsonDecode(value.toString()) as Map<String, dynamic>;
  return decoded.map((key, item) => MapEntry(key, (item as num).toInt()));
}

List<double> _doubleList(Object? value) {
  if (value == null || value.toString().isEmpty) return const [];
  final decoded = jsonDecode(value.toString()) as List<dynamic>;
  return decoded.map((item) => (item as num).toDouble()).toList();
}
