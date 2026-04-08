import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/customer.dart';
import '../models/flock.dart';
import '../models/audit_session.dart';
import '../models/chick_quality.dart';
import '../models/egg_breakout.dart';
import '../models/setter_measurements.dart';
import '../models/hatcher_measurements.dart';
import '../models/vaccine_storage.dart';
import '../models/egg_storage.dart';
import '../models/hatchery_results.dart';

class AppProvider extends ChangeNotifier {
  // ── Private fields ────────────────────────────────────────────────────────
  final DatabaseHelper _db = DatabaseHelper();
  final Uuid _uuid = const Uuid();

  List<Customer> _customers = [];
  List<Flock> _flocks = [];
  List<AuditSession> _auditSessions = [];

  Customer? _currentCustomer;
  Flock? _currentFlock;
  AuditSession? _currentSession;

  ChickQuality? _chickQuality;
  EggBreakout? _eggBreakout;
  SetterMeasurements? _setterMeasurements;
  HatcherMeasurements? _hatcherMeasurements;
  VaccineStorage? _vaccineStorage;
  EggStorage? _eggStorage;
  HatcheryResults? _hatcheryResults;

  bool _isLoading = false;

  // ── Getters ───────────────────────────────────────────────────────────────

  List<Customer> get customers => List.unmodifiable(_customers);
  List<Flock> get flocks => List.unmodifiable(_flocks);
  List<AuditSession> get auditSessions => List.unmodifiable(_auditSessions);

  Customer? get currentCustomer => _currentCustomer;
  Flock? get currentFlock => _currentFlock;
  AuditSession? get currentSession => _currentSession;

  ChickQuality? get chickQuality => _chickQuality;
  EggBreakout? get eggBreakout => _eggBreakout;
  SetterMeasurements? get setterMeasurements => _setterMeasurements;
  HatcherMeasurements? get hatcherMeasurements => _hatcherMeasurements;
  VaccineStorage? get vaccineStorage => _vaccineStorage;
  EggStorage? get eggStorage => _eggStorage;
  HatcheryResults? get hatcheryResults => _hatcheryResults;

  bool get isLoading => _isLoading;

  DatabaseHelper get db => _db;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Call once at app startup (e.g. in main.dart before runApp).
  Future<void> initialize() async {
    _isLoading = true;
    try {
      await _db.seedDefaultBenchmarks();
      _customers = await _db.getCustomers();
      _auditSessions = await _db.getAuditSessions();
    } finally {
      _isLoading = false;
    }
  }

  // ── Customers ─────────────────────────────────────────────────────────────

  Future<void> loadCustomers() async {
    _customers = await _db.getCustomers();
    notifyListeners();
  }

  /// Creates and persists a new [Customer]. Returns the created instance.
  Future<Customer> createCustomer(
    String name, {
    String? email,
    String? phone,
    String? address,
  }) async {
    final customer = Customer(
      id: _uuid.v4(),
      name: name,
      email: email,
      phone: phone,
      address: address,
      createdAt: DateTime.now(),
    );
    await _db.insertCustomer(customer);
    _customers = [..._customers, customer]
      ..sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
    return customer;
  }

  Future<void> updateCustomer(Customer customer) async {
    await _db.updateCustomer(customer);
    final idx = _customers.indexWhere((c) => c.id == customer.id);
    if (idx != -1) {
      _customers = List.of(_customers)..[idx] = customer;
      _customers.sort((a, b) => a.name.compareTo(b.name));
    }
    if (_currentCustomer?.id == customer.id) _currentCustomer = customer;
    notifyListeners();
  }

  // ── Flocks ────────────────────────────────────────────────────────────────

  Future<void> loadFlocks(String customerId) async {
    _flocks = await _db.getFlocksByCustomer(customerId);
    notifyListeners();
  }

  /// Creates and persists a new [Flock]. Returns the created instance.
  Future<Flock> createFlock(
    String customerId,
    String flockCode,
    String breed,
    DateTime entryDate,
  ) async {
    final flock = Flock(
      id: _uuid.v4(),
      customerId: customerId,
      flockCode: flockCode,
      breed: breed,
      entryDate: entryDate,
      status: 'active',
      createdAt: DateTime.now(),
    );
    await _db.insertFlock(flock);
    _flocks = [flock, ..._flocks];
    notifyListeners();
    return flock;
  }

