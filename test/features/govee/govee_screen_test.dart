import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:hatchaudit/features/dashboard/models/govee_capture_summary.dart';
import 'package:hatchaudit/features/govee/providers/govee_capture_provider.dart';
import 'package:hatchaudit/features/govee/screens/govee_screen.dart';
import 'package:hatchaudit/features/govee/widgets/govee_floating_launcher.dart';
import 'package:hatchaudit/features/govee/widgets/govee_review_sheet.dart';
import 'package:hatchaudit/features/temperature/providers/temperature_rh_provider.dart';
import 'package:hatchaudit/features/audits/providers/audit_session_provider.dart';
import 'package:hatchaudit/providers/app_provider.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockGoveeCaptureRepository extends Mock
    implements GoveeCaptureRepository {}

Widget buildGoveeTestApp(GoveeCaptureRepository repository) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => GoveeCaptureProvider()),
      ChangeNotifierProvider(create: (_) => CustomersProvider()),
    ],
    child: MaterialApp(home: GoveeScreen(repository: repository)),
  );
}

Widget buildReviewTestApp() {
  return MaterialApp(
    home: Scaffold(
      body: GoveeReviewSheet(
        initialLabels: const ['Spot 1', 'Spot 2', 'Spot 3'],
        onSave: (_) async {},
      ),
    ),
  );
}

void main() {
  late MockGoveeCaptureRepository repository;

  setUp(() {
    repository = MockGoveeCaptureRepository();
    when(
      () => repository.getCaptureSummaries(
        customerId: any(named: 'customerId'),
        hatcheryId: any(named: 'hatcheryId'),
        captureDate: any(named: 'captureDate'),
        place: any(named: 'place'),
      ),
    ).thenAnswer((_) async => const <GoveeCaptureSummary>[]);
  });

  testWidgets('Govee screen shows saved captures instead of active recording', (
    tester,
  ) async {
    await tester.pumpWidget(buildGoveeTestApp(repository));
    await tester.pump();

    expect(find.text('Govee'), findsOneWidget);
    expect(find.text('Saved Govee captures'), findsOneWidget);
    expect(find.text('Start Spot 1'), findsNothing);
    expect(find.text('No measures yet'), findsNothing);
  });

  testWidgets('floating launcher opens active Govee capture overlay', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppProvider()),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
          ChangeNotifierProvider(create: (_) => GoveeCaptureProvider()),
          ChangeNotifierProvider(create: (_) => TemperatureRhProvider()),
          ChangeNotifierProvider(create: (_) => AuditSessionProvider()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: GoveeFloatingLauncher(initializeLiveCardOnOpen: false),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(GoveeFloatingLauncher));
    await tester.pumpAndSettle();

    expect(find.text('Govee capture'), findsOneWidget);
    expect(find.text('Govee H5051'), findsOneWidget);
    expect(find.text('Start Spot 1'), findsOneWidget);
  });

  testWidgets('review allows editing spot labels only', (tester) async {
    await tester.pumpWidget(buildReviewTestApp());

    expect(find.text('Spot 1'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('govee-spot-label-1')),
      'Door',
    );
    await tester.pump();

    expect(find.text('Door'), findsOneWidget);
    expect(find.text('Customer'), findsNothing);
    expect(find.text('Hatchery'), findsNothing);
  });
}
