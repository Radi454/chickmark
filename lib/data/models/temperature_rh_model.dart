import 'dart:convert';

enum TemperaturePlace {
  outsideHatchery('Outside hatchery'),
  eggStorageRoom('Egg storage room'),
  chickHoldingArea('Chick holding area'),
  setterRoom('Setter room'),
  insideSetter('Inside setter'),
  hatcherRoom('Hatcher room'),
  insideHatcher('Inside hatcher');

  final String label;
  const TemperaturePlace(this.label);
}

TemperaturePlace temperaturePlaceFromName(String? name) {
  if (name == 'incubatorRoom') return TemperaturePlace.setterRoom;
  if (name == 'insideIncubator') return TemperaturePlace.insideSetter;
  return TemperaturePlace.values.firstWhere(
    (place) => place.name == name,
    orElse: () => TemperaturePlace.outsideHatchery,
  );
}

String goveeStationKeyForTemperaturePlace(TemperaturePlace place) {
  return switch (place) {
    TemperaturePlace.eggStorageRoom => 'egg',
    TemperaturePlace.chickHoldingArea => 'chicks',
    TemperaturePlace.setterRoom || TemperaturePlace.insideSetter => 'setters',
    TemperaturePlace.hatcherRoom ||
    TemperaturePlace.insideHatcher => 'hatchers',
    TemperaturePlace.outsideHatchery => '',
  };
}

class ChartPoint {
  final DateTime timestamp;
  final double value;

  const ChartPoint({required this.timestamp, required this.value});

