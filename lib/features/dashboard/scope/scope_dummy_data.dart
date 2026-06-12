import '../../../data/models/panel_sample_schema.dart';
import '../models/egg_storage_models.dart';
import 'scope_config.dart';
import 'scope_models.dart';

/// Example data transcribed from the prototype's SCOPE_DEMO. Used as a fallback
/// when a sector has no live rows (or has no backing table), so the
/// dashboard always renders something. Dummy leaves carry only a `value` (no
/// traySize/count), so the engine's percent path degrades to the simple mean —
/// reproducing the prototype's exact example numbers.
class ScopeDummyData {
  const ScopeDummyData._();

  /// A representative benchmark so the example data shows good/warn/err colors
  /// (live mode uses the real BMK for the selected age instead).
  static final BmkReference demoBmk = BmkReference(
    infertilePct: 7.0,
    early24hPct: 7.5,
    early48hPct: 1.0,
    bloodRingPct: 0.8,
    blackEyePct: 1.4,
    earlyDeadPct: 2.2,
    midDeadPct: 0.9,
    lateDeadPct: 2.0,
    externalPipPct: 0.6,
    crackedPct: 0.4,
    contamPct: 0.5,
    fertilityPct: 92.5,
    hatchabilityPct: 90.0,
    hofPct: 91.0,
    eggWeightG: 63.0,
    chickWeightG: 42.5,
  );

  static List<ScopeLeafRow> leavesFor(String sectorId) =>
      _builders[sectorId]?.call() ?? const [];

  static final Map<String, List<ScopeLeafRow> Function()> _builders = {
    'egg_storage': () => [
          _leaf('egg_storage', const {}, const [
            20.0, 4.2, 4, 2, 'Adequate', 'Far', 0, 0.6,
          ]),
        ],
    'egg_quality': () => [
          _leaf('egg_quality', {SamplingLayer.house: 'House A'}, const [
            92, 62.4, 88.2, 6.1, 63.0, 3.2, 1.1, 0.4, 0.8,
          ]),
          _leaf('egg_quality', {SamplingLayer.house: 'House B'}, const [
            88, 61.2, 83.4, 8.6, 63.0, 4.1, 1.6, 0.6, 1.2,
          ]),
        ],
    'chick_quality': () => [
          _leaf('chick_quality', {SamplingLayer.setterHatcher: 'S1H1'}, const [
            8.7, 2.0, 3.0, 9.0, 5.0, 3.0, 1.0, 104.1, 5.5, 9.1,
          ]),
          _leaf('chick_quality', {SamplingLayer.setterHatcher: 'S2H2'}, const [
            8.4, 2.0, 4.0, 21.0, 6.0, 3.0, 1.0, 104.0, 6.0, 9.4,
          ]),
        ],
    'chick_weights': () => [
          _leaf('chick_weights', {SamplingLayer.house: 'House A'}, const [
            100, 42.3, 87.0, 6.8, 42.5,
          ]),
          _leaf('chick_weights', {SamplingLayer.house: 'House B'}, const [
            100, 41.8, 85.0, 7.2, 42.5,
          ]),
        ],
    'hatch_results': () => [
          _leaf('hatch_results', const {}, const [
            14400, 12125, 84.2, 92.1, 91.4, 1140, 320, 110, 240, 60,
          ]),
        ],
    'fresh_egg_breakout': () => [
          _leaf('fresh_egg_breakout',
              {SamplingLayer.house: 'House A', SamplingLayer.tray: 'Tray 1'},
              const [150, 7.9, 1.2, 0.9, 0.6]),
          _leaf('fresh_egg_breakout',
              {SamplingLayer.house: 'House A', SamplingLayer.tray: 'Tray 2'},
              const [150, 8.4, 1.4, 1.1, 0.7]),
        ],
    'candled_egg_breakout': () => [
          _leaf('candled_egg_breakout', _hier('H1', 'S1H1', 'Tr2', 'Ty5'),
              const [150, 7.7, 2.0, 1.0, 0.8, 1.4]),
          _leaf('candled_egg_breakout', _hier('H1', 'S1H1', 'Tr2', 'Ty6'),
              const [150, 8.1, 2.2, 1.2, 0.9, 1.6]),
        ],
    'residue_breakout': _residueLeaves,
    'setter_optimizing': () => [
          _leaf('setter_optimizing', {SamplingLayer.setter: 'S-01'},
              const [100.0, 100.2, 55, 54, 180, 2700, 100.3, 6.4, 14400, 1]),
          _leaf('setter_optimizing', {SamplingLayer.setter: 'S-03'},
              const [100.0, 100.4, 55, 53, 180, 2900, 100.4, 9.1, 14400, 1]),
        ],
    'hatcher_optimizing': () => [
          _leaf('hatcher_optimizing', {SamplingLayer.hatcher: 'H-01'},
              const [98.5, 60, 2800, 103.6, 6.1, 0, 'None', 18]),
          _leaf('hatcher_optimizing', {SamplingLayer.hatcher: 'H-02'},
              const [98.5, 60, 3100, 103.8, 6.5, 0, 'None', 18]),
        ],
  };

