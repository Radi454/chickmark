import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/activity_log_repository.dart';
import 'package:hatchaudit/data/repositories/benchmark_lookup.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/features/audits/models/egg_breakout_sample.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

class _MockActivityLogRepository extends Mock
    implements ActivityLogRepository {}

class _MockBenchmarkLookup extends Mock implements BenchmarkLookup {}

Future<void> _createPanelTable(
  Database db,
  String tableName,
  List<String> extraColumns,
) async {
  final extra = extraColumns.isEmpty ? '' : ', ${extraColumns.join(', ')}';
  await db.execute('''CREATE TABLE $tableName (
    id TEXT PRIMARY KEY,
    sessionId TEXT NOT NULL,
    customerId TEXT NOT NULL,
    flockId TEXT,
    hatcheryId TEXT,
    date TEXT NOT NULL,
    breed TEXT,
    flockAgeWeeks INTEGER,
    house TEXT,
    setter TEXT,
    hatcher TEXT,
    trolley TEXT,
    tray TEXT,
    position TEXT,
    storagePeriodDays INTEGER,
    bmkAgeWeeks INTEGER,
    notes TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    lastSyncedAt TEXT,
    syncError TEXT$extra
  )''');
  await db.execute(
    "CREATE UNIQUE INDEX idx_${tableName}_unique_row ON $tableName (sessionId, IFNULL(house, ''), IFNULL(setter, ''), IFNULL(hatcher, ''), IFNULL(trolley, ''), IFNULL(tray, ''), IFNULL(position, ''))",
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late _MockDatabaseHelper databaseHelper;
  late _MockActivityLogRepository activityLogRepository;
  late _MockBenchmarkLookup benchmarkLookup;
  late AuditProvider provider;

  final user = UserModel(
    id: 'auditor-hatch-breakout-db',
    fullName: 'Hatch Breakout DB Auditor',
    email: 'hatch-breakout-db-auditor@example.com',
    role: 'auditor',
    status: 'approved',
    createdAt: DateTime(2026, 5, 18),
  );

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    databaseHelper = _MockDatabaseHelper();
    activityLogRepository = _MockActivityLogRepository();
    benchmarkLookup = _MockBenchmarkLookup();
    when(() => databaseHelper.db).thenAnswer((_) async => db);
    when(
      () => activityLogRepository.log(
        any(),
        any(),
        entityType: any(named: 'entityType'),
        entityId: any(named: 'entityId'),
        details: any(named: 'details'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => benchmarkLookup.nearestBreakoutBenchmark(
        calculatedBmkAgeDays: any(named: 'calculatedBmkAgeDays'),
      ),
    ).thenAnswer(
      (_) async => {
        'infertilePct': 5.0,
        'earlyDeadPct': 4.0,
        'midDeadPct': 1.0,
        'lateDeadPct': 2.5,
        'externalPipPct': 0.5,
        'crackedPct': 0.5,
        'contamPct': 0.5,
      },
    );

    await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY)');
    await db.execute('''CREATE TABLE flocks (
      id TEXT PRIMARY KEY,
      customerId TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE hatcheries (
      id TEXT PRIMARY KEY,
      customerId TEXT NOT NULL,
      name TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE audit_sessions (
      id TEXT PRIMARY KEY,
      customerId TEXT NOT NULL,
      flockId TEXT NOT NULL,
      hatcheryId TEXT NOT NULL,
      date TEXT NOT NULL
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
    final residuePanel = PanelSampleSchema.byTable('residue_breakout');
    await _createPanelTable(
      db,
      residuePanel.tableName,
      residuePanel.measurementColumns,
    );
    await db.insert('customers', {'id': 'customer-hatch-breakout-db'});
    await db.insert('flocks', {
      'id': 'flock-hatch-breakout-db',
      'customerId': 'customer-hatch-breakout-db',
    });
    await db.insert('hatcheries', {
      'id': 'hatchery-hatch-breakout-db',
      'customerId': 'customer-hatch-breakout-db',
      'name': 'Hatch Breakout DB Hatchery',
    });
    await db.insert('audit_sessions', {
      'id': 'session-hatch-breakout-db',
      'customerId': 'customer-hatch-breakout-db',
      'flockId': 'flock-hatch-breakout-db',
      'hatcheryId': 'hatchery-hatch-breakout-db',
      'date': '2026-05-18',
    });

    provider = AuditProvider(
      panelSampleRepository: PanelSampleRepository(
        databaseHelper: databaseHelper,
      ),
      activityLogRepository: activityLogRepository,
      benchmarkLookup: benchmarkLookup,
      autosaveEnabled: false,
    );
    provider.initialize(
      AuditContext(
        auditType: 'Hatch Analysis & Egg Breakouts',
        customerId: 'customer-hatch-breakout-db',
        flockId: 'flock-hatch-breakout-db',
        hatcheryId: 'hatchery-hatch-breakout-db',
        breed: 'Ross 308',
        flockAgeWeeks: 42,
        date: '2026-05-18',
      ),
      currentUser: user,
      sessionId: 'session-hatch-breakout-db',
      notify: false,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'residue breakout pooled station scope persists one blank hierarchy row',
    () async {
      provider.updateField(
        'ebBreakoutType',
        EggBreakoutType.residueHatchDay.storageValue,
      );
      provider.updateField('ebTraySize', 300);
      provider.updateField('ebInfertileCount', 12);

      expect(await provider.saveSamplesWithResult(), isTrue);

      final rows = await db.query('residue_breakout');

      expect(rows, hasLength(1));
      expect(rows.single['house'], isNull);
      expect(rows.single['setter'], isNull);
      expect(rows.single['hatcher'], isNull);
      expect(rows.single['trolley'], isNull);
      expect(rows.single['tray'], isNull);
      expect(rows.single['position'], isNull);
      expect(rows.single['infertileCount'], 12);
    },
  );

  test(
    'residue breakout house scope persists one row per open house',
    () async {
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.updateHatchField(0, 'houseId', 'House A');
      provider.updateHatchField(0, 'setterId', null);
      provider.updateHatchField(0, 'hatcherId', null);
      provider.updateHatchField(0, 'ebTraySize', 300);
      provider.updateHatchField(0, 'ebInfertileCount', 12);

      provider.addHatch();
      provider.updateHatchField(1, 'houseId', 'House B');
      provider.updateHatchField(1, 'setterId', null);
      provider.updateHatchField(1, 'hatcherId', null);
      provider.updateHatchField(1, 'ebTraySize', 300);
      provider.updateHatchField(1, 'ebInfertileCount', 18);

      expect(await provider.saveSamplesWithResult(), isTrue);

      final rows = await db.query('residue_breakout', orderBy: 'house ASC');

      expect(rows, hasLength(2));
      expect(rows.map((row) => row['house']), ['House A', 'House B']);
      expect(rows.every((row) => row['setter'] == null), isTrue);
      expect(rows.every((row) => row['hatcher'] == null), isTrue);
      expect(rows.every((row) => row['trolley'] == null), isTrue);
      expect(rows.every((row) => row['tray'] == null), isTrue);
      expect(rows.every((row) => row['position'] == null), isTrue);
      expect(rows.map((row) => row['infertileCount']), [12, 18]);
    },
  );

  test('residue breakout persists each tray as a separate table row', () async {
    provider.updateField(
      'ebTrayBreakoutJson',
      EggBreakoutSampleEntry.encodeList([
        EggBreakoutSampleEntry.tray(
          id: 'residue-tray-1',
          label: 'Tray 1',
          house: 'House A',
          setter: 'S1',
          hatcher: 'H1',
          trolley: 'T1',
          tray: 'Tray 1',
          position: 'top',
          traySize: 150,
          breakoutType: EggBreakoutType.residueHatchDay,
          counts: const {'infertile': 15, 'earlyDead': 9},
        ),
        EggBreakoutSampleEntry.tray(
          id: 'residue-tray-2',
          label: 'Tray 2',
          house: 'House A',
          setter: 'S1',
          hatcher: 'H1',
          trolley: 'T1',
          tray: 'Tray 2',
          position: 'bottom',
          traySize: 150,
          breakoutType: EggBreakoutType.residueHatchDay,
          counts: const {'infertile': 30, 'earlyDead': 18},
        ),
      ]),
    );
    provider.updateField(
      'ebBreakoutType',
      EggBreakoutType.residueHatchDay.storageValue,
    );
    provider.updateField('ebStorageDays', 4);
    provider.updateField('haStorageDays', 4);
    provider.updateField('setterId', 'S1');
    provider.updateField('hatcherId', 'H1');

    expect(await provider.saveSamplesWithResult(), isTrue);

    final rows = await db.query('residue_breakout', orderBy: 'tray ASC');

    expect(rows, hasLength(2));
    expect(rows.map((row) => row['house']), ['House A', 'House A']);
    expect(rows.map((row) => row['setter']), ['S1', 'S1']);
    expect(rows.map((row) => row['hatcher']), ['H1', 'H1']);
    expect(rows.map((row) => row['trolley']), ['T1', 'T1']);
    expect(rows.map((row) => row['tray']), ['Tray 1', 'Tray 2']);
    expect(rows.map((row) => row['position']), ['top', 'bottom']);
    expect(rows.map((row) => row['storagePeriodDays']), [4, 4]);
    for (final row in rows) {
      expect(row.keys, isNot(contains('bmkAgeDays')));
    }
    expect(rows.map((row) => row['bmkAgeWeeks']), [39, 39]);
    expect(rows.map((row) => row['traySize']), [150, 150]);
    expect(rows.map((row) => row['infertileCount']), [15, 30]);
    expect(rows.map((row) => row['earlyDeadCount']), [9, 18]);
    expect(rows.map((row) => row['infertilePct']), [10.0, 20.0]);
    expect(rows.map((row) => row['earlyDeadPct']), [6.0, 12.0]);
    expect(rows.map((row) => row['infertileDiffPct']), [5.0, 15.0]);
    expect(rows.map((row) => row['earlyDeadDiffPct']), [2.0, 8.0]);
  });

  test(
    'residue breakout machine scope persists setter and hatcher hierarchy',
    () async {
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.updateField('houseId', 'House A');
      provider.updateField('setterId', 'S1');
      provider.updateField('hatcherId', 'H1');
      provider.updateField(
        'ebBreakoutType',
        EggBreakoutType.residueHatchDay.storageValue,
      );
      provider.updateField('ebTraySize', 300);
      provider.updateField('ebInfertileCount', 12);

      expect(await provider.saveSamplesWithResult(), isTrue);

      final rows = await db.query('residue_breakout');

      expect(rows, hasLength(1));
      expect(rows.single['house'], 'House A');
      expect(rows.single['setter'], 'S1');
      expect(rows.single['hatcher'], 'H1');
      expect(rows.single['trolley'], isNull);
      expect(rows.single['tray'], isNull);
      expect(rows.single['position'], isNull);
    },
  );

  test(
    'residue breakout machine scope keeps open paths when only total eggs set is present',
    () async {
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.updateField(
        'ebBreakoutType',
        EggBreakoutType.residueHatchDay.storageValue,
      );

      final paths = [
        ('House A', 'S1', 'H1'),
        ('House A', 'S2', 'H2'),
        ('House B', 'S1', 'H1'),
        ('House B', 'S2', 'H2'),
      ];
      for (var index = 0; index < paths.length; index++) {
        if (index > 0) provider.addHatch();
        final (house, setter, hatcher) = paths[index];
        provider.updateHatchField(index, 'houseId', house);
        provider.updateHatchField(index, 'setterId', setter);
        provider.updateHatchField(index, 'hatcherId', hatcher);
      }

      expect(await provider.saveSamplesWithResult(), isTrue);

      final rows = await db.query(
        'residue_breakout',
        orderBy: 'house ASC, setter ASC, hatcher ASC',
      );

      expect(rows, hasLength(4));
      expect(
        rows.map(
          (row) => '${row['house']}|${row['setter']}|${row['hatcher']}',
        ),
        [
          'House A|S1|H1',
          'House A|S2|H2',
          'House B|S1|H1',
          'House B|S2|H2',
        ],
      );
      expect(rows.every((row) => row['trolley'] == null), isTrue);
      expect(rows.every((row) => row['tray'] == null), isTrue);
      expect(rows.every((row) => row['position'] == null), isTrue);
      expect(rows.map((row) => row['totalEggsSet']), [
        19200,
        19200,
        19200,
        19200,
      ]);
    },
  );

  test(
    'residue breakout trolley scope persists a trolley row under the selected machine',
    () async {
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.updateField('houseId', 'House A');
      provider.updateField('setterId', 'S1');
      provider.updateField('hatcherId', 'H1');
      provider.updateField(
        'ebBreakoutType',
        EggBreakoutType.residueHatchDay.storageValue,
      );
      provider.updateField(
        'ebTrayBreakoutJson',
        EggBreakoutSampleEntry.encodeList([
          EggBreakoutSampleEntry.pool(
            id: 'residue-trolley-1',
            label: 'Trolley T1',
            house: 'House A',
            setter: 'S1',
            hatcher: 'H1',
            trolley: 'T1',
            traySize: 150,
            numberOfTrays: 2,
            breakoutType: EggBreakoutType.residueHatchDay,
            counts: const {'infertile': 12, 'earlyDead': 6},
          ),
        ]),
      );

      expect(await provider.saveSamplesWithResult(), isTrue);

      final rows = await db.query('residue_breakout');

      expect(rows, hasLength(1));
      expect(rows.single['house'], 'House A');
      expect(rows.single['setter'], 'S1');
      expect(rows.single['hatcher'], 'H1');
      expect(rows.single['trolley'], 'T1');
      expect(rows.single['tray'], isNull);
      expect(rows.single['position'], isNull);
      expect(rows.single['traySize'], 300);
      expect(rows.single['infertileCount'], 12);
      expect(rows.single['earlyDeadCount'], 6);
    },
  );

  test(
    'residue breakout tray scope prunes stale pooled and parent hierarchy rows',
    () async {
      final now = DateTime.utc(2026, 5, 18).toIso8601String();
      Future<void> insertStaleRow({
        required String id,
        String? house,
        String? setter,
        String? hatcher,
        String? trolley,
      }) {
        return db.insert('residue_breakout', {
          'id': id,
          'sessionId': 'session-hatch-breakout-db',
          'customerId': 'customer-hatch-breakout-db',
          'flockId': 'flock-hatch-breakout-db',
          'hatcheryId': 'hatchery-hatch-breakout-db',
          'date': '2026-05-18',
          'breed': 'Ross 308',
          'house': house,
          'setter': setter,
          'hatcher': hatcher,
          'trolley': trolley,
          'traySize': 300,
          'infertileCount': 12,
          'createdAt': now,
          'updatedAt': now,
          'syncStatus': 'pending',
        });
      }

      await insertStaleRow(id: 'stale-pool');
      await insertStaleRow(id: 'stale-house', house: 'House A');
      await insertStaleRow(
        id: 'stale-machine',
        house: 'House A',
        setter: 'S1',
        hatcher: 'H1',
      );
      await insertStaleRow(
        id: 'stale-trolley',
        house: 'House A',
        setter: 'S1',
        hatcher: 'H1',
        trolley: 'T1',
      );

      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.updateField('houseId', 'House A');
      provider.updateField('setterId', 'S1');
      provider.updateField('hatcherId', 'H1');
      provider.updateField(
        'ebBreakoutType',
        EggBreakoutType.residueHatchDay.storageValue,
      );
      provider.updateField(
        'ebTrayBreakoutJson',
        EggBreakoutSampleEntry.encodeList([
          EggBreakoutSampleEntry.tray(
            id: 'residue-tray-1',
            label: 'Tray 1',
            house: 'House A',
            setter: 'S1',
            hatcher: 'H1',
            trolley: 'T1',
            tray: 'Tray 1',
            position: 'top',
            traySize: 150,
            breakoutType: EggBreakoutType.residueHatchDay,
            counts: const {'infertile': 15, 'earlyDead': 9},
          ),
        ]),
      );

      expect(await provider.saveSamplesWithResult(), isTrue);

      final rows = await db.query('residue_breakout');

      expect(rows, hasLength(1));
      expect(rows.single['house'], 'House A');
      expect(rows.single['setter'], 'S1');
      expect(rows.single['hatcher'], 'H1');
      expect(rows.single['trolley'], 'T1');
      expect(rows.single['tray'], 'Tray 1');
      expect(rows.single['position'], 'top');
      expect(rows.single['infertileCount'], 15);

      final tombstones = await db.query(
        'sync_tombstones',
        orderBy: 'rowId ASC',
      );
      expect(tombstones.map((row) => row['rowId']), [
        'stale-house',
        'stale-machine',
        'stale-pool',
        'stale-trolley',
      ]);
    },
  );

  test(
    'residue breakout saves only the narrowest active grain across open hierarchy paths',
    () async {
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.updateHatchField(0, 'houseId', 'House A');
      provider.updateHatchField(0, 'setterId', null);
      provider.updateHatchField(0, 'hatcherId', null);
      provider.updateHatchField(0, 'ebTraySize', 300);
      provider.updateHatchField(0, 'ebInfertileCount', 1);

      provider.addHatch();
      provider.updateHatchField(1, 'houseId', 'House B');
      provider.updateHatchField(1, 'setterId', null);
      provider.updateHatchField(1, 'hatcherId', null);
      provider.updateHatchField(1, 'ebTraySize', 300);
      provider.updateHatchField(1, 'ebInfertileCount', 1);

      var nextIndex = 2;
      for (final house in ['House A', 'House B']) {
        for (var machine = 1; machine <= 3; machine++) {
          provider.addHatch();
          final hatchIndex = provider.activeHatchIndex;
          final setter = 'S$machine';
          final hatcher = 'H$machine';
          provider.updateHatchField(hatchIndex, 'houseId', house);
          provider.updateHatchField(hatchIndex, 'setterId', setter);
          provider.updateHatchField(hatchIndex, 'hatcherId', hatcher);
          provider.updateHatchField(
            hatchIndex,
            'ebTrayBreakoutJson',
            EggBreakoutSampleEntry.encodeList([
              for (var trolley = 1; trolley <= 3; trolley++)
                for (var tray = 1; tray <= 3; tray++)
                  EggBreakoutSampleEntry.tray(
                    id: 'residue-$nextIndex-$trolley-$tray',
                    label: 'Tray $tray',
                    house: house,
                    setter: setter,
                    hatcher: hatcher,
                    trolley: 'T$trolley',
                    tray: 'Tray $tray',
                    position: 'P$tray',
                    traySize: 150,
                    breakoutType: EggBreakoutType.residueHatchDay,
                    counts: {'infertile': machine + trolley + tray},
                  ),
            ]),
          );
          nextIndex++;
        }
      }

      provider.updateField(
        'ebBreakoutType',
        EggBreakoutType.residueHatchDay.storageValue,
      );

      expect(await provider.saveSamplesWithResult(), isTrue);

      final rows = await db.query('residue_breakout');

      expect(rows, hasLength(54));
      expect(rows.every((row) => row['house'] != null), isTrue);
      expect(rows.every((row) => row['setter'] != null), isTrue);
      expect(rows.every((row) => row['hatcher'] != null), isTrue);
      expect(rows.every((row) => row['trolley'] != null), isTrue);
      expect(rows.every((row) => row['tray'] != null), isTrue);
      expect(rows.every((row) => row['position'] != null), isTrue);

      final houses = rows.map((row) => row['house']).toSet();
      final machinePaths = rows
          .map((row) => '${row['house']}|${row['setter']}|${row['hatcher']}')
          .toSet();
      final trolleyPaths = rows
          .map(
            (row) =>
                '${row['house']}|${row['setter']}|${row['hatcher']}|${row['trolley']}',
          )
          .toSet();
      final trayPaths = rows
          .map(
            (row) =>
                '${row['house']}|${row['setter']}|${row['hatcher']}|${row['trolley']}|${row['tray']}|${row['position']}',
          )
          .toSet();

      expect(houses, {'House A', 'House B'});
      expect(machinePaths, hasLength(6));
      expect(trolleyPaths, hasLength(18));
      expect(trayPaths, hasLength(54));
    },
  );
}
