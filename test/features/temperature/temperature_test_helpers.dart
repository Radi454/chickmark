import 'package:hatchaudit/data/models/temperature_rh_model.dart';

class TemperatureTestFixtures {
  TemperatureTestFixtures._();

  static const String testSessionId = 'temp-session-1';
  static const String testCustomerId = 'test-customer-1';
  static const String testHatcheryId = 'test-hatchery-1';
  static const String testAuditSessionId = 'audit-session-1';
  static const String testDeviceId = 'govee-h5075-1';
  static const String testDeviceName = 'Govee H5075';

  static final DateTime startedAt = DateTime(2026, 4, 24, 8);
  static final DateTime midAt = DateTime(2026, 4, 24, 8, 5);
  static final DateTime endedAt = DateTime(2026, 4, 24, 8, 15);
}

TemperatureSessionModel makeActiveTemperatureSession({
  String id = TemperatureTestFixtures.testSessionId,
  TemperaturePlace place = TemperaturePlace.eggStorageRoom,
}) {
  return TemperatureSessionModel(
    id: id,
    customerId: TemperatureTestFixtures.testCustomerId,
    hatcheryId: TemperatureTestFixtures.testHatcheryId,
    deviceId: TemperatureTestFixtures.testDeviceId,
    deviceName: TemperatureTestFixtures.testDeviceName,
    startedAt: TemperatureTestFixtures.startedAt,
    activePlace: place,
    status: 'active',
    createdAt: TemperatureTestFixtures.startedAt,
    updatedAt: TemperatureTestFixtures.startedAt,
  );
}

TemperatureSessionModel makeCompletedTemperatureSession({
  String id = TemperatureTestFixtures.testSessionId,
  TemperaturePlace place = TemperaturePlace.eggStorageRoom,
}) {
  return TemperatureSessionModel(
    id: id,
    customerId: TemperatureTestFixtures.testCustomerId,
    hatcheryId: TemperatureTestFixtures.testHatcheryId,
    deviceId: TemperatureTestFixtures.testDeviceId,
    deviceName: TemperatureTestFixtures.testDeviceName,
    startedAt: TemperatureTestFixtures.startedAt,
    endedAt: TemperatureTestFixtures.endedAt,
    activePlace: place,
    status: 'completed',
    createdAt: TemperatureTestFixtures.startedAt,
    updatedAt: TemperatureTestFixtures.endedAt,
  );
}

TemperatureReadingModel makeTemperatureReading({
  String id = 'reading-1',
  String sessionId = TemperatureTestFixtures.testSessionId,
  TemperaturePlace place = TemperaturePlace.eggStorageRoom,
  double temperatureFahrenheit = 72.5,
  double humidity = 65.0,
  int? rssi = -61,
  DateTime? recordedAt,
}) {
  final readingTime = recordedAt ?? TemperatureTestFixtures.midAt;
  return TemperatureReadingModel(
    id: id,
    sessionId: sessionId,
    customerId: TemperatureTestFixtures.testCustomerId,
    hatcheryId: TemperatureTestFixtures.testHatcheryId,
    place: place,
    temperatureFahrenheit: temperatureFahrenheit,
    humidity: humidity,
    rssi: rssi,
    deviceName: TemperatureTestFixtures.testDeviceName,
    recordedAt: readingTime,
    createdAt: readingTime,
  );
}

/// Future-facing summarized temperature-session row fixture for repository tests.
Map<String, dynamic> makeTemperatureSummaryRow({
  String id = TemperatureTestFixtures.testSessionId,
  String? auditSessionId,
  TemperaturePlace place = TemperaturePlace.eggStorageRoom,
  double tempAvg = 72.6,
  double tempMin = 71.8,
  double tempMax = 73.2,
  double tempCvPct = 0.8,
  double rhAvg = 65.1,
  double rhMin = 63.8,
  double rhMax = 66.4,
  double rhCvPct = 1.1,
  int readingCount = 48,
  int alertCount = 0,
  int warmupSeconds = 120,
}) {
  return {
    'id': id,
    'customerId': TemperatureTestFixtures.testCustomerId,
    'hatcheryId': TemperatureTestFixtures.testHatcheryId,
    'deviceId': TemperatureTestFixtures.testDeviceId,
    'deviceName': TemperatureTestFixtures.testDeviceName,
    'startedAt': TemperatureTestFixtures.startedAt.toIso8601String(),
    'endedAt': TemperatureTestFixtures.endedAt.toIso8601String(),
    'activePlace': place.name,
    'status': 'completed',
    'createdAt': TemperatureTestFixtures.startedAt.toIso8601String(),
    'updatedAt': TemperatureTestFixtures.endedAt.toIso8601String(),
    'auditSessionId':
        auditSessionId ?? TemperatureTestFixtures.testAuditSessionId,
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
    'tempChartPointsJson':
        '[{"t":0,"v":72.1},{"t":60,"v":72.8},{"t":120,"v":72.6}]',
    'rhChartPointsJson':
        '[{"t":0,"v":64.7},{"t":60,"v":65.4},{"t":120,"v":65.1}]',
    'warmupSeconds': warmupSeconds,
  };
}
