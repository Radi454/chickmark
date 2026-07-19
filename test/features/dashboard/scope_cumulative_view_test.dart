import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/repositories/panel_dashboard_repository.dart';
import 'package:hatchaudit/data/repositories/scope_comparison_repository.dart';
import 'package:hatchaudit/features/dashboard/models/egg_storage_models.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_filter.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_intelligence_models.dart';
import 'package:hatchaudit/features/dashboard/models/scope_cumulative.dart';
import 'package:hatchaudit/features/dashboard/providers/scope_comparison_provider.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_models.dart';
import 'package:hatchaudit/features/dashboard/widgets/scope/scope_sector_widget.dart';
import 'package:provider/provider.dart';

/// Widget test with in-memory fake repos (no real DB → completes under the
/// FakeAsync zone testWidgets runs in). Proves a real-data sector gets an
/// age-first table and can switch the same dataset to the existing chart view.
class _FakeScopeRepo extends ScopeComparisonRepository {
  @override
  Future<List<ScopeLeafRow>> getScopeLeaves(sector, filter) async {
    if (sector.id != 'residue_breakout') return const [];
    final w25 = [
      _leaf(25, 7.0, house: 'H1', tray: 'Ty1'),
      _leaf(25, 7.4, house: 'H1', tray: 'Ty1'),
    ];
    final w36 = [
      _leaf(36, 8.0, house: 'H1', tray: 'Ty1'),
      _leaf(36, 8.2, house: 'H1', tray: 'Ty2'),
      _leaf(36, 8.4, house: 'H2', tray: 'Ty1'),
      _leaf(36, 8.6, house: 'H2', tray: 'Ty2'),
    ];
    if (filter.bmkAge == 25) return w25;
    if (filter.bmkAge == 36) return w36;
    return [...w25, ...w36];
  }

  @override
  Future<List<ScopePeriod>> distinctPeriods(sector, base) async => const [
    ScopePeriod(label: 'W25', age: 25, n: 2),
    ScopePeriod(label: 'W36', age: 36, n: 4),
  ];

  @override
  Future<int?> dominantBmkAge(filter) async => 36;

  @override
  Future<ScopeDataBundle> loadBundle(sectors, DashboardFilter filter) async {
    final sector = sectors.firstWhere((item) => item.id == 'residue_breakout');
    final leaves = await getScopeLeaves(sector, filter);
    return ScopeDataBundle(
      leavesBySector: {'residue_breakout': leaves},
      periodsBySector: {
        'residue_breakout': await distinctPeriods(sector, filter),
      },
    );
  }

  ScopeLeafRow _leaf(
    int age,
    num infert, {
    required String house,
    required String tray,
  }) => ScopeLeafRow(
    bmkAge: age,
    layerSegments: {SamplingLayer.house: house, SamplingLayer.tray: tray},
    cells: {
      'infertilePct': ScopeCellAccumulator.sample(
        value: infert,
        traySize: 750,
        count: infert / 100 * 750,
      ),
    },
  );
}

class _FakePanelRepo extends PanelDashboardRepository {
  @override
  Future<BmkReference?> getBmkReferenceForAge(int ageWeek) async => null;

  @override
  Future<List<String>> getPhotoPaths(
    DashboardFilter filter,
    String panelName,
    String fieldKey,
  ) async => const [];
}

void main() {
  Future<void> settle(WidgetTester tester, [int frames = 12]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<ScopeComparisonProvider> pumpResidue(WidgetTester tester) async {
    final provider = ScopeComparisonProvider(
      repository: _FakeScopeRepo(),
      panelRepository: _FakePanelRepo(),
    );
    await provider.applyFilter(customerId: 'cust-1', hatcheryId: 'hatchery-1');
    await tester.pumpWidget(
      ChangeNotifierProvider<ScopeComparisonProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScopeSectorWidget(sectorId: 'residue_breakout'),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    return provider;
  }

  testWidgets('real-data sector defaults to the all-BMK-age table', (
    tester,
  ) async {
    await pumpResidue(tester);
    expect(find.text('Example data'), findsNothing); // real data → not dummy
    expect(find.text('Incremental'), findsNothing);
    expect(find.text('Cumulative'), findsNothing);
    expect(find.text('All BMK Ages'), findsOneWidget);
    expect(find.text('W25'), findsWidgets);
    expect(find.text('W36'), findsWidgets);
    expect(find.text('AVG'), findsOneWidget);
    expect(find.text('Tray'), findsNothing);
    expect(find.byType(LineChart), findsNothing);
  });

  testWidgets('existing chart icon switches the age table to a chart', (
    tester,
  ) async {
    await pumpResidue(tester);
    await tester.tap(find.byIcon(Icons.bar_chart));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      if (find.byType(LineChart).evaluate().isNotEmpty) break;
    }

    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('Pool'), findsOneWidget);
    expect(find.text('W25'), findsWidgets);
    expect(find.text('All BMK Ages'), findsOneWidget);
  });

  testWidgets(
    'specific age starts pooled and supports valid multi-level filters',
    (tester) async {
      await pumpResidue(tester);

      await tester.tap(find.text('All BMK Ages'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('W36').last);
      await settle(tester, 20);

      expect(find.text('Pool'), findsWidgets);
      expect(find.text('House'), findsOneWidget);
      expect(find.text('Tray'), findsOneWidget);
      expect(find.text('Machine'), findsNothing);
      expect(find.text('Trolley'), findsNothing);

      await tester.tap(find.text('House'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tray'));
      await tester.pumpAndSettle();

      expect(find.text('H1·Ty1'), findsWidgets);
      expect(find.text('H2·Ty2'), findsWidgets);
      expect(find.text('⌀ Avg'), findsWidgets);
    },
  );
}
