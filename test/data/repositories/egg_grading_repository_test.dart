import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/repositories/egg_grading_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

void main() {
  late Database db;
  late EggGradingRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final helper = _MockDatabaseHelper();
    when(() => helper.db).thenAnswer((_) async => db);
    await db.execute('''CREATE TABLE egg_quality_defect_counts (
      id TEXT PRIMARY KEY,
      eggQualityId TEXT NOT NULL,
      sessionId TEXT NOT NULL,
      customerId TEXT NOT NULL,
      flockId TEXT,
      hatcheryId TEXT,
      date TEXT NOT NULL,
      scopeType TEXT,
      houseKey TEXT,
      sampleLabel TEXT,
      defectCode TEXT NOT NULL,
      defectCategory TEXT,
      isReject INTEGER,
      count INTEGER NOT NULL DEFAULT 0,
      pctOfSample REAL,
      notes TEXT,
      sortOrder INTEGER NOT NULL DEFAULT 0,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL,
      syncStatus TEXT NOT NULL DEFAULT 'pending',
      dirtyAt TEXT,
      lastSyncedAt TEXT,
      syncError TEXT
    )''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_eqdc_unique_defect '
      'ON egg_quality_defect_counts (eggQualityId, defectCode)',
    );
    await db.execute('''CREATE TABLE sync_tombstones (
      id TEXT PRIMARY KEY,
      tableName TEXT NOT NULL,
      rowId TEXT NOT NULL,
      deletedAt TEXT NOT NULL,
      createdAt TEXT NOT NULL,
      syncedAt TEXT,
      lastError TEXT
    )''');
    repository = EggGradingRepository(databaseHelper: helper);
  });

  tearDown(() async => db.close());

  Future<void> save(String sampleId, Map<String, int> counts) {
    return repository.replaceCountsForSample(
      eggQualityId: sampleId,
      sessionId: 'session-1',
      customerId: 'customer-1',
      flockId: 'flock-1',
      date: '2026-08-23',
      scopeType: 'house',
      houseKey: sampleId == 'eq-1' ? 'H1' : 'H2',
      sampleLabel: sampleId == 'eq-1' ? 'H1' : 'H2',
      sampleSize: 100,
      counts: counts,
    );
  }

  test('counts are stored and read back per sample', () async {
    await save('eq-1', {'dirty': 4, 'cracked': 3});
    await save('eq-2', {'wrinkled': 2});

    expect(await repository.countsForSample('eq-1'), {
      'dirty': 4,
      'cracked': 3,
    });
    expect(await repository.countsForSample('eq-2'), {'wrinkled': 2});
  });

  test('replacing drops removed defects and keeps the rest', () async {
    await save('eq-1', {'dirty': 4, 'cracked': 3});
    await save('eq-1', {'dirty': 6});

    expect(await repository.countsForSample('eq-1'), {'dirty': 6});
    final tombstones = await db.query('sync_tombstones');
    expect(tombstones, hasLength(1));
    expect(tombstones.single['tableName'], 'egg_quality_defect_counts');
  });

  test('zero counts are not stored', () async {
    await save('eq-1', {'dirty': 0, 'cracked': 3});
    expect(await repository.countsForSample('eq-1'), {'cracked': 3});
  });

  test('pctOfSample is derived from the sample size', () async {
    await save('eq-1', {'dirty': 4});
    final row = (await db.query('egg_quality_defect_counts')).single;
    expect(row['pctOfSample'], closeTo(4.0, 0.001));
  });

  test('deleting a sample removes its counts and queues tombstones', () async {
    await save('eq-1', {'dirty': 4, 'cracked': 3});
    await repository.deleteCountsForSamples(['eq-1']);

    expect(await repository.countsForSample('eq-1'), isEmpty);
    expect(await db.query('sync_tombstones'), hasLength(2));
  });

  test('countsForSession groups by owning sample', () async {
    await save('eq-1', {'dirty': 4});
    await save('eq-2', {'wrinkled': 2});
    expect(await repository.countsForSession('session-1'), {
      'eq-1': {'dirty': 4},
      'eq-2': {'wrinkled': 2},
    });
  });

  test('re-saving a sample keeps each count row id stable', () async {
    await save('eq-1', {'dirty': 4});
    final firstRow = (await db.query(
      'egg_quality_defect_counts',
      where: 'eggQualityId = ? AND defectCode = ?',
      whereArgs: ['eq-1', 'dirty'],
    )).single;
    expect(firstRow['id'], 'eq-1:dirty');

    await save('eq-1', {'dirty': 9});
    final secondRow = (await db.query(
      'egg_quality_defect_counts',
      where: 'eggQualityId = ? AND defectCode = ?',
      whereArgs: ['eq-1', 'dirty'],
    )).single;

    // Load-bearing on both axes: the id did not change AND the write
    // actually landed (a fresh-id-per-save bug can make an ignored insert
    // leave the old id in place while silently failing to update the count).
    expect(secondRow['id'], firstRow['id']);
    expect(secondRow['id'], 'eq-1:dirty');
    expect(secondRow['count'], 9);
  });

  test(
    'markRowsSynced does not clear dirtyAt for an edit that landed after the dirty read',
    () async {
      await save('eq-1', {'dirty': 4});
      final rows = await db.query('egg_quality_defect_counts');
      final id = rows.single['id'] as String;

      final dirtyRows = await repository.getDirtyRows();
      expect(dirtyRows, hasLength(1));

      // Simulate an edit landing between the dirty read and the sync ack.
      await save('eq-1', {'dirty': 7});

      await repository.markRowsSynced([id]);

      final row = (await db.query(
        'egg_quality_defect_counts',
        where: 'id = ?',
        whereArgs: [id],
      )).single;
      expect(row['syncStatus'], 'pending');
      expect(row['dirtyAt'], isNotNull);
      expect(row['count'], 7);
    },
  );

  test(
    'upsertRemoteRow normalizes cloud columns and marks the row synced',
    () async {
      await repository.upsertRemoteRow({
        'id': 'eq-cloud:dirty',
        'egg_quality_id': 'eq-cloud',
        'session_id': 'session-cloud',
        'customer_id': 'customer-cloud',
        'flock_id': 'flock-cloud',
        'hatchery_id': 'hatchery-cloud',
        'date': '2026-08-23',
        'defect_code': 'dirty',
        'defect_category': 'shell',
        'is_reject': true,
        'count': 4,
        'pct_of_sample': 4.0,
        'sort_order': 1,
        'created_at': '2026-08-23T10:00:00.000Z',
        'updated_at': '2026-08-23T10:05:00.000Z',
        'cloud_only_column': 'ignored',
      });

      final row = (await db.query(
        'egg_quality_defect_counts',
        where: 'id = ?',
        whereArgs: ['eq-cloud:dirty'],
      )).single;
      expect(row['eggQualityId'], 'eq-cloud');
      expect(row['defectCode'], 'dirty');
      expect(row['pctOfSample'], 4.0);
      expect(row['syncStatus'], 'synced');
      expect(row['dirtyAt'], isNull);
    },
  );
}
