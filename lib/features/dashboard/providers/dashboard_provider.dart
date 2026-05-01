import 'package:flutter/foundation.dart';
import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'package:hatchaudit/data/repositories/customer_repository.dart';
import 'package:hatchaudit/data/repositories/flock_repository.dart';
import 'package:hatchaudit/data/repositories/temperature_rh_repository.dart';
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
import 'package:hatchaudit/features/dashboard/models/visit_session_summary.dart';

class DashboardProvider extends ChangeNotifier {
  final AuditRepository _auditRepo = AuditRepository();
  final AuditSessionRepository _sessionRepo = AuditSessionRepository();
  final CustomerRepository _customerRepo = CustomerRepository();
  final FlockRepository _flockRepo = FlockRepository();
  final TemperatureRhRepository _tempRepo = TemperatureRhRepository();
  final TroubleshootingRepository _troubleshootingRepo =
      TroubleshootingRepository();

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
  List<ChaEnvironmentalTrend> _chaTrend = [];
  List<String> _cvtPhotos = [];
  List<String> _yfbmPhotos = [];
  List<String> _chaPhotos = [];

  List<EggStorageTrend> _eggStorageTrend = [];
  EggStorageEstEvidence? _eggStorageEstEvidence;
  List<String> _shellTempPhotos = [];
  List<String> _uvPhotos = [];

  List<SetterComparison> _setterComparisons = [];
  List<HatcherComparison> _hatcherComparisons = [];

  BmkReference? _bmkReference;
  UserModel? _currentUser;

  // Visit-session aggregation state (US6)
  List<VisitSessionSummary> _visitSessions = [];
  VisitSessionSummary? _selectedVisitSession;

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
  List<ChaEnvironmentalTrend> get chaTrend => _chaTrend;
  List<String> get cvtPhotos => _cvtPhotos;
  List<String> get yfbmPhotos => _yfbmPhotos;
  List<String> get chaPhotos => _chaPhotos;

  List<EggStorageTrend> get eggStorageTrend => _eggStorageTrend;
  EggStorageTrend? get eggStorageLatest =>
      _eggStorageTrend.isNotEmpty ? _eggStorageTrend.last : null;
  EggStorageEstEvidence? get eggStorageEstEvidence => _eggStorageEstEvidence;
  List<String> get shellTempPhotos => _shellTempPhotos;
  List<String> get uvPhotos => _uvPhotos;

  List<SetterComparison> get setterComparisons => _setterComparisons;
  List<HatcherComparison> get hatcherComparisons => _hatcherComparisons;

  BmkReference? get bmkReference => _bmkReference;

  // Visit-session aggregation getters (US6)
  List<VisitSessionSummary> get visitSessions => _visitSessions;
  VisitSessionSummary? get selectedVisitSession => _selectedVisitSession;
  bool get canUseAllCustomers {
    final user = _currentUser;
    return user == null || !user.isCustomer;
  }

