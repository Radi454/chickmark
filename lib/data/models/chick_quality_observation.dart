class ChickQualityObservation {
  const ChickQualityObservation({
    required this.id,
    required this.sampleId,
    required this.customerId,
    required this.sessionId,
    required this.domain,
    required this.kind,
    required this.observationKey,
    required this.ordinal,
    required this.numericValue,
    required this.textValue,
    required this.unit,
    required this.qualityFlags,
    required this.source,
    required this.observedAt,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  });

  final String id;
  final String sampleId;
  final String customerId;
  final String sessionId;
  final String domain;
  final String kind;
  final String observationKey;
  final int? ordinal;
  final double? numericValue;
  final String? textValue;
  final String unit;
  final String qualityFlags;
  final String? source;
  final DateTime observedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  Map<String, Object?> toMap() => {
    'id': id,
    'sampleId': sampleId,
    'customerId': customerId,
    'sessionId': sessionId,
    'domain': domain,
    'kind': kind,
    'observationKey': observationKey,
    'ordinal': ordinal,
    'numericValue': numericValue,
    'textValue': textValue,
    'unit': unit,
    'qualityFlags': qualityFlags,
    'source': source,
    'observedAt': observedAt.toUtc().toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'syncStatus': syncStatus,
    'dirtyAt': dirtyAt?.toUtc().toIso8601String(),
    'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
    'syncError': syncError,
  };

  factory ChickQualityObservation.fromMap(Map<String, Object?> map) {
    return ChickQualityObservation(
      id: map['id']! as String,
      sampleId: map['sampleId']! as String,
      customerId: map['customerId']! as String,
      sessionId: map['sessionId']! as String,
      domain: map['domain']! as String,
      kind: map['kind']! as String,
      observationKey: map['observationKey']! as String,
      ordinal: map['ordinal'] as int?,
      numericValue: (map['numericValue'] as num?)?.toDouble(),
      textValue: map['textValue'] as String?,
      unit: map['unit']! as String,
      qualityFlags: (map['qualityFlags'] as String?) ?? '[]',
      source: map['source'] as String?,
      observedAt: DateTime.parse(map['observedAt']! as String),
      createdAt: DateTime.parse(map['createdAt']! as String),
      updatedAt: DateTime.parse(map['updatedAt']! as String),
      syncStatus: (map['syncStatus'] as String?) ?? 'pending',
      dirtyAt: _date(map['dirtyAt']),
      lastSyncedAt: _date(map['lastSyncedAt']),
      syncError: map['syncError'] as String?,
    );
  }

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString());
}
