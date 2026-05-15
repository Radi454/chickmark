import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/customers/screens/audit_detail_screen.dart';
import 'package:hatchaudit/providers/app_provider.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockSupabaseService extends Mock implements SupabaseService {}

class TestCustomersProvider extends CustomersProvider {
  final FlockModel flock;

  TestCustomersProvider(this.flock);

  @override
  FlockModel? flockById(String? id) => id == flock.id ? flock : null;
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      AuditModel(
        id: 'fallback',
        auditType: 'Chicks',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: DateTime(2026, 5, 15),
        hatchNumber: 1,
        status: 'draft',
        createdBy: 'auditor-1',
        createdAt: DateTime(2026, 5, 15),
        updatedAt: DateTime(2026, 5, 15),
      ),
    );
  });

  testWidgets(
    'chick editor falls back to flock breed when audit has no breed',
    (tester) async {
      final flock = FlockModel(
        id: 'flock-1',
        customerId: 'customer-1',
        flockId: 'flock-1',
        breed: 'Ross308',
        entryDate: DateTime(2025, 8, 1),
      );
      final customersProvider = TestCustomersProvider(flock);

      final audit = AuditModel(
        id: 'audit-chicks-1',
        auditType: 'Chicks',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: DateTime(2026, 5, 15),
        hatchNumber: 1,
        status: 'draft',
        createdBy: 'auditor-1',
        createdAt: DateTime(2026, 5, 15),
        updatedAt: DateTime(2026, 5, 15),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CustomersProvider>.value(
              value: customersProvider,
            ),
            ChangeNotifierProvider<AuditProvider>(
              create: (_) => AuditProvider(autosaveEnabled: false),
            ),
            ChangeNotifierProvider(
              create: (_) =>
                  AuthProvider(supabaseService: MockSupabaseService()),
            ),
            ChangeNotifierProvider(create: (_) => AppProvider()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => openAuditEditor(context, audit),
                      child: const Text('Open editor'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('chick-quality-panel-weights')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ross308'), findsOneWidget);
    },
  );
}
