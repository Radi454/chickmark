import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/database/seeds/breeder_benchmark_seeds.dart';
import 'package:sqflite/sqflite.dart';

import '../../support/test_database.dart';

/// Verification fixture for the Ross 308 Parent Stock 2021 benchmark
/// profile (breeder-flock-performance ticket 03): row count, metric
/// coverage, unit agreement, hand-checked spot values transcribed directly
/// from the published PDF, monotonic cumulative series, importer
/// idempotence, and published-version immutability.
///
/// Spot values are hand-checked against
/// Ross308-ParentStock-PerformanceObjectives-2021-EN.pdf (Aviagen, 2021):
/// Female In-Season Body Weight table (p.4), Male Body Weight table (p.7),
/// Weekly Egg Production table (p.8), Weekly Egg Weight and Egg Mass table
/// (p.10), and the Performance Summary (p.3).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await useIsolatedAppDatabase();
  });

  tearDown(resetAppDatabase);

  Future<Map<String, dynamic>> profileRow(Database db) async {
    final rows = await db.query(
      'breeder_benchmark_profiles',
      where: 'profileKey = ?',
      whereArgs: ['aviagen_ross308_parent_stock_2021_en'],
      limit: 1,
    );
    expect(rows, isNotEmpty, reason: 'Ross 308 profile must be imported');
    return rows.first;
  }

  Future<Map<String, String>> metricIdsByCode(Database db) async {
    final rows = await db.query('breeder_metric_definitions');
    return {for (final r in rows) r['code'] as String: r['id'] as String};
  }

  Future<double?> spotValue(
    Database db,
    String profileId,
    String metricId,
    String sex,
    int ageDays,
  ) async {
    final rows = await db.query(
      'breeder_benchmark_values',
      where: 'profileId = ? AND metricId = ? AND sex = ? AND ageDays = ?',
      whereArgs: [profileId, metricId, sex, ageDays],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['targetValue'] as num?)?.toDouble();
  }

  test('imports the Ross 308 profile as active with 22 metric definitions', () async {
    final db = await DatabaseHelper().db;
    final profile = await profileRow(db);
    expect(profile['state'], 'active');
    expect(profile['company'], 'Aviagen');
    expect(profile['breed'], 'Ross 308');

    // 18 metrics are published by the Aviagen guides; the remaining 4
    // (fertility weekly/cumulative, cumulative flock mortality, chick
    // weight) exist only because the Cobb500 supplements publish them.
    // Definitions are shared across every profile, so the table holds all
    // 22 regardless of which profile is being inspected.
    final metricCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM breeder_metric_definitions'),
    );
    expect(metricCount, 22);
  });

  test('profile has exactly the expected row count and full metric coverage', () async {
    final db = await DatabaseHelper().db;
    final profile = await profileRow(db);
    final profileId = profile['id'] as String;

    final valueCount = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM breeder_benchmark_values WHERE profileId = ?',
        [profileId],
      ),
    );
    expect(valueCount, 812);

    // Every metric definition the profile claims to cover must have at
    // least one value row under this profile, and every value's unit must
    // agree with its metric definition (join integrity — a dangling
    // metricId would silently mean "no unit").
    final coverage = await db.rawQuery('''
      SELECT d.code, d.unit, COUNT(v.id) AS rowCount
      FROM breeder_metric_definitions d
      JOIN breeder_benchmark_values v
        ON v.metricId = d.id AND v.profileId = ?
      GROUP BY d.id
    ''', [profileId]);
    expect(coverage, hasLength(18));
    for (final row in coverage) {
      expect((row['rowCount'] as int) > 0, isTrue);
      expect(row['unit'], isNotNull);
    }

    // The 4 Cobb-only metric definitions are deliberately uncovered here:
    // no Aviagen document publishes fertility, cumulative flock mortality,
    // or chick weight, and nothing is inferred to fill them in.
    final covered = {for (final row in coverage) row['code'] as String};
    expect(
      covered.intersection({
        'fertility_weekly_pct',
        'fertility_cumulative_pct',
        'flock_mortality_cumulative_pct',
        'chick_weight_g',
      }),
      isEmpty,
    );
  });

  test('hand-checked spot values match the published PDF exactly', () async {
    final db = await DatabaseHelper().db;
    final profile = await profileRow(db);
    final profileId = profile['id'] as String;
    final metrics = await metricIdsByCode(db);

    // Female body weight at 175 days (25 weeks): 2970 g.
    expect(
      await spotValue(db, profileId, metrics['body_weight_g']!, 'female', 175),
      2970,
    );
    // Male body weight at 175 days: 3825 g.
    expect(
      await spotValue(db, profileId, metrics['body_weight_g']!, 'male', 175),
      3825,
    );
    // Female body weight at depletion, 448 days: 4085 g.
    expect(
      await spotValue(db, profileId, metrics['body_weight_g']!, 'female', 448),
      4085,
    );
    // Hen-housed production peaks at 86.9% (week 7, day 217).
    expect(
      await spotValue(
        db,
        profileId,
        metrics['hen_housed_production_pct']!,
        'female',
        217,
      ),
      86.9,
    );
    // Egg weight at week 1 (day 175): 50.4 g.
    expect(
      await spotValue(db, profileId, metrics['egg_weight_g']!, 'female', 175),
      50.4,
    );
    // Cumulative eggs per hen-housed at week 40 (day 448): 185.2 — matches
    // the "Total Eggs (HHA)" figure on the Performance Summary page.
    expect(
      await spotValue(
        db,
        profileId,
        metrics['eggs_per_hen_housed_cumulative']!,
        'female',
        448,
      ),
      185.2,
    );
    // Cumulative hatchability at week 40: 85.3% — matches the summary
    // "Hatchability %" figure.
    expect(
      await spotValue(
        db,
        profileId,
        metrics['hatchability_cumulative_pct']!,
        'female',
        448,
      ),
      85.3,
    );
    // Liveability (laying period): 92% exact, from the Performance Summary.
    expect(
      await spotValue(
        db,
        profileId,
        metrics['liveability_laying_pct']!,
        'female',
        448,
      ),
      92,
    );
    // Daily feed intake, female, at day 175: 127 g/bird/day.
    expect(
      await spotValue(
        db,
        profileId,
        metrics['daily_feed_intake_g']!,
        'female',
        175,
      ),
      127,
    );
    // Daily feed intake, male, at day 175: 123 g/bird/day.
    expect(
      await spotValue(
        db,
        profileId,
        metrics['daily_feed_intake_g']!,
        'male',
        175,
      ),
      123,
    );
  });

  test('cumulative count series never decrease with age', () async {
    final db = await DatabaseHelper().db;
    final profile = await profileRow(db);
    final profileId = profile['id'] as String;
    final metrics = await metricIdsByCode(db);

    for (final code in [
      'eggs_per_hen_housed_cumulative',
      'hatching_eggs_per_hen_housed_cumulative',
      'chicks_per_hen_housed_cumulative',
    ]) {
      final rows = await db.query(
        'breeder_benchmark_values',
        where: 'profileId = ? AND metricId = ?',
        whereArgs: [profileId, metrics[code]],
        orderBy: 'ageDays ASC',
      );
      expect(rows, isNotEmpty, reason: '$code has no rows');
      double previous = -1;
      for (final row in rows) {
        final value = (row['targetValue'] as num).toDouble();
        expect(
          value >= previous,
          isTrue,
          reason: '$code decreased at ageDays=${row['ageDays']} '
              '($value < $previous)',
        );
        previous = value;
      }
    }
  });

  test('re-running the importer does not duplicate rows', () async {
    final db = await DatabaseHelper().db;
    final before = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM breeder_benchmark_values'),
    );
    final beforeProfiles = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM breeder_benchmark_profiles'),
    );
    final beforeMetrics = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM breeder_metric_definitions'),
    );

    await importBreederBenchmarks(db);
    await importBreederBenchmarks(db);

    final after = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM breeder_benchmark_values'),
    );
    final afterProfiles = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM breeder_benchmark_profiles'),
    );
    final afterMetrics = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM breeder_metric_definitions'),
    );

    expect(after, before);
    expect(afterProfiles, beforeProfiles);
    expect(afterMetrics, beforeMetrics);
  });

  test('a published profile cannot be updated or deleted', () async {
    final db = await DatabaseHelper().db;
    final profile = await profileRow(db);
    expect(profile['state'], 'active');

    await expectLater(
      db.update(
        'breeder_benchmark_profiles',
        {'guideVersion': 'tampered'},
        where: 'id = ?',
        whereArgs: [profile['id']],
      ),
      throwsA(isA<DatabaseException>()),
    );

    await expectLater(
      db.delete(
        'breeder_benchmark_profiles',
        where: 'id = ?',
        whereArgs: [profile['id']],
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('values of a published profile cannot be updated, deleted, or inserted into', () async {
    final db = await DatabaseHelper().db;
    final profile = await profileRow(db);
    final profileId = profile['id'] as String;
    final existingValue = (await db.query(
      'breeder_benchmark_values',
      where: 'profileId = ?',
      whereArgs: [profileId],
      limit: 1,
    )).first;
    final metrics = await metricIdsByCode(db);

    await expectLater(
      db.update(
        'breeder_benchmark_values',
        {'targetValue': 9999},
        where: 'id = ?',
        whereArgs: [existingValue['id']],
      ),
      throwsA(isA<DatabaseException>()),
    );

    await expectLater(
      db.delete(
        'breeder_benchmark_values',
        where: 'id = ?',
        whereArgs: [existingValue['id']],
      ),
      throwsA(isA<DatabaseException>()),
    );

    await expectLater(
      db.insert('breeder_benchmark_values', {
        'id': 'tamper-attempt',
        'profileId': profileId,
        'metricId': metrics['body_weight_g'],
        'sex': 'female',
        'ageDays': 999999,
        'ageWeek': 1,
        'periodType': 'weekly',
        'targetValue': 1,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      }),
      throwsA(isA<DatabaseException>()),
    );
  });
}
