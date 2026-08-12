import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/features/customers/widgets/add_flock_sheet.dart';
import 'package:hatchaudit/providers/customers_provider.dart';

void main() {
  testWidgets('save surfaces the failure instead of doing nothing', (
    tester,
  ) async {
    final provider = _FakeCustomersProvider(
      customer: _customer(),
      onAdd: (_) => throw StateError('This account has read-only access.'),
    );
    await _pumpSheet(tester, provider);

    await _fillForm(tester);
    await _tapSave(tester);

    expect(find.textContaining('read-only access'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Save'), findsOneWidget);
  });

  testWidgets('save reports a missing customer inside the sheet', (
    tester,
  ) async {
    final provider = _FakeCustomersProvider(customer: null);
    await _pumpSheet(tester, provider);

    await _fillForm(tester);
    await _tapSave(tester);

    expect(find.textContaining('No customer selected'), findsOneWidget);
  });

  testWidgets('successful save closes the sheet and keeps no error', (
    tester,
  ) async {
    final added = <FlockModel>[];
    final provider = _FakeCustomersProvider(
      customer: _customer(),
      onAdd: added.add,
    );
    await _pumpSheet(tester, provider);

    await _fillForm(tester);
    await _tapSave(tester);

    expect(added, hasLength(1));
    expect(added.single.flockId, 'F-100');
    expect(added.single.depletionAgeWeeks, 65);
    expect(find.byType(AddFlockSheet), findsNothing);
  });
}

Future<void> _tapSave(WidgetTester tester) async {
  final save = find.widgetWithText(ElevatedButton, 'Save');
  await tester.ensureVisible(save);
  await _pumpUi(tester);
  await tester.tap(save);
  await _pumpUi(tester);
}

Future<void> _fillForm(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Flock ID *'),
    'F-100',
  );
  await tester.tap(find.text('Current age'));
  await _pumpUi(tester);
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Current age weeks *'),
    '44',
  );
  await _pumpUi(tester);
}

Future<void> _pumpSheet(
  WidgetTester tester,
  _FakeCustomersProvider provider,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<CustomersProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showModalBottomSheet<FlockModel>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const AddFlockSheet(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await _pumpUi(tester);
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

CustomerModel _customer() => CustomerModel(
  id: 'customer-1',
  name: 'Blue Valley Farms',
  createdAt: DateTime(2026, 7, 5),
  createdBy: 'tester',
);

class _FakeCustomersProvider extends CustomersProvider {
  _FakeCustomersProvider({required CustomerModel? customer, this.onAdd})
    : _customer = customer;

  final CustomerModel? _customer;
  final void Function(FlockModel flock)? onAdd;

  @override
  CustomerModel? get selectedCustomer => _customer;

  @override
  Future<void> loadCustomers({
    UserModel? currentUser,
    bool syncRemote = false,
  }) async {}

  @override
  Future<void> addFlock(FlockModel flock) async {
    onAdd?.call(flock);
  }

  @override
  Future<void> updateFlock(FlockModel flock) async {
    onAdd?.call(flock);
  }
}
