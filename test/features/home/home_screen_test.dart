import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/providers/audit_session_provider.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/home/screens/home_screen.dart';
import 'package:hatchaudit/features/settings/providers/settings_provider.dart';
import 'package:hatchaudit/widgets/chick_mark_logo.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSupabaseService extends Mock implements SupabaseService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpHome(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(
              supabaseService: _MockSupabaseService(),
              bypassAuth: true,
            ),
          ),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => DashboardProvider()),
          ChangeNotifierProvider(create: (_) => AuditSessionProvider()),
        ],
        child: const MaterialApp(home: HomeScreen(loadInitialData: false)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('attention focus card opens its first actionable item', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.tap(find.text('Attention'));
    await tester.pumpAndSettle();

    expect(find.text('Add New Customer'), findsOneWidget);
  });

  testWidgets('home uses the current compact logo mark', (tester) async {
    await pumpHome(tester);

    final logoHeader = find.byKey(const ValueKey('home-logo-header'));

    expect(ChickMarkLogo.assetPath, 'assets/branding/chickmark-icon.png');
    expect(logoHeader, findsOneWidget);
    expect(tester.getSize(logoHeader).width, lessThanOrEqualTo(64));
    expect(tester.getTopLeft(logoHeader).dx, lessThan(40));
  });
}
