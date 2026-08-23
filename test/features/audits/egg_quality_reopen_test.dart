import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/features/audits/logic/egg_station_reconstruction.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/activity_log_repository.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

class _MockActivityLogRepository extends Mock
    implements ActivityLogRepository {}

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
    sampleMode TEXT,
    scopeType TEXT,
    sampleLabel TEXT,
    sampleIndex INTEGER,
    sourceDomain TEXT,
    actionDomain TEXT,
    recommendationTarget TEXT,
    notes TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    lastSyncedAt TEXT,
    syncError TEXT$extra
  )''');
  // `egg_quality` is id-keyed (see `PanelSampleSchema.idKeyedPanelTables`):
  // a comparison row may legitimately share or blank its hierarchy tuple, so
  // the real schema (`database_schema.dart`, since v61) never creates this
  // unique index for it. Mirror that here so the two comparison rows in the
  // metadata test below don't collide and overwrite each other.
  if (!PanelSampleSchema.idKeyedPanelTables.contains(tableName)) {
    await db.execute(
      "CREATE UNIQUE INDEX idx_${tableName}_unique_row ON $tableName (sessionId, IFNULL(house, ''), IFNULL(setter, ''), IFNULL(hatcher, ''), IFNULL(trolley, ''), IFNULL(tray, ''), IFNULL(position, ''))",
    );
  }
}

void main() {
  late Database db;
  late _MockDatabaseHelper databaseHelper;
  late _MockActivityLogRepository activityLogRepository;
  late PanelSampleRepository panelSampleRepository;
  late AuditProvider provider;

  final user = UserModel(
    id: 'auditor-egg-db',
    fullName: 'Egg DB Auditor',
    email: 'egg-db-auditor@example.com',
    role: 'auditor',
    status: 'approved',
    createdAt: DateTime(2026, 5, 15),
  );

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    databaseHelper = _MockDatabaseHelper();
    activityLogRepository = _MockActivityLogRepository();
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
    for (final panel in PanelSampleSchema.panels.where(
      (panel) => {'egg_storage', 'egg_quality'}.contains(panel.tableName),
    )) {
      await _createPanelTable(db, panel.tableName, panel.measurementColumns);
    }
    await db.insert('customers', {'id': 'customer-egg-db'});
    await db.insert('flocks', {
      'id': 'flock-egg-db',
      'customerId': 'customer-egg-db',
    });
    await db.insert('hatcheries', {
      'id': 'hatchery-egg-db',
      'customerId': 'customer-egg-db',
      'name': 'Egg DB Hatchery',
    });
    await db.insert('audit_sessions', {
      'id': 'session-egg-db',
      'customerId': 'customer-egg-db',
      'flockId': 'flock-egg-db',
      'hatcheryId': 'hatchery-egg-db',
      'date': '2026-05-15',
    });

    panelSampleRepository = PanelSampleRepository(
      databaseHelper: databaseHelper,
    );
    provider = AuditProvider(
      panelSampleRepository: panelSampleRepository,
      activityLogRepository: activityLogRepository,
      autosaveEnabled: false,
    );
    provider.initialize(
      AuditContext(
        auditType: 'Egg',
        customerId: 'customer-egg-db',
        flockId: 'flock-egg-db',
        hatcheryId: 'hatchery-egg-db',
        breed: 'Ross 308',
        flockAgeWeeks: 42,
        date: '2026-05-15',
      ),
      currentUser: user,
      sessionId: 'session-egg-db',
      notify: false,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('reopen restores saved mode, scope, label and order', () async {
    provider.updateField('esEggSampleSize', 11);
    // Two calls to addEggQualityScopeSample are required to get a distinct
    // second house-scoped sample: the first call only switches the existing
    // single sample into comparison mode and stamps it with the 'H'
    // placeholder label (see AuditProvider.addEggQualityScopeSample, and the
    // identical comment in egg_station_panel_persistence_test.dart's "saved
    // egg_quality rows carry explicit sample and domain metadata" test,
    // which establishes this same two-call pattern). This test additionally
    // labels the first sample explicitly (real usage always replaces the
    // 'H' placeholder before saving) so both saved labels are distinct.
    //
    // The houses are deliberately picked out of alphabetical order (H9 saved
    // first at sampleIndex 1, H2 saved second at sampleIndex 2) so that
    // ordering by the saved `sampleIndex` (this task's change) produces a
    // different, checkable order than the old hierarchy-column-alphabetical
    // ordering would (which would list H2 before H9).
    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.updateSampleMetadata({'houseNo': 'H9', 'houseLabel': 'House 9'});
    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.updateSampleMetadata({'houseNo': 'H2', 'houseLabel': 'House 2'});
    provider.updateField('esEggSampleSize', 22);
    await provider.saveSamplesWithResult(tabIndex: 0);

    final reopened = await reopenEggStation(db, 'session-egg-db');

    expect(reopened.stationSamples.map((s) => s.sampleLabel), ['H9', 'H2']);
    expect(reopened.stationSamples.map((s) => s.sampleIndex), [1, 2]);
    expect(
      reopened.stationSamples.map((s) => s.sampleMode),
      ['comparison', 'comparison'],
    );
    expect(reopened.stationAudits.map((a) => a.esEggSampleSize), [11, 22]);
  });

  test('legacy rows with null metadata still reopen by inference', () async {
    await db.insert('egg_quality', {
      'id': 'legacy-1',
      'sessionId': 'session-egg-db',
      'customerId': 'customer-egg-db',
      'flockId': 'flock-egg-db',
      'date': '2026-05-15',
      'house': 'H3',
      'eggSampleSize': 44,
      'createdAt': '2026-05-15T00:00:00.000Z',
      'updatedAt': '2026-05-15T00:00:00.000Z',
    });

    final reopened = await reopenEggStation(db, 'session-egg-db');

    expect(reopened.stationSamples.single.sampleMode, 'comparison');
    expect(reopened.stationSamples.single.sampleKind, 'house');
    expect(reopened.stationSamples.single.sampleLabel, 'H3');
  });

  test('a blank-house comparison row does not reopen as pooled', () async {
    await db.insert('egg_quality', {
      'id': 'explicit-1',
      'sessionId': 'session-egg-db',
      'customerId': 'customer-egg-db',
      'flockId': 'flock-egg-db',
      'date': '2026-05-15',
      'house': null,
      'sampleMode': 'comparison',
      'scopeType': 'house',
      'sampleLabel': 'H1',
      'sampleIndex': 1,
      'eggSampleSize': 55,
      'createdAt': '2026-05-15T00:00:00.000Z',
      'updatedAt': '2026-05-15T00:00:00.000Z',
    });

    final reopened = await reopenEggStation(db, 'session-egg-db');

    expect(reopened.stationSamples.single.sampleMode, 'comparison');
    expect(reopened.stationSamples.single.sampleLabel, 'H1');
  });
}
