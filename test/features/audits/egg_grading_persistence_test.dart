import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/activity_log_repository.dart';
import 'package:hatchaudit/data/repositories/egg_grading_repository.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/features/audits/logic/egg_station_reconstruction.dart';
import 'package:hatchaudit/features/audits/models/egg_grading.dart';
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
  if (!PanelSampleSchema.idKeyedPanelTables.contains(tableName)) {
    await db.execute(
      "CREATE UNIQUE INDEX idx_${tableName}_unique_row ON $tableName (sessionId, IFNULL(house, ''), IFNULL(setter, ''), IFNULL(hatcher, ''), IFNULL(trolley, ''), IFNULL(tray, ''), IFNULL(position, ''))",
    );
  }
}

Future<void> _createEggQualityDefectCountsTable(Database db) async {
  await db.execute('''CREATE TABLE egg_quality_defect_counts (
    id TEXT PRIMARY KEY,
    eggQualityId TEXT NOT NULL,
    sessionId TEXT NOT NULL,
    customerId TEXT NOT NULL,
    flockId TEXT,
    hatcheryId TEXT,
    date TEXT NOT NULL,
    scopeType TEXT,
    houseKey TEXT,
    sampleLabel TEXT,
    defectCode TEXT NOT NULL,
    defectCategory TEXT,
    isReject INTEGER,
    count INTEGER NOT NULL DEFAULT 0,
    pctOfSample REAL,
    notes TEXT,
    sortOrder INTEGER NOT NULL DEFAULT 0,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT
  )''');
  await db.execute(
    'CREATE UNIQUE INDEX idx_egg_quality_defect_counts_unique '
    'ON egg_quality_defect_counts (eggQualityId, defectCode)',
  );
}

