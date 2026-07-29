import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    databaseDirectory = Directory(
      p.join(
        Directory.systemTemp.path,
        'chickmark_unified_agent_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await databaseDirectory.create(recursive: true);
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
  });

  setUp(() async {
    await DatabaseHelper().close();
    await databaseFactory.deleteDatabase(
      p.join(databaseDirectory.path, 'hatchaudit.db'),
    );
  });

  tearDownAll(() async {
    await DatabaseHelper().close();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test('fresh v55 database exposes the unified agent evidence graph', () async {
    final db = await DatabaseHelper().db;

    expect(await _userVersion(db), 55);
    expect(
      await _tableNames(db),
      containsAll(const [
        'agent_conversations',
        'agent_conversation_turns',
        'agent_tool_events',
        'agent_intake_visits',
      ]),
    );
    expect(
      await _columnNames(db, 'telegram_staff_links'),
      containsAll(const ['accessRole', 'customerId']),
    );
    expect(
      await _columnNames(db, 'agent_conversations'),
      containsAll(const [
        'staffLinkId',
        'telegramChatId',
        'stateVersion',
        'pendingActionJson',
        'activeVisitId',
      ]),
    );
    expect(
      await _columnNames(db, 'agent_conversation_turns'),
      containsAll(const [
        'conversationId',
        'direction',
        'telegramUpdateId',
        'telegramMessageId',
        'text',
        'language',
        'model',
        'attachmentJson',
        'deliveryStatus',
      ]),
    );
    expect(
      await _columnNames(db, 'agent_tool_events'),
      containsAll(const [
        'conversationTurnId',
        'toolCallId',
        'toolName',
        'argumentsJson',
        'resultJson',
        'status',
        'durationMs',
        'stateVersionBefore',
        'stateVersionAfter',
      ]),
    );
    expect(
      await _columnNames(db, 'agent_intake_visits'),
      containsAll(const [
        'conversationId',
        'customerId',
        'flockId',
        'hatcheryId',
        'auditDate',
        'state',
        'approvedSessionId',
      ]),
    );
    expect(
      await _columnNames(db, 'agent_intake_sessions'),
      containsAll(const ['visitId', 'rowVersion', 'lastToolEventId']),
    );
    expect(
      await _indexNames(db),
      containsAll(const [
        'idx_agent_conversations_staff_chat',
        'idx_agent_conversation_turns_conversation',
        'idx_agent_tool_events_turn',
        'idx_agent_intake_visits_conversation',
        'idx_agent_intake_sessions_active_conversation',
      ]),
    );
    expect(
      await _triggerNames(db),
      containsAll(const [
        'trg_agent_intake_summary_immutable',
        'trg_agent_tool_events_immutable',
      ]),
    );
  });

  test(
    'v55 scope rebuild preserves sessions and accepts every layer',
    () async {
      final db = await DatabaseHelper().db;
      const now = '2026-07-28T10:00:00.000Z';
      await db.insert('telegram_staff_links', {
        'id': 'scope-admin',
        'telegramUserId': 'telegram-scope',
        'telegramChatId': 'chat-scope',
        'status': 'allowed',
        'accessRole': 'admin',
      });
      await db.insert('agent_intake_sessions', {
        'id': 'scope-intake',
        'staffLinkId': 'scope-admin',
        'telegramChatId': 'chat-scope',
        'schemaKey': 'chicks.weights',
        'schemaVersion': 1,
        'state': 'awaiting_admin_review',
        'language': 'en',
        'auditDate': '2026-07-28',
        'scope': 'house',
        'workingValuesJson': '{"weightsJson":[40,41]}',
        'summaryVersion': 1,
        'summarySnapshotJson': '{"version":1}',
        'userConfirmedAt': now,
        'createdAt': now,
        'updatedAt': now,
      });

      await db.execute('PRAGMA foreign_keys = OFF');
      await DatabaseHelper().applyV55UpgradeForTest(db);
      await db.execute('PRAGMA foreign_keys = ON');

      expect(
        await db.query(
          'agent_intake_sessions',
          columns: ['id', 'scope', 'summarySnapshotJson'],
          where: 'id = ?',
          whereArgs: ['scope-intake'],
        ),
        const [
          {
            'id': 'scope-intake',
            'scope': 'house',
            'summarySnapshotJson': '{"version":1}',
          },
        ],
      );
      for (final layer in const [
        'pool',
        'house',
        'setter',
        'hatcher',
        'setter_hatcher',
        'trolley',
        'tray',
      ]) {
        expect(
          await db.update(
            'agent_intake_sessions',
            {'scope': layer},
            where: 'id = ?',
            whereArgs: ['scope-intake'],
          ),
          1,
          reason: layer,
        );
      }
    },
  );

  test(
    'allowed Telegram links enforce exactly one valid access scope',
    () async {
      final db = await DatabaseHelper().db;
      final customer = (await db.query('customers', limit: 1)).single;

      await expectLater(
        () => db.insert('telegram_staff_links', {
          'id': 'missing-customer',
          'telegramUserId': 'telegram-1',
          'status': 'allowed',
          'accessRole': 'customer',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        () => db.insert('telegram_staff_links', {
          'id': 'restricted-admin',
          'telegramUserId': 'telegram-2',
          'status': 'allowed',
          'accessRole': 'admin',
          'customerId': customer['id'],
        }),
        throwsA(isA<DatabaseException>()),
      );

      await db.insert('telegram_staff_links', {
        'id': 'customer-link',
        'telegramUserId': 'telegram-3',
        'status': 'allowed',
        'accessRole': 'customer',
        'customerId': customer['id'],
      });
      await db.insert('telegram_staff_links', {
        'id': 'admin-link',
        'telegramUserId': 'telegram-4',
        'status': 'allowed',
        'accessRole': 'admin',
      });

      expect(
        await db.query(
          'telegram_staff_links',
          columns: ['id'],
          where: "status = 'allowed'",
        ),
        containsAll(const [
          {'id': 'customer-link'},
          {'id': 'admin-link'},
        ]),
      );
    },
  );

  test('confirmed summaries and tool-call evidence are immutable', () async {
    final db = await DatabaseHelper().db;
    const now = '2026-07-28T10:00:00.000Z';
    await db.insert('telegram_staff_links', {
      'id': 'evidence-admin',
      'telegramUserId': 'telegram-evidence',
      'telegramChatId': 'chat-evidence',
      'status': 'allowed',
      'accessRole': 'admin',
    });
    await db.insert('agent_conversations', {
      'id': 'conversation-1',
      'staffLinkId': 'evidence-admin',
      'telegramChatId': 'chat-evidence',
      'stateVersion': 1,
      'createdAt': now,
      'updatedAt': now,
    });
    await db.insert('agent_conversation_turns', {
      'id': 'conversation-turn-1',
      'conversationId': 'conversation-1',
      'direction': 'inbound',
      'telegramUpdateId': 'update-evidence-1',
      'text': 'sample 40',
      'language': 'en',
      'createdAt': now,
    });
    await db.insert('agent_tool_events', {
      'id': 'tool-event-1',
      'conversationTurnId': 'conversation-turn-1',
      'toolCallId': 'tool-call-1',
      'toolName': 'record_station_values',
      'argumentsJson': '{"pasgarSampleSize":40}',
      'resultJson': '{"accepted":true}',
      'status': 'succeeded',
      'createdAt': now,
    });
    await db.insert('agent_intake_sessions', {
      'id': 'confirmed-intake-1',
      'staffLinkId': 'evidence-admin',
      'telegramChatId': 'chat-evidence',
      'schemaKey': 'chicks.pasgar',
      'schemaVersion': 1,
      'state': 'awaiting_admin_review',
      'language': 'en',
      'auditDate': '2026-07-28',
      'workingValuesJson': '{}',
      'summaryVersion': 1,
      'summarySnapshotJson': '{"pasgarSampleSize":40}',
      'userConfirmedAt': now,
      'createdAt': now,
      'updatedAt': now,
    });

    await expectLater(
      () => db.update(
        'agent_intake_sessions',
        {'summarySnapshotJson': '{"pasgarSampleSize":41}'},
        where: 'id = ?',
        whereArgs: ['confirmed-intake-1'],
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect(
      await db.update(
        'agent_intake_sessions',
        {'state': 'approved'},
        where: 'id = ?',
        whereArgs: ['confirmed-intake-1'],
      ),
      1,
    );
    await expectLater(
      () => db.update(
        'agent_tool_events',
        {'resultJson': '{"accepted":false}'},
        where: 'id = ?',
        whereArgs: ['tool-event-1'],
      ),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      () => db.delete(
        'agent_tool_events',
        where: 'id = ?',
        whereArgs: ['tool-event-1'],
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('v54 upgrade preserves and groups each legacy intake session', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await _createLegacyAgentTables(db);
    await db.insert('telegram_staff_links', {
      'id': 'staff-1',
      'telegramUserId': 'telegram-1',
      'telegramChatId': 'chat-1',
      'status': 'allowed',
      'createdAt': '2026-07-27T09:00:00.000Z',
      'updatedAt': '2026-07-27T09:00:00.000Z',
    });
    await db.insert('agent_intake_sessions', {
      'id': 'intake-1',
      'staffLinkId': 'staff-1',
      'telegramChatId': 'chat-1',
      'schemaKey': 'chicks.pasgar',
      'schemaVersion': 1,
      'state': 'awaiting_admin_review',
      'language': 'ar',
      'auditDate': '2026-07-27',
      'workingValuesJson': '{}',
      'summaryVersion': 1,
      'summarySnapshotJson': '{"pasgarSampleSize":40}',
      'createdAt': '2026-07-27T09:00:00.000Z',
      'updatedAt': '2026-07-27T09:05:00.000Z',
    });

    await DatabaseHelper().applyV54UpgradeForTest(db);

    expect(
      await db.query(
        'telegram_staff_links',
        columns: ['accessRole', 'customerId'],
        where: 'id = ?',
        whereArgs: ['staff-1'],
      ),
      const [
        {'accessRole': 'admin', 'customerId': null},
      ],
    );
    expect(
      await db.query(
        'agent_intake_sessions',
        columns: ['id', 'visitId', 'rowVersion', 'summarySnapshotJson'],
        where: 'id = ?',
        whereArgs: ['intake-1'],
      ),
      const [
        {
          'id': 'intake-1',
          'visitId': 'legacy-visit-intake-1',
          'rowVersion': 1,
          'summarySnapshotJson': '{"pasgarSampleSize":40}',
        },
      ],
    );
    expect(
      await db.query(
        'agent_intake_visits',
        columns: ['id', 'conversationId', 'state'],
      ),
      const [
        {
          'id': 'legacy-visit-intake-1',
          'conversationId': 'legacy-conversation-staff-1-chat-1',
          'state': 'awaiting_admin_review',
        },
      ],
    );
  });
}

Future<void> _createLegacyAgentTables(Database db) async {
  await db.execute('''CREATE TABLE telegram_staff_links (
    id TEXT PRIMARY KEY,
    telegramUserId TEXT NOT NULL UNIQUE,
    telegramChatId TEXT,
    displayName TEXT,
    username TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    invitedBy TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT
  )''');
  await db.execute('''CREATE TABLE agent_intake_sessions (
    id TEXT PRIMARY KEY,
    staffLinkId TEXT NOT NULL,
    telegramChatId TEXT NOT NULL,
    schemaKey TEXT NOT NULL,
    schemaVersion INTEGER NOT NULL,
    state TEXT NOT NULL,
    language TEXT NOT NULL,
    customerId TEXT,
    customerName TEXT,
    flockId TEXT,
    flockName TEXT,
    hatcheryId TEXT,
    hatcheryName TEXT,
    auditDate TEXT NOT NULL,
    scope TEXT,
    setterIdentity TEXT,
    hatcherIdentity TEXT,
    workingValuesJson TEXT NOT NULL DEFAULT '{}',
    pendingClarificationJson TEXT,
    summaryVersion INTEGER NOT NULL DEFAULT 0,
    summarySnapshotJson TEXT,
    userConfirmedAt TEXT,
    approvedSessionId TEXT,
    approvedPanelRowId TEXT,
    reviewedBy TEXT,
    reviewedAt TEXT,
    rejectionReason TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT
  )''');
}

Future<int> _userVersion(Database db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  return rows.single['user_version']! as int;
}

Future<Set<String>> _tableNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  return rows.map((row) => row['name']! as String).toSet();
}

Future<Set<String>> _columnNames(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name']! as String).toSet();
}

Future<Set<String>> _indexNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'index'",
  );
  return rows.map((row) => row['name']! as String).toSet();
}

Future<Set<String>> _triggerNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'trigger'",
  );
  return rows.map((row) => row['name']! as String).toSet();
}
