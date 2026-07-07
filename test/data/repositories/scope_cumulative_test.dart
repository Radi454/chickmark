import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/database/seeds/dashboard_demo_seeds.dart';
import 'package:hatchaudit/data/repositories/scope_comparison_repository.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_filter.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_config.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

/// BMK-age period listing + period-filtered leaves against the seeded demo DB.
/// Every station enumerates ages so its dashboard selector has one consistent
/// age-first behavior. Period filtering reuses the dashboard leaf query.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ScopeComparisonRepository repo;

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  setUp(() async {
    await _resetDatabase();
    DatabaseHelper.seedDemoData = true;
    await DatabaseHelper().db;
    repo = ScopeComparisonRepository();
  });

  tearDown(resetAppDatabase);

  final demo = DashboardFilter(customerId: kDashboardDemoCustomerId);
  final residue = ScopeConfigRegistry.byId('residue_breakout');
  final setter = ScopeConfigRegistry.byId('setter_optimizing');

  test('age-axis distinctPeriods lists the seeded flock age', () async {
    expect(residue.cumulativeAxis, CumulativeAxis.age);
    final periods = await repo.distinctPeriods(residue, demo);
    expect(periods, isNotEmpty);
    expect(periods.every((p) => p.sessionId == null), isTrue);
    expect(periods.map((p) => p.age), contains(30));
    expect(periods.firstWhere((p) => p.age == 30).label, 'W30');
  });

  test('period filter narrows leaves to the chosen age', () async {
    final all = await repo.getScopeLeaves(residue, demo);
    final at30 = await repo.getScopeLeaves(residue, demo.copyWith(bmkAge: 30));
    final atNone = await repo.getScopeLeaves(
      residue,
      demo.copyWith(bmkAge: 999),
    );
    expect(at30, hasLength(all.length));
    expect(atNone, isEmpty);
  });

  test(
    'operational sectors also list BMK ages instead of session labels',
    () async {
      expect(setter.cumulativeAxis, CumulativeAxis.age);
      final periods = await repo.distinctPeriods(setter, demo);
      expect(periods, isNotEmpty);
      expect(periods.every((p) => p.age != null), isTrue);
      expect(periods.every((p) => p.sessionId == null), isTrue);

      // The BMK-age filter returns that age's rows.
      final age = periods.first.age!;
      final leaves = await repo.getScopeLeaves(
        setter,
        DashboardFilter(customerId: kDashboardDemoCustomerId, bmkAge: age),
      );
      expect(leaves, isNotEmpty);
      expect(leaves.every((leaf) => leaf.bmkAge == age), isTrue);
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
