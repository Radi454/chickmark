import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:hatchaudit/data/repositories/customer_repository.dart';
import 'package:hatchaudit/data/repositories/dashboard_action_repository.dart';
import 'package:hatchaudit/data/repositories/flock_repository.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:hatchaudit/data/repositories/hatchery_repository.dart';
import 'package:hatchaudit/data/repositories/lab_analysis_repository.dart';
import 'package:hatchaudit/data/repositories/panel_dashboard_repository.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/dashboard_action_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/hatchery_model.dart';
import 'package:hatchaudit/data/models/lab_analysis_models.dart';
import 'package:hatchaudit/data/models/troubleshooting_model.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_filter.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_intelligence_models.dart';
import 'package:hatchaudit/features/dashboard/models/hatch_analysis_models.dart';
import 'package:hatchaudit/features/dashboard/models/egg_breakout_models.dart';
import 'package:hatchaudit/features/dashboard/models/chick_quality_models.dart';
import 'package:hatchaudit/features/dashboard/models/egg_storage_models.dart';
import 'package:hatchaudit/features/dashboard/models/govee_capture_summary.dart';
import 'package:hatchaudit/features/dashboard/models/visit_session_summary.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_models.dart';

class DashboardProvider extends ChangeNotifier {
  final PanelDashboardRepository _panelDashboardRepo;
  final CustomerRepository _customerRepo;
  final FlockRepository _flockRepo;
  final HatcheryRepository _hatcheryRepo;
  final LabAnalysisRepository _labAnalysisRepo;
  final GoveeCaptureRepository _goveeCaptureRepo;
  final DashboardActionRepository _actionRepo;

  DashboardProvider({
    PanelDashboardRepository? panelDashboardRepository,
    CustomerRepository? customerRepository,
    FlockRepository? flockRepository,
    HatcheryRepository? hatcheryRepository,
    LabAnalysisRepository? labAnalysisRepository,
    GoveeCaptureRepository? goveeCaptureRepository,
    DashboardActionRepository? dashboardActionRepository,
  }) : _panelDashboardRepo =
           panelDashboardRepository ?? PanelDashboardRepository(),
       _customerRepo = customerRepository ?? CustomerRepository(),
       _flockRepo = flockRepository ?? FlockRepository(),
       _hatcheryRepo = hatcheryRepository ?? HatcheryRepository(),
       _labAnalysisRepo = labAnalysisRepository ?? LabAnalysisRepository(),
       _goveeCaptureRepo = goveeCaptureRepository ?? GoveeCaptureRepository(),
       _actionRepo = dashboardActionRepository ?? DashboardActionRepository();

  String? _selectedCustomerId;
  String? _selectedHatcheryId;
  String? _selectedFlockId;
  int? _selectedBmkAge;
  String _selectedBreakoutType = 'residue';
  bool _isInitialized = false;
  int _scopeGeneration = 0;
  Completer<void>? _reloadDrain;
  bool _reloadRequested = false;
  bool _reloadRequestedWithLoading = false;

  List<CustomerModel> _customers = [];
  List<HatcheryModel> _hatcheries = [];
  List<FlockModel> _flocks = [];
  List<int> _availableBmkAges = [];
  final List<String> _availableSetterIds = [];
  final List<String> _availableHatcherIds = [];
  final Set<String> _selectedSetterIds = {};
  final Set<String> _selectedHatcherIds = {};

  bool _isLoading = false;

  HatchAnalysisAvg? _hatchAnalysisAvg;
  List<HatchAnalysisTrend> _hatchAnalysisTrend = [];
  EggBreakoutAvg? _eggBreakoutAvg;
  List<EggBreakoutTrend> _eggBreakoutTrend = [];
  List<String> _eggBreakoutPhotos = [];

  List<ChickWeightTrend> _chickWeightTrend = [];
  PasgarAvg? _pasgarAvg;
  Map<String, TroubleshootingModel> _pasgarReferences = {};
  CvtAvg? _cvtAvg;
  List<YfbmTrend> _yfbmTrend = [];
  CulledChicksAnalysisAvg? _culledChicksAnalysis;
  List<String> _cvtPhotos = [];
  List<String> _yfbmPhotos = [];

