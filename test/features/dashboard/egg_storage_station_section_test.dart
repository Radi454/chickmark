import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/features/dashboard/models/egg_storage_models.dart';
import 'package:hatchaudit/features/dashboard/models/scope_cumulative.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/dashboard/providers/scope_comparison_provider.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_config.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_models.dart';
import 'package:hatchaudit/features/dashboard/widgets/scope/alarm_triage_feed.dart';
import 'package:hatchaudit/features/dashboard/widgets/scope/scope_cumulative_view.dart';
import 'package:hatchaudit/features/dashboard/widgets/scope/scope_matrix_table.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/egg_storage_station_section.dart';
import 'package:provider/provider.dart';

/// Static [DashboardProvider] feeding the pooled EST / upside / checklist data.
class _StaticDashboard extends DashboardProvider {
  final EggStorageTrend? latest;
  final EggStorageEstEvidence? evidence;

  _StaticDashboard({this.latest, this.evidence});

  @override
  bool get isLoading => false;

  @override
  List<EggStorageTrend> get eggStorageTrend =>
      latest == null ? const [] : [latest!];

  @override
  EggStorageTrend? get eggStorageLatest => latest;

  @override
  EggStorageEstEvidence? get eggStorageEstEvidence => evidence;
}

/// Scope provider stub returning canned per-house Egg Quality groups.
class _StaticScope extends ScopeComparisonProvider {
  final Map<String, List<ScopeGroup>> groups;
  final bool allAges;

  _StaticScope(this.groups, {this.allAges = false});

  @override
  bool get isLoading => false;

  @override
  List<ScopeGroup> groupsFor(String sectorId) => groups[sectorId] ?? const [];

  @override
  bool isDummyFor(String sectorId) => false;

  @override
  bool isEmptyFor(String sectorId) => groupsFor(sectorId).isEmpty;

  @override
  List<SamplingLayer> eligibleLayersFor(String sectorId) =>
      groupsFor(sectorId).length >= 2 ? const [SamplingLayer.house] : const [];

  @override
  List<ScopePeriod> periodsFor(String sectorId) => sectorId == 'egg_quality'
      ? const [ScopePeriod(label: 'W30', age: 30, n: 2)]
      : const [];

  @override
  ScopePeriod? selectedPeriodFor(String sectorId) =>
      allAges || sectorId != 'egg_quality'
      ? null
      : const ScopePeriod(label: 'W30', age: 30, n: 2);

  @override
  CumulativeSeries? cumulativeSeriesFor(String sectorId) {
    if (!allAges || sectorId != 'egg_quality') return null;
    final sector = ScopeConfigRegistry.byId('egg_quality');
    final cumulativeGroups = [
      for (final group in groupsFor(sectorId))
        CumulativeGroup(
          label: group.label,
          params: [
            for (var i = 0; i < sector.params.length; i++)
              CumulativeParam(
                param: sector.params[i],
                values: [group.cells[i].value],
                bmks: const [null],
                texts: [group.cells[i].text],
                severities: [group.cells[i].severity],
                averageValue: group.cells[i].value,
                averageText: group.cells[i].text,
              ),
          ],
        ),
    ];
    return CumulativeSeries(
      periods: const [ScopePeriod(label: 'W30', age: 30, n: 2)],
      groups: cumulativeGroups,
      params: cumulativeGroups.first.params,
    );
  }

  @override
  Future<void> loadCumulative(String sectorId) async {}

  @override
  ScopeGroup? poolGroupFor(String sectorId) {
    final houseGroups = groupsFor(sectorId);
    if (houseGroups.isEmpty) return null;
    final cells = <ScopeCell>[];
    final accumulators = <ScopeCellAccumulator>[];
    for (var i = 0; i < houseGroups.first.cells.length; i++) {
      final values = [
        for (final group in houseGroups)
          if (i < group.cells.length && group.cells[i].value != null)
            group.cells[i].value!,
      ];
      final value = values.isEmpty
          ? null
          : values.reduce((a, b) => a + b) / values.length;
      cells.add(
        ScopeCell(text: value?.toStringAsFixed(1) ?? '—', value: value),
      );
      var accumulator = const ScopeCellAccumulator();
      for (final group in houseGroups) {
        accumulator = accumulator.combine(group.accumulators[i]);
      }
      accumulators.add(accumulator);
    }
    return ScopeGroup(
      label: 'Pool',
      layer: null,
      cells: cells,
      accumulators: accumulators,
      severity: ScopeSeverity.pool,
    );
  }
}

