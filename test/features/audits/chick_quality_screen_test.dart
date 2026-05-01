import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/audits/screens/chick_quality_screen.dart';
import 'package:hatchaudit/features/audits/widgets/audit_numeric_keyboard.dart';
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
    auditType: 'Chick Quality',
    customerId: 'customer-1',
    flockId: 'flock-1',
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
        ],
        child: MaterialApp(home: ChickQualityScreen(context: contextData())),
      ),
    );
    await tester.pump();
  }

  testWidgets('does not render the CHA Environment tab', (tester) async {
    await pumpScreen(tester);

    expect(find.text('CHA Environmental'), findsNothing);
    expect(find.text('Pasgar Score'), findsOneWidget);
    expect(find.text('Chick Weights'), findsOneWidget);
  });

  testWidgets(
    'pool mode hides machine fields; comparison mode shows sample tabs and +/- controls',
    (tester) async {
      await pumpScreen(tester);

      expect(find.text('Single Sample'), findsOneWidget);
      expect(find.text('Setter ID'), findsNothing);
      expect(find.text('Hatcher ID'), findsNothing);

      await tester.tap(find.text('Compare Samples'));
      await tester.pumpAndSettle();

      expect(find.text('Setter ID'), findsOneWidget);
      expect(find.text('Hatcher ID'), findsOneWidget);
      expect(find.text('Sample 1'), findsOneWidget);
      expect(find.byTooltip('Add sample'), findsOneWidget);
      expect(find.byTooltip('Remove active sample'), findsOneWidget);

      await tester.tap(find.byTooltip('Add sample'));
      await tester.pumpAndSettle();
      expect(find.text('Sample 2'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove active sample'));
      await tester.pumpAndSettle();
      expect(find.text('Sample 2'), findsNothing);
      expect(find.text('Sample 1'), findsOneWidget);
    },
  );

  testWidgets('compare mode setter and hatcher IDs use audit numeric fields', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Compare Samples'));
    await tester.pumpAndSettle();

    final setterField = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(AuditNumericFormField, 'Setter ID'),
        matching: find.byType(EditableText),
      ),
    );
    final hatcherField = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(AuditNumericFormField, 'Hatcher ID'),
        matching: find.byType(EditableText),
      ),
    );

    expect(setterField.keyboardType, TextInputType.none);
    expect(hatcherField.keyboardType, TextInputType.none);

    await tester.tap(find.widgetWithText(AuditNumericFormField, 'Setter ID'));
    await tester.pumpAndSettle();

    expect(find.byType(AuditNumericKeyboard), findsOneWidget);
  });
}
