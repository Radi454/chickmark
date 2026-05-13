import 'panel_sample_schema.dart';

class PanelRecord {
  PanelRecord({
    required this.id,
    required this.tableName,
    required this.sessionId,
    this.auditId,
    required this.customerId,
    this.flockId,
    required this.date,
    this.hatcheryId,
    this.breed,
    this.flockAgeWeeks,
    this.mode = modePool,
    this.compareLayer,
    this.notes,
    this.metricsJson,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  static const modePool = 'pool';
  static const modeCompare = 'compare';

  final String id;
  final String tableName;
  final String sessionId;
  final String? auditId;
  final String customerId;
  final String? flockId;
  final DateTime date;
  final String? hatcheryId;
  final String? breed;
  final int? flockAgeWeeks;
  final String mode;
  final SamplingLayer? compareLayer;
  final String? notes;
  final String? metricsJson;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'sessionId': sessionId,
      'auditId': auditId,
      'customerId': customerId,
      'flockId': flockId,
      'date': date.toUtc().toIso8601String(),
      'hatcheryId': hatcheryId,
      'breed': breed,
      'flockAgeWeeks': flockAgeWeeks,
      'mode': mode,
      'compareLayer': compareLayer?.dbValue,
      'notes': notes,
      'metricsJson': metricsJson,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory PanelRecord.fromMap(String tableName, Map<String, Object?> map) {
    final compareLayer = map['compareLayer'] as String?;
    return PanelRecord(
      id: map['id'] as String,
      tableName: tableName,
      sessionId: map['sessionId'] as String,
      auditId: map['auditId'] as String?,
      customerId: map['customerId'] as String,
      flockId: map['flockId'] as String?,
      date: DateTime.parse(map['date'] as String),
      hatcheryId: map['hatcheryId'] as String?,
      breed: map['breed'] as String?,
      flockAgeWeeks: map['flockAgeWeeks'] as int?,
      mode: map['mode'] as String? ?? modePool,
      compareLayer: compareLayer == null
          ? null
          : SamplingLayer.fromDbValue(compareLayer),
      notes: map['notes'] as String?,
      metricsJson: map['metricsJson'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }
}

class PanelSampleRecord {
  PanelSampleRecord({
    required this.id,
    required this.panelId,
    this.scopeType = SamplingLayer.pool,
    String? scopeLabel,
    this.sampleIndex = 0,
    this.houseId,
    this.houseName,
    this.setterId,
    this.hatcherId,
    this.trolleyId,
    this.trolleyLabel,
    this.trayId,
    this.trayLabel,
    this.position,
    this.sampleSize,
    this.metricType,
    this.value,
    this.unit,
    this.summaryJson,
    this.rawJson,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : scopeLabel = scopeLabel ?? 'Random',
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String panelId;
  final SamplingLayer scopeType;
  final String scopeLabel;
  final int sampleIndex;
  final String? houseId;
  final String? houseName;
  final String? setterId;
  final String? hatcherId;
  final String? trolleyId;
  final String? trolleyLabel;
  final String? trayId;
  final String? trayLabel;
  final String? position;
  final int? sampleSize;
  final String? metricType;
  final double? value;
  final String? unit;
  final String? summaryJson;
  final String? rawJson;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'panelId': panelId,
      'scopeType': scopeType.dbValue,
      'scopeLabel': scopeLabel,
      'sampleIndex': sampleIndex,
      'houseId': houseId,
      'houseName': houseName,
      'setterId': setterId,
      'hatcherId': hatcherId,
      'trolleyId': trolleyId,
      'trolleyLabel': trolleyLabel,
      'trayId': trayId,
      'trayLabel': trayLabel,
      'position': position,
      'sampleSize': sampleSize,
      'metricType': metricType,
      'value': value,
      'unit': unit,
      'summaryJson': summaryJson,
      'rawJson': rawJson,
      'notes': notes,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory PanelSampleRecord.fromMap(Map<String, Object?> map) {
    return PanelSampleRecord(
      id: map['id'] as String,
      panelId: map['panelId'] as String,
      scopeType: SamplingLayer.fromDbValue(map['scopeType'] as String),
      scopeLabel: map['scopeLabel'] as String?,
      sampleIndex: map['sampleIndex'] as int? ?? 0,
      houseId: map['houseId'] as String?,
      houseName: map['houseName'] as String?,
      setterId: map['setterId'] as String?,
      hatcherId: map['hatcherId'] as String?,
      trolleyId: map['trolleyId'] as String?,
      trolleyLabel: map['trolleyLabel'] as String?,
      trayId: map['trayId'] as String?,
      trayLabel: map['trayLabel'] as String?,
      position: map['position'] as String?,
      sampleSize: map['sampleSize'] as int?,
      metricType: map['metricType'] as String?,
      value: (map['value'] as num?)?.toDouble(),
      unit: map['unit'] as String?,
      summaryJson: map['summaryJson'] as String?,
      rawJson: map['rawJson'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }
}