  factory ChartPoint.fromJson(Map<String, dynamic> json) {
    return ChartPoint(
      timestamp: DateTime.parse(json['t'] as String),
      value: (json['v'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'t': timestamp.toIso8601String(), 'v': value};
  }

  static List<ChartPoint> listFromJson(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded
            .map((e) => ChartPoint.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static String listToJson(List<ChartPoint>? points) {
    if (points == null || points.isEmpty) {
      return '[]';
    }
    return jsonEncode(points.map((p) => p.toJson()).toList());
  }
}

class TemperatureSessionModel {
  final String id;
  final String customerId;
  final String hatcheryId;
  final String? deviceId;
  final String? deviceName;
  final String? spotLabel;
  final String? captureSource;
  final DateTime startedAt;
  final DateTime? endedAt;
  final TemperaturePlace activePlace;
  final String status;
  final double? tempAvg;
  final double? tempMin;
  final double? tempMax;
  final double? tempCvPct;
  final double? rhAvg;
  final double? rhMin;
  final double? rhMax;
  final double? rhCvPct;
  final int? readingCount;
  final int? alertCount;
  final String? tempChartPointsJson;
  final String? rhChartPointsJson;
  final int warmupSeconds;
  final String? auditSessionId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TemperatureSessionModel({
    required this.id,
    required this.customerId,
    required this.hatcheryId,
    this.deviceId,
    this.deviceName,
    this.spotLabel,
    this.captureSource,
    required this.startedAt,
    this.endedAt,
    required this.activePlace,
    required this.status,
    this.tempAvg,
    this.tempMin,
    this.tempMax,
    this.tempCvPct,
    this.rhAvg,
    this.rhMin,
    this.rhMax,
    this.rhCvPct,
    this.readingCount,
    this.alertCount,
    this.tempChartPointsJson,
    this.rhChartPointsJson,
    this.warmupSeconds = 120,
    this.auditSessionId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TemperatureSessionModel.fromMap(Map<String, dynamic> map) {
    return TemperatureSessionModel(
      id: map['id'] as String,
      customerId: map['customerId'] as String,
      hatcheryId: map['hatcheryId'] as String,
      deviceId: map['deviceId'] as String?,
      deviceName: map['deviceName'] as String?,
      spotLabel: map['spotLabel'] as String?,
      captureSource: map['captureSource'] as String?,
      startedAt:
          DateTime.tryParse(map['startedAt'] as String? ?? '') ??
          DateTime.now(),
      endedAt: map['endedAt'] == null
          ? null
          : DateTime.tryParse(map['endedAt'] as String),
      activePlace: temperaturePlaceFromName(map['activePlace'] as String?),
      status: map['status'] as String? ?? 'active',
      tempAvg: map['tempAvg']?.toDouble(),
      tempMin: map['tempMin']?.toDouble(),
      tempMax: map['tempMax']?.toDouble(),
      tempCvPct: map['tempCvPct']?.toDouble(),
      rhAvg: map['rhAvg']?.toDouble(),
      rhMin: map['rhMin']?.toDouble(),
      rhMax: map['rhMax']?.toDouble(),
      rhCvPct: map['rhCvPct']?.toDouble(),
      readingCount: map['readingCount'] as int?,
      alertCount: map['alertCount'] as int?,
      tempChartPointsJson: map['tempChartPointsJson'] as String?,
      rhChartPointsJson: map['rhChartPointsJson'] as String?,
      warmupSeconds: map['warmupSeconds'] as int? ?? 120,
      auditSessionId: map['auditSessionId'] as String?,
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerId': customerId,
      'hatcheryId': hatcheryId,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'spotLabel': spotLabel,
      'captureSource': captureSource,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': endedAt?.toIso8601String(),
      'activePlace': activePlace.name,
      'status': status,
      'tempAvg': tempAvg,
      'tempMin': tempMin,
      'tempMax': tempMax,
      'tempCvPct': tempCvPct,
      'rhAvg': rhAvg,
      'rhMin': rhMin,
      'rhMax': rhMax,
      'rhCvPct': rhCvPct,
      'readingCount': readingCount,
      'alertCount': alertCount,
      'tempChartPointsJson': tempChartPointsJson,
      'rhChartPointsJson': rhChartPointsJson,
      'warmupSeconds': warmupSeconds,
      'auditSessionId': auditSessionId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  TemperatureSessionModel copyWith({
    String? deviceId,
    String? deviceName,
    String? spotLabel,
    String? captureSource,
    DateTime? endedAt,
    TemperaturePlace? activePlace,
    String? status,
    double? tempAvg,
    double? tempMin,
    double? tempMax,
    double? tempCvPct,
    double? rhAvg,
    double? rhMin,
    double? rhMax,
    double? rhCvPct,
    int? readingCount,
    int? alertCount,
    String? tempChartPointsJson,
    String? rhChartPointsJson,
    int? warmupSeconds,
    String? auditSessionId,
    DateTime? updatedAt,
  }) {
    return TemperatureSessionModel(
      id: id,
      customerId: customerId,
      hatcheryId: hatcheryId,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      spotLabel: spotLabel ?? this.spotLabel,
      captureSource: captureSource ?? this.captureSource,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      activePlace: activePlace ?? this.activePlace,
      status: status ?? this.status,
      tempAvg: tempAvg ?? this.tempAvg,
      tempMin: tempMin ?? this.tempMin,
      tempMax: tempMax ?? this.tempMax,
      tempCvPct: tempCvPct ?? this.tempCvPct,
      rhAvg: rhAvg ?? this.rhAvg,
      rhMin: rhMin ?? this.rhMin,
      rhMax: rhMax ?? this.rhMax,
      rhCvPct: rhCvPct ?? this.rhCvPct,
      readingCount: readingCount ?? this.readingCount,
      alertCount: alertCount ?? this.alertCount,
      tempChartPointsJson: tempChartPointsJson ?? this.tempChartPointsJson,
      rhChartPointsJson: rhChartPointsJson ?? this.rhChartPointsJson,
      warmupSeconds: warmupSeconds ?? this.warmupSeconds,
      auditSessionId: auditSessionId ?? this.auditSessionId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  List<ChartPoint> get tempChartPoints =>
      ChartPoint.listFromJson(tempChartPointsJson);

  List<ChartPoint> get rhChartPoints =>
      ChartPoint.listFromJson(rhChartPointsJson);
}

class TemperatureReadingModel {
  final String id;
  final String sessionId;
  final String customerId;
  final String hatcheryId;
  final TemperaturePlace place;
  final double temperatureFahrenheit;
  final double humidity;
  final int? rssi;
  final String? deviceName;
  final DateTime recordedAt;
  final DateTime createdAt;

  const TemperatureReadingModel({
    required this.id,
    required this.sessionId,
    required this.customerId,
    required this.hatcheryId,
    required this.place,
    required this.temperatureFahrenheit,
    required this.humidity,
    this.rssi,
    this.deviceName,
    required this.recordedAt,
    required this.createdAt,
  });

  factory TemperatureReadingModel.fromMap(Map<String, dynamic> map) {
    return TemperatureReadingModel(
      id: map['id'] as String,
      sessionId: map['sessionId'] as String,
      customerId: map['customerId'] as String,
      hatcheryId: map['hatcheryId'] as String,
      place: temperaturePlaceFromName(map['place'] as String?),
      temperatureFahrenheit: (map['temperatureFahrenheit'] as num).toDouble(),
      humidity: (map['humidity'] as num).toDouble(),
      rssi: map['rssi'] as int?,
      deviceName: map['deviceName'] as String?,
      recordedAt:
          DateTime.tryParse(map['recordedAt'] as String? ?? '') ??
          DateTime.now(),
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sessionId': sessionId,
      'customerId': customerId,
      'hatcheryId': hatcheryId,
      'place': place.name,
      'temperatureFahrenheit': temperatureFahrenheit,
      'humidity': humidity,
      'rssi': rssi,
      'deviceName': deviceName,
      'recordedAt': recordedAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
