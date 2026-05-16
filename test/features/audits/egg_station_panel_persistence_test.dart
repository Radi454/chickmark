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

  Future<List<Map<String, Object?>>> rows(String table) {
    return db.query(table, orderBy: 'sampleIndex ASC, scopeLabel ASC');
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

      expect(storage.single['mode'], 'pool');
      expect(storage.single['scopeType'], 'pool');
      expect(storage.single['storageDays'], 9);
      expect(storage.single['estReadingsJson'], contains('front_top'));
      expect(storage.single['estAvg'], 19.2);
      expect(storage.single['estCvPct'], 0.4);
      expect(storage.single['shellTemp'], 19.2);
      expect(storage.single['turningTimes'], 3);
      expect(storage.single['traySpacing'], 'Tight');
      expect(storage.single['coolerProximity'], 'Adjacent');
      expect(storage.single['condensationPresent'], 1);
      expect(storage.single['upsideDownCount'], 7);
      expect(storage.single['upsideDownPct'], closeTo(3.888, 0.001));
      expect(storage.single['notes'], 'egg-persist-probe pooled');

      expect(quality.single['uvTrayEggCount'], 180);
      expect(quality.single['uvCuticleDamageCount'], 4);
      expect(quality.single['uvWashedCount'], 2);
      expect(quality.single['uvDirtyCount'], 3);
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
      expect(quality.single['eggCvPct'], 2.28);
      expect(quality.single['eggBmkAgeWeeks'], 40);
      expect(quality.single['eggBmkWeight'], 62.5);
      expect(quality.single.containsKey('weightsJson'), isFalse);
      expect(quality.single.containsKey('sampleSize'), isFalse);
      expect(quality.single.containsKey('avgWeight'), isFalse);
    },
  );

  test('comparison Egg station save keeps each house row isolated', () async {
    provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
    fillEggDraft(
      storageDays: 4,
      estReadings: const {'front_top': 19.0},
      estAvg: 19.0,
      estCv: 0,
      uvTrays: const [
        {
          'totalEggs': 50,
          'cuticleDamage': 1,
          'washed': 1,
          'dirty': 0,
          'upsideDown': 2,
        },
      ],
      weights: const [55, 56],
      avgWeight: 55.5,
      uniformityPct: 100,
      cvPct: 1.27,
      notes: 'egg-persist-probe H1',
    );

    provider.addSample();
    fillEggDraft(
      storageDays: 12,
      estReadings: const {'front_top': 20.0, 'front_middle': 20.4},
      estAvg: 20.2,
      estCv: 1.4,
      uvTrays: const [
        {
          'totalEggs': 60,
          'cuticleDamage': 0,
          'washed': 2,
          'dirty': 3,
          'upsideDown': 5,
        },
      ],
      weights: const [65, 66, 67],
      avgWeight: 66,
      uniformityPct: 100,
      cvPct: 1.24,
      notes: 'egg-persist-probe H2',
    );

    expect(await provider.saveSamplesWithResult(), isTrue);

    final storage = await rows('egg_storage');
    final quality = await rows('egg_quality');
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'egg_weights'",
    );

    expect(storage, hasLength(2));
    expect(quality, hasLength(2));
    expect(tables, isEmpty);

    expect(storage.map((row) => row['mode']), ['comparison', 'comparison']);
    expect(storage.map((row) => row['scopeType']), ['house', 'house']);
    expect(storage.map((row) => row['scopeLabel']), ['House 1', 'House 2']);
    expect(storage.map((row) => row['storageDays']), [4, 12]);
    expect(storage.map((row) => row['notes']), [
      'egg-persist-probe H1',
      'egg-persist-probe H2',
    ]);
    expect(storage[0]['estAvg'], 19.0);
    expect(storage[1]['estAvg'], 20.2);
    expect(storage.map((row) => row['upsideDownCount']), [2, 5]);

    expect(quality.map((row) => row['uvTrayEggCount']), [50, 60]);
    expect(quality.map((row) => row['uvAffectedCount']), [2, 5]);
    expect(quality.any((row) => row.containsKey('affectedCount')), isFalse);
    expect(quality.any((row) => row.containsKey('upsideDownCount')), isFalse);

    expect(quality.map((row) => row['eggSampleSize']), [2, 3]);
    expect(quality.map((row) => row['eggAvgWeight']), [55.5, 66.0]);
    expect(quality[0]['eggWeightsJson'], jsonEncode([55.0, 56.0]));
    expect(quality[1]['eggWeightsJson'], jsonEncode([65.0, 66.0, 67.0]));
  });
}