  // Residue: full crossed 16 leaves (matches the prototype exactly).
  static List<ScopeLeafRow> _residueLeaves() {
    const rows = <List<Object?>>[
      ['H1', 'S1H1', 'Tr1', 'Ty1', 7.9, 2.2, 0.8, 3.0, 0.6, 0.3, 0.4, 92.1],
      ['H1', 'S1H1', 'Tr1', 'Ty2', 8.0, 2.1, 0.9, 3.4, 0.5, 0.4, 0.5, 92.0],
      ['H1', 'S1H1', 'Tr2', 'Ty1', 7.7, 2.3, 0.9, 2.9, 0.6, 0.3, 0.5, 92.2],
      ['H1', 'S1H1', 'Tr2', 'Ty2', 8.1, 2.0, 1.0, 3.1, 0.7, 0.4, 0.4, 91.9],
      ['H1', 'S2H2', 'Tr1', 'Ty1', 7.5, 2.4, 1.0, 2.8, 0.6, 0.3, 0.6, 92.4],
      ['H1', 'S2H2', 'Tr1', 'Ty2', 7.8, 2.5, 1.1, 2.7, 0.7, 0.4, 0.5, 92.3],
      ['H1', 'S2H2', 'Tr2', 'Ty1', 7.6, 2.4, 1.0, 2.8, 0.7, 0.3, 0.6, 92.4],
      ['H1', 'S2H2', 'Tr2', 'Ty2', 7.9, 2.6, 1.2, 3.0, 0.6, 0.4, 0.7, 92.0],
      ['H2', 'S1H1', 'Tr1', 'Ty1', 8.2, 2.6, 1.1, 2.9, 0.6, 0.5, 0.4, 91.8],
      ['H2', 'S1H1', 'Tr1', 'Ty2', 8.4, 2.5, 1.0, 3.0, 0.7, 0.5, 0.5, 91.6],
      ['H2', 'S1H1', 'Tr2', 'Ty1', 8.0, 2.3, 0.9, 2.9, 0.6, 0.4, 0.4, 92.0],
      ['H2', 'S1H1', 'Tr2', 'Ty2', 8.3, 2.7, 1.2, 3.5, 0.8, 0.6, 0.6, 91.5],
      ['H2', 'S2H2', 'Tr1', 'Ty1', 7.7, 2.2, 0.9, 2.8, 0.6, 0.3, 0.5, 92.3],
      ['H2', 'S2H2', 'Tr1', 'Ty2', 7.8, 2.3, 1.0, 2.9, 0.5, 0.4, 0.5, 92.2],
      ['H2', 'S2H2', 'Tr2', 'Ty1', 7.9, 2.4, 1.0, 2.7, 0.7, 0.3, 0.6, 92.1],
      ['H2', 'S2H2', 'Tr2', 'Ty2', 8.1, 2.5, 1.1, 3.2, 0.7, 0.5, 0.7, 91.9],
    ];
    return [
      for (final r in rows)
        _leaf(
          'residue_breakout',
          _hier(r[0] as String, r[1] as String, r[2] as String, r[3] as String),
          r.sublist(4),
        ),
    ];
  }

  static Map<SamplingLayer, String> _hier(
          String house, String mac, String trolley, String tray) =>
      {
        SamplingLayer.house: house,
        SamplingLayer.setterHatcher: mac,
        SamplingLayer.trolley: trolley,
        SamplingLayer.tray: tray,
      };

  /// Build a leaf for a sector from values aligned to its config params.
  static ScopeLeafRow _leaf(
    String sectorId,
    Map<SamplingLayer, String> segments,
    List<Object?> values,
  ) {
    final params = ScopeConfigRegistry.byId(sectorId).params;
    final cells = <String, ScopeCellAccumulator>{};
    for (var i = 0; i < params.length && i < values.length; i++) {
      final p = params[i];
      final v = values[i];
      if (p.format == ScopeValueFormat.text) {
        cells[p.column] = ScopeCellAccumulator.sample(text: v as String?);
      } else {
        cells[p.column] = ScopeCellAccumulator.sample(value: v as num?);
      }
    }
    return ScopeLeafRow(layerSegments: segments, cells: cells);
  }
}
