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
        'chickmark_pasgar_intake_${DateTime.now().microsecondsSinceEpoch}',
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

  test('fresh v62 database exposes the conversational intake graph', () async {
    final db = await DatabaseHelper().db;

    expect(await _userVersion(db), 62);
    expect(
      await _tableNames(db),
      containsAll(const [
        'agent_intake_sessions',
        'agent_intake_turns',
        'agent_intake_values',
      ]),
    );
    expect(
      await _columnNames(db, 'agent_intake_sessions'),
      containsAll(const [
        'staffLinkId',
        'telegramChatId',
        'schemaKey',
        'schemaVersion',
        'state',
        'language',
        'customerId',
        'flockId',
        'hatcheryId',
        'auditDate',
        'scope',
        'workingValuesJson',
        'summaryVersion',
        'summarySnapshotJson',
        'userConfirmedAt',
        'approvedSessionId',
        'approvedPanelRowId',
        'syncStatus',
      ]),
    );
    expect(
      await _columnNames(db, 'agent_intake_turns'),
      containsAll(const [
        'intakeSessionId',
        'direction',
        'telegramUpdateId',
        'text',
        'intent',
        'deliveryStatus',
        'attachmentRemotePath',
      ]),
    );
    expect(
      await _columnNames(db, 'agent_intake_values'),
      containsAll(const [
        'intakeSessionId',
        'fieldKey',
        'valueJson',
        'sourcePhrase',
        'confidence',
        'clarificationReason',
      ]),
    );
    expect(
      await _indexNames(db),
      containsAll(const [
        'idx_agent_intake_sessions_active_conversation',
        'idx_agent_intake_sessions_review',
        'idx_agent_intake_turns_session',
        'idx_agent_intake_values_session',
      ]),
    );
  });

  test(
    'v53 upgrade preserves existing rows and enforces evidence uniqueness',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('CREATE TABLE preserved_rows (id TEXT PRIMARY KEY)');
      await db.insert('preserved_rows', {'id': 'keep'});

      await DatabaseHelper().applyV53UpgradeForTest(db);

      expect(await db.query('preserved_rows'), [
        {'id': 'keep'},
      ]);

      await db.insert('agent_intake_sessions', _sessionRow());
      await db.insert('agent_intake_turns', _turnRow('turn-1'));
      await expectLater(
        () => db.insert('agent_intake_turns', _turnRow('turn-2')),
        throwsA(isA<DatabaseException>()),
      );

      await db.insert('agent_intake_values', _valueRow('value-1'));
      await expectLater(
        () => db.insert('agent_intake_values', _valueRow('value-2')),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
}

Map<String, Object?> _sessionRow() => {
  'id': 'intake-1',
  'staffLinkId': 'staff-1',
  'telegramChatId': 'chat-1',
  'schemaKey': 'chicks.pasgar',
  'schemaVersion': 1,
  'state': 'collecting',
  'language': 'en',
  'auditDate': '2026-07-28',
  'workingValuesJson': '{}',
  'summaryVersion': 0,
  'createdAt': '2026-07-28T10:00:00.000Z',
  'updatedAt': '2026-07-28T10:00:00.000Z',
};

Map<String, Object?> _turnRow(String id) => {
  'id': id,
  'intakeSessionId': 'intake-1',
  'direction': 'inbound',
  'telegramUpdateId': 'update-1',
  'text': 'sample 40',
  'language': 'en',
  'intent': 'provide_data',
  'createdAt': '2026-07-28T10:00:00.000Z',
};

Map<String, Object?> _valueRow(String id) => {
  'id': id,
  'intakeSessionId': 'intake-1',
  'fieldKey': 'pasgarSampleSize',
  'valueJson': '40',
  'sourcePhrase': 'sample 40',
  'confidence': 0.99,
  'createdAt': '2026-07-28T10:00:00.000Z',
  'updatedAt': '2026-07-28T10:00:00.000Z',
};

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
