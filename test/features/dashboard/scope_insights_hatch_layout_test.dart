import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/database/seeds/dashboard_demo_seeds.dart';
import 'package:hatchaudit/data/repositories/panel_dashboard_repository.dart';
import 'package:hatchaudit/data/repositories/scope_comparison_repository.dart';
import 'package:hatchaudit/features/dashboard/models/hatch_analysis_models.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_intelligence_models.dart';
import 'package:hatchaudit/features/dashboard/providers/scope_comparison_provider.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_models.dart';
import 'package:hatchaudit/features/dashboard/widgets/scope/scope_insights_section.dart';
import 'package:hatchaudit/features/dashboard/widgets/scope/scope_matrix_table.dart';
import 'package:provider/provider.dart';

/// Forces the demo-customer dummy fallback (real leaves empty), so every sector
/// — including the Hatch station's hatch_results + the 3 breakouts — populates.
class _EmptyScopeRepo extends ScopeComparisonRepository {
  @override
  Future<List<ScopeLeafRow>> getScopeLeaves(sector, filter) async => const [];
  @override
  Future<int?> dominantBmkAge(filter) async => null;
  @override
  Future<ScopeDataBundle> loadBundle(sectors, filter) async =>
      const ScopeDataBundle();
}

/// Canned Hatch age series so the chart has data without a DB.
class _FakePanelRepo extends PanelDashboardRepository {
  final List<HatchAgePoint> points;
  final Map<String, List<String>> photosByPanel;
  _FakePanelRepo(this.points, {this.photosByPanel = const {}});
  @override
  Future<List<HatchAgePoint>> getHatchByAge(filter) async => points;

  @override
  Future<List<String>> getPhotoPaths(
    filter,
    String panelName,
    String fieldKey,
  ) {
    return Future.value(photosByPanel[panelName] ?? const []);
  }
}

class _RecordedBreakoutScopeRepo extends ScopeComparisonRepository {
  _RecordedBreakoutScopeRepo(this.recordedSectorIds);

  final Set<String> recordedSectorIds;

  @override
  Future<List<ScopeLeafRow>> getScopeLeaves(sector, filter) async {
    if (!recordedSectorIds.contains(sector.id)) return const [];
    return [
      ScopeLeafRow(
        layerSegments: {
          SamplingLayer.house: 'H1',
          SamplingLayer.setterHatcher: 'S1H1',
          SamplingLayer.trolley: 'Tr1',
          SamplingLayer.tray: 'Ty1',
        },
        cells: {
          'infertilePct': ScopeCellAccumulator.sample(
            value: 4,
            count: 4,
            traySize: 100,
          ),
        },
      ),
    ];
  }

  @override
  Future<int?> dominantBmkAge(filter) async => null;

  @override
  Future<ScopeDataBundle> loadBundle(sectors, filter) async {
    final leaves = <String, List<ScopeLeafRow>>{};
    for (final sector in sectors) {
      final rows = await getScopeLeaves(sector, filter);
      if (rows.isNotEmpty) leaves[sector.id] = rows;
    }
    return ScopeDataBundle(leavesBySector: leaves);
  }
}

class _ScopeInsightsHarness extends StatefulWidget {
  const _ScopeInsightsHarness();

  @override
  State<_ScopeInsightsHarness> createState() => _ScopeInsightsHarnessState();
}

class _ScopeInsightsHarnessState extends State<_ScopeInsightsHarness> {
  final Set<String> _collapsedStations = <String>{};

