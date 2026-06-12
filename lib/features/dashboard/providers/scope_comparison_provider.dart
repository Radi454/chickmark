import 'package:flutter/foundation.dart';

import '../../../data/database/seeds/dashboard_demo_seeds.dart';
import '../../../data/models/panel_sample_schema.dart';
import '../../../data/repositories/panel_dashboard_repository.dart';
import '../../../data/repositories/scope_comparison_repository.dart';
import '../models/dashboard_filter.dart';
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

  final Map<String, List<ScopeLeafRow>> _leaves = {};
  final Map<String, bool> _isDummy = {};
  final Map<String, bool> _isEmpty = {};
  final Map<String, BmkReference?> _sectorBmk = {};
  final Map<String, List<SamplingLayer>> _selectedLayers = {};
  final Map<String, Set<int>> _hidden = {};
  final Map<String, List<ScopeGroup>> _groups = {};
  final Map<String, bool> _chartMode = {};
  final Map<String, int> _chartParam = {};
  final Map<String, int> _chartScope = {};

  /// Per-sector Incremental (false, default) ⇄ Cumulative (true) view mode.
  /// Additive: Incremental keeps the existing tiles/matrix/chart behavior.
  final Map<String, bool> _cumulative = {};

  /// Available axis points (ages/visits) per sector, and the picked period
  /// (null = All). Cumulative series are cached per sector, loaded on demand.
  final Map<String, List<ScopePeriod>> _periods = {};
  final Map<String, ScopePeriod?> _selectedPeriod = {};
  final Map<String, CumulativeSeries> _cumSeries = {};
  final Set<String> _cumLoading = {};

  /// Per-age Act-vs-BMK series for the Hatch Result charts (X = age). Loaded
  /// lazily when that chart is opened, not on the common applyFilter path.
  List<HatchAgePoint> _hatchByAge = const [];
  DashboardFilter? _lastFilter;

  bool get isLoading => _isLoading;

  List<HatchAgePoint> get hatchAgeSeries => _hatchByAge;

  /// Load every sector for the given filter (idempotent per filter). Pulls the
  /// BMK reference once and reuses it across live sectors.
  Future<void> applyFilter({
    String? customerId,
    String? flockId,
    int? bmkAge,
  }) async {
    final key = '$customerId|$flockId|$bmkAge';
    if (key == _filterKey && _groups.isNotEmpty) return;
    _filterKey = key;
    // New filter → drop per-sector period/cumulative caches so they re-derive.
    _selectedPeriod.clear();
    _periods.clear();
    _cumSeries.clear();
    _cumLoading.clear();
    _isLoading = true;
    notifyListeners();

    final filter = DashboardFilter(
      customerId: customerId,
      flockId: flockId,
      bmkAge: bmkAge,
    );
    _lastFilter = filter;

    // Example/dummy data is limited to the demo customer; real customers show
    // live data or an empty state.
    final isDemo = customerId == kDashboardDemoCustomerId;
    BmkReference? liveBmk;
    try {
      // Pick a BMK reference: explicit age, else the dominant age in the data.
      final refAge = bmkAge ?? await _repo.dominantBmkAge(filter);
      if (refAge != null) {
        liveBmk = await _panelRepo.getBmkReferenceForAge(refAge);
      }
      for (final sector in ScopeConfigRegistry.sectors) {
        List<ScopeLeafRow> leaves = const [];
        try {
          leaves = await _repo.getScopeLeaves(sector, filter);
        } catch (e) {
          debugPrint('Scope load failed for ${sector.id}: $e');
        }
        if (leaves.isNotEmpty) {
          _leaves[sector.id] = leaves;
          _isDummy[sector.id] = false;
          _isEmpty[sector.id] = false;
          _sectorBmk[sector.id] = liveBmk;
        } else if (isDemo) {
          _leaves[sector.id] = ScopeDummyData.leavesFor(sector.id);
          _isDummy[sector.id] = true;
          _isEmpty[sector.id] = false;
          _sectorBmk[sector.id] = ScopeDummyData.demoBmk;
        } else {
          _leaves[sector.id] = const [];
          _isDummy[sector.id] = false;
          _isEmpty[sector.id] = true;
          _sectorBmk[sector.id] = liveBmk;
        }
        _selectedLayers.putIfAbsent(
          sector.id,
          () => ScopeEngine.nonPoolLayers(sector),
        );
        _recompute(sector.id);
        try {
          _periods[sector.id] = await _repo.distinctPeriods(sector, filter);
        } catch (e) {
          debugPrint('Periods load failed for ${sector.id}: $e');
          _periods[sector.id] = const [];
        }
      }
    } catch (e) {
      debugPrint('Scope applyFilter error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    // Refresh the lazily-loaded Hatch age chart if it's already open so a filter
    // change updates it. Fire-and-forget — never blocks the main load.
    if (isChartMode('hatch_results')) _loadHatchAgeSeries();
  }

  /// Pull-to-refresh: force a re-query for the current filter, bypassing the
  /// idempotency guard in [applyFilter].
  Future<void> refresh() {
    final f = _lastFilter;
    _filterKey = null;
    return applyFilter(
      customerId: f?.customerId,
      flockId: f?.flockId,
      bmkAge: f?.bmkAge,
    );
  }

  // ── interaction ──────────────────────────────────────────────────────────

  /// Toggle a breakdown layer; recomputes columns and resets pick state to
  /// all-shown (matches the prototype's `applyScopeLayers`).
  void toggleLayer(String sectorId, SamplingLayer layer) {
    final sector = ScopeConfigRegistry.byId(sectorId);
    final nonPool = ScopeEngine.nonPoolLayers(sector);
    final current = {...(_selectedLayers[sectorId] ?? const <SamplingLayer>[])};
    current.contains(layer) ? current.remove(layer) : current.add(layer);
    _selectedLayers[sectorId] =
        nonPool.where(current.contains).toList(); // hierarchy order
    _hidden[sectorId] = <int>{};
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

  /// Narrow the Incremental view to one age/visit (null = All). Re-queries that
  /// sector's leaves with the period filter and recomputes — same code path as
  /// the global filter, so the matrix/tiles render exactly as before.
  Future<void> setPeriod(String sectorId, ScopePeriod? period) async {
    _selectedPeriod[sectorId] = period;
    final base = _lastFilter;
    if (base != null && !isDummyFor(sectorId)) {
      final sector = ScopeConfigRegistry.byId(sectorId);
      final f = DashboardFilter(
        customerId: base.customerId,
        flockId: base.flockId,
        bmkAge: period?.age,
        sessionId: period?.sessionId,
      );
      try {
        final leaves = await _repo.getScopeLeaves(sector, f);
        BmkReference? bmk = _sectorBmk[sectorId];
        if (period?.age != null) {
          bmk = await _panelRepo.getBmkReferenceForAge(period!.age!);
        }
        _leaves[sectorId] = leaves;
        _sectorBmk[sectorId] = bmk;
        _isEmpty[sectorId] = leaves.isEmpty;
        _recompute(sectorId);
      } catch (e) {
        debugPrint('setPeriod $sectorId failed: $e');
      }
    }
    notifyListeners();
  }

  // ── Cumulative series (per-axis trend) ─────────────────────────────────────
  CumulativeSeries? cumulativeSeriesFor(String sectorId) =>
      _cumSeries[sectorId];

  bool isCumulativeLoading(String sectorId) => _cumLoading.contains(sectorId);

  /// Build (once, cached) the per-period pooled series for a sector. Reuses
  /// [ScopeEngine] so each period's value equals the Incremental pool value.
  Future<void> loadCumulative(String sectorId) async {
    if (_cumSeries.containsKey(sectorId) || _cumLoading.contains(sectorId)) {
      return;
    }
    final base = _lastFilter;
    // Dummy/example sectors and the no-filter state have no DB rows to spread —
    // cache an empty series so the view shows its note instead of spinning.
    if (base == null || isDummyFor(sectorId)) {
      _cumSeries[sectorId] = const CumulativeSeries(periods: [], params: []);
      notifyListeners();
      return;
    }
    final sector = ScopeConfigRegistry.byId(sectorId);
    _cumLoading.add(sectorId);
    notifyListeners();
    try {
      var periods = _periods[sectorId];
      if (periods == null || periods.isEmpty) {
        periods = await _repo.distinctPeriods(sector, base);
        _periods[sectorId] = periods;
      }
      _cumSeries[sectorId] = await _buildCumulative(sector, periods, base);
    } catch (e) {
      debugPrint('loadCumulative $sectorId failed: $e');
      _cumSeries[sectorId] =
          const CumulativeSeries(periods: [], params: []);
    } finally {
      _cumLoading.remove(sectorId);
      notifyListeners();
    }
  }

  Future<CumulativeSeries> _buildCumulative(
    ScopeSectorConfig sector,
    List<ScopePeriod> periods,
    DashboardFilter base,
  ) async {
    final periodCells = <List<ScopeCell>>[];
    final periodBmk = <BmkReference?>[];
    for (final p in periods) {
      final f = DashboardFilter(
        customerId: base.customerId,
        flockId: base.flockId,
        bmkAge: p.age,
        sessionId: p.sessionId,
      );
      final leaves = await _repo.getScopeLeaves(sector, f);
      BmkReference? bmk;
      if (p.age != null) bmk = await _panelRepo.getBmkReferenceForAge(p.age!);
      final groups = ScopeEngine.comboGroups(sector, leaves, const [], bmk);
      periodCells.add(groups.isNotEmpty ? groups.first.cells : const []);
      periodBmk.add(bmk);
    }
    final params = <CumulativeParam>[];
    for (var j = 0; j < sector.params.length; j++) {
      final param = sector.params[j];
      final values = <num?>[];
      final bmks = <num?>[];
      final texts = <String>[];
      final sevs = <ScopeSeverity>[];
      for (var pi = 0; pi < periods.length; pi++) {
        final cells = periodCells[pi];
        final cell = j < cells.length ? cells[j] : null;
        values.add(cell?.value);
        texts.add(cell?.text ?? '—');
        sevs.add(cell?.severity ?? ScopeSeverity.good);
        bmks.add(
          param.bmkField != null ? bmkLookup(periodBmk[pi], param.bmkField) : null,
        );
      }
      params.add(CumulativeParam(
        param: param,
        values: values,
        bmks: bmks,
        texts: texts,
        severities: sevs,
      ));
    }
    return CumulativeSeries(periods: periods, params: params);
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
    try {
      _hatchByAge = await _panelRepo.getHatchByAge(filter);
      notifyListeners();
    } catch (e) {
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

  bool isLayerOn(String sectorId, SamplingLayer layer) =>
      _selectedLayers[sectorId]?.contains(layer) ?? false;

  List<ScopeGroup> groupsFor(String sectorId) =>
      _groups[sectorId] ?? const [];

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
    final sector = ScopeConfigRegistry.byId(sectorId);
    _groups[sectorId] = ScopeEngine.comboGroups(
      sector,
      _leaves[sectorId] ?? const [],
      _selectedLayers[sectorId] ?? const [],
      _sectorBmk[sectorId],
    );
  }
}
