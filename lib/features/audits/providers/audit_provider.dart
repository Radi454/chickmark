import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/audit_repository.dart';
import '../../../providers/app_provider.dart';
import '../../../services/supabase/supabase_service.dart';
import 'package:uuid/uuid.dart';

class AuditContext {
  final String auditType;
  final String customerId;
  final String? flockId;
  final String? breed;
  final String date;

  AuditContext({
    required this.auditType,
    required this.customerId,
    this.flockId,
    this.breed,
    required this.date,
  });
}

class AuditProvider extends ChangeNotifier {
  final AuditRepository _repository = AuditRepository();
  final SupabaseService _supabaseService = SupabaseService();
  final Uuid _uuid = const Uuid();

  // State
  AuditContext? _context;
  List<AuditModel> _drafts = [];
  int _activeHatchIndex = 0;
  final Map<int, Set<int>> _savedTabs = {}; // hatchIndex -> saved tab indices
  TempUnit _tempUnit = TempUnit.fahrenheit;
  bool _isReadOnly = false;
  bool _isLoading = false;
  UserModel? _currentUser;

  // Getters
  AuditContext? get context => _context;
  List<AuditModel> get drafts => List.unmodifiable(_drafts);
  int get activeHatchIndex => _activeHatchIndex;
  AuditModel get activeDraft => _drafts[_activeHatchIndex];
  bool isTabSaved(int tabIndex) =>
      _savedTabs[_activeHatchIndex]?.contains(tabIndex) ?? false;
  TempUnit get tempUnit => _tempUnit;
  bool get isReadOnly => _isReadOnly;
  bool get isLoading => _isLoading;
  int get hatchCount => _drafts.length;

  // Initialize new audit session
  void initialize(
    AuditContext context, {
    AuditModel? existingAudit,
    bool notify = true,
    UserModel? currentUser,
  }) {
    _context = context;
    _currentUser = currentUser;
    _tempUnit = TempUnit.fahrenheit;

    if (existingAudit != null) {
      _drafts = [existingAudit];
      _activeHatchIndex = 0;
      _isReadOnly = true;
    } else {
      _drafts = [_createNewDraft(hatchNumber: 1)];
      _activeHatchIndex = 0;
      _isReadOnly = false;
    }

    _savedTabs.clear();
    if (notify) notifyListeners();
  }

  // Create a new draft audit
  AuditModel _createNewDraft({required int hatchNumber}) {
    final now = DateTime.now();
    return AuditModel(
      id: _uuid.v4(),
      auditType: _context!.auditType,
      customerId: _context!.customerId,
      flockId: _context!.flockId,
      date: DateTime.parse(_context!.date),
      hatchNumber: hatchNumber,
      status: 'active',
      createdBy: _currentUser?.id ?? '',
      createdAt: now,
      updatedAt: now,
      soBreed: _context!.auditType == 'Setter Optimizing'
          ? _context!.breed
          : null,
      soIncubationAge: _context!.auditType == 'Setter Optimizing' ? 1 : null,
      hoBreed: _context!.auditType == 'Hatcher Optimizing'
          ? _context!.breed
          : null,
      hoIncubationAge: _context!.auditType == 'Hatcher Optimizing' ? 18 : null,
    );
  }

  // Update a field in the active draft
  void updateField(String key, dynamic value) {
    if (_isReadOnly) return;

    // Update the draft
    final updatedDraft = _updateAuditField(activeDraft, key, value);
    _drafts[_activeHatchIndex] = updatedDraft;

    notifyListeners();
  }

  // Helper to update a field in an AuditModel
  AuditModel _updateAuditField(AuditModel audit, String key, dynamic value) {
    // This is a simplified version - in production you'd use code generation or a more sophisticated approach
    // For now, we'll create a new AuditModel with the updated field
    final map = audit.toMap();
    map[key] = value;
    map['updatedAt'] = DateTime.now().toIso8601String();
    return AuditModel.fromMap(map);
  }

  // Save the current tab
  Future<void> saveTab(int tabIndex) async {
    if (_isReadOnly) return;

    _isLoading = true;
    notifyListeners();

    try {
      // Save to SQLite
      await _repository.insertAudit(activeDraft);

      // Mark tab as saved
      if (!_savedTabs.containsKey(_activeHatchIndex)) {
        _savedTabs[_activeHatchIndex] = {};
      }
      _savedTabs[_activeHatchIndex]!.add(tabIndex);

      unawaited(_supabaseService.syncAudit(activeDraft.toMap()));
    } catch (e) {
      // Silent error - data is still in memory
      if (kDebugMode) {
        print('Error saving audit: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Add a new hatch to the session
  void addHatch() {
    if (_isReadOnly) return;

    final newHatchNumber = _drafts.length + 1;
    _drafts.add(_createNewDraft(hatchNumber: newHatchNumber));
    _activeHatchIndex = _drafts.length - 1;

    notifyListeners();
  }

  // Switch to a different hatch
  void switchHatch(int index) {
    if (index < 0 || index >= _drafts.length) return;
    _activeHatchIndex = index;
    notifyListeners();
  }

  // Load an existing audit for editing
  Future<void> loadForEdit(String auditId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final audit = await _repository.getAuditById(auditId);
      if (audit != null) {
        // Load all hatches for this session
        final sessionAudits = await _repository.getAuditsBySession(
          audit.customerId,
          audit.flockId ?? '',
          audit.date.toIso8601String().split('T')[0],
          audit.auditType,
        );

        _drafts = sessionAudits;
        _activeHatchIndex = audit.hatchNumber - 1;
        _isReadOnly = true;

        // Mark all tabs as saved
        for (var i = 0; i < _drafts.length; i++) {
          _savedTabs[i] = {0, 1, 2, 3, 4}; // Assume all 5 tabs are saved
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading audit: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Toggle edit mode
  void setEditMode(bool editable) {
    _isReadOnly = !editable;
    notifyListeners();
  }

  // Set temperature unit
  void setTempUnit(TempUnit unit) {
    _tempUnit = unit;
    notifyListeners();
  }
}
