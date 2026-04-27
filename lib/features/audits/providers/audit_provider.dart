import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/constants/app_thresholds.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/sample_mode.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/activity_log_repository.dart';
import '../../../data/repositories/audit_repository.dart';
import '../../../providers/app_provider.dart';
import '../../../services/notifications/notification_service.dart';
import '../../../services/supabase/supabase_service.dart';
import '../models/egg_breakout_tray_rollup.dart';
import 'package:uuid/uuid.dart';

class AuditContext {
  final String auditType;
  final String customerId;
  final String flockId;
  final String? breed;
  final String? setterId;
  final String? hatcherId;
  final DateTime? flockEntryDate;
  final String date;

  AuditContext({
    required this.auditType,
    required this.customerId,
    required this.flockId,
    this.breed,
    this.setterId,
    this.hatcherId,
    this.flockEntryDate,
    required this.date,
  });
}

class AuditProvider extends ChangeNotifier {
  final AuditRepository _repository = AuditRepository();
  final ActivityLogRepository _activityLogRepository = ActivityLogRepository();
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
  bool _isDirty = false;
  UserModel? _currentUser;
  String? _activeSessionId;

  // Getters
  AuditContext? get context => _context;
  List<AuditModel> get drafts => List.unmodifiable(_drafts);
  int get activeHatchIndex => _activeHatchIndex;
  AuditModel get activeDraft => _drafts[_activeHatchIndex];
  String? get activeSessionId => _activeSessionId;
  bool isTabSaved(int tabIndex) =>
      _savedTabs[_activeHatchIndex]?.contains(tabIndex) ?? false;
  TempUnit get tempUnit => _tempUnit;
  bool get isReadOnly => _isReadOnly;
  bool get isLoading => _isLoading;
  bool get isDirty => _isDirty;
  int get hatchCount => _drafts.length;
  String get sampleMode => activeDraft.sampleMode;
  bool get isCompareMode => SampleMode.isCompare(sampleMode);

