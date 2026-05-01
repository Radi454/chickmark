import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/audits/screens/egg_storage_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
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
    auditType: 'Egg Storage',
    customerId: 'customer-1',
    flockId: 'flock-1',
    breed: 'Ross 308',
    flockAgeWeeks: 42,
    date: '2026-04-27',
  );

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuditProvider()),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: MockSupabaseService()),
          ),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
        ],
        child: MaterialApp(home: EggStorageScreen(context: contextData())),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders split egg storage workbench controls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester);

    expect(find.text('Egg'), findsWidgets);
    expect(find.text('Egg Storage & Handling'), findsNothing);
    expect(find.text('Egg Shell Temperature'), findsOneWidget);
    expect(find.text('19.0-21.0°C'), findsOneWidget);
    expect(find.text('Upside Down Score'), findsOneWidget);
    expect(find.text('Storage Checklist'), findsOneWidget);
    expect(find.text('Egg Quality Assessment'), findsOneWidget);
    expect(find.text('EQ'), findsNothing);
    expect(find.text('Weight uniformity and benchmark context'), findsNothing);
    expect(find.text('39 wks'), findsWidgets);
    expect(find.text('Egg Sample Mode'), findsOneWidget);
    expect(find.text('Multi House Samples'), findsOneWidget);

    final multiHouseChip = find.widgetWithText(
      ChoiceChip,
      'Multi House Samples',
    );
    await tester.ensureVisible(multiHouseChip);
    await tester.pump();
    await tester.tap(multiHouseChip);
    await tester.pumpAndSettle();

    expect(find.text('House Samples'), findsOneWidget);
    expect(find.byTooltip('Add house sample'), findsOneWidget);

    await tester.tap(find.byTooltip('Add house sample'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add house sample'));
    await tester.pumpAndSettle();

    final h3 = find.widgetWithText(ChoiceChip, 'H3');
    final addHouse = find.byTooltip('Add house sample');
    final removeHouse = find.byTooltip('Remove active house sample');

    expect(h3, findsOneWidget);
    expect(removeHouse, findsOneWidget);
    expect(tester.getCenter(addHouse).dx, greaterThan(tester.getCenter(h3).dx));
    expect(
      tester.getCenter(removeHouse).dx,
      greaterThan(tester.getCenter(addHouse).dx),
    );
    expect(tester.getTopLeft(addHouse).dy, tester.getTopLeft(removeHouse).dy);
  });
}
