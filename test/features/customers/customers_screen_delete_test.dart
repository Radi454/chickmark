import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/customers/screens/customers_screen.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/services/supabase/startup_sync_service.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';

class _MockSupabaseService extends Mock implements SupabaseService {}

void main() {
  testWidgets('cancel keeps customer and does not sync', (tester) async {
    var syncCalls = 0;
    final customersProvider = _FakeCustomersProvider([
      _customer('customer-1', 'Blue Valley Farms'),
    ]);
    await _pumpCustomersScreen(
      tester,
      customersProvider: customersProvider,
      syncAfterDelete: ({userId}) async {
        syncCalls++;
        return const SyncOutcome(online: true, pendingDeletes: 0);
      },
    );

    await tester.tap(find.byTooltip('Delete customer'));
    await _pumpUi(tester);
    expect(find.text('Delete customer?'), findsOneWidget);
    expect(find.text('Blue Valley Farms'), findsOneWidget);
    expect(find.textContaining('including its flocks'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await _pumpUi(tester);

    expect(customersProvider.hasCustomer('customer-1'), isTrue);
    expect(syncCalls, 0);
  });

  testWidgets('confirm deletes customer and reports synchronized cloud delete', (
    tester,
  ) async {
    var syncCalls = 0;
    final customersProvider = _FakeCustomersProvider([
      _customer('customer-1', 'Blue Valley Farms'),
    ]);
    await _pumpCustomersScreen(
      tester,
      customersProvider: customersProvider,
      syncAfterDelete: ({userId}) async {
        syncCalls++;
        return const SyncOutcome(online: true, pendingDeletes: 0);
      },
    );

    await tester.tap(find.byTooltip('Delete customer'));
    await _pumpUi(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await _pumpUi(tester);

    expect(customersProvider.hasCustomer('customer-1'), isFalse);
    expect(syncCalls, 1);
    expect(find.textContaining('deleted and synchronized'), findsOneWidget);
  });

  testWidgets('confirm deletes customer and reports pending cloud delete', (
    tester,
  ) async {
    var syncCalls = 0;
    final customersProvider = _FakeCustomersProvider([
      _customer('customer-1', 'Blue Valley Farms'),
    ]);
    await _pumpCustomersScreen(
      tester,
      customersProvider: customersProvider,
      syncAfterDelete: ({userId}) async {
        syncCalls++;
        return const SyncOutcome(online: false, pendingDeletes: 1);
      },
    );

    await tester.tap(find.byTooltip('Delete customer'));
    await _pumpUi(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await _pumpUi(tester);

    expect(customersProvider.hasCustomer('customer-1'), isFalse);
    expect(syncCalls, 1);
    expect(
      find.textContaining('cloud deletion is pending sync'),
      findsOneWidget,
    );
  });
}

CustomerModel _customer(String id, String name) {
  return CustomerModel(
    id: id,
    name: name,
    createdAt: DateTime(2026, 7, 5),
    createdBy: 'tester',
  );
}

Future<void> _pumpCustomersScreen(
  WidgetTester tester, {
  required _FakeCustomersProvider customersProvider,
  required Future<SyncOutcome> Function({String? userId}) syncAfterDelete,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<CustomersProvider>.value(
          value: customersProvider,
        ),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(
            supabaseService: _MockSupabaseService(),
            bypassAuth: true,
          ),
        ),
      ],
      child: MaterialApp(
        home: CustomersScreen(syncAfterDelete: syncAfterDelete),
      ),
    ),
  );
  await _pumpUi(tester);
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

class _FakeCustomersProvider extends CustomersProvider {
  _FakeCustomersProvider(List<CustomerModel> customers)
    : _customers = List<CustomerModel>.of(customers);

  final List<CustomerModel> _customers;

  bool hasCustomer(String id) =>
      _customers.any((customer) => customer.id == id);

  @override
  List<CustomerModel> get allCustomers => List.unmodifiable(_customers);

  @override
  List<CustomerModel> get filteredCustomers => allCustomers;

  @override
  String get searchQuery => '';

  @override
  Map<String, int> get flockCounts => const <String, int>{};

  @override
  bool get isLoading => false;

  @override
  bool customerHasEstimatedFlockAge(String customerId) => false;

  @override
  void setSearchQuery(String query) {}

  @override
  Future<void> loadCustomers({
    UserModel? currentUser,
    bool syncRemote = false,
  }) async {}

  @override
  Future<void> deleteCustomer(String customerId) async {
    _customers.removeWhere((customer) => customer.id == customerId);
    notifyListeners();
  }
}
