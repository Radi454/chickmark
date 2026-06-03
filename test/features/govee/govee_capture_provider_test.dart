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
    registerFallbackValue(Duration.zero);
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
    when(() => mockGovee.initializeBle()).thenAnswer((_) async {});
    when(() => mockGovee.setAutoReconnectEnabled(any())).thenReturn(null);
    when(
      () => mockGovee.syncHistory(
        startedAt: any(named: 'startedAt'),
        endedAt: any(named: 'endedAt'),
      ),
    ).thenAnswer((invocation) async {
      final startedAt = invocation.namedArguments[#startedAt] as DateTime;
      return _readingsFrom(startedAt: startedAt, count: 1000);
    });
    when(
      () => mockRepo.saveReplacement(
        capture: any(named: 'capture'),
        readings: any(named: 'readings'),
        rawReadings: any(named: 'rawReadings'),
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
          rawReadings: captureAny(named: 'rawReadings'),
        ),
      ).captured;
      final capture = captured[0] as GoveeDailyCaptureModel;
      final readings = captured[1] as List<GoveePlaceReadingModel>;
      final rawReadings = captured[2] as List<GoveePlaceReadingModel>;

      expect(capture.place, TemperaturePlace.insideSetter);
      expect(capture.machineId, 'setter-7');
      expect(capture.startedAt, DateTime.parse('2026-05-02T10:00:00'));
      expect(capture.endedAt, DateTime.parse('2026-05-02T10:20:00'));
      expect(capture.readingCount, 1000);
      expect(readings, hasLength(100));
      expect(rawReadings, hasLength(1000));
      expect(rawReadings.first.recordedAt, DateTime.parse('2026-05-02T10:00:00'));
    },
  );

  test('start recording scans when no Govee sensor is connected', () async {
    when(() => mockGovee.isConnected).thenReturn(false);
    when(() => mockGovee.isGattConnected).thenReturn(false);
    when(() => mockGovee.isScanning).thenReturn(false);
    when(
      () =>
          mockGovee.startScan(discoveryTimeout: any(named: 'discoveryTimeout')),
    ).thenAnswer((_) async {});
    final provider = await configuredProvider();

    await provider.startRecording();

    verify(
      () => mockGovee.startScan(discoveryTimeout: const Duration(seconds: 30)),
    ).called(1);
    expect(provider.phase, GoveeCapturePhase.validRecording);
  });

  test(
    'start recording connects a discovered sensor before recording',
    () async {
      when(() => mockGovee.isConnected).thenReturn(true);
      when(() => mockGovee.isGattConnected).thenReturn(false);
      when(() => mockGovee.connectDevice()).thenAnswer((_) async {});
      final provider = await configuredProvider();

      await provider.startRecording();

      verify(() => mockGovee.connectDevice()).called(1);
      verifyNever(
        () => mockGovee.startScan(
          discoveryTimeout: any(named: 'discoveryTimeout'),
        ),
      );
      expect(provider.phase, GoveeCapturePhase.validRecording);
    },
  );

  test(
    'live preview exposes the latest valid reading before recording',
    () async {
      final latest = _reading(
        timestamp: DateTime.parse('2026-05-02T10:01:00'),
        temp: 77.5,
        humidity: 53.3,
      );
      when(() => mockGovee.latestReading).thenReturn(latest);

      final provider = await configuredProvider();

      expect(provider.isRecording, isFalse);
      expect(provider.livePreviewReadings, [latest]);
    },
  );

  test('live preview accumulates sensor readings before recording', () async {
    final first = _reading(
      timestamp: DateTime.parse('2026-05-02T10:01:00'),
      temp: 77.4,
      humidity: 53.3,
    );
    final second = _reading(
      timestamp: DateTime.parse('2026-05-02T10:02:00'),
      temp: 77.5,
      humidity: 53.4,
    );
    final provider = await configuredProvider();

    await provider.ensureBleReady();
    liveReadings
      ..add(first)
      ..add(second);
    await Future<void>.delayed(Duration.zero);

    expect(provider.isRecording, isFalse);
    expect(provider.liveRecordingReadings, isEmpty);
    expect(provider.livePreviewReadings, [first, second]);
  });

  test('saves valid synced readings from the recording start', () async {
    when(
      () => mockGovee.syncHistory(
        startedAt: any(named: 'startedAt'),
        endedAt: any(named: 'endedAt'),
      ),
    ).thenAnswer((_) async {
      final start = DateTime.parse('2026-05-02T10:00:00');
      return [_reading(timestamp: start.add(const Duration(seconds: 10)))];
    });
    final provider = await configuredProvider();

    await provider.startRecording();
    fakeClock.elapse(const Duration(seconds: 30));
    await provider.stopAndSavePlaceCapture();

    final captured = verify(
      () => mockRepo.saveReplacement(
        capture: captureAny(named: 'capture'),
        readings: captureAny(named: 'readings'),
        rawReadings: captureAny(named: 'rawReadings'),
      ),
    ).captured;
    final capture = captured[0] as GoveeDailyCaptureModel;
    final readings = captured[1] as List<GoveePlaceReadingModel>;

    expect(provider.phase, GoveeCapturePhase.saved);
    expect(capture.readingCount, 1);
    expect(readings.single.recordedAt, DateTime.parse('2026-05-02T10:00:10'));
    expect(provider.error, isNull);
  });

  group('sensor scan', () {
    test('manual scan keeps discovery open for thirty seconds', () async {
      when(() => mockGovee.isConnected).thenReturn(false);
      when(() => mockGovee.isScanning).thenReturn(false);
      when(
        () => mockGovee.startScan(
          discoveryTimeout: any(named: 'discoveryTimeout'),
        ),
      ).thenAnswer((_) async {});
      final provider = await configuredProvider();

      await provider.connectSensor();

      verify(
        () =>
            mockGovee.startScan(discoveryTimeout: const Duration(seconds: 30)),
      ).called(1);
    });

    test('manual rescan keeps discovery open for thirty seconds', () async {
      when(() => mockGovee.isConnected).thenReturn(false);
      when(() => mockGovee.isScanning).thenReturn(true);
      when(
        () => mockGovee.restartScan(
          discoveryTimeout: any(named: 'discoveryTimeout'),
        ),
      ).thenAnswer((_) async {});
      final provider = await configuredProvider();

      await provider.connectSensor();

      verify(
        () => mockGovee.restartScan(
          discoveryTimeout: const Duration(seconds: 30),
        ),
      ).called(1);
    });
  });

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
          rawReadings: any(named: 'rawReadings'),
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
          rawReadings: captureAny(named: 'rawReadings'),
        ),
      ).captured;
      final capture = captured[0] as GoveeDailyCaptureModel;

      expect(capture.tempMax, lessThan(90));
      expect(capture.rhMax, lessThan(70));
    },
  );

  test(
    'uses live recording readings when recent history returns empty',
    () async {
      when(
        () => mockGovee.syncHistory(
          startedAt: any(named: 'startedAt'),
          endedAt: any(named: 'endedAt'),
        ),
      ).thenAnswer((_) async => const <GoveeSensorReading>[]);
      final provider = await configuredProvider();

      await provider.startRecording();
      liveReadings
        ..add(
          _reading(
            timestamp: DateTime.parse('2026-05-02T10:00:05'),
            temp: 77.6,
            humidity: 52.8,
          ),
        )
        ..add(
          _reading(
            timestamp: DateTime.parse('2026-05-02T10:00:10'),
            temp: 77.5,
            humidity: 52.5,
          ),
        );
      await Future<void>.delayed(Duration.zero);
      fakeClock.elapse(const Duration(minutes: 2));
      await provider.stopAndSavePlaceCapture();

      final captured = verify(
        () => mockRepo.saveReplacement(
          capture: captureAny(named: 'capture'),
          readings: captureAny(named: 'readings'),
          rawReadings: captureAny(named: 'rawReadings'),
        ),
      ).captured;
      final capture = captured[0] as GoveeDailyCaptureModel;
      final readings = captured[1] as List<GoveePlaceReadingModel>;

      expect(provider.phase, GoveeCapturePhase.saved);
      expect(capture.readingCount, 2);
      expect(capture.tempAvg, closeTo(77.55, 0.01));
      expect(capture.rhAvg, closeTo(52.65, 0.01));
      expect(readings.map((reading) => reading.recordedAt), [
        DateTime.parse('2026-05-02T10:00:05'),
        DateTime.parse('2026-05-02T10:00:10'),
      ]);
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

  test('invalid readings are excluded before stats and LTTB', () async {
    when(
      () => mockGovee.syncHistory(
        startedAt: any(named: 'startedAt'),
        endedAt: any(named: 'endedAt'),
      ),
    ).thenAnswer((_) async {
      final start = DateTime.parse('2026-05-02T10:00:00');
      return [
        _reading(timestamp: start.add(const Duration(seconds: 10)), temp: -100),
        _reading(timestamp: start.add(const Duration(seconds: 70)), temp: null),
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
        rawReadings: captureAny(named: 'rawReadings'),
      ),
    ).captured;
    final capture = captured[0] as GoveeDailyCaptureModel;
    final readings = captured[1] as List<GoveePlaceReadingModel>;

    expect(capture.tempMin, greaterThanOrEqualTo(70));
    expect(capture.rhMax, lessThanOrEqualTo(100));
    expect(readings, hasLength(50));
    expect(
      readings.every(
        (reading) =>
            !reading.recordedAt.isBefore(DateTime.parse('2026-05-02T10:00:00')),
      ),
      isTrue,
    );
  });

  test(
    'completed history buckets count when they overlap the Start/Stop window',
    () async {
      when(
        () => mockGovee.syncHistory(
          startedAt: any(named: 'startedAt'),
          endedAt: any(named: 'endedAt'),
        ),
      ).thenAnswer((_) async {
        final bucketStart = DateTime.parse('2026-05-02T10:01:00');
        return [
          GoveeSensorReading(
            temperatureFahrenheit: 72,
            humidity: 56,
            timestamp: bucketStart,
            bucketStartedAt: bucketStart,
            bucketEndedAt: bucketStart.add(const Duration(minutes: 1)),
          ),
        ];
      });
      final provider = await configuredProvider();

      fakeClock.elapse(const Duration(seconds: 56));
      await provider.startRecording();
      fakeClock.elapse(const Duration(seconds: 96));
      await provider.stopAndSavePlaceCapture();

      final captured = verify(
        () => mockRepo.saveReplacement(
          capture: captureAny(named: 'capture'),
          readings: captureAny(named: 'readings'),
          rawReadings: captureAny(named: 'rawReadings'),
        ),
      ).captured;
      final capture = captured[0] as GoveeDailyCaptureModel;

      expect(provider.phase, GoveeCapturePhase.saved);
      expect(capture.readingCount, 1);
      expect(provider.error, isNull);
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
        rawReadings: captureAny(named: 'rawReadings'),
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
          rawReadings: any(named: 'rawReadings'),
        ),
      );
    },
  );

  test(
    'empty valid synced history resets recorder so the user can start again',
    () async {
      when(
        () => mockGovee.syncHistory(
          startedAt: any(named: 'startedAt'),
          endedAt: any(named: 'endedAt'),
        ),
      ).thenAnswer((_) async {
        final start = DateTime.parse('2026-05-02T10:00:00');
        return [
          _reading(timestamp: start.subtract(const Duration(minutes: 2))),
          _reading(timestamp: start.subtract(const Duration(minutes: 1))),
        ];
      });
      final provider = await configuredProvider();

      await provider.startRecording();
      fakeClock.elapse(const Duration(minutes: 20));
      await provider.stopAndSavePlaceCapture();

      expect(provider.phase, GoveeCapturePhase.idle);
      expect(provider.canStartRecording, isTrue);
      expect(provider.canStopRecording, isFalse);
      expect(provider.error, contains('inside this recording window'));
      expect(provider.syncFailureDetails, contains('returned 2 readings'));
      expect(
        provider.syncFailureDiagnostics,
        contains(contains('before valid window: 2')),
      );
      verifyNever(
        () => mockRepo.saveReplacement(
          capture: any(named: 'capture'),
          readings: any(named: 'readings'),
          rawReadings: any(named: 'rawReadings'),
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
          rawReadings: any(named: 'rawReadings'),
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