  final List<EggStorageTrend> _eggStorageTrend = [];
  EggStorageEstEvidence? _eggStorageEstEvidence;
  final List<String> _uvPhotos = [];

  List<SetterComparison> _setterComparisons = [];
  List<HatcherComparison> _hatcherComparisons = [];

  BmkReference? _bmkReference;
  UserModel? _currentUser;

  // Visit-session aggregation state (US6)
  List<VisitSessionSummary> _visitSessions = [];
  VisitSessionSummary? _selectedVisitSession;
  List<GoveeCaptureSummary> _goveeCaptures = [];
  String? _goveeError;
  bool _isLoadingGoveeCaptures = false;
  List<LabAnalysisDashboardSummary> _labAnalysisSummaries = [];
  bool _isLoadingLabAnalysis = false;
  List<DashboardActionModel> _actions = [];
  bool _isSavingAction = false;
  String? _actionError;

  String? get selectedCustomerId => _selectedCustomerId;
  String? get selectedHatcheryId => _selectedHatcheryId;
  String? get selectedFlockId => _selectedFlockId;
  int? get selectedBmkAge => _selectedBmkAge;
  String get selectedBreakoutType => _selectedBreakoutType;
  bool get hasActiveFilters =>
      (canUseAllCustomers && _selectedCustomerId != null) ||
      _selectedHatcheryId != null ||
      _selectedFlockId != null ||
      _selectedBmkAge != null;

  int get activeFilterCount {
    var count = 0;
    if (canUseAllCustomers && _selectedCustomerId != null) count++;
    if (_selectedHatcheryId != null) count++;
    if (_selectedFlockId != null) count++;
    if (_selectedBmkAge != null) count++;
    return count;
  }

  List<CustomerModel> get customers => _customers;
  List<HatcheryModel> get hatcheries => _hatcheries;
  List<FlockModel> get flocks => _flocks;
  List<int> get availableBmkAges => _availableBmkAges;
  List<String> get availableSetterIds => _availableSetterIds;
  List<String> get availableHatcherIds => _availableHatcherIds;
  Set<String> get selectedSetterIds => _selectedSetterIds;
  Set<String> get selectedHatcherIds => _selectedHatcherIds;

  bool get isLoading => _isLoading;

  HatchAnalysisAvg? get hatchAnalysisAvg => _hatchAnalysisAvg;
  List<HatchAnalysisTrend> get hatchAnalysisTrend => _hatchAnalysisTrend;
  EggBreakoutAvg? get eggBreakoutAvg => _eggBreakoutAvg;
  List<EggBreakoutTrend> get eggBreakoutTrend => _eggBreakoutTrend;
  List<String> get eggBreakoutPhotos => _eggBreakoutPhotos;

  List<ChickWeightTrend> get chickWeightTrend => _chickWeightTrend;
  ChickWeightTrend? get chickWeightLatest =>
      _chickWeightTrend.isNotEmpty ? _chickWeightTrend.last : null;
  PasgarAvg? get pasgarAvg => _pasgarAvg;
  Map<String, TroubleshootingModel> get pasgarReferences => _pasgarReferences;
  CvtAvg? get cvtAvg => _cvtAvg;
  List<YfbmTrend> get yfbmTrend => _yfbmTrend;
  CulledChicksAnalysisAvg? get culledChicksAnalysis => _culledChicksAnalysis;
  List<String> get cvtPhotos => _cvtPhotos;
  List<String> get yfbmPhotos => _yfbmPhotos;

  List<EggStorageTrend> get eggStorageTrend => _eggStorageTrend;
  EggStorageTrend? get eggStorageLatest =>
      _eggStorageTrend.isNotEmpty ? _eggStorageTrend.last : null;
  EggStorageEstEvidence? get eggStorageEstEvidence => _eggStorageEstEvidence;
  List<String> get uvPhotos => _uvPhotos;

  List<SetterComparison> get setterComparisons => _setterComparisons;
  List<HatcherComparison> get hatcherComparisons => _hatcherComparisons;

