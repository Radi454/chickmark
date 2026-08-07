import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _panelTables = [
  'egg_storage',
  'egg_quality',
  'chick_quality',
  'chick_weights',
  'fresh_egg_breakout',
  'candled_egg_breakout',
  'residue_breakout',
  'setter_optimizing',
  'hatcher_optimizing',
];

const _legacyTables = [
  'audits',
  'station_samples',
  'sample_records',
  'sample_house_details',
  'sample_machine_details',
  'sample_batch_details',
  'sample_timing_details',
  'egg_quality_samples',
  'chick_pasgar',
  'chick_pasgar_samples',
  'govee_place_readings',
  'govee_spot_captures',
  'govee_spot_readings',
  'temperature_sessions',
  'temperature_readings',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final databaseDir = Directory(
      p.join(
        Directory.systemTemp.path,
        'chickmark_migration_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await databaseDir.create(recursive: true);
    await databaseFactory.setDatabasesPath(databaseDir.path);
  });

  setUp(_resetDatabase);

  tearDown(() async {
    await DatabaseHelper().close();
  });

  test(
    'upgrading a legacy database performs the v41 panel-only cutover',
    () async {
      await _createLegacyDatabase(version: 35);

      final db = await DatabaseHelper().db;
      final tables = await _tableNames(db);

      expect(tables, containsAll(_panelTables));
      for (final table in _legacyTables) {
        expect(tables, isNot(contains(table)), reason: table);
      }
      expect(
        tables.where((table) => table.endsWith('_samples')),
        isEmpty,
        reason: 'panel child sample tables are removed in the hard cutover',
      );
    },
  );

  test('cutover panel tables expose current common columns', () async {
    await _createLegacyDatabase(version: 40);

    final db = await DatabaseHelper().db;
    final eggQualityColumns = await _columnNames(db, 'egg_quality');
    final chickQualityColumns = await _columnNames(db, 'chick_quality');

    expect(
      eggQualityColumns,
      containsAll([
        'sessionId',
        'customerId',
        'hatcheryId',
        'house',
        'setter',
        'hatcher',
        'storagePeriodDays',
        'eggWeightsJson',
        'eggSampleSize',
        'eggAvgWeight',
      ]),
    );
    expect(
      chickQualityColumns,
      containsAll([
        'sessionId',
        'customerId',
        'house',
        'setter',
        'hatcher',
        'pasgarSampleSize',
        'cvtReadingsJson',
        'culledChicksAnalysisJson',
      ]),
    );
    expect(eggQualityColumns, isNot(contains('scopeType')));
    expect(chickQualityColumns, isNot(contains('sampleIndex')));
  });

  test(
    'v46 adds persistent dashboard actions without replacing data',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY)');
      await db.execute('CREATE TABLE hatcheries (id TEXT PRIMARY KEY)');
      await db.execute('CREATE TABLE flocks (id TEXT PRIMARY KEY)');
      await db.execute('CREATE TABLE audit_sessions (id TEXT PRIMARY KEY)');
      await db.execute(
        'CREATE TABLE preserved_rows (id TEXT PRIMARY KEY, value TEXT)',
      );
      await db.insert('preserved_rows', {'id': 'keep', 'value': 'still here'});

      await DatabaseHelper().applyV46UpgradeForTest(db);

      expect(await _tableNames(db), contains('dashboard_actions'));
      expect(
        await _columnNames(db, 'dashboard_actions'),
        containsAll([
          'findingKey',
          'ownerName',
          'status',
          'dueAt',
          'resolutionPhotoId',
          'syncStatus',
        ]),
      );
      expect(await db.query('preserved_rows'), [
        {'id': 'keep', 'value': 'still here'},
      ]);
    },
  );

  test(
    'v51 preserves legacy flocks and classifies only hatchery context',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('''CREATE TABLE flocks (
      id TEXT PRIMARY KEY,
      legacyNote TEXT
    )''');
      await db.execute('''CREATE TABLE audit_sessions (
      id TEXT PRIMARY KEY,
      flockId TEXT,
      hatcheryId TEXT
    )''');
      await db.insert('flocks', {
        'id': 'breeder-flock',
        'legacyNote': 'preserve breeder',
      });
      await db.insert('flocks', {
        'id': 'unknown-flock',
        'legacyNote': 'preserve unknown',
      });
      await db.insert('audit_sessions', {
        'id': 'visit-1',
        'flockId': 'breeder-flock',
        'hatcheryId': 'hatchery-1',
      });

      await DatabaseHelper().applyV51UpgradeForTest(db);

      expect(
        await _columnNames(db, 'flocks'),
        containsAll([
          'farmId',
          'sectorKey',
          'sexProfile',
          'targetProfileId',
          'productionPhase',
        ]),
      );
      expect(
        await db.query(
          'flocks',
          columns: ['id', 'legacyNote', 'sectorKey'],
          orderBy: 'id',
        ),
        [
          {
            'id': 'breeder-flock',
            'legacyNote': 'preserve breeder',
            'sectorKey': 'breeder',
          },
          {
            'id': 'unknown-flock',
            'legacyNote': 'preserve unknown',
            'sectorKey': null,
          },
        ],
      );
    },
  );

  test('v52 adds hatchery agent tables without replacing data', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE flocks (id TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE hatcheries (id TEXT PRIMARY KEY)');
    await db.execute(
      'CREATE TABLE preserved_rows (id TEXT PRIMARY KEY, value TEXT)',
    );
    await db.insert('preserved_rows', {'id': 'keep', 'value': 'still here'});

    await DatabaseHelper().applyV52UpgradeForTest(db);

    expect(
      await _tableNames(db),
      containsAll(const [
        'telegram_staff_links',
        'agent_settings',
        'agent_submissions',
        'agent_questions',
        'hatchery_draft_batches',
        'hatchery_draft_rows',
        'hatchery_agent_audit_events',
        'hatchery_daily_records',
      ]),
    );
    expect(await db.query('preserved_rows'), [
      {'id': 'keep', 'value': 'still here'},
    ]);
  });

  test('v54 repairs divergent harness tables missing indexed columns', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE flocks (id TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE hatcheries (id TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE audit_sessions (id TEXT PRIMARY KEY)');
    // Divergent development lines shipped these tables without turnIndex,
    // contextEpoch, or toolSequence; v54's partial unique indexes reference
    // them, so the upgrade used to fail with "no such column: turnIndex".
    await db.execute('''CREATE TABLE agent_conversations (
      id TEXT PRIMARY KEY,
      staffLinkId TEXT NOT NULL,
      telegramChatId TEXT NOT NULL,
      stateVersion INTEGER NOT NULL DEFAULT 1,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL,
      syncStatus TEXT NOT NULL DEFAULT 'synced',
      dirtyAt TEXT,
      lastSyncedAt TEXT,
      syncError TEXT
    )''');
    await db.execute('''CREATE TABLE agent_conversation_turns (
      id TEXT PRIMARY KEY,
      conversationId TEXT NOT NULL,
      direction TEXT NOT NULL,
      text TEXT NOT NULL,
      createdAt TEXT NOT NULL,
      syncStatus TEXT NOT NULL DEFAULT 'synced',
      dirtyAt TEXT,
      lastSyncedAt TEXT,
      syncError TEXT
    )''');
    await db.execute('''CREATE TABLE agent_tool_events (
      id TEXT PRIMARY KEY,
      conversationTurnId TEXT NOT NULL,
      toolCallId TEXT NOT NULL,
      toolName TEXT NOT NULL,
      status TEXT NOT NULL,
      createdAt TEXT NOT NULL,
      syncStatus TEXT NOT NULL DEFAULT 'synced',
      dirtyAt TEXT,
      lastSyncedAt TEXT,
      syncError TEXT
    )''');
    await db.insert('agent_conversation_turns', {
      'id': 'turn-1',
      'conversationId': 'conv-1',
      'direction': 'inbound',
      'text': 'legacy row',
      'createdAt': '2026-07-01T00:00:00Z',
    });

    await DatabaseHelper().applyV54UpgradeForTest(db);

    final turnColumns = (await db.rawQuery(
      'PRAGMA table_info(agent_conversation_turns)',
    )).map((row) => row['name']).toSet();
    expect(turnColumns, containsAll(const ['turnIndex', 'contextEpoch']));
    final toolColumns = (await db.rawQuery(
      'PRAGMA table_info(agent_tool_events)',
    )).map((row) => row['name']).toSet();
    expect(toolColumns, contains('toolSequence'));
    expect(await db.query('agent_conversation_turns'), hasLength(1));
  });

  test('v56 rebuild survives legacy ALTER TABLE semantics', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    // Apple's system SQLite (iOS/macOS) defaults to legacy ALTER TABLE
    // semantics, where RENAME does not rewrite foreign-key clauses in other
    // tables. The v56 shadow rebuild used to leave the renamed tables
    // referencing the dropped shadow names, so foreign_key_check flagged
    // every row.
    await db.execute('PRAGMA legacy_alter_table = ON');
    await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY)');
    await db.execute('''CREATE TABLE flocks (
      id TEXT PRIMARY KEY,
      customerId TEXT,
      farmId TEXT,
      sectorKey TEXT
    )''');
    await db.execute('CREATE TABLE hatcheries (id TEXT PRIMARY KEY)');
    await db.execute('''CREATE TABLE audit_sessions (
      id TEXT PRIMARY KEY,
      customerId TEXT,
      flockId TEXT,
      hatcheryId TEXT
    )''');

    final helper = DatabaseHelper();
    await helper.applyV52UpgradeForTest(db);
    await helper.applyV53UpgradeForTest(db);
    await helper.applyV54UpgradeForTest(db);
    await db.insert('telegram_staff_links', {
      'id': 'staff-1',
      'telegramUserId': 'tg-1',
      'status': 'allowed',
      'accessRole': 'admin',
    });
    await db.insert('agent_conversations', {
      'id': 'conv-1',
      'staffLinkId': 'staff-1',
      'telegramChatId': 'chat-1',
      'createdAt': '2026-07-01T00:00:00Z',
      'updatedAt': '2026-07-01T00:00:00Z',
    });
    await db.insert('agent_conversation_turns', {
      'id': 'turn-1',
      'conversationId': 'conv-1',
      'direction': 'inbound',
      'text': 'hello',
      'language': 'en',
      'createdAt': '2026-07-01T00:00:01Z',
    });
    await db.insert('agent_tool_events', {
      'id': 'tool-1',
      'conversationTurnId': 'turn-1',
      'toolCallId': 'call-1',
      'toolName': 'list_audits',
      'status': 'succeeded',
      'createdAt': '2026-07-01T00:00:02Z',
    });

    await helper.applyV55UpgradeForTest(db);
    await helper.applyV56UpgradeForTest(db);

    for (final table in const [
      'agent_conversations',
      'agent_conversation_turns',
      'agent_tool_events',
    ]) {
      expect(
        await db.rawQuery('PRAGMA foreign_key_check($table)'),
        isEmpty,
        reason: '$table should have no foreign-key violations',
      );
    }
    expect(await db.query('agent_conversation_turns'), hasLength(1));
    expect(await db.query('agent_tool_events'), hasLength(1));
  });
}

