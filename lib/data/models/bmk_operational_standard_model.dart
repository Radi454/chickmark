class BmkOperationalStandardModel {
  final String id;
  final String? hatcheryId;
  final String stationKey;
  final String sectorKey;
  final String metricKey;
  final String metricLabel;
  final String unit;
  final double? minValue;
  final double? maxValue;
  final double? targetValue;
  final String? source;
  final String? notes;
  final int sortOrder;
  final String? updatedAt;

  const BmkOperationalStandardModel({
    required this.id,
    this.hatcheryId,
    required this.stationKey,
    required this.sectorKey,
    required this.metricKey,
    required this.metricLabel,
    required this.unit,
    this.minValue,
    this.maxValue,
    this.targetValue,
    this.source,
    this.notes,
    required this.sortOrder,
    this.updatedAt,
  });

  factory BmkOperationalStandardModel.fromMap(Map<String, Object?> map) {
    return BmkOperationalStandardModel(
      id: map['id'] as String,
      hatcheryId: map['hatcheryId'] as String?,
      stationKey: map['stationKey'] as String,
      sectorKey: map['sectorKey'] as String,
      metricKey: map['metricKey'] as String,
      metricLabel: map['metricLabel'] as String,
      unit: map['unit'] as String? ?? '',
      minValue: _asDouble(map['minValue']),
      maxValue: _asDouble(map['maxValue']),
      targetValue: _asDouble(map['targetValue']),
      source: map['source'] as String?,
      notes: map['notes'] as String?,
      sortOrder: _asInt(map['sortOrder']) ?? 0,
      updatedAt: map['updatedAt'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'hatcheryId': hatcheryId,
      'stationKey': stationKey,
      'sectorKey': sectorKey,
      'metricKey': metricKey,
      'metricLabel': metricLabel,
      'unit': unit,
      'minValue': minValue,
      'maxValue': maxValue,
      'targetValue': targetValue,
      'source': source,
      'notes': notes,
      'sortOrder': sortOrder,
      'updatedAt': updatedAt,
    };
  }

  BmkOperationalStandardModel copyWith({
    String? id,
    Object? hatcheryId = _sentinel,
    String? stationKey,
    String? sectorKey,
    String? metricKey,
    String? metricLabel,
    String? unit,
    Object? minValue = _sentinel,
    Object? maxValue = _sentinel,
    Object? targetValue = _sentinel,
    Object? source = _sentinel,
    Object? notes = _sentinel,
    int? sortOrder,
    Object? updatedAt = _sentinel,
  }) {
    return BmkOperationalStandardModel(
      id: id ?? this.id,
      hatcheryId: hatcheryId == _sentinel
          ? this.hatcheryId
          : hatcheryId as String?,
      stationKey: stationKey ?? this.stationKey,
      sectorKey: sectorKey ?? this.sectorKey,
      metricKey: metricKey ?? this.metricKey,
      metricLabel: metricLabel ?? this.metricLabel,
      unit: unit ?? this.unit,
      minValue: minValue == _sentinel ? this.minValue : minValue as double?,
      maxValue: maxValue == _sentinel ? this.maxValue : maxValue as double?,
      targetValue: targetValue == _sentinel
          ? this.targetValue
          : targetValue as double?,
      source: source == _sentinel ? this.source : source as String?,
      notes: notes == _sentinel ? this.notes : notes as String?,
      sortOrder: sortOrder ?? this.sortOrder,
      updatedAt: updatedAt == _sentinel ? this.updatedAt : updatedAt as String?,
    );
  }

  static double? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class BmkOperationalHatcheryOption {
  final String id;
  final String label;

  const BmkOperationalHatcheryOption({required this.id, required this.label});
}

const Object _sentinel = Object();
