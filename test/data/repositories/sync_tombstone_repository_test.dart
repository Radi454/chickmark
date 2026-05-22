import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/repositories/sync_tombstone_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

void main() {
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
