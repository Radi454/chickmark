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
