import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';

class MockDatabase extends Mock implements Database {}

class MockTransaction extends Mock implements Transaction {}

List<Map<String, Object?>> _stationSampleColumns({
  bool includeHouse = false,
  bool includeCustom = false,
}) {
  final names = [
    'id',
    'auditSessionId',
    'legacyAuditId',
    'stationType',
    'sampleMode',
    'sampleIndex',
    'createdAt',
    'updatedAt',
    if (includeHouse) ...['houseNo', 'houseLabel'],
    if (includeCustom) 'customMetric',
  ];
  return [
    for (var i = 0; i < names.length; i++)
      {
        'cid': i,
        'name': names[i],
        'type': names[i] == 'sampleIndex' || names[i] == 'customMetric'
            ? 'INTEGER'
            : 'TEXT',
        'notnull': names[i] == 'id' ? 1 : 0,
        'dflt_value': null,
        'pk': names[i] == 'id' ? 1 : 0,
      },
  ];
}

List<Map<String, Object?>> _stationSampleForeignKeys() => [
  {
    'id': 0,
    'seq': 0,
    'table': 'audits',
    'from': 'legacyAuditId',
    'to': 'id',
    'on_update': 'NO ACTION',
    'on_delete': 'CASCADE',
    'match': 'NONE',
  },
  {
    'id': 1,
    'seq': 0,
    'table': 'audit_sessions',
    'from': 'auditSessionId',
    'to': 'id',
    'on_update': 'NO ACTION',
    'on_delete': 'CASCADE',
    'match': 'NONE',
  },
];

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

  test('v19 migration creates station samples table and indexes', () async {
    final db = MockDatabase();

    when(() => db.execute(any())).thenAnswer((_) async {});

    await DatabaseHelper().applyV19UpgradeForTest(db);

    final executedSql = verify(
      () => db.execute(captureAny()),
    ).captured.cast<String>().toList();

    expect(
      executedSql,
      contains(
        predicate<String>(
          (sql) =>
              sql.contains('CREATE TABLE IF NOT EXISTS station_samples') &&
              sql.contains('auditSessionId TEXT NOT NULL') &&
              sql.contains('sampleMode TEXT NOT NULL') &&
              sql.contains('comparisonType TEXT') &&
              sql.contains('sampleIndex INTEGER NOT NULL') &&
              sql.contains('houseNo TEXT') &&
              sql.contains('houseLabel TEXT') &&
              sql.contains('resultSummaryJson TEXT') &&
              sql.contains(
                'FOREIGN KEY (auditSessionId) REFERENCES audit_sessions(id)',
              ) &&
              sql.contains('FOREIGN KEY (legacyAuditId) REFERENCES audits(id)'),
        ),
      ),
    );
    expect(
      executedSql.join('\n'),
      allOf(
        contains('idx_station_samples_session_station'),
        contains('idx_station_samples_group'),
        contains('idx_station_samples_legacy_audit'),
        contains('idx_station_samples_bmk_age'),
      ),
    );
    expect(executedSql.join('\n'), isNot(contains('trayNo')));
    expect(executedSql.join('\n'), isNot(contains('trayLevel')));
    expect(executedSql.join('\n'), isNot(contains('trayDepth')));
    expect(executedSql.join('\n'), isNot(contains('machineLabel')));
    expect(executedSql.any((sql) => sql.contains('DROP TABLE')), isFalse);
    expect(
      executedSql.any(
        (sql) =>
            sql.contains('CREATE TABLE') &&
            RegExp(
              r'CREATE TABLE(?: IF NOT EXISTS)? audits\s*\(',
            ).hasMatch(sql),
      ),
      isFalse,
    );
  });

  test(
    'v20 migration adds nullable house fields when foreign keys exist',
    () async {
      final db = MockDatabase();

      when(
        () => db.rawQuery('PRAGMA table_info(station_samples)'),
      ).thenAnswer((_) async => _stationSampleColumns());
      when(
        () => db.rawQuery('PRAGMA foreign_key_list(station_samples)'),
      ).thenAnswer((_) async => _stationSampleForeignKeys());
      when(() => db.execute(any())).thenAnswer((_) async {});

      await DatabaseHelper().applyV20UpgradeForTest(db);

      final executedSql = verify(
        () => db.execute(captureAny()),
      ).captured.cast<String>().toList();

      expect(
        executedSql,
        contains('ALTER TABLE station_samples ADD COLUMN houseNo TEXT'),
      );
      expect(
        executedSql,
        contains('ALTER TABLE station_samples ADD COLUMN houseLabel TEXT'),
      );
      expect(executedSql.any((sql) => sql.contains('DROP TABLE')), isFalse);
    },
  );

  test(
    'v20 migration rebuilds in a transaction and preserves unknown columns',
    () async {
      final db = MockDatabase();
      final txn = MockTransaction();

      when(
        () => db.rawQuery('PRAGMA table_info(station_samples)'),
      ).thenAnswer((_) async => _stationSampleColumns(includeCustom: true));
      when(
        () => db.rawQuery('PRAGMA foreign_key_list(station_samples)'),
      ).thenAnswer((_) async => []);
      when(() => txn.execute(any())).thenAnswer((_) async {});
      when(() => db.transaction<void>(any())).thenAnswer((invocation) {
        final action =
            invocation.positionalArguments.single
                as Future<void> Function(Transaction);
        return action(txn);
      });

      await DatabaseHelper().applyV20UpgradeForTest(db);

      verify(() => db.transaction<void>(any())).called(1);
      final executedSql = verify(
        () => txn.execute(captureAny()),
      ).captured.cast<String>().toList();
      final joinedSql = executedSql.join('\n');

      expect(joinedSql, contains('"customMetric" INTEGER'));
      expect(joinedSql, contains('houseNo TEXT'));
      expect(joinedSql, contains('houseLabel TEXT'));
      expect(joinedSql, contains('FOREIGN KEY ("auditSessionId")'));
      expect(joinedSql, contains('FOREIGN KEY ("legacyAuditId")'));
      expect(joinedSql, contains('"customMetric"'));
      expect(joinedSql, contains('INSERT INTO "station_samples__v20_rebuild"'));
      expect(joinedSql, contains('SELECT "id", "auditSessionId"'));
      expect(joinedSql, contains('NULL, NULL'));
      expect(joinedSql, contains('DROP TABLE station_samples'));
      expect(
        joinedSql,
        contains(
          'ALTER TABLE "station_samples__v20_rebuild" RENAME TO station_samples',
        ),
      );
      expect(joinedSql, contains('idx_station_samples_session_station'));
      expect(joinedSql, contains('idx_station_samples_group'));
      expect(joinedSql, contains('idx_station_samples_legacy_audit'));
      expect(joinedSql, contains('idx_station_samples_bmk_age'));
    },
  );
}
