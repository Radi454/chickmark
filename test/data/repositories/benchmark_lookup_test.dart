import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/repositories/benchmark_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';

class MockDatabase extends Mock implements Database {}

class MockDatabaseHelper extends Mock implements DatabaseHelper {}

void main() {
  test('uses nearest benchmark week for calculated BMK days', () async {
    final db = MockDatabase();
    final dbHelper = MockDatabaseHelper();
    final lookup = BenchmarkLookup(dbHelper: dbHelper);

    when(() => dbHelper.db).thenAnswer((_) async => db);
    when(() => db.rawQuery(any(), any())).thenAnswer(
      (_) async => [
        {'ageWeek': 40, 'breed': 'Ross308', 'eggWeightG': 62.5},
      ],
    );

    final row = await lookup.nearestBreedBenchmark(
      calculatedBmkAgeDays: 283,
      breed: 'Ross308',
    );

    expect(row!['ageWeek'], 40);
    final captured = verify(
      () => db.rawQuery(captureAny(), captureAny()),
    ).captured;
    expect(captured.first as String, contains('ORDER BY ABS(ageWeek - ?)'));
    expect(captured.last as List<Object?>, ['Ross308', 40]);
  });
}
