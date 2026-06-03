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

const _removedTables = [
  'audits',
  'station_samples',
  'sample_records',
  'sample_house_details',
  'sample_machine_details',
  'sample_batch_details',
  'sample_timing_details',
];

const _commonPanelColumns = [
  'id',
  'sessionId',
  'customerId',
  'flockId',
  'hatcheryId',
  'date',
  'breed',
  'flockAgeWeeks',
  'house',
  'setter',
  'hatcher',
  'trolley',
  'tray',
  'position',
  'storagePeriodDays',
  'bmkAgeWeeks',
  'notes',
  'createdAt',
  'updatedAt',
  'syncStatus',
  'lastSyncedAt',
  'syncError',
];

const _legacyPanelIdentityColumns = [
  'mode',
  'scopeType',
  'scopeLabel',
  'sampleIndex',
  'groupKey',
  'groupLabel',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(_resetDatabase);

  tearDown(() async {
    await DatabaseHelper().close();
  });

  test(
    'fresh database creates panel-only tables without legacy audit/sample tables',
    () async {
      final db = await DatabaseHelper().db;
      final tables = await _tableNames(db);

      expect(tables, containsAll(_panelTables));
      for (final table in _removedTables) {
        expect(
          tables,
          isNot(contains(table)),
          reason: '$table must be removed',
        );
      }
      expect(
        tables.where((name) => name.endsWith('_samples')),
        isEmpty,
        reason: 'panel sample child tables are removed in the hard cutover',
      );
    },
  );

  test(
    'panel tables expose common identity, ownership, metadata, and sync columns',
    () async {
      final db = await DatabaseHelper().db;

      for (final table in _panelTables) {
        final columns = await _columnNames(db, table);
        final expectedColumns = _expectedCommonColumnsFor(table);
        expect(columns, containsAll(expectedColumns), reason: table);
        expect(columns, isNot(contains('bmkAgeDays')), reason: table);
        for (final legacyColumn in _legacyPanelIdentityColumns) {
          expect(columns, isNot(contains(legacyColumn)), reason: table);
        }
      }
    },
  );

  test('setter and hatcher tables start hierarchy at machine scope', () async {
    final db = await DatabaseHelper().db;
    final setterColumns = await _columnNames(db, 'setter_optimizing');
    final hatcherColumns = await _columnNames(db, 'hatcher_optimizing');

    expect(setterColumns, contains('setter'));
    expect(setterColumns, isNot(contains('house')));
    expect(setterColumns, isNot(contains('hatcher')));
    expect(setterColumns, isNot(contains('trolley')));
    expect(setterColumns, isNot(contains('tray')));
    expect(setterColumns, isNot(contains('position')));

    expect(hatcherColumns, contains('hatcher'));
    expect(hatcherColumns, isNot(contains('house')));
    expect(hatcherColumns, isNot(contains('setter')));
    expect(hatcherColumns, isNot(contains('trolley')));
    expect(hatcherColumns, isNot(contains('tray')));
    expect(hatcherColumns, isNot(contains('position')));
  });

  test(
    'opening an existing current database drops deprecated BMK age days',
    () async {
      await DatabaseHelper().close();
      final dbPath = p.join(
        await databaseFactory.getDatabasesPath(),
        'hatchaudit.db',
      );
      final existingDb = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 41,
          onCreate: (db, version) async {
            await db.execute('''CREATE TABLE egg_storage (
            id TEXT PRIMARY KEY,
            sessionId TEXT NOT NULL,
            customerId TEXT NOT NULL,
            date TEXT NOT NULL,
            bmkAgeDays INTEGER
          )''');
          },
        ),
      );
      await existingDb.close();

      final db = await DatabaseHelper().db;
      final columns = await _columnNames(db, 'egg_storage');

      expect(columns, isNot(contains('bmkAgeDays')));
      expect(columns, containsAll(['storagePeriodDays', 'bmkAgeWeeks']));
    },
  );

  test(
    'opening an existing current database drops obsolete setter hierarchy columns',
    () async {
      await DatabaseHelper().close();
      final dbPath = p.join(
        await databaseFactory.getDatabasesPath(),
        'hatchaudit.db',
      );
      final existingDb = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 41,
          onCreate: (db, version) async {
            await db.execute('''CREATE TABLE setter_optimizing (
              id TEXT PRIMARY KEY,
              sessionId TEXT NOT NULL,
              customerId TEXT NOT NULL,
              date TEXT NOT NULL,
              house TEXT,
              setter TEXT,
              hatcher TEXT,
              trolley TEXT,
              tray TEXT,
              position TEXT,
              createdAt TEXT NOT NULL,
              updatedAt TEXT NOT NULL,
              syncStatus TEXT NOT NULL DEFAULT 'pending'
            )''');
            await db.execute(
              "CREATE UNIQUE INDEX idx_setter_optimizing_unique_row ON setter_optimizing (sessionId, IFNULL(house, ''), IFNULL(setter, ''), IFNULL(hatcher, ''), IFNULL(trolley, ''), IFNULL(tray, ''), IFNULL(position, ''))",
            );
          },
        ),
      );
      await existingDb.close();

      final db = await DatabaseHelper().db;
      final columns = await _columnNames(db, 'setter_optimizing');

      expect(columns, contains('setter'));
      expect(columns, isNot(contains('house')));
      expect(columns, isNot(contains('hatcher')));
      expect(columns, isNot(contains('trolley')));
      expect(columns, isNot(contains('tray')));
      expect(columns, isNot(contains('position')));
    },
  );

  test('photos are scoped to panel rows instead of legacy audits', () async {
    final db = await DatabaseHelper().db;
    final columns = await _columnNames(db, 'photos');

    expect(
      columns,
      containsAll(['sessionId', 'panelName', 'panelRowId', 'fieldKey']),
    );
    expect(columns, isNot(contains('auditId')));
  });

  test(
    'egg quality table contains consolidated quality and weight columns',
    () async {
      final db = await DatabaseHelper().db;
      final tables = await _tableNames(db);
      final columns = await _columnNames(db, 'egg_quality');

      expect(tables, isNot(contains('egg_weights')));
      expect(
        columns,
        containsAll([
          'uvTrayEggCount',
          'uvCuticleDamageCount',
          'uvCuticleDamagePct',
          'uvWashedCount',
          'uvWashedPct',
          'uvDirtyCount',
          'uvDirtyPct',
          'uvAffectedCount',
          'uvAffectedPct',
          'eggWeightsJson',
          'eggSampleSize',
          'eggAvgWeight',
          'eggUniformityPct',
          'eggCvPct',
          'eggBmkAgeWeeks',
          'eggBmkWeight',
        ]),
      );
      expect(columns, isNot(contains('trayEggCount')));
      expect(columns, isNot(contains('cuticleDamageCount')));
      expect(columns, isNot(contains('washedCount')));
      expect(columns, isNot(contains('dirtyCount')));
      expect(columns, isNot(contains('affectedCount')));
      expect(columns, isNot(contains('affectedPct')));
      expect(columns, isNot(contains('weightsJson')));
      expect(columns, isNot(contains('sampleSize')));
      expect(columns, isNot(contains('avgWeight')));
      expect(columns, isNot(contains('uniformityPct')));
      expect(columns, isNot(contains('cvPct')));
      expect(columns, isNot(contains('bmkWeight')));
      expect(columns, isNot(contains('upsideDownCount')));
      expect(columns, isNot(contains('upsideDownPct')));
    },
  );

  test('egg storage table contains upside-down score columns', () async {
    final db = await DatabaseHelper().db;
    final columns = await _columnNames(db, 'egg_storage');

    expect(columns, containsAll(['upsideDownCount', 'upsideDownPct']));
  });

  test('fresh database creates combined chick quality table', () async {
    final db = await DatabaseHelper().db;
    final tables = await _tableNames(db);
    final columns = await _columnNames(db, 'chick_quality');

    expect(tables, contains('chick_quality'));
    expect(
      tables,
      isNot(
        containsAll(['chick_pasgar', 'chick_yfbm', 'chick_cvt', 'chick_pm']),
      ),
    );
    expect(
      columns,
      containsAll([
        'pasgarSampleSize',
        'pasgarReflexesCount',
        'pasgarFinalScore',
        'yfbmEntriesJson',
        'yfbmEntryCount',
        'yfbmAvgPct',
        'yfbmCvPct',
        'cvtReadingsJson',
        'cvtSampleSize',
        'cvtAvgTemp',
        'cvtCvPct',
        'pmSampleSize',
        'pmCollectionPoint',
        'pmGizzardErosionsCount',
        'pmGizzardErosionsSeverity',
        'pmAirSacCaseationsCount',
        'pmAirSacCaseationsSeverity',
        'pmUrolithiasisCount',
        'pmUrolithiasisSeverity',
        'pmNephritisCount',
        'pmNephritisSeverity',
        'pmGeneralSepticemiaCount',
        'pmGeneralSepticemiaSeverity',
        'pmOtherLesionsJson',
        'culledChicksTotalEggSet',
        'culledChicksAnalysisJson',
        'culledChicksAffectedPct',
        'culledChicksTopCategory',
        'culledChicksTopSubtype',
      ]),
    );
    expect(columns, isNot(contains('sampleSize')));
    expect(columns, isNot(contains('cvPct')));
    for (final column in [
      'pmUnabsorbedYolkCount',
      'pmUnabsorbedYolkSeverity',
      'pmPerihepatitisCount',
      'pmPerihepatitisSeverity',
      'pmPericarditisCount',
      'pmPericarditisSeverity',
      'pmAirsacAcuteCount',
      'pmAirsacAcuteSeverity',
      'pmAirsacChronicCount',
      'pmAirsacChronicSeverity',
      'pmPulmonaryGranulomaCount',
      'pmPulmonaryGranulomaSeverity',
      'pmSwollenJointsCount',
      'pmSwollenJointsSeverity',
      'pmStuntedOrgansCount',
      'pmStuntedOrgansSeverity',
      'pmPulmonaryHemorrhageCount',
      'pmPulmonaryHemorrhageSeverity',
      'pmGaspingPresent',
      'pmGaspingType',
      'pmExposedBrainCount',
      'pmEctopicVisceraCount',
      'pmExtraLegsCount',
      'pmCrossedBeakCount',
      'pmAbsentEyeBothCount',
      'pmAbsentEyeOneCount',
      'pmSmallEyeCount',
      'pmHydrocephalyCount',
      'pmStarGazerCount',
      'pmCurledToesCount',
      'pmShortLegsCount',
      'pmSpinalDeformityCount',
      'pmCardiacAnomalyCount',
      'pmConjoinedCount',
      'pmOtherDeformityCount',
      'pmOtherDeformityText',
    ]) {
      expect(columns, isNot(contains(column)), reason: column);
    }
  });

  test('v36 cutover opens an existing foreign-key legacy database', () async {
    await DatabaseHelper().close();
    final dbPath = p.join(
      await databaseFactory.getDatabasesPath(),
      'hatchaudit.db',
    );
    final legacyDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 35,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('''CREATE TABLE customers (
	            id TEXT PRIMARY KEY,
	            name TEXT
	          )''');
          await db.execute('''CREATE TABLE flocks (
	            id TEXT PRIMARY KEY,
	            customerId TEXT,
	            FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE
	          )''');
          await db.execute('''CREATE TABLE hatcheries (
	            id TEXT PRIMARY KEY,
	            customerId TEXT NOT NULL,
	            name TEXT NOT NULL,
	            FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE
	          )''');
          await db.execute('''CREATE TABLE audit_sessions (
	            id TEXT PRIMARY KEY,
	            customerId TEXT NOT NULL,
	            flockId TEXT NOT NULL,
	            hatcheryId TEXT NOT NULL,
	            date TEXT NOT NULL,
	            FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE,
	            FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE,
	            FOREIGN KEY (hatcheryId) REFERENCES hatcheries(id) ON DELETE CASCADE
	          )''');
        },
      ),
    );
    await legacyDb.close();

    final db = await DatabaseHelper().db;
    final tables = await _tableNames(db);
    final foreignKeys = await db.rawQuery('PRAGMA foreign_keys');

    expect(tables, containsAll(_panelTables));
    expect(tables, isNot(contains('audits')));
    expect(foreignKeys.single.values.single, 1);
  });

  test('debug startup recreates a locally corrupt database', () async {
    await DatabaseHelper().close();
    final dbPath = p.join(
      await databaseFactory.getDatabasesPath(),
      'hatchaudit.db',
    );
    final corruptDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: 35),
    );
    await corruptDb.execute('PRAGMA writable_schema = ON');
    await corruptDb.execute('''
      INSERT INTO sqlite_master(type, name, tbl_name, rootpage, sql)
      VALUES('table', '25', '25', 0, 'CREATE TABLE 25 (')
    ''');
    await corruptDb.close();

    final db = await DatabaseHelper().db;
    final tables = await _tableNames(db);

    expect(tables, containsAll(_panelTables));
    expect(tables, isNot(contains('25')));
  });
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

Set<String> _expectedCommonColumnsFor(String table) {
  final columns = _commonPanelColumns.toSet();
  switch (table) {
    case 'setter_optimizing':
      columns.removeAll(['house', 'hatcher', 'position', 'trolley', 'tray']);
      break;
    case 'hatcher_optimizing':
      columns.removeAll(['house', 'setter', 'position', 'trolley', 'tray']);
      break;
  }
  return columns;
}
