import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/bmk_operational_standard_model.dart';
import 'package:hatchaudit/data/repositories/bmk_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

// resetAppDatabase() only closes the singleton's open handle; the on-disk
// file at the isolated suite path is left in place, so state (and seeded
// operational-standard rows) would otherwise leak between tests in this
// file. Delete the file each time, matching
// bmk_operational_standards_test.dart's `_resetDatabase` pattern.
Future<void> _resetDatabase() async {
  await DatabaseHelper().close();
  final dbPath = p.join(
    await databaseFactory.getDatabasesPath(),
    'hatchaudit.db',
  );
  await databaseFactory.deleteDatabase(dbPath);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  setUp(_resetDatabase);

  tearDown(resetAppDatabase);

  BmkOperationalStandardModel standard(String id, {String? hatcheryId}) {
    return BmkOperationalStandardModel(
      id: id,
      hatcheryId: hatcheryId,
      stationKey: 'setter',
      sectorKey: 'incubation',
      metricKey: 'setter_temp',
      metricLabel: 'Setter temperature',
      unit: 'F',
      minValue: 99.0,
      maxValue: 100.5,
      targetValue: 99.8,
      sortOrder: 1,
    );
  }

  test('local edits are marked dirty and returned by getDirtyOperationalRows',
      () async {
    final repo = BmkRepository();
    await repo.upsertOperationalStandard(standard('std-1'));

    final dirty = await repo.getDirtyOperationalRows();

    expect(dirty, hasLength(1));
    expect(dirty.single['id'], 'std-1');
    expect(dirty.single['syncStatus'], 'pending');
    expect(dirty.single['dirtyAt'], isNotNull);
  });

  test('markOperationalRowsSynced clears the dirty flag', () async {
    final repo = BmkRepository();
    await repo.upsertOperationalStandard(standard('std-1'));
    await repo.getDirtyOperationalRows();

    await repo.markOperationalRowsSynced(['std-1']);

    expect(await repo.getDirtyOperationalRows(), isEmpty);
    expect(await repo.getOperationalRowSyncStatus('std-1'), 'synced');
  });

  test('markOperationalRowsFailed records the error and keeps the row dirty',
      () async {
    final repo = BmkRepository();
    await repo.upsertOperationalStandard(standard('std-1'));
    await repo.getDirtyOperationalRows();

    await repo.markOperationalRowsFailed(['std-1'], StateError('boom'));

    expect(await repo.getOperationalRowSyncStatus('std-1'), 'failed');
    expect(await repo.getDirtyOperationalRows(), hasLength(1));
  });

  test('upsertOperationalStandardRow converts a snake_case cloud row',
      () async {
    final repo = BmkRepository();

    await repo.upsertOperationalStandardRow({
      'id': 'std-cloud',
      'hatchery_id': null,
      'station_key': 'hatcher',
      'sector_key': 'incubation',
      'metric_key': 'hatcher_humidity',
      'metric_label': 'Hatcher humidity',
      'unit': '%',
      'min_value': 50.0,
      'max_value': 60.0,
      'target_value': 55.0,
      'sort_order': 2,
      'updated_at': '2026-08-14T00:00:00.000Z',
    });

    // Fresh databases already seed a couple dozen global operational
    // standards (see kBmkOperationalStandardSeeds), so assert on the pulled
    // row specifically rather than the full row count.
    final rows = await repo.getOperationalStandards();
    final pulled = rows.where((row) => row.id == 'std-cloud');
    expect(pulled, hasLength(1));
    expect(pulled.single.metricKey, 'hatcher_humidity');
    expect(pulled.single.targetValue, 55.0);
  });

  test('a pulled row is not dirty', () async {
    final repo = BmkRepository();

    await repo.upsertOperationalStandardRow({
      'id': 'std-cloud',
      'station_key': 'hatcher',
      'sector_key': 'incubation',
      'metric_key': 'hatcher_humidity',
      'metric_label': 'Hatcher humidity',
      'sort_order': 0,
    });

    expect(await repo.getDirtyOperationalRows(), isEmpty);
  });
}
