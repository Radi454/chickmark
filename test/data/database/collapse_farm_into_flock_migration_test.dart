import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

/// v68 collapses Farm into Flock: `houses.farmId` becomes `houses.flockId`
/// (carrying its own opening female/male bird counts), `flocks.farmId` is
/// removed, and `farms`/`flock_placements` are dropped outright. Because this
/// reshapes two v41-baseline-adjacent tables in place (not just adding a
/// column), the whole-table parity net in `schema_parity_test.dart` covers
/// the *shape* but not the backfill values — this suite rebuilds the genuine
/// pre-v68 tables directly and replays `applyV68UpgradeForTest` to prove the
/// backfill itself, the same pattern `bmk_operational_sync_migration_test.dart`
/// uses for v58.
const _preV68FlocksDdl = '''
CREATE TABLE flocks (
  id TEXT PRIMARY KEY,
  customerId TEXT,
  flockId TEXT,
  breed TEXT,
  entryDate TEXT,
  farmId TEXT,
  sectorKey TEXT,
  sexProfile TEXT NOT NULL DEFAULT 'as_hatched',
  targetProfileId TEXT,
  productionPhase TEXT,
  isAgeEstimated INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active',
  depletionAgeWeeks INTEGER NOT NULL DEFAULT 65,
  soldAt TEXT,
  updatedAt TEXT,
  syncStatus TEXT NOT NULL DEFAULT 'pending',
  dirtyAt TEXT,
  lastSyncedAt TEXT,
  syncError TEXT
)''';

const _preV68FarmsDdl = '''
CREATE TABLE farms (
  id TEXT PRIMARY KEY,
  customerId TEXT NOT NULL,
  sectorKey TEXT NOT NULL,
  name TEXT NOT NULL,
  isActive INTEGER NOT NULL DEFAULT 1
)''';

const _preV68HousesDdl = '''
CREATE TABLE houses (
  id TEXT PRIMARY KEY,
  farmId TEXT NOT NULL,
  name TEXT NOT NULL,
  code TEXT,
  capacity INTEGER,
  notes TEXT,
  isActive INTEGER NOT NULL DEFAULT 1,
  createdBy TEXT,
  createdAt TEXT,
  updatedAt TEXT,
  syncStatus TEXT NOT NULL DEFAULT 'pending',
  dirtyAt TEXT,
  lastSyncedAt TEXT,
  syncError TEXT
)''';

const _preV68FlockPlacementsDdl = '''
CREATE TABLE flock_placements (
  id TEXT PRIMARY KEY,
  flockId TEXT NOT NULL,
  houseId TEXT NOT NULL,
  placedBirds INTEGER NOT NULL,
  placedAt TEXT NOT NULL,
  endedAt TEXT,
  status TEXT NOT NULL DEFAULT 'active'
)''';

Future<void> _rebuildPreV68Schema(Database db) async {
  await db.execute('PRAGMA foreign_keys = OFF');
  for (final table in const [
    'houses',
    'flocks',
    'farms',
    'flock_placements',
  ]) {
    await db.execute('DROP TABLE IF EXISTS $table');
  }
  await db.execute(_preV68FlocksDdl);
  await db.execute(_preV68FarmsDdl);
  await db.execute(_preV68HousesDdl);
  await db.execute(_preV68FlockPlacementsDdl);
}

