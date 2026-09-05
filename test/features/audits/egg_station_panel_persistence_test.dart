import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/activity_log_repository.dart';
import 'package:hatchaudit/data/repositories/egg_grading_repository.dart';
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

// The egg_quality panel row now writes a matching set of
// `egg_quality_defect_counts` child rows (task B4); this harness creates the
// table so those writes have somewhere to land, mirroring B2/B3's schema.
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
  TestWidgetsFlutterBinding.ensureInitialized();
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
    await _createEggQualityDefectCountsTable(db);
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
      eggGradingRepository: EggGradingRepository(
        databaseHelper: databaseHelper,
      ),
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

  Future<List<Map<String, Object?>>> rows(String table) {
    return db.query(
      table,
      orderBy:
          'house ASC, setter ASC, hatcher ASC, trolley ASC, tray ASC, position ASC',
    );
  }

  void fillEggDraft({
    required int storageDays,
    required Map<String, double> estReadings,
    required double estAvg,
    required double estCv,
    required List<Map<String, Object?>> uvTrays,
    required List<double?> weights,
    required double avgWeight,
    required double uniformityPct,
    required double cvPct,
    required String notes,
  }) {
    provider.updateField('esEggStorageDays', storageDays);
    provider.updateField('es_estReadingsJson', jsonEncode(estReadings));
    provider.updateField('es_estAvg', estAvg);
    provider.updateField('es_estCv', estCv);
    provider.updateField('esShellTemp', estAvg);
    provider.updateField('esTurningTimes', 3);
    provider.updateField('es_traySpacing', 'Tight');
    provider.updateField('es_coolerProximity', 'Adjacent');
    provider.updateField('es_condensation', 1);
    provider.updateField('esUvTrays', jsonEncode(uvTrays));
    provider.updateField('esEggWeights', jsonEncode(weights));
    provider.updateField('esEggSampleSize', weights.whereType<double>().length);
    provider.updateField('esEggAvgWeight', avgWeight);
    provider.updateField('esEggUniformityPct', uniformityPct);
    provider.updateField('esEggCvPct', cvPct);
    provider.updateField('esEggBmkAge', 40);
    provider.updateField('esEggBmkWeight', 62.5);
    provider.updateField('notes', notes);
  }

  test('blank Egg station save does not create egg panel rows', () async {
    expect(await provider.saveSamplesWithResult(), isTrue);

    expect(await rows('egg_storage'), isEmpty);
    expect(await rows('egg_quality'), isEmpty);
  });

  test(
    'Egg metadata without EST or quality inputs does not create rows',
    () async {
      provider.updateField('esEggStorageDays', 5);
      provider.updateField('esEggQualityStorageDays', 7);
      provider.updateField('esEggBmkAge', 40);
      provider.updateField('esEggBmkWeight', 62.5);
      provider.updateField('notes', 'metadata only');

      expect(await provider.saveSamplesWithResult(), isTrue);

      expect(await rows('egg_storage'), isEmpty);
      expect(await rows('egg_quality'), isEmpty);
    },
  );

  Future<void> insertStaleEggStorageHouseRows() async {
    for (final house in ['H1', 'H2', 'H3']) {
      await db.insert('egg_storage', {
        'id': 'stale-egg-storage-$house',
        'sessionId': 'session-egg-db',
        'customerId': 'customer-egg-db',
        'flockId': 'flock-egg-db',
        'hatcheryId': 'hatchery-egg-db',
        'date': '2026-05-15',
        'breed': 'Ross 308',
        'flockAgeWeeks': 42,
        'house': house,
        'storagePeriodDays': 99,
        'notes': 'stale $house',
        'createdAt': DateTime(2026, 5, 15).toUtc().toIso8601String(),
        'updatedAt': DateTime(2026, 5, 15).toUtc().toIso8601String(),
        'syncStatus': 'pending',
      });
    }
  }

  test(
    'pooled Egg station save writes storage and consolidated quality tables',
    () async {
      fillEggDraft(
        storageDays: 9,
        estReadings: const {
          'front_top': 19.1,
          'middle_center': 19.3,
          'back_bottom': 19.2,
        },
        estAvg: 19.2,
        estCv: 0.4,
        uvTrays: const [
          {
            'totalEggs': 100,
            'cuticleDamage': 3,
            'washed': 2,
            'dirty': 1,
            'upsideDown': 4,
          },
          {
            'totalEggs': 80,
            'cuticleDamage': 1,
            'washed': 0,
            'dirty': 2,
            'upsideDown': 3,
          },
        ],
        weights: const [60, 61, 62, 63, 64],
        avgWeight: 62,
        uniformityPct: 100,
        cvPct: 2.28,
        notes: 'egg-persist-probe pooled',
      );

      expect(await provider.saveSamplesWithResult(), isTrue);

      final storage = await rows('egg_storage');
      final quality = await rows('egg_quality');
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'egg_weights'",
      );

      expect(storage, hasLength(1));
      expect(quality, hasLength(1));
      expect(tables, isEmpty);

      expect(storage.single['house'], isNull);
      expect(storage.single['storagePeriodDays'], 9);
      expect(storage.single['estReadingsJson'], contains('front_top'));
      expect(storage.single['estAvg'], 19.2);
      expect(storage.single['estCvPct'], 0.5);
      expect(storage.single['turningTimes'], 3);
      expect(storage.single['traySpacing'], 'Tight');
      expect(storage.single['coolerProximity'], 'Adjacent');
      expect(storage.single['condensationPresent'], 1);
      expect(storage.single['upsideDownCount'], 7);
      expect(storage.single['upsideDownPct'], closeTo(3.888, 0.001));
      expect(storage.single['notes'], 'egg-persist-probe pooled');

      expect(quality.single['uvTrayEggCount'], 180);
      expect(quality.single['uvCuticleDamageCount'], 4);
      expect(quality.single['uvCuticleDamagePct'], 2.2);
      expect(quality.single['uvWashedCount'], 2);
      expect(quality.single['uvWashedPct'], 1.1);
      expect(quality.single['uvDirtyCount'], 3);
      expect(quality.single['uvDirtyPct'], 1.7);
      expect(quality.single['uvAffectedCount'], 9);
      expect(quality.single['uvAffectedPct'], 5.0);
      expect(quality.single.containsKey('affectedCount'), isFalse);
      expect(quality.single.containsKey('upsideDownCount'), isFalse);
      expect(quality.single.containsKey('upsideDownPct'), isFalse);

      expect(
        quality.single['eggWeightsJson'],
        jsonEncode([60.0, 61.0, 62.0, 63.0, 64.0]),
      );
      expect(quality.single['eggSampleSize'], 5);
      expect(quality.single['eggAvgWeight'], 62);
      expect(quality.single['eggUniformityPct'], 100);
      expect(quality.single['eggCvPct'], 2.6);
      expect(quality.single['eggBmkAgeWeeks'], 40);
      expect(quality.single['eggBmkWeight'], 62.5);
      expect(quality.single.containsKey('weightsJson'), isFalse);
      expect(quality.single.containsKey('sampleSize'), isFalse);
      expect(quality.single.containsKey('avgWeight'), isFalse);
    },
  );

  test(
    'comparison Egg station save keeps storage pooled and quality isolated',
    () async {
      await insertStaleEggStorageHouseRows();
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.updateField('esEggStorageDays', 4);
      provider.updateField(
        'es_estReadingsJson',
        jsonEncode({'front_top': 19.0}),
      );
      provider.updateField('es_estAvg', 19.0);
      provider.updateField('es_estCv', 0.0);
      provider.updateField('esTurningTimes', 3);
      provider.updateField('es_traySpacing', 'Tight');
      provider.updateField('es_coolerProximity', 'Adjacent');
      provider.updateField('es_condensation', 1);
      provider.updateField(
        'esUvTrays',
        jsonEncode([
          {
            'totalEggs': 50,
            'cuticleDamage': 1,
            'washed': 1,
            'dirty': 0,
            'upsideDown': 2,
          },
        ]),
      );
      provider.updateField('esEggWeights', jsonEncode([55.0, 56.0]));
      provider.updateField('esEggSampleSize', 2);
      provider.updateField('esEggAvgWeight', 55.5);
      provider.updateField('esEggUniformityPct', 100.0);
      provider.updateField('esEggCvPct', 1.27);
      provider.updateField('notes', 'egg-persist-probe H1');

      provider.addSample();
      provider.updateField('esShellTemp', 20.2);
      provider.updateField(
        'esUvTrays',
        jsonEncode([
          {
            'totalEggs': 60,
            'cuticleDamage': 0,
            'washed': 2,
            'dirty': 3,
            'upsideDown': 0,
          },
        ]),
      );
      provider.updateField('esEggWeights', jsonEncode([65.0, 66.0, 67.0]));
      provider.updateField('esEggSampleSize', 3);
      provider.updateField('esEggAvgWeight', 66.0);
      provider.updateField('esEggUniformityPct', 100.0);
      provider.updateField('esEggCvPct', 1.24);
      provider.updateField('notes', 'egg-persist-probe H2');

      expect(await provider.saveSamplesWithResult(), isTrue);

      final storage = await rows('egg_storage');
      final quality = await rows('egg_quality');
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'egg_weights'",
      );

      expect(storage, hasLength(1));
      expect(quality, hasLength(2));
      expect(tables, isEmpty);

      expect(storage.single['house'], isNull);
      expect(storage.single['setter'], isNull);
      expect(storage.single['hatcher'], isNull);
      expect(storage.single['tray'], isNull);
      expect(storage.single['storagePeriodDays'], 4);
      expect(storage.single['estAvg'], 19.0);
      expect(storage.single['turningTimes'], 3);
      expect(storage.single['traySpacing'], 'Tight');
      expect(storage.single['coolerProximity'], 'Adjacent');
      expect(storage.single['condensationPresent'], 1);
      expect(storage.single['upsideDownCount'], 2);
      expect(storage.single['notes'], 'egg-persist-probe H1');

      expect(quality.map((row) => row['uvTrayEggCount']), [50, 60]);
      expect(quality.map((row) => row['uvAffectedCount']), [2, 5]);
      expect(quality.map((row) => row['uvCuticleDamagePct']), [2.0, 0.0]);
      expect(quality.map((row) => row['uvWashedPct']).toList()[0], 2.0);
      expect(quality.map((row) => row['uvWashedPct']).toList()[1], 3.3);
      expect(quality.map((row) => row['uvDirtyPct']), [0.0, 5.0]);
      expect(quality.map((row) => row['uvAffectedPct']).toList()[0], 4.0);
      expect(quality.map((row) => row['uvAffectedPct']).toList()[1], 8.3);
      expect(quality.any((row) => row.containsKey('affectedCount')), isFalse);
      expect(quality.any((row) => row.containsKey('upsideDownCount')), isFalse);

      expect(quality.map((row) => row['eggSampleSize']), [2, 3]);
      expect(quality.map((row) => row['eggAvgWeight']), [55.5, 66.0]);
      expect(quality[0]['eggWeightsJson'], jsonEncode([55.0, 56.0]));
      expect(quality[1]['eggWeightsJson'], jsonEncode([65.0, 66.0, 67.0]));
    },
  );

  test(
    'removing a reindexed egg quality scope deletes its saved row identity',
    () async {
      // NOTE: this test previously expected the surviving 'H3' house to be
      // renumbered to 'H2' after the middle house was removed. That relied
      // on default-value sniffing in AuditProvider that task A6 removed
      // (a sample's house identity is now owned by the sample once it
      // carries any value, never re-derived from position). The surviving
      // house keeps its own 'H3' identity below instead of being relabeled.
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.updateField('esEggWeights', jsonEncode([50.0]));
      provider.updateField('esEggSampleSize', 1);

      provider.addSample();
      provider.updateField('esEggWeights', jsonEncode([51.0]));
      provider.updateField('esEggSampleSize', 1);
      final removedSampleId = provider.activeStationSample.id;

      provider.addSample();
      provider.updateField('esEggWeights', jsonEncode([52.0]));
      provider.updateField('esEggSampleSize', 1);

      expect(await provider.saveSamplesWithResult(), isTrue);

      final beforeRemoval = await rows('egg_quality');
      expect(beforeRemoval.map((row) => row['house']), ['H1', 'H2', 'H3']);
      final removedRowId =
          beforeRemoval.singleWhere((row) => row['house'] == 'H2')['id']
              as String;
      expect(removedRowId, contains(removedSampleId));

      provider.switchSample(1);
      provider.removeActiveSample();

      expect(await provider.saveSamplesWithResult(), isTrue);

      final afterRemoval = await rows('egg_quality');
      expect(afterRemoval.map((row) => row['house']), ['H1', 'H3']);
      expect(
        afterRemoval.map((row) => row['id']),
        isNot(contains(removedRowId)),
      );
      expect(
        afterRemoval.map((row) => row['id'] as String),
        everyElement(isNot(contains(removedSampleId))),
      );
      expect(afterRemoval.last['eggWeightsJson'], jsonEncode([52.0]));
    },
  );

  test(
    'saved egg_quality rows carry explicit sample and domain metadata',
    () async {
      provider.updateField('esEggStorageDays', 9);
      provider.updateField(
        'es_estReadingsJson',
        jsonEncode({'front_top': 19.1}),
      );
      provider.updateField('es_estAvg', 19.1);
      provider.updateField('es_estCv', 0.0);
      provider.updateField('esEggSampleSize', 12);
      // The first call to addEggQualityScopeSample only switches the existing
      // single sample into comparison mode (see AuditProvider
      // .addEggQualityScopeSample: it returns immediately after
      // setStationSampleMode when not already comparing). A second call is
      // needed to actually add a distinct second house-scoped sample, matching
      // how the neighbouring 'comparison Egg station save...' test above
      // builds its two-sample scenario via setStationSampleMode + addSample.
      provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
      provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
      provider.updateSampleMetadata({'houseNo': 'H4', 'houseLabel': 'House 4'});
      provider.updateField('esEggSampleSize', 34);
      await provider.saveSamplesWithResult(tabIndex: 0);

      final saved = await db.query('egg_quality', orderBy: 'sampleIndex ASC');
      expect(saved, hasLength(2));
      expect(saved.map((r) => r['sampleMode']), ['comparison', 'comparison']);
      expect(saved.map((r) => r['scopeType']), ['house', 'house']);
      expect(saved.map((r) => r['sampleIndex']), [1, 2]);
      expect(saved.last['sampleLabel'], 'H4');
      for (final row in saved) {
        expect(row['sourceDomain'], 'hatchery');
        expect(row['actionDomain'], 'farm');
        expect(row['recommendationTarget'], 'farm');
      }

      final storage = await db.query('egg_storage');
      expect(storage, isNotEmpty);
      for (final row in storage) {
        expect(row['sampleMode'], 'pooled');
        expect(row['scopeType'], 'pool');
        expect(row['sourceDomain'], 'hatchery');
        expect(row['actionDomain'], 'hatchery');
        expect(row['recommendationTarget'], 'hatchery');
      }
    },
  );

  test('egg_quality row id is the station sample id', () async {
    provider.updateField('esEggSampleSize', 12);
    await provider.saveSamplesWithResult(tabIndex: 0);

    final saved = await db.query('egg_quality');
    expect(saved.single['id'], provider.activeStationSample.id);
  });
}
