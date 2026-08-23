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

  test(
    'fresh v60 database exposes ordered agent diagnostics and context',
    () async {
      final db = await DatabaseHelper().db;

      expect(await _userVersion(db), 60);
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
          'contextEpoch',
          'selectedCustomerId',
          'selectedFlockId',
          'selectedAuditId',
          'contextUpdatedAt',
          'pendingActionJson',
          'activeVisitId',
          'title',
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
          'turnIndex',
          'contextEpoch',
          'provider',
          'model',
          'providerResponseId',
          'replyToTurnId',
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
          'toolSequence',
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
          'idx_agent_conversation_turns_order',
          'idx_agent_tool_events_turn',
          'idx_agent_tool_events_sequence',
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
    },
  );

  test(
    'v56 backfill preserves explicit sectors and only assigns safe legacy matches',
    () async {
      final db = await DatabaseHelper().db;
      const now = '2026-07-30T10:00:00.000Z';
      for (final customerId in const [
        'sector-farm-customer',
        'sector-audit-customer',
        'sector-single-customer',
        'sector-ambiguous-customer',
        'sector-existing-customer',
      ]) {
        await db.insert('customers', {
          'id': customerId,
          'name': customerId,
          'createdAt': now,
        });
      }
      await db.insert('farms', {
        'id': 'sector-farm',
        'customerId': 'sector-farm-customer',
        'sectorKey': 'broiler',
        'name': 'Broiler farm',
      });
      for (final row in const [
        {
          'id': 'flock-farm',
          'customerId': 'sector-farm-customer',
          'farmId': 'sector-farm',
        },
        {'id': 'flock-audit', 'customerId': 'sector-audit-customer'},
        {'id': 'flock-single', 'customerId': 'sector-single-customer'},
        {'id': 'flock-ambiguous', 'customerId': 'sector-ambiguous-customer'},
        {
          'id': 'flock-existing',
          'customerId': 'sector-existing-customer',
          'sectorKey': 'layer',
        },
      ]) {
        await db.insert('flocks', row);
      }
      await db.insert('hatcheries', {
        'id': 'sector-hatchery',
        'customerId': 'sector-audit-customer',
        'name': 'Hatchery',
      });
      await db.insert('audit_sessions', {
        'id': 'sector-audit',
        'customerId': 'sector-audit-customer',
        'flockId': 'flock-audit',
        'hatcheryId': 'sector-hatchery',
        'date': '2026-07-30',
      });
      for (final row in const [
        {
          'id': 'sector-single',
          'customerId': 'sector-single-customer',
          'sectorKey': 'layer',
          'isActive': 1,
        },
        {
          'id': 'sector-ambiguous-a',
          'customerId': 'sector-ambiguous-customer',
          'sectorKey': 'breeder',
          'isActive': 1,
        },
        {
          'id': 'sector-ambiguous-b',
          'customerId': 'sector-ambiguous-customer',
          'sectorKey': 'broiler',
          'isActive': 1,
        },
      ]) {
        await db.insert('customer_sectors', row);
      }

      await DatabaseHelper().applyV56UpgradeForTest(db);

      final rows = await db.query(
        'flocks',
        columns: ['id', 'sectorKey'],
        where: "id LIKE 'flock-%'",
        orderBy: 'id',
      );
      expect(
        rows,
        containsAll(const [
          {'id': 'flock-farm', 'sectorKey': 'broiler'},
          {'id': 'flock-audit', 'sectorKey': 'breeder'},
          {'id': 'flock-single', 'sectorKey': 'layer'},
          {'id': 'flock-ambiguous', 'sectorKey': null},
          {'id': 'flock-existing', 'sectorKey': 'layer'},
        ]),
      );
    },
  );

  test(
    'v56 backfills deterministic evidence order and restores immutability',
    () async {
      final db = await DatabaseHelper().db;
      const now = '2026-07-30T10:00:00.000Z';
      await db.insert('telegram_staff_links', {
        'id': 'v56-order-staff',
        'telegramUserId': 'v56-order-user',
        'telegramChatId': 'v56-order-chat',
        'status': 'allowed',
        'accessRole': 'admin',
      });
      await db.insert('agent_conversations', {
        'id': 'v56-order-conversation',
        'staffLinkId': 'v56-order-staff',
        'telegramChatId': 'v56-order-chat',
        'stateVersion': 1,
        'createdAt': now,
        'updatedAt': now,
      });
      for (final turnId in const ['v56-order-turn-a', 'v56-order-turn-b']) {
        await db.insert('agent_conversation_turns', {
          'id': turnId,
          'conversationId': 'v56-order-conversation',
          'direction': 'inbound',
          'telegramUpdateId': 'update-$turnId',
          'text': turnId,
          'language': 'en',
          'createdAt': now,
        });
      }
      for (final eventId in const ['v56-order-event-a', 'v56-order-event-b']) {
        await db.insert('agent_tool_events', {
          'id': eventId,
          'conversationTurnId': 'v56-order-turn-a',
          'toolCallId': 'call-$eventId',
          'toolName': 'get_user_scope',
          'argumentsJson': '{}',
          'resultJson': '{"ok":true,"code":"ok"}',
          'status': 'succeeded',
          'createdAt': now,
        });
      }

      await DatabaseHelper().applyV56UpgradeForTest(db);

      expect(
        await db.query(
          'agent_conversation_turns',
          columns: ['id', 'turnIndex'],
          where: "id LIKE 'v56-order-turn-%'",
          orderBy: 'id',
        ),
        const [
          {'id': 'v56-order-turn-a', 'turnIndex': 1},
          {'id': 'v56-order-turn-b', 'turnIndex': 2},
        ],
      );
      expect(
        await db.query(
          'agent_tool_events',
          columns: ['id', 'toolSequence'],
          where: "id LIKE 'v56-order-event-%'",
          orderBy: 'id',
        ),
        const [
          {'id': 'v56-order-event-a', 'toolSequence': 1},
          {'id': 'v56-order-event-b', 'toolSequence': 2},
        ],
      );
      await expectLater(
        () => db.update(
          'agent_tool_events',
          {'resultJson': '{"ok":false}'},
          where: 'id = ?',
          whereArgs: ['v56-order-event-a'],
        ),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'v55 to v56 rebuild preserves rows and installs the fresh integrity contract',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createV55UnifiedAgentFixture(db);
      await db.execute('PRAGMA foreign_keys = ON');

      await DatabaseHelper().applyV56UpgradeForTest(db);

      expect(
        await db.query(
          'agent_conversations',
          columns: ['id', 'stateVersion', 'contextEpoch'],
        ),
        const [
          {'id': 'v55-conversation', 'stateVersion': 3, 'contextEpoch': 1},
        ],
      );
      expect(
        await db.query(
          'agent_conversation_turns',
          columns: ['id', 'turnIndex', 'contextEpoch', 'text'],
        ),
        const [
          {
            'id': 'v55-turn',
            'turnIndex': 1,
            'contextEpoch': 1,
            'text': 'preserve this turn',
          },
        ],
      );
      expect(
        await db.query(
          'agent_tool_events',
          columns: ['id', 'toolSequence', 'resultJson'],
        ),
        const [
          {'id': 'v55-tool', 'toolSequence': 1, 'resultJson': '{"ok":true}'},
        ],
      );

      expect(
        await _foreignKeys(db, 'agent_conversations'),
        containsAll(const [
          ('selectedCustomerId', 'customers', 'id', 'SET NULL'),
          ('selectedFlockId', 'flocks', 'id', 'SET NULL'),
          ('selectedAuditId', 'audit_sessions', 'id', 'SET NULL'),
        ]),
      );
      expect(
        await _foreignKeys(db, 'agent_conversation_turns'),
        contains(const (
          'replyToTurnId',
          'agent_conversation_turns',
          'id',
          'SET NULL',
        )),
      );

      await expectLater(
        () => db.update(
          'agent_conversations',
          {'contextEpoch': 0},
          where: 'id = ?',
          whereArgs: ['v55-conversation'],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        () => db.update(
          'agent_conversation_turns',
          {'turnIndex': 0},
          where: 'id = ?',
          whereArgs: ['v55-turn'],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        () => db.insert('agent_tool_events', {
          'id': 'invalid-sequence',
          'conversationTurnId': 'v55-turn',
          'toolCallId': 'invalid-sequence-call',
          'toolName': 'get_user_scope',
          'toolSequence': 0,
          'argumentsJson': '{}',
          'status': 'requested',
          'createdAt': '2026-07-30T10:05:00.000Z',
        }),
        throwsA(isA<DatabaseException>()),
      );

      await db.update(
        'agent_conversations',
        {
          'selectedCustomerId': 'v55-customer',
          'selectedFlockId': 'v55-flock',
          'selectedAuditId': 'v55-audit',
        },
        where: 'id = ?',
        whereArgs: ['v55-conversation'],
      );
      await db.delete(
        'audit_sessions',
        where: 'id = ?',
        whereArgs: ['v55-audit'],
      );
      expect(
        (await db.query(
          'agent_conversations',
          columns: ['selectedAuditId'],
          where: 'id = ?',
          whereArgs: ['v55-conversation'],
        )).single['selectedAuditId'],
        isNull,
      );
    },
  );

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

  test(
    'app-channel staff links persist and anchor their conversation',
    () async {
      final db = await DatabaseHelper().db;
      const now = '2026-08-15T10:00:00.000Z';

      // The cloud shape for an in-app staff member: no Telegram identity at
      // all. Before v59 this row failed telegramUserId NOT NULL, and because
      // the pull upsert uses INSERT OR IGNORE it vanished without an error —
      // taking every conversation that referenced it down with it.
      await db.insert('telegram_staff_links', {
        'id': 'app-user-link',
        'telegramUserId': null,
        'telegramChatId': 'app',
        'displayName': 'App Admin',
        'status': 'allowed',
        'accessRole': 'admin',
        'channel': 'app',
        'appUserId': 'dc4cd5c0-e3d9-4761-b973-2b19f8f9c9a5',
        'createdAt': now,
        'updatedAt': now,
      });
      expect(
        await db.query('telegram_staff_links', where: "id = 'app-user-link'"),
        hasLength(1),
      );

      await db.insert('agent_conversations', {
        'id': 'app-conversation',
        'staffLinkId': 'app-user-link',
        'telegramChatId': 'app',
        'stateVersion': 1,
        'createdAt': now,
        'updatedAt': now,
      });
      expect(
        await db.rawQuery('PRAGMA foreign_key_check(agent_conversations)'),
        isEmpty,
      );

      // A second app link must not collide with the first: uniqueness is per
      // channel, so the NULL telegramUserId columns do not compete.
      await db.insert('telegram_staff_links', {
        'id': 'app-user-link-2',
        'telegramUserId': null,
        'telegramChatId': 'app',
        'status': 'allowed',
        'accessRole': 'admin',
        'channel': 'app',
        'appUserId': 'a2f0f1b6-0000-4000-8000-000000000002',
        'createdAt': now,
        'updatedAt': now,
      });

      // Telegram identities stay unique, and so do app identities.
      await db.insert('telegram_staff_links', {
        'id': 'telegram-dupe-source',
        'telegramUserId': 'telegram-dupe',
        'status': 'pending',
        'accessRole': 'customer',
      });
      await expectLater(
        () => db.insert('telegram_staff_links', {
          'id': 'telegram-dupe-clash',
          'telegramUserId': 'telegram-dupe',
          'status': 'pending',
          'accessRole': 'customer',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        () => db.insert('telegram_staff_links', {
          'id': 'app-user-link-clash',
          'status': 'pending',
          'accessRole': 'customer',
          'channel': 'app',
          'appUserId': 'dc4cd5c0-e3d9-4761-b973-2b19f8f9c9a5',
        }),
        throwsA(isA<DatabaseException>()),
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

  test(
    'v54 upgrade creates missing agent prerequisites before unified indexes',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('''
        CREATE TABLE legacy_local_rows (
          id TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
      await db.insert('legacy_local_rows', {
        'id': 'preserved-1',
        'value': 'must survive',
      });

      await DatabaseHelper().applyV54UpgradeForTest(db);

      expect(
        await _tableNames(db),
        containsAll(const [
          'telegram_staff_links',
          'agent_intake_sessions',
          'agent_conversations',
        ]),
      );
      expect(
        await _indexNames(db),
        contains('idx_agent_intake_sessions_active_conversation'),
      );
      expect(await db.query('legacy_local_rows'), const [
        {'id': 'preserved-1', 'value': 'must survive'},
      ]);
    },
  );

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

Future<void> _createV55UnifiedAgentFixture(Database db) async {
  const now = '2026-07-30T10:00:00.000Z';
  await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY)');
  await db.execute('''CREATE TABLE flocks (
    id TEXT PRIMARY KEY,
    customerId TEXT,
    farmId TEXT,
    sectorKey TEXT
  )''');
  await db.execute('''CREATE TABLE hatcheries (
    id TEXT PRIMARY KEY,
    customerId TEXT
  )''');
  await db.execute('''CREATE TABLE audit_sessions (
    id TEXT PRIMARY KEY,
    customerId TEXT,
    flockId TEXT,
    hatcheryId TEXT
  )''');
  await db.execute('''CREATE TABLE telegram_staff_links (
    id TEXT PRIMARY KEY,
    telegramUserId TEXT NOT NULL UNIQUE,
    telegramChatId TEXT,
    status TEXT NOT NULL,
    accessRole TEXT NOT NULL DEFAULT 'customer',
    customerId TEXT
  )''');
  await db.execute('''CREATE TABLE agent_conversations (
    id TEXT PRIMARY KEY,
    staffLinkId TEXT NOT NULL,
    telegramChatId TEXT NOT NULL,
    stateVersion INTEGER NOT NULL DEFAULT 1 CHECK (stateVersion >= 1),
    pendingActionJson TEXT,
    activeVisitId TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'synced',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    UNIQUE (staffLinkId, telegramChatId),
    FOREIGN KEY (staffLinkId)
      REFERENCES telegram_staff_links(id) ON DELETE CASCADE
  )''');
  await db.execute('''CREATE TABLE agent_conversation_turns (
    id TEXT PRIMARY KEY,
    conversationId TEXT NOT NULL,
    direction TEXT NOT NULL CHECK (direction IN ('inbound', 'outbound')),
    telegramUpdateId TEXT UNIQUE,
    telegramMessageId TEXT,
    text TEXT NOT NULL,
    language TEXT NOT NULL CHECK (language IN ('en', 'ar', 'mixed')),
    model TEXT,
    attachmentJson TEXT,
    deliveryStatus TEXT,
    createdAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'synced',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (conversationId)
      REFERENCES agent_conversations(id) ON DELETE CASCADE
  )''');
  await db.execute('''CREATE TABLE agent_tool_events (
    id TEXT PRIMARY KEY,
    conversationTurnId TEXT NOT NULL,
    toolCallId TEXT NOT NULL,
    toolName TEXT NOT NULL,
    argumentsJson TEXT NOT NULL DEFAULT '{}',
    resultJson TEXT,
    status TEXT NOT NULL CHECK (status IN (
      'requested', 'succeeded', 'rejected', 'failed'
    )),
    durationMs INTEGER CHECK (durationMs IS NULL OR durationMs >= 0),
    stateVersionBefore INTEGER
      CHECK (stateVersionBefore IS NULL OR stateVersionBefore >= 1),
    stateVersionAfter INTEGER
      CHECK (stateVersionAfter IS NULL OR stateVersionAfter >= 1),
    createdAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'synced',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    UNIQUE (conversationTurnId, toolCallId),
    FOREIGN KEY (conversationTurnId)
      REFERENCES agent_conversation_turns(id) ON DELETE CASCADE
  )''');
  await db.execute('''CREATE TABLE agent_intake_visits (
    id TEXT PRIMARY KEY,
    conversationId TEXT NOT NULL,
    customerId TEXT,
    flockId TEXT,
    hatcheryId TEXT,
    auditDate TEXT NOT NULL,
    state TEXT NOT NULL,
    approvedSessionId TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'synced',
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
    auditDate TEXT NOT NULL,
    workingValuesJson TEXT NOT NULL DEFAULT '{}',
    summaryVersion INTEGER NOT NULL DEFAULT 0,
    summarySnapshotJson TEXT,
    userConfirmedAt TEXT,
    visitId TEXT,
    rowVersion INTEGER NOT NULL DEFAULT 1,
    lastToolEventId TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL
  )''');

  await db.insert('customers', {'id': 'v55-customer'});
  await db.insert('flocks', {
    'id': 'v55-flock',
    'customerId': 'v55-customer',
    'sectorKey': 'breeder',
  });
  await db.insert('hatcheries', {
    'id': 'v55-hatchery',
    'customerId': 'v55-customer',
  });
  await db.insert('audit_sessions', {
    'id': 'v55-audit',
    'customerId': 'v55-customer',
    'flockId': 'v55-flock',
    'hatcheryId': 'v55-hatchery',
  });
  await db.insert('telegram_staff_links', {
    'id': 'v55-staff',
    'telegramUserId': 'v55-user',
    'telegramChatId': 'v55-chat',
    'status': 'allowed',
    'accessRole': 'admin',
  });
  await db.insert('agent_conversations', {
    'id': 'v55-conversation',
    'staffLinkId': 'v55-staff',
    'telegramChatId': 'v55-chat',
    'stateVersion': 3,
    'createdAt': now,
    'updatedAt': now,
  });
  await db.insert('agent_conversation_turns', {
    'id': 'v55-turn',
    'conversationId': 'v55-conversation',
    'direction': 'inbound',
    'telegramUpdateId': 'v55-update',
    'text': 'preserve this turn',
    'language': 'en',
    'createdAt': now,
  });
  await db.insert('agent_tool_events', {
    'id': 'v55-tool',
    'conversationTurnId': 'v55-turn',
    'toolCallId': 'v55-tool-call',
    'toolName': 'get_user_scope',
    'argumentsJson': '{}',
    'resultJson': '{"ok":true}',
    'status': 'succeeded',
    'createdAt': now,
  });
}

Future<Set<(String, String, String, String)>> _foreignKeys(
  Database db,
  String table,
) async {
  final rows = await db.rawQuery('PRAGMA foreign_key_list($table)');
  return rows
      .map(
        (row) => (
          row['from']! as String,
          row['table']! as String,
          row['to']! as String,
          row['on_delete']! as String,
        ),
      )
      .toSet();
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
