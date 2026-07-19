import '../../../data/models/panel_sample_schema.dart';

/// Severity of a scope cell / column, ordered pool < good < warn < err.
/// Ported from the prototype's `good`/`warn`/`err` (plus `pool` for un-flagged
/// pooled aggregates).
enum ScopeSeverity { pool, good, warn, err }

const Map<ScopeSeverity, int> _severityRank = {
  ScopeSeverity.pool: 0,
  ScopeSeverity.good: 1,
  ScopeSeverity.warn: 2,
  ScopeSeverity.err: 3,
};

/// Worst (highest-rank) of two severities — `err` beats `warn` beats `good`.
ScopeSeverity worstSeverity(ScopeSeverity a, ScopeSeverity b) =>
    _severityRank[a]! >= _severityRank[b]! ? a : b;

/// Accumulator carrying the raw numerator/denominator pieces for one parameter
/// so aggregation across leaves is exact (count-weighted), not lossy.
///
/// A single DB sample row contributes one accumulator via [ScopeCellAccumulator.sample];
/// rolling several leaves up into a coarser scope is just [combine] (a fold).
class ScopeCellAccumulator {
  /// Σ of the raw defect-count column (e.g. Σ lateDeadCount) — count-weighting numerator.
  final num countSum;

  /// Σ traySize (the denominator: total eggs) aligned to [countSum]/[weightedValueSum].
  final num traySum;

  /// Generic metric-specific denominator (sample size, tray size, or count).
  final num denominatorSum;

  /// Σ (value × traySize) — used when only a percentage + sample size is available.
  final num weightedValueSum;

  /// Σ value (raw) — used for unweighted mean / integer sum fallback.
  final num valueSum;

  /// Count of non-null numeric values folded in.
  final int valueN;

  /// Last non-null numeric value folded in. Repository leaves are date-ordered.
  final num? latestValue;

  /// Whether any folded sample had a raw count column (so [countSum] is meaningful).
  final bool hasCountCol;

  /// Whether any folded sample had a positive traySize (so weighting is possible).
  final bool hasTray;
  final bool hasDenominator;

  /// Distinct text values seen (for text params: unique-or-`—`).
  final Set<String> textValues;

  const ScopeCellAccumulator({
    this.countSum = 0,
    this.traySum = 0,
    this.denominatorSum = 0,
    this.weightedValueSum = 0,
    this.valueSum = 0,
    this.valueN = 0,
    this.latestValue,
    this.hasCountCol = false,
    this.hasTray = false,
    this.hasDenominator = false,
    this.textValues = const {},
  });

  /// Build the accumulator for a single sample row's parameter.
  factory ScopeCellAccumulator.sample({
    num? value,
    num? traySize,
    num? denominator,
    num? count,
    String? text,
  }) {
    if (text != null && text.trim().isNotEmpty) {
      return ScopeCellAccumulator(textValues: {text.trim()});
    }
    if (value == null) return const ScopeCellAccumulator();
    final effectiveDenominator = denominator ?? traySize;
    final tray = (traySize != null && traySize > 0) ? traySize : 0;
    final den = (effectiveDenominator != null && effectiveDenominator > 0)
        ? effectiveDenominator
        : 0;
    final hasTray = tray > 0;
    return ScopeCellAccumulator(
      valueSum: value,
      valueN: 1,
      latestValue: value,
      traySum: tray,
      denominatorSum: den,
      weightedValueSum: den > 0 ? value * den : 0,
      hasTray: hasTray,
      hasDenominator: den > 0,
      countSum: count ?? 0,
      hasCountCol: count != null,
    );
  }

  ScopeCellAccumulator combine(ScopeCellAccumulator o) => ScopeCellAccumulator(
    countSum: countSum + o.countSum,
    traySum: traySum + o.traySum,
    denominatorSum: denominatorSum + o.denominatorSum,
    weightedValueSum: weightedValueSum + o.weightedValueSum,
    valueSum: valueSum + o.valueSum,
    valueN: valueN + o.valueN,
    latestValue: o.valueN > 0 ? o.latestValue : latestValue,
    hasCountCol: hasCountCol || o.hasCountCol,
    hasTray: hasTray || o.hasTray,
    hasDenominator: hasDenominator || o.hasDenominator,
    textValues: textValues.isEmpty && o.textValues.isEmpty
        ? const {}
        : {...textValues, ...o.textValues},
  );
}

/// One finest-grain sample (a DB row, or a prototype dummy leaf), carrying its
/// per-layer path segments and per-parameter accumulators.
///
/// `layerSegments` is keyed by [SamplingLayer] (NOT split positionally from a
/// string), so House+Machine nests correctly: `H1·S1H1` stays distinct from
/// `H2·S1H1`. `cells` is keyed by parameter column name.
class ScopeLeafRow {
  final String? rowId;
  final String? sessionId;
  final String? sourceTable;
  final String? customerId;
  final String? hatcheryId;
  final String? flockId;
  final DateTime? observedAt;
  final String? syncStatus;
  final Set<String> qualityFlags;
  final int? bmkAge;
  final Map<SamplingLayer, String> layerSegments;
  final Map<String, ScopeCellAccumulator> cells;

  const ScopeLeafRow({
    this.rowId,
    this.sessionId,
    this.sourceTable,
    this.customerId,
    this.hatcheryId,
    this.flockId,
    this.observedAt,
    this.syncStatus,
    this.qualityFlags = const {},
    this.bmkAge,
    required this.layerSegments,
    required this.cells,
  });
}

/// A rendered cell: formatted text + numeric value (for the ⌀ Avg roll-up) + severity.
class ScopeCell {
  final String text;
  final num? value;
  final bool isPercent;
  final ScopeSeverity severity;

  const ScopeCell({
    required this.text,
    this.value,
    this.isPercent = false,
    this.severity = ScopeSeverity.good,
  });
}

/// A comparison column = one unique combination of the selected layers.
class ScopeGroup {
  final String label; // 'H1·S1H1' or 'Pool'
  final SamplingLayer?
  layer; // finest selected layer (drives the header dot); null = pool
  final List<ScopeCell> cells; // aligned to sector.params
  final List<ScopeCellAccumulator>
  accumulators; // aligned to sector.params (for ⌀ Avg)
  final ScopeSeverity severity; // worst across cells

  const ScopeGroup({
    required this.label,
    required this.layer,
    required this.cells,
    required this.accumulators,
    required this.severity,
  });
}

/// The ⌀ Avg column for one parameter: count-weighted across the shown groups.
class ColumnStat {
  final String avgText;
  final String rangeText; // 'min–max'
  final ScopeSeverity worst;

  const ColumnStat({
    required this.avgText,
    required this.rangeText,
    required this.worst,
  });
}
