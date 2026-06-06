import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/providers/audit_session_provider.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/home/screens/home_screen.dart';
import 'package:hatchaudit/features/settings/providers/settings_provider.dart';
import 'package:hatchaudit/widgets/app_card.dart';
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

  testWidgets('home shows the logo before the app bar title', (tester) async {
    await pumpHome(tester);

    final appBarLogo = find.byKey(const ValueKey('home-appbar-logo'));
    final bodyLogoHeader = find.byKey(const ValueKey('home-logo-header'));
    final title = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('ChickMark'),
    );

    expect(ChickMarkLogo.assetPath, 'assets/branding/chickmark-icon.png');
    expect(appBarLogo, findsOneWidget);
    expect(bodyLogoHeader, findsNothing);
    expect(title, findsOneWidget);
    expect(
      tester.getCenter(appBarLogo).dx,
      lessThan(tester.getCenter(title).dx),
    );
    // The app-bar brand mark is an egg-shaped badge (40×52) — taller than the
    // old inline 30px logo. Guard that it still fits within the toolbar.
    expect(tester.getSize(appBarLogo).height, lessThanOrEqualTo(52));
  });

  testWidgets('active flocks KPI uses a poultry flock icon', (tester) async {
    await pumpHome(tester);

    final activeFlocksCard = find.ancestor(
      of: find.text('Active flocks'),
      matching: find.byType(AppCard),
    );

    expect(activeFlocksCard, findsOneWidget);
    expect(
      find.descendant(
        of: activeFlocksCard,
        matching: find.byKey(const ValueKey('home-active-flocks-flock-icon')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: activeFlocksCard,
        matching: find.byIcon(Icons.egg_alt_outlined),
      ),
      findsNothing,
    );
  });
}
