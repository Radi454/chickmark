import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

  AuditContextData contextData(String auditType) => AuditContextData(
    auditType: auditType,
    customerId: 'customer-1',
    flockId: 'flock-1',
    breed: 'Ross 308',
    setterId: 'Setter A',
    hatcherId: 'Hatcher B',
    flockAgeWeeks: 42,
    date: '2026-04-27',
  );

  Future<void> pumpScreen(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuditProvider()),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: MockSupabaseService()),
          ),
        ],
        child: MaterialApp(home: child),
      ),
    );
    await tester.pump();
  }

  testWidgets('Setters uses the professional audit workbench structure', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(
      tester,
      SetterOptimizingScreen(context: contextData('Setters')),
    );

    expect(
      find.byKey(const ValueKey('setter-workbench-shell')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('setter-station-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('setter-panel-setup')), findsOneWidget);
    expect(find.byKey(const ValueKey('setter-panel-machine')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('setter-panel-environment')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('setter-panel-est')), findsOneWidget);
    expect(find.text('Machine setup'), findsOneWidget);
    expect(find.text('Egg Shell Temperature'), findsOneWidget);
    expect(find.text('SETTER WORKBENCH'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('Hatchers uses the professional audit workbench structure', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(
      tester,
      HatcherOptimizingScreen(context: contextData('Hatchers')),
    );

    expect(
      find.byKey(const ValueKey('hatcher-workbench-shell')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('hatcher-station-header')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('hatcher-panel-setup')), findsOneWidget);
    expect(find.byKey(const ValueKey('hatcher-panel-cvt')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('hatcher-panel-observations')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('hatcher-panel-transfer')),
      findsOneWidget,
    );
    expect(find.text('Chick Vent Temperature'), findsOneWidget);
    expect(find.text('HATCHER WORKBENCH'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('Setters and Hatchers workbench headers fit mobile width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(
      tester,
      SetterOptimizingScreen(context: contextData('Setters')),
    );

    expect(
      find.byKey(const ValueKey('setter-workbench-shell')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('setter-station-header')), findsOneWidget);
    expect(find.text('SETTER WORKBENCH'), findsOneWidget);

    await pumpScreen(
      tester,
      HatcherOptimizingScreen(context: contextData('Hatchers')),
    );

    expect(
      find.byKey(const ValueKey('hatcher-workbench-shell')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('hatcher-station-header')),
      findsOneWidget,
    );
    expect(find.text('HATCHER WORKBENCH'), findsOneWidget);
  });
}
