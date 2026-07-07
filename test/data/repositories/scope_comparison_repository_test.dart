import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/database/seeds/dashboard_demo_seeds.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/repositories/scope_comparison_repository.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_filter.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_config.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_engine.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

/// End-to-end DB test: a fresh DatabaseHelper open runs the demo seeder, then the
/// scope repository reads the seeded rows back. Proves the live query path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ScopeComparisonRepository repo;
  late GoveeCaptureRepository goveeRepo;

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  setUp(() async {
    await _resetDatabase();
    DatabaseHelper.seedDemoData = true; // this e2e test needs the demo rows
    await DatabaseHelper().db; // triggers onCreate + onOpen (demo seeding)
    repo = ScopeComparisonRepository();
    goveeRepo = GoveeCaptureRepository();
  });

  tearDown(resetAppDatabase);

  final residue = ScopeConfigRegistry.byId('residue_breakout');
  final demo = DashboardFilter(customerId: kDashboardDemoCustomerId);

  test('demo seeding yields 16 residue leaves with layer segments', () async {
    final leaves = await repo.getScopeLeaves(residue, demo);
    expect(leaves, hasLength(16));
    final first = leaves.first;
    expect(first.layerSegments[SamplingLayer.house], 'H1');
    expect(first.layerSegments[SamplingLayer.setterHatcher], 'S1H1');
    expect(first.layerSegments[SamplingLayer.trolley], 'Tr1');
    expect(first.layerSegments[SamplingLayer.tray], 'Ty1');
    expect(first.bmkAge, 30);
  });

  test('count-weighted pool infert is computed from live rows', () async {
    final leaves = await repo.getScopeLeaves(residue, demo);
    final groups = ScopeEngine.comboGroups(residue, leaves, const [], null);
    expect(groups, hasLength(1));
    final infert = groups.first.cells[0].value!; // Infert % is param 0
    expect(infert, greaterThan(7.0));
    expect(infert, lessThan(8.6));
  });

  test('full layer selection yields 16 nested leaf columns', () async {
    final leaves = await repo.getScopeLeaves(residue, demo);
    final groups = ScopeEngine.comboGroups(
      residue,
      leaves,
      ScopeEngine.nonPoolLayers(residue),
      null,
    );
    expect(groups, hasLength(16));
    expect(groups.first.label, 'H1·S1H1·Tr1·Ty1');
  });

  test('dominantBmkAge resolves the seeded age', () async {
    expect(await repo.dominantBmkAge(demo), 30);
  });

  test('a non-demo customer has no seeded rows', () async {
    final leaves = await repo.getScopeLeaves(
      residue,
      DashboardFilter(customerId: 'cust-nobody'),
    );
    expect(leaves, isEmpty);
  });

  test(
    'demo seeding leaves الغريب plus dashboard test customer data',
    () async {
      final db = await DatabaseHelper().db;
      final rows = await db.query('customers', orderBy: 'name ASC');
      expect(rows, hasLength(2));
      expect(rows.map((row) => row['id']).toSet(), {
        'cust-al-ghareeb',
        kDashboardDemoCustomerId,
      });
      expect(rows.map((row) => row['name']).toSet(), {
        'الغريب',
        'Dashboard Test Customer',
      });
    },
  );

  test(
    'demo seeding adds five Govee readings for every dashboard place',
    () async {
      final captures = await goveeRepo.getCapturesForDashboard(
        customerId: kDashboardDemoCustomerId,
        hatcheryId: 'hatchery-dashboard-demo',
        captureDate: '2026-06-01',
      );

      expect(captures, hasLength(6));
      expect(captures.map((capture) => capture.place).toSet(), {
        TemperaturePlace.eggStorageRoom,
        TemperaturePlace.chickHoldingArea,
        TemperaturePlace.setterRoom,
        TemperaturePlace.insideSetter,
        TemperaturePlace.hatcherRoom,
        TemperaturePlace.insideHatcher,
      });
      for (final capture in captures) {
        expect(capture.readingCount, 5);
        expect(capture.chartReadings, hasLength(5));
      }
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
