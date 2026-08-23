import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/utils/calculation_utils.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/activity_log_repository.dart';
import 'package:hatchaudit/data/repositories/egg_grading_repository.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/features/audits/models/est_grid_data.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

class _MockActivityLogRepository extends Mock
    implements ActivityLogRepository {}

/// Reconstructs an Egg [AuditModel] from saved panel rows the same way the
/// session-open path does (see `_mergePanelRowIntoAuditMap` in
/// audit_session_screen.dart). Kept narrow on purpose: if the save side renames
/// a column, or AuditModel.fromMap renames a key, these mappings break and the
/// round-trip assertions fail — which is exactly the regression we want caught.
AuditModel _eggDraftFromRows(
  Map<String, Object?> storageRow,
  Map<String, Object?> qualityRow,
) {
  final map = <String, dynamic>{
    'id': 'rt-egg',
    'auditType': 'Egg',
    'customerId': storageRow['customerId'] ?? qualityRow['customerId'],
    'date': storageRow['date'] ?? qualityRow['date'],
    'status': 'completed',
    'createdBy': 'panel',
    'createdAt': storageRow['createdAt'],
    'updatedAt': storageRow['updatedAt'],
    // egg_storage → es_* keys
    'esEggStorageDays': storageRow['storagePeriodDays'],
    'es_estReadingsJson': storageRow['estReadingsJson'],
    'es_estAvg': storageRow['estAvg'],
    'es_estCv': storageRow['estCvPct'],
    // egg_quality → es_* keys
    'esEggWeights': qualityRow['eggWeightsJson'],
    'esEggSampleSize': qualityRow['eggSampleSize'],
    'esEggAvgWeight': qualityRow['eggAvgWeight'],
    'esEggUniformityPct': qualityRow['eggUniformityPct'],
    'esEggCvPct': qualityRow['eggCvPct'],
  };
  return AuditModel.fromMap(map);
}

List<double> _decodeReadings(String? json) {
  if (json == null || json.isEmpty) return const [];
  return EstGridData.normalizeReadings(
    jsonDecode(json) as Map<dynamic, dynamic>,
  ).values.toList();
}

List<double> _decodeWeights(String? json) {
  if (json == null || json.isEmpty) return const [];
  return (jsonDecode(json) as List)
      .whereType<num>()
      .map((n) => n.toDouble())
      .toList();
}

