import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/hatchery_model.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/customers/widgets/add_customer_sheet.dart';
import 'package:hatchaudit/features/customers/widgets/add_hatchery_sheet.dart';
import 'package:hatchaudit/providers/customers_provider.dart';

void main() {
  testWidgets('legacy customer edit keeps blank sampling code', (tester) async {
    CustomerModel? updated;
    final original = _customer();
    final provider = _FakeCustomersProvider(
      onCustomer: (value) => updated = value,
    );
    await _openCustomerSheet(tester, provider, original);

    await tester.tap(find.byType(ElevatedButton).last);
    await _pump(tester);

    expect(updated?.id, original.id);
    expect(updated?.samplingCode, isNull);
  });

  testWidgets('invalid customer code prevents save', (tester) async {
    var saved = false;
    final provider = _FakeCustomersProvider(onCustomer: (_) => saved = true);
    await _openCustomerSheet(tester, provider, _customer());
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Customer sampling code'),
      'AB1',
    );
    await tester.tap(find.byType(ElevatedButton).last);
    await _pump(tester);

    expect(saved, isFalse);
    expect(
      find.text('Enter exactly three letters A–Z, or leave blank.'),
      findsOneWidget,
    );
  });

  testWidgets('legacy hatchery edit keeps blank sampling code', (tester) async {
    HatcheryModel? updated;
    final original = HatcheryModel(
      id: 'h-legacy',
      customerId: 'customer-1',
      name: 'Legacy hatchery',
      createdAt: DateTime(2024),
      createdBy: 'tester',
    );
    final provider = _FakeCustomersProvider(
      onHatchery: (value) => updated = value,
    );
    await _openHatcherySheet(tester, provider, original);

    await tester.tap(find.byType(ElevatedButton).last);
    await _pump(tester);

    expect(updated?.id, original.id);
    expect(updated?.samplingCode, isNull);
  });
}

CustomerModel _customer() => CustomerModel(
  id: 'customer-1',
  name: 'Legacy customer',
  createdAt: DateTime(2024),
  createdBy: 'tester',
);

Future<void> _openCustomerSheet(
  WidgetTester tester,
  _FakeCustomersProvider provider,
  CustomerModel initial,
) async {
  await _open(
    tester,
    provider,
    (context) => AddCustomerSheet(initialCustomer: initial),
  );
}

Future<void> _openHatcherySheet(
  WidgetTester tester,
  _FakeCustomersProvider provider,
  HatcheryModel initial,
) async {
  await _open(
    tester,
    provider,
    (context) => AddHatcherySheet(
      customerId: initial.customerId,
      initialHatchery: initial,
    ),
  );
}

Future<void> _open(
  WidgetTester tester,
  _FakeCustomersProvider provider,
  Widget Function(BuildContext) sheet,
) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<CustomersProvider>.value(value: provider),
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: sheet,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await _pump(tester);
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

class _FakeCustomersProvider extends CustomersProvider {
  _FakeCustomersProvider({this.onCustomer, this.onHatchery});

  final void Function(CustomerModel)? onCustomer;
  final void Function(HatcheryModel)? onHatchery;

  @override
  Future<void> addCustomer(CustomerModel customer) async =>
      onCustomer?.call(customer);

  @override
  Future<void> updateCustomer(CustomerModel customer) async =>
      onCustomer?.call(customer);

  @override
  Future<void> selectCustomer(CustomerModel customer) async {}

  @override
  Future<void> addHatchery(HatcheryModel hatchery) async =>
      onHatchery?.call(hatchery);

  @override
  Future<void> updateHatchery(HatcheryModel hatchery) async =>
      onHatchery?.call(hatchery);

  @override
  Future<void> loadCustomers({
    UserModel? currentUser,
    bool syncRemote = false,
  }) async {}
}
