import 'package:flutter/foundation.dart';

import '../../../data/database/seeds/dashboard_demo_seeds.dart';
import '../../../data/models/panel_sample_schema.dart';
import '../../../data/repositories/panel_dashboard_repository.dart';
import '../../../data/repositories/scope_comparison_repository.dart';
import '../models/dashboard_filter.dart';
import '../models/dashboard_intelligence_models.dart';
import '../models/egg_storage_models.dart';
import '../models/hatch_analysis_models.dart';
import '../models/scope_cumulative.dart';
import '../scope/scope_config.dart';
import '../scope/scope_dummy_data.dart';
import '../scope/scope_engine.dart';
import '../scope/scope_models.dart';
import '../scope/scope_severity.dart';

/// Drives the "Scopes & Parameters" comparison sections. Holds per-sector layer
/// selection + column visibility, caches the fetched leaves, and recomputes
/// groups via [ScopeEngine] (layer toggles never re-query the DB).
///
/// Mirrors the prototype interaction model: layers narrow/broaden columns;
/// pick-chips show/hide columns; ⌀ Avg is shown when >1 group.
class ScopeComparisonProvider extends ChangeNotifier {
  ScopeComparisonProvider({
    ScopeComparisonRepository? repository,
    PanelDashboardRepository? panelRepository,
  }) : _repo = repository ?? ScopeComparisonRepository(),
       _panelRepo = panelRepository ?? PanelDashboardRepository();

  final ScopeComparisonRepository _repo;
  final PanelDashboardRepository _panelRepo;

  /// Sentinel used in [_hidden] to mean the ⌀ Avg column.
  static const int avgColumnId = -1;

  bool _isLoading = false;
  String? _filterKey;
  int _filterGeneration = 0;

  final Map<String, List<ScopeLeafRow>> _leaves = {};
  final Map<String, List<ScopeLeafRow>> _allLeaves = {};
  final Map<String, bool> _isDummy = {};
  final Map<String, bool> _isEmpty = {};
  final Map<String, BmkReference?> _sectorBmk = {};
  final Map<String, List<SamplingLayer>> _selectedLayers = {};
  final Map<String, List<SamplingLayer>> _eligibleLayers = {};
  final Map<String, Set<int>> _hidden = {};
  final Map<String, List<ScopeGroup>> _groups = {};
  final Map<String, bool> _chartMode = {};
  final Map<String, int> _chartParam = {};
  final Map<String, int> _chartScope = {};
  final Map<String, List<String>> _photoPaths = {};
  final Map<String, List<MetricObservation>> _observations = {};
  final Map<String, DashboardDataQuality> _quality = {};
  final Map<String, String> _errors = {};
  final Map<String, Map<String, HistoricalMetricComparison>> _history = {};

  /// Per-sector Incremental (false, default) ⇄ Cumulative (true) view mode.
  /// Additive: Incremental keeps the existing tiles/matrix/chart behavior.
  final Map<String, bool> _cumulative = {};

  /// Available axis points (ages/visits) per sector, and the picked period
  /// (null = All). Cumulative series are cached per sector, loaded on demand.
  final Map<String, List<ScopePeriod>> _periods = {};
  final Map<String, ScopePeriod?> _selectedPeriod = {};
  final Map<String, CumulativeSeries> _cumSeries = {};
  final Set<String> _cumLoading = {};
  final Set<String> _cumReloadPending = {};

  /// Per-age Act-vs-BMK series for the Hatch Result charts (X = age). Loaded
  /// lazily when that chart is opened, not on the common applyFilter path.
  List<HatchAgePoint> _hatchByAge = const [];
  DashboardFilter? _lastFilter;

  bool get isLoading => _isLoading;

  List<HatchAgePoint> get hatchAgeSeries => _hatchByAge;

  /// Clears app-scoped comparison caches before a different signed-in user can
  /// build a frame. In-flight queries are invalidated by the generation bump.
  void prepareForAccountChange() {
    _filterGeneration++;
    _filterKey = null;
    _lastFilter = null;
    _clearTenantData();
    _isLoading = true;
  }

  DashboardDataQuality qualityFor(String sectorId) =>
      _quality[sectorId] ?? const DashboardDataQuality();

  Map<String, DashboardDataQuality> get qualityBySector =>
      Map.unmodifiable(_quality);

  String? errorFor(String sectorId) => _errors[sectorId];

