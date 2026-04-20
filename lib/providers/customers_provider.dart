import 'package:flutter/foundation.dart';
import '../data/models/customer_model.dart';
import '../data/models/flock_model.dart';
import '../data/models/audit_model.dart';
import '../data/models/user_model.dart';
import '../data/repositories/customer_repository.dart';
import '../data/repositories/flock_repository.dart';
import '../data/repositories/audit_repository.dart';
import '../data/repositories/bmk_repository.dart';
import '../data/repositories/photo_repository.dart';
import '../services/supabase/supabase_service.dart';

class CustomersProvider extends ChangeNotifier {
  final CustomerRepository _customerRepository = CustomerRepository();
  final FlockRepository _flockRepository = FlockRepository();
  final AuditRepository _auditRepository = AuditRepository();
  final BmkRepository _bmkRepository = BmkRepository();
  final PhotoRepository _photoRepository = PhotoRepository();
  final SupabaseService _supabaseService = SupabaseService();

  // State
  List<CustomerModel> _allCustomers = [];
  String _searchQuery = '';
  final Map<String, int> _flockCounts = {};
  final Map<String, CustomerModel> _customersById = {};
  final Map<String, FlockModel> _flocksById = {};
  CustomerModel? _selectedCustomer;
  List<FlockModel> _flocks = [];
  FlockModel? _selectedFlock;
  List<AuditModel> _audits = [];
  bool _isLoading = false;
  UserModel? _currentUser;

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
  CustomerModel? customerById(String id) => _customersById[id];
  FlockModel? flockById(String? id) => id == null ? null : _flocksById[id];
  CustomerModel? get selectedCustomer => _selectedCustomer;
  List<FlockModel> get flocks => _flocks;
  FlockModel? get selectedFlock => _selectedFlock;
  List<AuditModel> get audits => _audits;
  bool get isLoading => _isLoading;

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
  Future<void> loadCustomers({UserModel? currentUser}) async {
    if (currentUser != null) _currentUser = currentUser;
    _isLoading = true;
    notifyListeners();

    try {
      await _supabaseService.pullFromSupabase(
        upsertCustomer: (row) => _customerRepository.upsertCustomer(row),
        upsertFlock: (row) => _flockRepository.upsertFlock(row),
        upsertAudit: (row) => _auditRepository.upsertAudit(row),
        upsertPhoto: (row) => _photoRepository.upsertPhoto(row),
        upsertBmkBreed: (row) => _bmkRepository.upsertBmkBreed(row),
        upsertBmkEggBreakout: (row) => _bmkRepository.upsertBmkEggBreakout(row),
      );
      final customers = await _customerRepository.getAllCustomers();
      final audits = await _auditRepository.getAllAudits();
      final allFlocks = await _flockRepository.getAllFlocks();

      _allCustomers = _scopeCustomers(customers);
      _audits = _scopeAudits(audits);
      final visibleFlocks = _scopeFlocks(allFlocks);
      _customersById
        ..clear()
        ..addEntries(_allCustomers.map((c) => MapEntry(c.id, c)));
      _flocksById
        ..clear()
        ..addEntries(visibleFlocks.map((f) => MapEntry(f.id, f)));

      // Load flock counts for each customer
      _flockCounts.clear();
      for (final customer in _allCustomers) {
        final flocks = await _flockRepository.getFlocksByCustomer(customer.id);
        _flockCounts[customer.id] = flocks.length;
      }
    } catch (e) {
      debugPrint('Error loading customers: $e');
    } finally {
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

      // Fire-and-forget Supabase sync
      try {
        _supabaseService.syncCustomer(customer.toMap());
      } catch (_) {
        // Silent failure - per Constitution IX
      }
    } catch (e) {
      debugPrint('Error adding customer: $e');
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

      // Auto-select first flock if available
      _selectedFlock = _flocks.isNotEmpty ? _flocks.first : null;

      // Load audits for this customer, sorted newest-first
      final audits = await _auditRepository.getAuditsByCustomer(customer.id);
      _audits = audits..sort((a, b) => b.date.compareTo(a.date));
    } catch (e) {
      debugPrint('Error selecting customer: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
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
      _selectedFlock = flock;

      // Fire-and-forget Supabase sync
      try {
        _supabaseService.syncFlock(flock.toMap());
      } catch (_) {
        // Silent failure - per Constitution IX
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error adding flock: $e');
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
      _selectedFlock = _flocks.firstWhere(
        (f) => f.id == flock.id,
        orElse: () => flock,
      );
      await loadCustomers();
      try {
        _supabaseService.syncUpdateFlock(flock.toMap());
      } catch (_) {}
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
      try {
        _supabaseService.syncDeleteFlock(flockId);
      } catch (_) {}
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting flock: $e');
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
