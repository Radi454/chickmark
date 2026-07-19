import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/seeds/dashboard_demo_seeds.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/repositories/panel_dashboard_repository.dart';
import 'package:hatchaudit/data/repositories/scope_comparison_repository.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_filter.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_intelligence_models.dart';
import 'package:hatchaudit/features/dashboard/models/egg_storage_models.dart';
import 'package:hatchaudit/features/dashboard/models/scope_cumulative.dart';
import 'package:hatchaudit/features/dashboard/providers/scope_comparison_provider.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_config.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_models.dart';

/// Returns no live rows → demo customer falls back to dummy; others go empty.
class _EmptyScopeRepo extends ScopeComparisonRepository {
  @override
  Future<List<ScopeLeafRow>> getScopeLeaves(sector, filter) async => const [];
  @override
  Future<int?> dominantBmkAge(filter) async => null;
  @override
  Future<ScopeDataBundle> loadBundle(sectors, filter) async =>
      const ScopeDataBundle();
}

class _AgeScopeRepo extends ScopeComparisonRepository {
  _AgeScopeRepo(this.byAge);

  final Map<int, List<ScopeLeafRow>> byAge;

  @override
  Future<List<ScopeLeafRow>> getScopeLeaves(
    ScopeSectorConfig sector,
    DashboardFilter filter,
  ) async {
    if (sector.id != 'residue_breakout') return const [];
    final age = filter.bmkAge;
    if (age != null) return byAge[age] ?? const [];
    return [for (final leaves in byAge.values) ...leaves];
  }

  @override
  Future<List<ScopePeriod>> distinctPeriods(
    ScopeSectorConfig sector,
    DashboardFilter base,
  ) async {
    if (sector.id != 'residue_breakout') return const [];
    final ages = byAge.keys.toList()..sort();
    return [
      for (final age in ages)
        ScopePeriod(label: 'W$age', age: age, n: byAge[age]!.length),
    ];
  }

  @override
  Future<int?> dominantBmkAge(DashboardFilter filter) async =>
      byAge.keys.isEmpty ? null : byAge.keys.reduce((a, b) => a > b ? a : b);

  @override
  Future<ScopeDataBundle> loadBundle(sectors, filter) async => ScopeDataBundle(
    leavesBySector: {
      'residue_breakout': [for (final rows in byAge.values) ...rows],
    },
    periodsBySector: {
      'residue_breakout': await distinctPeriods(
        ScopeConfigRegistry.byId('residue_breakout'),
        filter,
      ),
    },
  );
}

class _NoBmkPanelRepo extends PanelDashboardRepository {
  @override
  Future<BmkReference?> getBmkReferenceForAge(int ageWeek) async => null;

  @override
  Future<List<String>> getPhotoPaths(
    DashboardFilter filter,
    String panelName,
    String fieldKey,
  ) async => const [];
}

class _HistoryBmkPanelRepo extends _NoBmkPanelRepo {
  @override
  Future<BmkReference?> getBmkReferenceForAge(int ageWeek) async =>
      BmkReference(infertilePct: 5);
}

class _HistoryScopeRepo extends ScopeComparisonRepository {
  @override
  Future<int?> dominantBmkAge(DashboardFilter filter) async => 30;

  @override
  Future<ScopeDataBundle> loadBundle(sectors, filter) async {
    ScopeLeafRow leaf(String session, DateTime at, num value) => ScopeLeafRow(
      sessionId: session,
      observedAt: at,
      bmkAge: 30,
      layerSegments: const {},
      cells: {
        'infertilePct': ScopeCellAccumulator.sample(
          value: value,
          count: value,
          denominator: 100,
        ),
      },
    );
    return ScopeDataBundle(
      leavesBySector: {
        'residue_breakout': [
          leaf('previous', DateTime(2026, 6, 1), 9),
          leaf('latest', DateTime(2026, 7, 1), 8),
        ],
      },
    );
  }
}

class _BreakoutPhotoPanelRepo extends PanelDashboardRepository {
  _BreakoutPhotoPanelRepo(this.pathsByField);

  final Map<String, List<String>> pathsByField;
  final List<String> requestedFields = [];

  @override
  Future<List<String>> getPhotoPaths(
    DashboardFilter filter,
    String panelName,
    String fieldKey,
  ) async {
    if (panelName == 'residue_breakout') requestedFields.add(fieldKey);
    return pathsByField[fieldKey] ?? const [];
  }
}

