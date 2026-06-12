import '../../../core/constants/app_thresholds.dart';
import '../../../data/models/panel_sample_schema.dart';
import 'scope_severity.dart';

/// How a parameter's value is computed/displayed.
enum ScopeValueFormat { percent, number, integer, text, yesNo }

/// X-axis for a sector's Cumulative view: flock age (egg/chick/hatch biology
/// tracks hen age) or audit visit (hatchery-ops settings track over time).
enum CumulativeAxis { age, visit }

/// One column (row in the matrix) of a sector: a display label bound to a real
/// DB column, with formatting + optional count-weighting + BMK-diff severity.
class ScopeParam {
  final String label;
  final String column;
  final ScopeValueFormat format;
  final int decimals;

  /// Raw count column enabling true count-weighted percent (Σcount/ΣtraySize).
  final String? countColumn;

  /// Key into [bmkLookup] for benchmark-diff severity (null → no flag).
  final String? bmkField;

  /// For higher-is-better metrics (fertility, hatchability, uniformity).
  final bool higherIsBetter;

  /// Per-param threshold override (else sector default).
  final SeverityThresholds? thresholds;

  /// Hard cap used when there's no BMK counterpart (prototype-style flag).
  final num? absoluteLimit;

  const ScopeParam({
    required this.label,
    required this.column,
    required this.format,
    this.decimals = 1,
    this.countColumn,
    this.bmkField,
    this.higherIsBetter = false,
    this.thresholds,
    this.absoluteLimit,
  });

  const ScopeParam.percent(
    this.label,
    this.column, {
    this.countColumn,
    this.bmkField,
    this.higherIsBetter = false,
    this.decimals = 1,
    this.thresholds,
    this.absoluteLimit,
  }) : format = ScopeValueFormat.percent;

  const ScopeParam.number(
    this.label,
    this.column, {
    this.decimals = 1,
    this.bmkField,
    this.higherIsBetter = false,
    this.thresholds,
    this.absoluteLimit,
  }) : format = ScopeValueFormat.number,
       countColumn = null;

  const ScopeParam.integer(this.label, this.column)
    : format = ScopeValueFormat.integer,
      decimals = 0,
      countColumn = null,
      bmkField = null,
      higherIsBetter = false,
      thresholds = null,
      absoluteLimit = null;

  const ScopeParam.text(this.label, this.column)
    : format = ScopeValueFormat.text,
      decimals = 0,
      countColumn = null,
      bmkField = null,
      higherIsBetter = false,
      thresholds = null,
      absoluteLimit = null;

  /// Boolean flag rendered as Yes/No. Backed by a 0/1 column; "Yes" when any
  /// pooled session has it present (see [ScopeEngine] yesNo aggregation).
  const ScopeParam.yesNo(this.label, this.column)
    : format = ScopeValueFormat.yesNo,
      decimals = 0,
      countColumn = null,
      bmkField = null,
      higherIsBetter = false,
      thresholds = null,
      absoluteLimit = null;

  /// Format a raw scalar (e.g. a BMK benchmark) for display, honoring this
  /// param's [format]/[decimals]. (Distinct from [ScopeEngine] cell formatting,
  /// which aggregates accumulators; this is for plain benchmark/gap numbers.)
  String formatValue(num? v) {
    if (v == null) return '—';
    switch (format) {
      case ScopeValueFormat.percent:
        return '${v.toStringAsFixed(decimals)}%';
      case ScopeValueFormat.integer:
        return v.round().toString();
      case ScopeValueFormat.number:
      case ScopeValueFormat.text:
        return v.toStringAsFixed(decimals);
      case ScopeValueFormat.yesNo:
        return v > 0 ? 'Yes' : 'No';
    }
  }

  /// Signed difference (Act − BMK) for display, e.g. `+0.5%` / `−5.8%`.
  String formatGap(num gap) {
    final sign = gap > 0 ? '+' : (gap < 0 ? '−' : '±');
    return '$sign${formatValue(gap.abs())}';
  }
}

/// Declarative equivalent of the prototype's SCOPE_DEMO sector, pointing at real
/// tables/columns. `allowedLayers` is pulled from [PanelSampleSchema] so it never
/// drifts from the audit-entry schema; `params` are a curated, ordered subset.
class ScopeSectorConfig {
  final String id;
  final String title;
  final String station;
  final String note;

  /// Source table; null = dummy-only sector (no backing table → example data).
  final String? tableName;

  final List<SamplingLayer> allowedLayers;
  final List<ScopeParam> params;
  final SeverityThresholds defaultThresholds;

  /// Axis the Cumulative view spreads this sector across (age vs visit).
  final CumulativeAxis cumulativeAxis;