Future<void> _createLegacyDatabase({required int version}) async {
  await DatabaseHelper().close();
  final dbPath = p.join(
    await databaseFactory.getDatabasesPath(),
    'hatchaudit.db',
  );
  final legacyDb = await databaseFactory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY)');
        await db.execute('CREATE TABLE flocks (id TEXT PRIMARY KEY)');
        await db.execute('CREATE TABLE hatcheries (id TEXT PRIMARY KEY)');
        await db.execute('CREATE TABLE audit_sessions (id TEXT PRIMARY KEY)');
        await db.execute('CREATE TABLE audits (id TEXT PRIMARY KEY)');
        await db.execute('CREATE TABLE station_samples (id TEXT PRIMARY KEY)');
        await db.execute('CREATE TABLE sample_records (id TEXT PRIMARY KEY)');
        await db.execute(
          'CREATE TABLE sample_house_details (id TEXT PRIMARY KEY)',
        );
        await db.execute(
          'CREATE TABLE sample_machine_details (id TEXT PRIMARY KEY)',
        );
        await db.execute(
          'CREATE TABLE sample_batch_details (id TEXT PRIMARY KEY)',
        );
        await db.execute(
          'CREATE TABLE sample_timing_details (id TEXT PRIMARY KEY)',
        );
        await db.execute('CREATE TABLE egg_quality (id TEXT PRIMARY KEY)');
        await db.execute(
          'CREATE TABLE egg_quality_samples (id TEXT PRIMARY KEY)',
        );
        await db.execute('CREATE TABLE chick_pasgar (id TEXT PRIMARY KEY)');
        await db.execute(
          'CREATE TABLE chick_pasgar_samples (id TEXT PRIMARY KEY)',
        );
        await db.execute(
          'CREATE TABLE govee_place_readings (id TEXT PRIMARY KEY)',
        );
        await db.execute(
          'CREATE TABLE govee_spot_captures (id TEXT PRIMARY KEY)',
        );
        await db.execute(
          'CREATE TABLE govee_spot_readings (id TEXT PRIMARY KEY)',
        );
        await db.execute(
          'CREATE TABLE temperature_sessions (id TEXT PRIMARY KEY)',
        );
        await db.execute(
          'CREATE TABLE temperature_readings (id TEXT PRIMARY KEY)',
        );
      },
    ),
  );
  await legacyDb.close();
}

Future<void> _resetDatabase() async {
  await DatabaseHelper().close();
  final dbPath = p.join(
    await databaseFactory.getDatabasesPath(),
    'hatchaudit.db',
  );
  await databaseFactory.deleteDatabase(dbPath);
}

Future<Set<String>> _tableNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
  );
  return rows.map((row) => row['name']! as String).toSet();
}

Future<Set<String>> _columnNames(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name']! as String).toSet();
}
