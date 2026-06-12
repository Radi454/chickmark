import 'package:flutter/foundation.dart';
import 'package:hatchaudit/data/repositories/customer_repository.dart';
import 'package:hatchaudit/data/repositories/flock_repository.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:hatchaudit/data/repositories/panel_dashboard_repository.dart';
import 'package:hatchaudit/data/repositories/troubleshooting_repository.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/troubleshooting_model.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_filter.dart';
import 'package:hatchaudit/features/dashboard/models/hatch_analysis_models.dart';
import 'package:hatchaudit/features/dashboard/models/egg_breakout_models.dart';
import 'package:hatchaudit/features/dashboard/models/chick_quality_models.dart';
import 'package:hatchaudit/features/dashboard/models/egg_storage_models.dart';
import 'package:hatchaudit/features/dashboard/models/govee_capture_summary.dart';
import 'package:hatchaudit/features/dashboard/models/visit_session_summary.dart';

class DashboardProvider extends ChangeNotifier {
  final PanelDashboardRepository _panelDashboardRepo =
      PanelDashboardRepository();
  final TroubleshootingRepository _troubleshootingRepo =
      TroubleshootingRepository();
  final CustomerRepository _customerRepo = CustomerRepository();
  final FlockRepository _flockRepo = FlockRepository();
  final GoveeCaptureRepository _goveeCaptureRepo;

  DashboardProvider({GoveeCaptureRepository? goveeCaptureRepository})
    : _goveeCaptureRepo = goveeCaptureRepository ?? GoveeCaptureRepository();

  String? _selectedCustomerId;
  String? _selectedFlockId;
  int? _selectedBmkAge;
  String _selectedBreakoutType = 'residue';
  bool _isInitialized = false;

  List<CustomerModel> _customers = [];
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

  List<EggStorageTrend> _eggStorageTrend = [];
  EggStorageEstEvidence? _eggStorageEstEvidence;
  List<String> _uvPhotos = [];

  List<SetterComparison> _setterComparisons = [];
  List<HatcherComparison> _hatcherComparisons = [];

  BmkReference? _bmkReference;
  UserModel? _currentUser;

  // Visit-session aggregation state (US6)
  List<VisitSessionSummary> _visitSessions = [];
  VisitSessionSummary? _selectedVisitSession;
  List<GoveeCaptureSummary> _goveeCaptures = [];
  bool _isLoadingGoveeCaptures = false;

  String? get selectedCustomerId => _selectedCustomerId;
  String? get selectedFlockId => _selectedFlockId;
  int? get selectedBmkAge => _selectedBmkAge;
  String get selectedBreakoutType => _selectedBreakoutType;
  bool get hasActiveFilters =>
      (canUseAllCustomers && _selectedCustomerId != null) ||
      _selectedFlockId != null ||
      _selectedBmkAge != null;

  int get activeFilterCount {
    var count = 0;
    if (canUseAllCustomers && _selectedCustomerId != null) count++;
    if (_selectedFlockId != null) count++;
    if (_selectedBmkAge != null) count++;
    return count;
  }

  List<CustomerModel> get customers => _customers;
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
  bool get isLoadingGoveeCaptures => _isLoadingGoveeCaptures;
  bool get canUseAllCustomers {
    final user = _currentUser;
    return user == null || !user.isCustomer;
  }

