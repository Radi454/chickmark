import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/data/repositories/station_sample_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';

class MockDatabase extends Mock implements Database {}

class MockDatabaseHelper extends Mock implements DatabaseHelper {}

void main() {
  late MockDatabase db;
  late MockDatabaseHelper dbHelper;
  late StationSampleRepository repository;

  final sample = StationSampleModel(
    id: 'sample-1',
    auditSessionId: 'session-1',
    legacyAuditId: 'audit-1',
    stationType: 'chicks',
    sampleMode: StationSampleModel.sampleModeComparison,
    comparisonType: StationSampleModel.comparisonTypeBatch,
    sampleIndex: 1,
    sampleLabel: 'Sample 1',
    houseNo: 'HSE-01',
    houseLabel: 'North House',
    calculatedBmkAgeDays: 280,
    createdAt: DateTime(2026, 4, 27, 8),
    updatedAt: DateTime(2026, 4, 27, 8),
  );

  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  setUp(() {
    db = MockDatabase();
    dbHelper = MockDatabaseHelper();
    when(() => dbHelper.db).thenAnswer((_) async => db);
    repository = StationSampleRepository(dbHelper: dbHelper);

    when(
      () => db.insert(
        any(),
        any(),
        conflictAlgorithm: any(named: 'conflictAlgorithm'),
      ),
    ).thenAnswer((_) async => 1);
    when(
      () => db.query(
        any(),
        columns: any(named: 'columns'),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
        orderBy: any(named: 'orderBy'),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    ).thenAnswer((_) async => <Map<String, Object?>>[]);
    when(
      () => db.delete(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      ),
    ).thenAnswer((_) async => 1);
    when(() => db.rawQuery(any())).thenAnswer(
      (_) async => sample.toMap().keys.map((name) => {'name': name}).toList(),
    );
  });

  test('upsertSample writes station sample by stable id', () async {
    await repository.upsertSample(sample);

    final captured =
        verify(
              () => db.insert(
                'station_samples',
                captureAny(),
                conflictAlgorithm: ConflictAlgorithm.replace,
              ),
            ).captured.single
            as Map<String, dynamic>;

    expect(captured['id'], 'sample-1');
    expect(captured['auditSessionId'], 'session-1');
    expect(captured['legacyAuditId'], 'audit-1');
    expect(captured['sampleMode'], StationSampleModel.sampleModeComparison);
    expect(captured['houseNo'], 'HSE-01');
    expect(captured['houseLabel'], 'North House');
  });

  test('getSamplesForStation filters by session and station', () async {
    when(
      () => db.query(
        'station_samples',
        where: 'auditSessionId = ? AND stationType = ?',
        whereArgs: ['session-1', 'chicks'],
        orderBy: 'sampleIndex ASC, createdAt ASC',
      ),
    ).thenAnswer((_) async => [sample.toMap()]);

    final result = await repository.getSamplesForStation('session-1', 'chicks');

    expect(result, hasLength(1));
    expect(result.single.id, 'sample-1');
  });

  test('getSamplesBySessionId filters by audit session', () async {
    when(
      () => db.query(
        'station_samples',
        where: 'auditSessionId = ?',
        whereArgs: ['session-1'],
        orderBy: 'stationType ASC, sampleIndex ASC, createdAt ASC',
      ),
    ).thenAnswer((_) async => [sample.toMap()]);

    final result = await repository.getSamplesBySessionId('session-1');

    expect(result.single.auditSessionId, 'session-1');
  });

  test('getSamplesByGroupKey filters by session and group key', () async {
    when(
      () => db.query(
        'station_samples',
        where: 'auditSessionId = ? AND groupKey = ?',
        whereArgs: ['session-1', 'group-1'],
        orderBy: 'sampleIndex ASC, createdAt ASC',
      ),
    ).thenAnswer((_) async => [sample.copyWith(groupKey: 'group-1').toMap()]);

    final result = await repository.getSamplesByGroupKey(
      'session-1',
      'group-1',
    );

    expect(result.single.groupKey, 'group-1');
  });

  test('getSamplesByLegacyAuditId filters by linked audit row', () async {
    when(
      () => db.query(
        'station_samples',
        where: 'legacyAuditId = ?',
        whereArgs: ['audit-1'],
        orderBy: 'sampleIndex ASC, createdAt ASC',
      ),
    ).thenAnswer((_) async => [sample.toMap()]);

    final result = await repository.getSamplesByLegacyAuditId('audit-1');

    expect(result.single.legacyAuditId, 'audit-1');
  });

  test('upsertSampleRow normalizes snake case aliases', () async {
    await repository.upsertSampleRow({
      'id': 'sample-2',
      'audit_session_id': 'session-1',
      'legacy_audit_id': 'audit-2',
      'station_type': 'egg',
      'sample_mode': 'pooled',
      'sample_index': 1,
      'sample_label': 'Sample 1',
      'house_no': 'HSE-02',
      'house_label': 'South House',
      'created_at': DateTime(2026, 4, 27).toIso8601String(),
      'updated_at': DateTime(2026, 4, 27).toIso8601String(),
      'unknown_column': 'ignored',
    });

    final captured =
        verify(
              () => db.insert(
                'station_samples',
                captureAny(),
                conflictAlgorithm: ConflictAlgorithm.replace,
              ),
            ).captured.single
            as Map<String, dynamic>;

    expect(captured['auditSessionId'], 'session-1');
    expect(captured['legacyAuditId'], 'audit-2');
    expect(captured['stationType'], 'egg');
    expect(captured['houseNo'], 'HSE-02');
    expect(captured['houseLabel'], 'South House');
    expect(captured.containsKey('unknown_column'), isFalse);
  });
}
