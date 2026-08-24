import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
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
    scopeType TEXT,
    storagePeriodDays INTEGER,
    bmkAgeWeeks INTEGER,
    notes TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    lastSyncedAt TEXT,
    syncError TEXT,
    ${kChickV2IdentityColumnDefinitions.join(',\n    ')},
    ${kChickV2QualityColumnDefinitions.join(',\n    ')}$extra
  )''');
  await db.execute(
    'CREATE UNIQUE INDEX idx_${tableName}_sample_key ON $tableName '
    '(customerId, sampleKey) WHERE sampleKey IS NOT NULL',
  );
}

void main() {
  late Database db;
  late _MockDatabaseHelper databaseHelper;
  late _MockActivityLogRepository activityLogRepository;
  late PanelSampleRepository panelSampleRepository;
  late AuditProvider provider;

  final user = UserModel(
    id: 'auditor-chicks-db',
    fullName: 'Chicks DB Auditor',
    email: 'chicks-db-auditor@example.com',
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
    for (final panel in PanelSampleSchema.panels.where(
      (panel) => {'chick_quality', 'chick_weights'}.contains(panel.tableName),
    )) {
      await _createPanelTable(db, panel.tableName, panel.measurementColumns);
    }
    await db.execute('''CREATE TABLE chick_quality_observation (
      id TEXT PRIMARY KEY,
      sampleId TEXT NOT NULL,
      customerId TEXT NOT NULL,
      sessionId TEXT NOT NULL,
      domain TEXT NOT NULL,
      kind TEXT NOT NULL,
      observationKey TEXT NOT NULL,
      ordinal INTEGER,
      numericValue REAL,
      textValue TEXT,
      unit TEXT NOT NULL,
      qualityFlags TEXT NOT NULL DEFAULT '[]',
      source TEXT,
      observedAt TEXT NOT NULL,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL,
      syncStatus TEXT NOT NULL DEFAULT 'pending',
      dirtyAt TEXT,
      lastSyncedAt TEXT,
      syncError TEXT
    )''');
    await db.execute('''CREATE UNIQUE INDEX idx_chick_observation_logical
      ON chick_quality_observation (
        sampleId, domain, kind, observationKey, COALESCE(ordinal, -1)
      )''');
    await db.execute('''CREATE TABLE photos (
      id TEXT PRIMARY KEY,
      sessionId TEXT NOT NULL,
      panelName TEXT NOT NULL,
      panelRowId TEXT NOT NULL,
      fieldKey TEXT NOT NULL,
      observationId TEXT,
      uploadStatus TEXT NOT NULL DEFAULT 'local'
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
    await db.insert('customers', {'id': 'customer-chicks-db'});
    await db.insert('flocks', {
      'id': 'flock-chicks-db',
      'customerId': 'customer-chicks-db',
    });
    await db.insert('hatcheries', {
      'id': 'hatchery-chicks-db',
      'customerId': 'customer-chicks-db',
      'name': 'Chicks DB Hatchery',
    });
    await db.insert('audit_sessions', {
      'id': 'session-chicks-db',
      'customerId': 'customer-chicks-db',
      'flockId': 'flock-chicks-db',
      'hatcheryId': 'hatchery-chicks-db',
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
        auditType: 'Chicks',
        customerId: 'customer-chicks-db',
        flockId: 'flock-chicks-db',
        hatcheryId: 'hatchery-chicks-db',
        breed: 'Ross 308',
        flockAgeWeeks: 42,
        setterId: 'S-1',
        hatcherId: 'H-1',
        date: '2026-05-15',
      ),
      currentUser: user,
      sessionId: 'session-chicks-db',
      notify: false,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<Map<String, Object?>>> rows(String table) async =>
      panelSampleRepository
          .getRowsBySessionId(table, 'session-chicks-db')
          .then((rows) => rows.cast<Map<String, Object?>>());

  void fillQualityDraft({
    required int pasgarReflexes,
    required double pasgarScore,
    required List<Map<String, Object?>> yfbmEntries,
    required double yfbmAvgPct,
    required List<double> cvtReadings,
    required double cvtAvg,
    required int pmSampleSize,
  }) {
    provider.updateField('pasgarSampleSize', 40);
    provider.updateField('pasgarReflexes', pasgarReflexes);
    provider.updateField('pasgarBeak', 1);
    provider.updateField('pasgarNavel', 0);
    provider.updateField('pasgarBelly', 2);
    provider.updateField('pasgarLeg', 1);
    provider.updateField('pasgarFeatherDev', 1);
    provider.updateField('pasgarFinalScore', pasgarScore);
    provider.updateField('yfbmEntries', jsonEncode(yfbmEntries));
    provider.updateField('yfbmAvgPct', yfbmAvgPct);
    provider.updateField('yfbmCvPct', 1.1);
    provider.updateField('cvtReadingsJson', jsonEncode(cvtReadings));
    provider.updateField('cvtSampleSize', cvtReadings.length);
    provider.updateField('cvtAvg', cvtAvg);
    provider.updateField('cvtCvPct', 0.4);
    provider.updateField('pm_sampleSize', pmSampleSize);
    provider.updateField('pm_collectionPoint', 'Chick basket');
    provider.updateField('pm_omphalitisCount', 2);
    provider.updateField('pm_omphalitisSeverity', 'mild');
    provider.updateField('pm_gizzardErosionsCount', 3);
    provider.updateField('pm_gizzardErosionsSeverity', 'moderate');
    provider.updateField('pm_airSacCaseationsCount', 4);
    provider.updateField('pm_airSacCaseationsSeverity', 'severe');
    provider.updateField('pm_urolithiasisCount', 2);
    provider.updateField('pm_urolithiasisSeverity', 'moderate');
    provider.updateField('pm_nephritisCount', 1);
    provider.updateField('pm_nephritisSeverity', 'mild');
    provider.updateField('pm_generalSepticemiaCount', 5);
    provider.updateField('pm_generalSepticemiaSeverity', 'severe');
    provider.updateField(
      'pm_otherLesionsJson',
      jsonEncode([
        {'name': 'Retained shell', 'count': 2, 'severity': 'mild'},
      ]),
    );
    provider.updateField('pm_suspectedCauseManual', 'manual QA note');
  }

  test(
    'Chicks station save persists combined quality rows and house weight rows',
    () async {
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.updateSampleMetadata({'setterNo': 'S-1', 'hatcherNo': 'H-1'});
      fillQualityDraft(
        pasgarReflexes: 2,
        pasgarScore: 9.8,
        yfbmEntries: const [
          {'chickWeight': 42.0, 'yolkWeight': 4.2},
          {'chickWeight': 43.0, 'yolkWeight': 4.1},
        ],
        yfbmAvgPct: 9.7,
        cvtReadings: const [101.4, 101.8, 102.0],
        cvtAvg: 101.7,
        pmSampleSize: 12,
      );
      provider.updateField('culledChicksTotalEggSet', 19200);
      provider.updateField(
        'culledChicksAnalysisJson',
        jsonEncode([
          {'id': 'navel_open_unhealed', 'count': 3},
          {'id': 'legs_red_hocks', 'count': 2},
        ]),
      );

      provider.addSample();
      provider.updateSampleMetadata({'setterNo': 'S-2', 'hatcherNo': 'H-2'});
      fillQualityDraft(
        pasgarReflexes: 4,
        pasgarScore: 9.4,
        yfbmEntries: const [
          {'chickWeight': 51.0, 'yolkWeight': 5.2},
        ],
        yfbmAvgPct: 10.2,
        cvtReadings: const [102.1, 102.4],
        cvtAvg: 102.25,
        pmSampleSize: 8,
      );
      provider.updateField('culledChicksTotalEggSet', 19200);
      provider.updateField(
        'culledChicksAnalysisJson',
        jsonEncode([
          {'id': 'sticky_dehydrated_burned_chick', 'count': 1},
        ]),
      );

      provider.setChickWeightSampleMode(
        StationSampleModel.sampleModeComparison,
      );
      provider.switchChickWeightSample(0);
      provider.updateChickWeightSampleResult(
        weightsJson: jsonEncode([41.0, 42.0, 43.0]),
        avgWeight: 42.0,
        uniformityPct: 100.0,
        cvPct: 2.4,
      );
      provider.addChickWeightSample();
      provider.updateChickWeightSampleMetadata({'houseNo': 'House-B'});
      provider.updateChickWeightSampleResult(
        weightsJson: jsonEncode([51.0, 52.0]),
        avgWeight: 51.5,
        uniformityPct: 100.0,
        cvPct: 1.4,
      );

      expect(await provider.saveSamplesWithResult(), isTrue);

      final quality = await rows('chick_quality');
      final weights = await rows('chick_weights');

      expect(quality, hasLength(2));
      expect(weights, hasLength(2));

      expect(quality.map((row) => row['setter']), ['S-1', 'S-2']);
      expect(quality.map((row) => row['hatcher']), ['H-1', 'H-2']);
      expect(quality.map((row) => row['pasgarSampleSize']), [40, 40]);
      expect(quality.map((row) => row['pasgarReflexesCount']), [2, 4]);
      // The saved score is a controlled cache derived from the raw five
      // scored defect counts; the manually supplied 9.4 cannot drift from them.
      expect(quality.map((row) => row['pasgarFinalScore']), [9.8, 9.8]);

      expect(quality.map((row) => row['yfbmEntryCount']), [2, 1]);
      // Phase 4 rebuilds this cache from the persisted raw YFBM pairs; the
      // caller-supplied 9.7 cannot override their canonical 9.8 result.
      expect(quality.map((row) => row['yfbmAvgPct']), [9.8, 10.2]);
      expect(quality.first['yfbmEntriesJson'], contains('yolkWeight'));

      expect(quality.map((row) => row['cvtSampleSize']), [3, 2]);
      expect(quality.map((row) => row['cvtAvgTemp']), [101.7, 102.3]);
      expect(quality.last['cvtReadingsJson'], jsonEncode([102.1, 102.4]));

      expect(quality.map((row) => row['pmSampleSize']), [12, 8]);
      expect(quality.first['pmCollectionPoint'], 'Chick basket');
      expect(quality.first['pmOmphalitisCount'], 2);
      expect(quality.first['pmGizzardErosionsCount'], 3);
      expect(quality.first['pmGizzardErosionsSeverity'], 'moderate');
      expect(quality.first['pmAirSacCaseationsCount'], 4);
      expect(quality.first['pmAirSacCaseationsSeverity'], 'severe');
      expect(quality.first['pmUrolithiasisCount'], 2);
      expect(quality.first['pmUrolithiasisSeverity'], 'moderate');
      expect(quality.first['pmNephritisCount'], 1);
      expect(quality.first['pmNephritisSeverity'], 'mild');
      expect(quality.first['pmGeneralSepticemiaCount'], 5);
      expect(quality.first['pmGeneralSepticemiaSeverity'], 'severe');
      expect(quality.first['pmOtherLesionsJson'], contains('Retained shell'));
      expect(quality.first.containsKey('pmPulmonaryGranulomaCount'), isFalse);
      expect(quality.first.containsKey('pmSwollenJointsCount'), isFalse);
      expect(quality.first.containsKey('pmStuntedOrgansCount'), isFalse);
      expect(quality.first.containsKey('pmPulmonaryHemorrhageCount'), isFalse);
      expect(quality.first.containsKey('pmGaspingPresent'), isFalse);
      expect(quality.first.containsKey('pmOtherDeformityText'), isFalse);
      expect(quality.first['pmSuspectedCauseManual'], 'manual QA note');
      expect(quality.first['culledChicksTotalEggSet'], 19200);
      expect(quality.first['culledChicksAnalysisJson'], contains('red_hocks'));
      expect(quality.first['culledChicksAnalysisJson'], contains('"pct"'));
      expect(quality.first['culledChicksAnalysisJson'], contains('"count":3'));
      expect(
        quality.first['culledChicksAffectedPct'],
        closeTo(5 / 19200 * 100, 0.000001),
      );
      expect(quality.first['culledChicksTopCategory'], 'Navel');
      expect(quality.first['culledChicksTopSubtype'], 'Open / unhealed navel');
      expect(quality.first.containsKey('culledChicksTotalCount'), isFalse);
      expect(quality.last['culledChicksTotalEggSet'], 19200);
      expect(
        quality.last['culledChicksAffectedPct'],
        closeTo(1 / 19200 * 100, 0.000001),
      );
      expect(quality.last['culledChicksTopCategory'], 'Dehydrated');
      expect(
        quality.last['culledChicksTopSubtype'],
        'Dehydrated / burned chick',
      );

      expect(weights.map((row) => row['house']), ['H1', 'House-B']);
      expect(weights.map((row) => row['sampleSize']), [3, 2]);
      expect(weights.map((row) => row['weightsJson']), [
        jsonEncode([41.0, 42.0, 43.0]),
        jsonEncode([51.0, 52.0]),
      ]);
      expect(weights.map((row) => row['avgWeight']), [42.0, 51.5]);
      expect(weights.map((row) => row['cvPct']), [2.4, 1.4]);
    },
  );
}
