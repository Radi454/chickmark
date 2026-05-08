import 'temperature_rh_model.dart';

class GoveeDailyCaptureModel {
  final String id;
  final String customerId;
  final String hatcheryId;
  final String stationKey;
  final TemperaturePlace place;
  final String? machineId;
  final String captureDate;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? deviceId;
  final String? deviceName;
  final String status;
  final double? tempAvg;
  final double? tempMin;
  final double? tempMax;
  final double? tempSd;
  final double? tempCvPct;
  final double? rhAvg;
  final double? rhMin;
  final double? rhMax;
  final double? rhSd;
  final double? rhCvPct;
  final int readingCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  GoveeDailyCaptureModel({
    required this.id,
    required this.customerId,
    required this.hatcheryId,
    String? stationKey,
    required this.place,
    String? machineId,
    required this.captureDate,
    this.startedAt,
    this.endedAt,
    this.deviceId,
    this.deviceName,
    required this.status,
    this.tempAvg,
    this.tempMin,
    this.tempMax,
    this.tempSd,
    this.tempCvPct,
    this.rhAvg,
    this.rhMin,
    this.rhMax,
    this.rhSd,
    this.rhCvPct,
    required this.readingCount,
    required this.createdAt,
    required this.updatedAt,
  }) : stationKey = _normalizedStationKey(stationKey, place),
       machineId = _asNullableString(machineId);

