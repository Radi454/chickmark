import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:hatchaudit/features/govee/providers/govee_capture_provider.dart';
import 'package:hatchaudit/features/govee/screens/govee_screen.dart';
import 'package:hatchaudit/features/govee/widgets/govee_active_capture_content.dart';
import 'package:hatchaudit/features/govee/widgets/govee_chart_preview.dart';
import 'package:hatchaudit/features/temperature/providers/temperature_rh_provider.dart';
import 'package:hatchaudit/providers/app_provider.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/services/govee/govee_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockGoveeCaptureRepository extends Mock
    implements GoveeCaptureRepository {}

class _MockGoveeService extends Mock implements GoveeService {}

class _MockTemperatureRhProvider extends Mock
    implements TemperatureRhProvider {}

class _FakeClock {
  DateTime _now;

  _FakeClock(this._now);

  DateTime now() => _now;

  void elapse(Duration duration) {
    _now = _now.add(duration);
  }
}

Widget buildGoveeTestApp({GoveeCaptureProvider? provider}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => provider ?? GoveeCaptureProvider()),
      ChangeNotifierProvider(create: (_) => CustomersProvider()),
    ],
    child: const MaterialApp(home: GoveeScreen()),
  );
}

Future<GoveeCaptureProvider> _configuredProvider({
  required _MockGoveeService govee,
  GoveeCaptureTarget target = GoveeCaptureTarget.room,
  _FakeClock? clock,
}) async {
  final repo = _MockGoveeCaptureRepository();
  when(
    () => repo.getCaptureForScope(
      customerId: any(named: 'customerId'),
      hatcheryId: any(named: 'hatcheryId'),
      stationKey: any(named: 'stationKey'),
      place: any(named: 'place'),
      machineId: any(named: 'machineId'),
      captureDate: any(named: 'captureDate'),
    ),
  ).thenAnswer((_) async => null);

  final provider = GoveeCaptureProvider(
    repository: repo,
    goveeService: govee,
    enablePhaseTimer: false,
    clock: clock?.now ?? () => DateTime.parse('2026-05-06T08:00:00'),
  );
  await provider.configure(
    customerId: 'customer-1',
    hatcheryId: 'hatchery-1',
    place: TemperaturePlace.setterRoom,
    captureDate: '2026-05-06',
    stationKey: 'setters',
    machineId: 'Setter 7',
    captureTarget: target,
  );
  return provider;
}

void _stubLiveGovee(
  _MockGoveeService govee, {
  bool connected = true,
  GoveeSensorReading? latest,
  Stream<GoveeSensorReading>? readings,
}) {
  when(() => govee.isAvailable).thenReturn(true);
  when(() => govee.isConnected).thenReturn(connected);
  when(() => govee.isGattConnected).thenReturn(connected);
  when(() => govee.isGattConnecting).thenReturn(false);
  when(() => govee.isScanning).thenReturn(false);
  when(() => govee.deviceName).thenReturn('Govee H5051');
  when(() => govee.deviceId).thenReturn('device-1');
  when(() => govee.signalStrength).thenReturn(-61);
  when(() => govee.latestReading).thenReturn(latest);
  when(() => govee.lastSeenAt).thenReturn(latest?.timestamp);
  when(() => govee.diagnostics).thenReturn(const []);
  when(
    () => govee.readings,
  ).thenAnswer((_) => readings ?? const Stream.empty());
}

void _stubTemperatureProvider(
  _MockTemperatureRhProvider provider, {
  List<GoveeSensorReading> readings = const [],
}) {
  final latest = readings.isEmpty ? null : readings.last;
  when(() => provider.isBleAvailable).thenReturn(true);
  when(() => provider.isSensorConnected).thenReturn(true);
  when(() => provider.isGattConnected).thenReturn(true);
  when(() => provider.isGattConnecting).thenReturn(false);
  when(() => provider.isScanning).thenReturn(false);
  when(() => provider.deviceName).thenReturn('Govee H5051');
  when(() => provider.signalStrength).thenReturn(-61);
  when(() => provider.batteryPercent).thenReturn(latest?.batteryPercent);
  when(() => provider.error).thenReturn(null);
  when(
    () => provider.liveTemperatureFahrenheit,
  ).thenReturn(latest?.temperatureFahrenheit);
  when(() => provider.liveHumidity).thenReturn(latest?.humidity);
  when(() => provider.liveUpdatedAt).thenReturn(latest?.timestamp);
  when(() => provider.lastSensorSeenAt).thenReturn(latest?.timestamp);
  when(() => provider.liveReadings).thenReturn(readings);
  when(() => provider.addListener(any())).thenReturn(null);
  when(() => provider.removeListener(any())).thenReturn(null);
}

