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
      expect(
        tables,
        isNotEmpty,
        reason: 'audit_sessions should be restored by surgical repair',
      );
      final customers = await db.query(
        'customers',
        where: 'id = ?',
        whereArgs: ['c1'],
      );
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
      expect(flocksAfter.where((row) => row['id'] == 'f-keepme'), hasLength(1));
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

    test('legacy house gains flockId-scoped opening counts and indexes', () async {
      var db = await DatabaseHelper().db;
      await db.insert('customers', {
        'id': 'legacy-house-customer',
        'name': 'Preserved House Customer',
        'createdAt': '2026-07-30T00:00:00.000Z',
      });
      await db.insert('flocks', {
        'id': 'legacy-house-flock',
        'customerId': 'legacy-house-customer',
        'flockId': 'F-LEGACY',
        'breed': 'Ross 308',
        'entryDate': '2026-07-01',
        'status': 'active',
      });
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute('DROP TABLE houses');
      await db.execute('''CREATE TABLE houses (
        id TEXT PRIMARY KEY,
        flockId TEXT NOT NULL,
        name TEXT NOT NULL,
        code TEXT,
        capacity INTEGER,
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
      await db.insert('houses', {
        'id': 'legacy-house',
        'flockId': 'legacy-house-flock',
        'name': 'Must Survive',
      });

      await DatabaseHelper().close();
      db = await DatabaseHelper().db;

      final columns = await db.rawQuery('PRAGMA table_info(houses)');
      expect(
        columns.map((row) => row['name']),
        containsAll(const ['openingFemales', 'openingMales']),
      );
      expect(
        await db.query('houses', where: 'id = ?', whereArgs: ['legacy-house']),
        hasLength(1),
      );
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'index' AND name = 'idx_houses_flock_name'",
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

    test('breeder-cycle branch drift is healed: flocks columns restored, '
        'orphan triggers dropped', () async {
      // Arrange — reproduce the drift a chickmark-dashboard-redesign build
      // leaves in the shared DB file: flocks rebuilt WITHOUT
      // depletionAgeWeeks/soldAt, plus breeder_cycle_* triggers that abort
      // flock updates once status != 'planned'.
      var db = await DatabaseHelper().db;
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute('DROP TABLE flocks');
      await db.execute('''CREATE TABLE flocks (
          id TEXT PRIMARY KEY,
          customerId TEXT,
          flockId TEXT,
          breed TEXT,
          entryDate TEXT,
          farmId TEXT,
          targetProfileId TEXT,
          isAgeEstimated INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'active',
          createdAt TEXT,
          updatedAt TEXT,
          syncStatus TEXT NOT NULL DEFAULT 'pending',
          dirtyAt TEXT,
          lastSyncedAt TEXT,
          syncError TEXT,
          sectorKey TEXT,
          sexProfile TEXT NOT NULL DEFAULT 'as_hatched',
          productionPhase TEXT
        )''');
      await db.insert('flocks', {
        'id': 'f-drift',
        'customerId': 'c1',
        'flockId': 'Drift Farm',
        'breed': 'Ross308',
        'entryDate': '2026-06-17T00:00:00.000',
        'status': 'active',
      });
      await db.execute('''CREATE TRIGGER breeder_cycle_immutability_guard
          BEFORE UPDATE OF
            customerId, farmId, flockId, breed, entryDate, targetProfileId
          ON flocks
          WHEN OLD.status <> 'planned' AND (
            NEW.breed IS NOT OLD.breed
          )
          BEGIN
            SELECT RAISE(ABORT, 'active or terminal Breeder cycles are immutable');
          END''');
      await db.execute('''CREATE TRIGGER breeder_cycle_status_mirror
          AFTER UPDATE OF status ON flocks
          BEGIN
            SELECT 1;
          END''');

      // Act — reopen; surgical repair should heal columns and drop the
      // foreign triggers.
      await DatabaseHelper().close();
      db = await DatabaseHelper().db;

      // Assert — restored columns.
      final cols = (await db.rawQuery(
        'PRAGMA table_info(flocks)',
      )).map((row) => row['name']).toSet();
      expect(cols, contains('depletionAgeWeeks'));
      expect(cols, contains('soldAt'));

      // Assert — orphan triggers gone.
      final triggers = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='trigger' "
        "AND name LIKE 'breeder_cycle_%'",
      );
      expect(
        triggers,
        isEmpty,
        reason:
            'breeder_cycle_* triggers belong to another branch and '
            'must be dropped by repair',
      );

      // Assert — the exact writes that were refused now succeed: a flock
      // edit that changes a previously-guarded column, on an active row.
      await db.update(
        'flocks',
        {'breed': 'Cobb500', 'depletionAgeWeeks': 70, 'soldAt': null},
        where: 'id = ?',
        whereArgs: ['f-drift'],
      );
      final row = (await db.query('flocks', where: "id = 'f-drift'")).single;
      expect(row['breed'], 'Cobb500');
      expect(row['depletionAgeWeeks'], 70);
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
