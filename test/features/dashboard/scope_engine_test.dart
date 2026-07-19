import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/features/dashboard/models/egg_storage_models.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_config.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_engine.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_models.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_severity.dart';

ScopeLeafRow _residueLeaf({
  required String house,
  required String mac,
  required String trolley,
  required String tray,
  required num traySize,
  required num infertileCount,
}) {
  return ScopeLeafRow(
    layerSegments: {
      SamplingLayer.house: house,
      SamplingLayer.setterHatcher: mac,
      SamplingLayer.trolley: trolley,
      SamplingLayer.tray: tray,
    },
    cells: {
      'infertilePct': ScopeCellAccumulator.sample(
        value: 100 * infertileCount / traySize,
        traySize: traySize,
        count: infertileCount,
      ),
    },
  );
}

void main() {
  final residue = ScopeConfigRegistry.byId('residue_breakout');
  // Infert % is the first residue param.
  const infertIndex = 0;

  group('ScopeEngine count-weighted aggregation', () {
    test('pool column weights by traySize, not a simple mean', () {
      // Leaf A: 12/150 = 8.0% ; Leaf B: 2/50 = 4.0%.
      // Simple mean = 6.0% ; count-weighted = (12+2)/(150+50) = 7.0%.
      final leaves = [
        _residueLeaf(
          house: 'H1',
          mac: 'S1H1',
          trolley: 'Tr1',
          tray: 'Ty1',
          traySize: 150,
          infertileCount: 12,
        ),
        _residueLeaf(
          house: 'H2',
          mac: 'S1H1',
          trolley: 'Tr1',
          tray: 'Ty1',
          traySize: 50,
          infertileCount: 2,
        ),
      ];
      final groups = ScopeEngine.comboGroups(residue, leaves, const [], null);
      expect(groups, hasLength(1));
      expect(groups.first.label, 'Pool');
      expect(groups.first.cells[infertIndex].value, closeTo(7.0, 1e-9));
      expect(groups.first.cells[infertIndex].text, '7.0%');
    });

    test('⌀ Avg across shown groups is Σbad/Σtotal, not mean-of-means', () {
      final leaves = [
        _residueLeaf(
          house: 'H1',
          mac: 'S1H1',
          trolley: 'Tr1',
          tray: 'Ty1',
          traySize: 150,
          infertileCount: 12,
        ), // 8.0%
        _residueLeaf(
          house: 'H2',
          mac: 'S1H1',
          trolley: 'Tr1',
          tray: 'Ty1',
          traySize: 50,
          infertileCount: 2,
        ), // 4.0%
      ];
      final groups = ScopeEngine.comboGroups(residue, leaves, [
        SamplingLayer.house,
      ], null);
      expect(groups, hasLength(2));
      final stats = ScopeEngine.columnStats(residue, groups, null);
      expect(stats[infertIndex].avgText, '7.0%'); // weighted, not 6.0%
      expect(stats[infertIndex].rangeText, '4.0–8.0%');
    });
  });

  group('explicit aggregation policies', () {
    final sector = ScopeSectorConfig(
      id: 'policy-test',
      title: 'Policy test',
      station: 'Test',
      note: '',
      tableName: null,
      allowedLayers: const [SamplingLayer.pool],
      params: const [
        ScopeParam.percent(
          'Ratio',
          'ratio',
          countColumn: 'count',
          denominatorColumn: 'denominator',
        ),
        ScopeParam.number(
          'Weighted',
          'weighted',
          denominatorColumn: 'sampleSize',
          aggregationPolicy: ScopeAggregationPolicy.sampleWeightedMean,
        ),
        ScopeParam.number('Equal', 'equal'),
        ScopeParam.integer('Sum', 'sum'),
        ScopeParam.number(
          'Latest',
          'latest',
          aggregationPolicy: ScopeAggregationPolicy.latest,
        ),
      ],
    );

    test('each declared policy produces its documented result', () {
      ScopeLeafRow leaf({
        required num ratio,
        required num count,
        required num denominator,
        required num weighted,
        required num equal,
        required num sum,
        required num latest,
      }) => ScopeLeafRow(
        layerSegments: const {},
        cells: {
          'ratio': ScopeCellAccumulator.sample(
            value: ratio,
            count: count,
            denominator: denominator,
          ),
          'weighted': ScopeCellAccumulator.sample(
            value: weighted,
            denominator: denominator,
          ),
          'equal': ScopeCellAccumulator.sample(value: equal),
          'sum': ScopeCellAccumulator.sample(value: sum),
          'latest': ScopeCellAccumulator.sample(value: latest),
        },
      );

      final group = ScopeEngine.comboGroups(
        sector,
        [
          leaf(
            ratio: 10,
            count: 10,
            denominator: 100,
            weighted: 10,
            equal: 10,
            sum: 2,
            latest: 1,
          ),
          leaf(
            ratio: 50,
            count: 5,
            denominator: 10,
            weighted: 30,
            equal: 30,
            sum: 3,
            latest: 9,
          ),
        ],
        const [],
        null,
      ).single;

      expect(group.cells[0].value, closeTo(100 * 15 / 110, 1e-9));
      expect(group.cells[1].value, closeTo(1300 / 110, 1e-9));
      expect(group.cells[2].value, 20);
      expect(group.cells[3].value, 5);
      expect(group.cells[4].value, 9);
    });
  });

  group('ScopeEngine layer composition + nesting', () {
    final leaves = [
      _residueLeaf(
        house: 'H1',
        mac: 'S1H1',
        trolley: 'Tr1',
        tray: 'Ty1',
        traySize: 150,
        infertileCount: 12,
      ),
      _residueLeaf(
        house: 'H2',
        mac: 'S1H1',
        trolley: 'Tr1',
        tray: 'Ty1',
        traySize: 50,
        infertileCount: 2,
      ),
    ];

    test('no layers → single Pool column', () {
      final groups = ScopeEngine.comboGroups(residue, leaves, const [], null);
      expect(groups.map((g) => g.label), ['Pool']);
    });

    test('House+Machine nests (H1·S1H1 distinct from H2·S1H1)', () {
      final groups = ScopeEngine.comboGroups(residue, leaves, [
        SamplingLayer.house,
        SamplingLayer.setterHatcher,
      ], null);
      expect(groups.map((g) => g.label), ['H1·S1H1', 'H2·S1H1']);
    });

    test('Machine only → both leaves merge into one S1H1 column', () {
      final groups = ScopeEngine.comboGroups(residue, leaves, [
        SamplingLayer.setterHatcher,
      ], null);
      expect(groups.map((g) => g.label), ['S1H1']);
      expect(groups.first.cells[infertIndex].value, closeTo(7.0, 1e-9));
    });

    test('nonPoolLayers excludes pool', () {
      expect(ScopeEngine.nonPoolLayers(residue), [
        SamplingLayer.house,
        SamplingLayer.setterHatcher,
        SamplingLayer.trolley,
        SamplingLayer.tray,
      ]);
    });
  });

  group('ScopeEngine data-aware layer eligibility', () {
    ScopeLeafRow leaf({required String house, required String tray}) =>
        _residueLeaf(
          house: house,
          mac: 'S1H1',
          trolley: 'Tr1',
          tray: tray,
          traySize: 100,
          infertileCount: 5,
        );

    test('one sample exposes no comparison layers', () {
      expect(
        ScopeEngine.eligibleLayers(residue, [leaf(house: 'H1', tray: 'Ty1')]),
        isEmpty,
      );
    });

    test('different trays under different houses do not enable Tray', () {
      expect(
        ScopeEngine.eligibleLayers(residue, [
          leaf(house: 'H1', tray: 'Ty1'),
          leaf(house: 'H2', tray: 'Ty2'),
        ]),
        [SamplingLayer.house],
      );
    });

    test('a parent with two trays enables Tray alongside House', () {
      expect(
        ScopeEngine.eligibleLayers(residue, [
          leaf(house: 'H1', tray: 'Ty1'),
          leaf(house: 'H1', tray: 'Ty2'),
          leaf(house: 'H2', tray: 'Ty1'),
        ]),
        [SamplingLayer.house, SamplingLayer.tray],
      );
    });
  });

  group('BMK-diff severity bands', () {
    const t = SeverityThresholds(); // warn>+1pp, err>+3pp

    test('defect: good ≤ +1, warn ≤ +3, err > +3', () {
      num sev(num v) => severityFor(
        value: v,
        bmk: 5.0,
        higherIsBetter: false,
        thresholds: t,
      ).index;
      expect(
        severityFor(value: 5.5, bmk: 5, higherIsBetter: false, thresholds: t),
        ScopeSeverity.good,
      );
      expect(
        severityFor(value: 7.0, bmk: 5, higherIsBetter: false, thresholds: t),
        ScopeSeverity.warn,
      );
      expect(
        severityFor(value: 8.5, bmk: 5, higherIsBetter: false, thresholds: t),
        ScopeSeverity.err,
      );
      sev(5); // smoke
    });

    test('higher-is-better (fertility) flips the diff direction', () {
      expect(
        severityFor(value: 93.5, bmk: 94, higherIsBetter: true, thresholds: t),
        ScopeSeverity.good,
      );
      expect(
        severityFor(value: 92.0, bmk: 94, higherIsBetter: true, thresholds: t),
        ScopeSeverity.warn,
      );
      expect(
        severityFor(value: 90.0, bmk: 94, higherIsBetter: true, thresholds: t),
        ScopeSeverity.err,
      );
    });

    test('no benchmark → good (no false alarms)', () {
      expect(
        severityFor(value: 99, bmk: null, higherIsBetter: false, thresholds: t),
        ScopeSeverity.good,
      );
      expect(
        severityFor(value: 99, bmk: 0, higherIsBetter: false, thresholds: t),
        ScopeSeverity.good,
      );
    });

    test('engine applies severity to cells via BMK', () {
      final leaves = [
        _residueLeaf(
          house: 'H1',
          mac: 'S1H1',
          trolley: 'Tr1',
          tray: 'Ty1',
          traySize: 100,
          infertileCount: 8,
        ), // 8.0%
      ];
      final bmk = BmkReference(infertilePct: 5.0); // diff 3.0 → warn
      final groups = ScopeEngine.comboGroups(residue, leaves, const [], bmk);
      expect(groups.first.cells[infertIndex].severity, ScopeSeverity.warn);
    });
  });

  group('config integrity', () {
    test('all sectors present and grouped by station', () {
      expect(ScopeConfigRegistry.sectors.length, 10);
      expect(ScopeConfigRegistry.stations, [
        ScopeConfigRegistry.stationStorage,
        ScopeConfigRegistry.stationChicks,
        ScopeConfigRegistry.stationHatch,
        ScopeConfigRegistry.stationSetters,
        ScopeConfigRegistry.stationHatchers,
      ]);
    });

    test('single-scope sectors detected', () {
      expect(ScopeConfigRegistry.byId('egg_storage').isSingleScope, isTrue);
      expect(ScopeConfigRegistry.byId('hatch_results').isSingleScope, isTrue);
      expect(
        ScopeConfigRegistry.byId('residue_breakout').isSingleScope,
        isFalse,
      );
    });
  });
}
