import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/govee_capture_model.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';

void main() {
  test('daily capture round-trips capture scope and summaries', () {
    final now = DateTime.parse('2026-05-02T10:00:00');
    final capture = GoveeDailyCaptureModel(
      id: 'capture-1',
      customerId: 'customer-1',
      hatcheryId: 'hatchery-1',
      place: TemperaturePlace.eggStorageRoom,
      captureDate: '2026-05-02',
      deviceId: 'device-1',
      deviceName: 'Govee H5051',
      status: 'completed',
      tempAvg: 72.5,
      tempMin: 71.0,
      tempMax: 74.0,
      rhAvg: 57.1,
      rhMin: 55.0,
      rhMax: 59.0,
      spotCount: 3,
      readingCount: 180,
      createdAt: now,
      updatedAt: now,
    );

    final restored = GoveeDailyCaptureModel.fromMap(capture.toMap());

    expect(restored.id, 'capture-1');
    expect(restored.customerId, 'customer-1');
    expect(restored.hatcheryId, 'hatchery-1');
    expect(restored.place, TemperaturePlace.eggStorageRoom);
    expect(restored.captureDate, '2026-05-02');
    expect(restored.deviceId, 'device-1');
    expect(restored.deviceName, 'Govee H5051');
    expect(restored.tempAvg, 72.5);
    expect(restored.rhAvg, 57.1);
    expect(restored.spotCount, 3);
    expect(restored.readingCount, 180);
    expect(restored.createdAt, now);
    expect(restored.updatedAt, now);
  });

  test('spot capture round-trips timing and summaries', () {
    final now = DateTime.parse('2026-05-02T10:00:00');
    final spot = GoveeSpotCaptureModel(
      id: 'spot-1',
      captureId: 'capture-1',
      spotIndex: 1,
      spotLabel: 'Door',
      warmupStartedAt: now,
      validStartedAt: now.add(const Duration(seconds: 60)),
      validEndedAt: now.add(const Duration(seconds: 180)),
      validDurationSeconds: 120,
      tempAvg: 72.5,
      tempMin: 71.0,
      tempMax: 74.0,
      rhAvg: 57.1,
      rhMin: 55.0,
      rhMax: 59.0,
      readingCount: 60,
      createdAt: now,
      updatedAt: now,
    );

    final restored = GoveeSpotCaptureModel.fromMap(spot.toMap());

    expect(restored.id, 'spot-1');
    expect(restored.captureId, 'capture-1');
    expect(restored.spotIndex, 1);
    expect(restored.spotLabel, 'Door');
    expect(restored.warmupStartedAt, now);
    expect(restored.validStartedAt, now.add(const Duration(seconds: 60)));
    expect(restored.validEndedAt, now.add(const Duration(seconds: 180)));
    expect(restored.validDurationSeconds, 120);
    expect(restored.readingCount, 60);
  });

  test('spot reading round-trips bucketed Govee data', () {
    final now = DateTime.parse('2026-05-02T10:01:00');
    final reading = GoveeSpotReadingModel(
      id: 'reading-1',
      captureId: 'capture-1',
      spotId: 'spot-1',
      readingIndex: 7,
      recordedAt: now,
      temperatureFahrenheit: 72.4,
      humidity: 56.8,
      rssi: -61,
      deviceName: 'Govee H5051',
      createdAt: now,
    );

    final restored = GoveeSpotReadingModel.fromMap(reading.toMap());

    expect(restored.id, 'reading-1');
    expect(restored.captureId, 'capture-1');
    expect(restored.spotId, 'spot-1');
    expect(restored.readingIndex, 7);
    expect(restored.recordedAt, now);
    expect(restored.temperatureFahrenheit, 72.4);
    expect(restored.humidity, 56.8);
    expect(restored.rssi, -61);
    expect(restored.deviceName, 'Govee H5051');
    expect(restored.createdAt, now);
  });
}
