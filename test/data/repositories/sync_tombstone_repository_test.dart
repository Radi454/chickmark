import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/repositories/sync_tombstone_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late _MockDatabaseHelper dbHelper;
  late SyncTombstoneRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT
      )
    ''');
    await _createSyncTombstoneTable(db);
    dbHelper = _MockDatabaseHelper();
    when(() => dbHelper.db).thenAnswer((_) async => db);
    repository = SyncTombstoneRepository(dbHelper: dbHelper);
  });

  tearDown(() async {
    await db.close();
  });

  test('queued local deletes remain pending until marked synced', () async {
    await repository.queueDelete('customers', 'customer-1');

    final pending = await repository.getPendingDeletes();
    expect(pending, hasLength(1));
    expect(pending.single.tableName, 'customers');
    expect(pending.single.rowId, 'customer-1');

    await repository.markSynced(pending.single.id);

    expect(await repository.getPendingDeletes(), isEmpty);
  });

  test('remote tombstones delete matching local rows on reload', () async {
    await db.insert('customers', {'id': 'customer-1', 'name': 'Acme'});
    await repository.upsertRemoteTombstone({
      'id': 'customers:customer-1',
      'table_name': 'customers',
      'row_id': 'customer-1',
      'deleted_at': DateTime(2026, 5, 2).toIso8601String(),
      'created_at': DateTime(2026, 5, 2).toIso8601String(),
    });

    await repository.applyRemoteDeletes();

    final rows = await db.query('customers');
    expect(rows, isEmpty);
  });

  test(
    'pending tombstones remain compatible with legacy snake_case tables',
    () async {
      await _replaceWithLegacySyncTombstoneTable(db);
      await db.insert('sync_tombstones', {
        'id': 'customers:customer-1',
        'table_name': 'customers',
        'row_id': 'customer-1',
        'deleted_at': DateTime(2026, 5, 2).toIso8601String(),
        'created_at': DateTime(2026, 5, 2).toIso8601String(),
        'synced_at': null,
        'last_error': null,
      });

      final pending = await repository.getPendingDeletes();
      expect(pending, hasLength(1));
      expect(pending.single.tableName, 'customers');
      expect(pending.single.rowId, 'customer-1');

      await repository.markSynced(pending.single.id);

      expect(await repository.getPendingDeletes(), isEmpty);
    },
  );

  test(
    'remote deletes remain compatible with legacy snake_case tables',
    () async {
      await _replaceWithLegacySyncTombstoneTable(db);
      await db.insert('customers', {'id': 'customer-1', 'name': 'Acme'});
      await db.insert('sync_tombstones', {
        'id': 'customers:customer-1',
        'table_name': 'customers',
        'row_id': 'customer-1',
        'deleted_at': DateTime(2026, 5, 2).toIso8601String(),
        'created_at': DateTime(2026, 5, 2).toIso8601String(),
        'synced_at': DateTime(2026, 5, 2).toIso8601String(),
        'last_error': null,
      });

      await repository.applyRemoteDeletes();

      final rows = await db.query('customers');
      expect(rows, isEmpty);
    },
  );

  test(
    'remote tombstones can be inserted into legacy snake_case tables',
    () async {
      await _replaceWithLegacySyncTombstoneTable(db);

      await repository.upsertRemoteTombstone({
        'id': 'customers:customer-1',
        'table_name': 'customers',
        'row_id': 'customer-1',
        'deleted_at': DateTime(2026, 5, 2).toIso8601String(),
        'created_at': DateTime(2026, 5, 2).toIso8601String(),
      });

      final rows = await db.query('sync_tombstones');
      expect(rows, hasLength(1));
      expect(rows.single['table_name'], 'customers');
      expect(rows.single['row_id'], 'customer-1');
      expect(rows.single['synced_at'], isNotNull);
    },
  );
}

Future<void> _createSyncTombstoneTable(Database db) async {
  await db.execute('''CREATE TABLE sync_tombstones (
    id TEXT PRIMARY KEY,
    tableName TEXT NOT NULL,
    rowId TEXT NOT NULL,
    deletedAt TEXT NOT NULL,
    createdAt TEXT NOT NULL,
    syncedAt TEXT,
    lastError TEXT
  )''');
}

Future<void> _replaceWithLegacySyncTombstoneTable(Database db) async {
  await db.execute('DROP TABLE sync_tombstones');
  await db.execute('''CREATE TABLE sync_tombstones (
    id TEXT PRIMARY KEY,
    table_name TEXT NOT NULL,
    row_id TEXT NOT NULL,
    deleted_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    synced_at TEXT,
    last_error TEXT
  )''');
}
