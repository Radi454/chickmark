import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

/// Covers the schema-level half of Task A3: `egg_quality` must never carry
/// `idx_egg_quality_unique_row`, on a fresh database or after upgrading a
/// database that still has the index from before v61. Other panel tables
/// keep their hierarchy unique index in both cases.
///
/// `test/data/repositories/panel_sample_identity_test.dart` covers the
/// repository's id-first upsert path, but (as flagged in the A3 report) it
/// cannot be made to fail by reverting the schema change, because its raw
/// `CREATE TABLE` never carries the production unique index that the
/// hierarchy-merge path depends on for a conflict to occur. This file is the
/// load-bearing regression coverage for the schema change itself.
Future<Set<String>> _indexNamesForTable(
  DatabaseHelper helper,
  String tableName,
) async {
  final db = await helper.db;
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = ?",
    [tableName],
  );
  return rows.map((row) => row['name'] as String).toSet();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
  });

  tearDown(resetAppDatabase);

  test(
    'fresh database omits the hierarchy unique index for egg_quality but '
    'keeps it for other panels',
    () async {
      await useIsolatedAppDatabase();
      final helper = DatabaseHelper();

      final eggQualityIndexes = await _indexNamesForTable(
        helper,
        'egg_quality',
      );
      final chickQualityIndexes = await _indexNamesForTable(
        helper,
        'chick_quality',
      );

      expect(
        eggQualityIndexes,
        isNot(contains('idx_egg_quality_unique_row')),
        reason: 'egg_quality is id-keyed as of v61 and must not carry the '
            'hierarchy unique index',
      );
      expect(
        chickQualityIndexes,
        contains('idx_chick_quality_unique_row'),
        reason: 'chick_quality still resolves identity by hierarchy and '
            'must keep its unique index',
      );
    },
  );

  test(
    'opening a pre-v61 database that still has the egg_quality unique index '
    'drops it, while another panel keeps its index',
    () async {
      await useIsolatedAppDatabase();
      await DatabaseHelper().close();
      final dbPath = p.join(
        await databaseFactory.getDatabasesPath(),
        'hatchaudit.db',
      );

      // Simulate a database left over from before v61: egg_quality and
      // chick_quality both still carry the hierarchy unique index that A3
      // removes for egg_quality only.
      final legacyDb = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 61,
          onCreate: (db, version) async {
            for (final tableName in ['egg_quality', 'chick_quality']) {
              await db.execute('''CREATE TABLE $tableName (
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
                'CREATE UNIQUE INDEX idx_${tableName}_unique_row ON '
                "$tableName (sessionId, IFNULL(house, ''), "
                "IFNULL(setter, ''), IFNULL(hatcher, ''), "
                "IFNULL(trolley, ''), IFNULL(tray, ''), "
                "IFNULL(position, ''))",
              );
            }
          },
        ),
      );
      await legacyDb.close();

      // Opening through the app's DatabaseHelper runs the real onOpen chain
      // (surgical repair, then _dropPanelUniqueRowIndexes /
      // _ensurePanelUniqueRowIndexes), which is what A3 changed.
      final helper = DatabaseHelper();
      await helper.db;

      final eggQualityIndexes = await _indexNamesForTable(
        helper,
        'egg_quality',
      );
      final chickQualityIndexes = await _indexNamesForTable(
        helper,
        'chick_quality',
      );

      expect(
        eggQualityIndexes,
        isNot(contains('idx_egg_quality_unique_row')),
        reason: 'a pre-v61 egg_quality unique index must be dropped on open '
            'and never recreated',
      );
      expect(
        chickQualityIndexes,
        contains('idx_chick_quality_unique_row'),
        reason: 'chick_quality keeps its unique index across the same open',
      );
    },
  );
}
