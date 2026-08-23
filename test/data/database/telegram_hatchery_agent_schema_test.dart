import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = await useIsolatedAppDatabase();
  });

  setUp(resetAppDatabase);

  tearDownAll(() async {
    await resetAppDatabase();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test('fresh v62 database preserves Telegram hatchery agent tables', () async {
    final db = await DatabaseHelper().db;

    expect(await _userVersion(db), 62);
    expect(
      await _tableNames(db),
      containsAll(const <String>[
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
    expect(
      await _columnNames(db, 'hatchery_draft_rows'),
      containsAll(const [
        'customerName',
        'flockName',
        'stationName',
        'breed',
        'eggsPlaced',
        'totalProduction',
        'hatchabilityPct',
        'confidencePct',
        'warningsJson',
        'status',
      ]),
    );
    expect(
      await _indexNames(db),
      containsAll(const [
        'idx_agent_submissions_status',
        'idx_hatchery_draft_rows_batch',
        'idx_hatchery_daily_records_comparable',
      ]),
    );
  });
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
