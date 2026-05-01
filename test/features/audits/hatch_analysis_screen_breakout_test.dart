import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/models/egg_breakout_sample.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/audits/screens/hatch_analysis_screen.dart';
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

  AuditContextData contextData() => AuditContextData(
    auditType: 'Hatch Analysis',
    customerId: 'customer-1',
    flockId: 'flock-1',
    flockAgeWeeks: 42,
    date: '2026-04-27',
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required EggBreakoutType breakoutType,
    int storageDays = 5,
    int? candlingDay,
  }) async {
    final provider = AuditProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: MockSupabaseService()),
          ),
        ],
        child: MaterialApp(home: HatchAnalysisScreen(context: contextData())),
      ),
    );
    await tester.pumpAndSettle();
    provider.updateHatchField(0, 'ebBreakoutType', breakoutType.storageValue);
    provider.updateHatchField(0, 'haStorageDays', storageDays);
    provider.updateHatchField(0, 'ebStorageDays', storageDays);
    provider.updateHatchField(0, 'haTotalEggsSet', 100);
    if (candlingDay != null) {
      provider.updateHatchField(0, 'ebBreakoutAgeDays', candlingDay);
    }
    await tester.pumpAndSettle();
  }

  Future<void> addVisibleSample(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Add Sample'));
    await tester.pumpAndSettle();
  }

  testWidgets('fresh egg breakout hides hatchability and shows fresh items', (
    tester,
  ) async {
    await pumpScreen(tester, breakoutType: EggBreakoutType.freshEggBreakout);
    await addVisibleSample(tester);

    expect(find.text('Hatchability Results'), findsNothing);
    expect(find.text('Healthy Hatched'), findsNothing);
    expect(find.text('Culled'), findsNothing);
    expect(find.text('Dead at Hatch'), findsNothing);
    expect(find.text('Candling Day'), findsNothing);
    expect(find.text('BMK Age 289 days'), findsOneWidget);

    expect(find.text('Infertile'), findsOneWidget);
    expect(find.text('Early 24h'), findsOneWidget);
    expect(find.text('Early 48h'), findsOneWidget);
    expect(find.text('Early 72h / Blood ring'), findsOneWidget);
    expect(find.text('Black eye'), findsNothing);
    expect(find.text('Mid dead'), findsNothing);
  });

  testWidgets('candled egg breakout shows candling day and candled items', (
    tester,
  ) async {
    await pumpScreen(tester, breakoutType: EggBreakoutType.candledEggBreakout);
    await addVisibleSample(tester);

    expect(find.text('Hatchability Results'), findsNothing);
    expect(find.text('Candling Day'), findsOneWidget);
    expect(find.text('10'), findsWidgets);
    expect(find.text('BMK Age 279 days'), findsOneWidget);

    expect(find.text('Infertile'), findsOneWidget);
    expect(find.text('Early 24h'), findsOneWidget);
    expect(find.text('Early 48h'), findsOneWidget);
    expect(find.text('Early 72h / Blood ring'), findsOneWidget);
    expect(find.text('Black eye'), findsOneWidget);
    expect(find.text('Mid dead'), findsOneWidget);
  });

  testWidgets('residue hatch day shows hatchability and breakout samples', (
    tester,
  ) async {
    await pumpScreen(tester, breakoutType: EggBreakoutType.residueHatchDay);

    expect(find.text('Hatchability Results'), findsOneWidget);
    expect(find.text('Healthy Hatched'), findsOneWidget);
    expect(find.text('Breakout Samples'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Add Sample'), findsOneWidget);
    expect(find.text('BMK Age 268 days'), findsOneWidget);
  });
}
