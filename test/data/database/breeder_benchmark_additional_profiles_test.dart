import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:sqflite/sqflite.dart';

import '../../support/test_database.dart';

/// Verification fixture for the three breeder lines added alongside Ross 308:
/// Arbor Acres Plus, Indian River, Hubbard Conventional (EDGE), and Cobb500
/// Fast Feather. (Cobb500 Slow Feather was imported alongside Fast Feather
/// and retired by the v81 migration — the flock the app is used against runs
/// the Fast Feather line.)
///
/// Spot values below are hand-checked against the published documents:
/// Aviagen Arbor Acres Plus and Indian River Parent Stock Performance
/// Objectives 2021 EN; Hubbard Parent Stock Performance Objectives
/// V-2025-06 (EDGE); and the Cobb500 Fast Feather Breeder Management
/// Supplement plus the Cobb Male Management Supplement. Nothing here is
/// derived from the asset files themselves — every figure was read off the
/// source PDF (or its published summary box) first.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await useIsolatedAppDatabase();
  });

  tearDown(resetAppDatabase);

  Future<String> profileId(Database db, String profileKey) async {
    final rows = await db.query(
      'breeder_benchmark_profiles',
      where: 'profileKey = ?',
      whereArgs: [profileKey],
      limit: 1,
    );
    expect(rows, isNotEmpty, reason: '$profileKey must be imported');
    expect(rows.first['state'], 'active');
    return rows.first['id'] as String;
  }

  Future<Map<String, String>> metricIdsByCode(Database db) async {
    final rows = await db.query('breeder_metric_definitions');
    return {for (final r in rows) r['code'] as String: r['id'] as String};
  }

  Future<double?> spot(
    Database db,
    String profile,
    String metricId,
    String sex,
    int ageDays,
  ) async {
    final rows = await db.query(
      'breeder_benchmark_values',
      where: 'profileId = ? AND metricId = ? AND sex = ? AND ageDays = ?',
      whereArgs: [profile, metricId, sex, ageDays],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['targetValue'] as num?)?.toDouble();
  }

  const rowCounts = <String, int>{
    'aviagen_ross308_parent_stock_2021_en': 812,
    'aviagen_arboracres_plus_parent_stock_2021_en': 812,
    'aviagen_indianriver_parent_stock_2021_en': 812,
    'hubbard_conventional_edge_parent_stock_2025_en': 526,
    'cobb500_fast_feather_parent_stock_2020_en': 803,
  };

  test('all five official profiles import with their exact row counts', () async {
    final db = await DatabaseHelper().db;

    final profileCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM breeder_benchmark_profiles'),
    );
    expect(profileCount, rowCounts.length);

    for (final entry in rowCounts.entries) {
      final id = await profileId(db, entry.key);
      final count = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM breeder_benchmark_values WHERE profileId = ?',
          [id],
        ),
      );
      expect(count, entry.value, reason: '${entry.key} row count');
    }
  });

  test('every value row joins a metric definition and a sane age', () async {
    final db = await DatabaseHelper().db;

    // A dangling metricId would silently mean "no unit" on screen.
    final orphans = Sqflite.firstIntValue(
      await db.rawQuery('''
        SELECT COUNT(*) FROM breeder_benchmark_values v
        LEFT JOIN breeder_metric_definitions d ON d.id = v.metricId
        WHERE d.id IS NULL
      '''),
    );
    expect(orphans, 0);

    final badAges = Sqflite.firstIntValue(
      await db.rawQuery('''
        SELECT COUNT(*) FROM breeder_benchmark_values
        WHERE ageDays <> ageWeek * 7
           OR (targetValue IS NOT NULL AND targetValue < 0)
      '''),
    );
    expect(badAges, 0);
  });

  test('cumulative count series never decrease in any profile', () async {
    final db = await DatabaseHelper().db;
    final metrics = await metricIdsByCode(db);

    // Cumulative *counts* only. Cumulative percentages (hatchability,
    // fertility) legitimately decline as a flock ages.
    const countSeries = [
      'eggs_per_hen_housed_cumulative',
      'hatching_eggs_per_hen_housed_cumulative',
      'chicks_per_hen_housed_cumulative',
    ];

    for (final key in rowCounts.keys) {
      final id = await profileId(db, key);
      for (final code in countSeries) {
        final rows = await db.query(
          'breeder_benchmark_values',
          where: 'profileId = ? AND metricId = ?',
          whereArgs: [id, metrics[code]],
          orderBy: 'ageDays ASC',
        );
        if (rows.isEmpty) continue; // not every guide publishes every series
        double previous = -1;
        for (final row in rows) {
          final value = (row['targetValue'] as num).toDouble();
          expect(
            value >= previous,
            isTrue,
            reason: '$key/$code decreased at ageDays=${row['ageDays']}',
          );
          previous = value;
        }
      }
    }
  });

  test('Arbor Acres Plus spot values match the published PDF', () async {
    final db = await DatabaseHelper().db;
    final id = await profileId(db, 'aviagen_arboracres_plus_parent_stock_2021_en');
    final m = await metricIdsByCode(db);

    // Female body weight at 175 days (week 25), page 4.
    expect(await spot(db, id, m['body_weight_g']!, 'female', 175), 2970);
    // Male body weight at depletion (day 448), page 7.
    expect(await spot(db, id, m['body_weight_g']!, 'male', 448), 5100);
    // Peak hen-housed production 89.6% at week 31 (day 217), page 8.
    expect(
      await spot(db, id, m['hen_housed_production_pct']!, 'female', 217),
      89.6,
    );
    // Egg mass at week 56 (day 392), page 10.
    expect(await spot(db, id, m['egg_mass_g']!, 'female', 392), 44.0);
    // Total eggs (HHA) at depletion, cross-checked against the Performance
    // Summary on page 3 as well as the weekly table on page 8.
    expect(
      await spot(db, id, m['eggs_per_hen_housed_cumulative']!, 'female', 448),
      192.7,
    );
  });

  test('Indian River spot values match the published PDF', () async {
    final db = await DatabaseHelper().db;
    final id = await profileId(db, 'aviagen_indianriver_parent_stock_2021_en');
    final m = await metricIdsByCode(db);

    // Cumulative hatchability at day 448 — page 9 and the Performance
    // Summary's "Hatchability %" agree at 86.6.
    expect(
      await spot(db, id, m['hatchability_cumulative_pct']!, 'female', 448),
      86.6,
    );
    // Total eggs (HHA), page 3 / page 8.
    expect(
      await spot(db, id, m['eggs_per_hen_housed_cumulative']!, 'female', 448),
      187.5,
    );
    // Chicks per female housed, page 3 / page 9.
    expect(
      await spot(db, id, m['chicks_per_hen_housed_cumulative']!, 'female', 448),
      155.0,
    );
  });

  test('Hubbard EDGE spot values match the published PDF', () async {
    final db = await DatabaseHelper().db;
    final id = await profileId(
      db,
      'hubbard_conventional_edge_parent_stock_2025_en',
    );
    final m = await metricIdsByCode(db);

    // Page 2, week 24 (day 168): bodyweight 2930 g, ration 134 g/day.
    expect(await spot(db, id, m['body_weight_g']!, 'female', 168), 2930);
    expect(await spot(db, id, m['daily_feed_intake_g']!, 'female', 168), 134);
    // Page 3, final row (day 448): the before-feeding weight of "4147 / 4312".
    expect(await spot(db, id, m['body_weight_g']!, 'female', 448), 4147);
    // Page 4, final row: end-of-cycle cumulative headline figures.
    expect(
      await spot(db, id, m['eggs_per_hen_housed_cumulative']!, 'female', 448),
      181.8,
    );
    expect(
      await spot(
        db,
        id,
        m['hatching_eggs_per_hen_housed_cumulative']!,
        'female',
        448,
      ),
      174.7,
    );
    expect(
      await spot(db, id, m['chicks_per_hen_housed_cumulative']!, 'female', 448),
      149.6,
    );

    // Hubbard publishes no male table and no liveability, and its feed data
    // stops at week 24. Nothing is inferred to fill those gaps.
    final maleRows = Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM breeder_benchmark_values "
        "WHERE profileId = ? AND sex = 'male'",
        [id],
      ),
    );
    expect(maleRows, 0);
    final liveability = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM breeder_benchmark_values '
        'WHERE profileId = ? AND metricId IN (?, ?)',
        [id, m['liveability_rearing_pct'], m['liveability_laying_pct']],
      ),
    );
    expect(liveability, 0);
  });

  test('Cobb500 spot values match the supplements summary box', () async {
    final db = await DatabaseHelper().db;
    final fast = await profileId(db, 'cobb500_fast_feather_parent_stock_2020_en');
    final m = await metricIdsByCode(db);

    // Week 65 = day 455. Fast Feather's summary box prints 181.3 total eggs
    // and 174.8 hatching eggs per hen housed.
    expect(
      await spot(db, fast, m['eggs_per_hen_housed_cumulative']!, 'female', 455),
      181.3,
    );
    expect(
      await spot(
        db,
        fast,
        m['hatching_eggs_per_hen_housed_cumulative']!,
        'female',
        455,
      ),
      174.8,
    );
    // Cobb publishes the male line in its own Male Management Supplement
    // rather than in the feathering supplement, so the male series must be
    // present on this profile even though it came from a second document.
    final males = await db.query(
      'breeder_benchmark_values',
      columns: ['ageDays', 'targetValue'],
      where: "profileId = ? AND metricId = ? AND sex = 'male'",
      whereArgs: [fast, m['body_weight_g']],
      orderBy: 'ageDays ASC',
    );
    expect(males, isNotEmpty);
  });

  test('Cobb500 Slow Feather is not imported', () async {
    final db = await DatabaseHelper().db;
    final rows = await db.query(
      'breeder_benchmark_profiles',
      where: 'profileKey = ?',
      whereArgs: ['cobb500_slow_feather_parent_stock_2020_en'],
    );
    expect(rows, isEmpty);
  });

  test('Cobb-only metrics exist only under the Cobb profiles', () async {
    final db = await DatabaseHelper().db;
    final m = await metricIdsByCode(db);

    for (final code in [
      'fertility_weekly_pct',
      'fertility_cumulative_pct',
      'flock_mortality_cumulative_pct',
      'chick_weight_g',
    ]) {
      final companies = await db.rawQuery('''
        SELECT DISTINCT p.company
        FROM breeder_benchmark_values v
        JOIN breeder_benchmark_profiles p ON p.id = v.profileId
        WHERE v.metricId = ?
      ''', [m[code]]);
      expect(
        companies.map((r) => r['company']).toSet(),
        {'Cobb-Vantress'},
        reason: '$code should come only from the Cobb supplements',
      );
    }
  });
}
