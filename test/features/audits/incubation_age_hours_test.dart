import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/audits/screens/hatcher_optimizing_screen.dart';
import 'package:hatchaudit/features/audits/screens/setter_optimizing_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockSupabaseService extends Mock implements SupabaseService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const connectivityChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (call) async {
          if (call.method == 'check') return ['wifi'];
          return null;
        });
  });

  AuditContextData hatcherContext() => AuditContextData(
    auditType: 'Hatchers',
    customerId: 'customer-1',
    flockId: 'flock-1',
    breed: 'Ross 308',
    hatcherId: 'H-01',
    date: '2026-04-27',
  );

  AuditContextData setterContext() => AuditContextData(
    auditType: 'Setters',
    customerId: 'customer-1',
    flockId: 'flock-1',
    breed: 'Ross 308',
    setterId: '5',
    date: '2026-04-27',
  );

  Future<AuditProvider> pumpHatcherScreen(WidgetTester tester) async {
    final provider = AuditProvider(autosaveEnabled: false);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuditProvider>.value(value: provider),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: MockSupabaseService()),
          ),
        ],
        child: MaterialApp(
          home: HatcherOptimizingScreen(context: hatcherContext()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return provider;
  }

  Future<AuditProvider> pumpSetterScreen(WidgetTester tester) async {
    final provider = AuditProvider(autosaveEnabled: false);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuditProvider>.value(value: provider),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: MockSupabaseService()),
          ),
        ],
        child: MaterialApp(
          home: SetterOptimizingScreen(context: setterContext()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return provider;
  }

  testWidgets('Hatcher incubation age includes a selectable hour offset', (
    tester,
  ) async {
    final provider = await pumpHatcherScreen(tester);

    expect(find.text('Incubation Age: 18 days'), findsOneWidget);
    expect(find.text('Incubation Hours: 0 hours'), findsOneWidget);

    final hoursSlider = tester.widget<Slider>(
      find.byKey(const ValueKey('hatcher-incubation-hours-slider')),
    );
    hoursSlider.onChanged!(6);
    await tester.pump();

    expect(find.text('Incubation Hours: 6 hours'), findsOneWidget);
    expect(provider.activeDraft.toMap()['hoIncubationHours'], 6);
  });

  testWidgets('Setter incubation age includes a selectable hour offset', (
    tester,
  ) async {
    final provider = await pumpSetterScreen(tester);

    expect(find.text('Incubation Age: 1 days'), findsOneWidget);
    expect(find.text('Incubation Hours: 0 hours'), findsOneWidget);

    final hoursSlider = tester.widget<Slider>(
      find.byKey(const ValueKey('setter-incubation-hours-slider')),
    );
    hoursSlider.onChanged!(12);
    await tester.pump();

    expect(find.text('Incubation Hours: 12 hours'), findsOneWidget);
    expect(provider.activeDraft.toMap()['soIncubationHours'], 12);
  });

  testWidgets('Setter screen can add setter tabs labeled by setter number', (
    tester,
  ) async {
    final provider = await pumpSetterScreen(tester);

    expect(find.text('S5'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('setter-add-sample-button')));
    await tester.pump();

    expect(provider.sampleCount, 2);
    expect(
      provider.stationSampleMode,
      StationSampleModel.sampleModeComparison,
    );
    expect(find.text('S5'), findsOneWidget);
    expect(find.text('S2'), findsOneWidget);
  });

  testWidgets('Hatcher screen uses setter-style hatcher hierarchy', (
    tester,
  ) async {
    final provider = await pumpHatcherScreen(tester);

    expect(find.text('Hatchers'), findsWidgets);
    expect(find.text('H01'), findsOneWidget);
    expect(find.text('Hatcher settings'), findsOneWidget);
    expect(find.text('Hatcher number'), findsOneWidget);
    expect(find.text('CVT sample 1'), findsNothing);
    expect(find.text('Add hatcher'), findsOneWidget);
    expect(find.text('Add sample'), findsNothing);
    expect(find.text('Guided CVT capture'), findsOneWidget);
    expect(find.text('Hatcher type'), findsNothing);
    expect(find.text('Turning Angle (°)'), findsNothing);
    expect(find.text('Transfer Day'), findsNothing);
    expect(find.text('Dark greenish'), findsOneWidget);
    expect(find.text('Water'), findsOneWidget);
    expect(find.text('Greenish'), findsNothing);
    expect(find.text('Watery'), findsNothing);
    expect(
      tester.getTopLeft(find.text('H01')).dy,
      lessThan(tester.getTopLeft(find.text('Hatcher settings')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Hatcher settings')).dy,
      lessThan(tester.getTopLeft(find.text('Guided CVT capture')).dy),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('hatcher-add-sample-button')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('hatcher-add-sample-button')));
    await tester.pump();

    expect(provider.sampleCount, 2);
    expect(
      provider.stationSampleMode,
      StationSampleModel.sampleModeComparison,
    );
    expect(find.text('H01'), findsOneWidget);
    expect(find.text('H2'), findsOneWidget);
  });

  testWidgets('Hatchers do not show sample mode controls', (tester) async {
    await pumpHatcherScreen(tester);

    expect(find.text('Add setter'), findsNothing);

    expect(find.text('Sample Mode'), findsNothing);
    expect(find.text('Single Sample'), findsNothing);
    expect(find.text('Compare Samples'), findsNothing);
  });
}
