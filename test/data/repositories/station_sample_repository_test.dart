import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/data/repositories/station_sample_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

class MockDatabase extends Mock implements Database {}

class MockDatabaseHelper extends Mock implements DatabaseHelper {}

class MockTransaction extends Mock implements Transaction {}

Future<Database> _openStationSampleDatabase() async {
  ffi.sqfliteFfiInit();
  final db = await ffi.databaseFactoryFfi.openDatabase(
    ffi.inMemoryDatabasePath,
  );
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute('CREATE TABLE audits (id TEXT PRIMARY KEY)');
  await db.execute('CREATE TABLE audit_sessions (id TEXT PRIMARY KEY)');
  await DatabaseHelper().applyV31UpgradeForTest(db);
  await db.insert('audits', {'id': 'audit-1'});
  await db.insert('audit_sessions', {'id': 'session-1'});
  return db;
}

void main() {
  late MockDatabase db;
  late MockDatabaseHelper dbHelper;
  late MockTransaction txn;
  late StationSampleRepository repository;

  final sample = StationSampleModel(
    id: 'sample-1',
    auditSessionId: 'session-1',
    legacyAuditId: 'audit-1',
    stationType: 'chicks',
    sectorType: StationSampleModel.sectorChickWeights,
    sampleKind: StationSampleModel.sampleKindHouse,
    sampleMode: StationSampleModel.sampleModeComparison,
    comparisonType: StationSampleModel.comparisonTypeHouse,
    sampleIndex: 1,
    sampleLabel: 'H1',
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
    txn = MockTransaction();
    when(() => dbHelper.db).thenAnswer((_) async => db);
    repository = StationSampleRepository(dbHelper: dbHelper);

    when(() => db.transaction<void>(any())).thenAnswer((invocation) {
      final action =
          invocation.positionalArguments.single
              as Future<void> Function(Transaction);
      return action(txn);
    });
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
    when(
      () => txn.insert(
        any(),
        any(),
        conflictAlgorithm: any(named: 'conflictAlgorithm'),
      ),
    ).thenAnswer((_) async => 1);
    when(
      () => txn.delete(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      ),
    ).thenAnswer((_) async => 1);
    when(() => db.rawQuery(any())).thenAnswer(
      (_) async => sample.toMap().keys.map((name) => {'name': name}).toList(),
    );
  });

  test(
    'upsertSample writes normalized sample record and matching details',
    () async {
      await repository.upsertSample(sample);

      final record =
          verify(
                () => txn.insert(
                  'sample_records',
                  captureAny(),
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                ),
              ).captured.single
              as Map<String, dynamic>;

      expect(record['id'], 'sample-1');
      expect(record['auditSessionId'], 'session-1');
      expect(record['legacyAuditId'], 'audit-1');
      expect(record['stationType'], 'chicks');
      expect(record['sectorType'], StationSampleModel.sectorChickWeights);
      expect(record['sampleKind'], StationSampleModel.sampleKindHouse);
      expect(record['sampleMode'], StationSampleModel.sampleModeComparison);
      expect(record.containsKey('houseNo'), isFalse);
      expect(record.containsKey('setterNo'), isFalse);

      final houseDetails =
          verify(
                () => txn.insert(
                  'sample_house_details',
                  captureAny(),
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(houseDetails['sampleRecordId'], 'sample-1');
      expect(houseDetails['houseNo'], 'HSE-01');
      expect(houseDetails['houseLabel'], 'North House');
      verifyNever(
        () => txn.insert(
          'sample_machine_details',
          any(),
          conflictAlgorithm: any(named: 'conflictAlgorithm'),
        ),
      );
    },
  );

  test('getSamplesForStation filters by session and station', () async {
    when(
      () => db.rawQuery(any(), ['session-1', 'chicks']),
    ).thenAnswer((_) async => [sample.toMap()]);

    final result = await repository.getSamplesForStation('session-1', 'chicks');

    expect(result, hasLength(1));
    expect(result.single.id, 'sample-1');
  });

  test('getSamplesBySessionId filters by audit session', () async {
    when(
      () => db.rawQuery(any(), ['session-1']),
    ).thenAnswer((_) async => [sample.toMap()]);

    final result = await repository.getSamplesBySessionId('session-1');

    expect(result.single.auditSessionId, 'session-1');
  });

  test('getSamplesByGroupKey filters by session and group key', () async {
    when(
      () => db.rawQuery(any(), ['session-1', 'group-1']),
    ).thenAnswer((_) async => [sample.copyWith(groupKey: 'group-1').toMap()]);

    final result = await repository.getSamplesByGroupKey(
      'session-1',
      'group-1',
    );

    expect(result.single.groupKey, 'group-1');
  });

  test('getSamplesByLegacyAuditId filters by linked audit row', () async {
    when(
      () => db.rawQuery(any(), ['audit-1']),
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
              () => txn.insert(
                'sample_records',
                captureAny(),
                conflictAlgorithm: ConflictAlgorithm.ignore,
              ),
            ).captured.single
            as Map<String, dynamic>;

    expect(captured['auditSessionId'], 'session-1');
    expect(captured['legacyAuditId'], 'audit-2');
    expect(captured['stationType'], 'egg');
    expect(captured['sampleKind'], StationSampleModel.sampleKindHouse);
    verify(
      () => txn.insert(
        'sample_house_details',
        any(that: containsPair('houseNo', 'HSE-02')),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      ),
    ).called(1);
    expect(captured.containsKey('unknown_column'), isFalse);
  });

  test(
    'upsertSample rolls back detail deletes when parent write fails',
    () async {
      final realDb = await _openStationSampleDatabase();
      addTearDown(realDb.close);
      final realDbHelper = MockDatabaseHelper();
      when(() => realDbHelper.db).thenAnswer((_) async => realDb);
      final realRepository = StationSampleRepository(dbHelper: realDbHelper);
      const existingCreatedAt = '2026-04-27T08:00:00.000';
      const existingUpdatedAt = '2026-04-27T09:00:00.000';

      await realDb.insert('sample_records', {
        'id': 'sample-rollback',
        'auditSessionId': 'session-1',
        'legacyAuditId': 'audit-1',
        'stationType': 'egg',
        'sectorType': StationSampleModel.sectorEggQuality,
        'sampleKind': StationSampleModel.sampleKindHouse,
        'sampleMode': StationSampleModel.sampleModePooled,
        'sampleIndex': 1,
        'sampleLabel': 'House 1',
        'sampleType': StationSampleModel.sampleTypeDefault,
        'createdAt': existingCreatedAt,
        'updatedAt': existingUpdatedAt,
      });
      await realDb.insert('sample_house_details', {
        'sampleRecordId': 'sample-rollback',
        'houseNo': 'OLD-HOUSE',
        'houseLabel': 'Old House',
      });

      final invalidSample = StationSampleModel(
        id: 'sample-rollback',
        auditSessionId: 'session-1',
        legacyAuditId: 'missing-audit',
        stationType: 'egg',
        sectorType: StationSampleModel.sectorEggQuality,
        sampleKind: StationSampleModel.sampleKindHouse,
        sampleMode: StationSampleModel.sampleModePooled,
        sampleIndex: 1,
        sampleLabel: 'House 1',
        sampleType: StationSampleModel.sampleTypeDefault,
        houseNo: 'NEW-HOUSE',
        houseLabel: 'New House',
        createdAt: DateTime(2026, 4, 27, 10),
        updatedAt: DateTime(2026, 4, 27, 10),
      );

      await expectLater(
        realRepository.upsertSample(invalidSample),
        throwsA(isA<DatabaseException>()),
      );

      final records = await realDb.query(
        'sample_records',
        where: 'id = ?',
        whereArgs: ['sample-rollback'],
      );
      expect(records.single['legacyAuditId'], 'audit-1');
      expect(records.single['updatedAt'], existingUpdatedAt);

      final houseDetails = await realDb.query(
        'sample_house_details',
        where: 'sampleRecordId = ?',
        whereArgs: ['sample-rollback'],
      );
      expect(houseDetails, hasLength(1));
      expect(houseDetails.single['houseNo'], 'OLD-HOUSE');
      expect(houseDetails.single['houseLabel'], 'Old House');
    },
  );
}
