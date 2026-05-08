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
      stationKey: 'egg',
      place: TemperaturePlace.eggStorageRoom,
      machineId: null,
      captureDate: '2026-05-02',
      startedAt: now,
      endedAt: now.add(const Duration(minutes: 15)),
      deviceId: 'device-1',
      deviceName: 'Govee H5051',
      status: 'completed',
      tempAvg: 72.5,
      tempMin: 71.0,
      tempMax: 74.0,
      tempSd: 1.2,
      tempCvPct: 1.66,
      rhAvg: 57.1,
      rhMin: 55.0,
      rhMax: 59.0,
      rhSd: 2.1,
      rhCvPct: 3.68,
      readingCount: 100,
      createdAt: now,
      updatedAt: now,
    );

    final restored = GoveeDailyCaptureModel.fromMap(capture.toMap());

    expect(restored.id, 'capture-1');
    expect(restored.customerId, 'customer-1');
    expect(restored.hatcheryId, 'hatchery-1');
    expect(restored.stationKey, 'egg');
    expect(restored.place, TemperaturePlace.eggStorageRoom);
    expect(restored.machineId, isNull);
    expect(restored.captureDate, '2026-05-02');
    expect(restored.startedAt, now);
    expect(restored.endedAt, now.add(const Duration(minutes: 15)));
    expect(restored.deviceId, 'device-1');
    expect(restored.deviceName, 'Govee H5051');
    expect(restored.tempAvg, 72.5);
    expect(restored.tempSd, 1.2);
    expect(restored.tempCvPct, 1.66);
    expect(restored.rhAvg, 57.1);
    expect(restored.rhSd, 2.1);
    expect(restored.rhCvPct, 3.68);
    expect(restored.readingCount, 100);
    expect(restored.createdAt, now);
    expect(restored.updatedAt, now);
  });

  test('place reading round-trips lean representative Govee data', () {
    final now = DateTime.parse('2026-05-02T10:01:00');
    final reading = GoveePlaceReadingModel(
      id: 'reading-1',
      captureId: 'capture-1',
      readingIndex: 7,
      recordedAt: now,
      temperatureFahrenheit: 72.4,
      humidity: 56.8,
      createdAt: now,
    );

    final restored = GoveePlaceReadingModel.fromMap(reading.toMap());

    expect(restored.id, 'reading-1');
    expect(restored.captureId, 'capture-1');
    expect(restored.readingIndex, 7);
    expect(restored.recordedAt, now);
    expect(restored.temperatureFahrenheit, 72.4);
    expect(restored.humidity, 56.8);
    expect(restored.createdAt, now);
  });
}
