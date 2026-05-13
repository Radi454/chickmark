import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
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
  await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY)');
  await db.execute('''CREATE TABLE hatcheries (
    id TEXT PRIMARY KEY,
    customerId TEXT,
    name TEXT
  )''');
  await db.insert('customers', {'id': 'customer-1'});
  await db.insert('hatcheries', {
    'id': 'hatchery-1',
    'customerId': 'customer-1',
    'name': 'Hatchery 1',
  });
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

Future<void> _createStationSampleMigrationParents(Database db) async {
  await db.execute('CREATE TABLE audits (id TEXT PRIMARY KEY)');
  await db.execute('CREATE TABLE audit_sessions (id TEXT PRIMARY KEY)');
  await db.insert('audits', {'id': 'audit-legacy'});
  await db.insert('audit_sessions', {'id': 'session-legacy'});
}

Future<void> _createLegacyStationSamplesV30Table(Database db) async {
  await db.execute('''CREATE TABLE station_samples (
    id TEXT PRIMARY KEY,
    auditSessionId TEXT NOT NULL,
    legacyAuditId TEXT,
    stationType TEXT NOT NULL,
    sampleMode TEXT NOT NULL DEFAULT 'pooled',
    comparisonType TEXT,
    sampleIndex INTEGER NOT NULL DEFAULT 1,
    sampleLabel TEXT,
    sampleType TEXT,
    breakoutType TEXT,
    groupKey TEXT,
    groupLabel TEXT,
    houseNo TEXT,
    houseLabel TEXT,
    setterNo TEXT,
    hatcherNo TEXT,
    batchNo TEXT,
    hatchNo TEXT,
    storageDays INTEGER,
    incubationDay INTEGER,
    eggProductionDate TEXT,
    settingDate TEXT,
    hatchDate TEXT,
    calculatedBmkAgeDays INTEGER,
    benchmarkBreed TEXT,
    benchmarkAgeDays INTEGER,
    benchmarkSource TEXT,
    benchmarkSnapshotJson TEXT,
    resultSummaryJson TEXT,
    notes TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    FOREIGN KEY (auditSessionId) REFERENCES audit_sessions(id) ON DELETE CASCADE,
    FOREIGN KEY (legacyAuditId) REFERENCES audits(id) ON DELETE CASCADE
  )''');
}

