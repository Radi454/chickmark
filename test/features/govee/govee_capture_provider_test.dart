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
  double temp = 72.0,
  double humidity = 56.0,
}) {
  return GoveeSensorReading(
    temperatureFahrenheit: temp,
    humidity: humidity,
    timestamp: timestamp,
  );
}

void main() {
  late MockGoveeCaptureRepository mockRepo;
  late MockGoveeService mockGovee;
  late FakeClock fakeClock;

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
        spotCount: 3,
        readingCount: 180,
        createdAt: DateTime(2026, 5, 2),
        updatedAt: DateTime(2026, 5, 2),
      ),
    );
    registerFallbackValue(<GoveeSpotCaptureModel>[]);
    registerFallbackValue(<GoveeSpotReadingModel>[]);
  });

  setUp(() {
    mockRepo = MockGoveeCaptureRepository();
    mockGovee = MockGoveeService();
    fakeClock = FakeClock(DateTime.parse('2026-05-02T10:00:00'));

    when(
      () => mockRepo.getCaptureForScope(
        customerId: any(named: 'customerId'),
        hatcheryId: any(named: 'hatcheryId'),
        place: any(named: 'place'),
        captureDate: any(named: 'captureDate'),
      ),
    ).thenAnswer((_) async => null);
    when(() => mockGovee.deviceId).thenReturn('device-1');
    when(() => mockGovee.deviceName).thenReturn('Govee H5051');
    when(() => mockGovee.signalStrength).thenReturn(-61);
    when(
      () => mockGovee.syncHistory(
        startedAt: any(named: 'startedAt'),
        endedAt: any(named: 'endedAt'),
      ),
    ).thenAnswer((invocation) async {
      final startedAt = invocation.namedArguments[#startedAt] as DateTime;
      return List.generate(60, (index) {
        return _reading(
          timestamp: startedAt.add(Duration(seconds: index)),
          temp: 70 + index / 100,
          humidity: 55 + index / 200,
        );
      });
    });
    when(
      () => mockRepo.saveReplacement(
        capture: any(named: 'capture'),
        spots: any(named: 'spots'),
        readings: any(named: 'readings'),
      ),
    ).thenAnswer((_) async {});
  });

  Future<GoveeCaptureProvider> configuredProvider() async {
    final provider = GoveeCaptureProvider(
      repository: mockRepo,
      goveeService: mockGovee,
      clock: fakeClock.now,
      enablePhaseTimer: false,
    );
    await provider.configure(
      customerId: 'customer-1',
      hatcheryId: 'hatchery-1',
      place: TemperaturePlace.eggStorageRoom,
      captureDate: '2026-05-02',
    );
    return provider;
  }

  test('spot cannot finish before warmup plus minimum valid window', () async {
    final provider = await configuredProvider();

    await provider.startCurrentSpot();
    fakeClock.elapse(const Duration(seconds: 119));

    expect(provider.canFinishCurrentSpot, isFalse);

    fakeClock.elapse(const Duration(seconds: 1));

    expect(provider.canFinishCurrentSpot, isTrue);
  });

  test('spot auto-ends after maximum valid window', () async {
    final provider = await configuredProvider();

    await provider.startCurrentSpot();
    fakeClock.elapse(
      GoveeCaptureProvider.warmupDuration +
          GoveeCaptureProvider.maximumValidDuration,
    );

    expect(provider.phase, GoveeSpotPhase.autoEnded);
    expect(provider.canFinishCurrentSpot, isTrue);
  });

  test('maximum valid recording window is fifteen minutes', () {
    expect(
      GoveeCaptureProvider.maximumValidDuration,
      const Duration(minutes: 15),
    );
  });

  test('bucket averaging compresses synced spot history to 60 readings', () {
    final readings = List.generate(300, (index) {
      return GoveeSensorReading(
        temperatureFahrenheit: 70 + (index / 100),
        humidity: 55 + (index / 200),
        timestamp: DateTime.parse(
          '2026-05-02T10:00:00',
        ).add(Duration(seconds: index)),
      );
    });

    final compressed = GoveeCaptureProvider.compressSyncedReadings(
      readings,
      targetCount: 60,
    );

    expect(compressed, hasLength(60));
    expect(compressed.first.temperatureFahrenheit, closeTo(70.02, 0.05));
    expect(compressed.first.humidity, closeTo(55.01, 0.05));
  });

  test('retrying failed sync preserves the original spot window', () async {
    final syncedWindows = <({DateTime startedAt, DateTime endedAt})>[];
    when(
      () => mockGovee.syncHistory(
        startedAt: any(named: 'startedAt'),
        endedAt: any(named: 'endedAt'),
      ),
    ).thenAnswer((invocation) async {
      final startedAt = invocation.namedArguments[#startedAt] as DateTime;
      final endedAt = invocation.namedArguments[#endedAt] as DateTime;
      syncedWindows.add((startedAt: startedAt, endedAt: endedAt));
      if (syncedWindows.length == 1) {
        return const <GoveeSensorReading>[];
      }
      return List.generate(60, (index) {
        return _reading(timestamp: startedAt.add(Duration(seconds: index)));
      });
    });
    final provider = await configuredProvider();

    await provider.startCurrentSpot();
    fakeClock.elapse(const Duration(seconds: 120));
    await provider.finishCurrentSpot();

    expect(provider.completedSpotCount, 0);
    expect(provider.error, contains('reconnect Govee'));

    fakeClock.elapse(const Duration(minutes: 10));
    await provider.finishCurrentSpot();

    expect(provider.completedSpotCount, 1);
    expect(syncedWindows, hasLength(2));
    expect(syncedWindows[1].startedAt, syncedWindows[0].startedAt);
    expect(syncedWindows[1].endedAt, syncedWindows[0].endedAt);
  });

  test(
    'savePlaceCapture persists one daily capture with three spots',
    () async {
      final provider = await configuredProvider();

      for (var spot = 0; spot < GoveeCaptureProvider.spotCount; spot += 1) {
        await provider.startCurrentSpot();
        fakeClock.elapse(const Duration(seconds: 120));
        await provider.finishCurrentSpot();
        fakeClock.elapse(const Duration(minutes: 1));
      }

      await provider.savePlaceCapture(spotLabels: ['Door', 'Middle', 'Back']);

      final captured = verify(
        () => mockRepo.saveReplacement(
          capture: captureAny(named: 'capture'),
          spots: captureAny(named: 'spots'),
          readings: captureAny(named: 'readings'),
        ),
      ).captured;
      final capture = captured[0] as GoveeDailyCaptureModel;
      final spots = captured[1] as List<GoveeSpotCaptureModel>;
      final readings = captured[2] as List<GoveeSpotReadingModel>;

      expect(capture.customerId, 'customer-1');
      expect(capture.hatcheryId, 'hatchery-1');
      expect(capture.place, TemperaturePlace.eggStorageRoom);
      expect(capture.captureDate, '2026-05-02');
      expect(capture.spotCount, 3);
      expect(capture.readingCount, 180);
      expect(spots.map((spot) => spot.spotLabel), ['Door', 'Middle', 'Back']);
      expect(spots.map((spot) => spot.readingCount), [60, 60, 60]);
      expect(readings, hasLength(180));
      expect(readings.first.readingIndex, 0);
      expect(readings.last.readingIndex, 59);
    },
  );

  test(
    'savePlaceCapture clears active spots and suggests next place',
    () async {
      final provider = await configuredProvider();

      for (var spot = 0; spot < GoveeCaptureProvider.spotCount; spot += 1) {
        await provider.startCurrentSpot();
        fakeClock.elapse(const Duration(seconds: 120));
        await provider.finishCurrentSpot();
        fakeClock.elapse(const Duration(minutes: 1));
      }

      await provider.savePlaceCapture(spotLabels: ['Door', 'Middle', 'Back']);

      expect(provider.phase, GoveeSpotPhase.saved);
      expect(provider.completedSpotCount, 0);
      expect(provider.suggestedNextPlace, TemperaturePlace.chickHoldingArea);
      expect(provider.place, TemperaturePlace.chickHoldingArea);
    },
  );
}