/// Build an egg_quality group whose cells align to that sector's 9 params:
/// [sample, avgWt, uniformity, cv, bmkWt, uvAffected, cuticle, washed, dirty].
ScopeGroup _house(String label, List<num?> values) {
  return ScopeGroup(
    label: label,
    layer: SamplingLayer.house,
    cells: [
      for (final v in values)
        ScopeCell(text: v == null ? '—' : v.toString(), value: v),
    ],
    accumulators: [
      for (final v in values) ScopeCellAccumulator.sample(value: v),
    ],
    severity: ScopeSeverity.good,
  );
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    EggStorageTrend? latest,
    EggStorageEstEvidence? evidence,
    required List<ScopeGroup> houses,
    bool allAges = false,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DashboardProvider>.value(
            value: _StaticDashboard(latest: latest, evidence: evidence),
          ),
          ChangeNotifierProvider<ScopeComparisonProvider>.value(
            value: _StaticScope({'egg_quality': houses}, allAges: allAges),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: EggStorageStationSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the audit-station sub-cards in order', (tester) async {
    await pump(
      tester,
      latest: EggStorageTrend.fromMap(const {
        'estAvgF': 19.0, // within the 18-20°C medium-storage target
        'estCvPct': 5.0,
        'storageDays': 6,
        'turningTimes': 4,
        'traySpacing': 'Adequate',
        'coolerProximity': 'Far',
        'condensationPresent': false,
        'upsideDownCount': 4,
        'upsideDownPct': 1.2,
      }),
      evidence: EggStorageEstEvidence.fromJsonStrings(),
      houses: [
        _house('House A', [95, 62.0, 88.0, 6.0, 61.0, 2.0, 1.0, 0.5, 0.5]),
      ],
    );

    expect(find.byType(AlarmTriageFeed), findsOneWidget);
    expect(find.text('Egg Shell Temperature (EST)'), findsOneWidget);
    expect(find.text('Captured Photos'), findsOneWidget); // EST grid photo card
    expect(find.text('Upside Down Score'), findsOneWidget);
    expect(find.text('Storage Checklist'), findsOneWidget);
    expect(find.text('Egg Quality'), findsOneWidget);

    // EST summary tiles + checklist values.
    expect(find.text('19.0°C'), findsOneWidget);
    expect(find.text('18-20°C'), findsOneWidget);
    expect(find.text('6 days'), findsOneWidget);
    expect(find.text('4 times'), findsOneWidget);
  });

  testWidgets('all-clear state shows no action required', (tester) async {
    await pump(
      tester,
      latest: EggStorageTrend.fromMap(const {
        'estAvgF': 19.0,
        'estCvPct': 5.0,
        'storageDays': 6,
      }),
      houses: [
        _house('House A', [95, 62.0, 88.0, 6.0, 61.0, 2.0, 1.0, 0.5, 0.5]),
      ],
    );

    expect(find.textContaining('within target'), findsOneWidget);
  });

  testWidgets('collects EST and per-house alarms', (tester) async {
    await pump(
      tester,
      latest: EggStorageTrend.fromMap(const {
        'estAvgF': 27.1, // above the 18-20°C medium-storage target
        'estCvPct': 5.0,
        'storageDays': 6,
        'condensationPresent': true,
      }),
      houses: [
        // House B is out of spec on uniformity (<85), egg CV (>8), UV (>5).
        _house('House B', [90, 60.0, 70.0, 9.0, 61.0, 8.0, 3.0, 2.0, 3.0]),
      ],
    );

    // Triage groups by severity; the worst readings land in the Critical band.
    expect(find.text('CRITICAL — ACTION REQUIRED'), findsOneWidget);
    expect(find.text('EST Average'), findsOneWidget);
    expect(find.textContaining('27.1°C'), findsWidgets);
    // Condensation flag surfaces as its own item (Watch). The label also appears
    // on the Storage Checklist tile, so match the triage value instead.
    expect(find.text('Condensation'), findsWidgets);
    expect(find.text('Present'), findsOneWidget);
    // Per-house quality breaches name the metric; the house is a chip.
    expect(find.text('Egg Uniformity'), findsOneWidget);
    expect(find.text('UV Affected'), findsOneWidget);
  });

  testWidgets('renders Egg Quality as one Pool plus house scope sector', (
    tester,
  ) async {
    await pump(
      tester,
      latest: EggStorageTrend.fromMap(const {
        'storageDays': 6,
        'estAvgF': 19.0,
      }),
      houses: [
        _house('House A', [95, 62.0, 88.0, 6.0, 61.0, 2.0, 1.0, 0.5, 0.5]),
        _house('House B', [90, 60.0, 70.0, 9.0, 61.0, 8.0, 3.0, 2.0, 3.0]),
      ],
    );

    expect(find.text('Compare houses'), findsNothing);
    expect(find.text('Weights & Uniformity'), findsNothing);
    expect(find.text('W30'), findsOneWidget);
    expect(
      find.text('Break down by — add layers to narrow, remove to broaden'),
      findsOneWidget,
    );
    expect(find.text('Pool'), findsWidgets);
    expect(find.text('House A'), findsWidgets);
    expect(find.text('House B'), findsWidgets);
    expect(find.byType(ScopeMatrixTable), findsOneWidget);
  });

  testWidgets('one Egg Quality house hides the false House comparison', (
    tester,
  ) async {
    await pump(
      tester,
      latest: EggStorageTrend.fromMap(const {
        'storageDays': 6,
        'estAvgF': 19.0,
      }),
      houses: [
        _house('House A', [95, 62.0, 88.0, 6.0, 61.0, 2.0, 1.0, 0.5, 0.5]),
      ],
    );

    expect(
      find.text('Break down by — add layers to narrow, remove to broaden'),
      findsNothing,
    );
    expect(find.text('House'), findsNothing);
  });

  testWidgets('All BMK Ages uses the age table instead of pooling visits', (
    tester,
  ) async {
    await pump(
      tester,
      latest: EggStorageTrend.fromMap(const {
        'storageDays': 6,
        'estAvgF': 19.0,
      }),
      houses: [
        _house('House A', [95, 62.0, 88.0, 6.0, 61.0, 2.0, 1.0, 0.5, 0.5]),
        _house('House B', [90, 60.0, 70.0, 9.0, 61.0, 8.0, 3.0, 2.0, 3.0]),
      ],
      allAges: true,
    );

    expect(find.text('All BMK Ages'), findsOneWidget);
    expect(find.byType(ScopeCumulativeView), findsOneWidget);
    expect(find.text('W30'), findsWidgets);
    expect(find.text('AVG'), findsOneWidget);
  });

  testWidgets('Pool and houses can be selected or hidden from Egg Quality', (
    tester,
  ) async {
    await pump(
      tester,
      latest: EggStorageTrend.fromMap(const {
        'storageDays': 6,
        'estAvgF': 19.0,
      }),
      houses: [
        _house('House A', [95, 62.0, 88.0, 6.0, 61.0, 2.0, 1.0, 0.5, 0.5]),
        _house('House B', [90, 60.0, 70.0, 9.0, 61.0, 8.0, 3.0, 2.0, 3.0]),
      ],
    );

    expect(find.text('Pool'), findsWidgets);
    expect(find.text('House A'), findsWidgets);
    expect(find.text('62.0'), findsOneWidget);

    await tester.ensureVisible(find.text('House A').first);
    await tester.tap(find.text('House A').first);
    await tester.pumpAndSettle();

    expect(find.text('62.0'), findsNothing);
    expect(find.text('House B'), findsWidgets);
  });

  testWidgets('Egg Quality has a chart toggle', (tester) async {
    await pump(
      tester,
      latest: EggStorageTrend.fromMap(const {
        'storageDays': 6,
        'estAvgF': 19.0,
      }),
      houses: [
        _house('House A', [95, 62.0, 88.0, 6.0, 61.0, 2.0, 1.0, 0.5, 0.5]),
        _house('House B', [90, 60.0, 70.0, 9.0, 61.0, 8.0, 3.0, 2.0, 3.0]),
      ],
    );

    await tester.ensureVisible(find.byIcon(Icons.bar_chart));
    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.table_chart_outlined), findsOneWidget);
    expect(find.text('Avg wt g'), findsWidgets);
  });

  testWidgets('Egg Quality chart fits common house counts and shows average', (
    tester,
  ) async {
    await pump(
      tester,
      latest: EggStorageTrend.fromMap(const {
        'storageDays': 6,
        'estAvgF': 19.0,
      }),
      houses: [
        _house('Pool source', [95, 62.0, 88.0, 6.0, 61.0, 2.0, 1.0, 0.5, 0.5]),
        _house('1', [100, 57.9, 90.0, 12.9, 65.0, 2.0, 1.0, 0.5, 0.5]),
        _house('4', [100, 58.1, 93.3, 7.1, 65.0, 2.0, 1.0, 0.5, 0.5]),
        _house('5', [100, 57.8, 91.7, 7.4, 65.0, 2.0, 1.0, 0.5, 0.5]),
        _house('6', [100, 58.0, 89.8, 8.2, 65.0, 2.0, 1.0, 0.5, 0.5]),
        _house('7', [100, 57.7, 91.1, 8.0, 65.0, 2.0, 1.0, 0.5, 0.5]),
        _house('8', [100, 58.2, 90.7, 7.8, 65.0, 2.0, 1.0, 0.5, 0.5]),
      ],
    );

    await tester.ensureVisible(find.byIcon(Icons.bar_chart));
    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle();

    final chart = tester.widget<BarChart>(find.byType(BarChart));
    expect(
      chart.data.barGroups.every((group) => group.barRods.length == 2),
      isTrue,
    );
    expect(
      chart.data.barGroups.every(
        (group) => group.showingTooltipIndicators.isEmpty,
      ),
      isTrue,
    );
    expect(find.text('Act'), findsOneWidget);
    expect(find.text('BMK'), findsOneWidget);
    expect(chart.data.extraLinesData.horizontalLines, hasLength(1));
    expect(chart.data.extraLinesData.horizontalLines.single.dashArray, [4, 5]);
    final chartBox = tester.getSize(find.byType(BarChart));
    final scrollBox = tester.getSize(
      find.byKey(const ValueKey('egg-quality-chart-scroll')),
    );
    expect(chartBox.width, lessThanOrEqualTo(scrollBox.width + 1));
  });
}