  // Initialize new audit session
  void initialize(
    AuditContext context, {
    AuditModel? existingAudit,
    bool notify = true,
    UserModel? currentUser,
    String? sessionId,
  }) {
    _context = context;
    _currentUser = currentUser;
    _tempUnit = TempUnit.fahrenheit;
    _activeSessionId = sessionId ?? existingAudit?.sessionId;

    if (existingAudit != null) {
      _drafts = [existingAudit];
      _activeHatchIndex = 0;
      _isReadOnly = !(currentUser?.canEditAudits ?? false);
    } else {
      _drafts = [_createNewDraft(hatchNumber: 1)];
      _activeHatchIndex = 0;
      _isReadOnly = false;
    }

    _savedTabs.clear();
    _isDirty = false;
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
      setterId: _context!.setterId,
      hatcherId: _context!.hatcherId,
      sessionId: _activeSessionId,
      sampleMode: SampleMode.pool,
      haTotalEggsSet: _context!.auditType == 'Hatch Analysis' ? 19200 : null,
      soBreed: _context!.auditType == 'Setter Optimizing'
          ? _context!.breed
          : null,
      soSetterId: _context!.auditType == 'Setter Optimizing'
          ? _context!.setterId
          : null,
      soIncubationAge: _context!.auditType == 'Setter Optimizing' ? 1 : null,
      hoBreed: _context!.auditType == 'Hatcher Optimizing'
          ? _context!.breed
          : null,
      hoHatcherId: _context!.auditType == 'Hatcher Optimizing'
          ? _context!.hatcherId
          : null,
      hoIncubationAge: _context!.auditType == 'Hatcher Optimizing' ? 18 : null,
    );
  }

  // Update a field in the active draft
  void updateField(String key, dynamic value) {
    if (_isReadOnly) return;

    updateHatchField(_activeHatchIndex, key, value);
  }

  void updateHatchField(int hatchIndex, String key, dynamic value) {
    if (_isReadOnly) return;
    if (hatchIndex < 0 || hatchIndex >= _drafts.length) return;

    final updatedDraft = _updateAuditField(_drafts[hatchIndex], key, value);
    _drafts[hatchIndex] = updatedDraft;
    _isDirty = true;

    notifyListeners();
  }

  // Helper to update a field in an AuditModel
  AuditModel _updateAuditField(AuditModel audit, String key, dynamic value) {
    // This is a simplified version - in production you'd use code generation or a more sophisticated approach
    // For now, we'll create a new AuditModel with the updated field
    final map = audit.toMap();
    map[key] = value;
    if (key == 'ebTrayBreakoutJson') {
      map.addAll(
        EggBreakoutTrayRollup.fromJson(value as String?).toAuditFields(),
      );
    }
    map['updatedAt'] = DateTime.now().toIso8601String();
    return AuditModel.fromMap(map);
  }

  void setSampleMode(String mode) {
    if (_isReadOnly) return;
    final normalized = SampleMode.normalize(mode);
    final compareGroupKey = normalized == SampleMode.compare
        ? _activeCompareGroupKey()
        : null;

    if (normalized == SampleMode.pool && _drafts.length > 1) {
      _drafts = [_drafts.first];
      _activeHatchIndex = 0;
    }

    for (var i = 0; i < _drafts.length; i++) {
      final map = _drafts[i].toMap();
      map['sampleMode'] = normalized;
      map['compareGroupKey'] = compareGroupKey;
      map['hatchNumber'] = normalized == SampleMode.pool ? 1 : i + 1;
      map['updatedAt'] = DateTime.now().toIso8601String();
      _drafts[i] = AuditModel.fromMap(map);
    }
    _isDirty = true;
    notifyListeners();
  }

  String _activeCompareGroupKey() {
    for (final draft in _drafts) {
      final key = draft.compareGroupKey;
      if (key != null && key.isNotEmpty) return key;
    }
    return _uuid.v4();
  }

  // Save the current tab
  Future<void> saveTab(int tabIndex) async {
    if (_isReadOnly) return;

    _isLoading = true;
    notifyListeners();

    try {
      final draftsToSave = isCompareMode ? _drafts : [activeDraft];
      for (var i = 0; i < draftsToSave.length; i++) {
        final existing = await _repository.getAuditById(draftsToSave[i].id);
        await _repository.insertAudit(draftsToSave[i]);

        final savedIndex = isCompareMode ? i : _activeHatchIndex;
        _savedTabs.putIfAbsent(savedIndex, () => {}).add(tabIndex);
        await _logAuditChange(
          draftsToSave[i],
          existing == null ? 'create' : 'update',
        );
        await _checkThresholdsAndAlert(draftsToSave[i]);

        unawaited(_supabaseService.syncAudit(draftsToSave[i].toMap()));
      }
      _isDirty = false;
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

  Future<void> saveAllHatches() async {
    if (_isReadOnly) return;

    _isLoading = true;
    notifyListeners();

    try {
      final draftsToSave = isCompareMode ? _drafts : [_drafts.first];
      for (var i = 0; i < draftsToSave.length; i++) {
        final existing = await _repository.getAuditById(draftsToSave[i].id);
        await _repository.insertAudit(draftsToSave[i]);
        _savedTabs[i] = {0, 1};
        await _logAuditChange(
          draftsToSave[i],
          existing == null ? 'create' : 'update',
        );
        await _checkThresholdsAndAlert(draftsToSave[i]);
        unawaited(_supabaseService.syncAudit(draftsToSave[i].toMap()));
      }
      _isDirty = false;
    } catch (e) {
      if (kDebugMode) {
        print('Error saving hatch analysis: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // PM Necropsy conditional field validation
  List<String> validatePmConditionalFields() {
    final errors = <String>[];
    final a = activeDraft;

    final lesionPairs = <Map<String, dynamic>>[
      {
        'label': 'Omphalitis',
        'count': a.pmOmphalitisCount,
        'severity': a.pmOmphalitisSeverity,
      },
      {
        'label': 'Gaseous Ceca',
        'count': a.pmGaseousCecaCount,
        'severity': a.pmGaseousCecaSeverity,
      },
      {
        'label': 'Unabsorbed Yolk',
        'count': a.pmUnabsorbedYolkCount,
        'severity': a.pmUnabsorbedYolkSeverity,
      },
      {
        'label': 'Perihepatitis',
        'count': a.pmPerihepatitisCount,
        'severity': a.pmPerihepatitisSeverity,
      },
      {
        'label': 'Pericarditis',
        'count': a.pmPericarditisCount,
        'severity': a.pmPericarditisSeverity,
      },
      {
        'label': 'Airsac Acute',
        'count': a.pmAirsacAcuteCount,
        'severity': a.pmAirsacAcuteSeverity,
      },
      {
        'label': 'Airsac Chronic',
        'count': a.pmAirsacChronicCount,
        'severity': a.pmAirsacChronicSeverity,
      },
      {
        'label': 'Pulmonary Granuloma',
        'count': a.pmPulmonaryGranulomaCount,
        'severity': a.pmPulmonaryGranulomaSeverity,
      },
      {
        'label': 'Swollen Joints',
        'count': a.pmSwollenJointsCount,
        'severity': a.pmSwollenJointsSeverity,
      },
      {
        'label': 'Stunted Organs',
        'count': a.pmStuntedOrgansCount,
        'severity': a.pmStuntedOrgansSeverity,
      },
      {
        'label': 'Pulmonary Hemorrhage',
        'count': a.pmPulmonaryHemorrhageCount,
        'severity': a.pmPulmonaryHemorrhageSeverity,
      },
    ];

    for (final pair in lesionPairs) {
      final label = pair['label'] as String;
      final count = pair['count'] as int?;
      final severity = pair['severity'] as String?;
      if ((count ?? 0) > 0 && (severity == null || severity.isEmpty)) {
        errors.add('$label requires severity when count > 0');
      }
    }

    if (a.pmGaspingPresent == true &&
        (a.pmGaspingType == null || a.pmGaspingType!.isEmpty)) {
      errors.add('Gasping subtype is required when gasping is present');
    }

    if ((a.pmOtherDeformityCount ?? 0) > 0 &&
        (a.pmOtherDeformityText == null || a.pmOtherDeformityText!.isEmpty)) {
      errors.add('Other deformity description is required when count > 0');
    }

    return errors;
  }

  // Add a new hatch to the session
  void addHatch() {
    if (_isReadOnly) return;
    if (!isCompareMode) {
      setSampleMode(SampleMode.compare);
    }

    final newHatchNumber = _drafts.length + 1;
    final draft = _createNewDraft(hatchNumber: newHatchNumber);
    final map = draft.toMap();
    map['sampleMode'] = SampleMode.compare;
    map['compareGroupKey'] = _activeCompareGroupKey();
    _drafts.add(AuditModel.fromMap(map));
    _activeHatchIndex = _drafts.length - 1;
    _isDirty = true;

    notifyListeners();
  }

  void removeActiveHatch() {
    if (_isReadOnly) return;
    if (!isCompareMode || _drafts.length <= 1) return;

    final removedIndex = _activeHatchIndex;
    _drafts.removeAt(removedIndex);
    _activeHatchIndex = _activeHatchIndex.clamp(0, _drafts.length - 1).toInt();
    final compareGroupKey = _activeCompareGroupKey();

    for (var i = 0; i < _drafts.length; i++) {
      final map = _drafts[i].toMap();
      map['sampleMode'] = SampleMode.compare;
      map['compareGroupKey'] = compareGroupKey;
      map['hatchNumber'] = i + 1;
      map['updatedAt'] = DateTime.now().toIso8601String();
      _drafts[i] = AuditModel.fromMap(map);
    }

    final nextSavedTabs = <int, Set<int>>{};
    for (final entry in _savedTabs.entries) {
      if (entry.key == removedIndex) continue;
      final nextIndex = entry.key > removedIndex ? entry.key - 1 : entry.key;
      nextSavedTabs[nextIndex] = entry.value;
    }
    _savedTabs
      ..clear()
      ..addAll(nextSavedTabs);
    _isDirty = true;
    notifyListeners();
  }

  // Switch to a different hatch
  void switchHatch(int index) {
    if (index < 0 || index >= _drafts.length) return;
    _activeHatchIndex = index;
    notifyListeners();
  }

  // --- 100% Budget Validation ---

  int hatchBudgetSum(int hatchIndex) {
    if (hatchIndex < 0 || hatchIndex >= _drafts.length) return 0;
    final a = _drafts[hatchIndex];
    return (a.haHatched ?? 0) +
        (a.haCulled ?? 0) +
        (a.haDead ?? 0) +
        (a.haPipped ?? 0) +
        (a.haInfertileClear ?? 0) +
        (a.haEarlyDead ?? 0) +
        (a.haMidDead ?? 0) +
        (a.haMidLateDead ?? 0) +
        (a.haLateDead ?? 0) +
        (a.haContaminatedExploders ?? 0);
  }

  bool isHatchBudgetReconciled(int hatchIndex) {
    if (hatchIndex < 0 || hatchIndex >= _drafts.length) return false;
    final a = _drafts[hatchIndex];
    final total = a.haTotalEggsSet ?? 0;
    return total > 0 && hatchBudgetSum(hatchIndex) == total;
  }

  String? validateHatchBudget(int hatchIndex) {
    if (hatchIndex < 0 || hatchIndex >= _drafts.length) {
      return 'Invalid hatch index';
    }
    final a = _drafts[hatchIndex];

    if (a.haTotalEggsSet == null || a.haTotalEggsSet! <= 0) {
      return 'Total Eggs Set must be positive';
    }

    final sum = hatchBudgetSum(hatchIndex);
    final total = a.haTotalEggsSet!;

    if (sum != total) {
      final diff = total - sum;
      if (diff > 0) {
        return 'Unallocated eggs: $diff eggs still need a category assignment';
      } else {
        return 'Over budget: ${-diff} eggs exceed the total $total. Reduce category counts.';
      }
    }
    return null;
  }

  void recalculateHatchMetrics(int hatchIndex) {
    if (hatchIndex < 0 || hatchIndex >= _drafts.length) return;
    final a = _drafts[hatchIndex];
    final total = a.haTotalEggsSet ?? 0;
    if (total <= 0) return;

    final hatched = a.haHatched ?? 0;
    final hatchability = total > 0 ? (hatched / total) * 100 : 0.0;
    updateHatchField(
      hatchIndex,
      'haHatchability',
      double.parse(hatchability.toStringAsFixed(1)),
    );

    final infertile = a.haInfertileClear ?? 0;
    final fertile = total - infertile;
    final fertility = total > 0 ? (fertile / total) * 100 : 0.0;
    final fertilityRounded = double.parse(fertility.toStringAsFixed(1));
    updateHatchField(hatchIndex, 'haFertility', fertilityRounded);

    final hof = fertility > 0 ? (hatchability / fertility) * 100 : 0.0;
    updateHatchField(hatchIndex, 'haHof', double.parse(hof.toStringAsFixed(1)));
  }

  // Load an existing audit for editing
  Future<void> loadForEdit(String auditId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final audit = await _repository.getAuditById(auditId);
      if (audit != null) {
        _activeSessionId = audit.sessionId;
        _context ??= AuditContext(
          auditType: audit.auditType,
          customerId: audit.customerId,
          flockId: audit.flockId ?? '',
          breed: audit.soBreed ?? audit.hoBreed,
          setterId: audit.setterId ?? audit.soSetterId,
          hatcherId: audit.hatcherId ?? audit.hoHatcherId,
          flockEntryDate: _context?.flockEntryDate,
          date: audit.date.toIso8601String().split('T')[0],
        );
        // Load all hatches for this session
        final sessionAudits = await _repository.getAuditsBySession(
          audit.customerId,
          audit.flockId ?? '',
          audit.date.toIso8601String().split('T')[0],
          audit.auditType,
        );

        _drafts = sessionAudits;
        if (_drafts.isEmpty) {
          _drafts = [audit];
        }
        final loadedMode = _drafts.length > 1
            ? SampleMode.compare
            : _drafts.first.sampleMode;
        final compareGroupKey = loadedMode == SampleMode.compare
            ? _activeCompareGroupKey()
            : null;
        for (var i = 0; i < _drafts.length; i++) {
          final map = _drafts[i].toMap();
          map['sampleMode'] = loadedMode;
          map['compareGroupKey'] = compareGroupKey;
          _drafts[i] = AuditModel.fromMap(map);
        }
        _activeHatchIndex = (audit.hatchNumber - 1)
            .clamp(0, _drafts.length - 1)
            .toInt();
        _isReadOnly = true;

        // Mark all tabs as saved
        for (var i = 0; i < _drafts.length; i++) {
          _savedTabs[i] = {0, 1, 2, 3, 4};
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
    if (editable && !(_currentUser?.canEditAudits ?? false)) return;
    _isReadOnly = !editable;
    notifyListeners();
  }

  // Link active drafts to a visit session
  void setActiveSessionId(String? sessionId) {
    _activeSessionId = sessionId;
    if (sessionId != null) {
      for (var i = 0; i < _drafts.length; i++) {
        final map = _drafts[i].toMap();
        map['sessionId'] = sessionId;
        map['updatedAt'] = DateTime.now().toIso8601String();
        _drafts[i] = AuditModel.fromMap(map);
      }
      notifyListeners();
    }
  }

  // Set temperature unit
  void setTempUnit(TempUnit unit) {
    _tempUnit = unit;
    notifyListeners();
  }

  Future<void> _logAuditChange(AuditModel audit, String action) async {
    final userId = _currentUser?.id;
    if (userId == null || userId.isEmpty) return;
    await _activityLogRepository.log(
      userId,
      action,
      entityType: 'audit',
      entityId: audit.id,
      details: audit.auditType,
    );
  }

  Future<void> _checkThresholdsAndAlert(AuditModel audit) async {
    if (audit.pasgarFinalScore != null &&
        audit.pasgarFinalScore! < AppThresholds.pasgarAlertPct) {
      await NotificationService.showAlert(
        title: 'Low Pasgar Score',
        body:
            'Score ${audit.pasgarFinalScore!.toStringAsFixed(1)}% is below threshold.',
        payload: audit.id,
      );
    }

    final cvt = audit.cvtAvg ?? audit.hoCvtAvg;
    if (cvt != null &&
        (cvt < AppThresholds.cvtMin || cvt > AppThresholds.cvtMax)) {
      await NotificationService.showAlert(
        title: 'CVT Out of Range',
        body: 'CVT ${cvt.toStringAsFixed(1)} is outside the target range.',
        payload: audit.id,
      );
    }

    if (audit.esShellTemp != null &&
        (audit.esShellTemp! < AppThresholds.shellTempMin ||
            audit.esShellTemp! > AppThresholds.shellTempMax)) {
      await NotificationService.showAlert(
        title: 'Shell Temperature Alert',
        body:
            'Shell temp ${audit.esShellTemp!.toStringAsFixed(1)} is outside the target range.',
        payload: audit.id,
      );
    }
  }
}
