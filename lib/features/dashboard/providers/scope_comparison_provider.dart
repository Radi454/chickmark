import 'package:flutter/foundation.dart';

import '../../../data/models/panel_sample_schema.dart';
import '../../../data/repositories/panel_dashboard_repository.dart';
import '../../../data/repositories/scope_comparison_repository.dart';
import '../models/dashboard_filter.dart';
import '../models/egg_storage_models.dart';
import '../scope/scope_config.dart';
import '../scope/scope_dummy_data.dart';
import '../scope/scope_engine.dart';
import '../scope/scope_models.dart';

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
  final Map<String, BmkReference?> _sectorBmk = {};
  final Map<String, List<SamplingLayer>> _selectedLayers = {};
  final Map<String, Set<int>> _hidden = {};
  final Map<String, List<ScopeGroup>> _groups = {};

  bool get isLoading => _isLoading;

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
    _isLoading = true;
    notifyListeners();

    final filter = DashboardFilter(
      customerId: customerId,
      flockId: flockId,
      bmkAge: bmkAge,
    );

    BmkReference? liveBmk;
    try {
      if (bmkAge != null) {
        liveBmk = await _panelRepo.getBmkReferenceForAge(bmkAge);
      }
      for (final sector in ScopeConfigRegistry.sectors) {
        List<ScopeLeafRow> leaves = const [];
        try {
          leaves = await _repo.getScopeLeaves(sector, filter);
        } catch (e) {
          debugPrint('Scope load failed for ${sector.id}: $e');
        }
        if (leaves.isEmpty) {
          _leaves[sector.id] = ScopeDummyData.leavesFor(sector.id);
          _isDummy[sector.id] = true;
          _sectorBmk[sector.id] = ScopeDummyData.demoBmk;
        } else {
          _leaves[sector.id] = leaves;
          _isDummy[sector.id] = false;
          _sectorBmk[sector.id] = liveBmk;
        }
        _selectedLayers.putIfAbsent(
          sector.id,
          () => ScopeEngine.nonPoolLayers(sector),
        );
        _recompute(sector.id);
      }
    } catch (e) {
      debugPrint('Scope applyFilter error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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
