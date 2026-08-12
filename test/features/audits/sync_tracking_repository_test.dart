import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/models/govee_capture_model.dart';
import 'package:hatchaudit/data/models/panel_sample_model.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

/// Real-SQLite (FFI) tests for the per-row dirty-tracking the sync engine relies
/// on. Tables are built by hand (with the new `dirtyAt` column) so there is no
/// seed-data pollution of the global dirty queries.
void main() {
  late Database db;
  late _MockDatabaseHelper dbHelper;
  late AuditSessionRepository sessionRepo;
  late PanelSampleRepository panelRepo;
  late GoveeCaptureRepository goveeRepo;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await _createSchema(db);
    dbHelper = _MockDatabaseHelper();
    when(() => dbHelper.db).thenAnswer((_) async => db);
    when(
      () => dbHelper.assertForeignKeys(
        customerId: any(named: 'customerId'),
        flockId: any(named: 'flockId'),
        hatcheryId: any(named: 'hatcheryId'),
      ),
    ).thenAnswer((_) async {});
    sessionRepo = AuditSessionRepository(dbHelper: dbHelper);
    panelRepo = PanelSampleRepository(databaseHelper: dbHelper);
    goveeRepo = GoveeCaptureRepository(dbHelper: dbHelper);
  });

  tearDown(() async => db.close());

  Future<Map<String, Object?>> sessionRow(String id) async =>
      (await db.query('audit_sessions', where: 'id = ?', whereArgs: [id])).single;

  group('audit session dirty tracking', () {
    test('insertSession marks the row pending with a dirtyAt', () async {
      await sessionRepo.insertSession(_session('s1'));
      final row = await sessionRow('s1');
      expect(row['syncStatus'], 'pending');
      expect(row['dirtyAt'], isNotNull);
    });

    test('a local edit re-dirties a previously synced session', () async {
      await sessionRepo.insertSession(_session('s1'));
      await sessionRepo.markSessionsSynced(['s1']);
      expect((await sessionRow('s1'))['syncStatus'], 'synced');

      await sessionRepo.markStationCompleted('s1', 'egg');
      final row = await sessionRow('s1');
      expect(row['syncStatus'], 'pending');
      expect(row['dirtyAt'], isNotNull);
    });

    test('upsertSessionRow (pull) marks the row synced, not dirty', () async {
      await sessionRepo.upsertSessionRow(_sessionMap('s2'));
      final row = await sessionRow('s2');
      expect(row['syncStatus'], 'synced');
      expect(row['lastSyncedAt'], isNotNull);
      expect(row['dirtyAt'], isNull);
    });

    test('getDirtySessionRows returns pending + failed, never synced', () async {
      await sessionRepo.insertSession(_session('pending')); // pending
      await sessionRepo.upsertSessionRow(_sessionMap('synced')); // synced
      await sessionRepo.insertSession(_session('failed'));
      await sessionRepo.markSessionsFailed(['failed'], 'boom');

      final dirty = (await sessionRepo.getDirtySessionRows())
          .map((s) => s.id)
          .toSet();
      expect(dirty, {'pending', 'failed'});

      final failedRow = await sessionRow('failed');
      expect(failedRow['syncStatus'], 'failed');
      expect(failedRow['syncError'], 'boom');
    });

    test('markSessionsSynced clears dirtyAt and error', () async {
      await sessionRepo.insertSession(_session('s1'));
      await sessionRepo.markSessionsFailed(['s1'], 'boom');
      await sessionRepo.markSessionsSynced(['s1']);
      final row = await sessionRow('s1');
      expect(row['syncStatus'], 'synced');
      expect(row['dirtyAt'], isNull);
      expect(row['syncError'], isNull);
    });
  });

  group('mark-synced race protection', () {
    test('a session edited mid-push stays pending after markSessionsSynced',
        () async {
      await sessionRepo.insertSession(_session('s1'));
      await sessionRepo.getDirtySessionRows();           // capture cutoff
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await sessionRepo.updateSession(_session('s1'));   // mid-push edit
      await sessionRepo.markSessionsSynced(['s1']);
      final row = await sessionRow('s1');
      expect(row['syncStatus'], 'pending');
      expect(row['dirtyAt'], isNotNull);
    });

    test('an unedited session is cleared by markSessionsSynced', () async {
      await sessionRepo.insertSession(_session('s1'));
      await sessionRepo.getDirtySessionRows();
      await sessionRepo.markSessionsSynced(['s1']);
      final row = await sessionRow('s1');
      expect(row['syncStatus'], 'synced');
    });
  });

  group('panel row dirty tracking', () {
    Future<Map<String, Object?>> panelRow(String id) async =>
        (await db.query('egg_storage', where: 'id = ?', whereArgs: [id])).single;

    test('savePanelWithSamples marks the panel row pending', () async {
      await panelRepo.savePanelWithSamples(
        panel: PanelRecord(
          id: 'p1',
          tableName: 'egg_storage',
          sessionId: 's1',
          customerId: 'c1',
          date: DateTime(2026, 5, 1),
        ),
        samples: const [],
      );
      final row = await panelRow('p1');
      expect(row['syncStatus'], 'pending');
      expect(row['dirtyAt'], isNotNull);
    });

    test('upsertPanelRow (pull) marks the panel row synced', () async {
      await panelRepo.upsertPanelRow('egg_storage', {
        'id': 'p2',
        'sessionId': 's1',
        'customerId': 'c1',
        'date': '2026-05-01',
        'createdAt': '2026-05-01T00:00:00.000Z',
        'updatedAt': '2026-05-01T00:00:00.000Z',
      });
      final row = await panelRow('p2');
      expect(row['syncStatus'], 'synced');
      expect(row['dirtyAt'], isNull);
      expect(row['lastSyncedAt'], isNotNull);
    });

    test('getDirtyRows + markRowsSynced/Failed transitions', () async {
      await db.insert('egg_storage', _eggRow('a', syncStatus: 'pending'));
      await db.insert('egg_storage', _eggRow('b', syncStatus: 'synced', house: 'H'));
      await db.insert('egg_storage', _eggRow('c', syncStatus: 'failed', house: 'I'));

      expect(
        (await panelRepo.getDirtyRows('egg_storage'))
            .map((r) => r['id'])
            .toSet(),
        {'a', 'c'},
      );

      await panelRepo.markRowsSynced('egg_storage', ['a']);
      expect((await panelRow('a'))['syncStatus'], 'synced');
      expect((await panelRow('a'))['dirtyAt'], isNull);

      await panelRepo.markRowsFailed('egg_storage', ['b'], 'net');
      final bRow = await panelRow('b');
      expect(bRow['syncStatus'], 'failed');
      expect(bRow['syncError'], 'net');
    });

    test(
        'a panel row edited mid-push stays pending after markRowsSynced',
        () async {
      final panel = PanelRecord(
        id: 'p1',
        tableName: 'egg_storage',
        sessionId: 's1',
        customerId: 'c1',
        date: DateTime(2026, 5, 1),
      );
      await panelRepo.savePanelWithSamples(panel: panel, samples: const []);
      await panelRepo.getDirtyRows('egg_storage'); // capture cutoff
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await panelRepo.savePanelWithSamples(
        panel: panel,
        samples: const [],
      ); // mid-push edit
      await panelRepo.markRowsSynced('egg_storage', ['p1']);
      final row = await panelRow('p1');
      expect(row['syncStatus'], 'pending');
      expect(row['dirtyAt'], isNotNull);
    });

    test('an unedited panel row is cleared by markRowsSynced', () async {
      final panel = PanelRecord(
        id: 'p1',
        tableName: 'egg_storage',
        sessionId: 's1',
        customerId: 'c1',
        date: DateTime(2026, 5, 1),
      );
      await panelRepo.savePanelWithSamples(panel: panel, samples: const []);
      await panelRepo.getDirtyRows('egg_storage');
      await panelRepo.markRowsSynced('egg_storage', ['p1']);
      final row = await panelRow('p1');
      expect(row['syncStatus'], 'synced');
    });
  });

  group('station rollup', () {
    test('aggregates per session, table, and sync status', () async {
      await db.insert('egg_storage', _eggRow('r1', syncStatus: 'pending'));
      await db.insert('egg_storage', _eggRow('r2', syncStatus: 'synced', house: 'H'));
      await db.insert('chick_quality', _eggRow('r3', syncStatus: 'failed'));

      final rollup = await panelRepo.getStationRollupForSessions(['s1']);
      expect(rollup['s1']!['egg_storage'], {'pending': 1, 'synced': 1});
      expect(rollup['s1']!['chick_quality'], {'failed': 1});
    });

    test('returns an empty map for unknown sessions', () async {
      final rollup = await panelRepo.getStationRollupForSessions(['ghost']);
      expect(rollup, isEmpty);
    });
  });

  group('govee dirty tracking', () {
    Future<Map<String, Object?>> goveeRow(String id) async =>
        (await db.query(
          'govee_daily_captures',
          where: 'id = ?',
          whereArgs: [id],
        )).single;

    GoveeDailyCaptureModel capture(
      String id, {
      TemperaturePlace place = TemperaturePlace.setterRoom,
    }) => GoveeDailyCaptureModel(
      id: id,
      customerId: 'c1',
      hatcheryId: 'h1',
      place: place,
      captureDate: '2026-05-01',
      status: 'completed',
      readingCount: 0,
      createdAt: DateTime(2026, 5, 1),
      updatedAt: DateTime(2026, 5, 1),
    );

    test('saveReplacement marks the capture pending', () async {
      await goveeRepo.saveReplacement(capture: capture('gc1'), readings: const []);
      final row = await goveeRow('gc1');
      expect(row['syncStatus'], 'pending');
      expect(row['dirtyAt'], isNotNull);
    });

    test('upsertCaptureRow (pull) marks the capture synced', () async {
      await goveeRepo.upsertCaptureRow(capture('gc2').toMap());
      final row = await goveeRow('gc2');
      expect(row['syncStatus'], 'synced');
      expect(row['dirtyAt'], isNull);
      expect(row['lastSyncedAt'], isNotNull);
    });

    test('getDirtyCaptureRows + mark transitions', () async {
      await goveeRepo.saveReplacement(capture: capture('a'), readings: const []);
      await goveeRepo.saveReplacement(
        capture: capture('b', place: TemperaturePlace.hatcherRoom),
        readings: const [],
      );
      await goveeRepo.markCapturesSynced(['b']);

      expect(
        (await goveeRepo.getDirtyCaptureRows()).map((c) => c.id).toSet(),
        {'a'},
      );

      await goveeRepo.markCapturesFailed(['a'], 'net');
      final aRow = await goveeRow('a');
      expect(aRow['syncStatus'], 'failed');
      expect(aRow['syncError'], 'net');
    });

    test('rollup aggregates captures by station and sync status', () async {
      await goveeRepo.saveReplacement(capture: capture('a'), readings: const []);
      await goveeRepo.saveReplacement(
        capture: capture('b', place: TemperaturePlace.hatcherRoom),
        readings: const [],
      );
      await goveeRepo.markCapturesSynced(['b']);

      final rollup = await goveeRepo.getGoveeRollupForSessions([
        (customerId: 'c1', hatcheryId: 'h1', captureDate: '2026-05-01'),
      ]);
      final byStation = rollup['c1|h1|2026-05-01']!;
      expect(byStation['setters'], {'pending': 1});
      expect(byStation['hatchers'], {'synced': 1});
    });

    test(
        'a capture edited mid-push stays pending after markCapturesSynced',
        () async {
      await goveeRepo.saveReplacement(
        capture: capture('gc1'),
        readings: const [],
      );
      await goveeRepo.getDirtyCaptureRows(); // capture cutoff
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await goveeRepo.saveReplacement(
        capture: capture('gc1'),
        readings: const [],
      ); // mid-push edit (re-recording keeps the same id)
      await goveeRepo.markCapturesSynced(['gc1']);
      final row = await goveeRow('gc1');
      expect(row['syncStatus'], 'pending');
      expect(row['dirtyAt'], isNotNull);
    });

    test('an unedited capture is cleared by markCapturesSynced', () async {
      await goveeRepo.saveReplacement(
        capture: capture('gc1'),
        readings: const [],
      );
      await goveeRepo.getDirtyCaptureRows();
      await goveeRepo.markCapturesSynced(['gc1']);
      final row = await goveeRow('gc1');
      expect(row['syncStatus'], 'synced');
    });
  });
}