  @override
  Widget build(BuildContext context) {
    return ScopeInsightsSection(
      collapsedStations: _collapsedStations,
      onStationToggle: (station) {
        setState(() {
          if (!_collapsedStations.add(station)) {
            _collapsedStations.remove(station);
          }
        });
      },
    );
  }
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    void Function(ScopeComparisonProvider)? prime,
    PanelDashboardRepository? panelRepo,
    ScopeComparisonRepository? repository,
  }) async {
    final provider = ScopeComparisonProvider(
      repository: repository ?? _EmptyScopeRepo(),
      panelRepository: panelRepo ?? _FakePanelRepo(const []),
    );
    await provider.applyFilter(
      customerId: kDashboardDemoCustomerId,
      hatcheryId: 'hatchery-dashboard-demo',
    );
    prime?.call(provider);
    await tester.pumpWidget(
      ChangeNotifierProvider<ScopeComparisonProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: _ScopeInsightsHarness()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Hatch station hides unrecorded dummy breakout tabs', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Hatch Result'), findsOneWidget); // renamed sector title
    // Card trimmed to the 3 rate metrics — dropped count tiles are gone.
    expect(find.text('Hatched'), findsNothing);
    expect(find.text('Infert'), findsNothing);
    expect(find.text('Breakout'), findsNothing);
    expect(find.text('Fresh'), findsNothing);
    expect(find.text('Candled'), findsNothing);
    expect(find.text('Residue'), findsNothing);
  });

  testWidgets('Breakout dashboard shows recorded types and their photos only', (
    tester,
  ) async {
    final provider = ScopeComparisonProvider(
      repository: _RecordedBreakoutScopeRepo({'candled_egg_breakout'}),
      panelRepository: _FakePanelRepo(
        const [],
        photosByPanel: const {
          'candled_egg_breakout': ['/tmp/chickmark-candled-breakout.jpg'],
        },
      ),
    );
    await provider.applyFilter(
      customerId: 'customer-1',
      hatcheryId: 'hatchery-1',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ScopeComparisonProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: _ScopeInsightsHarness()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Candled'), findsOneWidget);
    expect(find.text('Fresh'), findsNothing);
    expect(find.text('Residue'), findsNothing);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.byIcon(Icons.image), findsOneWidget);
  });

  testWidgets('Breakout defaults to Fresh and switches on tab tap', (
    tester,
  ) async {
    await pump(
      tester,
      repository: _RecordedBreakoutScopeRepo({
        'fresh_egg_breakout',
        'residue_breakout',
      }),
    );
    // 'Late %' is a residue-only param → absent from the Fresh breakout matrix.
    // (It can surface in the station triage summary above, so scope the finder
    // to the breakout matrix itself.)
    expect(
      find.descendant(
        of: find.byType(ScopeMatrixTable),
        matching: find.text('Late %'),
      ),
      findsNothing,
    );

    // Hatch is far down the single scroll view — bring the pill on-screen so the
    // tap's hit-test lands.
    await tester.ensureVisible(find.text('Residue'));
    await tester.tap(find.text('Residue'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('breakout-residue_breakout')),
      findsOneWidget,
    );
  });

  testWidgets('Hatch Result chart mode renders a per-metric age chart', (
    tester,
  ) async {
    await pump(
      tester,
      panelRepo: _FakePanelRepo(const [
        HatchAgePoint(
          age: 30,
          hatchAct: 83.8,
          fertAct: 92.0,
          hofAct: 91.5,
          hatchBmk: 90.0,
          fertBmk: 95.0,
          hofBmk: 86.0,
        ),
        HatchAgePoint(
          age: 35,
          hatchAct: 85.0,
          fertAct: 93.0,
          hofAct: 92.0,
          hatchBmk: 89.0,
          fertBmk: 94.0,
          hofBmk: 85.0,
        ),
      ]),
      prime: (p) => p.toggleChartMode('hatch_results'),
    );

    // One chart per metric, Act-vs-BMK bars, age on the X axis.
    expect(find.text('Hatchability %'), findsOneWidget);
    expect(find.text('Fertility %'), findsOneWidget);
    // 'HOF %' is also the hatch_results param label, so the triage summary above
    // can show it too — the chart count below is the real per-metric assertion.
    expect(find.text('HOF %'), findsWidgets);
    expect(find.byType(BarChart), findsNWidgets(3));
    expect(find.text('30w'), findsWidgets);
    expect(find.text('35w'), findsWidgets);
  });
}
