import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/bmk_operational_standard_model.dart';
import 'package:hatchaudit/data/repositories/bmk_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  setUp(_resetDatabase);

  tearDown(() async {
    await DatabaseHelper().close();
  });

  test('fresh database seeds global operational BMK rows', () async {
    final repository = BmkRepository();
    final rows = await repository.getOperationalStandards();

    expect(rows, isNotEmpty);
    expect(
      rows.map((row) => row.metricKey),
      containsAll([
        'egg_storage_est_short',
        'setter_est_optimal',
        'chicks_cvt',
        'hatcher_cvt',
        'co2_max',
      ]),
    );
    final eggStorageShort = rows.firstWhere(
      (row) => row.metricKey == 'egg_storage_est_short',
    );
    expect(eggStorageShort.stationKey, 'egg');
    expect(eggStorageShort.minValue, 19);
    expect(eggStorageShort.maxValue, 21);
    expect(eggStorageShort.unit, '°C');
  });

  test('hatchery-specific operational BMK overrides global value', () async {
    final db = await DatabaseHelper().db;
    await db.insert('customers', {
      'id': 'customer-1',
      'name': 'Farm One',
      'createdAt': '2026-06-22T08:00:00.000',
    });
    await db.insert('hatcheries', {
      'id': 'hatchery-1',
      'customerId': 'customer-1',
      'name': 'Hatchery One',
      'createdAt': '2026-06-22T08:00:00.000',
    });

    final repository = BmkRepository();
    await repository.upsertOperationalStandard(
      BmkOperationalStandardModel(
        id: 'hatchery-1-chicks-cvt',
        hatcheryId: 'hatchery-1',
        stationKey: 'chicks',
        sectorKey: 'cvt',
        metricKey: 'chicks_cvt',
        metricLabel: 'Chicks CVT',
        unit: '°F',
        minValue: 102.5,
        maxValue: 104.5,
        sortOrder: 10,
      ),
    );

    final rows = await repository.getOperationalStandards(
      hatcheryId: 'hatchery-1',
    );
    final cvt = rows.firstWhere((row) => row.metricKey == 'chicks_cvt');

    expect(cvt.hatcheryId, 'hatchery-1');
    expect(cvt.minValue, 102.5);
    expect(cvt.maxValue, 104.5);
  });

  test('loads hatchery choices for operational BMK setup', () async {
    final db = await DatabaseHelper().db;
    await db.insert('customers', {
      'id': 'customer-1',
      'name': 'Farm One',
      'createdAt': '2026-06-22T08:00:00.000',
    });
    await db.insert('hatcheries', {
      'id': 'hatchery-1',
      'customerId': 'customer-1',
      'name': 'Hatchery One',
      'createdAt': '2026-06-22T08:00:00.000',
    });

    final repository = BmkRepository();
    final hatcheries = await repository.getOperationalHatcheries();

    expect(hatcheries.single.id, 'hatchery-1');
    expect(hatcheries.single.label, 'Farm One · Hatchery One');
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
