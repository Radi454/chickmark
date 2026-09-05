import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/repositories/performance_sync_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late PerformanceSyncRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE houses (
        id TEXT PRIMARY KEY,
        flockId TEXT NOT NULL,
        name TEXT NOT NULL,
        updatedAt TEXT,
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
        toolSequence INTEGER,
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
    ]);
    expect(PerformanceSyncRepository.postFlockPushOrder, [
      'houses',
      'breeder_flock_milestones',
      'breeder_isolation_areas',
      'breeder_weighing_sessions',
      'breeder_weighing_samples',
      'egg_batches',
      'egg_batch_house_sources',
      'breeder_performance_alerts',
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
        'tool_sequence': 1,
        'arguments_json': {'pasgarSampleSize': 40},
        'result_json': {'accepted': true},
        'status': 'succeeded',
        'created_at': '2026-07-28T10:00:00.000Z',
      });

      final row = await repository.getRowById('agent_tool_events', 'tool-1');
      expect(row, isNotNull);
      expect(row!['conversationTurnId'], 'turn-1');
      expect(row['toolCallId'], 'call-1');
      expect(row['toolSequence'], 1);
      expect(row['argumentsJson'], '{"pasgarSampleSize":40}');
      expect(row['resultJson'], '{"accepted":true}');
      expect(row['syncStatus'], 'synced');

      await repository.upsertRemoteRow('agent_tool_events', {
        'id': 'tool-1',
        'conversation_turn_id': 'turn-1',
        'tool_call_id': 'call-1',
        'tool_name': 'record_station_values',
        'tool_sequence': 1,
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
      await db.insert('houses', {
        'id': 'house-1',
        'flockId': 'flock-1',
        'name': 'Old name',
        'updatedAt': '2026-07-23T00:00:00.000Z',
        'syncStatus': 'pending',
        'dirtyAt': '2026-07-23T00:00:00.000Z',
      });

      expect(await repository.getDirtyRows('houses'), hasLength(1));
      await repository.markRowsSynced('houses', ['house-1']);
      expect((await db.query('houses')).single['syncStatus'], 'synced');

      await repository.upsertRemoteRow('houses', {
        'id': 'house-1',
        'flock_id': 'flock-1',
        'name': 'Cloud name',
        'updated_at': '2026-07-24T00:00:00.000Z',
        'unexpected_remote_column': 'ignored',
      });

      final row = (await db.query('houses')).single;
      expect(row['flockId'], 'flock-1');
      expect(row['name'], 'Cloud name');
      expect(row['syncStatus'], 'synced');
      expect(row['dirtyAt'], isNull);
    },
  );

  test('immutable tool events compare business evidence only', () async {
    await db.insert('agent_tool_events', {
      'id': 'tool-1',
      'conversationTurnId': 'turn-1',
      'toolCallId': 'call-1',
      'toolName': 'record_station_values',
      'toolSequence': 1,
      'argumentsJson': '{"pasgarSampleSize":40}',
      'resultJson': '{"accepted":true}',
      'status': 'succeeded',
      'createdAt': '2026-07-24T00:00:00.000Z',
      'syncStatus': 'synced',
    });
    final local = (await db.query('agent_tool_events')).single;

    expect(
      await repository.isEquivalentRemoteRow('agent_tool_events', local, {
        'id': 'tool-1',
        'conversation_turn_id': 'turn-1',
        'tool_call_id': 'call-1',
        'tool_name': 'record_station_values',
        'tool_sequence': 1,
        'arguments_json': {'pasgarSampleSize': 40},
        'result_json': {'accepted': true},
        'status': 'succeeded',
        'created_at': '2026-07-24T00:00:00.000Z',
      }),
      isTrue,
    );
    expect(
      await repository.isEquivalentRemoteRow('agent_tool_events', local, {
        'id': 'tool-1',
        'conversation_turn_id': 'turn-1',
        'tool_call_id': 'call-1',
        'tool_name': 'record_station_values',
        'tool_sequence': 1,
        'arguments_json': {'pasgarSampleSize': 40},
        'result_json': {'accepted': false},
        'status': 'failed',
        'created_at': '2026-07-24T00:00:00.000Z',
      }),
      isFalse,
    );
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

  group('mark-synced race protection', () {
    test('a row edited mid-push stays pending after markRowsSynced', () async {
      await db.insert('houses', {
        'id': 'house-race',
        'flockId': 'flock-1',
        'name': 'House',
        'updatedAt': '2026-07-23T00:00:00.000Z',
        'syncStatus': 'pending',
        'dirtyAt': '2026-07-23T00:00:00.000Z',
      });
      await repository.getDirtyRows('houses'); // capture cutoff
      await Future<void>.delayed(const Duration(milliseconds: 5));
      // mid-push edit: whatever domain repo owns 'houses' would stamp dirtyAt
      // the same way performance_sync_repository does (UTC ISO8601).
      await db.update(
        'houses',
        {
          'name': 'House edited',
          'syncStatus': 'pending',
          'dirtyAt': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: ['house-race'],
      );
      await repository.markRowsSynced('houses', ['house-race']);
      final row = (await db.query(
        'houses',
        where: 'id = ?',
        whereArgs: ['house-race'],
      )).single;
      expect(row['syncStatus'], 'pending');
      expect(row['dirtyAt'], isNotNull);
    });

    test('an unedited row is cleared by markRowsSynced', () async {
      await db.insert('houses', {
        'id': 'house-race-2',
        'flockId': 'flock-1',
        'name': 'House',
        'updatedAt': '2026-07-23T00:00:00.000Z',
        'syncStatus': 'pending',
        'dirtyAt': '2026-07-23T00:00:00.000Z',
      });
      await repository.getDirtyRows('houses');
      await repository.markRowsSynced('houses', ['house-race-2']);
      final row = (await db.query(
        'houses',
        where: 'id = ?',
        whereArgs: ['house-race-2'],
      )).single;
      expect(row['syncStatus'], 'synced');
    });
  });
}
