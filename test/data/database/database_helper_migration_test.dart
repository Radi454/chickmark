import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

Future<Database> _openInMemoryDatabase() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('PRAGMA foreign_keys = ON');
  return db;
}

Future<void> _createLegacyGoveeV23Tables(Database db) async {
  await db.execute('''CREATE TABLE govee_daily_captures (
    id TEXT PRIMARY KEY,
    customerId TEXT NOT NULL,
    hatcheryId TEXT NOT NULL,
    place TEXT NOT NULL,
    captureDate TEXT NOT NULL,
    deviceId TEXT,
    deviceName TEXT,
    status TEXT NOT NULL,
    tempAvg REAL,
    tempMin REAL,
    tempMax REAL,
    rhAvg REAL,
    rhMin REAL,
    rhMax REAL,
    spotCount INTEGER NOT NULL,
    readingCount INTEGER NOT NULL,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    UNIQUE(customerId, hatcheryId, place, captureDate)
  )''');
  await db.execute('''CREATE TABLE govee_spot_captures (
    id TEXT PRIMARY KEY,
    captureId TEXT NOT NULL,
    spotIndex INTEGER NOT NULL,
    spotLabel TEXT NOT NULL,
    warmupStartedAt TEXT NOT NULL,
    validStartedAt TEXT NOT NULL,
    validEndedAt TEXT NOT NULL,
    validDurationSeconds INTEGER NOT NULL,
    tempAvg REAL,
    tempMin REAL,
    tempMax REAL,
    rhAvg REAL,
    rhMin REAL,
    rhMax REAL,
    readingCount INTEGER NOT NULL,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    FOREIGN KEY (captureId) REFERENCES govee_daily_captures(id) ON DELETE CASCADE
  )''');
  await db.execute('''CREATE TABLE govee_spot_readings (
    id TEXT PRIMARY KEY,
    captureId TEXT NOT NULL,
    spotId TEXT NOT NULL,
    readingIndex INTEGER NOT NULL,
    recordedAt TEXT NOT NULL,
    temperatureFahrenheit REAL NOT NULL,
    humidity REAL NOT NULL,
    rssi INTEGER,
    deviceName TEXT,
    createdAt TEXT NOT NULL,
    FOREIGN KEY (captureId) REFERENCES govee_daily_captures(id) ON DELETE CASCADE,
    FOREIGN KEY (spotId) REFERENCES govee_spot_captures(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE INDEX idx_govee_daily_scope ON govee_daily_captures (customerId, hatcheryId, place, captureDate)',
  );
}

Future<void> _insertLegacyGoveeFixture(
  Database db, {
  required String captureId,
  required String place,
  String captureDate = '2026-05-02',
}) async {
  const createdAt = '2026-05-02T10:00:00.000';
  const updatedAt = '2026-05-02T10:15:00.000';
  final spotId = '$captureId-spot-1';
  await db.insert('govee_daily_captures', {
    'id': captureId,
    'customerId': 'customer-1',
    'hatcheryId': 'hatchery-1',
    'place': place,
    'captureDate': captureDate,
    'deviceId': 'device-1',
    'deviceName': 'Govee H5051',
    'status': 'completed',
    'tempAvg': 99.2,
    'tempMin': 98.7,
    'tempMax': 99.8,
    'rhAvg': 55.5,
    'rhMin': 54.0,
    'rhMax': 57.0,
    'spotCount': 1,
    'readingCount': 1,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  });
  await db.insert('govee_spot_captures', {
    'id': spotId,
    'captureId': captureId,
    'spotIndex': 1,
    'spotLabel': 'Spot 1',
    'warmupStartedAt': '2026-05-02T09:58:00.000',
    'validStartedAt': '2026-05-02T09:59:00.000',
    'validEndedAt': '2026-05-02T10:00:00.000',
    'validDurationSeconds': 60,
    'readingCount': 1,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  });
  await db.insert('govee_spot_readings', {
    'id': '$captureId-reading-1',
    'captureId': captureId,
    'spotId': spotId,
    'readingIndex': 0,
    'recordedAt': '2026-05-02T09:59:30.000',
    'temperatureFahrenheit': 99.2,
    'humidity': 55.5,
    'rssi': -61,
    'deviceName': 'Govee H5051',
    'createdAt': createdAt,
  });
}

void main() {
  test('web database recovery recognizes corrupted IndexedDB open errors', () {
    final helper = DatabaseHelper();

    expect(
      helper.isRecoverableWebDatabaseOpenErrorForTest(
        RangeError('Invalid typed array length: -4096'),
      ),
      isTrue,
    );
    expect(
      helper.isRecoverableWebDatabaseOpenErrorForTest(
        StateError('schema migration failed'),
      ),
      isFalse,
    );
  });

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

  test('v21 migration adds Chicks CVT grid JSON columns', () async {
    final db = MockDatabase();

    when(() => db.rawQuery('PRAGMA table_info(audits)')).thenAnswer(
      (_) async => [
        {
          'cid': 0,
          'name': 'id',
          'type': 'TEXT',
          'notnull': 1,
          'dflt_value': null,
          'pk': 1,
        },
      ],
    );
    when(() => db.execute(any())).thenAnswer((_) async {});

    await DatabaseHelper().applyV21UpgradeForTest(db);

    final executedSql = verify(
      () => db.execute(captureAny()),
    ).captured.cast<String>().toList();

    expect(
      executedSql,
      contains('ALTER TABLE audits ADD COLUMN cvtReadingsJson TEXT'),
    );
    expect(
      executedSql,
      contains('ALTER TABLE audits ADD COLUMN cvtPhotosJson TEXT'),
    );
    expect(executedSql.any((sql) => sql.contains('DROP TABLE')), isFalse);
  });

  test(
    'v22 migration creates Govee tables and deletes old audit-linked temperature rows',
    () async {
      final db = MockDatabase();

      when(() => db.execute(any())).thenAnswer((_) async {});

      await DatabaseHelper().applyV22UpgradeForTest(db);

      final executedSql = verify(
        () => db.execute(captureAny()),
      ).captured.cast<String>().toList();
      final joinedSql = executedSql.join('\n');

      expect(
        joinedSql,
        contains('CREATE TABLE IF NOT EXISTS govee_daily_captures'),
      );
      expect(
        joinedSql,
        contains(
          'UNIQUE(customerId, hatcheryId, place, machineId, captureDate)',
        ),
      );
      expect(joinedSql, contains("stationKey TEXT NOT NULL DEFAULT ''"));
      expect(joinedSql, contains("machineId TEXT NOT NULL DEFAULT ''"));
      expect(joinedSql, contains('startedAt TEXT'));
      expect(joinedSql, contains('endedAt TEXT'));
      expect(joinedSql, contains('tempSd REAL'));
      expect(joinedSql, contains('tempCvPct REAL'));
      expect(joinedSql, contains('rhSd REAL'));
      expect(joinedSql, contains('rhCvPct REAL'));
      expect(
        joinedSql,
        contains('CREATE TABLE IF NOT EXISTS govee_place_readings'),
      );
      expect(joinedSql, isNot(contains('govee_spot_captures')));
      expect(joinedSql, isNot(contains('govee_spot_readings')));
      expect(joinedSql, isNot(contains('spotCount')));
      expect(joinedSql, contains('idx_govee_place_readings_capture'));
      expect(joinedSql, contains('idx_govee_daily_scope'));
      expect(
        joinedSql,
        contains('DELETE FROM temperature_readings WHERE sessionId IN'),
      );
      expect(
        joinedSql,
        contains(
          'DELETE FROM temperature_sessions WHERE auditSessionId IS NOT NULL',
        ),
      );
    },
  );

  test('v23 migration renames station identity values', () async {
    final db = MockDatabase();

    when(() => db.execute(any())).thenAnswer((_) async {});

    await DatabaseHelper().applyV23UpgradeForTest(db);

    final executedSql = verify(
      () => db.execute(captureAny()),
    ).captured.cast<String>().toList();
    final joinedSql = executedSql.join('\n');

    expect(joinedSql, contains("WHEN 'Chick Quality' THEN 'Chicks'"));
    expect(
      joinedSql,
      contains("WHEN 'Hatch Analysis' THEN 'Hatch Analysis & Egg Breakouts'"),
    );
    expect(joinedSql, contains("WHEN 'Setter Optimizing' THEN 'Setters'"));
    expect(joinedSql, contains("WHEN 'Hatcher Optimizing' THEN 'Hatchers'"));
    expect(joinedSql, contains('"chick_quality"'));
    expect(joinedSql, contains('"hatch_analysis_egg_breakouts"'));
  });

  test(
    'v25 migration preserves Govee records and converts old place values',
    () async {
      final db = await _openInMemoryDatabase();
      addTearDown(db.close);
      await _createLegacyGoveeV23Tables(db);
      await _insertLegacyGoveeFixture(
        db,
        captureId: 'capture-setter-room',
        place: 'incubatorRoom',
      );

      await DatabaseHelper().applyV25UpgradeForTest(db);

      final captures = await db.query('govee_daily_captures');
      expect(captures, hasLength(1));
      expect(captures.single['place'], 'setterRoom');
      expect(captures.single['stationKey'], 'setters');
      expect(captures.single['machineId'], '');
      expect(captures.single['startedAt'], '2026-05-02T10:00:00.000');
      expect(captures.single['endedAt'], '2026-05-02T10:15:00.000');

      final legacySpotTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'govee_spot_%'",
      );
      expect(legacySpotTables, isEmpty);

      final readings = await db.query('govee_place_readings');
      expect(readings, hasLength(1));
      expect(readings.single['captureId'], 'capture-setter-room');
      expect(readings.single['readingIndex'], 0);
      expect(readings.single['recordedAt'], '2026-05-02T09:59:30.000');
      expect(readings.single.keys, isNot(contains('spotId')));
      expect(readings.single.keys, isNot(contains('bucketStartedAt')));
      expect(readings.single.keys, isNot(contains('rawReadingCount')));
    },
  );

  test('v25 migration creates dashboard query index', () async {
    final db = await _openInMemoryDatabase();
    addTearDown(db.close);
    await _createLegacyGoveeV23Tables(db);

    await DatabaseHelper().applyV25UpgradeForTest(db);

    final indexes = await db.rawQuery(
      "PRAGMA index_info('idx_govee_daily_dashboard')",
    );
    expect(indexes.map((row) => row['name']), [
      'customerId',
      'hatcheryId',
      'captureDate',
    ]);
  });

  test('v25 migration creates machine-aware capture scope', () async {
    final db = await _openInMemoryDatabase();
    addTearDown(db.close);
    await _createLegacyGoveeV23Tables(db);

    await DatabaseHelper().applyV25UpgradeForTest(db);

    final scopeIndex = await db.rawQuery(
      "PRAGMA index_info('idx_govee_daily_scope')",
    );
    expect(scopeIndex.map((row) => row['name']), [
      'customerId',
      'hatcheryId',
      'place',
      'machineId',
      'captureDate',
    ]);

    final indexes = await db.rawQuery(
      "PRAGMA index_list('govee_daily_captures')",
    );
    final uniqueColumnSets = <List<Object?>>[];
    for (final index in indexes) {
      if (index['unique'] != 1) continue;
      final columns = await db.rawQuery(
        "PRAGMA index_info('${index['name']}')",
      );
      uniqueColumnSets.add(columns.map((row) => row['name']).toList());
    }
    final uniqueColumnKeys = uniqueColumnSets.map((columns) {
      return columns.join(',');
    }).toList();
    expect(
      uniqueColumnKeys,
      contains('customerId,hatcheryId,place,machineId,captureDate'),
    );
    expect(
      uniqueColumnKeys,
      isNot(
        contains(
          'customerId,hatcheryId,stationKey,place,machineId,captureDate',
        ),
      ),
    );
  });

  test(
    'v25 migration allows inside setter captures per machine on same date',
    () async {
      final db = await _openInMemoryDatabase();
      addTearDown(db.close);
      await _createLegacyGoveeV23Tables(db);
      await _insertLegacyGoveeFixture(
        db,
        captureId: 'capture-inside-setter',
        place: 'insideIncubator',
      );

      await DatabaseHelper().applyV25UpgradeForTest(db);

      final migrated = await db.query(
        'govee_daily_captures',
        where: 'id = ?',
        whereArgs: ['capture-inside-setter'],
      );
      expect(migrated.single['place'], 'insideSetter');
      expect(migrated.single['stationKey'], 'setters');

      for (final machineId in ['Setter 1', 'Setter 2']) {
        await db.insert('govee_daily_captures', {
          'id': 'capture-$machineId',
          'customerId': 'customer-1',
          'hatcheryId': 'hatchery-1',
          'stationKey': 'setters',
          'place': 'insideSetter',
          'machineId': machineId,
          'captureDate': '2026-05-02',
          'status': 'completed',
          'readingCount': 0,
          'createdAt': '2026-05-02T11:00:00.000',
          'updatedAt': '2026-05-02T11:00:00.000',
        });
      }

      final captures = await db.query(
        'govee_daily_captures',
        where:
            'customerId = ? AND hatcheryId = ? AND place = ? AND captureDate = ?',
        whereArgs: ['customer-1', 'hatchery-1', 'insideSetter', '2026-05-02'],
        orderBy: 'machineId ASC',
      );
      expect(captures.map((row) => row['machineId']), [
        '',
        'Setter 1',
        'Setter 2',
      ]);
    },
  );
}
