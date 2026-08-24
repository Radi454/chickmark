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
    await db.execute('''CREATE TABLE chick_quality (
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
      scopeType TEXT,
      domain TEXT,
      schemaVersion INTEGER,
      scopeKey TEXT,
      replicate INTEGER,
      sampleKey TEXT,
      source TEXT,
      captureMethod TEXT,
      createdBy TEXT,
      deviceId TEXT,
      sourceRefId TEXT,
      observedAt TEXT,
      pasgarSampleSize INTEGER,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL,
      syncStatus TEXT NOT NULL DEFAULT 'pending',
      dirtyAt TEXT,
      lastSyncedAt TEXT,
      syncError TEXT
    )''');
    await db.execute('''
      CREATE UNIQUE INDEX idx_chick_quality_sample_key
      ON chick_quality (customerId, sampleKey)
      WHERE sampleKey IS NOT NULL
    ''');
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

  Map<String, Object?> chickRow(
    String id, {
    int size = 20,
    String setter = 'Setter A',
    String hatcher = 'Hatcher A',
  }) => {
    'id': id,
    'sessionId': 'session-1',
    'customerId': 'customer-1',
    'date': '2026-08-24',
    'scopeType': 'setter_hatcher',
    'setter': setter,
    'hatcher': hatcher,
    'pasgarSampleSize': size,
    'createdAt': '2026-08-24T09:00:00.000Z',
    'updatedAt': '2026-08-24T09:00:00.000Z',
  };

  test(
    'two blank-house egg_quality rows in one session stay separate',
    () async {
      await repository.upsertRow(
        tableName: 'egg_quality',
        row: row('row-a', size: 10),
      );
      await repository.upsertRow(
        tableName: 'egg_quality',
        row: row('row-b', size: 20),
      );

      final saved = await db.query('egg_quality', orderBy: 'id ASC');
      expect(saved.map((r) => r['id']), ['row-a', 'row-b']);
      expect(saved.map((r) => r['eggSampleSize']), [10, 20]);
    },
  );

  test(
    'renaming a house updates the same row rather than creating one',
    () async {
      await repository.upsertRow(
        tableName: 'egg_quality',
        row: row('row-a', house: 'H1', size: 10),
      );
      await repository.upsertRow(
        tableName: 'egg_quality',
        row: row('row-a', house: 'H7', size: 10),
      );

      final saved = await db.query('egg_quality');
      expect(saved, hasLength(1));
      expect(saved.single['id'], 'row-a');
      expect(saved.single['house'], 'H7');
    },
  );

  test('two rows may share a house without merging', () async {
    await repository.upsertRow(
      tableName: 'egg_quality',
      row: row('row-a', house: 'H1', size: 10),
    );
    await repository.upsertRow(
      tableName: 'egg_quality',
      row: row('row-b', house: 'H1', size: 20),
    );

    final saved = await db.query('egg_quality', orderBy: 'id ASC');
    expect(saved, hasLength(2));
    expect(saved.map((r) => r['eggSampleSize']), [10, 20]);
  });

  test('same-scope Chick ids are preserved as distinct replicates', () async {
    await repository.upsertRow(
      tableName: 'chick_quality',
      row: chickRow('human-row', size: 20),
    );
    await repository.upsertRow(
      tableName: 'chick_quality',
      row: chickRow('agent-row', size: 40),
    );

    final saved = await db.query('chick_quality', orderBy: 'replicate');
    expect(saved.map((row) => row['id']), ['human-row', 'agent-row']);
    expect(saved.map((row) => row['pasgarSampleSize']), [20, 40]);
    expect(saved.map((row) => row['domain']), [
      'chicks.legacy_combined',
      'chicks.legacy_combined',
    ]);
    expect(saved.map((row) => row['replicate']), [1, 2]);
    expect(saved.map((row) => row['sampleKey']).toSet(), hasLength(2));
  });

  test('editing a persisted Chick id keeps its identity envelope', () async {
    await repository.upsertRow(
      tableName: 'chick_quality',
      row: chickRow('row-a', size: 20),
    );
    final before = (await db.query('chick_quality')).single;

    await repository.upsertRow(
      tableName: 'chick_quality',
      row: chickRow(
        'row-a',
        size: 30,
        setter: 'Renamed Setter',
        hatcher: 'Renamed Hatcher',
      ),
    );

    final after = (await db.query('chick_quality')).single;
    expect(after['pasgarSampleSize'], 30);
    expect(after['setter'], 'Renamed Setter');
    expect(after['sampleKey'], before['sampleKey']);
    expect(after['scopeKey'], before['scopeKey']);
    expect(after['replicate'], before['replicate']);
  });

  test(
    'cloud identity reconciliation atomically applies a batch permutation',
    () async {
      await repository.upsertRow(
        tableName: 'chick_quality',
        row: chickRow('row-a'),
      );
      await repository.upsertRow(
        tableName: 'chick_quality',
        row: chickRow('row-b'),
      );
      final before = await db.query('chick_quality', orderBy: 'id');

      await repository.reconcileChickIdentityAssignments('chick_quality', [
        {
          'id': 'row-a',
          'replicate': before[1]['replicate'],
          'sample_key': before[1]['sampleKey'],
        },
        {
          'id': 'row-b',
          'replicate': before[0]['replicate'],
          'sample_key': before[0]['sampleKey'],
        },
      ]);

      final after = await db.query('chick_quality', orderBy: 'id');
      expect(after[0]['sampleKey'], before[1]['sampleKey']);
      expect(after[1]['sampleKey'], before[0]['sampleKey']);
    },
  );

  test(
    'cloud reconciliation reallocates an out-of-batch local key holder',
    () async {
      await repository.upsertRow(
        tableName: 'chick_quality',
        row: chickRow('uploaded-row'),
      );
      await repository.upsertRow(
        tableName: 'chick_quality',
        row: chickRow('created-during-upload', size: 40),
      );
      final before = await db.query('chick_quality', orderBy: 'replicate');
      final cloudKey = before[1]['sampleKey'] as String;

      await repository.reconcileChickIdentityAssignments('chick_quality', [
        {'id': 'uploaded-row', 'replicate': 2, 'sample_key': cloudKey},
      ]);

      final after = await db.query('chick_quality', orderBy: 'replicate');
      expect(after, hasLength(2));
      expect(after[0]['id'], 'uploaded-row');
      expect(after[0]['replicate'], 2);
      expect(after[0]['sampleKey'], cloudKey);
      expect(after[1]['id'], 'created-during-upload');
      expect(after[1]['replicate'], 3);
      expect(after[1]['sampleKey'], isNot(cloudKey));
      expect(after[1]['pasgarSampleSize'], 40);
      expect(after[1]['syncStatus'], 'pending');
    },
  );

  test('persisted sample key recovers a row whose draft id changed', () async {
    await repository.upsertRow(
      tableName: 'chick_quality',
      row: chickRow('persisted-row'),
    );
    final persisted = (await db.query('chick_quality')).single;

    await repository.upsertRow(
      tableName: 'chick_quality',
      row: {
        ...chickRow('regenerated-draft-id', size: 55),
        'domain': persisted['domain'],
        'scopeKey': persisted['scopeKey'],
        'replicate': persisted['replicate'],
        'sampleKey': persisted['sampleKey'],
      },
    );

    final rows = await db.query('chick_quality');
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'persisted-row');
    expect(rows.single['pasgarSampleSize'], 55);
    expect(rows.single['sampleKey'], persisted['sampleKey']);
  });

  test('sample key recovery never moves a row across sessions', () async {
    await repository.upsertRow(
      tableName: 'chick_quality',
      row: chickRow('persisted-row'),
    );
    final persisted = (await db.query('chick_quality')).single;

    await repository.upsertRow(
      tableName: 'chick_quality',
      row: {
        ...chickRow('new-session-row', size: 60),
        'sessionId': 'session-2',
        'domain': persisted['domain'],
        'scopeKey': persisted['scopeKey'],
        'replicate': persisted['replicate'],
        'sampleKey': persisted['sampleKey'],
      },
    );

    final rows = await db.query('chick_quality', orderBy: 'id');
    expect(rows, hasLength(2));
    expect(
      rows.singleWhere((row) => row['id'] == 'persisted-row')['sessionId'],
      'session-1',
    );
    final newRow = rows.singleWhere((row) => row['id'] == 'new-session-row');
    expect(newRow['sessionId'], 'session-2');
    expect(newRow['sampleKey'], isNot(persisted['sampleKey']));
  });

  test(
    'an older cloud Chick row receives conservative legacy provenance',
    () async {
      await repository.upsertPanelRow('chick_quality', {
        'id': 'remote-old-1',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'date': '2026-08-24',
        'createdAt': '2026-08-24T08:00:00.000Z',
        'updatedAt': '2026-08-24T08:00:00.000Z',
        'pasgarSampleSize': 20,
      });

      final row = await repository.getRowById('chick_quality', 'remote-old-1');
      expect(row?['source'], 'legacy');
      expect(row?['captureMethod'], 'unknown');
      expect(row?['syncStatus'], 'synced');
      expect(row?['sampleKey'], isNotNull);
    },
  );
}
