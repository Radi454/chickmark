import 'dart:math' as math;

import '../../../data/models/panel_sample_schema.dart';
import '../models/egg_storage_models.dart';
import 'scope_config.dart';
import 'scope_models.dart';
import 'scope_severity.dart';

/// Pure-Dart port of the prototype's scope engine (`_comboGroups` / `_aggGroup` /
/// `_columnStats` / `_scopeSeverity`), with count-weighted aggregation and
/// BMK-diff severity. No Flutter / no DB — fully unit-testable.
class ScopeEngine {
  const ScopeEngine._();

  /// Layers usable for breakdown (allowed minus `pool`). There is no `station`
  /// layer; station-only sectors have `allowedLayers == [pool]`.
  static List<SamplingLayer> nonPoolLayers(ScopeSectorConfig sector) =>
      sector.allowedLayers.where((l) => l != SamplingLayer.pool).toList();

  /// Breakdown layers that represent a real sibling comparison in [leaves].
  /// A deeper layer is eligible only when at least one matching parent path
  /// contains two distinct, nonblank children at that layer.
  static List<SamplingLayer> eligibleLayers(
    ScopeSectorConfig sector,
    List<ScopeLeafRow> leaves, {
    Set<SamplingLayer>? limitTo,
  }) {
    final ordered = nonPoolLayers(sector);
    final eligible = <SamplingLayer>[];
    for (var i = 0; i < ordered.length; i++) {
      final candidate = ordered[i];
      if (limitTo != null && !limitTo.contains(candidate)) continue;

      final childrenByParent = <String, Set<String>>{};
      for (final leaf in leaves) {
        final child = leaf.layerSegments[candidate]?.trim();
        if (child == null || child.isEmpty) continue;
        final parent = ordered
            .take(i)
            .map((layer) => leaf.layerSegments[layer]?.trim() ?? '')
            .where((value) => value.isNotEmpty)
            .join('·');
        childrenByParent.putIfAbsent(parent, () => <String>{}).add(child);
      }
      if (childrenByParent.values.any((children) => children.length >= 2)) {
        eligible.add(candidate);
      }
    }
    return eligible;
  }

  /// Bucket leaves into comparison columns by the join of the SELECTED layers'
  /// segments (hierarchy order preserved → proper nesting). Empty selection →
  /// a single pooled `Pool` column.
  static List<ScopeGroup> comboGroups(
    ScopeSectorConfig sector,
    List<ScopeLeafRow> leaves,
    List<SamplingLayer> selected,
    BmkReference? bmk,
  ) {
    final nonPool = nonPoolLayers(sector);
    final sel = nonPool.where(selected.contains).toList();
    if (sel.isEmpty) {
      return [_aggGroup(sector, 'Pool', leaves, null, bmk)];
    }
    final buckets = <String, List<ScopeLeafRow>>{};
    final order = <String>[];
    for (final leaf in leaves) {
      final label = sel.map((l) => leaf.layerSegments[l] ?? '—').join('·');
      buckets
          .putIfAbsent(label, () {
            order.add(label);
            return <ScopeLeafRow>[];
          })
          .add(leaf);
    }
    return [
      for (final label in order)
        _aggGroup(sector, label, buckets[label]!, sel.last, bmk),
    ];
  }

  /// The ⌀ Avg column: count-weighted across the SHOWN groups (true Σbad/Σtotal,
  /// not a mean-of-means). Only meaningful when `groups.length > 1`.
  static List<ColumnStat> columnStats(
    ScopeSectorConfig sector,
    List<ScopeGroup> shownGroups,
    BmkReference? bmk,
  ) {
    return [
      for (var j = 0; j < sector.params.length; j++)
        _statFor(sector, j, shownGroups, bmk),
    ];
  }

  // ── internals ──────────────────────────────────────────────────────────