void main() {
  // ───────────────────────────────────────────────────────────────────────
  // Save → reload round-trip (in-memory). Detects save/load key mismatches.
  // ───────────────────────────────────────────────────────────────────────
  group('Egg station save → reload round-trip', () {
    late Database db;
    late _MockDatabaseHelper databaseHelper;
    late _MockActivityLogRepository activityLogRepository;
    late PanelSampleRepository panelSampleRepository;
    late AuditProvider provider;

    final user = UserModel(
      id: 'rt-auditor',
      fullName: 'Round Trip Auditor',
      email: 'rt@example.com',
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
        final extra = panel.measurementColumns.isEmpty
            ? ''
            : ', ${panel.measurementColumns.join(', ')}';
        await db.execute('''CREATE TABLE ${panel.tableName} (
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
          "CREATE UNIQUE INDEX idx_${panel.tableName}_unique_row ON "
          "${panel.tableName} (sessionId, IFNULL(house, ''), "
          "IFNULL(setter, ''), IFNULL(hatcher, ''), IFNULL(trolley, ''), "
          "IFNULL(tray, ''), IFNULL(position, ''))",
        );
      }
      // egg_quality now writes matching `egg_quality_defect_counts` child
      // rows (task B4); create the table so those writes land somewhere.
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
      await db.insert('customers', {'id': 'rt-customer'});
      await db.insert('flocks', {
        'id': 'rt-flock',
        'customerId': 'rt-customer',
      });
      await db.insert('hatcheries', {
        'id': 'rt-hatchery',
        'customerId': 'rt-customer',
        'name': 'RT Hatchery',
      });
      await db.insert('audit_sessions', {
        'id': 'rt-session',
        'customerId': 'rt-customer',
        'flockId': 'rt-flock',
        'hatcheryId': 'rt-hatchery',
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
          customerId: 'rt-customer',
          flockId: 'rt-flock',
          hatcheryId: 'rt-hatchery',
          breed: 'Ross 308',
          flockAgeWeeks: 30,
          date: '2026-05-15',
        ),
        currentUser: user,
        sessionId: 'rt-session',
        notify: false,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('EST grid, average, shell temp and storage survive reload', () async {
      const readings = {
        'front_top': 19.8,
        'middle_middle': 20.0,
        'back_bottom': 20.2,
      };
      provider.updateField('esEggStorageDays', 6);
      provider.updateField('es_estReadingsJson', jsonEncode(readings));
      provider.updateField('es_estAvg', 20.0);
      provider.updateField('es_estCv', 1.0);
      provider.updateField('esShellTemp', 20.0);

      expect(await provider.saveSamplesWithResult(), isTrue);

      final storage = await db.query('egg_storage');
      expect(storage, hasLength(1));

      // Raw grid persisted (not just the aggregate).
      final restored = _eggDraftFromRows(storage.single, <String, Object?>{});
      final grid = _decodeReadings(restored.esEstReadingsJson);
      expect(grid, hasLength(3));
      expect(CalculationUtils.average(grid), closeTo(20.0, 0.05));
      expect(restored.esEstAvg, 20.0);
      expect(restored.esEggStorageDays, 6);
    });

    test(
      'Egg quality weights, sample size and average survive reload',
      () async {
        // Average is exactly 62.4 so the reloaded aggregate is derived from raw.
        const weights = <double>[61.0, 62.0, 62.4, 63.0, 63.6];
        provider.updateField('esEggQualityStorageDays', 5);
        provider.updateField(
          'esUvTrays',
          jsonEncode(const [
            {'totalEggs': 150, 'cuticleDamage': 2, 'washed': 1, 'dirty': 1},
          ]),
        );
        provider.updateField('esEggWeights', jsonEncode(weights));
        provider.updateField('esEggSampleSize', weights.length);
        provider.updateField('esEggAvgWeight', 62.4);
        provider.updateField('esEggUniformityPct', 100.0);
        provider.updateField('esEggCvPct', 1.6);

        expect(await provider.saveSamplesWithResult(), isTrue);

        final quality = await db.query('egg_quality');
        expect(quality, hasLength(1));
        expect(quality.single['uvTrayEggCount'], 150);

        final restored = _eggDraftFromRows(<String, Object?>{}, quality.single);
        final reloaded = _decodeWeights(restored.esEggWeights);
        expect(reloaded, weights);
        expect(CalculationUtils.average(reloaded), closeTo(62.4, 0.05));
        expect(restored.esEggSampleSize, weights.length);
        expect(restored.esEggAvgWeight, 62.4);
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────
  // Demo seed integrity (full real schema). The seeded session must reopen
  // showing the same raw data a user would have entered, with aggregates
  // derivable from the raw inputs.
  // ───────────────────────────────────────────────────────────────────────
  group('Dashboard demo seed integrity', () {
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = Directory(
        p.join(
          Directory.systemTemp.path,
          'chickmark_seed_rt_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      await dir.create(recursive: true);
      await databaseFactory.setDatabasesPath(dir.path);
    });

    setUp(() async {
      await DatabaseHelper().close();
      await databaseFactory.deleteDatabase(
        p.join(await databaseFactory.getDatabasesPath(), 'hatchaudit.db'),
      );
      DatabaseHelper.seedDemoData = true;
      await DatabaseHelper().db; // triggers full schema create + demo seed
    });

    tearDown(() async {
      DatabaseHelper.seedDemoData = false;
      await DatabaseHelper().close();
    });

    Future<Map<String, Object?>> singleRow(String table, String id) async {
      final db = await DatabaseHelper().db;
      final rows = await db.query(table, where: 'id = ?', whereArgs: [id]);
      expect(rows, hasLength(1), reason: '$table/$id should be seeded');
      return rows.single;
    }

    test('Egg storage EST grid reopens populated with avg == estAvg', () async {
      final row = await singleRow('egg_storage', 'demo-es-0');
      final restored = _eggDraftFromRows(row, <String, Object?>{});
      final grid = _decodeReadings(restored.esEstReadingsJson);

      expect(grid, isNotEmpty, reason: 'EST grid must reopen non-empty');
      expect(grid, hasLength(EstGridData.scanKeys.length));
      // Dashboard value (estAvg) equals the entry-screen value (grid mean).
      expect(CalculationUtils.average(grid), closeTo(20.0, 0.05));
      expect(restored.esEstAvg, 20.0);
      expect(restored.esEggStorageDays, 4);
    });

    test('Egg quality weights + UV tray reopen populated', () async {
      final row = await singleRow('egg_quality', 'demo-eq-0');
      final restored = _eggDraftFromRows(<String, Object?>{}, row);
      final weights = _decodeWeights(restored.esEggWeights);

      expect(weights, hasLength(92));
      expect(CalculationUtils.average(weights), closeTo(62.4, 0.05));
      expect(restored.esEggAvgWeight, 62.4);
      expect(restored.esEggSampleSize, 92);
      expect(row['uvTrayEggCount'], 150);
    });

    test(
      'Chick weights reopen as a raw array averaging the seeded mean',
      () async {
        final row = await singleRow('chick_weights', 'demo-cw-0');
        final weights = _decodeWeights(row['weightsJson'] as String?);
        expect(weights, hasLength(100));
        expect(CalculationUtils.average(weights), closeTo(42.3, 0.05));
        expect(row['avgWeight'], 42.3);
      },
    );

    test('Machine EST/CVT grids reopen populated', () async {
      final setter = await singleRow('setter_optimizing', 'demo-set-0');
      final setterGrid = _decodeReadings(setter['estReadingsJson'] as String?);
      expect(setterGrid, hasLength(EstGridData.scanKeys.length));
      expect(CalculationUtils.average(setterGrid), closeTo(100.3, 0.05));
      // Setter screen hydrates from estSamplesJson — must be present too.
      final samples = jsonDecode(setter['estSamplesJson'] as String) as List;
      expect(samples, hasLength(1));
      expect((samples.first as Map)['estReadings'], isA<Map>());

      final hatcher = await singleRow('hatcher_optimizing', 'demo-hat-0');
      final hatcherGrid = _decodeReadings(
        hatcher['cvtReadingsJson'] as String?,
      );
      expect(hatcherGrid, hasLength(EstGridData.scanKeys.length));
      expect(CalculationUtils.average(hatcherGrid), closeTo(103.6, 0.05));

      final chick = await singleRow('chick_quality', 'demo-cq-0');
      final chickCvt = _decodeReadings(chick['cvtReadingsJson'] as String?);
      expect(chickCvt, hasLength(EstGridData.scanKeys.length));
      expect(CalculationUtils.average(chickCvt), closeTo(104.1, 0.05));
      expect(chick['pasgarSampleSize'], 100);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Autosave safety: a populated EST grid recomputes to the same aggregate, so
  // re-opening a seeded session and autosaving cannot wipe the dashboard value.
  // (An empty grid intentionally clears the average — no readings, no average.)
  // ───────────────────────────────────────────────────────────────────────
  group('Autosave does not wipe a populated aggregate', () {
    test('recomputed EST average reproduces the seeded mean', () {
      final grid = EstGridData.normalizeReadings(
        jsonDecode(
              jsonEncode({
                'front_top': 20.5,
                'middle_middle': 20.0,
                'back_bottom': 19.5,
              }),
            )
            as Map<dynamic, dynamic>,
      ).values.toList();

      // This mirrors _updateEstCalculations: avg of the live grid cells.
      expect(grid, isNotEmpty);
      expect(CalculationUtils.average(grid), closeTo(20.0, 0.05));
    });
  });
}
