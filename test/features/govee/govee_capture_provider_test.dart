import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/govee_capture_model.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:hatchaudit/features/govee/providers/govee_capture_provider.dart';
import 'package:hatchaudit/services/govee/govee_service.dart';
import 'package:mocktail/mocktail.dart';

class MockGoveeCaptureRepository extends Mock
    implements GoveeCaptureRepository {}

class MockGoveeService extends Mock implements GoveeService {}

class FakeClock {
  DateTime _now;

  FakeClock(this._now);

  DateTime now() => _now;

  void elapse(Duration duration) {
    _now = _now.add(duration);
  }
}

GoveeSensorReading _reading({
  required DateTime timestamp,
  double? temp = 72.0,
  double? humidity = 56.0,
}) {
  return GoveeSensorReading(
    temperatureFahrenheit: temp,
    humidity: humidity,
    timestamp: timestamp,
  );
}

List<GoveeSensorReading> _readingsFrom({
  required DateTime startedAt,
  required int count,
  Duration step = const Duration(seconds: 1),
}) {
  return List.generate(count, (index) {
    return _reading(
      timestamp: startedAt.add(step * index),
      temp: 70 + index / 100,
      humidity: 55 + index / 200,
    );
  });
}

void main() {
  late MockGoveeCaptureRepository mockRepo;
  late MockGoveeService mockGovee;
  late FakeClock fakeClock;
  late StreamController<GoveeSensorReading> liveReadings;

  setUpAll(() {
    registerFallbackValue(TemperaturePlace.eggStorageRoom);
    registerFallbackValue(
      GoveeDailyCaptureModel(
        id: 'fallback-capture',
        customerId: 'customer-1',
        hatcheryId: 'hatchery-1',
        place: TemperaturePlace.eggStorageRoom,
        captureDate: '2026-05-02',
        status: 'completed',
        readingCount: 50,
        createdAt: DateTime(2026, 5, 2),
        updatedAt: DateTime(2026, 5, 2),
      ),
    );
    registerFallbackValue(<GoveePlaceReadingModel>[]);
  });

  setUp(() {
    mockRepo = MockGoveeCaptureRepository();
    mockGovee = MockGoveeService();
    fakeClock = FakeClock(DateTime.parse('2026-05-02T10:00:00'));
    liveReadings = StreamController<GoveeSensorReading>.broadcast();

    when(
      () => mockRepo.getCaptureForScope(
        customerId: any(named: 'customerId'),
        hatcheryId: any(named: 'hatcheryId'),
        stationKey: any(named: 'stationKey'),
        place: any(named: 'place'),
        machineId: any(named: 'machineId'),
        captureDate: any(named: 'captureDate'),
      ),
    ).thenAnswer((_) async => null);
    when(() => mockGovee.deviceId).thenReturn('device-1');
    when(() => mockGovee.deviceName).thenReturn('Govee H5051');
    when(() => mockGovee.isGattConnected).thenReturn(true);
    when(() => mockGovee.signalStrength).thenReturn(-61);
    when(() => mockGovee.diagnostics).thenReturn(const []);
    when(() => mockGovee.readings).thenAnswer((_) => liveReadings.stream);
    when(
      () => mockGovee.syncHistory(
        startedAt: any(named: 'startedAt'),
        endedAt: any(named: 'endedAt'),
      ),
    ).thenAnswer((invocation) async {
      final startedAt = invocation.namedArguments[#startedAt] as DateTime;
      return _readingsFrom(
        startedAt: startedAt.add(GoveeCaptureProvider.warmupDuration),
        count: 1000,
      );
    });
    when(
      () => mockRepo.saveReplacement(
        capture: any(named: 'capture'),
        readings: any(named: 'readings'),
      ),
    ).thenAnswer((_) async {});
  });

  tearDown(() async {
    await liveReadings.close();
  });

  Future<GoveeCaptureProvider> configuredProvider({
    TemperaturePlace place = TemperaturePlace.eggStorageRoom,
    String stationKey = 'egg',
    String? machineId,
    GoveeCaptureTarget captureTarget = GoveeCaptureTarget.room,
  }) async {
    final provider = GoveeCaptureProvider(
      repository: mockRepo,
      goveeService: mockGovee,
      clock: fakeClock.now,
      enablePhaseTimer: false,
    );
    await provider.configure(
      customerId: 'customer-1',
      hatcheryId: 'hatchery-1',
      place: place,
      captureDate: '2026-05-02',
      stationKey: stationKey,
      machineId: machineId,
      captureTarget: captureTarget,
    );
    return provider;
  }

  test(
    'manual Start/Stop records one place window from history sync',
    () async {
      final provider = await configuredProvider(
        place: TemperaturePlace.setterRoom,
        stationKey: 'setters',
        machineId: 'setter-7',
        captureTarget: GoveeCaptureTarget.insideMachine,
      );

      await provider.startRecording();
      fakeClock.elapse(const Duration(minutes: 20));
      await provider.stopAndSavePlaceCapture();

      verify(
        () => mockGovee.syncHistory(
          startedAt: DateTime.parse('2026-05-02T10:00:00'),
          endedAt: DateTime.parse('2026-05-02T10:20:00'),
        ),
      ).called(1);

      final captured = verify(
        () => mockRepo.saveReplacement(
          capture: captureAny(named: 'capture'),
          readings: captureAny(named: 'readings'),
        ),
      ).captured;
      final capture = captured[0] as GoveeDailyCaptureModel;
      final readings = captured[1] as List<GoveePlaceReadingModel>;

      expect(capture.place, TemperaturePlace.insideSetter);
      expect(capture.machineId, 'setter-7');
      expect(capture.startedAt, DateTime.parse('2026-05-02T10:00:00'));
      expect(capture.endedAt, DateTime.parse('2026-05-02T10:20:00'));
      expect(capture.readingCount, 100);
      expect(readings, hasLength(100));
    },
  );

  test(
    'live readings are preview only and saved data comes from history',
    () async {
      final provider = await configuredProvider();
      final live = _reading(
        timestamp: DateTime.parse('2026-05-02T10:00:05'),
        temp: 110,
        humidity: 90,
      );

      await provider.startRecording();
      liveReadings.add(live);
      await Future<void>.delayed(Duration.zero);
      fakeClock.elapse(const Duration(minutes: 11));
      await provider.stopAndSavePlaceCapture();

      expect(provider.liveRecordingReadings, contains(same(live)));
      final captured = verify(
        () => mockRepo.saveReplacement(
          capture: captureAny(named: 'capture'),
          readings: captureAny(named: 'readings'),
        ),
      ).captured;
      final capture = captured[0] as GoveeDailyCaptureModel;

      expect(capture.tempMax, lessThan(90));
      expect(capture.rhMax, lessThan(70));
    },
  );

  test(
    'warmup and invalid readings are excluded before stats and LTTB',
    () async {
      when(
        () => mockGovee.syncHistory(
          startedAt: any(named: 'startedAt'),
          endedAt: any(named: 'endedAt'),
        ),
      ).thenAnswer((_) async {
        final start = DateTime.parse('2026-05-02T10:00:00');
        return [
          _reading(timestamp: start.add(const Duration(seconds: 10)), temp: 10),
          _reading(
            timestamp: start.add(const Duration(seconds: 70)),
            temp: null,
          ),
          _reading(
            timestamp: start.add(const Duration(seconds: 71)),
            humidity: 101,
          ),
          ..._readingsFrom(
            startedAt: start.add(const Duration(seconds: 80)),
            count: 120,
          ),
        ];
      });
      final provider = await configuredProvider();

      await provider.startRecording();
      fakeClock.elapse(const Duration(minutes: 5));
      await provider.stopAndSavePlaceCapture();

      final captured = verify(
        () => mockRepo.saveReplacement(
          capture: captureAny(named: 'capture'),
          readings: captureAny(named: 'readings'),
        ),
      ).captured;
      final capture = captured[0] as GoveeDailyCaptureModel;
      final readings = captured[1] as List<GoveePlaceReadingModel>;

      expect(capture.tempMin, greaterThanOrEqualTo(70));
      expect(capture.rhMax, lessThanOrEqualTo(100));
      expect(readings, hasLength(50));
      expect(
        readings.every(
          (reading) => !reading.recordedAt.isBefore(
            DateTime.parse('2026-05-02T10:01:00'),
          ),
        ),
        isTrue,
      );
    },
  );

  test('summary computes Avg Min Max SD and CV for Temp and RH', () async {
    when(
      () => mockGovee.syncHistory(
        startedAt: any(named: 'startedAt'),
        endedAt: any(named: 'endedAt'),
      ),
    ).thenAnswer((_) async {
      final start = DateTime.parse('2026-05-02T10:01:00');
      return [
        _reading(timestamp: start, temp: 70, humidity: 50),
        _reading(
          timestamp: start.add(const Duration(seconds: 1)),
          temp: 72,
          humidity: 52,
        ),
        _reading(
          timestamp: start.add(const Duration(seconds: 2)),
          temp: 74,
          humidity: 54,
        ),
      ];
    });
    final provider = await configuredProvider();

    await provider.startRecording();
    fakeClock.elapse(const Duration(minutes: 2));
    await provider.stopAndSavePlaceCapture();

    final captured = verify(
      () => mockRepo.saveReplacement(
        capture: captureAny(named: 'capture'),
        readings: captureAny(named: 'readings'),
      ),
    ).captured;
    final capture = captured[0] as GoveeDailyCaptureModel;

    expect(capture.tempAvg, 72);
    expect(capture.tempMin, 70);
    expect(capture.tempMax, 74);
    expect(capture.tempSd, 1.63);
    expect(capture.tempCvPct, 2.27);
    expect(capture.rhAvg, 52);
    expect(capture.rhMin, 50);
    expect(capture.rhMax, 54);
    expect(capture.rhSd, 1.63);
    expect(capture.rhCvPct, 3.14);
  });

  test(
    'failed history sync preserves window and blocks accidental restart',
    () async {
      when(
        () => mockGovee.syncHistory(
          startedAt: any(named: 'startedAt'),
          endedAt: any(named: 'endedAt'),
        ),
      ).thenThrow(StateError('history timed out'));
      final provider = await configuredProvider();

      await provider.startRecording();
      fakeClock.elapse(const Duration(minutes: 5));
      await provider.stopAndSavePlaceCapture();

      expect(provider.phase, GoveeCapturePhase.syncFailed);
      expect(provider.canStartRecording, isFalse);
      expect(provider.syncFailureDetails, contains('StateError'));
      expect(provider.syncFailureDetails, contains('history timed out'));
      expect(provider.syncFailureDiagnostics.first, contains('Govee H5051'));

      await provider.startRecording();

      expect(provider.phase, GoveeCapturePhase.syncFailed);
      expect(provider.canStartRecording, isFalse);
      verifyNever(
        () => mockRepo.saveReplacement(
          capture: any(named: 'capture'),
          readings: any(named: 'readings'),
        ),
      );
    },
  );
}
