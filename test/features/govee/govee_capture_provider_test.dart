import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/govee_capture_model.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:hatchaudit/features/dashboard/models/govee_capture_summary.dart';
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

GoveeDailyCaptureModel _capture({
  required String id,
  required TemperaturePlace place,
  String stationKey = 'egg',
  String? machineId,
  int readingCount = 2,
  DateTime? startedAt,
  DateTime? endedAt,
}) {
  final now = DateTime.parse('2026-05-02T10:00:00');
  return GoveeDailyCaptureModel(
    id: id,
    customerId: 'customer-1',
    hatcheryId: 'hatchery-1',
    stationKey: stationKey,
    place: place,
    machineId: machineId,
    captureDate: '2026-05-02',
    startedAt: startedAt ?? now,
    endedAt: endedAt ?? now.add(const Duration(minutes: 5)),
    status: 'completed',
    tempAvg: 72,
    tempMin: 71,
    tempMax: 73,
    rhAvg: 56,
    rhMin: 55,
    rhMax: 57,
    readingCount: readingCount,
    createdAt: now,
    updatedAt: now,
  );
}

List<GoveePlaceReadingModel> _placeReadings(String captureId) {
  final now = DateTime.parse('2026-05-02T10:00:00');
  return [
    GoveePlaceReadingModel(
      id: '$captureId-reading-1',
      captureId: captureId,
      readingIndex: 0,
      recordedAt: now,
      temperatureFahrenheit: 71,
      humidity: 55,
      createdAt: now,
    ),
    GoveePlaceReadingModel(
      id: '$captureId-reading-2',
      captureId: captureId,
      readingIndex: 1,
      recordedAt: now.add(const Duration(minutes: 1)),
      temperatureFahrenheit: 73,
      humidity: 57,
      createdAt: now,
    ),
  ];
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
    when(
      () => mockRepo.getCapturesForDashboard(
        customerId: any(named: 'customerId'),
        hatcheryId: any(named: 'hatcheryId'),
        captureDate: any(named: 'captureDate'),
      ),
    ).thenAnswer((_) async => const []);
    when(
      () => mockRepo.getReadingsForCapture(any()),
    ).thenAnswer((_) async => const []);
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
    'configure loads saved captures for the date and start recording keeps them visible',
    () async {
      final eggCapture = _capture(
        id: 'egg-capture',
        place: TemperaturePlace.eggStorageRoom,
        stationKey: 'egg',
      );
      final chickCapture = _capture(
        id: 'chick-capture',
        place: TemperaturePlace.chickHoldingArea,
        stationKey: 'chicks',
      );
      when(
        () => mockRepo.getCapturesForDashboard(
          customerId: 'customer-1',
          hatcheryId: 'hatchery-1',
          captureDate: '2026-05-02',
        ),
      ).thenAnswer((_) async => [chickCapture, eggCapture]);
      when(
        () => mockRepo.getReadingsForCapture(eggCapture.id),
      ).thenAnswer((_) async => _placeReadings(eggCapture.id));
      when(
        () => mockRepo.getReadingsForCapture(chickCapture.id),
      ).thenAnswer((_) async => _placeReadings(chickCapture.id));

      final provider = await configuredProvider();

      expect(provider.savedSummaries, hasLength(2));
      expect(provider.savedSummaries.map((summary) => summary.capture.id), [
        'egg-capture',
        'chick-capture',
      ]);
      expect(provider.selectedSavedSummary?.capture.id, 'egg-capture');

      await provider.startRecording();

      expect(provider.savedSummaries, hasLength(2));
      expect(provider.selectedSavedSummary?.capture.id, 'egg-capture');
      expect(provider.finishedCapture?.id, 'egg-capture');
    },
  );

  test('configure recovers when saved capture lookup fails', () async {
    when(
      () => mockRepo.getCaptureForScope(
        customerId: any(named: 'customerId'),
        hatcheryId: any(named: 'hatcheryId'),
        stationKey: any(named: 'stationKey'),
        place: any(named: 'place'),
        machineId: any(named: 'machineId'),
        captureDate: any(named: 'captureDate'),
      ),
    ).thenThrow(StateError('database unavailable'));

    final provider = await configuredProvider();

    expect(provider.error, contains('Could not load saved Govee captures'));
    expect(provider.savedSummaries, isEmpty);
    expect(provider.finishedCapture, isNull);
    expect(provider.canStartRecording, isTrue);
  });

  test(
    'saving refreshes saved summaries and selects the replacement capture',
    () async {
      GoveeDailyCaptureModel? savedCapture;
      List<GoveePlaceReadingModel> savedReadings = const [];
      when(
        () => mockRepo.getCapturesForDashboard(
          customerId: 'customer-1',
          hatcheryId: 'hatchery-1',
          captureDate: '2026-05-02',
        ),
      ).thenAnswer((_) async => savedCapture == null ? [] : [savedCapture!]);
      when(
        () => mockRepo.getReadingsForCapture(any()),
      ).thenAnswer((_) async => savedReadings);
      when(
        () => mockRepo.saveReplacement(
          capture: any(named: 'capture'),
          readings: any(named: 'readings'),
        ),
      ).thenAnswer((invocation) async {
        savedCapture =
            invocation.namedArguments[#capture] as GoveeDailyCaptureModel;
        savedReadings =
            invocation.namedArguments[#readings]
                as List<GoveePlaceReadingModel>;
      });
      final provider = await configuredProvider();

      await provider.startRecording();
      fakeClock.elapse(const Duration(minutes: 10));
      await provider.stopAndSavePlaceCapture();

      expect(provider.savedSummaries, hasLength(1));
      expect(provider.savedSummaries.single.capture.id, savedCapture!.id);
      expect(provider.selectedSavedSummary?.capture.id, savedCapture!.id);
      expect(provider.finishedCapture?.id, savedCapture!.id);
      expect(provider.finishedReadings, savedReadings);
      expect(provider.savedSummaries, everyElement(isA<GoveeCaptureSummary>()));
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

  test('live preview readings are capped during long recordings', () async {
    final provider = await configuredProvider();

    await provider.startRecording();
    for (var i = 0; i < 520; i++) {
      liveReadings.add(
        _reading(
          timestamp: DateTime.parse(
            '2026-05-02T10:00:00',
          ).add(Duration(seconds: i)),
          temp: 70 + i / 100,
          humidity: 55,
        ),
      );
    }
    await Future<void>.delayed(Duration.zero);

    expect(provider.liveRecordingReadings, hasLength(500));
    expect(
      provider.liveRecordingReadings.first.timestamp,
      DateTime.parse('2026-05-02T10:00:20'),
    );
    expect(
      provider.liveRecordingReadings.last.timestamp,
      DateTime.parse('2026-05-02T10:08:39'),
    );
  });

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
    expect(capture.tempSd, 2.0);
    expect(capture.tempCvPct, 2.78);
    expect(capture.rhAvg, 52);
    expect(capture.rhMin, 50);
    expect(capture.rhMax, 54);
    expect(capture.rhSd, 2.0);
    expect(capture.rhCvPct, 3.85);
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

  test(
    'failed capture save preserves synced readings and retries without another history sync',
    () async {
      var attempts = 0;
      GoveeDailyCaptureModel? savedCapture;
      List<GoveePlaceReadingModel> savedReadings = const [];
      when(
        () => mockRepo.saveReplacement(
          capture: any(named: 'capture'),
          readings: any(named: 'readings'),
        ),
      ).thenAnswer((invocation) async {
        attempts += 1;
        if (attempts == 1) {
          throw StateError('database locked');
        }
        savedCapture =
            invocation.namedArguments[#capture] as GoveeDailyCaptureModel;
        savedReadings =
            invocation.namedArguments[#readings]
                as List<GoveePlaceReadingModel>;
      });
      when(
        () => mockRepo.getCapturesForDashboard(
          customerId: 'customer-1',
          hatcheryId: 'hatchery-1',
          captureDate: '2026-05-02',
        ),
      ).thenAnswer((_) async => savedCapture == null ? [] : [savedCapture!]);
      when(
        () => mockRepo.getReadingsForCapture(any()),
      ).thenAnswer((_) async => savedReadings);
      final provider = await configuredProvider();

      await provider.startRecording();
      fakeClock.elapse(const Duration(minutes: 10));
      await provider.stopAndSavePlaceCapture();

      expect(provider.error, contains('Could not save'));
      expect(provider.canStopRecording, isTrue);

      await provider.stopAndSavePlaceCapture();

      verify(
        () => mockGovee.syncHistory(
          startedAt: any(named: 'startedAt'),
          endedAt: any(named: 'endedAt'),
        ),
      ).called(1);
      expect(attempts, 2);
      expect(provider.phase, GoveeCapturePhase.saved);
      expect(provider.savedSummaries.single.capture.id, savedCapture!.id);
    },
  );
}
