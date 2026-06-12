import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/repositories/panel_dashboard_repository.dart';
import 'package:hatchaudit/data/repositories/scope_comparison_repository.dart';
import 'package:hatchaudit/features/dashboard/models/egg_storage_models.dart';
import 'package:hatchaudit/features/dashboard/models/scope_cumulative.dart';
import 'package:hatchaudit/features/dashboard/providers/scope_comparison_provider.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_models.dart';
import 'package:hatchaudit/features/dashboard/widgets/scope/scope_sector_widget.dart';
import 'package:provider/provider.dart';

/// Widget test with in-memory fake repos (no real DB → completes under the
/// FakeAsync zone testWidgets runs in). Proves a real-data sector gets the
/// Incremental ⇄ Cumulative toggle + period picker, and switching renders the
/// per-axis trend (line chart + axis chips). Dummy/example sectors keep their
/// single view (covered by scope_sector_widget_test.dart).
class _FakeScopeRepo extends ScopeComparisonRepository {
  @override
  Future<List<ScopeLeafRow>> getScopeLeaves(sector, filter) async {
    final base = filter.bmkAge == 25 ? 7.0 : 8.0;
    return [_leaf(base), _leaf(base + 0.4)];
  }

  @override
  Future<List<ScopePeriod>> distinctPeriods(sector, base) async => const [
        ScopePeriod(label: 'W25', age: 25, n: 2),
        ScopePeriod(label: 'W36', age: 36, n: 2),
      ];

  @override
  Future<int?> dominantBmkAge(filter) async => 36;

  ScopeLeafRow _leaf(num infert) => ScopeLeafRow(
        layerSegments: const {SamplingLayer.house: 'H1'},
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
    await provider.applyFilter(customerId: 'cust-1');
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

  testWidgets('real-data sector exposes the mode toggle + period picker', (
    tester,
  ) async {
    await pumpResidue(tester);
    expect(find.text('Example data'), findsNothing); // real data → not dummy
    expect(find.text('Incremental'), findsOneWidget);
    expect(find.text('Cumulative'), findsOneWidget);
    expect(find.text('All'), findsOneWidget); // period picker default label
    expect(find.byType(LineChart), findsNothing); // Incremental: no trend chart
  });

  testWidgets('switching to Cumulative renders the trend view', (tester) async {
    await pumpResidue(tester);
    await tester.tap(find.text('Cumulative'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      if (find.byType(LineChart).evaluate().isNotEmpty) break;
    }

    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('Actual'), findsOneWidget); // chart legend
    expect(find.text('W25'), findsWidgets); // axis chip + x-axis label
    expect(find.text('Infert %'), findsWidgets); // cumulative table row
  });
}