  BmkReference? get bmkReference => _bmkReference;

  // Visit-session aggregation getters (US6)
  List<VisitSessionSummary> get visitSessions => _visitSessions;
  VisitSessionSummary? get selectedVisitSession => _selectedVisitSession;
  List<GoveeCaptureSummary> get goveeCaptures => _goveeCaptures;
  String? get goveeError => _goveeError;
  bool get isLoadingGoveeCaptures => _isLoadingGoveeCaptures;
  List<LabAnalysisDashboardSummary> get labAnalysisSummaries =>
      _labAnalysisSummaries;
  bool get isLoadingLabAnalysis => _isLoadingLabAnalysis;
  List<DashboardActionModel> get actions => List.unmodifiable(_actions);
  bool get isSavingAction => _isSavingAction;
  String? get actionError => _actionError;
  bool get canUseAllCustomers {
    final user = _currentUser;
    return user != null && !user.isCustomer;
  }

  bool get canManageActions => _currentUser?.canEditAudits ?? false;

  bool get isOperationalScope =>
      _selectedCustomerId != null && _selectedHatcheryId != null;

  DashboardActionModel? actionForFinding(String findingKey) {
    for (final action in _actions) {
      if (action.findingKey == findingKey && !action.isResolved) return action;
    }
    return null;
  }