Future<void> _insertLegacyStationSampleFixture(Database db) async {
  await db.insert('station_samples', {
    'id': 'legacy-sample-1',
    'auditSessionId': 'session-legacy',
    'legacyAuditId': 'audit-legacy',
    'stationType': 'chicks',
    'sampleMode': StationSampleModel.sampleModeComparison,
    'comparisonType': StationSampleModel.comparisonTypeMachine,
    'sampleIndex': 2,
    'sampleLabel': 'Machine 2',
    'sampleType': StationSampleModel.sampleTypeChickQualityHatchedBatch,
    'groupKey': 'machine-group-1',
    'groupLabel': 'Machine comparison',
    'houseNo': 'H-2',
    'houseLabel': 'House 2',
    'setterNo': 'Setter 2',
    'hatcherNo': 'Hatcher 2',
    'batchNo': 'Batch 2',
    'hatchNo': '2',
    'storageDays': 4,
    'incubationDay': 18,
    'eggProductionDate': '2026-05-01T00:00:00.000',
    'settingDate': '2026-05-05T00:00:00.000',
    'hatchDate': '2026-05-26T00:00:00.000',
    'calculatedBmkAgeDays': 280,
    'benchmarkBreed': 'Ross 308',
    'benchmarkAgeDays': 280,
    'benchmarkSource': 'legacy-bmk',
    'benchmarkSnapshotJson': '{"breed":"Ross 308"}',
    'resultSummaryJson': '{"avg":42.5}',
    'notes': 'legacy station note',
    'createdAt': '2026-05-02T10:00:00.000',
    'updatedAt': '2026-05-02T10:15:00.000',
  });
}

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

  test('v19 migration creates normalized sample tables and indexes', () async {
    final db = MockDatabase();

    when(() => db.execute(any())).thenAnswer((_) async {});
    when(() => db.rawQuery(any())).thenAnswer(
      (_) async => [
        {'name': 'auditSessionId'},
        {'name': 'stationType'},
        {'name': 'sectorType'},
        {'name': 'groupKey'},
        {'name': 'legacyAuditId'},
        {'name': 'calculatedBmkAgeDays'},
      ],
    );

    await DatabaseHelper().applyV19UpgradeForTest(db);

    final executedSql = verify(
      () => db.execute(captureAny()),
    ).captured.cast<String>().toList();

    expect(
      executedSql,
      contains(
        predicate<String>(
          (sql) =>
              sql.contains('CREATE TABLE IF NOT EXISTS sample_records') &&
              sql.contains('auditSessionId TEXT NOT NULL') &&
              sql.contains('sectorType TEXT NOT NULL') &&
              sql.contains('sampleKind TEXT NOT NULL') &&
              sql.contains('sampleMode TEXT NOT NULL') &&
              sql.contains('comparisonType TEXT') &&
              sql.contains('sampleIndex INTEGER NOT NULL') &&
              sql.contains('resultSummaryJson TEXT') &&
              sql.contains(
                'FOREIGN KEY (auditSessionId) REFERENCES audit_sessions(id)',
              ) &&
              sql.contains('FOREIGN KEY (legacyAuditId) REFERENCES audits(id)'),
        ),
      ),
    );
    expect(
      executedSql,
      contains(
        predicate<String>(
          (sql) =>
              sql.contains('CREATE TABLE IF NOT EXISTS sample_house_details') &&
              sql.contains('houseNo TEXT') &&
              sql.contains('houseLabel TEXT') &&
              sql.contains(
                'FOREIGN KEY (sampleRecordId) REFERENCES sample_records(id)',
              ),
        ),
      ),
    );
    expect(
      executedSql,
      contains(
        predicate<String>(
          (sql) =>
              sql.contains(
                'CREATE TABLE IF NOT EXISTS sample_machine_details',
              ) &&
              sql.contains('setterNo TEXT') &&
              sql.contains('hatcherNo TEXT') &&
              sql.contains(
                'FOREIGN KEY (sampleRecordId) REFERENCES sample_records(id)',
              ),
        ),
      ),
    );
    expect(
      executedSql.join('\n'),
      allOf(
        contains('idx_sample_records_session_station'),
        contains('idx_sample_records_group'),
        contains('idx_sample_records_legacy_audit'),
        contains('idx_sample_records_bmk_age'),
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
      when(() => db.rawQuery(any(), any())).thenAnswer((invocation) async {
        final args = invocation.positionalArguments[1] as List<Object?>;
        final table = args.single?.toString();
        if (table == 'temperature_sessions' ||
            table == 'temperature_readings') {
          return [
            {'name': table},
          ];
        }
        return [];
      });

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
      expect(joinedSql, contains("chartPointsJson TEXT NOT NULL DEFAULT '[]'"));
      expect(
        joinedSql,
        isNot(contains('CREATE TABLE IF NOT EXISTS govee_place_readings')),
      );
      expect(joinedSql, isNot(contains('govee_spot_captures')));
      expect(joinedSql, isNot(contains('govee_spot_readings')));
      expect(joinedSql, isNot(contains('spotCount')));
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
    when(() => db.rawQuery(any(), any())).thenAnswer((invocation) async {
      final args = invocation.positionalArguments[1] as List<Object?>;
      final table = args.single?.toString();
      if (table == 'station_samples' || table == 'sample_records') {
        return [
          {'name': table},
        ];
      }
      return [];
    });

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
    'v24 migration normalizes legacy Govee place values before v25 rebuild',
    () async {
      final db = await _openInMemoryDatabase();
      addTearDown(db.close);
      await _createLegacyGoveeV23Tables(db);
      await _insertLegacyGoveeFixture(
        db,
        captureId: 'capture-setter-room',
        place: 'incubatorRoom',
      );

      await DatabaseHelper().applyV24UpgradeForTest(db);

      final captures = await db.query('govee_daily_captures');
      expect(captures.single['place'], 'setterRoom');
    },
  );

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

      final placeReadingTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'govee_place_readings'",
      );
      expect(placeReadingTables, isEmpty);
      expect(captures.single['chartPointsJson'], '[]');
    },
  );

  test(
    'v26 migration preserves Govee captures while removing legacy detail tables',
    () async {
      final db = await _openInMemoryDatabase();
      addTearDown(db.close);
      await _createLegacyGoveeV23Tables(db);
      await _insertLegacyGoveeFixture(
        db,
        captureId: 'capture-demo',
        place: 'eggStorageRoom',
      );

      await DatabaseHelper().applyV26UpgradeForTest(db);

      final captures = await db.query('govee_daily_captures');
      final placeReadingTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'govee_place_readings'",
      );
      final columns = await db.rawQuery(
        "PRAGMA table_info('govee_daily_captures')",
      );

      expect(captures, hasLength(1));
      expect(captures.single['id'], 'capture-demo');
      expect(captures.single['place'], 'eggStorageRoom');
      expect(captures.single['stationKey'], 'egg');
      expect(captures.single['startedAt'], '2026-05-02T10:00:00.000');
      expect(captures.single['endedAt'], '2026-05-02T10:15:00.000');
      expect(placeReadingTables, isEmpty);
      expect(columns.map((row) => row['name']), contains('chartPointsJson'));
    },
  );

  test(
    'v26 migration preserves Govee captures through v24 to current upgrade path',
    () async {
      final db = await _openInMemoryDatabase();
      addTearDown(db.close);
      await _createLegacyGoveeV23Tables(db);
      await _insertLegacyGoveeFixture(
        db,
        captureId: 'capture-upgrade-path',
        place: 'incubatorRoom',
      );

      await DatabaseHelper().applyV24UpgradeForTest(db);
      await DatabaseHelper().applyV25UpgradeForTest(db);
      await DatabaseHelper().applyV26UpgradeForTest(db);
      await DatabaseHelper().applyV27UpgradeForTest(db);
      await DatabaseHelper().applyV28UpgradeForTest(db);
      await DatabaseHelper().applyV29UpgradeForTest(db);
      await DatabaseHelper().applyV30UpgradeForTest(db);
      await DatabaseHelper().applyV31UpgradeForTest(db);
      await DatabaseHelper().applyV32UpgradeForTest(db);

      final captures = await db.query(
        'govee_daily_captures',
        where: 'id = ?',
        whereArgs: ['capture-upgrade-path'],
      );
      expect(captures, hasLength(1));
      expect(captures.single['place'], 'setterRoom');
      expect(captures.single['stationKey'], 'setters');
      expect(captures.single['readingCount'], 1);
    },
  );

  test('v27 migration removes obsolete Govee tables and audit fields', () async {
    final db = await _openInMemoryDatabase();
    addTearDown(db.close);
    await db.execute('''CREATE TABLE audits (
      id TEXT PRIMARY KEY,
      customerId TEXT,
      flockId TEXT,
      auditType TEXT,
      date TEXT,
      hatchNumber INTEGER NOT NULL DEFAULT 1,
      setterId TEXT,
      hatcherId TEXT,
      sessionId TEXT,
      chaGoveeConnected INTEGER,
      soGoveeConnected INTEGER,
      soGoveeTemp REAL,
      soGoveeHumidity REAL,
      hoGoveeConnected INTEGER,
      hoGoveeTemp REAL,
      hoGoveeHumidity REAL,
      esGoveeConnected INTEGER,
      esGoveeTemp REAL,
      esGoveeHumidity REAL,
      customKeep TEXT
    )''');
    await db.execute('''CREATE TABLE photos (
      id TEXT PRIMARY KEY,
      auditId TEXT
    )''');
    await db.execute('''CREATE TABLE flocks (
      id TEXT PRIMARY KEY,
      customerId TEXT,
      status TEXT
    )''');
    await db.execute('CREATE TABLE govee_place_readings (id TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE govee_spot_captures (id TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE govee_spot_readings (id TEXT PRIMARY KEY)');
    await db.insert('audits', {
      'id': 'audit-1',
      'customerId': 'customer-1',
      'flockId': 'flock-1',
      'auditType': 'Setters',
      'date': '2026-05-08',
      'hatchNumber': 1,
      'setterId': 'setter-1',
      'hatcherId': null,
      'sessionId': 'session-1',
      'soGoveeTemp': 99.7,
      'customKeep': 'still-here',
    });

    await DatabaseHelper().applyV27UpgradeForTest(db);

    final auditColumns = await db.rawQuery("PRAGMA table_info('audits')");
    final auditColumnNames = auditColumns.map((row) => row['name']).toSet();
    expect(auditColumnNames, contains('customKeep'));
    expect(auditColumnNames, isNot(contains('chaGoveeConnected')));
    expect(auditColumnNames, isNot(contains('soGoveeConnected')));
    expect(auditColumnNames, isNot(contains('soGoveeTemp')));
    expect(auditColumnNames, isNot(contains('soGoveeHumidity')));
    expect(auditColumnNames, isNot(contains('hoGoveeConnected')));
    expect(auditColumnNames, isNot(contains('hoGoveeTemp')));
    expect(auditColumnNames, isNot(contains('hoGoveeHumidity')));
    expect(auditColumnNames, isNot(contains('esGoveeConnected')));
    expect(auditColumnNames, isNot(contains('esGoveeTemp')));
    expect(auditColumnNames, isNot(contains('esGoveeHumidity')));

    final audits = await db.query('audits');
    expect(audits.single['customKeep'], 'still-here');

    final legacyTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('govee_place_readings', 'govee_spot_captures', 'govee_spot_readings')",
    );
    expect(legacyTables, isEmpty);
  });

  test('v28 migration removes legacy temperature session tables', () async {
    final db = await _openInMemoryDatabase();
    addTearDown(db.close);
    await db.execute('''CREATE TABLE temperature_sessions (
      id TEXT PRIMARY KEY,
      customerId TEXT,
      hatcheryId TEXT,
      activePlace TEXT,
      status TEXT,
      createdAt TEXT
    )''');
    await db.execute('''CREATE TABLE temperature_readings (
      id TEXT PRIMARY KEY,
      sessionId TEXT,
      temperatureFahrenheit REAL,
      humidity REAL
    )''');
    await db.insert('temperature_sessions', {
      'id': 'session-1',
      'customerId': 'customer-1',
      'hatcheryId': 'hatchery-1',
      'activePlace': 'setterRoom',
      'status': 'completed',
      'createdAt': '2026-05-08T12:00:00.000',
    });
    await db.insert('temperature_readings', {
      'id': 'reading-1',
      'sessionId': 'session-1',
      'temperatureFahrenheit': 99.7,
      'humidity': 55.0,
    });

    await DatabaseHelper().applyV28UpgradeForTest(db);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('temperature_sessions', 'temperature_readings')",
    );
    expect(tables, isEmpty);
  });

  test('v29 migration rebuilds egg breakout BMKs to cleaned fields', () async {
    final db = await _openInMemoryDatabase();
    addTearDown(db.close);
    await db.execute('''CREATE TABLE bmk_egg_breakout (
      id TEXT PRIMARY KEY,
      ageWeek INTEGER NOT NULL UNIQUE,
      infertilePct REAL DEFAULT 0.0,
      early24hPct REAL DEFAULT 0.0,
      early48hPct REAL DEFAULT 0.0,
      bloodRingPct REAL DEFAULT 0.0,
      blackEyePct REAL DEFAULT 0.0,
      midDeadPct REAL DEFAULT 0.0,
      lateDeadPct REAL DEFAULT 0.0,
      pippedInternalPct REAL DEFAULT 0.0,
      pippedExternalPct REAL DEFAULT 0.0,
      explodedPct REAL DEFAULT 0.0,
      mushyPct REAL DEFAULT 0.0,
      contamPct REAL DEFAULT 0.0,
      cullPct REAL DEFAULT 0.0,
      seeperPct REAL DEFAULT 0.0,
      otherPct REAL DEFAULT 0.0,
      feathersPct REAL DEFAULT 0.0,
      turnedPct REAL DEFAULT 0.0,
      exposedBrainPct REAL DEFAULT 0.0,
      crossedBeakPct REAL DEFAULT 0.0,
      crackedPct REAL DEFAULT 0.0,
      earlyDeadPct REAL DEFAULT 0.0,
      midBlackEyePct REAL DEFAULT 0.0,
      internalPipPct REAL DEFAULT 0.0,
      externalPipPct REAL DEFAULT 0.0
    )''');
    await db.insert('bmk_egg_breakout', {
      'id': 'eb-old-65',
      'ageWeek': 65,
      'infertilePct': 99.0,
      'turnedPct': 99.0,
    });

    await DatabaseHelper().applyV29UpgradeForTest(db);

    final columnRows = await db.rawQuery(
      "PRAGMA table_info('bmk_egg_breakout')",
    );
    final columnNames = columnRows.map((row) => row['name']).toSet();
    expect(
      columnNames,
      containsAll([
        'id',
        'ageWeek',
        'infertilePct',
        'early24hPct',
        'early48hPct',
        'bloodRingPct',
        'blackEyePct',
        'earlyDeadPct',
        'midDeadPct',
        'lateDeadPct',
        'externalPipPct',
        'crackedPct',
        'contamPct',
      ]),
    );
    expect(columnNames, isNot(contains('pippedInternalPct')));
    expect(columnNames, isNot(contains('pippedExternalPct')));
    expect(columnNames, isNot(contains('explodedPct')));
    expect(columnNames, isNot(contains('mushyPct')));
    expect(columnNames, isNot(contains('cullPct')));
    expect(columnNames, isNot(contains('seeperPct')));
    expect(columnNames, isNot(contains('otherPct')));
    expect(columnNames, isNot(contains('feathersPct')));
    expect(columnNames, isNot(contains('turnedPct')));
    expect(columnNames, isNot(contains('internalPipPct')));
    expect(columnNames, isNot(contains('exposedBrainPct')));
    expect(columnNames, isNot(contains('crossedBeakPct')));

    final young = await db.query(
      'bmk_egg_breakout',
      where: 'ageWeek = ?',
      whereArgs: [25],
      limit: 1,
    );
    expect(young.single['infertilePct'], 6.0);
    expect(young.single['earlyDeadPct'], 5.5);
    expect(young.single['midDeadPct'], 1.0);
    expect(young.single['externalPipPct'], 1.0);

    final peak = await db.query(
      'bmk_egg_breakout',
      where: 'ageWeek = ?',
      whereArgs: [31],
      limit: 1,
    );
    expect(peak.single['infertilePct'], 2.5);
    expect(peak.single['early24hPct'], 0.5);
    expect(peak.single['early48hPct'], 1.0);
    expect(peak.single['bloodRingPct'], 2.0);
    expect(peak.single['blackEyePct'], 0.5);

    final aboveSixty = await db.query(
      'bmk_egg_breakout',
      where: 'ageWeek = ?',
      whereArgs: [65],
      limit: 1,
    );
    expect(aboveSixty.single['infertilePct'], 8.0);
    expect(aboveSixty.single['earlyDeadPct'], 4.5);
    expect(aboveSixty.single['crackedPct'], 1.0);
    expect(aboveSixty.single['contamPct'], 1.0);
  });

  test('v30 migration adds incubation hour columns to audits', () async {
    final db = await _openInMemoryDatabase();
    addTearDown(db.close);
    await db.execute('''CREATE TABLE audits (
      id TEXT PRIMARY KEY,
      soIncubationAge INTEGER,
      hoIncubationAge INTEGER
    )''');

    await DatabaseHelper().applyV30UpgradeForTest(db);

    final columnRows = await db.rawQuery("PRAGMA table_info('audits')");
    final columnNames = columnRows.map((row) => row['name']).toSet();
    expect(columnNames, contains('soIncubationHours'));
    expect(columnNames, contains('hoIncubationHours'));

    await db.insert('audits', {
      'id': 'audit-1',
      'soIncubationAge': 10,
      'soIncubationHours': 12,
      'hoIncubationAge': 19,
      'hoIncubationHours': 6,
    });
    final rows = await db.query(
      'audits',
      where: 'id = ?',
      whereArgs: ['audit-1'],
    );
    expect(rows.single['soIncubationHours'], 12);
    expect(rows.single['hoIncubationHours'], 6);
  });

  test(
    'v31 migration copies legacy station samples into normalized tables before dropping legacy table',
    () async {
      final db = await _openInMemoryDatabase();
      addTearDown(db.close);
      await _createStationSampleMigrationParents(db);
      await _createLegacyStationSamplesV30Table(db);
      await _insertLegacyStationSampleFixture(db);

      await DatabaseHelper().applyV31UpgradeForTest(db);
      await DatabaseHelper().applyV32UpgradeForTest(db);

      final records = await db.query('sample_records');
      expect(records, hasLength(1));
      final record = records.single;
      expect(record['id'], 'legacy-sample-1');
      expect(record['auditSessionId'], 'session-legacy');
      expect(record['legacyAuditId'], 'audit-legacy');
      expect(record['stationType'], 'chicks');
      expect(record['sectorType'], StationSampleModel.sectorChickQuality);
      expect(record['sampleKind'], StationSampleModel.sampleKindMachine);
      expect(record['sampleMode'], StationSampleModel.sampleModeComparison);
      expect(
        record['comparisonType'],
        StationSampleModel.comparisonTypeMachine,
      );
      expect(record['sampleIndex'], 2);
      expect(record['sampleLabel'], 'Machine 2');
      expect(
        record['sampleType'],
        StationSampleModel.sampleTypeChickQualityHatchedBatch,
      );
      expect(record['groupKey'], 'machine-group-1');
      expect(record['groupLabel'], 'Machine comparison');
      expect(record['calculatedBmkAgeDays'], 280);
      expect(record['benchmarkBreed'], 'Ross 308');
      expect(record['benchmarkAgeDays'], 280);
      expect(record['benchmarkSource'], 'legacy-bmk');
      expect(record['benchmarkSnapshotJson'], '{"breed":"Ross 308"}');
      expect(record['resultSummaryJson'], '{"avg":42.5}');
      expect(record['notes'], 'legacy station note');

      final house = await db.query('sample_house_details');
      expect(house.single['sampleRecordId'], 'legacy-sample-1');
      expect(house.single['houseNo'], 'H-2');
      expect(house.single['houseLabel'], 'House 2');

      final machine = await db.query('sample_machine_details');
      expect(machine.single['sampleRecordId'], 'legacy-sample-1');
      expect(machine.single['setterNo'], 'Setter 2');
      expect(machine.single['hatcherNo'], 'Hatcher 2');

      final batch = await db.query('sample_batch_details');
      expect(batch.single['sampleRecordId'], 'legacy-sample-1');
      expect(batch.single['batchNo'], 'Batch 2');
      expect(batch.single['hatchNo'], '2');
      expect(batch.single['storageDays'], 4);
      expect(batch.single['incubationDay'], 18);

      final timing = await db.query('sample_timing_details');
      expect(timing.single['sampleRecordId'], 'legacy-sample-1');
      expect(timing.single['eggProductionDate'], '2026-05-01T00:00:00.000');
      expect(timing.single['settingDate'], '2026-05-05T00:00:00.000');
      expect(timing.single['hatchDate'], '2026-05-26T00:00:00.000');

      final legacyTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'station_samples'",
      );
      expect(legacyTables, isEmpty);
    },
  );

  test(
    'v32 upgrade creates panel-owned sample tables and preserves legacy samples',
    () async {
      final db = await _openInMemoryDatabase();
      addTearDown(db.close);
      await db.execute('CREATE TABLE sample_records (id TEXT PRIMARY KEY)');

      await DatabaseHelper().applyV32UpgradeForTest(db);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
      );
      final names = tables.map((row) => row['name']).cast<String>().toSet();

      expect(names, contains('sample_records'));
      expect(names, contains('chick_pasgar'));
      expect(names, contains('chick_pasgar_samples'));
      expect(names, contains('egg_quality'));
      expect(names, contains('egg_quality_samples'));
      expect(names, contains('residue_breakout'));
      expect(names, contains('residue_breakout_samples'));

      final sampleColumns = await db.rawQuery(
        "PRAGMA table_info('residue_breakout_samples')",
      );
      final sampleColumnNames = sampleColumns.map((row) => row['name']).toSet();
      expect(
        sampleColumnNames,
        containsAll([
          'scopeType',
          'scopeLabel',
          'houseId',
          'setterId',
          'hatcherId',
          'trolleyId',
          'trayId',
          'summaryJson',
          'rawJson',
        ]),
      );
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
