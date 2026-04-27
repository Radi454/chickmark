import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';

class MockDatabase extends Mock implements Database {}

void main() {
  test('v18 migration adds columns without recreating tables', () async {
    final db = MockDatabase();

    when(() => db.rawQuery(any())).thenAnswer((_) async => []);
    when(() => db.execute(any())).thenAnswer((_) async {});
    when(
      () => db.insert(
        any(),
        any(),
        conflictAlgorithm: any(named: 'conflictAlgorithm'),
      ),
    ).thenAnswer((_) async => 1);

    await DatabaseHelper().applyV18UpgradeForTest(db);

    final executedSql = verify(
      () => db.execute(captureAny()),
    ).captured.cast<String>().toList();

    expect(
      executedSql,
      contains(
        predicate<String>(
          (sql) => sql.contains('ALTER TABLE audits ADD COLUMN sampleMode'),
        ),
      ),
    );
    expect(
      executedSql,
      contains(
        predicate<String>(
          (sql) =>
              sql.contains('ALTER TABLE audits ADD COLUMN compareGroupKey'),
        ),
      ),
    );
    expect(
      executedSql,
      contains(
        predicate<String>(
          (sql) =>
              sql.contains('ALTER TABLE audits ADD COLUMN ebTrayBreakoutJson'),
        ),
      ),
    );
    expect(
      executedSql,
      contains(
        predicate<String>(
          (sql) => sql.contains(
            'ALTER TABLE troubleshooting ADD COLUMN benchmarkJson',
          ),
        ),
      ),
    );
    expect(executedSql.any((sql) => sql.contains('DROP TABLE')), isFalse);
    expect(executedSql.any((sql) => sql.contains('CREATE TABLE')), isFalse);
  });
}
