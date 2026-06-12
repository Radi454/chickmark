import 'dart:convert';

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
  final String chartPointsJson;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Per-row sync state: 'pending' (local edit awaiting push), 'synced', or
  /// 'failed' (last push errored).
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

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
    String? chartPointsJson,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  }) : stationKey = _normalizedStationKey(stationKey, place),
       machineId = _asNullableString(machineId),
       chartPointsJson = _normalizedChartPointsJson(chartPointsJson);

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
      chartPointsJson: map['chartPointsJson'] as String?,
      createdAt: _parseDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(map['updatedAt']) ?? DateTime.now(),
      syncStatus: map['syncStatus'] as String? ?? 'synced',
      dirtyAt: _parseDate(map['dirtyAt']),
      lastSyncedAt: _parseDate(map['lastSyncedAt']),
      syncError: map['syncError'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerId': customerId,
      'hatcheryId': hatcheryId,
      'stationKey': stationKey,
      'place': place.name,
      // Both stores require machineId NOT NULL (SQLite DEFAULT '', cloud mirror);
      // the field is nullable only in memory, so serialize the '' sentinel.
      'machineId': machineId ?? '',
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
      'chartPointsJson': chartPointsJson,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'syncStatus': syncStatus,
      'dirtyAt': dirtyAt?.toIso8601String(),
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'syncError': syncError,
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
    String? chartPointsJson,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
    Object? dirtyAt = _copyUnset,
    Object? lastSyncedAt = _copyUnset,
    Object? syncError = _copyUnset,
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
      chartPointsJson: chartPointsJson ?? this.chartPointsJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      dirtyAt: identical(dirtyAt, _copyUnset)
          ? this.dirtyAt
          : dirtyAt as DateTime?,
      lastSyncedAt: identical(lastSyncedAt, _copyUnset)
          ? this.lastSyncedAt
          : lastSyncedAt as DateTime?,
      syncError: identical(syncError, _copyUnset)
          ? this.syncError
          : syncError as String?,
    );
  }

  List<GoveePlaceReadingModel> get chartReadings {
    return GoveePlaceReadingModel.listFromJson(
      chartPointsJson,
      captureId: id,
      createdAt: createdAt,
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

  Map<String, dynamic> toChartPointJson() {
    return {
      't': recordedAt.toIso8601String(),
      'temp': temperatureFahrenheit,
      'rh': humidity,
    };
  }

  static String listToJson(List<GoveePlaceReadingModel> readings) {
    if (readings.isEmpty) return '[]';
    return jsonEncode(
      readings.map((reading) => reading.toChartPointJson()).toList(),
    );
  }

  static List<GoveePlaceReadingModel> listFromJson(
    String? json, {
    required String captureId,
    required DateTime createdAt,
  }) {
    if (json == null || json.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return decoded
          .asMap()
          .entries
          .map((entry) {
            final point = entry.value as Map<String, dynamic>;
            final recordedAt = _parseDate(point['t']) ?? createdAt;
            return GoveePlaceReadingModel(
              id: '$captureId-${entry.key}',
              captureId: captureId,
              readingIndex: entry.key,
              recordedAt: recordedAt,
              temperatureFahrenheit: _asDouble(point['temp']) ?? 0,
              humidity: _asDouble(point['rh']) ?? 0,
              createdAt: createdAt,
            );
          })
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
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

String _normalizedChartPointsJson(String? json) {
  final trimmed = json?.trim();
  if (trimmed == null || trimmed.isEmpty) return '[]';
  return trimmed;
}