  Future<void> updateFlock(Flock flock) async {
    await _db.updateFlock(flock);
    final idx = _flocks.indexWhere((f) => f.id == flock.id);
    if (idx != -1) {
      _flocks = List.of(_flocks)..[idx] = flock;
    }
    if (_currentFlock?.id == flock.id) _currentFlock = flock;
    notifyListeners();
  }

  Future<void> markFlockAsSold(String flockId) async {
    final idx = _flocks.indexWhere((f) => f.id == flockId);
    if (idx == -1) return;
    final flock = _flocks[idx];
    flock.status = 'sold';
    await _db.updateFlock(flock);
    _flocks = List.of(_flocks)..[idx] = flock;
    if (_currentFlock?.id == flockId) _currentFlock = flock;
    notifyListeners();
  }

  // ── Audit Sessions ────────────────────────────────────────────────────────

  Future<void> loadAuditSessions({String? flockId}) async {
    if (flockId != null) {
      _auditSessions = await _db.getAuditSessionsByFlock(flockId);
    } else {
      _auditSessions = await _db.getAuditSessions();
    }
    notifyListeners();
  }

  /// Creates a new [AuditSession] for the given customer and flock, sets it
  /// as the current session, and clears all tab data.
  Future<AuditSession> startNewAudit(Customer customer, Flock flock) async {
    _currentCustomer = customer;
    _currentFlock = flock;

    final session = AuditSession(
      id: _uuid.v4(),
      customerId: customer.id,
      flockId: flock.id,
      breed: flock.breed,
      flockAgeWeeks: flock.currentAgeWeeks,
      eggProductionAgeWeeks: flock.eggProductionAgeWeeks,
      auditDate: DateTime.now(),
      benchmarkSet: flock.breed,
      isCompleted: false,
      createdAt: DateTime.now(),
    );

    await _db.insertAuditSession(session);
    _currentSession = session;
    _auditSessions = [session, ..._auditSessions];

    // Clear all tab data for a fresh session
    _chickQuality = null;
    _eggBreakout = null;
    _setterMeasurements = null;
    _hatcherMeasurements = null;
    _vaccineStorage = null;
    _eggStorage = null;
    _hatcheryResults = null;

    notifyListeners();
    return session;
  }

  /// Loads an existing session as the current session, fetching all tab data.
  Future<void> setCurrentSession(AuditSession session) async {
    _currentSession = session;
    _setLoading(true);
    try {
      // Resolve customer — search cached list first, reload from DB if absent
      _currentCustomer = _customers.cast<Customer?>().firstWhere(
            (c) => c?.id == session.customerId,
            orElse: () => null,
          );
      if (_currentCustomer == null) {
        await loadCustomers();
        _currentCustomer = _customers.cast<Customer?>().firstWhere(
              (c) => c?.id == session.customerId,
              orElse: () => null,
            );
      }

      // Resolve flock — load for this customer then find by id
      final flocks = await _db.getFlocksByCustomer(session.customerId);
      _currentFlock = flocks.cast<Flock?>().firstWhere(
            (f) => f?.id == session.flockId,
            orElse: () => null,
          );

      final results = await Future.wait([
        _db.getChickQualityBySession(session.id),
        _db.getEggBreakoutBySession(session.id),
        _db.getSetterMeasurementsBySession(session.id),
        _db.getHatcherMeasurementsBySession(session.id),
        _db.getVaccineStorageBySession(session.id),
        _db.getEggStorageBySession(session.id),
        _db.getHatcheryResultsBySession(session.id),
      ]);
      _chickQuality        = results[0] as ChickQuality?;
      _eggBreakout         = results[1] as EggBreakout?;
      _setterMeasurements  = results[2] as SetterMeasurements?;
      _hatcherMeasurements = results[3] as HatcherMeasurements?;
      _vaccineStorage      = results[4] as VaccineStorage?;
      _eggStorage          = results[5] as EggStorage?;
      _hatcheryResults     = results[6] as HatcheryResults?;
    } finally {
      _setLoading(false);
    }
  }