  Future<void> init({UserModel? currentUser}) async {
    prepareForUser(currentUser);
    final generation = _scopeGeneration;
    if (_isInitialized) {
      // Singleton provider: this runs on every dashboard mount. Refresh the
      // pick list so customers synced since first load — or a different scope
      // after an account switch (auditor → admin) — show up without a restart.
      // reload() refreshes the pick lists then reloads the sector data.
      await reload();
      return;
    }
    _isInitialized = true;
    _isLoading = true;
    notifyListeners();

    try {
      // reload() refreshes the pick lists, then loads the sector data. init
      // owns the full-screen spinner, so it runs without flipping the flag.
      await reload(showLoading: false);
    } catch (e) {
      if (_isCurrentScope(generation)) {
        debugPrint('Error loading dashboard: $e');
      }
    } finally {
      if (_isCurrentScope(generation)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Synchronously clears data retained by the app-scoped provider when the
  /// signed-in identity or tenant changes. DashboardScreen calls this before
  /// its first build so a customer never sees a frame cached for a prior user.
  void prepareForUser(UserModel? user) {
    final previousKey = _userScopeKey(_currentUser);
    final nextKey = _userScopeKey(user);
    if (previousKey == nextKey) return;
    _scopeGeneration++;
    _currentUser = user;
    _selectedCustomerId = user?.isCustomer == true ? user?.customerId : null;
    _selectedHatcheryId = null;
    _selectedFlockId = null;
    _selectedBmkAge = null;
    _customers = [];
    _hatcheries = [];
    _flocks = [];
    _availableBmkAges = [];
    _clearHiddenSectorData();
    _isLoading = true;
  }

  bool _isCurrentScope(int generation) => generation == _scopeGeneration;

  String _userScopeKey(UserModel? user) => user == null
      ? 'signed-out'
      : '${user.id}|${user.role}|${user.status}|${user.customerId ?? ''}';

  /// (Re)load the customer + flock + bmk-age pick lists from local storage.
  /// **Pure**: refreshes list state only — it never triggers a sector-data
  /// reload, so [reload] can call it without re-entering itself. Callers that
  /// also want fresh sector data call [reload] (which calls this first).
  Future<void> _refreshPickLists([int? expectedGeneration]) async {
    final generation = expectedGeneration ?? _scopeGeneration;
    final customers = await _customerRepo.getAllCustomers();
    if (!_isCurrentScope(generation)) return;
    _customers = _scopeCustomers(customers);
    // Keep the user's current pick if still valid; otherwise fall back. Customer
    // role can't use "All", so it must always land on a concrete customer.
    final selectionValid =
        _selectedCustomerId != null &&
        _customers.any((customer) => customer.id == _selectedCustomerId);
    if (!selectionValid) {
      _selectedCustomerId = (!canUseAllCustomers && _customers.isNotEmpty)
          ? _customers.first.id
          : (canUseAllCustomers ? null : _selectedCustomerId);
    }
    await _refreshHatcheries(generation);
    if (!_isCurrentScope(generation)) return;
    await _refreshFlocks(generation);
  }

  Future<void> _refreshHatcheries([int? expectedGeneration]) async {
    final generation = expectedGeneration ?? _scopeGeneration;
    final customerId = _selectedCustomerId;
    final hatcheries = customerId == null
        ? await _hatcheryRepo.getAllHatcheries()
        : await _hatcheryRepo.getHatcheriesByCustomer(customerId);
    if (!_isCurrentScope(generation)) return;
    _hatcheries = hatcheries;
    final selectionValid =
        _selectedHatcheryId != null &&
        _hatcheries.any((hatchery) => hatchery.id == _selectedHatcheryId);
    if (!selectionValid) {
      _selectedHatcheryId =
          _selectedCustomerId != null && _hatcheries.length == 1
          ? _hatcheries.first.id
          : null;
    }
  }

  /// (Re)load the flock pick list for the current customer plus its bmk ages.
  /// **Pure**: list state only, no sector-data reload. Mutators that change the
  /// customer/flock set call this then [reload] explicitly.
  Future<void> _refreshFlocks([int? expectedGeneration]) async {
    final generation = expectedGeneration ?? _scopeGeneration;
    final customerId = _selectedCustomerId;
    final flocks = customerId == null
        ? await _flockRepo.getAllFlocks()
        : await _flockRepo.getFlocksByCustomer(customerId);
    if (!_isCurrentScope(generation)) return;
    _flocks = _scopeFlocks(flocks);
    if (_selectedFlockId != null &&
        !_flocks.any((flock) => flock.id == _selectedFlockId)) {
      _selectedFlockId = null;
    }
    await _loadBmkAges(generation);
  }

  Future<void> _loadBmkAges([int? expectedGeneration]) async {
    final generation = expectedGeneration ?? _scopeGeneration;
    final ages = await _panelDashboardRepo.getDistinctBmkAges(
      customerId: _selectedCustomerId,
      hatcheryId: _selectedHatcheryId,
      flockId: _selectedFlockId,
    );
    if (!_isCurrentScope(generation)) return;
    _availableBmkAges = ages;
    if (!_availableBmkAges.contains(_selectedBmkAge)) {
      _selectedBmkAge = null;
    }
    notifyListeners();
  }

  Future<void> setCustomer(String? customerId) async {
    _scopeGeneration++;
    _selectedCustomerId = canUseAllCustomers
        ? customerId
        : _currentUser?.customerId;
    _selectedFlockId = null;
    _selectedHatcheryId = null;
    _selectedBmkAge = null;
    await _refreshHatcheries();
    await _refreshFlocks();
    await reload();
  }

  Future<void> setHatchery(String? hatcheryId) async {
    _scopeGeneration++;
    _selectedHatcheryId = hatcheryId;
    _selectedFlockId = null;
    _selectedBmkAge = null;
    await _loadBmkAges();
    await reload();
  }

  Future<void> setFlock(String? flockId) async {
    _scopeGeneration++;
    _selectedFlockId = flockId;
    _selectedBmkAge = null;
    await _loadBmkAges();
    await reload();
  }

  void setBmkAge(int? age) {
    _scopeGeneration++;
    _selectedBmkAge = age;
    reload();
  }

  Future<void> clearFilters() async {
    _scopeGeneration++;
    _selectedCustomerId = canUseAllCustomers ? null : _currentUser?.customerId;
    _selectedFlockId = null;
    _selectedHatcheryId = null;
    _selectedBmkAge = null;
    _selectedBreakoutType = 'residue';
    _selectedSetterIds.clear();
    _selectedHatcherIds.clear();
    _flocks = [];
    await _refreshHatcheries();
    await _refreshFlocks();
    await reload();
  }

  void setBreakoutType(String type) {
    _scopeGeneration++;
    _selectedBreakoutType = type;
    reload();
  }

  Future<void> selectVisitSession(VisitSessionSummary session) async {
    final generation = _scopeGeneration;
    _selectedVisitSession = session;
    _isLoadingGoveeCaptures = true;
    notifyListeners();
    await _loadGoveeCapturesForVisit(session, generation);
    if (!_isCurrentScope(generation)) return;
    _isLoadingGoveeCaptures = false;
    notifyListeners();
  }

  void toggleSetter(String setterId) {
    _scopeGeneration++;
    if (_selectedSetterIds.contains(setterId)) {
      _selectedSetterIds.remove(setterId);
    } else {
      _selectedSetterIds.add(setterId);
    }
    reload();
  }

  void toggleHatcher(String hatcherId) {
    _scopeGeneration++;
    if (_selectedHatcherIds.contains(hatcherId)) {
      _selectedHatcherIds.remove(hatcherId);
    } else {
      _selectedHatcherIds.add(hatcherId);
    }
    reload();
  }

  /// Pull-to-refresh entry point. Re-queries the current filter without
  /// flipping the full-screen [isLoading] flag — the RefreshIndicator shows its
  /// own spinner, so the content stays put and updates in place.
  Future<void> refresh() => reload(showLoading: false);

  /// Serializes and coalesces dashboard reloads. Sync completion, reconnect,
  /// pull-to-refresh, and filter changes can otherwise overlap and expose the
  /// temporary cleared sector state. That collapses the long Lab Analysis card
  /// and clamps the outer scroll position, which looks like a random jump to a
  /// different dashboard sector.
  Future<void> reload({bool showLoading = true}) {
    _reloadRequested = true;
    _reloadRequestedWithLoading = _reloadRequestedWithLoading || showLoading;

    final active = _reloadDrain;
    if (active != null) return active.future;

    final drain = Completer<void>();
    _reloadDrain = drain;
    unawaited(_drainReloadQueue(drain));
    return drain.future;
  }

  Future<void> _drainReloadQueue(Completer<void> drain) async {
    try {
      while (_reloadRequested) {
        final showLoading = _reloadRequestedWithLoading;
        _reloadRequested = false;
        _reloadRequestedWithLoading = false;
        await _reloadOnce(showLoading: showLoading);
      }
      drain.complete();
    } catch (error, stackTrace) {
      drain.completeError(error, stackTrace);
    } finally {
      if (identical(_reloadDrain, drain)) _reloadDrain = null;
    }
  }

  Future<void> _reloadOnce({required bool showLoading}) async {
    final generation = _scopeGeneration;
    if (_currentUser == null) {
      _clearHiddenSectorData();
      _isLoading = false;
      notifyListeners();
      return;
    }
    if (showLoading) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      // Refresh the pick lists first so customers/flocks synced since the last
      // load appear in the filter (pull-to-refresh after a Sync Now).
      await _refreshPickLists(generation);
      if (!_isCurrentScope(generation)) return;

      final filter = DashboardFilter(
        customerId: _selectedCustomerId,
        hatcheryId: _selectedHatcheryId,
        flockId: _selectedFlockId,
        bmkAge: _selectedBmkAge,
      );

      // A background refresh must keep the current sector widgets mounted.
      // Clearing Lab Analysis here can remove several screen-heights of content
      // while the query is in flight and permanently clamp the ListView offset.
      if (showLoading) _clearHiddenSectorData();
      _isLoadingLabAnalysis = true;
      if (!showLoading) notifyListeners();
      await _loadLabAnalysis(filter, generation, preserveOnError: !showLoading);
      if (!_isCurrentScope(generation)) return;
      _isLoadingLabAnalysis = false;
      if (!filter.isOperational) {
        _goveeCaptures = const [];
        _goveeError = null;
        _isLoadingGoveeCaptures = false;
        _actions = const [];
        return;
      }
      _isLoadingGoveeCaptures = true;
      final futures = <Future<void>>[
        // Station metrics are loaded once by ScopeComparisonRepository's
        // analytics bundle. The legacy per-card queries are intentionally not
        // repeated here because those bespoke cards are no longer rendered.
        _loadSavedGoveeCaptures(filter, generation),
        _loadActions(filter, generation),
      ];

      await Future.wait(futures);
      if (!_isCurrentScope(generation)) return;
      _isLoadingGoveeCaptures = false;

      _bmkReference = null;
      if (_selectedBmkAge != null) {
        final reference = await _panelDashboardRepo.getBmkReferenceForAge(
          _selectedBmkAge!,
        );
        if (!_isCurrentScope(generation)) return;
        _bmkReference = reference;
      }
    } catch (e) {
      if (!_isCurrentScope(generation)) return;
      debugPrint('Error reloading dashboard: $e');
      _isLoadingGoveeCaptures = false;
      _isLoadingLabAnalysis = false;
    } finally {
      if (_isCurrentScope(generation)) {
        if (showLoading) _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadSavedGoveeCaptures(
    DashboardFilter filter,
    int generation,
  ) async {
    try {
      final captures = await _goveeCaptureRepo.getCapturesForDashboard(
        customerId: filter.customerId,
        hatcheryId: filter.hatcheryId,
      );
      if (!_isCurrentScope(generation)) return;
      _goveeCaptures = [
        for (final capture in captures)
          GoveeCaptureSummary(
            capture: capture,
            readings: capture.chartReadings,
          ),
      ];
      _goveeError = null;
    } catch (e) {
      if (!_isCurrentScope(generation)) return;
      debugPrint('Error loading saved Govee captures: $e');
      _goveeCaptures = [];
      _goveeError = e.toString();
    }
  }

  Future<void> _loadActions(
    DashboardFilter filter, [
    int? expectedGeneration,
  ]) async {
    final generation = expectedGeneration ?? _scopeGeneration;
    if (!filter.isOperational) {
      _actions = const [];
      return;
    }
    final actions = await _actionRepo.getForScope(
      customerId: filter.customerId!,
      hatcheryId: filter.hatcheryId!,
      flockId: filter.flockId,
    );
    if (!_isCurrentScope(generation)) return;
    _actions = actions;
  }

  Future<void> _loadLabAnalysis(
    DashboardFilter filter,
    int generation, {
    bool preserveOnError = false,
  }) async {
    try {
      final summaries = await _labAnalysisRepo.getDashboardSummaries(
        customerId: filter.customerId,
        flockId: filter.flockId,
      );
      if (!_isCurrentScope(generation)) return;
      _labAnalysisSummaries = summaries;
    } catch (e) {
      if (!_isCurrentScope(generation)) return;
      debugPrint('Error loading lab analysis dashboard data: $e');
      if (!preserveOnError) _labAnalysisSummaries = [];
    }
  }

  Future<DashboardActionModel?> createAction(
    DashboardFinding finding, {
    String? ownerName,
    DateTime? dueAt,
    String? description,
  }) async {
    if (!canManageActions) return null;
    final customerId = _selectedCustomerId;
    final hatcheryId = _selectedHatcheryId;
    if (customerId == null || hatcheryId == null) return null;
    final now = DateTime.now();
    final action = DashboardActionModel(
      id: const Uuid().v4(),
      findingKey: finding.key,
      customerId: customerId,
      hatcheryId: hatcheryId,
      flockId: _selectedFlockId,
      sessionId: finding.sessionId,
      panelName: finding.panelName,
      panelRowId: finding.panelRowId,
      metricKey: finding.metricKey,
      title: finding.metricLabel,
      description: description ?? finding.advice,
      priority: finding.severity == ScopeSeverity.err
          ? DashboardActionPriority.critical
          : DashboardActionPriority.watch,
      ownerName: ownerName,
      dueAt: dueAt,
      firstObservedAt: finding.latestAt ?? now,
      lastObservedAt: finding.latestAt ?? now,
      createdBy: _currentUser?.id,
      createdAt: now,
      updatedAt: now,
    );
    return _saveAction(action);
  }

  Future<DashboardActionModel?> updateAction(
    DashboardActionModel action, {
    DashboardActionStatus? status,
    String? ownerName,
    DateTime? dueAt,
    String? resolutionNotes,
  }) {
    if (!canManageActions) return Future.value(null);
    final nextStatus = status ?? action.status;
    return _saveAction(
      action.copyWith(
        status: nextStatus,
        ownerName: ownerName,
        dueAt: dueAt,
        resolvedAt: nextStatus == DashboardActionStatus.resolved
            ? DateTime.now()
            : null,
        resolutionNotes: resolutionNotes,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<DashboardActionModel?> _saveAction(DashboardActionModel action) async {
    final generation = _scopeGeneration;
    _isSavingAction = true;
    _actionError = null;
    notifyListeners();
    try {
      await _actionRepo.save(action);
      if (!_isCurrentScope(generation)) return null;
      await _loadActions(
        DashboardFilter(
          customerId: _selectedCustomerId,
          hatcheryId: _selectedHatcheryId,
          flockId: _selectedFlockId,
        ),
        generation,
      );
      if (!_isCurrentScope(generation)) return null;
      for (final item in _actions) {
        if (item.id == action.id) return item;
      }
      return null;
    } catch (error) {
      if (!_isCurrentScope(generation)) return null;
      _actionError = error.toString();
      return null;
    } finally {
      if (_isCurrentScope(generation)) {
        _isSavingAction = false;
        notifyListeners();
      }
    }
  }

  void _clearHiddenSectorData() {
    _hatchAnalysisAvg = null;
    _hatchAnalysisTrend = [];
    _eggBreakoutAvg = null;
    _eggBreakoutTrend = [];
    _eggBreakoutPhotos = [];
    _chickWeightTrend = [];
    _pasgarAvg = null;
    _pasgarReferences = {};
    _cvtAvg = null;
    _yfbmTrend = [];
    _culledChicksAnalysis = null;
    _cvtPhotos = [];
    _yfbmPhotos = [];
    _eggStorageTrend.clear();
    _eggStorageEstEvidence = null;
    _uvPhotos.clear();
    _setterComparisons = [];
    _hatcherComparisons = [];
    _visitSessions = [];
    _selectedVisitSession = null;
    _labAnalysisSummaries = [];
    _actions = [];
    _goveeCaptures = const [];
    _goveeError = null;
    _bmkReference = null;
    _isLoadingGoveeCaptures = false;
    _isLoadingLabAnalysis = false;
    _actionError = null;
    _isSavingAction = false;
    _availableSetterIds.clear();
    _availableHatcherIds.clear();
    _selectedSetterIds.clear();
    _selectedHatcherIds.clear();
  }

  Future<void> _loadGoveeCapturesForVisit(
    VisitSessionSummary visit,
    int generation,
  ) async {
    try {
      final session = visit.session;
      final captures = await _goveeCaptureRepo.getCapturesForDashboard(
        customerId: session.customerId,
        hatcheryId: session.hatcheryId,
        captureDate: _captureDateKey(session.date),
      );
      if (!_isCurrentScope(generation)) return;
      _goveeCaptures = [
        for (final capture in captures)
          GoveeCaptureSummary(
            capture: capture,
            readings: capture.chartReadings,
          ),
      ];
      _goveeError = null;
    } catch (e) {
      if (!_isCurrentScope(generation)) return;
      debugPrint('Error loading Govee captures: $e');
      _goveeCaptures = [];
      _goveeError = e.toString();
    }
  }

  String _captureDateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  List<CustomerModel> _scopeCustomers(List<CustomerModel> customers) {
    final user = _currentUser;
    if (user == null || !user.isCustomer) return customers;
    final customerId = user.customerId;
    if (customerId == null || customerId.isEmpty) return [];
    return customers.where((customer) => customer.id == customerId).toList();
  }

  List<FlockModel> _scopeFlocks(List<FlockModel> flocks) {
    final user = _currentUser;
    if (user == null || !user.isCustomer) return flocks;
    final customerId = user.customerId;
    if (customerId == null || customerId.isEmpty) return [];
    return flocks.where((flock) => flock.customerId == customerId).toList();
  }
}