AuditSessionModel _session(String id) => AuditSessionModel(
  id: id,
  customerId: 'c1',
  flockId: 'f1',
  hatcheryId: 'h1',
  date: DateTime(2026, 5, 1),
  createdAt: DateTime(2026, 5, 1),
  updatedAt: DateTime(2026, 5, 1),
);

Map<String, dynamic> _sessionMap(String id) => {
  'id': id,
  'customerId': 'c1',
  'flockId': 'f1',
  'hatcheryId': 'h1',
  'date': '2026-05-01T00:00:00.000',
  'createdAt': '2026-05-01T00:00:00.000',
  'updatedAt': '2026-05-01T00:00:00.000',
};

Map<String, Object?> _eggRow(
  String id, {
  required String syncStatus,
  String? house,
}) => {
  'id': id,
  'sessionId': 's1',
  'customerId': 'c1',
  'date': '2026-05-01',
  'house': house,
  'createdAt': '2026-05-01T00:00:00.000Z',
  'updatedAt': '2026-05-01T00:00:00.000Z',
  'syncStatus': syncStatus,
};

Future<void> _createSchema(Database db) async {
  await db.execute('''CREATE TABLE audit_sessions (
    id TEXT PRIMARY KEY,
    customerId TEXT NOT NULL,
    flockId TEXT NOT NULL,
    hatcheryId TEXT NOT NULL,
    date TEXT NOT NULL,
    breed TEXT,
    flockAgeWeeks INTEGER,
    status TEXT DEFAULT 'in_progress',
    selectedStationKeys TEXT,
    stationsCompleted TEXT,
    findingsJson TEXT,
    scorecardJson TEXT,
    notes TEXT,
    createdBy TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    completedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT
  )''');
  await db.execute('''CREATE TABLE sync_tombstones (
    id TEXT PRIMARY KEY,
    tableName TEXT NOT NULL,
    rowId TEXT NOT NULL,
    deletedAt TEXT NOT NULL,
    createdAt TEXT NOT NULL,
    syncedAt TEXT,
    lastError TEXT
  )''');
  for (final panel in PanelSampleSchema.panels) {
    await _createPanelTable(db, panel);
  }
  await db.execute('''CREATE TABLE govee_daily_captures (
    id TEXT PRIMARY KEY,
    customerId TEXT NOT NULL,
    hatcheryId TEXT NOT NULL,
    stationKey TEXT NOT NULL DEFAULT '',
    place TEXT NOT NULL,
    machineId TEXT NOT NULL DEFAULT '',
    captureDate TEXT NOT NULL,
    startedAt TEXT,
    endedAt TEXT,
    deviceId TEXT,
    deviceName TEXT,
    status TEXT NOT NULL,
    tempAvg REAL,
    tempMin REAL,
    tempMax REAL,
    tempSd REAL,
    tempCvPct REAL,
    rhAvg REAL,
    rhMin REAL,
    rhMax REAL,
    rhSd REAL,
    rhCvPct REAL,
    readingCount INTEGER NOT NULL,
    chartPointsJson TEXT NOT NULL DEFAULT '[]',
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    UNIQUE(customerId, hatcheryId, place, machineId, captureDate)
  )''');
}

Future<void> _createPanelTable(Database db, PanelSampleDefinition panel) async {
  final hierarchy = panel.hierarchyColumnDefinitions.join(',\n    ');
  final extra = panel.measurementColumns.isEmpty
      ? ''
      : ',\n    ${panel.measurementColumns.join(',\n    ')}';
  await db.execute('''CREATE TABLE ${panel.tableName} (
    id TEXT PRIMARY KEY,
    sessionId TEXT NOT NULL,
    customerId TEXT NOT NULL,
    flockId TEXT,
    hatcheryId TEXT,
    date TEXT NOT NULL,
    breed TEXT,
    flockAgeWeeks INTEGER,
    $hierarchy,
    storagePeriodDays INTEGER,
    bmkAgeWeeks INTEGER,
    notes TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT$extra
  )''');
  final indexCols = [
    'sessionId',
    ...panel.hierarchyColumnNames.map((c) => "IFNULL($c, '')"),
  ].join(', ');
  await db.execute(
    'CREATE UNIQUE INDEX idx_${panel.tableName}_unique_row '
    'ON ${panel.tableName} ($indexCols)',
  );
}