  Future<void> init({UserModel? currentUser}) async {
    if (_isInitialized) {
      // Singleton provider: this runs on every dashboard mount. Refresh the
      // pick list so customers synced since first load — or a different scope
      // after an account switch (auditor → admin) — show up without a restart.
      if (currentUser != null) _currentUser = currentUser;
      // reload() refreshes the pick lists then reloads the sector data.
      await reload();
      return;
    }
    _isInitialized = true;
    _currentUser = currentUser;
    _isLoading = true;
    notifyListeners();

    try {
      // reload() refreshes the pick lists, then loads the sector data. init
      // owns the full-screen spinner, so it runs without flipping the flag.
      await reload(showLoading: false);
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// (Re)load the customer + flock + bmk-age pick lists from local storage.
  /// **Pure**: refreshes list state only — it never triggers a sector-data
  /// reload, so [reload] can call it without re-entering itself. Callers that
  /// also want fresh sector data call [reload] (which calls this first).
  Future<void> _refreshPickLists() async {
    _customers = _scopeCustomers(await _customerRepo.getAllCustomers());
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
    await _refreshFlocks();
  }

  /// (Re)load the flock pick list for the current customer plus its bmk ages.
  /// **Pure**: list state only, no sector-data reload. Mutators that change the
  /// customer/flock set call this then [reload] explicitly.
  Future<void> _refreshFlocks() async {
    final flocks = _selectedCustomerId == null
        ? await _flockRepo.getAllFlocks()
        : await _flockRepo.getFlocksByCustomer(_selectedCustomerId!);
    _flocks = _scopeFlocks(flocks);
    if (_selectedFlockId != null &&
        !_flocks.any((flock) => flock.id == _selectedFlockId)) {
      _selectedFlockId = null;
    }
    await _loadBmkAges();
  }

  Future<void> _loadBmkAges() async {
    _availableBmkAges = await _panelDashboardRepo.getDistinctBmkAges(
      customerId: _selectedCustomerId,
      flockId: _selectedFlockId,
    );
    if (!_availableBmkAges.contains(_selectedBmkAge)) {
      _selectedBmkAge = null;
    }
    notifyListeners();
  }

  Future<void> setCustomer(String? customerId) async {
    _selectedCustomerId = canUseAllCustomers
        ? customerId
        : _currentUser?.customerId;
    _selectedFlockId = null;
    _selectedBmkAge = null;
    await _refreshFlocks();
    await reload();
  }

  Future<void> setFlock(String? flockId) async {
    _selectedFlockId = flockId;
    _selectedBmkAge = null;
    await _loadBmkAges();
    await reload();
  }

  void setBmkAge(int? age) {
    _selectedBmkAge = age;
    reload();
  }

  Future<void> clearFilters() async {
    _selectedCustomerId = canUseAllCustomers ? null : _currentUser?.customerId;
    _selectedFlockId = null;
    _selectedBmkAge = null;
    _selectedBreakoutType = 'residue';
    _selectedSetterIds.clear();
    _selectedHatcherIds.clear();
    _flocks = [];
    await _refreshFlocks();
    await reload();
  }

  void setBreakoutType(String type) {
    _selectedBreakoutType = type;
    reload();
  }

  Future<void> selectVisitSession(VisitSessionSummary session) async {
    _selectedVisitSession = session;
    _isLoadingGoveeCaptures = true;
    notifyListeners();
    await _loadGoveeCapturesForVisit(session);
    _isLoadingGoveeCaptures = false;
    notifyListeners();
  }

  void toggleSetter(String setterId) {
    if (_selectedSetterIds.contains(setterId)) {
      _selectedSetterIds.remove(setterId);
    } else {
      _selectedSetterIds.add(setterId);
    }
    reload();
  }

  void toggleHatcher(String hatcherId) {
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

  Future<void> reload({bool showLoading = true}) async {
    if (showLoading) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      // Refresh the pick lists first so customers/flocks synced since the last
      // load appear in the filter (pull-to-refresh after a Sync Now).
      await _refreshPickLists();

      final filter = DashboardFilter(
        customerId: _selectedCustomerId,
        flockId: _selectedFlockId,
        bmkAge: _selectedBmkAge,
      );

      _clearHiddenSectorData();
      _isLoadingGoveeCaptures = true;
      final futures = <Future<void>>[
        _loadEggStorage(filter),
        _loadChickQuality(filter),
        _loadSavedGoveeCaptures(filter),
      ];

      await Future.wait(futures);
      _isLoadingGoveeCaptures = false;

      _bmkReference = null;
      if (_selectedBmkAge != null) {
        _bmkReference = await _panelDashboardRepo.getBmkReferenceForAge(
          _selectedBmkAge!,
        );
      }
    } catch (e) {
      debugPrint('Error reloading dashboard: $e');
      _isLoadingGoveeCaptures = false;
    } finally {
      if (showLoading) _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadEggStorage(DashboardFilter filter) async {
    _eggStorageTrend =
        await _panelDashboardRepo.getEggStorageTrend(filter) ?? [];
    _eggStorageEstEvidence = await _panelDashboardRepo
        .getLatestEggStorageEstEvidence(filter);
    _uvPhotos = await _panelDashboardRepo.getPhotoPaths(
      filter,
      'egg_quality',
      'uv_inspection',
    );
  }

  Future<void> _loadChickQuality(DashboardFilter filter) async {
    _chickWeightTrend =
        await _panelDashboardRepo.getChickWeightTrend(filter) ?? [];
    _pasgarAvg = await _panelDashboardRepo.getPasgarAvg(filter);
    _pasgarReferences = await _troubleshootingRepo.getByParameters(const [
      'pasgar_final_score',
      'pasgar_reflexes',
      'pasgar_beak',
      'pasgar_navel',
      'pasgar_belly',
      'pasgar_leg',
      'pasgar_feather_dev',
    ]);
    _cvtAvg = await _panelDashboardRepo.getCvtAvg(filter);
    _yfbmTrend = await _panelDashboardRepo.getYfbmTrend(filter) ?? [];
    _culledChicksAnalysis = await _panelDashboardRepo.getCulledChicksAnalysis(
      filter,
    );
    _cvtPhotos = await _panelDashboardRepo.getPhotoPaths(
      filter,
      'chick_quality',
      'cvt',
    );
    _yfbmPhotos = await _panelDashboardRepo.getPhotoPaths(
      filter,
      'chick_quality',
      'yfbm',
    );
  }

  Future<void> _loadSavedGoveeCaptures(DashboardFilter filter) async {
    try {
      final captures = await _goveeCaptureRepo.getCapturesForDashboard(
        customerId: filter.customerId,
      );
      final summaries = <GoveeCaptureSummary>[];
      for (final capture in captures) {
        final readings = await _goveeCaptureRepo.getReadingsForCapture(
          capture.id,
        );
        summaries.add(
          GoveeCaptureSummary(capture: capture, readings: readings),
        );
      }
      _goveeCaptures = summaries;
    } catch (e) {
      debugPrint('Error loading saved Govee captures: $e');
      _goveeCaptures = [];
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
    _setterComparisons = [];
    _hatcherComparisons = [];
    _visitSessions = [];
    _selectedVisitSession = null;
    _availableSetterIds.clear();
    _availableHatcherIds.clear();
    _selectedSetterIds.clear();
    _selectedHatcherIds.clear();
  }

  Future<void> _loadGoveeCapturesForVisit(VisitSessionSummary visit) async {
    try {
      final session = visit.session;
      final captures = await _goveeCaptureRepo.getCapturesForDashboard(
        customerId: session.customerId,
        hatcheryId: session.hatcheryId,
        captureDate: _captureDateKey(session.date),
      );
      final summaries = <GoveeCaptureSummary>[];
      for (final capture in captures) {
        final readings = await _goveeCaptureRepo.getReadingsForCapture(
          capture.id,
        );
        summaries.add(
          GoveeCaptureSummary(capture: capture, readings: readings),
        );
      }
      _goveeCaptures = summaries;
    } catch (e) {
      debugPrint('Error loading Govee captures: $e');
      _goveeCaptures = [];
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
