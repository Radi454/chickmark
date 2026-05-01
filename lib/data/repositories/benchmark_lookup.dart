import '../../core/utils/bmk_age_calculator.dart';
import '../database/database_helper.dart';

class BenchmarkLookup {
  final DatabaseHelper _dbHelper;

  BenchmarkLookup({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  Future<Map<String, Object?>?> nearestBreedBenchmark({
    required int calculatedBmkAgeDays,
    required String breed,
  }) async {
    final bmkAgeWeeks = BmkAgeCalculator.benchmarkWeekForDays(
      calculatedBmkAgeDays,
    );
    if (bmkAgeWeeks == null) return null;

    final db = await _dbHelper.db;
    final result = await db.rawQuery(
      '''
      SELECT *
      FROM bmk_breeds
      WHERE breed = ?
      ORDER BY ABS(ageWeek - ?)
      LIMIT 1
      ''',
      [breed, bmkAgeWeeks],
    );
    if (result.isEmpty) return null;
    return result.first;
  }

  Future<Map<String, Object?>?> nearestBreakoutBenchmark({
    required int calculatedBmkAgeDays,
  }) async {
    final bmkAgeWeeks = BmkAgeCalculator.benchmarkWeekForDays(
      calculatedBmkAgeDays,
    );
    if (bmkAgeWeeks == null) return null;

    final db = await _dbHelper.db;
    final result = await db.rawQuery(
      '''
      SELECT *
      FROM bmk_egg_breakout
      ORDER BY ABS(ageWeek - ?)
      LIMIT 1
      ''',
      [bmkAgeWeeks],
    );
    if (result.isEmpty) return null;
    return result.first;
  }
}
