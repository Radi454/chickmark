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

  testWidgets('editing a legacy flock can keep its optional code blank', (
    tester,
  ) async {
    FlockModel? updated;
    final legacy = FlockModel(
      id: 'flock-legacy',
      customerId: 'customer-1',
      flockId: 'F-100',
      breed: 'Ross308',
      entryDate: DateTime(2025),
    );
    final provider = _FakeCustomersProvider(
      customer: _customer(),
      onAdd: (flock) => updated = flock,
    );
    await _pumpSheet(tester, provider, initialFlock: legacy);

    await _tapSave(tester);

    expect(updated?.id, 'flock-legacy');
    expect(updated?.samplingCode, isNull);
    expect(find.byType(AddFlockSheet), findsNothing);
  });

  testWidgets('invalid optional code blocks flock save with localized error', (
    tester,
  ) async {
    var saved = false;
    final provider = _FakeCustomersProvider(
      customer: _customer(),
      onAdd: (_) => saved = true,
    );
    await _pumpSheet(tester, provider);
    await _fillForm(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Farm sampling code'),
      'A1',
    );
    await _tapSave(tester);

    expect(saved, isFalse);
    expect(
      find.text('Enter exactly three letters A–Z, or leave blank.'),
      findsOneWidget,
    );
  });
}

Future<void> _tapSave(WidgetTester tester) async {
  final save = find.byType(ElevatedButton).last;
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
  _FakeCustomersProvider provider, {
  FlockModel? initialFlock,
}) {
  return _showSheet(tester, provider, initialFlock: initialFlock);
}

Future<void> _showSheet(
  WidgetTester tester,
  _FakeCustomersProvider provider, {
  FlockModel? initialFlock,
}) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
                builder: (_) => AddFlockSheet(initialFlock: initialFlock),
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