void main() {
  setUpAll(() {
    registerFallbackValue(TemperaturePlace.eggStorageRoom);
  });

  testWidgets('Govee screen shows capture controls instead of saved history', (
    tester,
  ) async {
    await tester.pumpWidget(buildGoveeTestApp());

    expect(find.text('Govee'), findsOneWidget);
    expect(find.text('Start recording'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('No measures yet'), findsNothing);
  });

  testWidgets('redesigned live header shows device and latest reading', (
    tester,
  ) async {
    final govee = _MockGoveeService();
    _stubLiveGovee(
      govee,
      latest: GoveeSensorReading(
        temperatureFahrenheit: 99.5,
        humidity: 58.2,
        batteryPercent: 88,
        timestamp: DateTime.parse('2026-05-06T07:45:00'),
      ),
    );
    final provider = await _configuredProvider(govee: govee);

    await tester.pumpWidget(buildGoveeTestApp(provider: provider));

    expect(find.byKey(const ValueKey('govee-live-header')), findsOneWidget);
    expect(find.text('Govee H5051'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('99.5 F'), findsOneWidget);
    expect(find.text('58.2%'), findsOneWidget);
    expect(find.textContaining('Updated at'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Read'), findsOneWidget);
  });

  testWidgets('Setters entry offers room and inside-machine choices', (
    tester,
  ) async {
    final govee = _MockGoveeService();
    _stubLiveGovee(govee, connected: false);
    final provider = await _configuredProvider(govee: govee);

    await tester.pumpWidget(buildGoveeTestApp(provider: provider));

    expect(
      find.byKey(const ValueKey('govee-scope-room-choice')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('govee-scope-machine-choice')),
      findsOneWidget,
    );
    expect(find.text('Setter room'), findsWidgets);
    expect(find.text('Inside Setter 7'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('govee-scope-machine-choice')));
    await tester.pump();

    expect(provider.place, TemperaturePlace.insideSetter);
    expect(provider.machineId, 'Setter 7');
  });

  testWidgets('failed history sync shows retry as the primary action', (
    tester,
  ) async {
    final govee = _MockGoveeService();
    _stubLiveGovee(govee);
    when(() => govee.diagnostics).thenReturn(const [
      '08:04:58  Discovered Govee history characteristics',
      '08:05:21  History sync timed out. Keep the H5051 powered on and near the app, then retry sync.',
    ]);
    when(
      () => govee.syncHistory(
        startedAt: any(named: 'startedAt'),
        endedAt: any(named: 'endedAt'),
      ),
    ).thenThrow(StateError('history timed out'));
    final clock = _FakeClock(DateTime.parse('2026-05-06T08:00:00'));
    final provider = await _configuredProvider(govee: govee, clock: clock);

    await provider.startRecording();
    clock.elapse(const Duration(minutes: 5));
    await provider.stopAndSavePlaceCapture();
    await tester.pumpWidget(buildGoveeTestApp(provider: provider));

    expect(find.text('History sync failed'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Start recording'), findsNothing);
    final retryButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Retry sync'),
    );
    expect(retryButton.onPressed, isNotNull);
    expect(find.text('Sync diagnostics'), findsOneWidget);
    expect(find.textContaining('StateError'), findsOneWidget);
    expect(find.textContaining('history timed out'), findsWidgets);
    expect(find.textContaining('Govee H5051'), findsWidgets);
    expect(find.textContaining('History sync timed out'), findsOneWidget);
  });

  testWidgets('recording shows elapsed length and enabled stop action', (
    tester,
  ) async {
    final govee = _MockGoveeService();
    _stubLiveGovee(govee);
    final provider = await _configuredProvider(govee: govee);

    await provider.startRecording();
    await tester.pumpWidget(buildGoveeTestApp(provider: provider));

    final stopButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Stop and save'),
    );
    expect(stopButton.onPressed, isNotNull);
    expect(find.textContaining('Warmup'), findsNothing);
    expect(find.textContaining('Recording length 00:00'), findsOneWidget);
  });

  testWidgets(
    'active capture panel shows live preview charts while recording',
    (tester) async {
      final startedAt = DateTime.parse('2026-05-06T08:00:00');
      final readings = [
        GoveeSensorReading(
          temperatureFahrenheit: 98,
          humidity: 50,
          timestamp: startedAt,
        ),
        GoveeSensorReading(
          temperatureFahrenheit: 99,
          humidity: 51,
          timestamp: startedAt.add(const Duration(minutes: 1)),
        ),
      ];
      final govee = _MockGoveeService();
      final temperatureProvider = _MockTemperatureRhProvider();
      _stubLiveGovee(govee);
      _stubTemperatureProvider(temperatureProvider, readings: readings);
      final provider = await _configuredProvider(govee: govee);

      await provider.startRecording();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GoveeCaptureProvider>.value(value: provider),
            ListenableProvider<TemperatureRhProvider>.value(
              value: temperatureProvider,
            ),
            ChangeNotifierProvider(create: (_) => AppProvider()),
            ChangeNotifierProvider(create: (_) => CustomersProvider()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: GoveeActiveCaptureContent()),
          ),
        ),
      );

      expect(find.text('Temperature preview'), findsOneWidget);
      expect(find.text('Relative Humidity preview'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('govee-temperature-preview-chart')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('govee-rh-preview-chart')),
        findsOneWidget,
      );
    },
  );

  testWidgets('live chart preview renders temperature and RH charts', (
    tester,
  ) async {
    final startedAt = DateTime.parse('2026-05-06T08:00:00');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoveeChartPreview(
            machineId: 'Setter 7',
            readings: [
              GoveeSensorReading(
                temperatureFahrenheit: 98,
                humidity: 50,
                timestamp: startedAt,
              ),
              GoveeSensorReading(
                temperatureFahrenheit: 99,
                humidity: 51,
                timestamp: startedAt.add(const Duration(minutes: 1)),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Temperature preview'), findsOneWidget);
    expect(find.text('Relative Humidity preview'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('govee-temperature-preview-chart')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('govee-rh-preview-chart')),
      findsOneWidget,
    );
    expect(find.textContaining('live readings'), findsOneWidget);
    expect(find.textContaining('Setter 7'), findsWidgets);
  });
}
