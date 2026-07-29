import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  setUp(_resetDatabase);

  tearDown(resetAppDatabase);

  group('surgical schema repair', () {
    test('missing critical table is restored on next open', () async {
      // Arrange — seed a healthy DB and remember a customer row.
      var db = await DatabaseHelper().db;
      await db.insert('customers', {
        'id': 'c1',
        'name': 'Repair Farm',
        'createdAt': '2026-06-06T00:00:00.000',
      });

      // Act — drop a critical table behind the helper's back, then reopen.
      await db.execute('DROP TABLE audit_sessions');
      await DatabaseHelper().close();
      db = await DatabaseHelper().db;

      // Assert — table back, intact customer survived.
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='audit_sessions'",
      );
      expect(tables, isNotEmpty,
          reason: 'audit_sessions should be restored by surgical repair');
      final customers = await db.query('customers', where: 'id = ?', whereArgs: ['c1']);
      expect(customers, hasLength(1));
      expect(customers.first['name'], 'Repair Farm');
    });

    test('intact data on other tables survives a repair pass', () async {
      // Arrange — populate three tables. `_ensureDummyTestData` will also
      // seed demo rows in non-release mode, so we assert on row presence and
      // total count diffs instead of fixed lengths.
      var db = await DatabaseHelper().db;
      final customersBefore = (await db.query('customers')).length;
      final flocksBefore = (await db.query('flocks')).length;
      final hatcheriesBefore = (await db.query('hatcheries')).length;
      await db.insert('customers', {
        'id': 'cust-keepme',
        'name': 'Keep Me',
        'createdAt': '2026-06-06T00:00:00.000',
      });
      await db.insert('flocks', {
        'id': 'f-keepme',
        'customerId': 'cust-keepme',
        'flockId': 'F-1',
        'breed': 'Ross308',
        'entryDate': '2026-01-01',
        'status': 'active',
      });
      await db.insert('hatcheries', {
        'id': 'h-keepme',
        'customerId': 'cust-keepme',
        'name': 'Hatch',
        'createdAt': '2026-06-06T00:00:00.000',
      });

      // Act — drop ONE peripheral table and reopen so repair fires.
      await db.execute('DROP TABLE sync_conflicts');
      await DatabaseHelper().close();
      db = await DatabaseHelper().db;

      // Assert — exactly the rows we inserted are still present (plus the
      // pre-existing seeds), and the dropped table got rebuilt empty.
      final customersAfter = await db.query('customers');
      final flocksAfter = await db.query('flocks');
      final hatcheriesAfter = await db.query('hatcheries');
      expect(customersAfter, hasLength(customersBefore + 1));
      expect(
        customersAfter.where((row) => row['id'] == 'cust-keepme'),
        hasLength(1),
      );
      expect(flocksAfter, hasLength(flocksBefore + 1));
      expect(
        flocksAfter.where((row) => row['id'] == 'f-keepme'),
        hasLength(1),
      );
      expect(hatcheriesAfter, hasLength(hatcheriesBefore + 1));
      expect(
        hatcheriesAfter.where((row) => row['id'] == 'h-keepme'),
        hasLength(1),
      );
      // Sync conflicts table is restored and empty (repair never reseeds it).
      final conflicts = await db.query('sync_conflicts');
      expect(conflicts, isEmpty);
    });

    test('missing column on audit_sessions is added by ALTER', () async {
      // Arrange — replace audit_sessions with a copy missing the `notes` col,
      // simulating an old-schema drift.
      var db = await DatabaseHelper().db;
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute('DROP TABLE audit_sessions');
      await db.execute('''CREATE TABLE audit_sessions (
        id TEXT PRIMARY KEY,
        customerId TEXT,
        flockId TEXT,
        hatcheryId TEXT,
        date TEXT
      )''');
      // Seed a row so we can prove ALTER preserves data.
      await db.insert('audit_sessions', {
        'id': 's1',
        'customerId': 'c1',
        'flockId': 'f1',
        'hatcheryId': 'h1',
        'date': '2026-06-06',
      });

      // Act — reopen triggers surgical repair which should ALTER ADD COLUMN.
      await DatabaseHelper().close();
      db = await DatabaseHelper().db;

      // Assert — `notes` column now exists, original row still there.
      final cols = await db.rawQuery('PRAGMA table_info(audit_sessions)');
      final names = cols.map((row) => row['name']).toSet();
      expect(names, contains('notes'));
      expect(names, contains('status'));
      expect(names, contains('updatedAt'));
      final rows = await db.query('audit_sessions');
      expect(rows, hasLength(1));
      expect(rows.first['id'], 's1');
    });

    test('legacy farms gain sectorKey before monitoring indexes', () async {
      var db = await DatabaseHelper().db;
      await db.insert('customers', {
        'id': 'legacy-farm-customer',
        'name': 'Preserved Farm Customer',
        'createdAt': '2026-07-30T00:00:00.000Z',
      });
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute('DROP TABLE farms');
      await db.execute('''CREATE TABLE farms (
        id TEXT PRIMARY KEY,
        customerId TEXT NOT NULL,
        name TEXT NOT NULL,
        location TEXT,
        notes TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdBy TEXT,
        createdAt TEXT,
        updatedAt TEXT,
        syncStatus TEXT NOT NULL DEFAULT 'pending',
        dirtyAt TEXT,
        lastSyncedAt TEXT,
        syncError TEXT
      )''');
      await db.insert('farms', {
        'id': 'legacy-farm',
        'customerId': 'legacy-farm-customer',
        'name': 'Must Survive',
      });

      await DatabaseHelper().close();
      db = await DatabaseHelper().db;

      final columns = await db.rawQuery('PRAGMA table_info(farms)');
      expect(columns.map((row) => row['name']), contains('sectorKey'));
      expect(
        await db.query('farms', where: 'id = ?', whereArgs: ['legacy-farm']),
        hasLength(1),
      );
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'index' AND name = 'idx_farms_customer_sector'",
        ),
        isNotEmpty,
      );
    });

    test('legacy flock placements gain current indexed columns', () async {
      var db = await DatabaseHelper().db;
      await db.insert('customers', {
        'id': 'legacy-placement-customer',
        'name': 'Placement Customer',
        'createdAt': '2026-07-30T00:00:00.000Z',
      });
      await db.insert('flocks', {
        'id': 'legacy-placement-flock',
        'customerId': 'legacy-placement-customer',
        'flockId': 'F-LEGACY',
        'breed': 'Ross 308',
        'entryDate': '2026-07-01',
        'status': 'active',
      });
      await db.insert('farms', {
        'id': 'legacy-placement-farm',
        'customerId': 'legacy-placement-customer',
        'sectorKey': 'breeder',
        'name': 'Placement Farm',
      });
      await db.insert('houses', {
        'id': 'legacy-placement-house',
        'farmId': 'legacy-placement-farm',
        'name': 'House 1',
      });
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute('DROP TABLE flock_placements');
      await db.execute('''CREATE TABLE flock_placements (
        id TEXT PRIMARY KEY,
        flockId TEXT NOT NULL,
        houseId TEXT NOT NULL,
        receptionDate TEXT,
        femalePlaced INTEGER,
        malePlaced INTEGER,
        placementCountsKnown INTEGER,
        cycleStatus TEXT,
        notes TEXT,
        createdBy TEXT,
        createdAt TEXT,
        updatedAt TEXT,
        syncStatus TEXT NOT NULL DEFAULT 'pending',
        dirtyAt TEXT,
        lastSyncedAt TEXT,
        syncError TEXT
      )''');
      await db.insert('flock_placements', {
        'id': 'legacy-placement',
        'flockId': 'legacy-placement-flock',
        'houseId': 'legacy-placement-house',
        'receptionDate': '2026-07-01',
        'femalePlaced': 1000,
        'malePlaced': 100,
        'cycleStatus': 'active',
      });

      await DatabaseHelper().close();
      db = await DatabaseHelper().db;

      final columns = await db.rawQuery('PRAGMA table_info(flock_placements)');
      expect(
        columns.map((row) => row['name']),
        containsAll(const ['placedBirds', 'placedAt', 'endedAt', 'status']),
      );
      expect(
        await db.query(
          'flock_placements',
          where: 'id = ?',
          whereArgs: ['legacy-placement'],
        ),
        hasLength(1),
      );
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'index' AND name = 'idx_flock_placements_flock'",
        ),
        isNotEmpty,
      );
    });

    test('missing index is restored after drop', () async {
      var db = await DatabaseHelper().db;
      await db.execute('DROP INDEX idx_audit_sessions_customer_date');

      await DatabaseHelper().close();
      db = await DatabaseHelper().db;

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_audit_sessions_customer_date'",
      );
      expect(indexes, isNotEmpty);
    });

    test('repair is a no-op (no DROP) when schema is intact', () async {
      // Arrange — populate then capture exact row state.
      var db = await DatabaseHelper().db;
      await db.insert('customers', {
        'id': 'c1',
        'name': 'Unchanged',
        'createdAt': '2026-06-06T00:00:00.000',
      });
      final beforeRows = await db.query('customers');

      // Act — reopen (repair runs against a healthy schema).
      await DatabaseHelper().close();
      db = await DatabaseHelper().db;

      // Assert — row identical, no destructive side effects.
      final afterRows = await db.query('customers');
      expect(afterRows, equals(beforeRows));
    });
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
