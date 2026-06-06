import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

class MockSupabaseService extends Mock implements SupabaseService {}

class _TestCustomersProvider extends CustomersProvider {
  @override
  Future<void> loadCustomers({
    UserModel? currentUser,
    bool syncRemote = false,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  setUp(_resetDatabase);

  tearDown(() async {
    await DatabaseHelper().close();
  });

  testWidgets('customer picker exposes an add customer action in the header', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthProvider(
              bypassAuth: true,
              supabaseService: MockSupabaseService(),
            ),
          ),
          ChangeNotifierProvider<CustomersProvider>(
            create: (_) => _TestCustomersProvider(),
          ),
          ChangeNotifierProvider(
            create: (_) => AuditProvider(autosaveEnabled: false),
          ),
        ],
        child: const MaterialApp(home: AuditContextScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.warehouse_outlined), findsOneWidget);
    expect(find.byKey(const ValueKey('flock-chick-icon')), findsOneWidget);
    expect(find.byIcon(Icons.egg_alt_outlined), findsNothing);
    expect(find.byIcon(Icons.business_outlined), findsNothing);
    expect(find.byIcon(Icons.factory_outlined), findsNothing);
    expect(find.byIcon(Icons.pets), findsNothing);

    await tester.tap(find.text('Select customer'));
    await tester.pumpAndSettle();

    expect(find.text('Select Customer'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Add'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Add New Customer'), findsOneWidget);
  });

  testWidgets('customer picker closes when tapping the dimmed backdrop', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthProvider(
              bypassAuth: true,
              supabaseService: MockSupabaseService(),
            ),
          ),
          ChangeNotifierProvider<CustomersProvider>(
            create: (_) => _TestCustomersProvider(),
          ),
          ChangeNotifierProvider(
            create: (_) => AuditProvider(autosaveEnabled: false),
          ),
        ],
        child: const MaterialApp(home: AuditContextScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select customer'));
    await tester.pumpAndSettle();

    expect(find.text('Select Customer'), findsOneWidget);
    expect(
      tester
          .widget<DraggableScrollableSheet>(
            find.byType(DraggableScrollableSheet),
          )
          .expand,
      isFalse,
    );

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('Select Customer'), findsNothing);
  });
}

Future<void> _resetDatabase() async {
  await DatabaseHelper().close();
  final dbPath = p.join(
    await databaseFactory.getDatabasesPath(),
    'hatchaudit.db',
  );
  await databaseFactory.deleteDatabase(dbPath);
}
