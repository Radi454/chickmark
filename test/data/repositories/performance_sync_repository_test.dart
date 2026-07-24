import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/repositories/performance_sync_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

void main() {
  late Database db;
  late PerformanceSyncRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE farms (
        id TEXT PRIMARY KEY,
        customerId TEXT NOT NULL,
        sectorKey TEXT NOT NULL,
        name TEXT NOT NULL,
        updatedAt TEXT,
        syncStatus TEXT NOT NULL DEFAULT 'pending',
        dirtyAt TEXT,
        lastSyncedAt TEXT,
        syncError TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE broiler_daily_record_revisions (
        id TEXT PRIMARY KEY,
        recordId TEXT NOT NULL,
        revisionNumber INTEGER NOT NULL,
        dailyMortality INTEGER,
        createdAt TEXT NOT NULL,
        syncStatus TEXT NOT NULL DEFAULT 'pending',
        dirtyAt TEXT,
        lastSyncedAt TEXT,
        syncError TEXT
      )
    ''');
    final dbHelper = _MockDatabaseHelper();
    when(() => dbHelper.db).thenAnswer((_) async => db);
    repository = PerformanceSyncRepository(databaseHelper: dbHelper);
  });

  tearDown(() async => db.close());

  test('push and delete orders preserve every parent dependency', () {
    expect(PerformanceSyncRepository.preFlockPushOrder, [
      'customer_sectors',
      'farms',
      'houses',
      'broiler_target_profiles',
      'broiler_target_rows',
    ]);
    expect(PerformanceSyncRepository.postFlockPushOrder, [
      'flock_placements',
      'broiler_daily_records',
      'broiler_daily_record_revisions',
      'broiler_daily_events',
      'daily_record_sources',
      'performance_alert_rules',
      'performance_concerns',
      'farm_visit_sessions',
      'farm_visit_houses',
      'visit_investigations',
      'visit_findings',
      'cause_assessments',
      'corrective_actions',
      'action_kpi_evaluations',
    ]);
    expect(
      PerformanceSyncRepository.deleteOrder,
      PerformanceSyncRepository.allPushTables.reversed,
    );
  });

  test(
    'normalizes pulled snake_case rows and tracks per-row sync state',
    () async {
      await db.insert('farms', {
        'id': 'farm-1',
        'customerId': 'customer-1',
        'sectorKey': 'broiler',
        'name': 'Old name',
        'updatedAt': '2026-07-23T00:00:00.000Z',
        'syncStatus': 'pending',
        'dirtyAt': '2026-07-23T00:00:00.000Z',
      });

      expect(await repository.getDirtyRows('farms'), hasLength(1));
      await repository.markRowsSynced('farms', ['farm-1']);
      expect((await db.query('farms')).single['syncStatus'], 'synced');

      await repository.upsertRemoteRow('farms', {
        'id': 'farm-1',
        'customer_id': 'customer-1',
        'sector_key': 'broiler',
        'name': 'Cloud name',
        'updated_at': '2026-07-24T00:00:00.000Z',
        'unexpected_remote_column': 'ignored',
      });

      final row = (await db.query('farms')).single;
      expect(row['customerId'], 'customer-1');
      expect(row['name'], 'Cloud name');
      expect(row['syncStatus'], 'synced');
      expect(row['dirtyAt'], isNull);
    },
  );

  test('immutable daily revisions compare business evidence only', () async {
    await db.insert('broiler_daily_record_revisions', {
      'id': 'revision-1',
      'recordId': 'record-1',
      'revisionNumber': 1,
      'dailyMortality': 4,
      'createdAt': '2026-07-24T00:00:00.000Z',
      'syncStatus': 'pending',
      'dirtyAt': '2026-07-24T00:00:00.000Z',
    });
    final local = (await db.query('broiler_daily_record_revisions')).single;

    expect(
      await repository
          .isEquivalentRemoteRow('broiler_daily_record_revisions', local, {
            'id': 'revision-1',
            'record_id': 'record-1',
            'revision_number': 1,
            'daily_mortality': 4,
            'created_at': '2026-07-24T00:00:00.000Z',
            'customer_id': 'customer-1',
          }),
      isTrue,
    );
    expect(
      await repository
          .isEquivalentRemoteRow('broiler_daily_record_revisions', local, {
            'id': 'revision-1',
            'record_id': 'record-1',
            'revision_number': 1,
            'daily_mortality': 9,
            'created_at': '2026-07-24T00:00:00.000Z',
          }),
      isFalse,
    );
  });

  test('remote source payload excludes device-only attachment state', () {
    final payload = repository.prepareRemoteRow('daily_record_sources', {
      'id': 'source-1',
      'revisionId': 'revision-1',
      'sourceKind': 'photo',
      'localPath': '/private/device/photo.jpg',
      'remoteStoragePath': 'supabase://photos/performance_sources/c1/a.jpg',
      'uploadState': 'synced',
      'uploadError': null,
      'syncStatus': 'pending',
      'dirtyAt': '2026-07-24T00:00:00.000Z',
    });

    expect(payload, isNot(contains('localPath')));
    expect(payload, isNot(contains('uploadState')));
    expect(payload, isNot(contains('uploadError')));
    expect(payload, isNot(contains('syncStatus')));
    expect(payload['remoteStoragePath'], contains('performance_sources'));
  });
}
