import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/dashboard/models/egg_storage_models.dart';
import 'package:hatchaudit/features/dashboard/providers/scope_comparison_provider.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_config.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_engine.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_models.dart';
import 'package:hatchaudit/features/dashboard/widgets/scope/station_kpi_strip.dart';
import 'package:provider/provider.dart';

/// Feeds canned scope groups so the strip can be exercised without a DB.
class _FakeScopeProvider extends ScopeComparisonProvider {
  final Map<String, List<ScopeGroup>> _groups;
  final BmkReference? _bmk;

  _FakeScopeProvider(this._groups, this._bmk);

  @override
  bool get isLoading => false;

  @override
  List<ScopeGroup> groupsFor(String sectorId) => _groups[sectorId] ?? const [];

  @override
  BmkReference? bmkFor(String sectorId) => _bmk;
}

Future<void> _pump(WidgetTester tester, _FakeScopeProvider provider) {
  return tester.pumpWidget(
    ChangeNotifierProvider<ScopeComparisonProvider>.value(
      value: provider,
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: StationKpiStrip())),
      ),
    ),
  );
}

void _setPhoneViewport(
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

void main() {
  testWidgets('renders a card per station with empty-state placeholders', (
    tester,
  ) async {
    await _pump(tester, _FakeScopeProvider(const {}, null));
    await tester.pump();

    // One card for each station, all in the empty/no-data state.
    expect(find.text('Hatch', skipOffstage: false), findsOneWidget);
    expect(find.text('Egg Storage', skipOffstage: false), findsOneWidget);
    expect(find.text('Chicks', skipOffstage: false), findsOneWidget);
    expect(find.text('Setters', skipOffstage: false), findsOneWidget);
    expect(find.text('Hatchers', skipOffstage: false), findsOneWidget);
    expect(find.text('—', skipOffstage: false), findsNWidgets(5));
    expect(find.text('On spec', skipOffstage: false), findsNWidgets(5));
    expect(find.text('OK', skipOffstage: false), findsNWidgets(5));
  });

  testWidgets('flags a below-benchmark station as ACTION with off-spec count', (
    tester,
  ) async {
    final hatchSector = ScopeConfigRegistry.byId('hatch_results');
    final bmk = BmkReference(hatchabilityPct: 90, fertilityPct: 95, hofPct: 90);
    // Hatchability 82.4 vs BMK 90 → 7.6 below → err (ACTION).
    final leaf = ScopeLeafRow(
      layerSegments: const {},
      cells: {'hatchabilityPct': ScopeCellAccumulator.sample(value: 82.4)},
    );
    final groups = ScopeEngine.comboGroups(hatchSector, [leaf], const [], bmk);

    await _pump(tester, _FakeScopeProvider({'hatch_results': groups}, bmk));
    await tester.pump();

    // Hatch card shows the headline value and an ACTION status.
    expect(find.text('82.4%', skipOffstage: false), findsOneWidget);
    expect(find.text('ACTION', skipOffstage: false), findsOneWidget);
    expect(find.text('1 off-spec', skipOffstage: false), findsOneWidget);

    // The other four stations have no data → OK / On spec.
    expect(find.text('OK', skipOffstage: false), findsNWidgets(4));
    expect(find.text('On spec', skipOffstage: false), findsNWidgets(4));
  });

  testWidgets('mobile KPI strip avoids overflow at large text scale', (
    tester,
  ) async {
    _setPhoneViewport(tester);

    final hatchSector = ScopeConfigRegistry.byId('hatch_results');
    final bmk = BmkReference(hatchabilityPct: 90, fertilityPct: 95, hofPct: 90);
    final leaf = ScopeLeafRow(
      layerSegments: const {},
      cells: {'hatchabilityPct': ScopeCellAccumulator.sample(value: 82.4)},
    );
    final groups = ScopeEngine.comboGroups(hatchSector, [leaf], const [], bmk);

    await _pump(tester, _FakeScopeProvider({'hatch_results': groups}, bmk));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('ACTION', skipOffstage: false), findsOneWidget);
  });
}