class _RecordedResidueScopeRepo extends ScopeComparisonRepository {
  @override
  Future<List<ScopeLeafRow>> getScopeLeaves(
    ScopeSectorConfig sector,
    DashboardFilter filter,
  ) async {
    if (sector.id != 'residue_breakout') return const [];
    return [
      ScopeLeafRow(
        layerSegments: const {SamplingLayer.house: 'H1'},
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
  Future<int?> dominantBmkAge(DashboardFilter filter) async => null;

  @override
  Future<List<ScopePeriod>> distinctPeriods(
    ScopeSectorConfig sector,
    DashboardFilter base,
  ) async => const [];

  @override
  Future<ScopeDataBundle> loadBundle(sectors, filter) async => ScopeDataBundle(
    leavesBySector: {
      'residue_breakout': await getScopeLeaves(
        ScopeConfigRegistry.byId('residue_breakout'),
        filter,
      ),
    },
  );
}

ScopeLeafRow _ageLeaf({
  required int age,
  required String house,
  required String tray,
  required num value,
  String machine = 'S1H1',
}) {
  return ScopeLeafRow(
    bmkAge: age,
    layerSegments: {
      SamplingLayer.house: house,
      SamplingLayer.setterHatcher: machine,
      SamplingLayer.trolley: 'Tr1',
      SamplingLayer.tray: tray,
    },
    cells: {
      'infertilePct': ScopeCellAccumulator.sample(
        value: value,
        traySize: 100,
        count: value,
      ),
    },
  );
}

void main() {
  late ScopeComparisonProvider provider;

  setUp(() async {
    provider = ScopeComparisonProvider(repository: _EmptyScopeRepo());
    // Demo customer → example fallback when a sector has no live rows.
    await provider.applyFilter(
      customerId: kDashboardDemoCustomerId,
      hatcheryId: 'hatchery-dashboard-demo',
    );
  });

  test('real customer with no rows shows empty state (no dummy)', () async {
    final real = ScopeComparisonProvider(repository: _EmptyScopeRepo());
    await real.applyFilter(customerId: 'cust-real-123', hatcheryId: 'h1');
    expect(real.isDummyFor('residue_breakout'), isFalse);
    expect(real.isEmptyFor('residue_breakout'), isTrue);
    expect(real.groupsFor('residue_breakout'), isEmpty);
  });

  test('falls back to dummy data when no live rows', () {
    expect(provider.isDummyFor('residue_breakout'), isTrue);
    expect(provider.isDummyFor('egg_storage'), isTrue);
  });

  test('residue defaults to one pooled column with no active layers', () {
    expect(provider.groupsFor('residue_breakout'), hasLength(1));
    expect(provider.groupsFor('residue_breakout').single.label, 'Pool');
    expect(provider.selectedLayersFor('residue_breakout'), isEmpty);
    expect(provider.showAvg('residue_breakout'), isFalse);
  });

  test('ineligible demo layers cannot create false comparisons', () {
    provider.toggleLayer('residue_breakout', SamplingLayer.tray);
    expect(provider.groupsFor('residue_breakout').map((g) => g.label), [
      'Pool',
    ]);
    expect(provider.selectedLayersFor('residue_breakout'), isEmpty);
  });

  test('single-scope sector yields one pooled group', () {
    expect(provider.groupsFor('egg_storage'), hasLength(1));
    expect(provider.showAvg('egg_storage'), isFalse);
  });

  test('pick-chip hides a column', () {
    expect(provider.visibleColumnIndexes('chick_quality'), [0]);
    provider.toggleColumn('chick_quality', 0);
    expect(provider.visibleColumnIndexes('chick_quality'), isEmpty);
  });

  test('demo data keeps its BMK reference while starting pooled', () {
    expect(provider.bmkFor('residue_breakout'), isNotNull);
    expect(provider.groupsFor('residue_breakout').single.label, 'Pool');
  });

  test('all 10 sectors load', () {
    for (final s in ScopeConfigRegistry.sectors) {
      expect(provider.groupsFor(s.id), isNotEmpty, reason: s.id);
    }
  });

  test('loads item-scoped breakout photos for the dashboard grid', () async {
    final panelRepo = _BreakoutPhotoPanelRepo(const {
      'breakout_infertile_photo': ['/tmp/infertile.jpg'],
      'breakout_earlyDead_photo': ['/tmp/early.jpg'],
      'breakout_midDead_photo': ['/tmp/mid.jpg'],
      'breakout_photo': ['/tmp/legacy.jpg', '/tmp/mid.jpg'],
    });
    final real = ScopeComparisonProvider(
      repository: _RecordedResidueScopeRepo(),
      panelRepository: panelRepo,
    );

    await real.applyFilter(customerId: 'customer-1', hatcheryId: 'h1');

    expect(
      real.photoPathsFor('residue_breakout'),
      containsAll(<String>[
        '/tmp/infertile.jpg',
        '/tmp/early.jpg',
        '/tmp/mid.jpg',
        '/tmp/legacy.jpg',
      ]),
    );
    expect(
      real
          .photoPathsFor('residue_breakout')
          .where((path) => path == '/tmp/mid.jpg'),
      hasLength(1),
    );
    expect(panelRepo.requestedFields, contains('breakout_midDead_photo'));
  });

  test('scope leaves carry their BMK age for period-local comparisons', () {
    final leaf = ScopeLeafRow(
      bmkAge: 36,
      layerSegments: const {SamplingLayer.house: 'H1'},
      cells: const {},
    );

    expect(leaf.bmkAge, 36);
  });

  test(
    'latest versus previous classifies a persistent breach improving',
    () async {
      final historyProvider = ScopeComparisonProvider(
        repository: _HistoryScopeRepo(),
        panelRepository: _HistoryBmkPanelRepo(),
      );
      await historyProvider.applyFilter(
        customerId: 'customer-1',
        hatcheryId: 'hatchery-1',
      );

      final comparison = historyProvider.historyFor(
        'residue_breakout',
        'infertilePct',
      );
      expect(comparison, isNotNull);
      expect(comparison!.latestValue, 8);
      expect(comparison.previousValue, 9);
      expect(comparison.delta, -1);
      expect(comparison.state, MetricTrendState.improving);
    },
  );

  group('data-aware age and hierarchy state', () {
    test(
      'different houses in different ages do not create a comparison',
      () async {
        final real = ScopeComparisonProvider(
          repository: _AgeScopeRepo({
            34: [_ageLeaf(age: 34, house: 'H1', tray: 'Ty1', value: 80)],
            35: [_ageLeaf(age: 35, house: 'H2', tray: 'Ty1', value: 90)],
          }),
          panelRepository: _NoBmkPanelRepo(),
        );

        await real.applyFilter(customerId: 'cust-real', hatcheryId: 'h1');

        expect(real.selectedLayersFor('residue_breakout'), isEmpty);
        expect(real.eligibleLayersFor('residue_breakout'), isEmpty);
      },
    );

    test(
      'specific age starts pooled and exposes only sibling-valid levels',
      () async {
        final real = ScopeComparisonProvider(
          repository: _AgeScopeRepo({
            36: [
              _ageLeaf(age: 36, house: 'H1', tray: 'Ty1', value: 80),
              _ageLeaf(age: 36, house: 'H1', tray: 'Ty2', value: 90),
            ],
          }),
          panelRepository: _NoBmkPanelRepo(),
        );
        await real.applyFilter(customerId: 'cust-real', hatcheryId: 'h1');

        await real.setPeriod(
          'residue_breakout',
          const ScopePeriod(label: 'W36', age: 36, n: 2),
        );

        expect(real.groupsFor('residue_breakout').single.label, 'Pool');
        expect(real.selectedLayersFor('residue_breakout'), isEmpty);
        expect(real.eligibleLayersFor('residue_breakout'), [
          SamplingLayer.tray,
        ]);
      },
    );

    test('all-age average gives every age equal weight', () async {
      final real = ScopeComparisonProvider(
        repository: _AgeScopeRepo({
          34: [_ageLeaf(age: 34, house: 'H1', tray: 'Ty1', value: 80)],
          35: [
            _ageLeaf(age: 35, house: 'H1', tray: 'Ty1', value: 90),
            _ageLeaf(age: 35, house: 'H1', tray: 'Ty2', value: 90),
            _ageLeaf(age: 35, house: 'H1', tray: 'Ty3', value: 90),
          ],
        }),
        panelRepository: _NoBmkPanelRepo(),
      );
      await real.applyFilter(customerId: 'cust-real', hatcheryId: 'h1');
      await real.loadCumulative('residue_breakout');

      final series = real.cumulativeSeriesFor('residue_breakout')!;
      expect(series.periods.map((period) => period.label), ['W34', 'W35']);
      expect(series.groups.single.label, 'Pool');
      expect(
        series.groups.single.params.first.averageValue,
        closeTo(85, 0.001),
      );
    });

    test(
      'House comparison keeps missing ages null and averages recorded ages',
      () async {
        final real = ScopeComparisonProvider(
          repository: _AgeScopeRepo({
            34: [
              _ageLeaf(age: 34, house: 'H1', tray: 'Ty1', value: 80),
              _ageLeaf(age: 34, house: 'H2', tray: 'Ty1', value: 90),
            ],
            35: [_ageLeaf(age: 35, house: 'H1', tray: 'Ty1', value: 85)],
          }),
          panelRepository: _NoBmkPanelRepo(),
        );
        await real.applyFilter(customerId: 'cust-real', hatcheryId: 'h1');
        expect(real.eligibleLayersFor('residue_breakout'), [
          SamplingLayer.house,
        ]);

        real.toggleLayer('residue_breakout', SamplingLayer.house);
        await real.loadCumulative('residue_breakout');

        final groups = real.cumulativeSeriesFor('residue_breakout')!.groups;
        final h1 = groups.singleWhere((group) => group.label == 'H1');
        final h2 = groups.singleWhere((group) => group.label == 'H2');
        expect(h1.params.first.values, [80, 85]);
        expect(h1.params.first.averageValue, closeTo(82.5, 0.001));
        expect(h2.params.first.values, [90, null]);
        expect(h2.params.first.averageValue, closeTo(90, 0.001));
      },
    );

    test(
      'Machine comparison produces one longitudinal series per machine',
      () async {
        final real = ScopeComparisonProvider(
          repository: _AgeScopeRepo({
            34: [
              _ageLeaf(
                age: 34,
                house: 'H1',
                machine: 'S1H1',
                tray: 'Ty1',
                value: 80,
              ),
              _ageLeaf(
                age: 34,
                house: 'H1',
                machine: 'S2H2',
                tray: 'Ty1',
                value: 90,
              ),
            ],
            35: [
              _ageLeaf(
                age: 35,
                house: 'H1',
                machine: 'S1H1',
                tray: 'Ty1',
                value: 85,
              ),
              _ageLeaf(
                age: 35,
                house: 'H1',
                machine: 'S2H2',
                tray: 'Ty1',
                value: 95,
              ),
            ],
          }),
          panelRepository: _NoBmkPanelRepo(),
        );
        await real.applyFilter(customerId: 'cust-real', hatcheryId: 'h1');

        expect(real.eligibleLayersFor('residue_breakout'), [
          SamplingLayer.setterHatcher,
        ]);
        real.toggleLayer('residue_breakout', SamplingLayer.setterHatcher);
        await real.loadCumulative('residue_breakout');

        final series = real.cumulativeSeriesFor('residue_breakout')!;
        expect(series.groups.map((group) => group.label), ['S1H1', 'S2H2']);
        expect(series.groups.first.params.first.values, [80, 85]);
        expect(series.groups.last.params.first.values, [90, 95]);
        expect(series.params.first.averageValue, closeTo(87.5, 0.001));
      },
    );

    test('layer change rebuilds cumulative from cached leaves', () async {
      final repository = _AgeScopeRepo({
        34: [
          _ageLeaf(age: 34, house: 'H1', tray: 'Ty1', value: 80),
          _ageLeaf(age: 34, house: 'H2', tray: 'Ty1', value: 90),
        ],
      });
      final real = ScopeComparisonProvider(
        repository: repository,
        panelRepository: _NoBmkPanelRepo(),
      );
      await real.applyFilter(customerId: 'cust-real', hatcheryId: 'h1');
      await real.loadCumulative('residue_breakout');
      real.toggleLayer('residue_breakout', SamplingLayer.house);
      await real.loadCumulative('residue_breakout');

      expect(
        real
            .cumulativeSeriesFor('residue_breakout')!
            .groups
            .map((group) => group.label),
        ['H1', 'H2'],
      );
    });
  });
}
