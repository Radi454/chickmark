import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/hatchery_model.dart';
import 'package:hatchaudit/data/repositories/customer_repository.dart';
import 'package:hatchaudit/data/repositories/flock_repository.dart';
import 'package:hatchaudit/data/repositories/hatchery_repository.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

/// Real-SQLite (FFI) tests for per-row dirty tracking on the reference
/// repositories (customers, hatcheries, flocks). Tables are hand-built with
/// the Task 3 sync-meta columns so there is no seed-data pollution of the
/// dirty queries.
void main() {
  late Database db;
  late _MockDatabaseHelper dbHelper;
  late CustomerRepository customerRepo;
  late HatcheryRepository hatcheryRepo;
  late FlockRepository flockRepo;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await _createSchema(db);
    dbHelper = _MockDatabaseHelper();
    when(() => dbHelper.db).thenAnswer((_) async => db);
    when(
      () => dbHelper.assertForeignKeys(
        customerId: any(named: 'customerId'),
        flockId: any(named: 'flockId'),
        hatcheryId: any(named: 'hatcheryId'),
      ),
    ).thenAnswer((_) async {});
    customerRepo = CustomerRepository(dbHelper: dbHelper);
    hatcheryRepo = HatcheryRepository(dbHelper: dbHelper);
    flockRepo = FlockRepository(dbHelper: dbHelper);
    // Seed a customer row so hatchery/flock FK-shaped columns are coherent
    // (the mocked assertForeignKeys doesn't enforce this, but rows should
    // still make sense).
    await db.insert('customers', {
      'id': 'c1',
      'name': 'Seed Customer',
      'createdAt': '2026-08-01T00:00:00.000',
      'createdBy': 'seed',
      'syncStatus': 'synced',
      'dirtyAt': null,
      'lastSyncedAt': '2026-08-01T00:00:00.000',
      'syncError': null,
    });
  });

  tearDown(() async => db.close());

  Future<Map<String, Object?>> rowById(String table, String id) async =>
      (await db.query(table, where: 'id = ?', whereArgs: [id])).single;

  group('CustomerRepository dirty tracking', () {
    test('insert stamps the row pending with a dirtyAt', () async {
      await customerRepo.insertCustomer(_customer('c1'));
      final row = await rowById('customers', 'c1');
      expect(row['syncStatus'], 'pending');
      expect(row['dirtyAt'], isNotNull);
    });

    test('remote upsert stamps the row synced', () async {
      await customerRepo.upsertCustomer({
        'id': 'c1',
        'name': 'Remote',
        'created_at': '2026-08-01T00:00:00.000',
        'created_by': 'cloud',
      });
      final row = await rowById('customers', 'c1');
      expect(row['syncStatus'], 'synced');
      expect(row['dirtyAt'], isNull);
    });

    test('a local edit re-dirties a previously synced row', () async {
      await customerRepo.upsertCustomer({'id': 'c1', 'name': 'Remote'});
      await customerRepo.updateCustomer(_customer('c1'));
      final row = await rowById('customers', 'c1');
      expect(row['syncStatus'], 'pending');
    });

    test('getDirtyRows returns only pending/failed rows', () async {
      await customerRepo.insertCustomer(_customer('c1'));
      await customerRepo.upsertCustomer({'id': 'c2', 'name': 'Remote'});
      final dirty = await customerRepo.getDirtyRows();
      expect(dirty.map((row) => row['id']), ['c1']);
    });

    test('markRowsSynced clears dirty state', () async {
      await customerRepo.insertCustomer(_customer('c1'));
      await customerRepo.getDirtyRows();
      await customerRepo.markRowsSynced(['c1']);
      final row = await rowById('customers', 'c1');
      expect(row['syncStatus'], 'synced');
      expect(row['dirtyAt'], isNull);
      expect(row['lastSyncedAt'], isNotNull);
    });

    test('an edit during the push window survives markRowsSynced', () async {
      await customerRepo.insertCustomer(_customer('c1'));
      await customerRepo.getDirtyRows(); // capture cutoff
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await customerRepo.updateCustomer(
        _customer('c1', name: 'Edited mid-push'),
      );
      await customerRepo.markRowsSynced(['c1']); // must NOT clear the edit
      final row = await rowById('customers', 'c1');
      expect(row['syncStatus'], 'pending');
      expect(row['dirtyAt'], isNotNull);
    });

    test('markRowsFailed stamps failed status and error', () async {
      await customerRepo.insertCustomer(_customer('c1'));
      await customerRepo.markRowsFailed(['c1'], StateError('boom'));
      final row = await rowById('customers', 'c1');
      expect(row['syncStatus'], 'failed');
      expect(row['syncError'], contains('boom'));
    });

    test('getRowSyncStatus reflects current status', () async {
      await customerRepo.insertCustomer(_customer('c1'));
      expect(await customerRepo.getRowSyncStatus('c1'), 'pending');
      await customerRepo.upsertCustomer({'id': 'c1', 'name': 'Remote'});
      expect(await customerRepo.getRowSyncStatus('c1'), 'synced');
      expect(await customerRepo.getRowSyncStatus('missing'), isNull);
    });
  });

  group('HatcheryRepository dirty tracking', () {
    test('insert stamps the row pending with a dirtyAt', () async {
      await hatcheryRepo.insertHatchery(_hatchery('h1'));
      final row = await rowById('hatcheries', 'h1');
      expect(row['syncStatus'], 'pending');
      expect(row['dirtyAt'], isNotNull);
    });

    test('remote upsert stamps the row synced', () async {
      await hatcheryRepo.upsertHatchery({
        'id': 'h1',
        'customerId': 'c1',
        'name': 'Remote Hatchery',
      });
      final row = await rowById('hatcheries', 'h1');
      expect(row['syncStatus'], 'synced');
      expect(row['dirtyAt'], isNull);
    });

    test('a local edit re-dirties a previously synced row', () async {
      await hatcheryRepo.upsertHatchery({
        'id': 'h1',
        'customerId': 'c1',
        'name': 'Remote Hatchery',
      });
      await hatcheryRepo.updateHatchery(_hatchery('h1'));
      final row = await rowById('hatcheries', 'h1');
      expect(row['syncStatus'], 'pending');
    });

    test('getDirtyRows returns only pending/failed rows', () async {
      await hatcheryRepo.insertHatchery(_hatchery('h1'));
      await hatcheryRepo.upsertHatchery({
        'id': 'h2',
        'customerId': 'c1',
        'name': 'Remote Hatchery',
      });
      final dirty = await hatcheryRepo.getDirtyRows();
      expect(dirty.map((row) => row['id']), ['h1']);
    });

    test('markRowsSynced clears dirty state', () async {
      await hatcheryRepo.insertHatchery(_hatchery('h1'));
      await hatcheryRepo.getDirtyRows();
      await hatcheryRepo.markRowsSynced(['h1']);
      final row = await rowById('hatcheries', 'h1');
      expect(row['syncStatus'], 'synced');
      expect(row['dirtyAt'], isNull);
      expect(row['lastSyncedAt'], isNotNull);
    });

    test('an edit during the push window survives markRowsSynced', () async {
      await hatcheryRepo.insertHatchery(_hatchery('h1'));
      await hatcheryRepo.getDirtyRows(); // capture cutoff
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await hatcheryRepo.updateHatchery(
        _hatchery('h1', name: 'Edited mid-push'),
      );
      await hatcheryRepo.markRowsSynced(['h1']); // must NOT clear the edit
      final row = await rowById('hatcheries', 'h1');
      expect(row['syncStatus'], 'pending');
      expect(row['dirtyAt'], isNotNull);
    });

    test('markRowsFailed stamps failed status and error', () async {
      await hatcheryRepo.insertHatchery(_hatchery('h1'));
      await hatcheryRepo.markRowsFailed(['h1'], StateError('boom'));
      final row = await rowById('hatcheries', 'h1');
      expect(row['syncStatus'], 'failed');
      expect(row['syncError'], contains('boom'));
    });

    test('getRowSyncStatus reflects current status', () async {
      await hatcheryRepo.insertHatchery(_hatchery('h1'));
      expect(await hatcheryRepo.getRowSyncStatus('h1'), 'pending');
      await hatcheryRepo.upsertHatchery({
        'id': 'h1',
        'customerId': 'c1',
        'name': 'Remote Hatchery',
      });
      expect(await hatcheryRepo.getRowSyncStatus('h1'), 'synced');
      expect(await hatcheryRepo.getRowSyncStatus('missing'), isNull);
    });
  });

  group('FlockRepository dirty tracking', () {
    test('insert stamps the row pending with a dirtyAt', () async {
      await flockRepo.insertFlock(_flock('f1'));
      final row = await rowById('flocks', 'f1');
      expect(row['syncStatus'], 'pending');
      expect(row['dirtyAt'], isNotNull);
    });

    test('remote upsert stamps the row synced', () async {
      await flockRepo.upsertFlock({
        'id': 'f1',
        'customerId': 'c1',
        'flockId': 'f1',
        'breed': 'Remote Breed',
        'entryDate': '2026-08-01T00:00:00.000',
      });
      final row = await rowById('flocks', 'f1');
      expect(row['syncStatus'], 'synced');
      expect(row['dirtyAt'], isNull);
    });

    test('a local edit re-dirties a previously synced row', () async {
      await flockRepo.upsertFlock({
        'id': 'f1',
        'customerId': 'c1',
        'flockId': 'f1',
        'breed': 'Remote Breed',
        'entryDate': '2026-08-01T00:00:00.000',
      });
      await flockRepo.updateFlock(_flock('f1'));
      final row = await rowById('flocks', 'f1');
      expect(row['syncStatus'], 'pending');
    });

    test('getDirtyRows returns only pending/failed rows', () async {
      await flockRepo.insertFlock(_flock('f1'));
      await flockRepo.upsertFlock({
        'id': 'f2',
        'customerId': 'c1',
        'flockId': 'f2',
        'breed': 'Remote Breed',
        'entryDate': '2026-08-01T00:00:00.000',
      });
      final dirty = await flockRepo.getDirtyRows();
      expect(dirty.map((row) => row['id']), ['f1']);
    });

    test('markRowsSynced clears dirty state', () async {
      await flockRepo.insertFlock(_flock('f1'));
      await flockRepo.getDirtyRows();
      await flockRepo.markRowsSynced(['f1']);
      final row = await rowById('flocks', 'f1');
      expect(row['syncStatus'], 'synced');
      expect(row['dirtyAt'], isNull);
      expect(row['lastSyncedAt'], isNotNull);
    });

    test('an edit during the push window survives markRowsSynced', () async {
      await flockRepo.insertFlock(_flock('f1'));
      await flockRepo.getDirtyRows(); // capture cutoff
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await flockRepo.updateFlock(_flock('f1', breed: 'Edited mid-push'));
      await flockRepo.markRowsSynced(['f1']); // must NOT clear the edit
      final row = await rowById('flocks', 'f1');
      expect(row['syncStatus'], 'pending');
      expect(row['dirtyAt'], isNotNull);
    });

    test('markRowsFailed stamps failed status and error', () async {
      await flockRepo.insertFlock(_flock('f1'));
      await flockRepo.markRowsFailed(['f1'], StateError('boom'));
      final row = await rowById('flocks', 'f1');
      expect(row['syncStatus'], 'failed');
      expect(row['syncError'], contains('boom'));
    });

    test('getRowSyncStatus reflects current status', () async {
      await flockRepo.insertFlock(_flock('f1'));
      expect(await flockRepo.getRowSyncStatus('f1'), 'pending');
      await flockRepo.upsertFlock({
        'id': 'f1',
        'customerId': 'c1',
        'flockId': 'f1',
        'breed': 'Remote Breed',
        'entryDate': '2026-08-01T00:00:00.000',
      });
      expect(await flockRepo.getRowSyncStatus('f1'), 'synced');
      expect(await flockRepo.getRowSyncStatus('missing'), isNull);
    });
  });
}

