import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/repositories/customer_repository.dart';
import 'package:hatchaudit/data/repositories/flock_repository.dart';

import '../../support/test_database.dart';

/// Reproduction harness for the mobile "refuses to create or edit flocks"
/// report: exercises the REAL DatabaseHelper schema (full _onCreate at v57),
/// not a hand-built test schema, through the exact repo calls the
/// add-flock sheet makes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  tearDownAll(() async {
    await DatabaseHelper().close();
  });

  test('insertFlock and updateFlock succeed against the real v57 schema',
      () async {
    final customers = CustomerRepository();
    final flocks = FlockRepository();

    await customers.insertCustomer(
      CustomerModel(
        id: 'repro-customer-1',
        name: 'Repro Customer',
        createdAt: DateTime(2026, 8, 1),
        createdBy: 'tester',
      ),
    );

    final flock = FlockModel(
      id: 'repro-flock-1',
      customerId: 'repro-customer-1',
      flockId: 'F-100',
      breed: 'Ross308',
      entryDate: DateTime(2026, 6, 1),
      isAgeEstimated: false,
      status: FlockModel.activeStatus,
      depletionAgeWeeks: FlockModel.defaultDepletionAgeWeeks,
    );

    await flocks.insertFlock(flock);
    await flocks.updateFlock(flock);

    final row = (await (await DatabaseHelper().db)
            .query('flocks', where: 'id = ?', whereArgs: ['repro-flock-1']))
        .single;
    expect(row['syncStatus'], 'pending');
    expect(row['dirtyAt'], isNotNull);
  });
}
