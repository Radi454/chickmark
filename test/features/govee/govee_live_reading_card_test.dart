import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:hatchaudit/features/govee/providers/govee_capture_provider.dart';
import 'package:hatchaudit/features/govee/widgets/govee_live_reading_card.dart';
import 'package:hatchaudit/providers/app_provider.dart';
import 'package:hatchaudit/services/govee/govee_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockGoveeCaptureRepository extends Mock
    implements GoveeCaptureRepository {}

class _MockGoveeService extends Mock implements GoveeService {}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('scan action is disabled while a compact-card scan is active', (
    tester,
  ) async {
    final repository = _MockGoveeCaptureRepository();
    final service = _MockGoveeService();
    when(() => service.isAvailable).thenReturn(true);
    when(() => service.isConnected).thenReturn(false);
    when(() => service.isGattConnected).thenReturn(false);
    when(() => service.isGattConnecting).thenReturn(false);
    when(() => service.isScanning).thenReturn(true);
    when(() => service.deviceName).thenReturn('Govee_H5051');
    when(() => service.deviceId).thenReturn(null);
    when(() => service.signalStrength).thenReturn(null);
    when(() => service.latestReading).thenReturn(null);
    when(() => service.lastSeenAt).thenReturn(null);
    when(() => service.diagnostics).thenReturn(const []);

    final provider = GoveeCaptureProvider(
      repository: repository,
      goveeService: service,
      enablePhaseTimer: false,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GoveeCaptureProvider>.value(value: provider),
          ChangeNotifierProvider<AppProvider>(create: (_) => AppProvider()),
        ],
        child: const MaterialApp(home: Scaffold(body: GoveeLiveReadingCard())),
      ),
    );
    await tester.pump();

    expect(find.text('Status: Scanning'), findsOneWidget);
    expect(find.text('Govee H5051'), findsOneWidget);

    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Scanning'),
    );
    expect(button.onPressed, isNull);
  });
}