  /// Clears the current session and all tab data, returning the UI to the
  /// no-session (picker) state. Refreshes the recent-audits list.
  Future<void> clearCurrentSession() async {
    _currentSession = null;
    _currentCustomer = null;
    _currentFlock = null;
    _chickQuality = null;
    _eggBreakout = null;
    _setterMeasurements = null;
    _hatcherMeasurements = null;
    _vaccineStorage = null;
    _eggStorage = null;
    _hatcheryResults = null;
    await loadAuditSessions();
  }

  // ── Tab saves ─────────────────────────────────────────────────────────────

  Future<void> saveChickQuality(ChickQuality cq) async {
    if (_chickQuality == null) {
      await _db.insertChickQuality(cq);
    } else {
      await _db.updateChickQuality(cq);
    }
    _chickQuality = cq;
    _markSectionIfCompleted('chick_quality', cq.isCompleted);
    notifyListeners();
  }

  Future<void> saveEggBreakout(EggBreakout eb) async {
    if (_eggBreakout == null) {
      await _db.insertEggBreakout(eb);
    } else {
      await _db.updateEggBreakout(eb);
    }
    _eggBreakout = eb;
    _markSectionIfCompleted('egg_breakout', eb.isCompleted);
    notifyListeners();
  }

  Future<void> saveSetterMeasurements(SetterMeasurements sm) async {
    if (_setterMeasurements == null) {
      await _db.insertSetterMeasurements(sm);
    } else {
      await _db.updateSetterMeasurements(sm);
    }
    _setterMeasurements = sm;
    _markSectionIfCompleted('setter_measurements', sm.isCompleted);
    notifyListeners();
  }

  Future<void> saveHatcherMeasurements(HatcherMeasurements hm) async {
    if (_hatcherMeasurements == null) {
      await _db.insertHatcherMeasurements(hm);
    } else {
      await _db.updateHatcherMeasurements(hm);
    }
    _hatcherMeasurements = hm;
    _markSectionIfCompleted('hatcher_measurements', hm.isCompleted);
    notifyListeners();
  }

  Future<void> saveVaccineStorage(VaccineStorage vs) async {
    if (_vaccineStorage == null) {
      await _db.insertVaccineStorage(vs);
    } else {
      await _db.updateVaccineStorage(vs);
    }
    _vaccineStorage = vs;
    _markSectionIfCompleted('vaccine_storage', vs.isCompleted);
    notifyListeners();
  }

  Future<void> saveEggStorage(EggStorage es) async {
    if (_eggStorage == null) {
      await _db.insertEggStorage(es);
    } else {
      await _db.updateEggStorage(es);
    }
    _eggStorage = es;
    _markSectionIfCompleted('egg_storage', es.isCompleted);
    notifyListeners();
  }

  Future<void> saveHatcheryResults(HatcheryResults hr) async {
    if (_hatcheryResults == null) {
      await _db.insertHatcheryResults(hr);
    } else {
      await _db.updateHatcheryResults(hr);
    }
    _hatcheryResults = hr;
    _markSectionIfCompleted('hatchery_results', hr.isCompleted);
    notifyListeners();
  }

  // ── Benchmarks ────────────────────────────────────────────────────────────

  /// Returns the benchmark value for [parameter] at the closest age bracket
  /// at or below [flockAgeWeeks] for the given [breed]. Returns null if not
  /// found.
  Future<double?> getBenchmark(
    String breed,
    double flockAgeWeeks,
    String parameter,
  ) {
    return _db.getBenchmark(breed, flockAgeWeeks, parameter);
  }

  // ── Flock history ─────────────────────────────────────────────────────────

  /// Returns all audit sessions for a specific flock, ordered newest first.
  Future<List<AuditSession>> getFlockAudits(String flockId) {
    return _db.getAuditSessionsByFlock(flockId);
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  /// Updates the current session's completed-sections list and persists it.
  void _markSectionIfCompleted(String sectionKey, bool isCompleted) {
    final session = _currentSession;
    if (session == null) return;
    if (isCompleted) {
      session.markSectionCompleted(sectionKey);
    } else {
      session.markSectionIncomplete(sectionKey);
    }
    // Persist the updated session asynchronously; ignore result.
    _db.updateAuditSession(session);
    // Update list cache
    final idx = _auditSessions.indexWhere((s) => s.id == session.id);
    if (idx != -1) {
      _auditSessions = List.of(_auditSessions)..[idx] = session;
    }
  }
}
