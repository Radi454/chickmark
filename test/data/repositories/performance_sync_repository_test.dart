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
    await db.execute('''
      CREATE TABLE agent_intake_sessions (
        id TEXT PRIMARY KEY,
        state TEXT,
        workingValuesJson TEXT,
        pendingClarificationJson TEXT,
        summarySnapshotJson TEXT,
        syncStatus TEXT NOT NULL DEFAULT 'pending',
        dirtyAt TEXT,
        lastSyncedAt TEXT,
        syncError TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE agent_tool_events (
        id TEXT PRIMARY KEY,
        conversationTurnId TEXT NOT NULL,
        toolCallId TEXT NOT NULL,
        toolName TEXT NOT NULL,
        argumentsJson TEXT NOT NULL,
        resultJson TEXT,
        status TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        syncStatus TEXT NOT NULL DEFAULT 'synced',
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
      'telegram_staff_links',
      'agent_settings',
      'agent_submissions',
      'agent_questions',
      'hatchery_draft_batches',
      'hatchery_draft_rows',
      'hatchery_agent_audit_events',
      'hatchery_daily_records',
      'agent_intake_sessions',
      'agent_intake_turns',
      'agent_intake_values',
    ]);
    expect(
      PerformanceSyncRepository.deleteOrder,
      PerformanceSyncRepository.allPushTables.reversed,
    );
    expect(
      PerformanceSyncRepository.postFlockPushOrder,
      containsAllInOrder([
        'agent_intake_sessions',
        'agent_intake_turns',
        'agent_intake_values',
      ]),
    );
    expect(
      PerformanceSyncRepository.allPushTables,
      isNot(contains('agent_tool_events')),
    );
    expect(
      PerformanceSyncRepository.allPullTables,
      containsAllInOrder(const [
        'agent_conversations',
        'agent_conversation_turns',
        'agent_tool_events',
        'agent_intake_visits',
        'agent_intake_sessions',
        'agent_intake_turns',
        'agent_intake_values',
      ]),
    );
    expect(
      PerformanceSyncRepository.deleteOrder,
      isNot(contains('agent_tool_events')),
    );
  });

  test(
    'pulls server tool evidence with snake/camel and JSON conversion',
    () async {
      await repository.upsertRemoteRow('agent_tool_events', {
        'id': 'tool-1',
        'conversation_turn_id': 'turn-1',
        'tool_call_id': 'call-1',
        'tool_name': 'record_station_values',
        'arguments_json': {'pasgarSampleSize': 40},
        'result_json': {'accepted': true},
        'status': 'succeeded',
        'created_at': '2026-07-28T10:00:00.000Z',
      });

      final row = await repository.getRowById('agent_tool_events', 'tool-1');
      expect(row, isNotNull);
      expect(row!['conversationTurnId'], 'turn-1');
      expect(row['toolCallId'], 'call-1');
      expect(row['argumentsJson'], '{"pasgarSampleSize":40}');
      expect(row['resultJson'], '{"accepted":true}');
      expect(row['syncStatus'], 'synced');

      await repository.upsertRemoteRow('agent_tool_events', {
        'id': 'tool-1',
        'conversation_turn_id': 'turn-1',
        'tool_call_id': 'call-1',
        'tool_name': 'record_station_values',
        'arguments_json': {'pasgarSampleSize': 40},
        'result_json': {'accepted': false},
        'status': 'failed',
        'created_at': '2026-07-28T10:00:00.000Z',
      });
      final preserved = await repository.getRowById(
        'agent_tool_events',
        'tool-1',
      );
      expect(preserved!['resultJson'], '{"accepted":true}');
      expect(preserved['status'], 'succeeded');

      await expectLater(
        repository.getDirtyRows('agent_tool_events'),
        throwsArgumentError,
      );
    },
  );

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

  test(
    'intake JSON crosses the SQLite and Supabase boundary as JSON',
    () async {
      final payload = repository.prepareRemoteRow('agent_intake_sessions', {
        'id': 'intake-1',
        'workingValuesJson': '{"pasgarSampleSize":40}',
        'pendingClarificationJson': null,
        'summarySnapshotJson': '{"version":1,"values":{}}',
        'syncStatus': 'pending',
      });

      expect(payload['workingValuesJson'], {'pasgarSampleSize': 40});
      expect(payload['summarySnapshotJson'], {
        'version': 1,
        'values': <String, Object?>{},
      });

      await repository.upsertRemoteRow('agent_intake_sessions', {
        'id': 'intake-1',
        'state': 'awaiting_admin_review',
        'working_values_json': {'pasgarSampleSize': 40},
        'pending_clarification_json': null,
        'summary_snapshot_json': {
          'version': 1,
          'values': {'pasgarSampleSize': 40},
        },
      });
      final row = (await db.query('agent_intake_sessions')).single;
      expect(row['workingValuesJson'], '{"pasgarSampleSize":40}');
      expect(
        row['summarySnapshotJson'],
        '{"version":1,"values":{"pasgarSampleSize":40}}',
      );
      expect(row['syncStatus'], 'synced');
    },
  );
}
