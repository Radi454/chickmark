import 'temperature_rh_model.dart';

class GoveeDailyCaptureModel {
  final String id;
  final String customerId;
  final String hatcheryId;
  final TemperaturePlace place;
  final String captureDate;
  final String? deviceId;
  final String? deviceName;
  final String status;
  final double? tempAvg;
  final double? tempMin;
  final double? tempMax;
  final double? rhAvg;
  final double? rhMin;
  final double? rhMax;
  final int spotCount;
  final int readingCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GoveeDailyCaptureModel({
    required this.id,
    required this.customerId,
    required this.hatcheryId,
    required this.place,
    required this.captureDate,
    this.deviceId,
    this.deviceName,
    required this.status,
    this.tempAvg,
    this.tempMin,
    this.tempMax,
    this.rhAvg,
    this.rhMin,
    this.rhMax,
    required this.spotCount,
    required this.readingCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GoveeDailyCaptureModel.fromMap(Map<String, dynamic> map) {
    return GoveeDailyCaptureModel(
      id: map['id'] as String,
      customerId: map['customerId'] as String,
      hatcheryId: map['hatcheryId'] as String,
      place: temperaturePlaceFromName(map['place'] as String?),
      captureDate: map['captureDate'] as String,
      deviceId: map['deviceId'] as String?,
      deviceName: map['deviceName'] as String?,
      status: map['status'] as String? ?? 'completed',
      tempAvg: _asDouble(map['tempAvg']),
      tempMin: _asDouble(map['tempMin']),
      tempMax: _asDouble(map['tempMax']),
      rhAvg: _asDouble(map['rhAvg']),
      rhMin: _asDouble(map['rhMin']),
      rhMax: _asDouble(map['rhMax']),
      spotCount: _asInt(map['spotCount']) ?? 0,
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
      'place': place.name,
      'captureDate': captureDate,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'status': status,
      'tempAvg': tempAvg,
      'tempMin': tempMin,
      'tempMax': tempMax,
      'rhAvg': rhAvg,
      'rhMin': rhMin,
      'rhMax': rhMax,
      'spotCount': spotCount,
      'readingCount': readingCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  GoveeDailyCaptureModel copyWith({
    String? id,
    String? customerId,
    String? hatcheryId,
    TemperaturePlace? place,
    String? captureDate,
    String? deviceId,
    String? deviceName,
    String? status,
    double? tempAvg,
    double? tempMin,
    double? tempMax,
    double? rhAvg,
    double? rhMin,
    double? rhMax,
    int? spotCount,
    int? readingCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GoveeDailyCaptureModel(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      hatcheryId: hatcheryId ?? this.hatcheryId,
      place: place ?? this.place,
      captureDate: captureDate ?? this.captureDate,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      status: status ?? this.status,
      tempAvg: tempAvg ?? this.tempAvg,
      tempMin: tempMin ?? this.tempMin,
      tempMax: tempMax ?? this.tempMax,
      rhAvg: rhAvg ?? this.rhAvg,
      rhMin: rhMin ?? this.rhMin,
      rhMax: rhMax ?? this.rhMax,
      spotCount: spotCount ?? this.spotCount,
      readingCount: readingCount ?? this.readingCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class GoveeSpotCaptureModel {
  final String id;
  final String captureId;
  final int spotIndex;
  final String spotLabel;
  final DateTime warmupStartedAt;
  final DateTime validStartedAt;
  final DateTime validEndedAt;
  final int validDurationSeconds;
  final double? tempAvg;
  final double? tempMin;
  final double? tempMax;
  final double? rhAvg;
  final double? rhMin;
  final double? rhMax;
  final int readingCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GoveeSpotCaptureModel({
    required this.id,
    required this.captureId,
    required this.spotIndex,
    required this.spotLabel,
    required this.warmupStartedAt,
    required this.validStartedAt,
    required this.validEndedAt,
    required this.validDurationSeconds,
    this.tempAvg,
    this.tempMin,
    this.tempMax,
    this.rhAvg,
    this.rhMin,
    this.rhMax,
    required this.readingCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GoveeSpotCaptureModel.fromMap(Map<String, dynamic> map) {
    return GoveeSpotCaptureModel(
      id: map['id'] as String,
      captureId: map['captureId'] as String,
      spotIndex: _asInt(map['spotIndex']) ?? 1,
      spotLabel: map['spotLabel'] as String? ?? 'Spot 1',
      warmupStartedAt: _parseDate(map['warmupStartedAt']) ?? DateTime.now(),
      validStartedAt: _parseDate(map['validStartedAt']) ?? DateTime.now(),
      validEndedAt: _parseDate(map['validEndedAt']) ?? DateTime.now(),
      validDurationSeconds: _asInt(map['validDurationSeconds']) ?? 0,
      tempAvg: _asDouble(map['tempAvg']),
      tempMin: _asDouble(map['tempMin']),
      tempMax: _asDouble(map['tempMax']),
      rhAvg: _asDouble(map['rhAvg']),
      rhMin: _asDouble(map['rhMin']),
      rhMax: _asDouble(map['rhMax']),
      readingCount: _asInt(map['readingCount']) ?? 0,
      createdAt: _parseDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(map['updatedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'captureId': captureId,
      'spotIndex': spotIndex,
      'spotLabel': spotLabel,
      'warmupStartedAt': warmupStartedAt.toIso8601String(),
      'validStartedAt': validStartedAt.toIso8601String(),
      'validEndedAt': validEndedAt.toIso8601String(),
      'validDurationSeconds': validDurationSeconds,
      'tempAvg': tempAvg,
      'tempMin': tempMin,
      'tempMax': tempMax,
      'rhAvg': rhAvg,
      'rhMin': rhMin,
      'rhMax': rhMax,
      'readingCount': readingCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  GoveeSpotCaptureModel copyWith({
    String? id,
    String? captureId,
    int? spotIndex,
    String? spotLabel,
    DateTime? warmupStartedAt,
    DateTime? validStartedAt,
    DateTime? validEndedAt,
    int? validDurationSeconds,
    double? tempAvg,
    double? tempMin,
    double? tempMax,
    double? rhAvg,
    double? rhMin,
    double? rhMax,
    int? readingCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GoveeSpotCaptureModel(
      id: id ?? this.id,
      captureId: captureId ?? this.captureId,
      spotIndex: spotIndex ?? this.spotIndex,
      spotLabel: spotLabel ?? this.spotLabel,
      warmupStartedAt: warmupStartedAt ?? this.warmupStartedAt,
      validStartedAt: validStartedAt ?? this.validStartedAt,
      validEndedAt: validEndedAt ?? this.validEndedAt,
      validDurationSeconds: validDurationSeconds ?? this.validDurationSeconds,
      tempAvg: tempAvg ?? this.tempAvg,
      tempMin: tempMin ?? this.tempMin,
      tempMax: tempMax ?? this.tempMax,
      rhAvg: rhAvg ?? this.rhAvg,
      rhMin: rhMin ?? this.rhMin,
      rhMax: rhMax ?? this.rhMax,
      readingCount: readingCount ?? this.readingCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class GoveeSpotReadingModel {
  final String id;
  final String captureId;
  final String spotId;
  final int readingIndex;
  final DateTime recordedAt;
  final double temperatureFahrenheit;
  final double humidity;
  final int? rssi;
  final String? deviceName;
  final DateTime createdAt;

  const GoveeSpotReadingModel({
    required this.id,
    required this.captureId,
    required this.spotId,
    required this.readingIndex,
    required this.recordedAt,
    required this.temperatureFahrenheit,
    required this.humidity,
    this.rssi,
    this.deviceName,
    required this.createdAt,
  });

  factory GoveeSpotReadingModel.fromMap(Map<String, dynamic> map) {
    return GoveeSpotReadingModel(
      id: map['id'] as String,
      captureId: map['captureId'] as String,
      spotId: map['spotId'] as String,
      readingIndex: _asInt(map['readingIndex']) ?? 0,
      recordedAt: _parseDate(map['recordedAt']) ?? DateTime.now(),
      temperatureFahrenheit: _asDouble(map['temperatureFahrenheit']) ?? 0.0,
      humidity: _asDouble(map['humidity']) ?? 0.0,
      rssi: _asInt(map['rssi']),
      deviceName: map['deviceName'] as String?,
      createdAt: _parseDate(map['createdAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'captureId': captureId,
      'spotId': spotId,
      'readingIndex': readingIndex,
      'recordedAt': recordedAt.toIso8601String(),
      'temperatureFahrenheit': temperatureFahrenheit,
      'humidity': humidity,
      'rssi': rssi,
      'deviceName': deviceName,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  GoveeSpotReadingModel copyWith({
    String? id,
    String? captureId,
    String? spotId,
    int? readingIndex,
    DateTime? recordedAt,
    double? temperatureFahrenheit,
    double? humidity,
    int? rssi,
    String? deviceName,
    DateTime? createdAt,
  }) {
    return GoveeSpotReadingModel(
      id: id ?? this.id,
      captureId: captureId ?? this.captureId,
      spotId: spotId ?? this.spotId,
      readingIndex: readingIndex ?? this.readingIndex,
      recordedAt: recordedAt ?? this.recordedAt,
      temperatureFahrenheit:
          temperatureFahrenheit ?? this.temperatureFahrenheit,
      humidity: humidity ?? this.humidity,
      rssi: rssi ?? this.rssi,
      deviceName: deviceName ?? this.deviceName,
      createdAt: createdAt ?? this.createdAt,
    );
  }
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
