import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

/// v58 is the first migration that ALTERs a v41-baseline table
/// (`bmk_operational_standards` gains the four device-local sync columns), so
/// the whole-table parity net in `schema_parity_test.dart` structurally cannot
/// cover it — see the soundness limitation documented in
/// `migration_fixtures.dart`. This suite covers it directly instead.
///
/// Like the parity test, it calls `applyV58UpgradeForTest` directly rather than
/// reopening through `DatabaseHelper().db`: `onOpen` runs
/// `_surgicalSchemaRepair`, which would recreate/repair the table and paper
/// over exactly the regressions this test exists to catch.
const _preV58Ddl = '''
CREATE TABLE bmk_operational_standards (
  id TEXT PRIMARY KEY,
  hatcheryId TEXT,
  stationKey TEXT NOT NULL,
  sectorKey TEXT NOT NULL,
  metricKey TEXT NOT NULL,
  metricLabel TEXT NOT NULL,
  unit TEXT DEFAULT '',
  minValue REAL,
  maxValue REAL,
  targetValue REAL,
  source TEXT,
  sourceUrl TEXT,
  sourcePhotoPath TEXT,
  sourcePhotoRemotePath TEXT,
  notes TEXT,
  sortOrder INTEGER NOT NULL DEFAULT 0,
  updatedAt TEXT
)''';

Map<String, Object?> _row({
  required String id,
  String? hatcheryId,
  String? updatedAt,
}) => {
  'id': id,
  'hatcheryId': hatcheryId,
  'stationKey': 'global',
  'sectorKey': 'uniformity',
  'metricKey': id.split('-').last,
  'metricLabel': 'Metric $id',
  'unit': '%',
  'maxValue': 8.0,
  'sortOrder': 100,
  'updatedAt': updatedAt,
};

Future<Set<String>> _columnsOf(Database db) async {
  final info = await db.rawQuery(
    "PRAGMA table_info('bmk_operational_standards')",
  );
  return info.map((row) => row['name']! as String).toSet();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  tearDown(resetAppDatabase);

  test(
    'v58 upgrade adds sync columns and keeps pre-existing user edits pushable',
    () async {
      final db = await DatabaseHelper().db;

      // Rebuild the table in its genuine pre-v58 shape (no sync columns).
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute('DROP TABLE IF EXISTS bmk_operational_standards');
      await db.execute(_preV58Ddl);

      expect(
        await _columnsOf(db),
        isNot(contains('syncStatus')),
        reason:
            'sanity check: the fixture must really be pre-v58, otherwise this '
            'test would vacuously pass',
      );

      // A pristine seed row: seeds in kBmkOperationalStandardSeeds carry no
      // updatedAt, and _backfillOperationalBmkSeedSources never writes one.
      await db.insert(
        'bmk_operational_standards',
        _row(id: 'global-cv_alert'),
      );
      // A user-edited GLOBAL row: same id shape as the seed, but
      // BmkRepository.upsertOperationalStandard stamped updatedAt.
      await db.insert(
        'bmk_operational_standards',
        _row(id: 'global-co2_max', updatedAt: '2026-05-01T10:00:00.000'),
      );
      // A user-created hatchery override: user-created by definition, since
      // every seed row is global.
      await db.insert(
        'bmk_operational_standards',
        _row(
          id: 'hatchery-1-cv_alert',
          hatcheryId: 'hatchery-1',
          updatedAt: '2026-05-02T10:00:00.000',
        ),
      );

      await DatabaseHelper().applyV58UpgradeForTest(db);

      expect(
        await _columnsOf(db),
        containsAll(<String>[
          'syncStatus',
          'dirtyAt',
          'lastSyncedAt',
          'syncError',
        ]),
      );

      final rows = await db.query(
        'bmk_operational_standards',
        columns: ['id', 'syncStatus', 'dirtyAt'],
        orderBy: 'id ASC',
      );
      final statusById = {
        for (final row in rows) row['id'] as String: row['syncStatus'],
      };
      final dirtyAtById = {
        for (final row in rows) row['id'] as String: row['dirtyAt'],
      };

      // Seed rows already exist in the cloud: they must not look dirty.
      expect(statusById['global-cv_alert'], 'synced');
      expect(dirtyAtById['global-cv_alert'], isNull);

      // Pre-existing user edits predate this table joining the sync path.
      // Stamping them 'synced' would drop them from every future push.
      expect(statusById['global-co2_max'], 'pending');
      expect(dirtyAtById['global-co2_max'], isNotNull);
      expect(statusById['hatchery-1-cv_alert'], 'pending');
      expect(dirtyAtById['hatchery-1-cv_alert'], isNotNull);
    },
  );

  test('v58 upgrade is idempotent and does not re-dirty synced seed rows',
      () async {
    final db = await DatabaseHelper().db;
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.execute('DROP TABLE IF EXISTS bmk_operational_standards');
    await db.execute(_preV58Ddl);
    await db.insert('bmk_operational_standards', _row(id: 'global-cv_alert'));

    await DatabaseHelper().applyV58UpgradeForTest(db);
    await DatabaseHelper().applyV58UpgradeForTest(db);

    final rows = await db.query('bmk_operational_standards');
    expect(rows.single['syncStatus'], 'synced');
  });
}
