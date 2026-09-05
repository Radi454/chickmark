import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/features/customers/widgets/customer_sector_management_sheet.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:provider/provider.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;
  late CustomersProvider provider;

  setUpAll(() async => databaseDirectory = await useIsolatedAppDatabase());
  setUp(() async {
    await resetAppDatabase();
    final db = await DatabaseHelper().db;
    await db.delete('customers');
    await db.insert('customers', {
      'id': 'customer-1',
      'name': 'Customer',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'createdBy': 'test',
    });
    provider = CustomersProvider();
  });
  tearDownAll(() async {
    await resetAppDatabase();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test('customer supports multiple sectors independently of hatchery management', () async {
    await provider.replaceCustomerSectors(
      'customer-1',
      PoultrySector.values.toSet(),
    );

    expect(provider.enabledSectors, PoultrySector.values.toSet());
    expect(provider.hatcheryManagementEnabled, isTrue);

    await provider.replaceCustomerSectors('customer-1', {
      PoultrySector.broiler,
    });
    expect(provider.enabledSectors, {PoultrySector.broiler});
    expect(provider.hatcheryManagementEnabled, isFalse);
  });

  testWidgets('sector sheet exposes breeder broiler and layer together', (
    tester,
  ) async {
    await tester.runAsync(
      () => provider.replaceCustomerSectors(
        'customer-1',
        PoultrySector.values.toSet(),
      ),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<CustomersProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(
            body: CustomerSectorManagementSheet(customerId: 'customer-1'),
          ),
        ),
      ),
    );

    expect(find.text('Breeder'), findsOneWidget);
    expect(find.text('Broiler'), findsOneWidget);
    expect(find.text('Layer'), findsOneWidget);
    expect(find.textContaining('Hatcheries belong to Breeder'), findsOneWidget);
  });
}
