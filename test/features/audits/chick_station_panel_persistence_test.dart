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
    mode TEXT NOT NULL DEFAULT 'pool',
    scopeType TEXT NOT NULL DEFAULT 'pool',
    scopeLabel TEXT NOT NULL DEFAULT 'Random',
    sampleIndex INTEGER NOT NULL DEFAULT 0,
    groupKey TEXT,
    groupLabel TEXT,
    notes TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    lastSyncedAt TEXT,
    syncError TEXT$extra
  )''');
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
      (panel) => {
        'chick_pasgar',
        'chick_weights',
        'chick_yfbm',
        'chick_cvt',
        'chick_pm',
      }.contains(panel.tableName),
    )) {
      await _createPanelTable(db, panel.tableName, panel.measurementColumns);
    }
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

  Future<List<Map<String, Object?>>> rows(String table) {
    return db.query(table, orderBy: 'sampleIndex ASC, scopeLabel ASC');
  }

  void fillQualityDraft({
    required int pasgarReflexes,
    required double pasgarScore,
    required List<Map<String, Object?>> yfbmEntries,
    required double yfbmAvgPct,
    required List<double> cvtReadings,
    required double cvtAvg,
    required int pmSampleSize,
    required bool gaspingPresent,
    required String gaspingType,
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
    provider.updateField('pm_nephritisCount', 1);
    provider.updateField('pm_nephritisSeverity', 'mild');
    provider.updateField('pm_generalSepticemiaCount', 5);
    provider.updateField('pm_generalSepticemiaSeverity', 'severe');
    provider.updateField('pm_gaspingPresent', gaspingPresent ? 1 : 0);
    provider.updateField('pm_gaspingType', gaspingType);
    provider.updateField('pm_otherDeformityCount', 1);
    provider.updateField('pm_otherDeformityText', 'crossed toes');
    provider.updateField('pm_suspectedCauseManual', 'manual QA note');
  }

  test(
    'Chicks station save persists quality panels and house weight rows',
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
        gaspingPresent: true,
        gaspingType: 'mild',
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
        gaspingPresent: false,
        gaspingType: 'none',
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

      final pasgar = await rows('chick_pasgar');
      final yfbm = await rows('chick_yfbm');
      final cvt = await rows('chick_cvt');
      final pm = await rows('chick_pm');
      final weights = await rows('chick_weights');

      expect(pasgar, hasLength(2));
      expect(yfbm, hasLength(2));
      expect(cvt, hasLength(2));
      expect(pm, hasLength(2));
      expect(weights, hasLength(2));

      expect(pasgar.map((row) => row['scopeType']), [
        'setter_hatcher',
        'setter_hatcher',
      ]);
      expect(pasgar.map((row) => row['scopeLabel']), ['S-1/H-1', 'S-2/H-2']);
      expect(pasgar.map((row) => row['sampleSize']), [40, 40]);
      expect(pasgar.map((row) => row['reflexesCount']), [2, 4]);
      expect(pasgar.map((row) => row['finalScore']), [9.8, 9.4]);

      expect(yfbm.map((row) => row['entryCount']), [2, 1]);
      expect(yfbm.map((row) => row['avgPct']), [9.7, 10.2]);
      expect(yfbm.first['entriesJson'], contains('yolkWeight'));

      expect(cvt.map((row) => row['sampleSize']), [3, 2]);
      expect(cvt.map((row) => row['avgTemp']), [101.7, 102.25]);
      expect(cvt.last['readingsJson'], jsonEncode([102.1, 102.4]));

      expect(pm.map((row) => row['sampleSize']), [12, 8]);
      expect(pm.first['collectionPoint'], 'Chick basket');
      expect(pm.first['omphalitisCount'], 2);
      expect(pm.first['gizzardErosionsCount'], 3);
      expect(pm.first['gizzardErosionsSeverity'], 'moderate');
      expect(pm.first['airSacCaseationsCount'], 4);
      expect(pm.first['airSacCaseationsSeverity'], 'severe');
      expect(pm.first['nephritisCount'], 1);
      expect(pm.first['nephritisSeverity'], 'mild');
      expect(pm.first['generalSepticemiaCount'], 5);
      expect(pm.first['generalSepticemiaSeverity'], 'severe');
      expect(pm.map((row) => row['gaspingPresent']), [1, 0]);
      expect(pm.first['gaspingType'], 'mild');
      expect(pm.first['otherDeformityText'], 'crossed toes');
      expect(pm.first['suspectedCauseManual'], 'manual QA note');

      expect(weights.map((row) => row['scopeType']), ['house', 'house']);
      expect(weights.map((row) => row['scopeLabel']), ['House 1', 'House-B']);
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
