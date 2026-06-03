import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/repositories/panel_dashboard_repository.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_filter.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PanelDashboardRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await _resetDatabase();
    repository = PanelDashboardRepository();
  });

  tearDown(() async {
    await DatabaseHelper().close();
  });

  test(
    'dashboard aggregates directly from panel tables without audits',
    () async {
      final db = await DatabaseHelper().db;
      final tables = await _tableNames(db);
      expect(tables, isNot(contains('audits')));

      await db.insert('customers', {
        'id': 'customer-1',
        'name': 'Customer 1',
        'createdAt': '2026-01-01T00:00:00Z',
      });
      await db.insert('flocks', {
        'id': 'flock-1',
        'customerId': 'customer-1',
        'flockId': 'Flock 1',
        'entryDate': '2025-01-01',
      });
      await db.insert('hatcheries', {
        'id': 'hatchery-1',
        'customerId': 'customer-1',
        'name': 'Hatchery 1',
        'createdAt': '2026-01-01T00:00:00Z',
      });
      await db.insert('audit_sessions', {
        'id': 'session-1',
        'customerId': 'customer-1',
        'flockId': 'flock-1',
        'hatcheryId': 'hatchery-1',
        'date': '2026-01-01',
        'status': 'completed',
        'selectedStationKeys': '["chicks","hatch_analysis_egg_breakouts"]',
        'stationsCompleted': '["chicks","hatch_analysis_egg_breakouts"]',
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': '2026-01-01T00:00:00Z',
      });
      await db.insert('chick_weights', {
        'id': 'weight-1',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'flockId': 'flock-1',
        'date': '2026-01-01',
        'flockAgeWeeks': 40,
        'weightsJson': '[40,42,44]',
        'sampleSize': 3,
        'avgWeight': 42.0,
        'uniformityPct': 100.0,
        'cvPct': 3.9,
        'bmkAgeWeeks': 40,
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': '2026-01-01T00:00:00Z',
      });
      await db.insert('egg_storage', {
        'id': 'egg-storage-1',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'flockId': 'flock-1',
        'date': '2026-01-01',
        'flockAgeWeeks': 40,
        'storagePeriodDays': 5,
        'shellTemp': 20.1,
        'estAvg': 20.1,
        'estCvPct': 1.2,
        'upsideDownCount': 4,
        'upsideDownPct': 4.0,
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': '2026-01-01T00:00:00Z',
      });
      await db.insert('egg_quality', {
        'id': 'egg-quality-1',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'flockId': 'flock-1',
        'date': '2026-01-01',
        'uvTrayEggCount': 100,
        'uvCuticleDamageCount': 2,
        'uvCuticleDamagePct': 2.0,
        'uvWashedCount': 1,
        'uvWashedPct': 1.0,
        'uvDirtyCount': 2,
        'uvDirtyPct': 2.0,
        'uvAffectedCount': 5,
        'uvAffectedPct': 5.0,
        'eggWeightsJson': '[60,62,64]',
        'eggSampleSize': 3,
        'eggAvgWeight': 62.0,
        'eggUniformityPct': 100.0,
        'eggCvPct': 3.2,
        'eggBmkAgeWeeks': 40,
        'eggBmkWeight': 63.0,
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': '2026-01-01T00:00:00Z',
      });
      await db.insert('chick_quality', {
        'id': 'chick-quality-1',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'flockId': 'flock-1',
        'date': '2026-01-01',
        'flockAgeWeeks': 40,
        'setter': 'S-clear',
        'culledChicksTotalEggSet': 19200,
        'culledChicksAnalysisJson': jsonEncode([
          {'id': 'navel_open_unhealed', 'pct': 3 / 19200 * 100},
          {'id': 'legs_red_hocks', 'pct': 2 / 19200 * 100},
        ]),
        'culledChicksAffectedPct': 5 / 19200 * 100,
        'culledChicksTopCategory': 'Navel',
        'culledChicksTopSubtype': 'Open / unhealed navel',
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': '2026-01-01T00:00:00Z',
      });
      await db.insert('chick_quality', {
        'id': 'chick-quality-clear',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'flockId': 'flock-1',
        'date': '2026-01-01',
        'flockAgeWeeks': 40,
        'culledChicksTotalEggSet': 19200,
        'createdAt': '2026-01-01T00:00:01Z',
        'updatedAt': '2026-01-01T00:00:01Z',
      });
      await db.insert('residue_breakout', {
        'id': 'residue-1',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'flockId': 'flock-1',
        'date': '2026-01-01',
        'traySize': 100,
        'hatchabilityPct': 86.0,
        'fertilityPct': 92.0,
        'hofPct': 93.5,
        'culledPct': 2.0,
        'deadPct': 1.0,
        'bmkAgeWeeks': 40,
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': '2026-01-01T00:00:00Z',
      });

      final filter = DashboardFilter(customerId: 'customer-1', bmkAge: 40);
      final chickTrend = await repository.getChickWeightTrend(filter);
      final culledChicks = await repository.getCulledChicksAnalysis(filter);
      final eggTrend = await repository.getEggStorageTrend(filter);
      final hatchAvg = await repository.getHatchAnalysisAvg(filter);
      final ages = await repository.getDistinctBmkAges(
        customerId: 'customer-1',
      );

      expect(chickTrend, hasLength(1));
      expect(chickTrend!.single.avgWeightG, 42.0);
      expect(culledChicks?.totalEggSet, 38400);
      expect(culledChicks?.affectedPct, closeTo(5 / 38400 * 100, 0.000001));
      expect(culledChicks?.topCategory, 'Navel');
      expect(culledChicks?.topSubtype, 'Open / unhealed navel');
      expect(eggTrend, hasLength(1));
      expect(eggTrend!.single.avgWeightG, 62.0);
      expect(eggTrend.single.uniformityPct, 100.0);
      expect(eggTrend.single.uvAffectedPct, 5.0);
      expect((eggTrend.single as dynamic).uvCuticleDamagePct, 2.0);
      expect((eggTrend.single as dynamic).uvWashedPct, 1.0);
      expect((eggTrend.single as dynamic).uvDirtyPct, 2.0);
      expect((eggTrend.single as dynamic).eggSampleSize, 3);
      expect((eggTrend.single as dynamic).eggBmkWeight, 63.0);
      expect(hatchAvg?.hatchabilityPct, 86.0);
      expect(ages, contains(40));
    },
  );
}

Future<void> _resetDatabase() async {
  await DatabaseHelper().close();
  final dbPath = p.join(
    await databaseFactory.getDatabasesPath(),
    'hatchaudit.db',
  );
  await databaseFactory.deleteDatabase(dbPath);
}

Future<Set<String>> _tableNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  return rows.map((row) => row['name'] as String).toSet();
}
