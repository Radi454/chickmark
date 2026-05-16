import 'panel_sample_schema.dart';

class PanelRecord {
  PanelRecord({
    required this.id,
    required this.tableName,
    required this.sessionId,
    required this.customerId,
    this.flockId,
    this.hatcheryId,
    required this.date,
    this.breed,
    this.flockAgeWeeks,
    this.mode = modePool,
    SamplingLayer? scopeType,
    SamplingLayer? compareLayer,
    String? scopeLabel,
    this.sampleIndex = 0,
    this.groupKey,
    this.groupLabel,
    this.notes,
    String? metricsJson,
    this.syncStatus = 'pending',
    this.lastSyncedAt,
    this.syncError,
    Map<String, Object?>? values,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : scopeType = scopeType ?? compareLayer ?? SamplingLayer.pool,
       scopeLabel = scopeLabel ?? 'Random',
       values = {
         ...(metricsJson == null
             ? const <String, Object?>{}
             : {'metricsJson': metricsJson}),
         ...?values,
       },
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  static const modePool = 'pool';
  static const modeComparison = 'comparison';
  static const modeCompare = modeComparison;

  final String id;
  final String tableName;
  final String sessionId;
  final String customerId;
  final String? flockId;
  final String? hatcheryId;
  final DateTime date;
  final String? breed;
  final int? flockAgeWeeks;
  final String mode;
  final SamplingLayer scopeType;
  final String scopeLabel;
  final int sampleIndex;
  final String? groupKey;
  final String? groupLabel;
  final String? notes;
  final String syncStatus;
  final DateTime? lastSyncedAt;
  final String? syncError;
  final Map<String, Object?> values;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'sessionId': sessionId,
      'customerId': customerId,
      'flockId': flockId,
      'hatcheryId': hatcheryId,
      'date': _dateOnly(date),
      'breed': breed,
      'flockAgeWeeks': flockAgeWeeks,
      'mode': mode,
      'scopeType': scopeType.dbValue,
      'scopeLabel': scopeLabel,
      'sampleIndex': sampleIndex,
      'groupKey': groupKey,
      'groupLabel': groupLabel,
      'notes': notes,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'syncStatus': syncStatus,
      'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
      'syncError': syncError,
      ...values,
    };
  }

  factory PanelRecord.fromMap(String tableName, Map<String, Object?> map) {
    final knownKeys = {
      'id',
      'sessionId',
      'customerId',
      'flockId',
      'hatcheryId',
      'date',
      'breed',
      'flockAgeWeeks',
      'mode',
      'scopeType',
      'scopeLabel',
      'sampleIndex',
      'groupKey',
      'groupLabel',
      'notes',
      'createdAt',
      'updatedAt',
      'syncStatus',
      'lastSyncedAt',
      'syncError',
    };
    return PanelRecord(
      id: map['id'] as String,
      tableName: tableName,
      sessionId: map['sessionId'] as String,
      customerId: map['customerId'] as String,
      flockId: map['flockId'] as String?,
      date: DateTime.parse(map['date'] as String),
      hatcheryId: map['hatcheryId'] as String?,
      breed: map['breed'] as String?,
      flockAgeWeeks: map['flockAgeWeeks'] as int?,
      mode: map['mode'] as String? ?? modePool,
      scopeType: SamplingLayer.fromDbValue(
        map['scopeType'] as String? ?? SamplingLayer.pool.dbValue,
      ),
      scopeLabel: map['scopeLabel'] as String?,
      sampleIndex: map['sampleIndex'] as int? ?? 0,
      groupKey: map['groupKey'] as String?,
      groupLabel: map['groupLabel'] as String?,
      notes: map['notes'] as String?,
      syncStatus: map['syncStatus'] as String? ?? 'synced',
      lastSyncedAt: _parseDate(map['lastSyncedAt']),
      syncError: map['syncError'] as String?,
      values: Map.fromEntries(
        map.entries.where((entry) => !knownKeys.contains(entry.key)),
      ),
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  static String _dateOnly(DateTime value) {
    final utc = value.toUtc();
    final year = utc.year.toString().padLeft(4, '0');
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
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
