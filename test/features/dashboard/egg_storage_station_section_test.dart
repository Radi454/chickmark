import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/features/dashboard/models/egg_storage_models.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/dashboard/providers/scope_comparison_provider.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_models.dart';
import 'package:hatchaudit/features/dashboard/widgets/scope/alarm_triage_feed.dart';
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

  _StaticScope(this.groups);

  @override
  bool get isLoading => false;

  @override
  List<ScopeGroup> groupsFor(String sectorId) => groups[sectorId] ?? const [];

  @override
  bool isDummyFor(String sectorId) => false;

  @override
  bool isEmptyFor(String sectorId) => groupsFor(sectorId).isEmpty;

  // The canned groups carry no accumulators, so steer the "Compare houses"
  // matrix away from the ⌀ Avg path (which folds accumulators) — it renders from
  // the per-house cells alone.
  @override
  List<int> visibleColumnIndexes(String sectorId) =>
      [for (var i = 0; i < groupsFor(sectorId).length; i++) i];

  @override
  bool isAvgVisible(String sectorId) => false;

  @override
  List<ColumnStat> columnStatsFor(String sectorId) => const [];
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
    accumulators: const [],
    severity: ScopeSeverity.good,
  );
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    EggStorageTrend? latest,
    EggStorageEstEvidence? evidence,
    required List<ScopeGroup> houses,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DashboardProvider>.value(
            value: _StaticDashboard(latest: latest, evidence: evidence),
          ),
          ChangeNotifierProvider<ScopeComparisonProvider>.value(
            value: _StaticScope({'egg_quality': houses}),
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

    expect(
      find.textContaining('within target'),
      findsOneWidget,
    );
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

  testWidgets('switches Egg Quality between house tabs', (tester) async {
    await pump(
      tester,
      latest: EggStorageTrend.fromMap(const {'storageDays': 6, 'estAvgF': 19.0}),
      houses: [
        _house('House A', [95, 62.0, 88.0, 6.0, 61.0, 2.0, 1.0, 0.5, 0.5]),
        _house('House B', [90, 60.0, 70.0, 9.0, 61.0, 8.0, 3.0, 2.0, 3.0]),
      ],
    );

    // Both tabs present; House A is selected first → its uniformity shows.
    // (House B also appears as a triage chip, so it's findsWidgets not one.)
    expect(find.text('House A'), findsOneWidget);
    expect(find.text('House B'), findsWidgets);
    expect(find.text('88.0%'), findsOneWidget);

    // Tabs sit below the 600px test viewport — scroll the pill on-screen so the
    // tap's hit-test lands.
    await tester.ensureVisible(find.text('House B').last);
    await tester.tap(find.text('House B').last);
    await tester.pumpAndSettle();

    // House B's out-of-spec uniformity is now visible (tile + triage card).
    expect(find.text('70.0%'), findsWidgets);
  });

  testWidgets('Compare houses reveal toggles the comparison matrix', (
    tester,
  ) async {
    await pump(
      tester,
      latest: EggStorageTrend.fromMap(const {'storageDays': 6, 'estAvgF': 19.0}),
      houses: [
        _house('House A', [95, 62.0, 88.0, 6.0, 61.0, 2.0, 1.0, 0.5, 0.5]),
        _house('House B', [90, 60.0, 70.0, 9.0, 61.0, 8.0, 3.0, 2.0, 3.0]),
      ],
    );

    // Lazy: matrix stays out of the tree until the reveal is opened.
    expect(find.byType(ScopeMatrixTable), findsNothing);

    await tester.ensureVisible(find.text('Compare houses'));
    await tester.tap(find.text('Compare houses'));
    await tester.pumpAndSettle();

    expect(find.byType(ScopeMatrixTable), findsOneWidget);
  });
}