  HistoricalMetricComparison? historyFor(String sectorId, String metricKey) =>
      _history[sectorId]?[metricKey];

  List<MetricObservation> observationsFor(String sectorId) =>
      _observations[sectorId] ?? const [];

  /// Load every sector for the given filter (idempotent per filter). Pulls the
  /// BMK reference once and reuses it across live sectors.
  Future<void> applyFilter({
    String? customerId,
    String? hatcheryId,
    String? flockId,
    int? bmkAge,
  }) async {
    final key = '$customerId|$hatcheryId|$flockId|$bmkAge';
    if (key == _filterKey && _groups.isNotEmpty) return;
    final generation = ++_filterGeneration;
    _filterKey = key;
    _clearTenantData();
    // New filter → drop per-sector period/cumulative caches so they re-derive.
    _isLoading = true;
    notifyListeners();
    final filter = DashboardFilter(
      customerId: customerId,
      hatcheryId: hatcheryId,
      flockId: flockId,
      bmkAge: bmkAge,
    );
    _lastFilter = filter;

    if (!filter.isOperational) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    // Example/dummy data is limited to the demo customer; real customers show
    // live data or an empty state.
    final isDemo = customerId == kDashboardDemoCustomerId;
    BmkReference? liveBmk;
    try {
      // Pick a BMK reference: explicit age, else the dominant age in the data.
      final refAge = bmkAge ?? await _repo.dominantBmkAge(filter);
      if (generation != _filterGeneration) return;
      if (refAge != null) {
        liveBmk = await _panelRepo.getBmkReferenceForAge(refAge);
        if (generation != _filterGeneration) return;
      }
      final bundle = await _repo.loadBundle(
        ScopeConfigRegistry.sectors,
        filter,
      );
      if (generation != _filterGeneration) return;
      _observations.addAll(bundle.observationsBySector);
      _quality.addAll(bundle.qualityBySector);
      _errors.addAll(bundle.errorsBySector);
      for (final sector in ScopeConfigRegistry.sectors) {
        final leaves = bundle.leavesBySector[sector.id] ?? const [];
        if (leaves.isNotEmpty) {
          _leaves[sector.id] = leaves;
          _allLeaves[sector.id] = leaves;
          _isDummy[sector.id] = false;
          _isEmpty[sector.id] = false;
          _sectorBmk[sector.id] = liveBmk;
        } else if (isDemo) {
          _leaves[sector.id] = ScopeDummyData.leavesFor(sector.id);
          _allLeaves[sector.id] = _leaves[sector.id]!;
          _isDummy[sector.id] = true;
          _isEmpty[sector.id] = false;
          _sectorBmk[sector.id] = ScopeDummyData.demoBmk;
        } else {
          _leaves[sector.id] = const [];
          _allLeaves[sector.id] = const [];
          _isDummy[sector.id] = false;
          _isEmpty[sector.id] = true;
          _sectorBmk[sector.id] = liveBmk;
        }
        _selectedLayers[sector.id] = const [];
        _updateEligibleLayers(sector.id);
        _recompute(sector.id);
        _periods[sector.id] = bundle.periodsBySector[sector.id] ?? const [];
        if (_isBreakoutSector(sector.id) &&
            !(_isDummy[sector.id] ?? false) &&
            !(_isEmpty[sector.id] ?? true)) {
          final photos = await _loadBreakoutPhotos(filter, sector.id);
          if (generation != _filterGeneration) return;
          _photoPaths[sector.id] = photos;
        }
      }
      _recomputeHistory();
    } catch (e) {
      if (generation == _filterGeneration) {
        debugPrint('Scope applyFilter error: $e');
      }
    } finally {
      if (generation == _filterGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
    if (generation != _filterGeneration) return;
    // Refresh the lazily-loaded Hatch age chart if it's already open so a filter
    // change updates it. Fire-and-forget — never blocks the main load.
    if (isChartMode('hatch_results')) _loadHatchAgeSeries();
  }

  void _clearTenantData() {
    _selectedPeriod.clear();
    _periods.clear();
    _cumSeries.clear();
    _cumLoading.clear();
    _cumReloadPending.clear();
    _photoPaths.clear();
    _selectedLayers.clear();
    _eligibleLayers.clear();
    _hidden.clear();
    _observations.clear();
    _quality.clear();
    _errors.clear();
    _history.clear();
    _hatchByAge = const [];
    _leaves.clear();
    _allLeaves.clear();
    _isDummy.clear();
    _isEmpty.clear();
    _sectorBmk.clear();
    _groups.clear();
  }

  /// Pull-to-refresh: force a re-query for the current filter, bypassing the
  /// idempotency guard in [applyFilter].
  Future<void> refresh() {
    final f = _lastFilter;
    _filterKey = null;
    return applyFilter(
      customerId: f?.customerId,
      hatcheryId: f?.hatcheryId,
      flockId: f?.flockId,
      bmkAge: f?.bmkAge,
    );
  }

  // ── interaction ──────────────────────────────────────────────────────────

  /// Toggle a breakdown layer; recomputes columns and resets pick state to
  /// all-shown (matches the prototype's `applyScopeLayers`).
  void toggleLayer(String sectorId, SamplingLayer layer) {
    if (!eligibleLayersFor(sectorId).contains(layer)) return;
    final sector = ScopeConfigRegistry.byId(sectorId);
    final nonPool = ScopeEngine.nonPoolLayers(sector);
    final current = {...(_selectedLayers[sectorId] ?? const <SamplingLayer>[])};
    current.contains(layer) ? current.remove(layer) : current.add(layer);
    _selectedLayers[sectorId] = nonPool
        .where(current.contains)
        .toList(); // hierarchy order
    _hidden[sectorId] = <int>{};
    _cumSeries.remove(sectorId);
    if (_cumLoading.contains(sectorId)) _cumReloadPending.add(sectorId);
    _recompute(sectorId);
    notifyListeners();
  }

  /// Show/hide one column. `columnId == avgColumnId` toggles the ⌀ Avg column.
  void toggleColumn(String sectorId, int columnId) {
    final hidden = _hidden.putIfAbsent(sectorId, () => <int>{});
    hidden.contains(columnId) ? hidden.remove(columnId) : hidden.add(columnId);
    notifyListeners();
  }

  // ── reads ──────────────────────────────────────────────────────────────

  bool isDummyFor(String sectorId) => _isDummy[sectorId] ?? false;

  /// True when a real customer has no rows for this sector (show empty state).
  bool isEmptyFor(String sectorId) => _isEmpty[sectorId] ?? false;

  List<String> photoPathsFor(String sectorId) =>
      _photoPaths[sectorId] ?? const [];

  // ── Incremental ⇄ Cumulative view mode ─────────────────────────────────────
  bool isCumulative(String sectorId) => _cumulative[sectorId] ?? false;

  void setCumulative(String sectorId, bool on) {
    if (isCumulative(sectorId) == on) return;
    _cumulative[sectorId] = on;
    notifyListeners();
    if (on) loadCumulative(sectorId);
  }

  // ── period picker (Incremental view narrowed to one age/visit) ─────────────
  List<ScopePeriod> periodsFor(String sectorId) =>
      _periods[sectorId] ?? const [];

  ScopePeriod? selectedPeriodFor(String sectorId) => _selectedPeriod[sectorId];

  /// Narrow the sector to one BMK age (null = All). Every change returns the
  /// hierarchy breakdown to Pool before deriving the valid layers for the new
  /// age scope.
  Future<void> setPeriod(String sectorId, ScopePeriod? period) async {
    final generation = _filterGeneration;
    _selectedPeriod[sectorId] = period;
    _selectedLayers[sectorId] = const [];
    _hidden[sectorId] = <int>{};
    _cumSeries.remove(sectorId);
    if (_cumLoading.contains(sectorId)) _cumReloadPending.add(sectorId);
    final base = _lastFilter;
    if (base != null && !isDummyFor(sectorId)) {
      try {
        final leaves = period == null
            ? (_allLeaves[sectorId] ?? const <ScopeLeafRow>[])
            : (_allLeaves[sectorId] ?? const <ScopeLeafRow>[])
                  .where(
                    (leaf) =>
                        (period.age == null || leaf.bmkAge == period.age) &&
                        (period.sessionId == null ||
                            leaf.sessionId == period.sessionId),
                  )
                  .toList();
        BmkReference? bmk = _sectorBmk[sectorId];
        if (period?.age != null) {
          bmk = await _panelRepo.getBmkReferenceForAge(period!.age!);
          if (generation != _filterGeneration) return;
        }
        _leaves[sectorId] = leaves;
        _sectorBmk[sectorId] = bmk;
        _isEmpty[sectorId] = leaves.isEmpty;
        _updateEligibleLayers(sectorId);
        _recompute(sectorId);
      } catch (e) {
        debugPrint('setPeriod $sectorId failed: $e');
      }
    }
    if (generation != _filterGeneration) return;
    notifyListeners();
    if (period == null) await loadCumulative(sectorId);
  }

  // ── Cumulative series (per-axis trend) ─────────────────────────────────────
  CumulativeSeries? cumulativeSeriesFor(String sectorId) =>
      _cumSeries[sectorId];

  bool isCumulativeLoading(String sectorId) => _cumLoading.contains(sectorId);

  /// Build (once, cached) the BMK-age series for a sector. With no selected
  /// layer it is pooled; House/Machine layers create stable longitudinal groups.
  Future<void> loadCumulative(String sectorId) async {
    if (_cumSeries.containsKey(sectorId) || _cumLoading.contains(sectorId)) {
      return;
    }
    final base = _lastFilter;
    final generation = _filterGeneration;
    // Dummy/example sectors and the no-filter state have no DB rows to spread —
    // cache an empty series so the view shows its note instead of spinning.
    if (base == null || isDummyFor(sectorId)) {
      _cumSeries[sectorId] = const CumulativeSeries(periods: [], params: []);
      notifyListeners();
      return;
    }
    _cumLoading.add(sectorId);
    notifyListeners();
    try {
      final sector = ScopeConfigRegistry.byId(sectorId);
      final periods = _periods[sectorId] ?? const <ScopePeriod>[];
      final series = await _buildCumulative(sector, periods, base);
      if (generation != _filterGeneration) return;
      _cumSeries[sectorId] = series;
    } catch (e) {
      if (generation != _filterGeneration) return;
      debugPrint('loadCumulative $sectorId failed: $e');
      _cumSeries[sectorId] = const CumulativeSeries(periods: [], params: []);
    } finally {
      if (generation == _filterGeneration) {
        _cumLoading.remove(sectorId);
        notifyListeners();
      }
    }
    if (generation != _filterGeneration) return;
    if (_cumReloadPending.remove(sectorId)) {
      _cumSeries.remove(sectorId);
      await loadCumulative(sectorId);
    }
  }

  Future<CumulativeSeries> _buildCumulative(
    ScopeSectorConfig sector,
    List<ScopePeriod> periods,
    DashboardFilter base,
  ) async {
    final selected = _selectedLayers[sector.id] ?? const <SamplingLayer>[];
    final periodGroups = <Map<String, ScopeGroup>>[];
    final periodBmk = <BmkReference?>[];
    final labels = <String>[];
    for (final p in periods) {
      final leaves = (_allLeaves[sector.id] ?? const <ScopeLeafRow>[])
          .where(
            (leaf) =>
                (p.age == null || leaf.bmkAge == p.age) &&
                (p.sessionId == null || leaf.sessionId == p.sessionId),
          )
          .toList();
      BmkReference? bmk;
      if (p.age != null) bmk = await _panelRepo.getBmkReferenceForAge(p.age!);
      final groups = ScopeEngine.comboGroups(sector, leaves, selected, bmk);
      final byLabel = <String, ScopeGroup>{};
      for (final group in groups) {
        byLabel[group.label] = group;
        if (!labels.contains(group.label)) labels.add(group.label);
      }
      periodGroups.add(byLabel);
      periodBmk.add(bmk);
    }

    final cumulativeGroups = <CumulativeGroup>[
      for (final label in labels)
        CumulativeGroup(
          label: label,
          params: _cumulativeParamsForGroup(
            sector,
            label,
            periods,
            periodGroups,
            periodBmk,
          ),
        ),
    ];
    final overall = cumulativeGroups.length <= 1
        ? (cumulativeGroups.isEmpty
              ? const <CumulativeParam>[]
              : cumulativeGroups.first.params)
        : _overallCumulativeParams(sector, cumulativeGroups, periodBmk);
    return CumulativeSeries(
      periods: periods,
      groups: cumulativeGroups,
      params: overall,
    );
  }

  List<CumulativeParam> _cumulativeParamsForGroup(
    ScopeSectorConfig sector,
    String label,
    List<ScopePeriod> periods,
    List<Map<String, ScopeGroup>> periodGroups,
    List<BmkReference?> periodBmk,
  ) {
    final params = <CumulativeParam>[];
    for (var j = 0; j < sector.params.length; j++) {
      final param = sector.params[j];
      final values = <num?>[];
      final bmks = <num?>[];
      final texts = <String>[];
      final sevs = <ScopeSeverity>[];
      for (var pi = 0; pi < periods.length; pi++) {
        final group = periodGroups[pi][label];
        final cell = group != null && j < group.cells.length
            ? group.cells[j]
            : null;
        values.add(cell?.value);
        texts.add(cell?.text ?? '—');
        sevs.add(cell?.severity ?? ScopeSeverity.good);
        bmks.add(
          param.bmkField != null
              ? bmkLookup(periodBmk[pi], param.bmkField)
              : null,
        );
      }
      final average = _mean(values);
      params.add(
        CumulativeParam(
          param: param,
          values: values,
          bmks: bmks,
          texts: texts,
          severities: sevs,
          averageValue: average,
          averageText: _formatAverage(param, average),
        ),
      );
    }
    return params;
  }

  List<CumulativeParam> _overallCumulativeParams(
    ScopeSectorConfig sector,
    List<CumulativeGroup> groups,
    List<BmkReference?> periodBmk,
  ) {
    final out = <CumulativeParam>[];
    for (var j = 0; j < sector.params.length; j++) {
      final param = sector.params[j];
      final values = <num?>[];
      final texts = <String>[];
      final severities = <ScopeSeverity>[];
      final bmks = <num?>[];
      for (var pi = 0; pi < periodBmk.length; pi++) {
        final periodValues = <num>[
          for (final group in groups)
            if (group.params[j].values[pi] case final num value) value,
        ];
        final value = _mean(periodValues);
        values.add(value);
        texts.add(_formatAverage(param, value));
        var severity = ScopeSeverity.good;
        for (final group in groups) {
          severity = worstSeverity(severity, group.params[j].severities[pi]);
        }
        severities.add(severity);
        bmks.add(
          param.bmkField == null
              ? null
              : bmkLookup(periodBmk[pi], param.bmkField),
        );
      }
      final groupAverage = _mean([
        for (final group in groups)
          if (group.params[j].averageValue case final num value) value,
      ]);
      out.add(
        CumulativeParam(
          param: param,
          values: values,
          bmks: bmks,
          texts: texts,
          severities: severities,
          averageValue: groupAverage,
          averageText: _formatAverage(param, groupAverage),
        ),
      );
    }
    return out;
  }

  num? _mean(Iterable<num?> values) {
    final present = values.whereType<num>().toList();
    if (present.isEmpty) return null;
    return present.fold<num>(0, (sum, value) => sum + value) / present.length;
  }

  void _recomputeHistory() {
    _history.clear();
    for (final sector in ScopeConfigRegistry.sectors) {
      final leaves = _allLeaves[sector.id] ?? const <ScopeLeafRow>[];
      final bySession = <String, List<ScopeLeafRow>>{};
      for (final leaf in leaves) {
        final sessionId = leaf.sessionId;
        if (sessionId == null || sessionId.isEmpty) continue;
        bySession.putIfAbsent(sessionId, () => []).add(leaf);
      }
      final sessions = bySession.entries.toList()
        ..sort((a, b) {
          DateTime? latest(List<ScopeLeafRow> items) => items
              .map((leaf) => leaf.observedAt)
              .nonNulls
              .fold<DateTime?>(
                null,
                (best, value) =>
                    best == null || value.isAfter(best) ? value : best,
              );
          final aAt = latest(a.value);
          final bAt = latest(b.value);
          if (aAt == null && bAt == null) return 0;
          if (aAt == null) return 1;
          if (bAt == null) return -1;
          return bAt.compareTo(aAt);
        });
      if (sessions.isEmpty) continue;
      final latest = sessions.first;
      final previous = sessions.length > 1 ? sessions[1] : null;
      final bmk = _sectorBmk[sector.id];
      final latestGroup = ScopeEngine.comboGroups(
        sector,
        latest.value,
        const [],
        bmk,
      ).first;
      final previousGroup = previous == null
          ? null
          : ScopeEngine.comboGroups(
              sector,
              previous.value,
              const [],
              bmk,
            ).first;
      final values = <String, HistoricalMetricComparison>{};
      for (var i = 0; i < sector.params.length; i++) {
        final param = sector.params[i];
        final current = latestGroup.cells[i];
        final before = previousGroup?.cells[i];
        values[param.column] = HistoricalMetricComparison(
          sectorId: sector.id,
          metricKey: param.column,
          latestValue: current.value,
          previousValue: before?.value,
          latestAt: _latestAt(latest.value),
          previousAt: previous == null ? null : _latestAt(previous.value),
          state: _trendState(param, current, before),
        );
      }
      _history[sector.id] = values;
    }
  }

  DateTime? _latestAt(List<ScopeLeafRow> leaves) => leaves
      .map((leaf) => leaf.observedAt)
      .nonNulls
      .fold<DateTime?>(
        null,
        (best, value) => best == null || value.isAfter(best) ? value : best,
      );

  MetricTrendState _trendState(
    ScopeParam param,
    ScopeCell current,
    ScopeCell? previous,
  ) {
    if (current.value == null || previous?.value == null) {
      return MetricTrendState.insufficient;
    }
    final currentIssue =
        current.severity == ScopeSeverity.warn ||
        current.severity == ScopeSeverity.err;
    final previousIssue =
        previous!.severity == ScopeSeverity.warn ||
        previous.severity == ScopeSeverity.err;
    if (currentIssue && !previousIssue) return MetricTrendState.newIssue;
    if (!currentIssue && previousIssue) return MetricTrendState.resolved;
    final delta = current.value! - previous.value!;
    if (delta.abs() < 0.01) {
      return currentIssue
          ? MetricTrendState.persistent
          : MetricTrendState.stable;
    }
    final improving = param.higherIsBetter ? delta > 0 : delta < 0;
    if (currentIssue && previousIssue) {
      return improving
          ? MetricTrendState.improving
          : MetricTrendState.worsening;
    }
    return MetricTrendState.stable;
  }

  String _formatAverage(ScopeParam param, num? value) {
    if (value == null ||
        param.format == ScopeValueFormat.text ||
        param.format == ScopeValueFormat.yesNo) {
      return '—';
    }
    return param.formatValue(value);
  }

  // ── table ↔ chart toggle ──────────────────────────────────────────────────
  bool isChartMode(String sectorId) => _chartMode[sectorId] ?? false;

  void toggleChartMode(String sectorId) {
    final on = !isChartMode(sectorId);
    _chartMode[sectorId] = on;
    // Hatch Result's chart is a per-age series fetched on demand — kept off the
    // common applyFilter path so a slow/unavailable DB never stalls the load.
    if (on && sectorId == 'hatch_results') _loadHatchAgeSeries();
    notifyListeners();
  }

  Future<void> _loadHatchAgeSeries() async {
    final filter = _lastFilter;
    if (filter == null) return;
    final generation = _filterGeneration;
    try {
      final series = await _panelRepo.getHatchByAge(filter);
      if (generation != _filterGeneration) return;
      _hatchByAge = series;
      notifyListeners();
    } catch (e) {
      if (generation != _filterGeneration) return;
      debugPrint('Hatch age series load failed: $e');
      _hatchByAge = const [];
    }
  }

  int chartParamIndex(String sectorId) => _chartParam[sectorId] ?? 0;

  void setChartParam(String sectorId, int index) {
    _chartParam[sectorId] = index;
    notifyListeners();
  }

  /// Selected scope (group index) for the chart's Act-vs-STD view.
  int chartScopeIndex(String sectorId) => _chartScope[sectorId] ?? 0;

  void setChartScope(String sectorId, int index) {
    _chartScope[sectorId] = index;
    notifyListeners();
  }

  BmkReference? bmkFor(String sectorId) => _sectorBmk[sectorId];

  List<SamplingLayer> selectedLayersFor(String sectorId) =>
      _selectedLayers[sectorId] ?? const [];

  List<SamplingLayer> eligibleLayersFor(String sectorId) =>
      _eligibleLayers[sectorId] ?? const [];

  bool isLayerOn(String sectorId, SamplingLayer layer) =>
      _selectedLayers[sectorId]?.contains(layer) ?? false;

  List<ScopeGroup> groupsFor(String sectorId) => _groups[sectorId] ?? const [];

  ScopeGroup? poolGroupFor(String sectorId) {
    final sector = ScopeConfigRegistry.byId(sectorId);
    final groups = ScopeEngine.comboGroups(
      sector,
      _leaves[sectorId] ?? const [],
      const [],
      _sectorBmk[sectorId],
    );
    return groups.isEmpty ? null : groups.first;
  }

  bool showAvg(String sectorId) => groupsFor(sectorId).length > 1;

  bool isAvgVisible(String sectorId) =>
      showAvg(sectorId) && !(_hidden[sectorId]?.contains(avgColumnId) ?? false);

  bool isColumnVisible(String sectorId, int index) =>
      !(_hidden[sectorId]?.contains(index) ?? false);

  /// Group indexes currently shown (pick-chips active).
  List<int> visibleColumnIndexes(String sectorId) {
    final groups = groupsFor(sectorId);
    return [
      for (var i = 0; i < groups.length; i++)
        if (isColumnVisible(sectorId, i)) i,
    ];
  }

  /// ⌀ Avg column for the currently-visible groups (count-weighted across them).
  List<ColumnStat> columnStatsFor(String sectorId) {
    if (!isAvgVisible(sectorId)) return const [];
    final sector = ScopeConfigRegistry.byId(sectorId);
    final groups = groupsFor(sectorId);
    final shown = [for (final i in visibleColumnIndexes(sectorId)) groups[i]];
    if (shown.length < 2) return const [];
    return ScopeEngine.columnStats(sector, shown, _sectorBmk[sectorId]);
  }

  void _recompute(String sectorId) {
    final leaves = _leaves[sectorId] ?? const <ScopeLeafRow>[];
    if (leaves.isEmpty) {
      _groups[sectorId] = const [];
      return;
    }
    final sector = ScopeConfigRegistry.byId(sectorId);
    _groups[sectorId] = ScopeEngine.comboGroups(
      sector,
      leaves,
      _selectedLayers[sectorId] ?? const [],
      _sectorBmk[sectorId],
    );
  }

  void _updateEligibleLayers(String sectorId) {
    final sector = ScopeConfigRegistry.byId(sectorId);
    final selectedPeriod = _selectedPeriod[sectorId];
    final leaves = selectedPeriod == null
        ? (_allLeaves[sectorId] ?? const <ScopeLeafRow>[])
        : (_leaves[sectorId] ?? const <ScopeLeafRow>[]);

    if (selectedPeriod != null) {
      _eligibleLayers[sectorId] = ScopeEngine.eligibleLayers(sector, leaves);
      return;
    }

    const longitudinal = <SamplingLayer>{
      SamplingLayer.house,
      SamplingLayer.setter,
      SamplingLayer.hatcher,
      SamplingLayer.setterHatcher,
    };
    final byAge = <int, List<ScopeLeafRow>>{};
    for (final leaf in leaves) {
      final age = leaf.bmkAge;
      if (age != null) byAge.putIfAbsent(age, () => []).add(leaf);
    }
    final eligible = <SamplingLayer>{};
    for (final ageLeaves in byAge.values) {
      eligible.addAll(
        ScopeEngine.eligibleLayers(sector, ageLeaves, limitTo: longitudinal),
      );
    }
    _eligibleLayers[sectorId] = ScopeEngine.nonPoolLayers(
      sector,
    ).where(eligible.contains).toList();
  }

  bool _isBreakoutSector(String sectorId) {
    return sectorId == 'fresh_egg_breakout' ||
        sectorId == 'candled_egg_breakout' ||
        sectorId == 'residue_breakout';
  }

  Future<List<String>> _loadBreakoutPhotos(
    DashboardFilter filter,
    String sectorId,
  ) async {
    final paths = <String>[];
    final seen = <String>{};
    for (final fieldKey in const [
      'breakout_infertile_photo',
      'breakout_early24h_photo',
      'breakout_early48h_photo',
      'breakout_early72hBloodRing_photo',
      'breakout_blackEye_photo',
      'breakout_earlyDead_photo',
      'breakout_midDead_photo',
      'breakout_lateDead_photo',
      'breakout_externalPip_photo',
      'breakout_cracked_photo',
      'breakout_contaminated_photo',
      'breakout_photo',
      'photo',
    ]) {
      try {
        final loaded = await _panelRepo.getPhotoPaths(
          filter,
          sectorId,
          fieldKey,
        );
        for (final path in loaded) {
          if (seen.add(path)) paths.add(path);
        }
      } catch (e) {
        debugPrint('Breakout photo load failed for $sectorId/$fieldKey: $e');
      }
    }
    return paths;
  }
}
