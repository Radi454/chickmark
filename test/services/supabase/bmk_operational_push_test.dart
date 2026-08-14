import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/models/bmk_operational_standard_model.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/hatchery_model.dart';
import 'package:hatchaudit/data/repositories/bmk_repository.dart';
import 'package:hatchaudit/data/repositories/customer_repository.dart';
import 'package:hatchaudit/data/repositories/hatchery_repository.dart';

import '../../support/test_database.dart';
// Reuse the fake service + harness shared with the startup sync tests.
// `startup_sync_service_test.dart` uses mocktail mocks stubbed per test, so
// there is no reusable fake/buildService to import from it directly; the
// shared fake lives in startup_sync_harness.dart instead (see brief step 1).
import 'startup_sync_harness.dart' as harness;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  tearDown(resetAppDatabase);

  test('pushes dirty operational standards with snake_case columns', () async {
    await CustomerRepository().insertCustomer(
      CustomerModel(
        id: 'customer-a',
        name: 'Customer A',
        createdAt: DateTime(2026, 5, 1),
        createdBy: 'tester',
      ),
    );
    await HatcheryRepository().insertHatchery(
      HatcheryModel(
        id: 'hatchery-a',
        customerId: 'customer-a',
        name: 'Hatchery A',
        createdAt: DateTime(2026, 5, 1),
        createdBy: 'tester',
      ),
    );

    final repo = BmkRepository();
    await repo.upsertOperationalStandard(
      BmkOperationalStandardModel(
        id: 'std-1',
        hatcheryId: 'hatchery-a',
        stationKey: 'setter',
        sectorKey: 'incubation',
        metricKey: 'setter_temp',
        metricLabel: 'Setter temperature',
        unit: 'F',
        minValue: 99.0,
        maxValue: 100.5,
        targetValue: 99.8,
        sortOrder: 1,
      ),
    );

    final service = harness.buildService();
    await service.run();

    final pushed = harness.fakeSupabase.upserts['bmk_operational_standards'];
    expect(pushed, hasLength(1));
    expect(pushed!.single['station_key'], 'setter');
    expect(pushed.single['hatchery_id'], 'hatchery-a');
    expect(pushed.single['target_value'], 99.8);
    // Device-local sync columns never leave the device.
    expect(pushed.single.containsKey('syncStatus'), isFalse);
    expect(pushed.single.containsKey('dirtyAt'), isFalse);

    expect(await repo.getOperationalRowSyncStatus('std-1'), 'synced');
  });

  test('a failed push marks rows failed without aborting the sync', () async {
    final repo = BmkRepository();
    await repo.upsertOperationalStandard(
      BmkOperationalStandardModel(
        id: 'std-1',
        stationKey: 'setter',
        sectorKey: 'incubation',
        metricKey: 'setter_temp',
        metricLabel: 'Setter temperature',
        unit: 'F',
        sortOrder: 0,
      ),
    );

    final service = harness.buildService(
      failUpsertsFor: {'bmk_operational_standards'},
    );
    await service.run();

    expect(await repo.getOperationalRowSyncStatus('std-1'), 'failed');
  });
}
