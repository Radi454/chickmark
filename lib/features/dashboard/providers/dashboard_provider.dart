import 'package:flutter/foundation.dart';
import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/data/repositories/customer_repository.dart';
import 'package:hatchaudit/data/repositories/flock_repository.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_filter.dart';
import 'package:hatchaudit/features/dashboard/models/hatch_analysis_models.dart';
import 'package:hatchaudit/features/dashboard/models/egg_breakout_models.dart';
import 'package:hatchaudit/features/dashboard/models/chick_quality_models.dart';
import 'package:hatchaudit/features/dashboard/models/egg_storage_models.dart';

class DashboardProvider extends ChangeNotifier {
  final AuditRepository _auditRepo = AuditRepository();
  final CustomerRepository _customerRepo = CustomerRepository();
  final FlockRepository _flockRepo = FlockRepository();

  String? _selectedCustomerId;
  String? _selectedFlockId;
  int? _selectedBmkAge;
  String _selectedBreakoutType = 'residue';

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

  ChickWeightTrend? _chickWeightTrend;
  PasgarAvg? _pasgarAvg;
  CvtAvg? _cvtAvg;
  List<YfbmTrend> _yfbmTrend = [];
  List<ChaEnvironmentalTrend> _chaTrend = [];
  List<String> _cvtPhotos = [];
  List<String> _yfbmPhotos = [];
  List<String> _chaPhotos = [];

  EggStorageTrend? _eggStorageTrend;
  List<String> _shellTempPhotos = [];
  List<String> _uvPhotos = [];

  List<SetterComparison> _setterComparisons = [];
  List<HatcherComparison> _hatcherComparisons = [];

  BmkReference? _bmkReference;
  UserModel? _currentUser;

  String? get selectedCustomerId => _selectedCustomerId;
  String? get selectedFlockId => _selectedFlockId;
  int? get selectedBmkAge => _selectedBmkAge;
  String get selectedBreakoutType => _selectedBreakoutType;

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

  ChickWeightTrend? get chickWeightTrend => _chickWeightTrend;
  PasgarAvg? get pasgarAvg => _pasgarAvg;
  CvtAvg? get cvtAvg => _cvtAvg;
  List<YfbmTrend> get yfbmTrend => _yfbmTrend;
  List<ChaEnvironmentalTrend> get chaTrend => _chaTrend;
  List<String> get cvtPhotos => _cvtPhotos;
  List<String> get yfbmPhotos => _yfbmPhotos;
  List<String> get chaPhotos => _chaPhotos;

  EggStorageTrend? get eggStorageTrend => _eggStorageTrend;
  List<String> get shellTempPhotos => _shellTempPhotos;
  List<String> get uvPhotos => _uvPhotos;

  List<SetterComparison> get setterComparisons => _setterComparisons;
  List<HatcherComparison> get hatcherComparisons => _hatcherComparisons;

  BmkReference? get bmkReference => _bmkReference;
  bool get canUseAllCustomers {
    final user = _currentUser;
    return user == null || !user.isCustomer;
  }

  Future<void> init({UserModel? currentUser}) async {
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

  void setBreakoutType(String type) {
    _selectedBreakoutType = type;
    reload();
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
    _chickWeightTrend = await _auditRepo.getChickWeightTrend(filter);
    _pasgarAvg = await _auditRepo.getPasgarAvg(filter);
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
    _eggStorageTrend = await _auditRepo.getEggStorageTrend(filter);
    _shellTempPhotos = await _auditRepo.getPhotoPaths(
      filter,
      'egg_storage',
      'shell_temp',
    );
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
