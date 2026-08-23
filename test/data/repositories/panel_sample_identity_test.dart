import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

void main() {
  late Database db;
  late PanelSampleRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final helper = _MockDatabaseHelper();
    when(() => helper.db).thenAnswer((_) async => db);
    await db.execute('''CREATE TABLE egg_quality (
      id TEXT PRIMARY KEY,
      sessionId TEXT NOT NULL,
      customerId TEXT NOT NULL,
      date TEXT NOT NULL,
      house TEXT,
      setter TEXT,
      hatcher TEXT,
      trolley TEXT,
      tray TEXT,
      position TEXT,
      eggSampleSize INTEGER,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL,
      syncStatus TEXT NOT NULL DEFAULT 'pending',
      dirtyAt TEXT,
      lastSyncedAt TEXT,
      syncError TEXT
    )''');
    await db.execute('''CREATE TABLE sync_tombstones (
      id TEXT PRIMARY KEY,
      tableName TEXT NOT NULL,
      rowId TEXT NOT NULL,
      deletedAt TEXT NOT NULL,
      createdAt TEXT NOT NULL,
      syncedAt TEXT,
      lastError TEXT
    )''');
    repository = PanelSampleRepository(databaseHelper: helper);
  });

  tearDown(() async => db.close());

  Map<String, Object?> row(String id, {String? house, int? size}) => {
        'id': id,
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'date': '2026-08-23',
        'house': house,
        'eggSampleSize': size,
        'createdAt': '2026-08-23T00:00:00.000Z',
        'updatedAt': '2026-08-23T00:00:00.000Z',
      };

  test('two blank-house egg_quality rows in one session stay separate',
      () async {
    await repository.upsertRow(tableName: 'egg_quality', row: row('row-a', size: 10));
    await repository.upsertRow(tableName: 'egg_quality', row: row('row-b', size: 20));

    final saved = await db.query('egg_quality', orderBy: 'id ASC');
    expect(saved.map((r) => r['id']), ['row-a', 'row-b']);
    expect(saved.map((r) => r['eggSampleSize']), [10, 20]);
  });

  test('renaming a house updates the same row rather than creating one',
      () async {
    await repository.upsertRow(tableName: 'egg_quality', row: row('row-a', house: 'H1', size: 10));
    await repository.upsertRow(tableName: 'egg_quality', row: row('row-a', house: 'H7', size: 10));

    final saved = await db.query('egg_quality');
    expect(saved, hasLength(1));
    expect(saved.single['id'], 'row-a');
    expect(saved.single['house'], 'H7');
  });

  test('two rows may share a house without merging', () async {
    await repository.upsertRow(tableName: 'egg_quality', row: row('row-a', house: 'H1', size: 10));
    await repository.upsertRow(tableName: 'egg_quality', row: row('row-b', house: 'H1', size: 20));

    final saved = await db.query('egg_quality', orderBy: 'id ASC');
    expect(saved, hasLength(2));
    expect(saved.map((r) => r['eggSampleSize']), [10, 20]);
  });
}