CustomerModel _customer(String id, {String name = 'Local Customer'}) =>
    CustomerModel(
      id: id,
      name: name,
      createdAt: DateTime(2026, 8, 1),
      createdBy: 'tester',
    );

HatcheryModel _hatchery(String id, {String name = 'Local Hatchery'}) =>
    HatcheryModel(
      id: id,
      customerId: 'c1',
      name: name,
      createdAt: DateTime(2026, 8, 1),
      createdBy: 'tester',
    );

FlockModel _flock(String id, {String breed = 'Local Breed'}) => FlockModel(
  id: id,
  customerId: 'c1',
  flockId: id,
  breed: breed,
  entryDate: DateTime(2026, 8, 1),
);

Future<void> _createSchema(Database db) async {
  await db.execute('''CREATE TABLE customers (
    id TEXT PRIMARY KEY,
    name TEXT,
    location TEXT,
    phone TEXT,
    email TEXT,
    createdAt TEXT,
    createdBy TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT
  )''');
  await db.execute('''CREATE TABLE hatcheries (
    id TEXT PRIMARY KEY,
    customerId TEXT NOT NULL,
    name TEXT NOT NULL,
    location TEXT,
    notes TEXT,
    createdAt TEXT,
    createdBy TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT
  )''');
  await db.execute('''CREATE TABLE flocks (
    id TEXT PRIMARY KEY,
    customerId TEXT,
    flockId TEXT,
    breed TEXT,
    entryDate TEXT,
    farmId TEXT,
    sectorKey TEXT,
    sexProfile TEXT NOT NULL DEFAULT 'as_hatched',
    targetProfileId TEXT,
    productionPhase TEXT,
    isAgeEstimated INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'active',
    depletionAgeWeeks INTEGER NOT NULL DEFAULT 65,
    soldAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT
  )''');
}