  Future<void> init({UserModel? currentUser}) async {
    if (_isInitialized) {
      if (currentUser != null && currentUser != _currentUser) {
        _currentUser = currentUser;
      }
      return;
    }
    _isInitialized = true;
    _currentUser = currentUser;
    _isLoading = true;
    notifyListeners();

    try {
      _customers = _scopeCustomers(await _customerRepo.getAllCustomers());
      if (!canUseAllCustomers && _customers.isNotEmpty) {
        _selectedCustomerId = _customers.first.id;
      }
      await _loadFlocks();
    } catch (e) {
      debugPrint('Error loading customers: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadFlocks() async {
    final flocks = _selectedCustomerId == null
        ? await _flockRepo.getAllFlocks()
        : await _flockRepo.getFlocksByCustomer(_selectedCustomerId!);
    _flocks = _scopeFlocks(flocks);
    if (_selectedFlockId != null &&
        !_flocks.any((flock) => flock.id == _selectedFlockId)) {
      _selectedFlockId = null;
    }
    await _loadEquipmentIds();
    await _loadBmkAges();
    await reload();
    notifyListeners();
  }

  Future<void> _loadBmkAges() async {
    _availableBmkAges = await _auditRepo.getDistinctBmkAges(
      customerId: _selectedCustomerId,
      flockId: _selectedFlockId,
    );
    if (!_availableBmkAges.contains(_selectedBmkAge)) {
      _selectedBmkAge = null;
    }
    notifyListeners();
  }

  Future<void> _loadEquipmentIds() async {
    final setters = await _auditRepo.getDistinctSetterIds(
      customerId: _selectedCustomerId,
      flockId: _selectedFlockId,
    );
    final hatchers = await _auditRepo.getDistinctHatcherIds(
      customerId: _selectedCustomerId,
      flockId: _selectedFlockId,
    );
    _availableSetterIds
      ..clear()
      ..addAll(setters);
    _availableHatcherIds
      ..clear()
      ..addAll(hatchers);
    _selectedSetterIds
      ..clear()
      ..addAll(setters);
    _selectedHatcherIds
      ..clear()
      ..addAll(hatchers);
  }

  Future<void> setCustomer(String? customerId) async {
    _selectedCustomerId = canUseAllCustomers
        ? customerId
        : _currentUser?.customerId;
    _selectedFlockId = null;
    _selectedBmkAge = null;
    await _loadFlocks();
  }

  Future<void> setFlock(String? flockId) async {
    _selectedFlockId = flockId;
    _selectedBmkAge = null;
    await _loadEquipmentIds();
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
    await _loadFlocks();
  }

  void setBreakoutType(String type) {
    _selectedBreakoutType = type;
    reload();
  }

  void selectVisitSession(VisitSessionSummary session) {
    _selectedVisitSession = session;
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

  Future<void> reload() async {
    _isLoading = true;
    notifyListeners();

    try {
      final filter = DashboardFilter(
        customerId: _selectedCustomerId,
        flockId: _selectedFlockId,
        bmkAge: _selectedBmkAge,
      );

      final futures = <Future<void>>[
        _loadHatchAnalysis(filter),
        _loadEggBreakout(filter),
        _loadChickQuality(filter),
        _loadEggStorage(filter),
        _loadSetterComparison(filter),
        _loadHatcherComparison(filter),
        _loadVisitSessions(filter),
      ];

      await Future.wait(futures);

      _bmkReference = null;
      if (_selectedBmkAge != null) {
        _bmkReference = await _auditRepo.getBmkReferenceForAge(
          _selectedBmkAge!,
        );
      }
    } catch (e) {
      debugPrint('Error reloading dashboard: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadHatchAnalysis(DashboardFilter filter) async {
    _hatchAnalysisAvg = await _auditRepo.getHatchAnalysisAvg(filter);
    _hatchAnalysisTrend = await _auditRepo.getHatchAnalysisTrend(filter) ?? [];
  }

  Future<void> _loadEggBreakout(DashboardFilter filter) async {
    _eggBreakoutAvg = await _auditRepo.getEggBreakoutAvg(
      filter,
      _selectedBreakoutType,
    );
    _eggBreakoutTrend =
        await _auditRepo.getEggBreakoutTrend(filter, _selectedBreakoutType) ??
        [];
    _eggBreakoutPhotos = await _auditRepo.getPhotoPaths(
      filter,
      'hatch_analysis',
      'egg_breakout',
    );
  }

  Future<void> _loadChickQuality(DashboardFilter filter) async {
    _chickWeightTrend = await _auditRepo.getChickWeightTrend(filter) ?? [];
    _pasgarAvg = await _auditRepo.getPasgarAvg(filter);
    _pasgarReferences = await _troubleshootingRepo.getByParameters([
      'pasgar_final_score',
      'pasgar_reflexes',
      'pasgar_beak',
      'pasgar_navel',
      'pasgar_belly',
      'pasgar_leg',
      'pasgar_feather_dev',
    ]);
    _cvtAvg = await _auditRepo.getCvtAvg(filter);
    _yfbmTrend = await _auditRepo.getYfbmTrend(filter) ?? [];
    _chaTrend = await _auditRepo.getChaEnvironmentalTrend(filter) ?? [];
    _cvtPhotos = await _auditRepo.getPhotoPaths(filter, 'chick_quality', 'cvt');
    _yfbmPhotos = await _auditRepo.getPhotoPaths(
      filter,
      'chick_quality',
      'yfbm',
    );
    _chaPhotos = await _auditRepo.getPhotoPaths(
      filter,
      'chick_quality',
      'cha_env',
    );
  }

  Future<void> _loadEggStorage(DashboardFilter filter) async {
    _eggStorageTrend = await _auditRepo.getEggStorageTrend(filter) ?? [];
    _eggStorageEstEvidence = await _auditRepo.getLatestEggStorageEstEvidence(
      filter,
    );
    _shellTempPhotos = await _auditRepo.getEggStorageEstPhotoPaths(filter);
    _uvPhotos = await _auditRepo.getPhotoPaths(
      filter,
      'egg_storage',
      'uv_inspection',
    );
  }

  Future<void> _loadSetterComparison(DashboardFilter filter) async {
    if (_selectedSetterIds.isEmpty) {
      _setterComparisons = [];
      return;
    }
    _setterComparisons =
        await _auditRepo.getSetterComparisons(
          filter,
          _selectedSetterIds.toList(),
        ) ??
        [];
  }

  Future<void> _loadHatcherComparison(DashboardFilter filter) async {
    if (_selectedHatcherIds.isEmpty) {
      _hatcherComparisons = [];
      return;
    }
    _hatcherComparisons =
        await _auditRepo.getHatcherComparisons(
          filter,
          _selectedHatcherIds.toList(),
        ) ??
        [];
  }

  Future<void> _loadVisitSessions(DashboardFilter filter) async {
    try {
      final sessions = await _sessionRepo.getCompletedSessions(
        customerId: filter.customerId,
        limit: 20,
      );
      final summaries = <VisitSessionSummary>[];
      for (final session in sessions) {
        final audits = await _auditRepo.getAuditsBySessionId(session.id);
        final temps = await _tempRepo.getCompletedSummariesByAuditSession(
          session.id,
        );
        summaries.add(
          VisitSessionSummary.fromSession(
            session: session,
            stationAudits: audits,
            temperatureSummaries: temps,
          ),
        );
      }
      _visitSessions = summaries;
      _selectedVisitSession = summaries.isNotEmpty ? summaries.first : null;
    } catch (e) {
      debugPrint('Error loading visit sessions: $e');
      _visitSessions = [];
      _selectedVisitSession = null;
    }
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