  const ScopeSectorConfig({
    required this.id,
    required this.title,
    required this.station,
    required this.note,
    required this.tableName,
    required this.allowedLayers,
    required this.params,
    this.defaultThresholds = const SeverityThresholds(),
    this.cumulativeAxis = CumulativeAxis.age,
  });

  /// True when there is no breakdown layer (pool/station only) → render tiles.
  bool get isSingleScope =>
      allowedLayers.where((l) => l != SamplingLayer.pool).isEmpty;
}

/// Allowed layers for a real table, straight from the audit schema.
List<SamplingLayer> _layersOf(String table) =>
    PanelSampleSchema.byTable(table).allowedLayers;

/// Display label for a layer in the "Break down by" filter (prototype _LAYER_LABEL).
String scopeLayerLabel(SamplingLayer layer) {
  switch (layer) {
    case SamplingLayer.house:
      return 'House';
    case SamplingLayer.setter:
    case SamplingLayer.hatcher:
    case SamplingLayer.setterHatcher:
      return 'Machine';
    case SamplingLayer.trolley:
      return 'Trolley';
    case SamplingLayer.tray:
      return 'Tray';
    case SamplingLayer.pool:
      return 'All';
  }
}

/// All sectors, grouped by station for display. Mirrors the prototype's
/// SCOPE_DEMO. Stations are rendered in this order.
class ScopeConfigRegistry {
  const ScopeConfigRegistry._();

  static const String stationStorage = 'Egg Storage & Handling';
  static const String stationChicks = 'Chicks';
  static const String stationHatch = 'Hatch Analysis & Egg Breakouts';
  static const String stationSetters = 'Setters';
  static const String stationHatchers = 'Hatchers';

