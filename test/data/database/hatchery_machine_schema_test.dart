import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

Future<Set<String>> _columns(Database db) async => (await db.rawQuery(
  "PRAGMA table_info('hatchery_machines')",
)).map((row) => row['name'] as String).toSet();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  tearDown(resetAppDatabase);

  test('fresh database creates the v83 machine catalog', () async {
    await useIsolatedAppDatabase();
    final db = await DatabaseHelper().db;
    expect(
      (await db.rawQuery('PRAGMA user_version')).single['user_version'],
      83,
    );
    expect(
      await _columns(db),
      containsAll([
        'id',
        'hatcheryId',
        'kind',
        'code',
        'name',
        'batchSize',
        'trolleyCapacity',
        'traySize',
        'trolleyCount',
        'traysPerTrolley',
        'createdAt',
        'updatedAt',
        'createdBy',
        'syncStatus',
        'dirtyAt',
        'lastSyncedAt',
        'syncError',
      ]),
    );
  });

  test(
    'v83 upgrade creates catalog and preserves existing hatchery rows',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute(
        'CREATE TABLE hatcheries(id TEXT PRIMARY KEY, name TEXT)',
      );
      await db.insert('hatcheries', {'id': 'h1', 'name': 'Existing'});

    await DatabaseHelper().applyV83UpgradeForTest(db);
    await db.insert('hatchery_machines', {
      'id': 'machine-1',
      'hatcheryId': 'h1',
      'kind': 'setter',
      'code': 'S-01',
      'name': 'Setter 1',
      'batchSize': 19200,
      'trolleyCapacity': 4800,
      'traySize': 150,
      'trolleyCount': 4,
      'traysPerTrolley': 32,
    });
    await DatabaseHelper().applyV83UpgradeForTest(db);

    expect((await db.query('hatcheries')).single['name'], 'Existing');
    expect((await db.query('hatchery_machines')).single['id'], 'machine-1');
      expect(
        await _columns(db),
        containsAll(['id', 'hatcheryId', 'kind', 'code']),
      );
    },
  );
}
