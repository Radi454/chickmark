import '../../providers/scope_comparison_provider.dart';
import '../../scope/scope_config.dart';
import '../../scope/scope_models.dart';
import '../../scope/scope_severity.dart';
import 'alarm_triage_feed.dart';

/// Roll a station's sectors up into [TriageItem]s for an [AlarmTriageFeed].
///
/// Only *monitored* params take part — those with a benchmark ([ScopeParam.bmkField])
/// or a hard cap ([ScopeParam.absoluteLimit]). For each, the worst-graded scope
/// (house / machine / leaf) becomes one item; good ones populate the collapsible
/// "In Target" list, warn → Watch, err → Critical.
List<TriageItem> stationTriageItems(
  ScopeComparisonProvider provider,
  String station,
) {
  final out = <TriageItem>[];

  for (final sector in ScopeConfigRegistry.forStation(station)) {
    if (provider.isEmptyFor(sector.id)) continue;
    final groups = provider.groupsFor(sector.id);
    if (groups.isEmpty) continue;
    final bmk = provider.bmkFor(sector.id);

    for (var j = 0; j < sector.params.length; j++) {
      final param = sector.params[j];
      final bmkVal = param.bmkField != null
          ? bmkLookup(bmk, param.bmkField)
          : null;
      final hasBmk = bmkVal != null && bmkVal > 0;
      final hasLimit = param.absoluteLimit != null;
      if (!hasBmk && !hasLimit) continue; // not a monitored metric

      final pick = _worstGroupFor(groups, j, param);
      if (pick == null) continue;
      final observations =
          provider
              .observationsFor(sector.id)
              .where((item) => item.metricKey == param.column)
              .toList()
            ..sort((a, b) => b.observedAt.compareTo(a.observedAt));
      final source = observations.isEmpty ? null : observations.first;

      out.add(
        TriageItem(
          severity: pick.cell.severity,
          primaryTag: sector.title,
          secondaryTag: _scopeTag(pick.group),
          metric: param.label,
          value: pick.cell.text,
          context: _context(param, pick.cell, hasBmk ? bmkVal : null),
          advice: _advice(param, pick.cell.severity),
          station: station,
          sectorId: sector.id,
          metricKey: param.column,
          observedAt: source?.observedAt,
          sessionId: source?.sessionId,
          panelName: source?.tableName,
          panelRowId: source?.rowId,
          history: provider.historyFor(sector.id, param.column),
        ),
      );
    }
  }

  out.sort((a, b) => _rank(b.severity).compareTo(_rank(a.severity)));
  return out;
}

class _Pick {
  final ScopeGroup group;
  final ScopeCell cell;
  const _Pick(this.group, this.cell);
}

/// Worst scope for param [j]: highest severity, tie-broken by the most extreme
/// value (largest for defects, smallest for higher-is-better).
_Pick? _worstGroupFor(List<ScopeGroup> groups, int j, ScopeParam param) {
  _Pick? best;
  for (final g in groups) {
    if (j >= g.cells.length) continue;
    final c = g.cells[j];
    if (c.value == null) continue;
    if (best == null) {
      best = _Pick(g, c);
      continue;
    }
    final byRank = _rank(c.severity).compareTo(_rank(best.cell.severity));
    if (byRank > 0) {
      best = _Pick(g, c);
    } else if (byRank == 0) {
      final more = param.higherIsBetter
          ? c.value! < best.cell.value!
          : c.value! > best.cell.value!;
      if (more) best = _Pick(g, c);
    }
  }
  return best;
}

String _scopeTag(ScopeGroup group) =>
    (group.layer == null || group.label == 'Pool') ? 'Pooled' : group.label;

String _context(ScopeParam param, ScopeCell cell, num? bmk) {
  if (bmk != null && cell.value != null) {
    // gap is signed Act − BMK; formatGap prints +/− with the param's unit.
    return 'BMK ${param.formatValue(bmk)} · ${param.formatGap(cell.value! - bmk)} vs benchmark';
  }
  final limit = param.absoluteLimit;
  if (limit != null) {
    return param.higherIsBetter
        ? 'Target ≥ ${param.formatValue(limit)}'
        : 'Limit ≤ ${param.formatValue(limit)}';
  }
  return '';
}

String? _advice(ScopeParam param, ScopeSeverity severity) {
  switch (severity) {
    case ScopeSeverity.err:
      return param.higherIsBetter
          ? 'Below target — corrective action required.'
          : 'Past limit — corrective action required.';
    case ScopeSeverity.warn:
      return param.higherIsBetter
          ? 'Near the target floor — monitor next visit.'
          : 'Slightly over limit — monitor next visit.';
    case ScopeSeverity.good:
    case ScopeSeverity.pool:
      return null;
  }
}

int _rank(ScopeSeverity s) {
  switch (s) {
    case ScopeSeverity.err:
      return 3;
    case ScopeSeverity.warn:
      return 2;
    case ScopeSeverity.good:
      return 1;
    case ScopeSeverity.pool:
      return 0;
  }
}