  static final List<ScopeSectorConfig> sectors = [
    // ── Egg Storage & Handling ──────────────────────────────────────────
    ScopeSectorConfig(
      id: 'egg_storage',
      title: 'Egg Storage',
      station: stationStorage,
      note: 'Pool only · customer · hatchery · flock · breed (no added layer).',
      tableName: 'egg_storage',
      allowedLayers: _layersOf('egg_storage'),
      cumulativeAxis: CumulativeAxis.visit,
      // NOTE: prototype's "CO₂" param dropped — no column on egg_storage.
      params: const [
        ScopeParam.number('EST °C', 'estAvg'),
        ScopeParam.percent('EST CV%', 'estCvPct'),
        ScopeParam.integer('Storage d', 'storagePeriodDays'),
        ScopeParam.integer('Turn/day', 'turningTimes'),
        ScopeParam.text('Tray sp.', 'traySpacing'),
        ScopeParam.text('Cooler', 'coolerProximity'),
        ScopeParam.yesNo('Condens.', 'condensationPresent'),
        ScopeParam.percent('UpsideDn %', 'upsideDownPct'),
      ],
    ),
    ScopeSectorConfig(
      id: 'egg_quality',
      title: 'Egg Quality',
      station: stationStorage,
      note: 'Scoped by house → one row per house, no pool row.',
      tableName: 'egg_quality',
      allowedLayers: _layersOf('egg_quality'),
      params: const [
        ScopeParam.integer('Sample', 'eggSampleSize'),
        ScopeParam.number('Avg wt g', 'eggAvgWeight'),
        ScopeParam.percent('Unif %', 'eggUniformityPct', higherIsBetter: true,
            absoluteLimit: AppThresholds.uniformityGood,
            thresholds: SeverityThresholds(nearMargin: 2)),
        ScopeParam.percent('CV%', 'eggCvPct',
            absoluteLimit: AppThresholds.cvAlertPct),
        ScopeParam.number('BMK wt', 'eggBmkWeight'),
        ScopeParam.percent('UV aff %', 'uvAffectedPct',
            absoluteLimit: 5, thresholds: SeverityThresholds(nearMargin: 2)),
        ScopeParam.percent('Cuticle %', 'uvCuticleDamagePct'),
        ScopeParam.percent('Washed %', 'uvWashedPct'),
        ScopeParam.percent('Dirty %', 'uvDirtyPct'),
      ],
    ),

    // ── Chicks ──────────────────────────────────────────────────────────
    ScopeSectorConfig(
      id: 'chick_quality',
      title: 'Chick Quality',
      station: stationChicks,
      note: 'Scoped by machine pair → one row per S#H#.',
      tableName: 'chick_quality',
      // No traySize on this table → percent params degrade to unweighted mean.
      allowedLayers: _layersOf('chick_quality'),
      params: const [
        ScopeParam.number('Pasgar', 'pasgarFinalScore', higherIsBetter: true),
        ScopeParam.percent('Reflex %', 'pasgarReflexesPct', higherIsBetter: true),
        ScopeParam.percent('Beak %', 'pasgarBeakPct',
            absoluteLimit: AppThresholds.pasgarAlertPct,
            thresholds: SeverityThresholds(nearMargin: 3)),
        ScopeParam.percent('Navel %', 'pasgarNavelPct',
            absoluteLimit: AppThresholds.pasgarAlertPct,
            thresholds: SeverityThresholds(nearMargin: 3)),
        ScopeParam.percent('Belly %', 'pasgarBellyPct',
            absoluteLimit: AppThresholds.pasgarAlertPct,
            thresholds: SeverityThresholds(nearMargin: 3)),
        ScopeParam.percent('Leg %', 'pasgarLegPct',
            absoluteLimit: AppThresholds.pasgarAlertPct,
            thresholds: SeverityThresholds(nearMargin: 3)),
        ScopeParam.percent('Feather %', 'pasgarFeatherDevPct', higherIsBetter: true),
        ScopeParam.number('CVT °F', 'cvtAvgTemp'),
        ScopeParam.percent('CVT CV%', 'cvtCvPct',
            absoluteLimit: AppThresholds.cvAlertPct),
        ScopeParam.percent('YFBM %', 'yfbmAvgPct'),
      ],
    ),
    ScopeSectorConfig(
      id: 'chick_weights',
      title: 'Chick Weights',
      station: stationChicks,
      note: 'Scoped by house.',
      tableName: 'chick_weights',
      allowedLayers: _layersOf('chick_weights'),
      params: const [
        ScopeParam.integer('Sample', 'sampleSize'),
        ScopeParam.number('Avg wt g', 'avgWeight'),
        ScopeParam.percent('Unif %', 'uniformityPct', higherIsBetter: true,
            absoluteLimit: AppThresholds.uniformityGood,
            thresholds: SeverityThresholds(nearMargin: 2)),
        ScopeParam.percent('CV%', 'cvPct',
            absoluteLimit: AppThresholds.cvAlertPct),
        ScopeParam.number('BMK wt', 'bmkWeight'),
      ],
    ),
    // ── Hatch Analysis & Egg Breakouts ──────────────────────────────────
    ScopeSectorConfig(
      id: 'hatch_results',
      title: 'Hatch Result',
      station: stationHatch,
      note: 'Pooled tally → hatchability / fertility / HOF.',
      tableName: 'residue_breakout',
      allowedLayers: const [SamplingLayer.pool], // pooled readout (tiles)
      // Headline rates only; the per-age Act-vs-BMK charts live in chart mode
      // (see HatchAgeChart). Counts (Set/Hatched/Infert/…) intentionally dropped.
      params: const [
        ScopeParam.percent('Hatch %', 'hatchabilityPct',
            bmkField: 'hatchabilityPct', higherIsBetter: true),
        ScopeParam.percent('Fert %', 'fertilityPct',
            bmkField: 'fertilityPct', higherIsBetter: true),
        ScopeParam.percent('HOF %', 'hofPct',
            bmkField: 'hofPct', higherIsBetter: true),
      ],
    ),
    ScopeSectorConfig(
      id: 'fresh_egg_breakout',
      title: 'Fresh Breakout',
      station: stationHatch,
      note: '0-day · house + tray leaves.',
      tableName: 'fresh_egg_breakout',
      allowedLayers: _layersOf('fresh_egg_breakout'),
      params: const [
        ScopeParam.percent('Infert %', 'infertilePct',
            countColumn: 'infertileCount', bmkField: 'infertilePct'),
        ScopeParam.percent('24h %', 'early24hPct',
            countColumn: 'early24hCount', bmkField: 'early24hPct'),
        ScopeParam.percent('48h %', 'early48hPct',
            countColumn: 'early48hCount', bmkField: 'early48hPct'),
        ScopeParam.percent('Blood ring %', 'bloodRingPct',
            countColumn: 'bloodRingCount', bmkField: 'bloodRingPct'),
      ],
    ),
    ScopeSectorConfig(
      id: 'candled_egg_breakout',
      title: 'Candled Breakout',
      station: stationHatch,
      note: '10-day · full hierarchy leaves.',
      tableName: 'candled_egg_breakout',
      allowedLayers: _layersOf('candled_egg_breakout'),
      params: const [
        ScopeParam.percent('Infert %', 'infertilePct',
            countColumn: 'infertileCount', bmkField: 'infertilePct'),
        ScopeParam.percent('24h %', 'early24hPct',
            countColumn: 'early24hCount', bmkField: 'early24hPct'),
        ScopeParam.percent('48h %', 'early48hPct',
            countColumn: 'early48hCount', bmkField: 'early48hPct'),
        ScopeParam.percent('Blood ring %', 'bloodRingPct',
            countColumn: 'bloodRingCount', bmkField: 'bloodRingPct'),
        ScopeParam.percent('Black eye %', 'blackEyePct',
            countColumn: 'blackEyeCount', bmkField: 'blackEyePct'),
      ],
    ),
    ScopeSectorConfig(
      id: 'residue_breakout',
      title: 'Residue Breakout',
      station: stationHatch,
      note:
          '21-day · 2 house × 2 machine × 2 trolley × 2 tray = 16 leaves.',
      tableName: 'residue_breakout',
      allowedLayers: _layersOf('residue_breakout'),
      params: const [
        ScopeParam.percent('Infert %', 'infertilePct',
            countColumn: 'infertileCount', bmkField: 'infertilePct'),
        ScopeParam.percent('Early %', 'earlyDeadPct',
            countColumn: 'earlyDeadCount', bmkField: 'earlyDeadPct'),
        ScopeParam.percent('Mid %', 'midDeadPct',
            countColumn: 'midDeadCount', bmkField: 'midDeadPct'),
        ScopeParam.percent('Late %', 'lateDeadPct',
            countColumn: 'lateDeadCount', bmkField: 'lateDeadPct'),
        ScopeParam.percent('Ext pip %', 'externalPipPct',
            countColumn: 'externalPipCount', bmkField: 'externalPipPct'),
        ScopeParam.percent('Crack %', 'crackedPct',
            countColumn: 'crackedCount', bmkField: 'crackedPct'),
        ScopeParam.percent('Contam %', 'contaminatedPct',
            countColumn: 'contaminatedCount', bmkField: 'contamPct'),
      ],
    ),

    // ── Setters ─────────────────────────────────────────────────────────
    ScopeSectorConfig(
      id: 'setter_optimizing',
      title: 'Setter Optimizing',
      station: stationSetters,
      note:
          'Per setter machine. Trolley/tray live in the EST grid, not as scope chips.',
      tableName: 'setter_optimizing',
      allowedLayers: _layersOf('setter_optimizing'),
      cumulativeAxis: CumulativeAxis.visit,
      params: const [
        ScopeParam.number('Setpt °F', 'setpointF'),
        ScopeParam.number('Act °F', 'actualF'),
        ScopeParam.number('Setpt RH', 'setpointRh', decimals: 0),
        ScopeParam.number('Act RH', 'actualRh', decimals: 0),
        ScopeParam.number('Turn°', 'turningAngle', decimals: 0),
        ScopeParam.number('CO₂', 'co2Ppm', decimals: 0,
            absoluteLimit: AppThresholds.co2Max,
            thresholds: SeverityThresholds(nearMargin: 300)),
        ScopeParam.number('EST °F', 'estAvg'),
        ScopeParam.percent('EST CV%', 'estCvPct',
            absoluteLimit: AppThresholds.cvAlertPct),
        ScopeParam.integer('Batch sz', 'batchSize'),
        ScopeParam.integer('Batches', 'batchCount'),
      ],
    ),

    // ── Hatchers ────────────────────────────────────────────────────────
    ScopeSectorConfig(
      id: 'hatcher_optimizing',
      title: 'Hatcher Optimizing',
      station: stationHatchers,
      note:
          'Per hatcher machine. Trolley/tray live in the CVT grid, not as scope chips.',
      tableName: 'hatcher_optimizing',
      allowedLayers: _layersOf('hatcher_optimizing'),
      cumulativeAxis: CumulativeAxis.visit,
      // NOTE: prototype's "Act °F"/"Act RH" dropped — no actualF/actualRh on hatcher_optimizing.
      params: const [
        ScopeParam.number('Setpt °F', 'setpointF'),
        ScopeParam.number('Setpt RH', 'setpointRh', decimals: 0),
        ScopeParam.number('CO₂', 'co2Ppm', decimals: 0,
            absoluteLimit: AppThresholds.co2Max,
            thresholds: SeverityThresholds(nearMargin: 300)),
        ScopeParam.number('CVT °F', 'cvtAvg'),
        ScopeParam.percent('CVT CV%', 'cvtCvPct',
            absoluteLimit: AppThresholds.cvAlertPct),
        ScopeParam.integer('Panting', 'chickPanting'),
        ScopeParam.text('Meconium', 'meconium'),
        ScopeParam.integer('Transfer d', 'transferDay'),
      ],
    ),
  ];

  static ScopeSectorConfig byId(String id) =>
      sectors.firstWhere((s) => s.id == id);

  /// Stations in display order with their sectors.
  static List<String> get stations {
    final seen = <String>[];
    for (final s in sectors) {
      if (!seen.contains(s.station)) seen.add(s.station);
    }
    return seen;
  }

  static List<ScopeSectorConfig> forStation(String station) =>
      sectors.where((s) => s.station == station).toList();
}
