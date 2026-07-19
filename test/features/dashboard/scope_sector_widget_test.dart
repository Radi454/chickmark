import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/seeds/dashboard_demo_seeds.dart';
import 'package:hatchaudit/data/repositories/scope_comparison_repository.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_intelligence_models.dart';
import 'package:hatchaudit/features/dashboard/providers/scope_comparison_provider.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_models.dart';
import 'package:hatchaudit/features/dashboard/widgets/scope/scope_sector_widget.dart';
import 'package:provider/provider.dart';

class _EmptyScopeRepo extends ScopeComparisonRepository {
  @override
  Future<List<ScopeLeafRow>> getScopeLeaves(sector, filter) async => const [];
  @override
  Future<int?> dominantBmkAge(filter) async => null;
  @override
  Future<ScopeDataBundle> loadBundle(sectors, filter) async =>
      const ScopeDataBundle();
}

void main() {
  void setPhoneViewport(
    WidgetTester tester, {
    double width = 360,
    double height = 844,
    double textScale = 1.5,
  }) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<void> pumpResidue(WidgetTester tester) async {
    final provider = ScopeComparisonProvider(repository: _EmptyScopeRepo());
    await provider.applyFilter(
      customerId: kDashboardDemoCustomerId,
      hatcheryId: 'hatchery-dashboard-demo',
    );
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
    await tester.pumpAndSettle();
  }

  testWidgets('residue starts pooled instead of inventing hierarchy filters', (
    tester,
  ) async {
    await pumpResidue(tester);
    expect(find.text('Pool'), findsWidgets);
    expect(find.text('H1·S1H1·Tr1·Ty1'), findsNothing);
    expect(find.text('Tray'), findsNothing);
    expect(find.text('Example data'), findsOneWidget);
  });

  testWidgets('candled matrix renders the weighted ⌀ Avg column', (
    tester,
  ) async {
    final provider = ScopeComparisonProvider(repository: _EmptyScopeRepo());
    await provider.applyFilter(
      customerId: kDashboardDemoCustomerId,
      hatcheryId: 'hatchery-dashboard-demo',
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<ScopeComparisonProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScopeSectorWidget(sectorId: 'candled_egg_breakout'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Leaves are 7.7% and 8.1% infert → only the Avg column shows 7.9%.
    expect(find.text('7.9%'), findsWidgets);
  });

  testWidgets('chart mode renders a bar chart', (tester) async {
    final provider = ScopeComparisonProvider(repository: _EmptyScopeRepo());
    await provider.applyFilter(
      customerId: kDashboardDemoCustomerId,
      hatcheryId: 'hatchery-dashboard-demo',
    );
    provider.toggleChartMode('residue_breakout');
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
    await tester.pumpAndSettle();
    expect(find.byType(BarChart), findsOneWidget);
  });

  testWidgets('unused comparison levels are hidden', (tester) async {
    await pumpResidue(tester);
    expect(find.text('House'), findsNothing);
    expect(find.text('Machine'), findsNothing);
    expect(find.text('Trolley'), findsNothing);
    expect(find.text('Tray'), findsNothing);
  });

  testWidgets('residue sector avoids phone overflow at large text scale', (
    tester,
  ) async {
    setPhoneViewport(tester);

    await pumpResidue(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Example data'), findsOneWidget);
  });
}
