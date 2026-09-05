import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../support/test_database.dart';

/// The v81 migration retires the Cobb500 Slow Feather profile from installs
/// that already imported it.
///
/// Dropping the asset file is not enough on its own: the importer only ever
/// adds profiles, and a device that ran the 2026-08-28 build still holds the
/// rows. Those rows are immutable at the database level, so this proves the
/// migration really can delete them and really does put the guards back —
/// a retirement that left the triggers dropped would silently unlock every
/// other published profile for editing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const retiredKey = 'cobb500_slow_feather_parent_stock_2020_en';
  const uuid = Uuid();

  setUp(() async {
    await useIsolatedAppDatabase();
  });

  tearDown(resetAppDatabase);

  /// Inserts a published profile the way the importer does: as `draft`, with
  /// values, then one final UPDATE to `active`.
  Future<String> publishProfile(Database db, String profileKey) async {
    final now = DateTime.now().toIso8601String();
    final profileId = uuid.v4();
    await db.insert('breeder_benchmark_profiles', {
      'id': profileId,
      'profileKey': profileKey,
      'company': 'Cobb-Vantress',
      'breed': 'Cobb500 Slow Feather',
      'product': 'Parent Stock',
      'guideVersion': 'Breeder Management Supplement (L-011-01-20 EN)',
      'publicationDate': null,
      'sourceUrl': 'https://example.invalid/slow-feather.pdf',
      'effectiveAgeStartDays': 7,
      'effectiveAgeEndDays': 455,
      'lifecycleCoverage': 'rearing,production',
      'state': 'draft',
      'createdAt': now,
      'updatedAt': now,
      'syncStatus': 'synced',
      'lastSyncedAt': now,
    });

    final metric = (await db.query(
      'breeder_metric_definitions',
      columns: ['id'],
      where: 'code = ?',
      whereArgs: ['body_weight_g'],
      limit: 1,
    )).first['id'] as String;

    for (var week = 1; week <= 3; week++) {
      await db.insert('breeder_benchmark_values', {
        'id': uuid.v4(),
        'profileId': profileId,
        'metricId': metric,
        'sex': 'female',
        'ageDays': week * 7,
        'ageWeek': week,
        'productionWeek': null,
        'periodType': 'weekly',
        'targetValue': 100.0 * week,
        'lowerBound': null,
        'upperBound': null,
        'createdAt': now,
        'updatedAt': now,
        'syncStatus': 'synced',
        'lastSyncedAt': now,
      });
    }

    await db.update(
      'breeder_benchmark_profiles',
      {'state': 'active', 'updatedAt': now},
      where: 'id = ?',
      whereArgs: [profileId],
    );
    return profileId;
  }

  Future<int> valueCount(Database db, String profileId) async {
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM breeder_benchmark_values WHERE profileId = ?',
            [profileId],
          ),
        ) ??
        -1;
  }

  test('the current app no longer imports Cobb500 Slow Feather', () async {
    final db = await DatabaseHelper().db;
    final rows = await db.query(
      'breeder_benchmark_profiles',
      where: 'profileKey = ?',
      whereArgs: [retiredKey],
    );
    expect(rows, isEmpty);
  });

  test('v81 deletes an already-imported Slow Feather profile', () async {
    final helper = DatabaseHelper();
    final db = await helper.db;
    final profileId = await publishProfile(db, retiredKey);
    expect(await valueCount(db, profileId), 3);

    await helper.applyV81UpgradeForTest(db);

    expect(
      await db.query(
        'breeder_benchmark_profiles',
        where: 'profileKey = ?',
        whereArgs: [retiredKey],
      ),
      isEmpty,
    );
    expect(await valueCount(db, profileId), 0);
  });

  test('v81 leaves every other published profile immutable', () async {
    final helper = DatabaseHelper();
    final db = await helper.db;
    await publishProfile(db, retiredKey);

    await helper.applyV81UpgradeForTest(db);

    // Ross 308 is imported by the seeds and is still published.
    final ross = (await db.query(
      'breeder_benchmark_profiles',
      columns: ['id'],
      where: 'profileKey = ?',
      whereArgs: ['aviagen_ross308_parent_stock_2021_en'],
      limit: 1,
    )).first['id'] as String;

    await expectLater(
      db.delete(
        'breeder_benchmark_profiles',
        where: 'id = ?',
        whereArgs: [ross],
      ),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.delete(
        'breeder_benchmark_values',
        where: 'profileId = ?',
        whereArgs: [ross],
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('v81 is a no-op when the profile was never imported', () async {
    final helper = DatabaseHelper();
    final db = await helper.db;
    final before = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM breeder_benchmark_values'),
    );

    await helper.applyV81UpgradeForTest(db);

    expect(
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM breeder_benchmark_values'),
      ),
      before,
    );
  });
}