Future<Set<String>> _columnsOf(Database db, String table) async {
  final info = await db.rawQuery("PRAGMA table_info('$table')");
  return info.map((row) => row['name']! as String).toSet();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  tearDown(resetAppDatabase);

  test(
    'v68 backfills a house onto its active-placement flock with opening '
    'counts, and deletes houses that cannot be resolved',
    () async {
      final db = await DatabaseHelper().db;
      await _rebuildPreV68Schema(db);

      expect(
        await _columnsOf(db, 'houses'),
        contains('farmId'),
        reason:
            'sanity check: the fixture must really be pre-v68, otherwise '
            'this test would vacuously pass',
      );

      await db.insert('customers', {
        'id': 'customer-1',
        'name': 'Integrated Poultry Co.',
      });

      // A female breeder flock with a house that has a genuine active
      // placement: this house must survive with the placement's bird count
      // assigned entirely to females (the source data never split by sex).
      await db.insert('flocks', {
        'id': 'flock-female',
        'customerId': 'customer-1',
        'flockId': 'BR-2026-01',
        'breed': 'Ross 308',
        'entryDate': '2026-07-01T00:00:00.000Z',
        'farmId': 'farm-1',
        'sectorKey': 'breeder',
        'sexProfile': 'as_hatched',
      });
      await db.insert('farms', {
        'id': 'farm-1',
        'customerId': 'customer-1',
        'sectorKey': 'breeder',
        'name': 'Farm 1',
      });
      await db.insert('houses', {
        'id': 'house-resolved',
        'farmId': 'farm-1',
        'name': 'House 1',
        'code': 'H1',
        'capacity': 12000,
        'isActive': 1,
        'syncStatus': 'synced',
      });
      await db.insert('flock_placements', {
        'id': 'placement-1',
        'flockId': 'flock-female',
        'houseId': 'house-resolved',
        'placedBirds': 10500,
        'placedAt': '2026-07-01T00:00:00.000Z',
        'status': 'active',
      });

      // A male flock's house: the placement's birds must land on
      // openingMales instead of openingFemales.
      await db.insert('flocks', {
        'id': 'flock-male',
        'customerId': 'customer-1',
        'flockId': 'BR-2026-02',
        'breed': 'Ross 308',
        'entryDate': '2026-07-05T00:00:00.000Z',
        'farmId': 'farm-1',
        'sectorKey': 'breeder',
        'sexProfile': 'male',
      });
      await db.insert('houses', {
        'id': 'house-male',
        'farmId': 'farm-1',
        'name': 'House Male',
        'isActive': 1,
        'syncStatus': 'synced',
      });
      await db.insert('flock_placements', {
        'id': 'placement-2',
        'flockId': 'flock-male',
        'houseId': 'house-male',
        'placedBirds': 1200,
        'placedAt': '2026-07-05T00:00:00.000Z',
        'status': 'active',
      });

      // Orphan #1: a house with no placement row at all.
      await db.insert('houses', {
        'id': 'house-orphan-no-placement',
        'farmId': 'farm-1',
        'name': 'House Orphan',
        'isActive': 1,
        'syncStatus': 'synced',
      });

      // Orphan #2: a house whose only placement already ended (not active),
      // so it cannot be resolved to a current flock.
      await db.insert('houses', {
        'id': 'house-orphan-ended',
        'farmId': 'farm-1',
        'name': 'House Ended',
        'isActive': 1,
        'syncStatus': 'synced',
      });
      await db.insert('flock_placements', {
        'id': 'placement-3',
        'flockId': 'flock-female',
        'houseId': 'house-orphan-ended',
        'placedBirds': 8000,
        'placedAt': '2026-01-01T00:00:00.000Z',
        'endedAt': '2026-06-01T00:00:00.000Z',
        'status': 'ended',
      });

      await DatabaseHelper().applyV68UpgradeForTest(db);

      // Shape: farms and flock_placements are gone, flocks.farmId is gone,
      // houses has flockId + opening counts instead of farmId.
      final tables = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      )).map((row) => row['name']! as String).toSet();
      expect(tables, isNot(contains('farms')));
      expect(tables, isNot(contains('flock_placements')));
      expect(await _columnsOf(db, 'flocks'), isNot(contains('farmId')));
      final houseColumns = await _columnsOf(db, 'houses');
      expect(houseColumns, isNot(contains('farmId')));
      expect(
        houseColumns,
        containsAll(['flockId', 'openingFemales', 'openingMales']),
      );

      // The resolved houses land on the right flock with the right opening
      // counts, split by the owning flock's sex profile.
      final resolved = await db.query(
        'houses',
        where: 'id = ?',
        whereArgs: ['house-resolved'],
      );
      expect(resolved.single['flockId'], 'flock-female');
      expect(resolved.single['openingFemales'], 10500);
      expect(resolved.single['openingMales'], 0);
      // Untouched carried-over columns survive the rebuild.
      expect(resolved.single['code'], 'H1');
      expect(resolved.single['capacity'], 12000);

      final maleHouse = await db.query(
        'houses',
        where: 'id = ?',
        whereArgs: ['house-male'],
      );
      expect(maleHouse.single['flockId'], 'flock-male');
      expect(maleHouse.single['openingFemales'], 0);
      expect(maleHouse.single['openingMales'], 1200);

      // Orphan houses (no placement, or only an ended one) are deleted
      // rather than assigned an invented flock.
      final remainingIds = (await db.query(
        'houses',
        columns: ['id'],
      )).map((row) => row['id']).toSet();
      expect(remainingIds, {'house-resolved', 'house-male'});
      expect(remainingIds, isNot(contains('house-orphan-no-placement')));
      expect(remainingIds, isNot(contains('house-orphan-ended')));

      // The rebuilt houses table still enforces per-flock uniqueness on
      // name and code.
      final violations = await db.rawQuery('PRAGMA foreign_key_check(houses)');
      expect(violations, isEmpty);
    },
  );
}