  factory GoveeDailyCaptureModel.fromMap(Map<String, dynamic> map) {
    final place = temperaturePlaceFromName(map['place'] as String?);
    return GoveeDailyCaptureModel(
      id: map['id'] as String,
      customerId: map['customerId'] as String,
      hatcheryId: map['hatcheryId'] as String,
      stationKey: _asNullableString(map['stationKey']),
      place: place,
      machineId: _asNullableString(map['machineId']),
      captureDate: map['captureDate'] as String,
      startedAt: _parseDate(map['startedAt']),
      endedAt: _parseDate(map['endedAt']),
      deviceId: map['deviceId'] as String?,
      deviceName: map['deviceName'] as String?,
      status: map['status'] as String? ?? 'completed',
      tempAvg: _asDouble(map['tempAvg']),
      tempMin: _asDouble(map['tempMin']),
      tempMax: _asDouble(map['tempMax']),
      tempSd: _asDouble(map['tempSd']),
      tempCvPct: _asDouble(map['tempCvPct']),
      rhAvg: _asDouble(map['rhAvg']),
      rhMin: _asDouble(map['rhMin']),
      rhMax: _asDouble(map['rhMax']),
      rhSd: _asDouble(map['rhSd']),
      rhCvPct: _asDouble(map['rhCvPct']),
      readingCount: _asInt(map['readingCount']) ?? 0,
      createdAt: _parseDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(map['updatedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerId': customerId,
      'hatcheryId': hatcheryId,
      'stationKey': stationKey,
      'place': place.name,
      'machineId': machineId,
      'captureDate': captureDate,
      'startedAt': startedAt?.toIso8601String(),
      'endedAt': endedAt?.toIso8601String(),
      'deviceId': deviceId,
      'deviceName': deviceName,
      'status': status,
      'tempAvg': tempAvg,
      'tempMin': tempMin,
      'tempMax': tempMax,
      'tempSd': tempSd,
      'tempCvPct': tempCvPct,
      'rhAvg': rhAvg,
      'rhMin': rhMin,
      'rhMax': rhMax,
      'rhSd': rhSd,
      'rhCvPct': rhCvPct,
      'readingCount': readingCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  GoveeDailyCaptureModel copyWith({
    String? id,
    String? customerId,
    String? hatcheryId,
    String? stationKey,
    TemperaturePlace? place,
    Object? machineId = _copyUnset,
    String? captureDate,
    Object? startedAt = _copyUnset,
    Object? endedAt = _copyUnset,
    String? deviceId,
    String? deviceName,
    String? status,
    double? tempAvg,
    double? tempMin,
    double? tempMax,
    double? tempSd,
    double? tempCvPct,
    double? rhAvg,
    double? rhMin,
    double? rhMax,
    double? rhSd,
    double? rhCvPct,
    int? readingCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final nextPlace = place ?? this.place;
    return GoveeDailyCaptureModel(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      hatcheryId: hatcheryId ?? this.hatcheryId,
      stationKey:
          stationKey ??
          (place == null
              ? this.stationKey
              : goveeStationKeyForTemperaturePlace(nextPlace)),
      place: nextPlace,
      machineId: identical(machineId, _copyUnset)
          ? this.machineId
          : machineId as String?,
      captureDate: captureDate ?? this.captureDate,
      startedAt: identical(startedAt, _copyUnset)
          ? this.startedAt
          : startedAt as DateTime?,
      endedAt: identical(endedAt, _copyUnset)
          ? this.endedAt
          : endedAt as DateTime?,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      status: status ?? this.status,
      tempAvg: tempAvg ?? this.tempAvg,
      tempMin: tempMin ?? this.tempMin,
      tempMax: tempMax ?? this.tempMax,
      tempSd: tempSd ?? this.tempSd,
      tempCvPct: tempCvPct ?? this.tempCvPct,
      rhAvg: rhAvg ?? this.rhAvg,
      rhMin: rhMin ?? this.rhMin,
      rhMax: rhMax ?? this.rhMax,
      rhSd: rhSd ?? this.rhSd,
      rhCvPct: rhCvPct ?? this.rhCvPct,
      readingCount: readingCount ?? this.readingCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class GoveePlaceReadingModel {
  final String id;
  final String captureId;
  final int readingIndex;
  final DateTime recordedAt;
  final double temperatureFahrenheit;
  final double humidity;
  final DateTime createdAt;

  const GoveePlaceReadingModel({
    required this.id,
    required this.captureId,
    required this.readingIndex,
    required this.recordedAt,
    required this.temperatureFahrenheit,
    required this.humidity,
    required this.createdAt,
  });

  factory GoveePlaceReadingModel.fromMap(Map<String, dynamic> map) {
    return GoveePlaceReadingModel(
      id: map['id'] as String,
      captureId: map['captureId'] as String,
      readingIndex: _asInt(map['readingIndex']) ?? 0,
      recordedAt: _parseDate(map['recordedAt']) ?? DateTime.now(),
      temperatureFahrenheit: _asDouble(map['temperatureFahrenheit']) ?? 0.0,
      humidity: _asDouble(map['humidity']) ?? 0.0,
      createdAt: _parseDate(map['createdAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'captureId': captureId,
      'readingIndex': readingIndex,
      'recordedAt': recordedAt.toIso8601String(),
      'temperatureFahrenheit': temperatureFahrenheit,
      'humidity': humidity,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  GoveePlaceReadingModel copyWith({
    String? id,
    String? captureId,
    int? readingIndex,
    DateTime? recordedAt,
    double? temperatureFahrenheit,
    double? humidity,
    DateTime? createdAt,
  }) {
    return GoveePlaceReadingModel(
      id: id ?? this.id,
      captureId: captureId ?? this.captureId,
      readingIndex: readingIndex ?? this.readingIndex,
      recordedAt: recordedAt ?? this.recordedAt,
      temperatureFahrenheit:
          temperatureFahrenheit ?? this.temperatureFahrenheit,
      humidity: humidity ?? this.humidity,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

const Object _copyUnset = Object();

String _normalizedStationKey(String? stationKey, TemperaturePlace place) {
  final trimmed = stationKey?.trim();
  if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  return goveeStationKeyForTemperaturePlace(place);
}

String? _asNullableString(dynamic value) {
  if (value == null) return null;
  final trimmed = value.toString().trim();
  return trimmed.isEmpty ? null : trimmed;
}

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
