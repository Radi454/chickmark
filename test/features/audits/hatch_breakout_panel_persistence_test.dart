import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
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
    bmkAgeDays INTEGER,
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
    expect(rows.map((row) => row['bmkAgeDays']), [269, 269]);
    expect(rows.map((row) => row['bmkAgeWeeks']), [39, 39]);
    expect(rows.map((row) => row['traySize']), [150, 150]);
    expect(rows.map((row) => row['infertileCount']), [15, 30]);
    expect(rows.map((row) => row['earlyDeadCount']), [9, 18]);
    expect(rows.map((row) => row['infertilePct']), [10.0, 20.0]);
    expect(rows.map((row) => row['earlyDeadPct']), [6.0, 12.0]);
    expect(rows.map((row) => row['infertileDiffPct']), [5.0, 15.0]);
    expect(rows.map((row) => row['earlyDeadDiffPct']), [2.0, 8.0]);
  });
}
