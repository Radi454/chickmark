import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/data/repositories/temperature_rh_repository.dart';
import 'package:hatchaudit/features/temperature/providers/temperature_rh_provider.dart';
import 'package:hatchaudit/services/govee/govee_service.dart';
import 'temperature_test_helpers.dart';

class MockGoveeService extends Mock implements GoveeService {}

class MockTemperatureRhRepository extends Mock
    implements TemperatureRhRepository {}

GoveeSensorReading _reading({
  double temp = 72.5,
  double humidity = 65.0,
  int battery = 99,
  DateTime? timestamp,
}) {
  return GoveeSensorReading(
    temperatureFahrenheit: temp,
    humidity: humidity,
    batteryPercent: battery,
    timestamp: timestamp ?? DateTime.now(),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      TemperatureSessionModel(
        id: 'fallback-session',
        customerId: 'fallback',
        hatcheryId: 'fallback',
        startedAt: DateTime.now(),
        activePlace: TemperaturePlace.eggStorageRoom,
        status: 'active',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    registerFallbackValue(
      GoveeSensorReading(
        temperatureFahrenheit: 70.0,
        humidity: 60.0,
        batteryPercent: 100,
        timestamp: DateTime.now(),
      ),
    );
    registerFallbackValue(
      TemperatureReadingModel(
        id: 'fallback-reading',
        sessionId: 'fallback',
        customerId: 'fallback',
        hatcheryId: 'fallback',
        place: TemperaturePlace.eggStorageRoom,
        temperatureFahrenheit: 72.0,
        humidity: 65.0,
        recordedAt: DateTime.now(),
        createdAt: DateTime.now(),
      ),
    );
  });

  late MockGoveeService mockGovee;
  late MockTemperatureRhRepository mockRepo;
  late StreamController<GoveeSensorReading> readingStreamController;

  setUp(() {
    mockGovee = MockGoveeService();
    mockRepo = MockTemperatureRhRepository();
    readingStreamController = StreamController<GoveeSensorReading>.broadcast();

    when(() => mockGovee.isAvailable).thenReturn(true);
    when(() => mockGovee.isConnected).thenReturn(true);
    when(() => mockGovee.isScanning).thenReturn(true);
    when(() => mockGovee.isGattConnected).thenReturn(false);
    when(() => mockGovee.isGattConnecting).thenReturn(false);
    when(() => mockGovee.deviceName).thenReturn('Govee H5075');
    when(() => mockGovee.deviceId).thenReturn('aa:bb:cc:dd:ee:ff');
    when(() => mockGovee.signalStrength).thenReturn(-61);
    when(() => mockGovee.lastSeenAt).thenReturn(null);
    when(() => mockGovee.latestReading).thenReturn(null);
    when(() => mockGovee.diagnostics).thenReturn([]);
    when(() => mockGovee.readings).thenAnswer(
      (_) => readingStreamController.stream,
    );
    when(() => mockGovee.addListener(any())).thenAnswer((_) {});
    when(() => mockGovee.startScan()).thenAnswer((_) async {});
    when(() => mockGovee.requestLiveReading()).thenAnswer((_) async {});
  });

  tearDown(() {
    readingStreamController.close();
  });

  DateTime _now() => DateTime.now();

  Future<void> _emitReadings(List<GoveeSensorReading> readings) async {
    for (final reading in readings) {
      when(() => mockGovee.latestReading).thenReturn(reading);
      readingStreamController.add(reading);
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }

  Future<TemperatureSessionModel> _captureSummary(
    TemperatureRhProvider provider,
    List<GoveeSensorReading> readings,
  ) async {
    await _emitReadings(readings);
    when(() => mockGovee.latestReading).thenReturn(null);
    await provider.stopSession();
    final captured =
        verify(() => mockRepo.persistSessionSummary(captureAny())).captured;
    return captured.first as TemperatureSessionModel;
  }

  group('warm-up exclusion', () {
    test(
      'readings captured during warmup period are excluded from summary stats',
      () async {
        when(() => mockRepo.upsertSession(any())).thenAnswer((_) async {});
        when(() => mockRepo.persistSessionSummary(any()))
            .thenAnswer((_) async {});
        when(() => mockRepo.getReadingsForSession(any()))
            .thenAnswer((_) async => []);

        final base = _now();

        final warmupReadings = [
          _reading(temp: 72.0, humidity: 60.0,
            timestamp: base.add(const Duration(seconds: 20))),
          _reading(temp: 73.0, humidity: 61.0,
            timestamp: base.add(const Duration(seconds: 45))),
          _reading(temp: 80.0, humidity: 55.0,
            timestamp: base.add(const Duration(seconds: 60))),
        ];

        final postWarmupReadings = [
          _reading(temp: 72.5, humidity: 65.0,
            timestamp: base.add(const Duration(seconds: 130))),
          _reading(temp: 72.6, humidity: 65.2,
            timestamp: base.add(const Duration(seconds: 160))),
          _reading(temp: 72.7, humidity: 65.1,
            timestamp: base.add(const Duration(seconds: 190))),
        ];

        final provider = TemperatureRhProvider(
          goveeService: mockGovee,
          repository: mockRepo,
        );

        await provider.setActivePlace(TemperaturePlace.eggStorageRoom);
        await provider.startSession(
          customerId: TemperatureTestFixtures.testCustomerId,
          hatcheryId: TemperatureTestFixtures.testHatcheryId,
        );

        await _emitReadings(warmupReadings);
        await _emitReadings(postWarmupReadings);

        final summary = await _captureSummary(provider, []);

        expect(summary.tempMin, closeTo(72.5, 0.1));
        expect(summary.tempMax, closeTo(72.7, 0.1));
      },
    );

    test(
      'all readings excluded when session stopped within warmup window',
      () async {
        when(() => mockRepo.upsertSession(any())).thenAnswer((_) async {});
        when(() => mockRepo.persistSessionSummary(any()))
            .thenAnswer((_) async {});
        when(() => mockRepo.getReadingsForSession(any()))
            .thenAnswer((_) async => []);

        final base = _now();
        final reading = _reading(
          temp: 72.0, humidity: 65.0,
          timestamp: base.add(const Duration(seconds: 30)),
        );

        final provider = TemperatureRhProvider(
          goveeService: mockGovee,
          repository: mockRepo,
        );

        await provider.setActivePlace(TemperaturePlace.eggStorageRoom);
        await provider.startSession(
          customerId: TemperatureTestFixtures.testCustomerId,
          hatcheryId: TemperatureTestFixtures.testHatcheryId,
        );

        final summary = await _captureSummary(provider, [reading]);

        expect(summary.readingCount, isNull);
        expect(summary.tempMin, isNull);
        expect(summary.tempMax, isNull);
        expect(summary.tempAvg, isNull);
      },
    );

    test(
      'warmup period can be configured via warmupSeconds field',
      () async {
        when(() => mockRepo.upsertSession(any())).thenAnswer((_) async {});
        when(() => mockRepo.persistSessionSummary(any()))
            .thenAnswer((_) async {});
        when(() => mockRepo.getReadingsForSession(any()))
            .thenAnswer((_) async => []);

        final base = _now();
        final reading = _reading(
          temp: 72.5, humidity: 65.0,
          timestamp: base.add(const Duration(seconds: 40)),
        );

        final provider = TemperatureRhProvider(
          goveeService: mockGovee,
          repository: mockRepo,
        );

        await provider.setActivePlace(TemperaturePlace.eggStorageRoom);
        await provider.startSession(
          customerId: TemperatureTestFixtures.testCustomerId,
          hatcheryId: TemperatureTestFixtures.testHatcheryId,
        );
        provider.setWarmupSeconds(30);

        final summary = await _captureSummary(provider, [reading]);

        expect(summary.readingCount, 1);
        expect(summary.tempAvg, closeTo(72.5, 0.1));
      },
    );
  });

  group('summary metrics', () {
    test(
      'computes min, max, avg for temperature and humidity on stop',
      () async {
        when(() => mockRepo.upsertSession(any())).thenAnswer((_) async {});
        when(() => mockRepo.persistSessionSummary(any()))
            .thenAnswer((_) async {});
        when(() => mockRepo.getReadingsForSession(any()))
            .thenAnswer((_) async => []);

        final base = _now();
        final readings = [
          _reading(temp: 70.0, humidity: 60.0,
            timestamp: base.add(const Duration(seconds: 130))),
          _reading(temp: 75.0, humidity: 65.0,
            timestamp: base.add(const Duration(seconds: 160))),
          _reading(temp: 72.5, humidity: 62.5,
            timestamp: base.add(const Duration(seconds: 190))),
        ];

        final provider = TemperatureRhProvider(
          goveeService: mockGovee,
          repository: mockRepo,
        );

        await provider.setActivePlace(TemperaturePlace.eggStorageRoom);
        await provider.startSession(
          customerId: TemperatureTestFixtures.testCustomerId,
          hatcheryId: TemperatureTestFixtures.testHatcheryId,
        );
        provider.setWarmupSeconds(30);

        final summary = await _captureSummary(provider, readings);

        expect(summary.readingCount, 3);
        expect(summary.tempMin, closeTo(70.0, 0.1));
        expect(summary.tempMax, closeTo(75.0, 0.1));
        expect(summary.tempAvg, closeTo(72.5, 0.2));
        expect(summary.rhMin, closeTo(60.0, 0.1));
        expect(summary.rhMax, closeTo(65.0, 0.1));
        expect(summary.rhAvg, closeTo(62.5, 0.2));
      },
    );

    test(
      'computes CV% for temperature and humidity',
      () async {
        when(() => mockRepo.upsertSession(any())).thenAnswer((_) async {});
        when(() => mockRepo.persistSessionSummary(any()))
            .thenAnswer((_) async {});
        when(() => mockRepo.getReadingsForSession(any()))
            .thenAnswer((_) async => []);

        final base = _now();
        final readings = [
          _reading(temp: 70.0, humidity: 60.0,
            timestamp: base.add(const Duration(seconds: 130))),
          _reading(temp: 80.0, humidity: 70.0,
            timestamp: base.add(const Duration(seconds: 160))),
        ];

        final provider = TemperatureRhProvider(
          goveeService: mockGovee,
          repository: mockRepo,
        );

        await provider.setActivePlace(TemperaturePlace.eggStorageRoom);
        await provider.startSession(
          customerId: TemperatureTestFixtures.testCustomerId,
          hatcheryId: TemperatureTestFixtures.testHatcheryId,
        );
        provider.setWarmupSeconds(30);

        final summary = await _captureSummary(provider, readings);

        expect(summary.tempCvPct, isNotNull);
        expect(summary.tempCvPct! > 0, isTrue);
        expect(summary.rhCvPct, isNotNull);
        expect(summary.rhCvPct! > 0, isTrue);
      },
    );

    test(
      'single reading produces zero CV% and same min/max/avg',
      () async {
        when(() => mockRepo.upsertSession(any())).thenAnswer((_) async {});
        when(() => mockRepo.persistSessionSummary(any()))
            .thenAnswer((_) async {});
        when(() => mockRepo.getReadingsForSession(any()))
            .thenAnswer((_) async => []);

        final base = _now();
        final reading = _reading(
          temp: 72.5, humidity: 65.0,
          timestamp: base.add(const Duration(seconds: 130)),
        );

        final provider = TemperatureRhProvider(
          goveeService: mockGovee,
          repository: mockRepo,
        );

        await provider.setActivePlace(TemperaturePlace.eggStorageRoom);
        await provider.startSession(
          customerId: TemperatureTestFixtures.testCustomerId,
          hatcheryId: TemperatureTestFixtures.testHatcheryId,
        );
        provider.setWarmupSeconds(30);

        final summary = await _captureSummary(provider, [reading]);

        expect(summary.readingCount, 1);
        expect(summary.tempMin, closeTo(72.5, 0.01));
        expect(summary.tempMax, closeTo(72.5, 0.01));
        expect(summary.tempAvg, closeTo(72.5, 0.01));
        expect(summary.tempCvPct, closeTo(0, 0.01));
        expect(summary.rhCvPct, closeTo(0, 0.01));
      },
    );

    test(
      'links summary to auditSessionId when provided',
      () async {
        when(() => mockRepo.upsertSession(any())).thenAnswer((_) async {});
        when(() => mockRepo.persistSessionSummary(any()))
            .thenAnswer((_) async {});
        when(() => mockRepo.getReadingsForSession(any()))
            .thenAnswer((_) async => []);

        final base = _now();
        final reading = _reading(
          temp: 72.5, humidity: 65.0,
          timestamp: base.add(const Duration(seconds: 130)),
        );

        final provider = TemperatureRhProvider(
          goveeService: mockGovee,
          repository: mockRepo,
        );

        await provider.setActivePlace(TemperaturePlace.eggStorageRoom);
        await provider.startSession(
          customerId: TemperatureTestFixtures.testCustomerId,
          hatcheryId: TemperatureTestFixtures.testHatcheryId,
          auditSessionId: 'audit-session-42',
        );
        provider.setWarmupSeconds(30);

        final summary = await _captureSummary(provider, [reading]);

        expect(summary.auditSessionId, 'audit-session-42');
      },
    );

    test(
      'excludes outlier readings beyond reasonable bounds from summary',
      () async {
        when(() => mockRepo.upsertSession(any())).thenAnswer((_) async {});
        when(() => mockRepo.persistSessionSummary(any()))
            .thenAnswer((_) async {});
        when(() => mockRepo.getReadingsForSession(any()))
            .thenAnswer((_) async => []);

        final base = _now();
        final readings = [
          _reading(temp: 72.0, humidity: 60.0,
            timestamp: base.add(const Duration(seconds: 130))),
          _reading(temp: -50.0, humidity: 30.0,
            timestamp: base.add(const Duration(seconds: 140))),
          _reading(temp: 72.5, humidity: 61.0,
            timestamp: base.add(const Duration(seconds: 150))),
          _reading(temp: -60.0, humidity: 5.0,
            timestamp: base.add(const Duration(seconds: 160))),
          _reading(temp: 73.0, humidity: 62.0,
            timestamp: base.add(const Duration(seconds: 170))),
        ];

        final provider = TemperatureRhProvider(
          goveeService: mockGovee,
          repository: mockRepo,
        );

        await provider.setActivePlace(TemperaturePlace.eggStorageRoom);
        await provider.startSession(
          customerId: TemperatureTestFixtures.testCustomerId,
          hatcheryId: TemperatureTestFixtures.testHatcheryId,
        );
        provider.setWarmupSeconds(30);

        final summary = await _captureSummary(provider, readings);

        expect(summary.readingCount, 3);
        expect(summary.tempMin, closeTo(72.0, 0.1));
        expect(summary.tempMax, closeTo(73.0, 0.1));
      },
    );
  });

  group('chart downsampling', () {
    test(
      'produces chart point JSONs on stop',
      () async {
        when(() => mockRepo.upsertSession(any())).thenAnswer((_) async {});
        when(() => mockRepo.persistSessionSummary(any()))
            .thenAnswer((_) async {});
        when(() => mockRepo.getReadingsForSession(any()))
            .thenAnswer((_) async => []);

        final base = _now();
        final readings = List.generate(30, (i) {
          return _reading(
            temp: 70.0 + i * 0.1,
            humidity: 60.0 + i * 0.05,
            timestamp: base.add(Duration(seconds: 130 + i * 10)),
          );
        });

        final provider = TemperatureRhProvider(
          goveeService: mockGovee,
          repository: mockRepo,
        );

        await provider.setActivePlace(TemperaturePlace.eggStorageRoom);
        await provider.startSession(
          customerId: TemperatureTestFixtures.testCustomerId,
          hatcheryId: TemperatureTestFixtures.testHatcheryId,
        );
        provider.setWarmupSeconds(30);

        final summary = await _captureSummary(provider, readings);

        expect(summary.tempChartPointsJson, isNotNull);
        expect(summary.tempChartPointsJson!.isNotEmpty, isTrue);
        expect(summary.rhChartPointsJson, isNotNull);
        expect(summary.rhChartPointsJson!.isNotEmpty, isTrue);

        final tempPoints = summary.tempChartPoints;
        expect(tempPoints.isNotEmpty, isTrue);
        for (final point in tempPoints) {
          expect(point.value, greaterThan(0));
        }

        final rhPoints = summary.rhChartPoints;
        expect(rhPoints.isNotEmpty, isTrue);
        for (final point in rhPoints) {
          expect(point.value, greaterThan(0));
        }
      },
    );

    test(
      'downsamples readings to maximum chart points',
      () async {
        when(() => mockRepo.upsertSession(any())).thenAnswer((_) async {});
        when(() => mockRepo.persistSessionSummary(any()))
            .thenAnswer((_) async {});
        when(() => mockRepo.getReadingsForSession(any()))
            .thenAnswer((_) async => []);

        final base = _now();
        final readings = List.generate(300, (i) {
          return _reading(
            temp: 70.0 + i * 0.02,
            humidity: 60.0 + i * 0.01,
            timestamp: base.add(Duration(seconds: 130 + i * 2)),
          );
        });

        final provider = TemperatureRhProvider(
          goveeService: mockGovee,
          repository: mockRepo,
        );

        await provider.setActivePlace(TemperaturePlace.eggStorageRoom);
        await provider.startSession(
          customerId: TemperatureTestFixtures.testCustomerId,
          hatcheryId: TemperatureTestFixtures.testHatcheryId,
        );
        provider.setWarmupSeconds(30);

        final summary = await _captureSummary(provider, readings);

        const maxPoints = 60;
        final tempPoints = summary.tempChartPoints;
        final rhPoints = summary.rhChartPoints;
        expect(tempPoints.length, lessThanOrEqualTo(maxPoints));
        expect(rhPoints.length, lessThanOrEqualTo(maxPoints));
      },
    );

    test(
      'empty readings produce empty chart JSON arrays',
      () async {
        when(() => mockRepo.upsertSession(any())).thenAnswer((_) async {});
        when(() => mockRepo.persistSessionSummary(any()))
            .thenAnswer((_) async {});
        when(() => mockRepo.getReadingsForSession(any()))
            .thenAnswer((_) async => []);

        final provider = TemperatureRhProvider(
          goveeService: mockGovee,
          repository: mockRepo,
        );

        await provider.setActivePlace(TemperaturePlace.eggStorageRoom);
        await provider.startSession(
          customerId: TemperatureTestFixtures.testCustomerId,
          hatcheryId: TemperatureTestFixtures.testHatcheryId,
        );
        provider.setWarmupSeconds(30);

        when(() => mockGovee.latestReading).thenReturn(null);
        await provider.stopSession();
        final captured =
            verify(() => mockRepo.persistSessionSummary(captureAny())).captured;
        final summary = captured.first as TemperatureSessionModel;

        expect(summary.tempChartPoints, isEmpty);
        expect(summary.rhChartPoints, isEmpty);
      },
    );
  });

  group('in-memory buffering', () {
    test(
      'does not write raw readings to repository during active capture',
      () async {
        when(() => mockRepo.upsertSession(any())).thenAnswer((_) async {});
        when(() => mockRepo.persistSessionSummary(any()))
            .thenAnswer((_) async {});
        when(() => mockRepo.insertReading(any())).thenAnswer((_) async {});

        final base = _now();
        final reading = _reading(
          temp: 72.5, humidity: 65.0,
          timestamp: base.add(const Duration(seconds: 130)),
        );

        final provider = TemperatureRhProvider(
          goveeService: mockGovee,
          repository: mockRepo,
        );

        await provider.setActivePlace(TemperaturePlace.eggStorageRoom);
        await provider.startSession(
          customerId: TemperatureTestFixtures.testCustomerId,
          hatcheryId: TemperatureTestFixtures.testHatcheryId,
        );
        provider.setWarmupSeconds(30);

        await _emitReadings([reading]);

        verifyNever(() => mockRepo.insertReading(any()));

        when(() => mockGovee.latestReading).thenReturn(null);
        await provider.stopSession();
        verify(() => mockRepo.persistSessionSummary(any())).called(1);
      },
    );

    test(
      'clears in-memory buffer after stop',
      () async {
        when(() => mockRepo.upsertSession(any())).thenAnswer((_) async {});
        when(() => mockRepo.persistSessionSummary(any()))
            .thenAnswer((_) async {});
        when(() => mockRepo.getReadingsForSession(any()))
            .thenAnswer((_) async => []);

        final base = _now();
        final reading1 = _reading(
          temp: 72.0, humidity: 65.0,
          timestamp: base.add(const Duration(seconds: 130)),
        );
        final reading2 = _reading(
          temp: 72.5, humidity: 65.2,
          timestamp: base.add(const Duration(seconds: 160)),
        );

        final provider = TemperatureRhProvider(
          goveeService: mockGovee,
          repository: mockRepo,
        );

        await provider.setActivePlace(TemperaturePlace.eggStorageRoom);
        await provider.startSession(
          customerId: TemperatureTestFixtures.testCustomerId,
          hatcheryId: TemperatureTestFixtures.testHatcheryId,
        );
        provider.setWarmupSeconds(30);

        await _emitReadings([reading1, reading2]);

        when(() => mockGovee.latestReading).thenReturn(null);
        await provider.stopSession();

        await provider.setActivePlace(TemperaturePlace.chickHoldingArea);
        await provider.startSession(
          customerId: TemperatureTestFixtures.testCustomerId,
          hatcheryId: TemperatureTestFixtures.testHatcheryId,
        );

        when(() => mockGovee.latestReading).thenReturn(null);
        await provider.stopSession();

        final allCaptured = verify(
          () => mockRepo.persistSessionSummary(captureAny()),
        ).captured;
        expect(allCaptured.length, greaterThanOrEqualTo(2));

        final secondSummary = allCaptured.last as TemperatureSessionModel;
        expect(secondSummary.readingCount, isNull);
        expect(secondSummary.tempAvg, isNull);
      },
    );
  });
}
