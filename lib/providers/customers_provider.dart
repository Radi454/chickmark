import 'dart:async';

import 'package:flutter/foundation.dart';
import '../data/models/customer_model.dart';
import '../data/models/flock_model.dart';
import '../data/models/hatchery_model.dart';
import '../data/models/audit_model.dart';
import '../data/models/user_model.dart';
import '../data/repositories/activity_log_repository.dart';
import '../data/repositories/audit_session_repository.dart';
import '../data/repositories/customer_repository.dart';
import '../data/repositories/flock_repository.dart';
import '../data/repositories/hatchery_repository.dart';
import '../data/repositories/audit_repository.dart';
import '../data/repositories/bmk_repository.dart';
import '../data/repositories/photo_repository.dart';
import '../data/repositories/temperature_rh_repository.dart';
import '../services/photo/photo_service.dart';
import '../services/supabase/supabase_service.dart';
import '../features/dashboard/models/visit_session_summary.dart';

class CustomersProvider extends ChangeNotifier {
  final CustomerRepository _customerRepository = CustomerRepository();
  final FlockRepository _flockRepository = FlockRepository();
  final HatcheryRepository _hatcheryRepository = HatcheryRepository();
  final ActivityLogRepository _activityLogRepository = ActivityLogRepository();
  final AuditRepository _auditRepository = AuditRepository();
  final AuditSessionRepository _sessionRepository = AuditSessionRepository();
  final BmkRepository _bmkRepository = BmkRepository();
  final PhotoRepository _photoRepository = PhotoRepository();
  final PhotoService _photoService = PhotoService();
  final SupabaseService _supabaseService = SupabaseService();
  final TemperatureRhRepository _tempRepository = TemperatureRhRepository();

  bool _isLoadingCustomers = false;

  // State
  List<CustomerModel> _allCustomers = [];
  String _searchQuery = '';
  final Map<String, int> _flockCounts = {};
  final Set<String> _estimatedFlockCustomerIds = {};
  final Map<String, CustomerModel> _customersById = {};
  final Map<String, FlockModel> _flocksById = {};
  final Map<String, HatcheryModel> _hatcheriesById = {};
  final Map<String, int> _hatcheryCounts = {};
  CustomerModel? _selectedCustomer;
  List<FlockModel> _flocks = [];
  List<HatcheryModel> _hatcheries = [];
  FlockModel? _selectedFlock;
  List<AuditModel> _audits = [];
  bool _isLoading = false;
  UserModel? _currentUser;
  List<VisitSessionSummary> _visitSessions = [];

  // Getters
  List<CustomerModel> get filteredCustomers {
    if (_searchQuery.isEmpty) {
      return _allCustomers;
    }
    return _allCustomers
        .where(
          (customer) =>
              customer.name.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ||
              (customer.location?.toLowerCase().contains(
                    _searchQuery.toLowerCase(),
                  ) ??
                  false) ||
              (customer.phone?.toLowerCase().contains(
                    _searchQuery.toLowerCase(),
                  ) ??
                  false),
        )
        .toList();
  }

  String get searchQuery => _searchQuery;
  Map<String, int> get flockCounts => _flockCounts;
  bool customerHasEstimatedFlockAge(String customerId) =>
      _estimatedFlockCustomerIds.contains(customerId);
  CustomerModel? customerById(String id) => _customersById[id];
  FlockModel? flockById(String? id) => id == null ? null : _flocksById[id];
  HatcheryModel? hatcheryById(String? id) =>
      id == null ? null : _hatcheriesById[id];
  Map<String, int> get hatcheryCounts => _hatcheryCounts;
  CustomerModel? get selectedCustomer => _selectedCustomer;
  List<FlockModel> get flocks => _flocks;
  List<FlockModel> get availableFlocks =>
      _flocks.where((flock) => flock.isAvailableForAudit).toList();
  List<HatcheryModel> get hatcheries => _hatcheries;
  FlockModel? get selectedFlock => _selectedFlock;
  List<AuditModel> get audits => _audits;
  bool get isLoading => _isLoading;
  List<VisitSessionSummary> get visitSessions => _visitSessions;