  static ScopeGroup _aggGroup(
    ScopeSectorConfig sector,
    String label,
    List<ScopeLeafRow> leaves,
    SamplingLayer? layer,
    BmkReference? bmk,
  ) {
    final accumulators = <ScopeCellAccumulator>[];
    final cells = <ScopeCell>[];
    var groupSeverity = layer == null ? ScopeSeverity.pool : ScopeSeverity.good;
    for (final param in sector.params) {
      var acc = const ScopeCellAccumulator();
      for (final leaf in leaves) {
        final cellAcc = leaf.cells[param.column];
        if (cellAcc != null) acc = acc.combine(cellAcc);
      }
      final cell = _resolveCell(sector, param, acc, bmk);
      accumulators.add(acc);
      cells.add(cell);
      groupSeverity = worstSeverity(groupSeverity, cell.severity);
    }
    return ScopeGroup(
      label: label,
      layer: layer,
      cells: cells,
      accumulators: accumulators,
      severity: groupSeverity,
    );
  }

  static ColumnStat _statFor(
    ScopeSectorConfig sector,
    int j,
    List<ScopeGroup> groups,
    BmkReference? bmk,
  ) {
    final param = sector.params[j];
    var acc = const ScopeCellAccumulator();
    final values = <num>[];
    var worst = ScopeSeverity.good;
    for (final g in groups) {
      acc = acc.combine(g.accumulators[j]);
      final c = g.cells[j];
      if (c.value != null) values.add(c.value!);
      worst = worstSeverity(worst, c.severity);
    }
    final cell = _resolveCell(sector, param, acc, bmk);
    final String range;
    if (values.isEmpty || param.format == ScopeValueFormat.text) {
      range = '—';
    } else {
      final lo = values.reduce(math.min).toStringAsFixed(param.decimals);
      final hi = values.reduce(math.max).toStringAsFixed(param.decimals);
      final suffix = param.format == ScopeValueFormat.percent ? '%' : '';
      range = '$lo–$hi$suffix';
    }
    return ColumnStat(
      avgText: cell.text,
      rangeText: range,
      worst: worstSeverity(worst, cell.severity),
    );
  }

  /// Aggregate one parameter's accumulator into a displayable [ScopeCell].
  static ScopeCell _resolveCell(
    ScopeSectorConfig sector,
    ScopeParam param,
    ScopeCellAccumulator acc,
    BmkReference? bmk,
  ) {
    num? value;
    String text;
    switch (param.format) {
      case ScopeValueFormat.percent:
        if (param.countColumn != null && acc.hasCountCol && acc.traySum > 0) {
          value =
              100 * acc.countSum / acc.traySum; // count-weighted Σbad/Σtotal
        } else if (acc.hasTray && acc.traySum > 0) {
          value = acc.weightedValueSum / acc.traySum; // weighted mean of pct
        } else if (acc.valueN > 0) {
          value = acc.valueSum / acc.valueN; // unweighted mean (no traySize)
        }
        text = value == null
            ? '—'
            : '${value.toStringAsFixed(param.decimals)}%';
        break;
      case ScopeValueFormat.number:
        if (acc.hasTray && acc.traySum > 0) {
          value = acc.weightedValueSum / acc.traySum;
        } else if (acc.valueN > 0) {
          value = acc.valueSum / acc.valueN;
        }
        text = value == null ? '—' : value.toStringAsFixed(param.decimals);
        break;
      case ScopeValueFormat.integer:
        if (acc.valueN > 0) value = acc.valueSum;
        text = value == null ? '—' : value.round().toString();
        break;
      case ScopeValueFormat.yesNo:
        // Backed by a 0/1 column; valueSum = Σ(present) across pooled sessions.
        // "Yes" when any present. value stays null so it's neutral for severity
        // and excluded from the numeric range/charts (like text).
        text = acc.valueN == 0 ? '—' : (acc.valueSum > 0 ? 'Yes' : 'No');
        break;
      case ScopeValueFormat.text:
        value = null;
        text = acc.textValues.length == 1 ? acc.textValues.first : '—';
        break;
    }
    final severity = value == null
        ? ScopeSeverity.good
        : severityFor(
            value: value,
            bmk: bmkLookup(bmk, param.bmkField),
            higherIsBetter: param.higherIsBetter,
            thresholds: param.thresholds ?? sector.defaultThresholds,
            absoluteLimit: param.absoluteLimit,
          );
    return ScopeCell(
      text: text,
      value: value,
      isPercent: param.format == ScopeValueFormat.percent,
      severity: severity,
    );
  }
}
