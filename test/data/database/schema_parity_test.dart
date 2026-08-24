import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';
import 'migration_fixtures.dart';

/// Normalized schema: table -> sorted list of "name type notnull dflt pk"
/// plus index names per table. Whitespace/case differences in CREATE
/// statements are irrelevant; PRAGMA output is canonical.
Future<Map<String, Object>> normalizedSchema(Database db) async {
  final tables = (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  )).map((r) => r['name'] as String).toList();
  final result = <String, Object>{};
  for (final table in tables) {
    final cols =
        (await db.rawQuery('PRAGMA table_info("$table")'))
            .map(
              (c) =>
                  '${c['name']} ${(c['type'] as String).toUpperCase()} '
                  'nn=${c['notnull']} dflt=${c['dflt_value']} pk=${c['pk']}',
            )
            .toList()
          ..sort();
    final indexes =
        (await db.rawQuery('PRAGMA index_list("$table")'))
            .map((i) => i['name'] as String)
            .where((n) => !n.startsWith('sqlite_autoindex'))
            .toList()
          ..sort();
    result[table] = {'columns': cols, 'indexes': indexes};
  }
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  tearDown(resetAppDatabase);

  test(
    'v41-baseline database upgraded through v62 matches a fresh v62 create',
    () async {
      // Fresh v62: DatabaseHelper's real _onCreate path, on a database file
      // that has never existed before.
      final freshDb = await DatabaseHelper().db;
      final freshSchema = await normalizedSchema(freshDb);

      // Turn that same on-disk database into a v41-style baseline in place:
      // every table introduced by a v46+ migration is dropped. Every kept
      // table's DDL is still the genuine production definition, since it
      // was never dropped or recreated.
      final dropped = await dropTablesIntroducedAfterV41(freshDb);
      expect(
        dropped,
        isNotEmpty,
        reason:
            'sanity check: the v41 baseline must actually differ from a '
            'fresh v62 database, otherwise this test would vacuously pass',
      );

      // Replay the real v46..v62 handler chain directly via the
      // @visibleForTesting hooks, in the exact order
      // DatabaseHelper._onUpgrade invokes them for any oldVersion in
      // [41, 45] (every "oldVersion < X" guard is true for oldVersion=41).
      // This deliberately bypasses DatabaseHelper().db/onOpen: onOpen runs
      // _surgicalSchemaRepair, which idempotently recreates missing
      // critical tables and would silently paper over exactly the kind of
      // chain regression this test exists to catch.
      final helper = DatabaseHelper();
      await helper.applyV46UpgradeForTest(freshDb);
      await helper.applyV47UpgradeForTest(freshDb);
      await helper.applyV48UpgradeForTest(freshDb);
      await helper.applyV51UpgradeForTest(freshDb);
      await helper.applyV52UpgradeForTest(freshDb);
      await helper.applyV53UpgradeForTest(freshDb);
      await helper.applyV54UpgradeForTest(freshDb);
      await helper.applyV55UpgradeForTest(freshDb);
      await helper.applyV56UpgradeForTest(freshDb);
      await helper.applyV57UpgradeForTest(freshDb);
      await helper.applyV58UpgradeForTest(freshDb);
      await helper.applyV59UpgradeForTest(freshDb);
      await helper.applyV60UpgradeForTest(freshDb);
      await helper.applyV61UpgradeForTest(freshDb);
      await helper.applyV62UpgradeForTest(freshDb);
      await helper.applyV63UpgradeForTest(freshDb);

      final upgradedSchema = await normalizedSchema(freshDb);

      expect(
        upgradedSchema.keys.toSet(),
        freshSchema.keys.toSet(),
        reason: 'table sets diverge between fresh create and upgrade chain',
      );
      for (final table in freshSchema.keys) {
        expect(
          upgradedSchema[table],
          freshSchema[table],
          reason: 'schema divergence in table "$table"',
        );
      }
    },
  );
}