  List<CustomerModel> get allCustomers => _allCustomers;
  int get customersCount => _allCustomers.length;
  int get totalAuditsCount => _audits.length;
  int get activeAuditsCount =>
      _audits.where((a) => a.status == 'active').length;

  List<AuditModel> get allAudits {
    final result = <AuditModel>[];
    for (final customer in _allCustomers) {
      final audits = _audits.where((a) => a.customerId == customer.id).toList();
      result.addAll(audits);
    }
    return result..sort((a, b) => b.date.compareTo(a.date));
  }

  // Actions
  Future<void> loadCustomers({
    UserModel? currentUser,
    bool syncRemote = false,
  }) async {
    if (_isLoadingCustomers) return;
    _isLoadingCustomers = true;
    if (currentUser != null) _currentUser = currentUser;
    _isLoading = true;
    notifyListeners();

    try {
      if (syncRemote) {
        await _supabaseService.pullFromSupabase(
          upsertCustomer: (row) => _customerRepository.upsertCustomer(row),
          upsertFlock: (row) => _flockRepository.upsertFlock(row),
          upsertHatchery: (row) => _hatcheryRepository.upsertHatchery(row),
          upsertAudit: (row) => _auditRepository.upsertAudit(row),
          upsertPhoto: (row) => _photoRepository.upsertPhoto(row),
          upsertBmkBreed: (row) => _bmkRepository.upsertBmkBreed(row),
          upsertBmkEggBreakout: (row) =>
              _bmkRepository.upsertBmkEggBreakout(row),
          upsertAuditSession: (row) => _sessionRepository.upsertSessionRow(row),
          upsertTemperatureSession: (row) =>
              _tempRepository.upsertSessionRow(row),
        );
      }
      final customers = await _customerRepository.getAllCustomers();
      final audits = await _auditRepository.getAllAudits(limit: 100000);
      final allFlocks = await _flockRepository.getAllFlocks();
      final allHatcheries = await _hatcheryRepository.getAllHatcheries();

      _allCustomers = _scopeCustomers(customers);
      _audits = _scopeAudits(audits);
      final visibleFlocks = _scopeFlocks(allFlocks);
      final visibleHatcheries = _scopeHatcheries(allHatcheries);
      _customersById
        ..clear()
        ..addEntries(_allCustomers.map((c) => MapEntry(c.id, c)));
      _flocksById
        ..clear()
        ..addEntries(visibleFlocks.map((f) => MapEntry(f.id, f)));
      _hatcheriesById
        ..clear()
        ..addEntries(visibleHatcheries.map((h) => MapEntry(h.id, h)));
      _estimatedFlockCustomerIds
        ..clear()
        ..addAll(
          visibleFlocks
              .where((flock) => flock.isAgeEstimated)
              .map((flock) => flock.customerId),
        );

      // Load flock counts for each customer
      _flockCounts.clear();
      _hatcheryCounts.clear();
      for (final customer in _allCustomers) {
        final flocks = visibleFlocks
            .where((flock) => flock.customerId == customer.id)
            .toList();
        _flockCounts[customer.id] = flocks.length;
        _hatcheryCounts[customer.id] = visibleHatcheries
            .where((hatchery) => hatchery.customerId == customer.id)
            .length;
      }
    } catch (e) {
      debugPrint('Error loading customers: $e');
    } finally {
      _isLoadingCustomers = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> addCustomer(CustomerModel customer) async {
    _ensureCanEdit();
    try {
      // Save to SQLite first
      await _customerRepository.insertCustomer(customer);

      // Refresh customers list and flock counts
      await loadCustomers();
    } catch (e) {
      debugPrint('Error adding customer: $e');
      rethrow;
    }
  }

  Future<void> updateCustomer(CustomerModel customer) async {
    _ensureCanEdit();
    try {
      await _customerRepository.updateCustomer(customer);
      if (_selectedCustomer?.id == customer.id) {
        _selectedCustomer = customer;
      }
      await loadCustomers();
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating customer: $e');
      rethrow;
    }
  }

  Future<void> selectCustomer(CustomerModel customer) async {
    _isLoading = true;
    notifyListeners();

    try {
      _selectedCustomer = customer;

      // Load flocks for this customer
      _flocks = await _flockRepository.getFlocksByCustomer(customer.id);
      _hatcheries = await _hatcheryRepository.getHatcheriesByCustomer(
        customer.id,
      );

      // Auto-select first audit-available flock if available.
      final availableFlocks = _flocks
          .where((flock) => flock.isAvailableForAudit)
          .toList();
      _selectedFlock = availableFlocks.isNotEmpty
          ? availableFlocks.first
          : _flocks.isNotEmpty
          ? _flocks.first
          : null;

      // Load audits for this customer, sorted newest-first
      final audits = await _auditRepository.getAuditsByCustomer(
        customer.id,
        limit: 100000,
      );
      _audits = audits..sort((a, b) => b.date.compareTo(a.date));

      // Load visit sessions for this customer (US6)
      await _loadVisitSessions(customer.id);
    } catch (e) {
      debugPrint('Error selecting customer: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadVisitSessions(String customerId) async {
    try {
      final sessions = await _sessionRepository.getSessionsByCustomer(
        customerId,
        limit: 20,
      );
      final summaries = <VisitSessionSummary>[];
      for (final session in sessions) {
        final audits = await _auditRepository.getAuditsBySessionId(session.id);
        summaries.add(
          VisitSessionSummary.fromSession(
            session: session,
            stationAudits: audits,
          ),
        );
      }
      _visitSessions = summaries;
    } catch (e) {
      debugPrint('Error loading customer visit sessions: $e');
      _visitSessions = [];
    }
  }

  Future<void> addFlock(FlockModel flock) async {
    _ensureCanEdit();
    try {
      // Save to SQLite first
      await _flockRepository.insertFlock(flock);

      // Refresh flocks list
      if (_selectedCustomer != null) {
        _flocks = await _flockRepository.getFlocksByCustomer(
          _selectedCustomer!.id,
        );
      }

      // Update flock counts
      await loadCustomers();

      // Auto-select new flock
      final availableFlocks = _flocks
          .where((item) => item.isAvailableForAudit)
          .toList();
      _selectedFlock = flock.isAvailableForAudit
          ? flock
          : availableFlocks.isNotEmpty
          ? availableFlocks.first
          : null;

      notifyListeners();
    } catch (e) {
      debugPrint('Error adding flock: $e');
      rethrow;
    }
  }

  Future<void> addHatchery(HatcheryModel hatchery) async {
    _ensureCanEdit();
    try {
      await _hatcheryRepository.insertHatchery(hatchery);
      if (_selectedCustomer?.id == hatchery.customerId) {
        _hatcheries = await _hatcheryRepository.getHatcheriesByCustomer(
          hatchery.customerId,
        );
      }
      await loadCustomers();
      notifyListeners();
    } catch (e) {
      debugPrint('Error adding hatchery: $e');
      rethrow;
    }
  }

  Future<void> updateHatchery(HatcheryModel hatchery) async {
    _ensureCanEdit();
    try {
      await _hatcheryRepository.updateHatchery(hatchery);
      if (_selectedCustomer?.id == hatchery.customerId) {
        _hatcheries = await _hatcheryRepository.getHatcheriesByCustomer(
          hatchery.customerId,
        );
      }
      await loadCustomers();
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating hatchery: $e');
      rethrow;
    }
  }

  Future<void> deleteHatchery(String hatcheryId) async {
    _ensureCanEdit();
    try {
      await _hatcheryRepository.deleteHatchery(hatcheryId);
      if (_selectedCustomer != null) {
        _hatcheries = await _hatcheryRepository.getHatcheriesByCustomer(
          _selectedCustomer!.id,
        );
      }
      await loadCustomers();
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting hatchery: $e');
      rethrow;
    }
  }

  void selectFlock(FlockModel? flock) {
    _selectedFlock = flock;
    notifyListeners();
  }

  Future<void> updateFlock(FlockModel flock) async {
    _ensureCanEdit();
    try {
      await _flockRepository.updateFlock(flock);
      if (_selectedCustomer != null) {
        _flocks = await _flockRepository.getFlocksByCustomer(
          _selectedCustomer!.id,
        );
      }
      final updatedFlock = _flocks.firstWhere(
        (f) => f.id == flock.id,
        orElse: () => flock,
      );
      final availableFlocks = _flocks
          .where((item) => item.isAvailableForAudit)
          .toList();
      _selectedFlock = updatedFlock.isAvailableForAudit
          ? updatedFlock
          : availableFlocks.isNotEmpty
          ? availableFlocks.first
          : null;
      await loadCustomers();
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating flock: $e');
      rethrow;
    }
  }

  Future<void> deleteFlock(String flockId) async {
    _ensureCanEdit();
    try {
      await _flockRepository.deleteFlock(flockId);
      if (_selectedCustomer != null) {
        _flocks = await _flockRepository.getFlocksByCustomer(
          _selectedCustomer!.id,
        );
      }
      if (_selectedFlock?.id == flockId) {
        _selectedFlock = _flocks.isNotEmpty ? _flocks.first : null;
      }
      await loadCustomers();
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting flock: $e');
      rethrow;
    }
  }

  Future<void> deleteAudit(String auditId) async {
    _ensureCanEdit();
    try {
      await _auditRepository.deleteAudit(auditId);
      _audits.removeWhere((audit) => audit.id == auditId);
      if (_currentUser != null) {
        await _activityLogRepository.log(
          _currentUser!.id,
          'delete',
          entityType: 'audit',
          entityId: auditId,
        );
      }
      unawaited(_supabaseService.syncDeleteAudit(auditId));
      await loadCustomers(currentUser: _currentUser);
    } catch (e) {
      debugPrint('Error deleting audit: $e');
      rethrow;
    }
  }

  Future<void> deleteCustomer(String customerId) async {
    _ensureCanEdit();
    try {
      final audits = (await _auditRepository.getAllAudits(
        limit: 100000,
      )).where((audit) => audit.customerId == customerId).toList();
      for (final audit in audits) {
        final photos = await _photoRepository.getByAuditId(audit.id);
        for (final photo in photos) {
          await _photoService.deletePhoto(photo.filePath);
        }
      }

      await _auditRepository.deleteAuditsByCustomer(customerId);
      await _flockRepository.deleteFlocksByCustomer(customerId);
      await _hatcheryRepository.deleteHatcheriesByCustomer(customerId);
      await _customerRepository.deleteCustomer(customerId);

      if (_selectedCustomer?.id == customerId) {
        _selectedCustomer = null;
        _selectedFlock = null;
        _flocks = [];
        _hatcheries = [];
      }

      await loadCustomers(currentUser: _currentUser);
    } catch (e) {
      debugPrint('Error deleting customer: $e');
      rethrow;
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

  List<HatcheryModel> _scopeHatcheries(List<HatcheryModel> hatcheries) {
    final user = _currentUser;
    if (user == null || !user.isCustomer) return hatcheries;
    final customerId = user.customerId;
    if (customerId == null || customerId.isEmpty) return [];
    return hatcheries
        .where((hatchery) => hatchery.customerId == customerId)
        .toList();
  }

  List<AuditModel> _scopeAudits(List<AuditModel> audits) {
    final user = _currentUser;
    if (user == null || !user.isCustomer) return audits;
    final customerId = user.customerId;
    if (customerId == null || customerId.isEmpty) return [];
    return audits.where((audit) => audit.customerId == customerId).toList();
  }

  void _ensureCanEdit() {
    final user = _currentUser;
    if (user != null && !user.canEditAudits) {
      throw StateError('This account has read-only access.');
    }
  }
}