void main() {
  late Database db;
  late _MockDatabaseHelper databaseHelper;
  late _MockActivityLogRepository activityLogRepository;
  late PanelSampleRepository panelSampleRepository;
  late AuditProvider provider;

  final user = UserModel(
    id: 'auditor-egg-grading',
    fullName: 'Egg Grading Auditor',
    email: 'egg-grading-auditor@example.com',
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
    await _createEggQualityDefectCountsTable(db);

    await db.insert('customers', {'id': 'customer-egg-grading'});
    await db.insert('flocks', {
      'id': 'flock-egg-grading',
      'customerId': 'customer-egg-grading',
    });
    await db.insert('hatcheries', {
      'id': 'hatchery-egg-grading',
      'customerId': 'customer-egg-grading',
      'name': 'Egg Grading Hatchery',
    });
    await db.insert('audit_sessions', {
      'id': 'session-egg-db',
      'customerId': 'customer-egg-grading',
      'flockId': 'flock-egg-grading',
      'hatcheryId': 'hatchery-egg-grading',
      'date': '2026-05-15',
    });

    panelSampleRepository = PanelSampleRepository(
      databaseHelper: databaseHelper,
    );
    provider = AuditProvider(
      panelSampleRepository: panelSampleRepository,
      activityLogRepository: activityLogRepository,
      eggGradingRepository: EggGradingRepository(
        databaseHelper: databaseHelper,
      ),
      autosaveEnabled: false,
    );
    provider.initialize(
      AuditContext(
        auditType: 'Egg',
        customerId: 'customer-egg-grading',
        flockId: 'flock-egg-grading',
        hatcheryId: 'hatchery-egg-grading',
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

  test(
    'grading is saved per sample and does not bleed between houses',
    () async {
      provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
      provider.updateSampleMetadata({'houseNo': 'H1', 'houseLabel': 'House 1'});
      provider.updateField('esGradingSampleSize', 100);
      provider.updateField('esGradingRejectedCount', 9);
      provider.updateGradingCounts({'dirty': 4, 'cracked': 3});

      provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
      provider.updateSampleMetadata({'houseNo': 'H2', 'houseLabel': 'House 2'});
      provider.updateField('esGradingSampleSize', 100);
      provider.updateField('esGradingRejectedCount', 2);
      provider.updateGradingCounts({'wrinkled': 2});

      expect(await provider.saveSamplesWithResult(tabIndex: 0), isTrue);

      final panels = await db.query('egg_quality', orderBy: 'sampleIndex ASC');
      expect(panels.map((r) => r['gradingRejectedCount']), [9, 2]);
      expect(panels.map((r) => r['gradingAcceptableCount']), [91, 98]);
      expect(panels.first['gradingTopDefectCode'], 'dirty');

      final counts = await db.query(
        'egg_quality_defect_counts',
        orderBy: 'eggQualityId ASC, defectCode ASC',
      );
      expect(counts, hasLength(3));
      expect(
        counts
            .where((r) => r['eggQualityId'] == panels.first['id'])
            .map((r) => r['defectCode']),
        ['cracked', 'dirty'],
      );
    },
  );

  Future<void> gradeTwoHouses() async {
    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.updateSampleMetadata({'houseNo': 'H1', 'houseLabel': 'House 1'});
    provider.updateField('esGradingSampleSize', 100);
    provider.updateField('esGradingRejectedCount', 9);
    provider.updateGradingCounts({'dirty': 4, 'cracked': 3});
    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.updateSampleMetadata({'houseNo': 'H2', 'houseLabel': 'House 2'});
    provider.updateField('esGradingSampleSize', 100);
    provider.updateField('esGradingRejectedCount', 2);
    provider.updateGradingCounts({'wrinkled': 2});
    expect(await provider.saveSamplesWithResult(tabIndex: 0), isTrue);
  }

  test('reopen restores grading for every sample', () async {
    await gradeTwoHouses();
    final reopened = await reopenEggStation(db, 'session-egg-db');
    expect(reopened.stationAudits.map((a) => a.esGradingRejectedCount), [9, 2]);
    final restored = EggGradingSummary.fromJson(
      reopened.stationAudits.first.esGradingDefectsJson,
      sampleSize: 100,
      rejectedCount: 9,
    );
    expect(restored.counts, {'dirty': 4, 'cracked': 3});
  });

  test(
    'a panel row without child rows falls back to its JSON mirror',
    () async {
      await gradeTwoHouses();
      await db.delete('egg_quality_defect_counts');

      final reopened = await reopenEggStation(db, 'session-egg-db');
      final restored = EggGradingSummary.fromJson(
        reopened.stationAudits.first.esGradingDefectsJson,
        sampleSize: 100,
        rejectedCount: 9,
      );
      expect(restored.counts, {'dirty': 4, 'cracked': 3});
    },
  );

  test('removing a sample removes its grading rows', () async {
    await gradeTwoHouses();
    provider.switchSample(1);
    provider.removeActiveEggQualityScopeSample(
      StationSampleModel.sampleKindHouse,
    );
    expect(await provider.saveSamplesWithResult(tabIndex: 0), isTrue);

    // orderBy added for determinism: a bare SELECT with no ORDER BY has no
    // guaranteed row order in SQLite, so this asserts only the meaningful
    // fact — H2's 'wrinkled' row is gone, H1's two rows survive — sorted so
    // the assertion is stable regardless of physical row order.
    final counts = await db.query(
      'egg_quality_defect_counts',
      orderBy: 'defectCode ASC',
    );
    expect(counts.map((r) => r['defectCode']), ['cracked', 'dirty']);
    expect(await db.query('sync_tombstones'), isNotEmpty);
  });

  // Reviewer finding (Critical, post-8889bf5): H1 is graded (grading data is
  // its only meaningful egg_quality signal), H2 gets plain quality data
  // (esEggSampleSize, not grading). Clearing H1's grading down to nothing
  // makes H1's whole egg_quality row non-meaningful while H2 stays meaningful
  // — H1's egg_quality row is now pruned by
  // `_pruneStalePanelHierarchyRowsForTable`, not by
  // `_deleteEggQualityRowsBySessionId` (which only fires when *no* sample in
  // the session has meaningful quality data). Before the fix, that prune path
  // deleted the parent row without going through `EggGradingRepository`, so
  // H1's `egg_quality_defect_counts` rows were left behind with no tombstone
  // queued for them — dead weight locally, and a batch PostgREST would
  // reject if it round-tripped that pending child row against an already
  // uploaded delete of its parent.
  test('clearing one house grading does not orphan its child rows', () async {
    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.updateSampleMetadata({'houseNo': 'H1', 'houseLabel': 'House 1'});
    provider.updateField('esGradingSampleSize', 100);
    provider.updateField('esGradingRejectedCount', 9);
    provider.updateGradingCounts({'dirty': 4, 'cracked': 3});

    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.updateSampleMetadata({'houseNo': 'H2', 'houseLabel': 'House 2'});
    provider.updateField('esEggSampleSize', 5);

    expect(await provider.saveSamplesWithResult(tabIndex: 0), isTrue);

    final beforeCounts = await db.query('egg_quality_defect_counts');
    expect(beforeCounts, hasLength(2));

    provider.switchSample(0);
    provider.updateField('esGradingSampleSize', null);
    provider.updateField('esGradingRejectedCount', null);
    provider.updateGradingCounts({});

    expect(await provider.saveSamplesWithResult(tabIndex: 0), isTrue);

    final afterCounts = await db.query('egg_quality_defect_counts');
    expect(afterCounts, isEmpty);

    final tombstones = await db.query(
      'sync_tombstones',
      where: 'tableName = ?',
      whereArgs: ['egg_quality_defect_counts'],
    );
    expect(tombstones, isNotEmpty);
  });

  // Reviewer finding (Important, post-8889bf5): every earlier test's child
  // rows agreed with the panel row's own `gradingDefectsJson` mirror, so
  // `_withGradingFromChildRows` could be deleted from
  // `egg_station_reconstruction.dart` without any test noticing. This test
  // deliberately makes them disagree — the panel row's JSON is overwritten to
  // a different, wrong defect set after saving, simulating a panel row pulled
  // from the cloud whose own JSON has gone stale relative to its (more
  // current) child rows — and asserts the child rows win.
  test('reopen prefers child rows over a stale panel JSON mirror', () async {
    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.updateSampleMetadata({'houseNo': 'H1', 'houseLabel': 'House 1'});
    provider.updateField('esGradingSampleSize', 100);
    provider.updateField('esGradingRejectedCount', 9);
    provider.updateGradingCounts({'dirty': 4, 'cracked': 3});
    expect(await provider.saveSamplesWithResult(tabIndex: 0), isTrue);

    final panelRow = (await db.query('egg_quality')).single;
    await db.update(
      'egg_quality',
      {
        'gradingDefectsJson': jsonEncode([
          {
            'code': 'wrinkled',
            'name': 'Wrinkled',
            'category': 'shell_quality',
            'isReject': true,
            'count': 99,
          },
        ]),
      },
      where: 'id = ?',
      whereArgs: [panelRow['id']],
    );

    final reopened = await reopenEggStation(db, 'session-egg-db');
    final restored = EggGradingSummary.fromJson(
      reopened.stationAudits.first.esGradingDefectsJson,
      sampleSize: 100,
      rejectedCount: 9,
    );
    expect(restored.counts, {'dirty': 4, 'cracked': 3});
  });

  test('clearing grading persists nulls while keeping egg weights', () async {
    provider.updateField('esEggWeights', jsonEncode([62.0, 63.0]));
    provider.updateField('esEggSampleSize', 2);
    provider.updateField('esEggAvgWeight', 62.5);
    provider.updateField('esGradingSampleSize', 100);
    provider.updateField('esGradingRejectedCount', 9);
    provider.updateGradingCounts({'dirty': 4});
    expect(await provider.saveSamplesWithResult(tabIndex: 0), isTrue);

    provider.updateField('esGradingSampleSize', null);
    provider.updateField('esGradingRejectedCount', null);
    provider.updateGradingCounts({});
    expect(await provider.saveSamplesWithResult(tabIndex: 0), isTrue);

    final panel = (await db.query('egg_quality')).single;
    for (final column in const [
      'gradingSampleSize',
      'gradingRejectedCount',
      'gradingAcceptableCount',
      'gradingRejectedPct',
      'gradingAcceptablePct',
      'gradingDefectsJson',
      'gradingTopDefectCode',
      'gradingTopDefectPct',
    ]) {
      expect(panel[column], isNull, reason: column);
    }
    expect(panel['eggWeightsJson'], jsonEncode([62.0, 63.0]));
    expect(await db.query('egg_quality_defect_counts'), isEmpty);

    final reopened = await reopenEggStation(db, 'session-egg-db');
    expect(reopened.stationAudits.single.esEggSampleSize, 2);
    expect(reopened.stationAudits.single.esEggAvgWeight, 62.5);
    expect(
      reopened.stationAudits.single.esEggWeights,
      jsonEncode([62.0, 63.0]),
    );
    expect(reopened.stationAudits.single.esGradingSampleSize, isNull);
    expect(reopened.stationAudits.single.esGradingRejectedCount, isNull);
    expect(reopened.stationAudits.single.esGradingDefectsJson, isNull);
  });

  test('explicit save rejects invalid grading without persistence', () async {
    provider.updateField('esEggSampleSize', 10);
    provider.updateField('esGradingSampleSize', 10);
    provider.updateField('esGradingRejectedCount', 11);

    expect(await provider.saveSamplesWithResult(tabIndex: 0), isFalse);
    expect(provider.activeDraft.esGradingRejectedCount, 11);
    expect(await db.query('egg_quality'), isEmpty);
    expect(await db.query('egg_quality_defect_counts'), isEmpty);
  });

  test(
    'autosave rejects an invalid defect count without persistence',
    () async {
      final autosaveProvider = AuditProvider(
        panelSampleRepository: panelSampleRepository,
        activityLogRepository: activityLogRepository,
        eggGradingRepository: EggGradingRepository(
          databaseHelper: databaseHelper,
        ),
        autosaveEnabled: true,
        autosaveDebounceDuration: const Duration(milliseconds: 1),
      );
      autosaveProvider.initialize(
        AuditContext(
          auditType: 'Egg',
          customerId: 'customer-egg-grading',
          flockId: 'flock-egg-grading',
          hatcheryId: 'hatchery-egg-grading',
          breed: 'Ross 308',
          flockAgeWeeks: 42,
          date: '2026-05-15',
        ),
        currentUser: user,
        sessionId: 'session-egg-db',
        notify: false,
      );
      autosaveProvider.updateField('esEggSampleSize', 10);
      autosaveProvider.updateField('esGradingSampleSize', 10);
      autosaveProvider.updateGradingCounts({'dirty': 11});

      expect(await autosaveProvider.flushAutosave(), isFalse);
      expect(autosaveProvider.activeGradingCounts, {'dirty': 11});
      expect(await db.query('egg_quality'), isEmpty);
      expect(await db.query('egg_quality_defect_counts'), isEmpty);
    },
  );

  test(
    'multiple defects may exceed the sample when each count is valid',
    () async {
      provider.updateField('esGradingSampleSize', 100);
      provider.updateField('esGradingRejectedCount', 40);
      provider.updateGradingCounts({'dirty': 60, 'cracked': 55});

      expect(await provider.saveSamplesWithResult(tabIndex: 0), isTrue);
      final rows = await db.query(
        'egg_quality_defect_counts',
        orderBy: 'defectCode ASC',
      );
      expect(rows.map((row) => row['count']), [55, 60]);
    },
  );
}
