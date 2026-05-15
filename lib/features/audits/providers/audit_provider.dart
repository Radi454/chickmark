import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/constants/app_thresholds.dart';
import '../../../core/security/safe_debug_log.dart';
import '../../../core/utils/bmk_age_calculator.dart';
import '../../../data/mappers/station_sample_mapper.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/panel_sample_model.dart';
import '../../../data/models/panel_sample_schema.dart';
import '../../../data/models/sample_mode.dart';
import '../../../data/models/station_sample_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/activity_log_repository.dart';
import '../../../data/repositories/audit_repository.dart';
import '../../../data/repositories/panel_sample_repository.dart';
import '../../../data/repositories/station_sample_repository.dart';
import '../../../providers/app_provider.dart';
import '../../../services/notifications/notification_service.dart';
import '../../../services/supabase/supabase_service.dart';
import '../models/egg_breakout_tray_rollup.dart';
import '../models/egg_breakout_sample.dart';
import '../models/residue_batch_metrics.dart';
import 'package:uuid/uuid.dart';

class AuditContext {
  final String auditType;
  final String customerId;
  final String flockId;
  final String? hatcheryId;
  final String? breed;
  final String? setterId;
  final String? hatcherId;
  final DateTime? flockEntryDate;
  final int? flockAgeWeeks;
  final String date;

  AuditContext({
    required this.auditType,
    required this.customerId,
    required this.flockId,
    this.hatcheryId,
    this.breed,
    this.setterId,
    this.hatcherId,
    this.flockEntryDate,
    this.flockAgeWeeks,
    required this.date,
  });
}

class AuditProvider extends ChangeNotifier {
  AuditProvider({
    AuditRepository? repository,
    StationSampleRepository? stationSampleRepository,
    PanelSampleRepository? panelSampleRepository,
    ActivityLogRepository? activityLogRepository,
    SupabaseService? supabaseService,
    Duration autosaveDebounceDuration = defaultAutosaveDebounceDuration,
    bool autosaveEnabled = true,
  }) : _repository = repository ?? AuditRepository(),
       _stationSampleRepository =
           stationSampleRepository ?? StationSampleRepository(),
       _panelSampleRepository =
           panelSampleRepository ?? PanelSampleRepository(),
       _activityLogRepository =
           activityLogRepository ?? ActivityLogRepository(),
       _supabaseService = supabaseService ?? SupabaseService(),
       _autosaveDebounceDuration = autosaveDebounceDuration,
       _autosaveEnabled = autosaveEnabled;

  static const Duration defaultAutosaveDebounceDuration = Duration(seconds: 1);

  final AuditRepository _repository;
  final StationSampleRepository _stationSampleRepository;
  final PanelSampleRepository _panelSampleRepository;
  final ActivityLogRepository _activityLogRepository;
  final SupabaseService _supabaseService;
  final Duration _autosaveDebounceDuration;
  final bool _autosaveEnabled;
  final Uuid _uuid = const Uuid();

  // State
  AuditContext? _context;
  List<AuditModel> _drafts = [];
  List<StationSampleModel> _stationSamples = [];
  List<StationSampleModel> _chickWeightSamples = [];
  final Set<String> _removedStationSampleIds = {};
  final Set<String> _removedLegacyAuditIds = {};
  int _activeHatchIndex = 0;
  int _activeChickWeightSampleIndex = 0;
  final Map<int, Set<int>> _savedTabs = {}; // hatchIndex -> saved tab indices
  TempUnit _tempUnit = TempUnit.fahrenheit;
  bool _isReadOnly = false;
  bool _isLoading = false;
  bool _isDirty = false;
  bool _isAutosaving = false;
  DateTime? _lastAutosavedAt;
  String? _autosaveError;
  int _changeVersion = 0;
  int _savedVersion = 0;
  Timer? _autosaveTimer;
  Future<bool>? _autosaveFuture;
  bool _isDisposed = false;
  UserModel? _currentUser;
  String? _activeSessionId;
  Future<bool>? _saveFuture;

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
  bool get isAutosaving => _isAutosaving;
  DateTime? get lastAutosavedAt => _lastAutosavedAt;
  String? get autosaveError => _autosaveError;
  bool get isAutosaveCaughtUp =>
      !_isDirty &&
      !_isAutosaving &&
      _autosaveError == null &&
      _savedVersion == _changeVersion;
  bool get hasPendingAutosave =>
      _isDirty ||
      _isAutosaving ||
      (_autosaveTimer?.isActive ?? false) ||
      _autosaveError != null;
  int get hatchCount => _drafts.length;
  String get sampleMode => activeDraft.sampleMode;
  bool get isCompareMode => SampleMode.isCompare(sampleMode);
  int get sampleCount => _drafts.length;
  int get activeSampleIndex => _activeHatchIndex;
  List<StationSampleModel> get stationSamples =>
      List.unmodifiable(_stationSamples);
  StationSampleModel get activeStationSample =>
      _stationSamples[_activeHatchIndex];
  List<StationSampleModel> get chickWeightSamples =>
      List.unmodifiable(_chickWeightSamples);
  int get activeChickWeightSampleIndex => _activeChickWeightSampleIndex;
  StationSampleModel get activeChickWeightSample =>
      _chickWeightSamples[_activeChickWeightSampleIndex];
  String get chickWeightSampleMode => _chickWeightSamples.isEmpty
      ? StationSampleModel.sampleModePooled
      : activeChickWeightSample.sampleMode;
  bool get isChickWeightCompareMode =>
      chickWeightSampleMode == StationSampleModel.sampleModeComparison;
  String get stationSampleMode => activeStationSample.sampleMode;
  String? get comparisonType => activeStationSample.comparisonType;

  @override
  void dispose() {
    _isDisposed = true;
    _autosaveTimer?.cancel();
    super.dispose();
  }

  void _notifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  void _markDirtyAndScheduleAutosave() {
    _changeVersion++;
    _isDirty = true;
    _autosaveError = null;
    _scheduleAutosave();
  }

  void _scheduleAutosave() {
    if (!_autosaveEnabled || _isReadOnly || _isDisposed) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(_autosaveDebounceDuration, () {
      unawaited(_runAutosave());
    });
  }

  // Initialize new audit session
  void initialize(
    AuditContext context, {
    AuditModel? existingAudit,
    List<AuditModel>? existingAudits,
    List<StationSampleModel>? existingStationSamples,
    bool? readOnly,
    bool notify = true,
    UserModel? currentUser,
    String? sessionId,
  }) {
    _context = context;
    _currentUser = currentUser;
    _tempUnit = TempUnit.fahrenheit;
    final restoredAudits =
        existingAudits
            ?.where((audit) => audit.auditType == context.auditType)
            .toList()
          ?..sort((a, b) => a.hatchNumber.compareTo(b.hatchNumber));
    final restoredSessionId =
        restoredAudits != null && restoredAudits.isNotEmpty
        ? restoredAudits.first.sessionId
        : null;
    _activeSessionId =
        sessionId ?? existingAudit?.sessionId ?? restoredSessionId;

    if (restoredAudits != null && restoredAudits.isNotEmpty) {
      _drafts = restoredAudits;
      _activeHatchIndex = 0;
      _isReadOnly = readOnly ?? !(currentUser?.canEditAudits ?? false);
    } else if (existingAudit != null) {
      _drafts = [existingAudit];
      _activeHatchIndex = 0;
      _isReadOnly = readOnly ?? !(currentUser?.canEditAudits ?? false);
    } else {
      _drafts = [_createNewDraft(hatchNumber: 1)];
      _activeHatchIndex = 0;
      _isReadOnly = readOnly ?? false;
    }
    _stationSamples = _buildSamplesForDrafts(
      existingStationSamples: _primarySamplesForContext(existingStationSamples),
    );
    _chickWeightSamples = _buildChickWeightSamplesForContext(
      existingStationSamples,
    );
    _activeChickWeightSampleIndex = 0;

    _savedTabs.clear();
    _removedStationSampleIds.clear();
    _removedLegacyAuditIds.clear();
    _autosaveTimer?.cancel();
    _autosaveError = null;
    _isAutosaving = false;
    _lastAutosavedAt = null;
    _changeVersion = 0;
    _savedVersion = 0;
    _isDirty = false;
    if (notify) notifyListeners();
  }

  // Create a new draft audit
  AuditModel _createNewDraft({required int hatchNumber}) {
    final now = DateTime.now();
    final isHatchBreakout =
        _context!.auditType == 'Hatch Analysis & Egg Breakouts';
    final isSetterOptimizing = _context!.auditType == 'Setters';
    final setterId = isHatchBreakout
        ? '$hatchNumber'
        : isSetterOptimizing
        ? (hatchNumber == 1 && _context!.setterId?.trim().isNotEmpty == true
              ? _context!.setterId
              : '$hatchNumber')
        : _context!.setterId;
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
      setterId: setterId,
      hatcherId: isHatchBreakout ? '$hatchNumber' : _context!.hatcherId,
      sessionId: _activeSessionId,
      sampleMode: SampleMode.pool,
      esEggStorageDays: _context!.auditType == 'Egg' ? 0 : null,
      haTotalEggsSet: isHatchBreakout ? 19200 : null,
      haStorageDays: isHatchBreakout ? 0 : null,
      ebStorageDays: isHatchBreakout ? 0 : null,
      soBreed: isSetterOptimizing ? _context!.breed : null,
      soSetterId: isSetterOptimizing ? setterId : null,
      soIncubationAge: _context!.auditType == 'Setters' ? 1 : null,
      soIncubationHours: _context!.auditType == 'Setters' ? 0 : null,
      hoBreed: _context!.auditType == 'Hatchers' ? _context!.breed : null,
      hoHatcherId: _context!.auditType == 'Hatchers'
          ? _context!.hatcherId
          : null,
      hoIncubationAge: _context!.auditType == 'Hatchers' ? 18 : null,
      hoIncubationHours: _context!.auditType == 'Hatchers' ? 0 : null,
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
    _syncStationSampleFromDraft(hatchIndex);
    _markDirtyAndScheduleAutosave();

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
    final provisional = AuditModel.fromMap(map);
    if (EggBreakoutType.fromStorageValue(provisional.ebBreakoutType) ==
        EggBreakoutType.residueHatchDay) {
      final metrics = ResidueBatchMetrics.fromAudit(provisional);
      map['haHatchability'] = metrics.hatchabilityPct;
      map['haFertility'] = metrics.fertilityPct;
      map['haHof'] = metrics.hofPct;
    }
    map['updatedAt'] = DateTime.now().toIso8601String();
    return AuditModel.fromMap(map);
  }

  void setSampleMode(String mode) {
    setStationSampleMode(
      SampleMode.isCompare(mode)
          ? StationSampleModel.sampleModeComparison
          : StationSampleModel.sampleModePooled,
    );
  }

  void setStationSampleMode(String mode) {
    if (_isReadOnly) return;
    final normalized = StationSampleModel.normalizeSampleMode(mode);
    final legacyMode = normalized == StationSampleModel.sampleModeComparison
        ? SampleMode.compare
        : SampleMode.pool;
    final compareGroupKey = legacyMode == SampleMode.compare
        ? _activeCompareGroupKey()
        : null;

    if (legacyMode == SampleMode.pool && _drafts.length > 1) {
      _removedStationSampleIds.addAll(
        _stationSamples.skip(1).map((sample) => sample.id),
      );
      _removedLegacyAuditIds.addAll(_drafts.skip(1).map((draft) => draft.id));
      _drafts = [_drafts.first];
      _stationSamples = [_stationSamples.first];
      _activeHatchIndex = 0;
    }

    for (var i = 0; i < _drafts.length; i++) {
      final map = _drafts[i].toMap();
      map['sampleMode'] = legacyMode;
      map['compareGroupKey'] = compareGroupKey;
      map['hatchNumber'] = legacyMode == SampleMode.pool ? 1 : i + 1;
      map['updatedAt'] = DateTime.now().toIso8601String();
      _drafts[i] = AuditModel.fromMap(map);
      _syncStationSampleFromDraft(i);
    }
    _markDirtyAndScheduleAutosave();
    notifyListeners();
  }

  void setComparisonType(String? value) {
    if (_isReadOnly || _stationSamples.isEmpty) return;
    final sample = activeStationSample;
    _stationSamples[_activeHatchIndex] = sample.copyWith(
      comparisonType: value,
      updatedAt: DateTime.now(),
    );
    _markDirtyAndScheduleAutosave();
    notifyListeners();
  }

  void updateSampleMetadata(Map<String, dynamic> fields) {
    if (_isReadOnly || _stationSamples.isEmpty) return;
    final now = DateTime.now();
    final draft = activeDraft;
    var sample = activeStationSample;
    final eggProductionDate =
        fields['eggProductionDate'] as DateTime? ?? sample.eggProductionDate;
    final storageDays = fields['storageDays'] as int? ?? sample.storageDays;
    final calculatedBmkAgeDays =
        fields['calculatedBmkAgeDays'] as int? ??
        BmkAgeCalculator.calculateDays(
          currentFlockAgeDays: BmkAgeCalculator.currentFlockAgeDaysFromWeeks(
            _context?.flockAgeWeeks,
          ),
          auditDate: draft.date,
          eggProductionDate: eggProductionDate,
          legacyBmkAgeWeeks: _legacyBmkWeeksForDraft(draft),
          storageDays: storageDays,
          flockEntryDate: _context?.flockEntryDate,
        );
    sample = sample.copyWith(
      sampleLabel:
          fields['sampleLabel'] as String? ??
          _sampleLabelForMetadataUpdate(
            draft: draft,
            sample: sample,
            setterNo: fields['setterNo'] as String? ?? sample.setterNo,
            hatcherNo: fields['hatcherNo'] as String? ?? sample.hatcherNo,
          ),
      batchNo: fields['batchNo'] as String? ?? sample.batchNo,
      houseNo: fields['houseNo'] as String? ?? sample.houseNo,
      houseLabel: fields['houseLabel'] as String? ?? sample.houseLabel,
      hatchNo: fields['hatchNo'] as String? ?? sample.hatchNo,
      eggProductionDate: eggProductionDate,
      settingDate: fields['settingDate'] as DateTime? ?? sample.settingDate,
      hatchDate: fields['hatchDate'] as DateTime? ?? sample.hatchDate,
      storageDays: storageDays,
      incubationDay: fields['incubationDay'] as int? ?? sample.incubationDay,
      setterNo: fields['setterNo'] as String? ?? sample.setterNo,
      hatcherNo: fields['hatcherNo'] as String? ?? sample.hatcherNo,
      notes: fields['notes'] as String? ?? sample.notes,
      calculatedBmkAgeDays: calculatedBmkAgeDays,
      updatedAt: now,
    );
    _stationSamples[_activeHatchIndex] = sample;
    _applySamplePatchToDraft(_activeHatchIndex);
    _markDirtyAndScheduleAutosave();
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
    await saveTabWithResult(tabIndex);
  }

  Future<bool> saveTabWithResult(int tabIndex) async {
    return saveSamplesWithResult(tabIndex: tabIndex);
  }

  Future<void> saveAllHatches() async {
    await saveAllHatchesWithResult();
  }

  Future<bool> saveAllHatchesWithResult() async {
    return saveSamplesWithResult(markAllTabsSaved: true);
  }

  Future<bool> saveSamplesWithResult({
    int? tabIndex,
    bool markAllTabsSaved = false,
  }) async {
    if (_isReadOnly) return true;
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    final autosaveInFlight = _autosaveFuture;
    if (autosaveInFlight != null) {
      await autosaveInFlight;
    }
    final inFlight = _saveFuture;
    if (inFlight != null) return inFlight;

    final saveVersion = _changeVersion;
    final future = _saveSamplesInternal(
      tabIndex: tabIndex,
      markAllTabsSaved: markAllTabsSaved,
      saveVersion: saveVersion,
      runFinalSaveSideEffects: true,
      showLoading: true,
    );
    _saveFuture = future;
    try {
      final saved = await future;
      if (saved) {
        _lastAutosavedAt = DateTime.now();
        _autosaveError = null;
        if (_changeVersion > saveVersion && _isDirty) {
          _scheduleAutosave();
        }
      }
      return saved;
    } finally {
      _saveFuture = null;
    }
  }

  Future<bool> flushAutosave() async {
    if (_isReadOnly) return true;
    if (!_autosaveEnabled) return true;
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    final autosaveInFlight = _autosaveFuture;
    if (autosaveInFlight != null) return autosaveInFlight;
    if (!_isDirty && _autosaveError == null) return true;
    return _runAutosave();
  }

  Future<bool> _runAutosave() {
    if (!_autosaveEnabled || _isReadOnly) return Future.value(true);
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    if (!_isDirty) return Future.value(_autosaveError == null);
    final finalSaveInFlight = _saveFuture;
    if (finalSaveInFlight != null) return finalSaveInFlight;
    final existingAutosave = _autosaveFuture;
    if (existingAutosave != null) return existingAutosave;

    final saveVersion = _changeVersion;
    _isAutosaving = true;
    _autosaveError = null;
    _notifyListeners();

    final future = () async {
      final saved = await _saveSamplesInternal(
        saveVersion: saveVersion,
        runFinalSaveSideEffects: false,
        showLoading: false,
      );
      if (saved) {
        _lastAutosavedAt = DateTime.now();
        if (_changeVersion > saveVersion && _isDirty) {
          _scheduleAutosave();
        }
      } else {
        _autosaveError =
            'Could not autosave this station draft. Use Save to retry.';
      }
      _isAutosaving = false;
      _autosaveFuture = null;
      _notifyListeners();
      return saved;
    }();
    _autosaveFuture = future;
    return future;
  }

  Future<bool> _saveSamplesInternal({
    int? tabIndex,
    bool markAllTabsSaved = false,
    required int saveVersion,
    required bool runFinalSaveSideEffects,
    required bool showLoading,
  }) async {
    if (showLoading) {
      _isLoading = true;
      _notifyListeners();
    }

    try {
      final draftsToSave = List<AuditModel>.from(
        isCompareMode ? _drafts : [_drafts.first],
      );
      final samplesToSave = <int, StationSampleModel?>{};
      for (var i = 0; i < draftsToSave.length; i++) {
        samplesToSave[i] = _sampleForSave(i, draftsToSave[i]);
      }
      final chickWeightSamplesToSave = _chickWeightSamplesForSave();
      final removedStationSampleIds = List<String>.from(
        _removedStationSampleIds,
      );
      final removedLegacyAuditIds = List<String>.from(_removedLegacyAuditIds);
      final finalSaveSideEffects = <({AuditModel audit, String action})>[];
      final savedDrafts = <AuditModel>[];
      for (var i = 0; i < draftsToSave.length; i++) {
        final draft = runFinalSaveSideEffects
            ? _asStatus(draftsToSave[i], 'active')
            : _asStatus(draftsToSave[i], 'draft');
        savedDrafts.add(draft);
        final existing = runFinalSaveSideEffects
            ? await _repository.getAuditById(draft.id)
            : null;
        await _repository.insertAudit(draft);
        if (runFinalSaveSideEffects) {
          if (markAllTabsSaved) {
            _savedTabs[i] = {0, 1, 2, 3, 4};
          } else if (tabIndex != null) {
            _savedTabs.putIfAbsent(i, () => {}).add(tabIndex);
          }
          final action =
              existing == null || existing.status.toLowerCase() == 'draft'
              ? 'create'
              : 'update';
          finalSaveSideEffects.add((audit: draft, action: action));
        }

        final sample = samplesToSave[i];
        if (sample != null) {
          await _stationSampleRepository.upsertSample(sample);
          await _savePanelTablesForSample(draft, sample);
          if (i < _stationSamples.length) {
            _stationSamples[i] = sample;
          }
        }
      }
      for (var i = 0; i < chickWeightSamplesToSave.length; i++) {
        final sample = chickWeightSamplesToSave[i];
        await _stationSampleRepository.upsertSample(sample);
        if (i < _chickWeightSamples.length) {
          _chickWeightSamples[i] = sample;
        }
      }
      if (savedDrafts.isNotEmpty && chickWeightSamplesToSave.isNotEmpty) {
        await _savePanelTableWithSamples(
          'chick_weights',
          savedDrafts.first,
          chickWeightSamplesToSave,
        );
      }
      for (final id in removedStationSampleIds) {
        await _stationSampleRepository.deleteSample(id);
      }
      for (final id in removedLegacyAuditIds) {
        await _repository.deleteAudit(id);
      }
      for (final sideEffect in finalSaveSideEffects) {
        await _runFinalSaveSideEffects(sideEffect.audit, sideEffect.action);
      }
      _removedStationSampleIds.removeAll(removedStationSampleIds);
      _removedLegacyAuditIds.removeAll(removedLegacyAuditIds);
      if (_changeVersion == saveVersion) {
        _isDirty = false;
        _savedVersion = saveVersion;
      } else if (!runFinalSaveSideEffects) {
        _scheduleAutosave();
      }
      return true;
    } catch (e) {
      safeDebugLog('Error saving audit station', error: e);
      return false;
    } finally {
      if (showLoading) {
        _isLoading = false;
      }
      _notifyListeners();
    }
  }

  AuditModel _asStatus(AuditModel audit, String status) {
    if (audit.status == status) return audit;
    final map = audit.toMap();
    map['status'] = status;
    return AuditModel.fromMap(map);
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
    addSample();
  }

  void addSample() {
    if (_isReadOnly) return;
    if (!isCompareMode) {
      setStationSampleMode(StationSampleModel.sampleModeComparison);
    }

    final newHatchNumber = _drafts.length + 1;
    final draft = _createNewDraft(hatchNumber: newHatchNumber);
    final map = draft.toMap();
    map['sampleMode'] = SampleMode.compare;
    map['compareGroupKey'] = _activeCompareGroupKey();
    if (_context?.auditType == 'Hatch Analysis & Egg Breakouts') {
      map['ebBreakoutType'] = activeDraft.ebBreakoutType;
    }
    final nextDraft = AuditModel.fromMap(map);
    _drafts.add(nextDraft);
    _stationSamples.add(_createSampleForDraft(nextDraft, _drafts.length - 1));
    _activeHatchIndex = _drafts.length - 1;
    _markDirtyAndScheduleAutosave();

    notifyListeners();
  }

  void removeActiveHatch() {
    removeActiveSample();
  }

  void removeActiveSample() {
    if (_isReadOnly) return;
    if (!isCompareMode || _drafts.length <= 1) return;

    final removedIndex = _activeHatchIndex;
    _removedStationSampleIds.add(_stationSamples[removedIndex].id);
    _removedLegacyAuditIds.add(_drafts[removedIndex].id);
    _drafts.removeAt(removedIndex);
    _stationSamples.removeAt(removedIndex);
    _activeHatchIndex = _activeHatchIndex.clamp(0, _drafts.length - 1).toInt();
    final compareGroupKey = _activeCompareGroupKey();

    for (var i = 0; i < _drafts.length; i++) {
      final map = _drafts[i].toMap();
      map['sampleMode'] = SampleMode.compare;
      map['compareGroupKey'] = compareGroupKey;
      map['hatchNumber'] = i + 1;
      map['updatedAt'] = DateTime.now().toIso8601String();
      _drafts[i] = AuditModel.fromMap(map);
      _syncStationSampleFromDraft(i);
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
    _markDirtyAndScheduleAutosave();
    notifyListeners();
  }

  // Switch to a different hatch
  void switchHatch(int index) {
    switchSample(index);
  }

  void switchSample(int index) {
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
    if (EggBreakoutType.fromStorageValue(a.ebBreakoutType).showsHatchability) {
      return null;
    }
    return null;
  }

  void recalculateHatchMetrics(int hatchIndex) {
    if (hatchIndex < 0 || hatchIndex >= _drafts.length) return;
    final a = _drafts[hatchIndex];
    if (EggBreakoutType.fromStorageValue(a.ebBreakoutType) !=
        EggBreakoutType.residueHatchDay) {
      return;
    }
    final metrics = ResidueBatchMetrics.fromAudit(a);
    updateHatchField(hatchIndex, 'haHatchability', metrics.hatchabilityPct);
    updateHatchField(hatchIndex, 'haFertility', metrics.fertilityPct);
    updateHatchField(hatchIndex, 'haHof', metrics.hofPct);
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
          hatcheryId: _context?.hatcheryId,
          breed: audit.soBreed ?? audit.hoBreed,
          setterId: audit.setterId ?? audit.soSetterId,
          hatcherId: audit.hatcherId ?? audit.hoHatcherId,
          flockEntryDate: _context?.flockEntryDate,
          flockAgeWeeks: _context?.flockAgeWeeks,
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
        final loadedSamples = await _loadSavedSamplesForEdit(audit);
        _stationSamples = _buildSamplesForDrafts(
          existingStationSamples: _primarySamplesForContext(loadedSamples),
        );
        _chickWeightSamples = _buildChickWeightSamplesForContext(loadedSamples);
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
      safeDebugLog('Error loading audit', error: e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<StationSampleModel>> _loadSavedSamplesForEdit(
    AuditModel audit,
  ) async {
    final sessionId = _activeSessionId ?? audit.sessionId;
    if (sessionId != null && sessionId.isNotEmpty) {
      return _stationSampleRepository.getSamplesBySessionId(sessionId);
    }
    return _stationSampleRepository.getSamplesByLegacyAuditId(audit.id);
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
        _syncStationSampleFromDraft(i);
      }
      for (var i = 0; i < _chickWeightSamples.length; i++) {
        _chickWeightSamples[i] = _chickWeightSamples[i].copyWith(
          auditSessionId: sessionId,
          updatedAt: DateTime.now(),
        );
      }
      notifyListeners();
    }
  }

  void setChickWeightSampleMode(String mode) {
    if (_isReadOnly || !_isChicksContext || _chickWeightSamples.isEmpty) return;
    final normalized = StationSampleModel.normalizeSampleMode(mode);
    final compareGroupKey =
        normalized == StationSampleModel.sampleModeComparison
        ? _activeChickWeightCompareGroupKey()
        : null;

    if (normalized == StationSampleModel.sampleModePooled &&
        _chickWeightSamples.length > 1) {
      _removedStationSampleIds.addAll(
        _chickWeightSamples.skip(1).map((sample) => sample.id),
      );
      _chickWeightSamples = [_chickWeightSamples.first];
      _activeChickWeightSampleIndex = 0;
    }

    for (var i = 0; i < _chickWeightSamples.length; i++) {
      _chickWeightSamples[i] = _normalizedChickWeightSample(
        _chickWeightSamples[i],
        index: i,
        sampleMode: normalized,
        groupKey: compareGroupKey,
      );
    }
    _markDirtyAndScheduleAutosave();
    notifyListeners();
  }

  void addChickWeightSample() {
    if (_isReadOnly || !_isChicksContext) return;
    if (!isChickWeightCompareMode) {
      setChickWeightSampleMode(StationSampleModel.sampleModeComparison);
    }
    final mode = StationSampleModel.sampleModeComparison;
    final groupKey = _activeChickWeightCompareGroupKey();
    _chickWeightSamples.add(
      _createChickWeightSample(_chickWeightSamples.length, mode, groupKey),
    );
    _activeChickWeightSampleIndex = _chickWeightSamples.length - 1;
    _normalizeChickWeightSamples();
    _markDirtyAndScheduleAutosave();
    notifyListeners();
  }

  void removeActiveChickWeightSample() {
    if (_isReadOnly ||
        !_isChicksContext ||
        !isChickWeightCompareMode ||
        _chickWeightSamples.length <= 1) {
      return;
    }
    final removedIndex = _activeChickWeightSampleIndex;
    _removedStationSampleIds.add(_chickWeightSamples[removedIndex].id);
    _chickWeightSamples.removeAt(removedIndex);
    _activeChickWeightSampleIndex = _activeChickWeightSampleIndex
        .clamp(0, _chickWeightSamples.length - 1)
        .toInt();
    _normalizeChickWeightSamples();
    _markDirtyAndScheduleAutosave();
    notifyListeners();
  }

  void switchChickWeightSample(int index) {
    if (index < 0 || index >= _chickWeightSamples.length) return;
    _activeChickWeightSampleIndex = index;
    notifyListeners();
  }

  void updateChickWeightSampleMetadata(Map<String, dynamic> fields) {
    if (_isReadOnly || !_isChicksContext || _chickWeightSamples.isEmpty) return;
    final sample = activeChickWeightSample;
    _chickWeightSamples[_activeChickWeightSampleIndex] = sample.copyWith(
      sampleLabel: fields['sampleLabel'] as String? ?? sample.sampleLabel,
      houseNo: fields['houseNo'] as String? ?? sample.houseNo,
      houseLabel: fields['houseLabel'] as String? ?? sample.houseLabel,
      notes: fields['notes'] as String? ?? sample.notes,
      updatedAt: DateTime.now(),
    );
    _markDirtyAndScheduleAutosave();
    notifyListeners();
  }

  void updateChickWeightSampleResult({
    required String weightsJson,
    double? avgWeight,
    double? uniformityPct,
    double? cvPct,
  }) {
    if (_isReadOnly || !_isChicksContext || _chickWeightSamples.isEmpty) return;
    final summary = <String, Object?>{
      'auditType': 'Chicks',
      'sectorType': StationSampleModel.sectorChickWeights,
      'sampleLabel': activeChickWeightSample.sampleLabel,
      'chickWeights': _decodedWeights(weightsJson),
      'chickAvgWeight': avgWeight,
      'chickUniformityPct': uniformityPct,
      'chickCvPct': cvPct,
    }..removeWhere((_, value) => value == null);
    _chickWeightSamples[_activeChickWeightSampleIndex] = activeChickWeightSample
        .copyWith(
          resultSummaryJson: jsonEncode(summary),
          updatedAt: DateTime.now(),
        );

    final map = activeDraft.toMap();
    map['chickWeights'] = weightsJson;
    map['chickAvgWeight'] = avgWeight;
    map['chickUniformityPct'] = uniformityPct;
    map['chickCvPct'] = cvPct;
    map['updatedAt'] = DateTime.now().toIso8601String();
    _drafts[_activeHatchIndex] = AuditModel.fromMap(map);
    _syncStationSampleFromDraft(_activeHatchIndex);
    _markDirtyAndScheduleAutosave();
    notifyListeners();
  }

  bool get _isChicksContext => _context?.auditType == 'Chicks';

  List<StationSampleModel>? _primarySamplesForContext(
    List<StationSampleModel>? samples,
  ) {
    if (!_isChicksContext || samples == null) return samples;
    return samples
        .where(
          (sample) =>
              sample.sectorType != StationSampleModel.sectorChickWeights,
        )
        .toList();
  }

  List<StationSampleModel> _buildChickWeightSamplesForContext(
    List<StationSampleModel>? existingStationSamples,
  ) {
    if (!_isChicksContext || _drafts.isEmpty) return [];
    final existing =
        existingStationSamples
            ?.where(
              (sample) =>
                  sample.stationType == 'chicks' &&
                  sample.sectorType == StationSampleModel.sectorChickWeights,
            )
            .toList()
          ?..sort((a, b) => a.sampleIndex.compareTo(b.sampleIndex));
    if (existing != null && existing.isNotEmpty) {
      return [
        for (var i = 0; i < existing.length; i++)
          _normalizedChickWeightSample(
            existing[i],
            index: i,
            sampleMode: existing.first.sampleMode,
            groupKey: existing.first.groupKey,
          ),
      ];
    }
    return [
      _createChickWeightSample(0, StationSampleModel.sampleModePooled, null),
    ];
  }

  StationSampleModel _createChickWeightSample(
    int index,
    String sampleMode,
    String? groupKey,
  ) {
    final now = DateTime.now();
    final draft = activeDraft;
    final isComparison = sampleMode == StationSampleModel.sampleModeComparison;
    return StationSampleModel(
      id: _uuid.v4(),
      auditSessionId: _activeSessionId ?? draft.sessionId ?? '',
      stationType: 'chicks',
      sectorType: StationSampleModel.sectorChickWeights,
      sampleKind: StationSampleModel.sampleKindHouse,
      sampleMode: sampleMode,
      comparisonType: isComparison
          ? StationSampleModel.comparisonTypeHouse
          : null,
      sampleIndex: index + 1,
      sampleLabel: 'H${index + 1}',
      sampleType: StationSampleModel.sampleTypeDefault,
      groupKey: isComparison ? groupKey : null,
      groupLabel: isComparison ? 'House comparison' : null,
      houseNo: 'H${index + 1}',
      houseLabel: 'House ${index + 1}',
      calculatedBmkAgeDays: BmkAgeCalculator.calculateDays(
        currentFlockAgeDays: BmkAgeCalculator.currentFlockAgeDaysFromWeeks(
          _context?.flockAgeWeeks,
        ),
        auditDate: draft.date,
        legacyBmkAgeWeeks: _legacyBmkWeeksForDraft(draft),
        storageDays: draft.chickStorageDays,
        flockEntryDate: _context?.flockEntryDate,
      ),
      benchmarkBreed: _context?.breed,
      resultSummaryJson: _chickWeightResultSummaryJsonFromDraft(draft),
      createdAt: now,
      updatedAt: now,
    );
  }

  StationSampleModel _normalizedChickWeightSample(
    StationSampleModel sample, {
    required int index,
    required String sampleMode,
    required String? groupKey,
  }) {
    final isComparison = sampleMode == StationSampleModel.sampleModeComparison;
    return StationSampleModel(
      id: sample.id,
      auditSessionId: _activeSessionId ?? sample.auditSessionId,
      legacyAuditId: sample.legacyAuditId,
      stationType: 'chicks',
      sectorType: StationSampleModel.sectorChickWeights,
      sampleKind: StationSampleModel.sampleKindHouse,
      sampleMode: sampleMode,
      comparisonType: isComparison
          ? StationSampleModel.comparisonTypeHouse
          : null,
      sampleIndex: index + 1,
      sampleLabel: 'H${index + 1}',
      sampleType: sample.sampleType,
      breakoutType: sample.breakoutType,
      groupKey: isComparison ? groupKey : null,
      groupLabel: isComparison ? 'House comparison' : null,
      batchNo: sample.batchNo,
      houseNo: 'H${index + 1}',
      houseLabel: 'House ${index + 1}',
      hatchNo: sample.hatchNo,
      eggProductionDate: sample.eggProductionDate,
      settingDate: sample.settingDate,
      hatchDate: sample.hatchDate,
      storageDays: sample.storageDays,
      incubationDay: sample.incubationDay,
      calculatedBmkAgeDays: sample.calculatedBmkAgeDays,
      benchmarkBreed: sample.benchmarkBreed,
      benchmarkAgeDays: sample.benchmarkAgeDays,
      benchmarkSource: sample.benchmarkSource,
      benchmarkSnapshotJson: sample.benchmarkSnapshotJson,
      resultSummaryJson: sample.resultSummaryJson,
      notes: sample.notes,
      createdAt: sample.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  void _normalizeChickWeightSamples() {
    if (_chickWeightSamples.isEmpty) return;
    final mode = chickWeightSampleMode;
    final groupKey = mode == StationSampleModel.sampleModeComparison
        ? _activeChickWeightCompareGroupKey()
        : null;
    for (var i = 0; i < _chickWeightSamples.length; i++) {
      _chickWeightSamples[i] = _normalizedChickWeightSample(
        _chickWeightSamples[i],
        index: i,
        sampleMode: mode,
        groupKey: groupKey,
      );
    }
  }

  String _activeChickWeightCompareGroupKey() {
    for (final sample in _chickWeightSamples) {
      final key = sample.groupKey;
      if (key != null && key.isNotEmpty) return key;
    }
    return _uuid.v4();
  }

  List<StationSampleModel> _chickWeightSamplesForSave() {
    if (!_isChicksContext || _chickWeightSamples.isEmpty) return [];
    final sessionId = _activeSessionId ?? activeDraft.sessionId;
    if (sessionId == null || sessionId.isEmpty) return [];
    final samples = isChickWeightCompareMode
        ? _chickWeightSamples
        : [_chickWeightSamples.first];
    return [
      for (var i = 0; i < samples.length; i++)
        _normalizedChickWeightSample(
          samples[i],
          index: i,
          sampleMode: samples.first.sampleMode,
          groupKey: samples.first.groupKey,
        ).copyWith(auditSessionId: sessionId, updatedAt: DateTime.now()),
    ];
  }

  String? _chickWeightResultSummaryJsonFromDraft(AuditModel draft) {
    if (draft.chickWeights == null &&
        draft.chickAvgWeight == null &&
        draft.chickUniformityPct == null &&
        draft.chickCvPct == null) {
      return null;
    }
    final summary = <String, Object?>{
      'auditType': 'Chicks',
      'sectorType': StationSampleModel.sectorChickWeights,
      'chickWeights': draft.chickWeights == null
          ? null
          : _decodedWeights(draft.chickWeights!),
      'chickAvgWeight': draft.chickAvgWeight,
      'chickUniformityPct': draft.chickUniformityPct,
      'chickCvPct': draft.chickCvPct,
    }..removeWhere((_, value) => value == null);
    return jsonEncode(summary);
  }

  Object? _decodedWeights(String weightsJson) {
    try {
      return jsonDecode(weightsJson);
    } catch (_) {
      return null;
    }
  }

  List<StationSampleModel> _buildSamplesForDrafts({
    List<StationSampleModel>? existingStationSamples,
  }) {
    final builtSamples = List.generate(
      _drafts.length,
      (index) => _createSampleForDraft(_drafts[index], index),
    );
    if (existingStationSamples == null || existingStationSamples.isEmpty) {
      return builtSamples;
    }

    return List.generate(builtSamples.length, (index) {
      final draft = _drafts[index];
      final fresh = builtSamples[index];
      final existing = _matchingExistingSample(
        existingStationSamples,
        draft,
        fresh,
      );
      if (existing == null) return fresh;

      return existing.copyWith(
        legacyAuditId: fresh.legacyAuditId,
        stationType: fresh.stationType,
        sectorType: fresh.sectorType,
        sampleKind: fresh.sampleKind,
        sampleMode: fresh.sampleMode,
        comparisonType: fresh.comparisonType,
        sampleIndex: fresh.sampleIndex,
        sampleLabel: fresh.sampleLabel,
        sampleType: fresh.sampleType,
        breakoutType: fresh.breakoutType,
        groupKey: fresh.groupKey,
        groupLabel: fresh.groupLabel,
        batchNo: fresh.batchNo,
        houseNo: fresh.houseNo,
        houseLabel: fresh.houseLabel,
        hatchNo: fresh.hatchNo,
        storageDays: fresh.storageDays,
        incubationDay: fresh.incubationDay,
        setterNo: fresh.setterNo,
        hatcherNo: fresh.hatcherNo,
        calculatedBmkAgeDays: fresh.calculatedBmkAgeDays,
        benchmarkBreed: fresh.benchmarkBreed,
        benchmarkAgeDays: fresh.benchmarkAgeDays,
        resultSummaryJson: fresh.resultSummaryJson,
        updatedAt: fresh.updatedAt,
      );
    });
  }

  StationSampleModel? _matchingExistingSample(
    List<StationSampleModel> samples,
    AuditModel draft,
    StationSampleModel fresh,
  ) {
    for (final sample in samples) {
      if (sample.legacyAuditId == draft.id) return sample;
    }
    for (final sample in samples) {
      if (sample.sampleIndex == fresh.sampleIndex &&
          sample.stationType == fresh.stationType) {
        return sample;
      }
    }
    return null;
  }

  StationSampleModel _createSampleForDraft(AuditModel draft, int index) {
    final now = DateTime.now();
    return StationSampleModel(
      id: _uuid.v4(),
      auditSessionId: _activeSessionId ?? draft.sessionId ?? '',
      legacyAuditId: draft.id,
      stationType: StationSampleMapper.stationTypeForAuditType(draft.auditType),
      sectorType: _defaultSectorType(draft.auditType),
      sampleKind: _defaultSampleKind(draft.auditType),
      sampleMode: SampleMode.isCompare(draft.sampleMode)
          ? StationSampleModel.sampleModeComparison
          : StationSampleModel.sampleModePooled,
      comparisonType: _defaultComparisonType(draft.auditType, draft.sampleMode),
      sampleIndex: index + 1,
      sampleLabel: _sampleLabelForDraft(draft, index),
      sampleType: _defaultSampleType(draft.auditType, draft.ebBreakoutType),
      breakoutType: _defaultBreakoutType(draft.ebBreakoutType),
      groupKey: draft.compareGroupKey,
      groupLabel: _groupLabelForDraft(draft),
      batchNo: draft.hatchNumber.toString(),
      houseNo: _houseNoForDraft(draft, index),
      houseLabel: _houseLabelForDraft(draft, index),
      hatchNo: draft.hatchNumber.toString(),
      storageDays: _storageDaysForDraft(draft),
      incubationDay: draft.soIncubationAge ?? draft.hoIncubationAge,
      setterNo: draft.setterId ?? draft.soSetterId,
      hatcherNo: draft.hatcherId ?? draft.hoHatcherId,
      calculatedBmkAgeDays: BmkAgeCalculator.calculateDays(
        currentFlockAgeDays: BmkAgeCalculator.currentFlockAgeDaysFromWeeks(
          _context?.flockAgeWeeks,
        ),
        auditDate: draft.date,
        legacyBmkAgeWeeks: _legacyBmkWeeksForDraft(draft),
        storageDays: _storageDaysForDraft(draft),
        flockEntryDate: _context?.flockEntryDate,
      ),
      benchmarkBreed: _context?.breed ?? draft.soBreed ?? draft.hoBreed,
      resultSummaryJson: StationSampleMapper.resultSummaryJsonForAudit(draft),
      createdAt: draft.createdAt,
      updatedAt: now,
    );
  }

  void _syncStationSampleFromDraft(int index) {
    if (index < 0 || index >= _drafts.length) return;
    if (_stationSamples.length != _drafts.length) {
      _stationSamples = _buildSamplesForDrafts();
      return;
    }
    final existing = _stationSamples[index];
    final fresh = _createSampleForDraft(_drafts[index], index);
    final keepGeneratedHouseMetadata =
        _drafts[index].auditType == 'Egg' &&
        SampleMode.isCompare(_drafts[index].sampleMode);
    final keepGeneratedMachineMetadata =
        _drafts[index].auditType == 'Chicks' &&
        SampleMode.isCompare(_drafts[index].sampleMode);
    final keepGeneratedSetterMetadata =
        _drafts[index].auditType == 'Setters' &&
        SampleMode.isCompare(_drafts[index].sampleMode);
    final keepGeneratedSampleMetadata =
        keepGeneratedHouseMetadata ||
        keepGeneratedMachineMetadata ||
        keepGeneratedSetterMetadata;
    final next = fresh.copyWith(
      id: existing.id,
      auditSessionId: _activeSessionId ?? existing.auditSessionId,
      legacyAuditId: _drafts[index].id,
      sectorType: fresh.sectorType,
      sampleKind: fresh.sampleKind,
      comparisonType: keepGeneratedSampleMetadata
          ? fresh.comparisonType
          : existing.comparisonType ?? fresh.comparisonType,
      sampleLabel: keepGeneratedSampleMetadata
          ? fresh.sampleLabel
          : existing.sampleLabel,
      sampleType: existing.sampleType,
      breakoutType: existing.breakoutType,
      groupKey: _drafts[index].compareGroupKey ?? existing.groupKey,
      groupLabel: keepGeneratedSampleMetadata
          ? fresh.groupLabel
          : existing.groupLabel,
      batchNo: existing.batchNo,
      houseNo: keepGeneratedHouseMetadata ? fresh.houseNo : existing.houseNo,
      houseLabel: keepGeneratedHouseMetadata
          ? fresh.houseLabel
          : existing.houseLabel,
      hatchNo: existing.hatchNo,
      eggProductionDate: existing.eggProductionDate,
      settingDate: existing.settingDate,
      hatchDate: existing.hatchDate,
      setterNo: keepGeneratedSetterMetadata
          ? fresh.setterNo
          : existing.setterNo,
      notes: existing.notes,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );
    _stationSamples[index] = next;
  }

  StationSampleModel? _sampleForSave(int index, AuditModel draft) {
    final sessionId = _activeSessionId ?? draft.sessionId;
    if (sessionId == null || sessionId.isEmpty) return null;
    _syncStationSampleFromDraft(index);
    return _stationSamples[index].copyWith(
      auditSessionId: sessionId,
      legacyAuditId: draft.id,
      resultSummaryJson: StationSampleMapper.resultSummaryJsonForAudit(draft),
      updatedAt: DateTime.now(),
    );
  }

  void _applySamplePatchToDraft(int index) {
    if (index < 0 || index >= _drafts.length) return;
    final patch = StationSampleMapper.legacyAuditPatchForSample(
      _stationSamples[index],
    );
    final map = _drafts[index].toMap()..addAll(patch);
    _drafts[index] = AuditModel.fromMap(map);
  }

  String? _defaultComparisonType(String auditType, String sampleMode) {
    if (!SampleMode.isCompare(sampleMode)) return null;
    switch (auditType) {
      case 'Egg':
        return StationSampleModel.comparisonTypeHouse;
      case 'Chicks':
      case 'Setters':
      case 'Hatchers':
        return StationSampleModel.comparisonTypeMachine;
      case 'Hatch Analysis & Egg Breakouts':
        return StationSampleModel.comparisonTypeBatch;
      default:
        return null;
    }
  }

  String _defaultSectorType(String auditType) {
    return switch (auditType) {
      'Egg' => StationSampleModel.sectorEggQuality,
      'Chicks' => StationSampleModel.sectorChickQuality,
      'Hatch Analysis & Egg Breakouts' =>
        StationSampleModel.sectorHatchBreakout,
      'Setters' => StationSampleModel.sectorSetterOptimizing,
      'Hatchers' => StationSampleModel.sectorHatcherOptimizing,
      _ => StationSampleModel.sectorDefault,
    };
  }

  String _defaultSampleKind(String auditType) {
    return switch (auditType) {
      'Egg' => StationSampleModel.sampleKindHouse,
      'Chicks' ||
      'Setters' ||
      'Hatchers' => StationSampleModel.sampleKindMachine,
      'Hatch Analysis & Egg Breakouts' => StationSampleModel.sampleKindBatch,
      _ => StationSampleModel.sampleKindPooled,
    };
  }

  String _sampleLabelForDraft(AuditModel draft, int index) {
    if (draft.auditType == 'Egg' && SampleMode.isCompare(draft.sampleMode)) {
      return 'H${index + 1}';
    }
    if (draft.auditType == 'Chicks' && SampleMode.isCompare(draft.sampleMode)) {
      return _chickMachineSampleLabel(
        setterNo: draft.setterId ?? draft.soSetterId,
        hatcherNo: draft.hatcherId ?? draft.hoHatcherId,
        fallbackIndex: index + 1,
      );
    }
    if (draft.auditType == 'Setters' &&
        SampleMode.isCompare(draft.sampleMode)) {
      return _machineSampleLabel(
        draft.setterId ?? draft.soSetterId,
        prefix: 'S',
        fallbackIndex: index + 1,
      );
    }
    if (draft.auditType == 'Hatchers' &&
        SampleMode.isCompare(draft.sampleMode)) {
      return _machineSampleLabel(
        draft.hatcherId ?? draft.hoHatcherId,
        prefix: 'H',
        fallbackIndex: index + 1,
      );
    }
    return 'Sample ${index + 1}';
  }

  String? _groupLabelForDraft(AuditModel draft) {
    if (draft.compareGroupKey == null) return null;
    if (draft.auditType == 'Egg') return 'House comparison';
    if (draft.auditType == 'Chicks') return 'Machine comparison';
    if (draft.auditType == 'Setters') return 'Setter comparison';
    if (draft.auditType == 'Hatchers') return 'Hatcher comparison';
    return 'Comparison';
  }

  String _machineSampleLabel(
    String? rawValue, {
    required String prefix,
    required int fallbackIndex,
  }) {
    final raw = (rawValue ?? '').trim();
    if (raw.isEmpty) return '$prefix$fallbackIndex';
    final digits = RegExp(r'\d+').allMatches(raw).map((m) => m.group(0)).join();
    if (digits.isNotEmpty) return '$prefix$digits';
    final withoutPrefix = raw.toLowerCase().startsWith(prefix.toLowerCase())
        ? raw.substring(1).trim()
        : raw;
    return '$prefix$withoutPrefix';
  }

  String _chickMachineSampleLabel({
    required String? setterNo,
    required String? hatcherNo,
    required int fallbackIndex,
  }) {
    final setterLabel = _machineSampleLabel(
      setterNo,
      prefix: 'S',
      fallbackIndex: fallbackIndex,
    );
    final hatcherLabel = _machineSampleLabel(
      hatcherNo,
      prefix: 'H',
      fallbackIndex: fallbackIndex,
    );
    return '$setterLabel$hatcherLabel';
  }

  String _sampleLabelForMetadataUpdate({
    required AuditModel draft,
    required StationSampleModel sample,
    required String? setterNo,
    required String? hatcherNo,
  }) {
    final isChickMachineComparison =
        draft.auditType == 'Chicks' &&
        sample.sampleMode == StationSampleModel.sampleModeComparison;
    if (!isChickMachineComparison) return sample.sampleLabel;
    return _chickMachineSampleLabel(
      setterNo: setterNo,
      hatcherNo: hatcherNo,
      fallbackIndex: sample.sampleIndex,
    );
  }

  String? _houseNoForDraft(AuditModel draft, int index) {
    if (draft.auditType != 'Egg' || !SampleMode.isCompare(draft.sampleMode)) {
      return null;
    }
    return 'H${index + 1}';
  }

  String? _houseLabelForDraft(AuditModel draft, int index) {
    if (draft.auditType != 'Egg' || !SampleMode.isCompare(draft.sampleMode)) {
      return null;
    }
    return 'House ${index + 1}';
  }

  String _defaultSampleType(String auditType, String? breakoutType) {
    if (auditType == 'Chicks') {
      return StationSampleModel.sampleTypeChickQualityHatchedBatch;
    }
    if (auditType == 'Hatch Analysis & Egg Breakouts') {
      return switch (EggBreakoutType.fromStorageValue(breakoutType)) {
        EggBreakoutType.freshEggBreakout =>
          StationSampleModel.sampleTypeBreakoutFresh,
        EggBreakoutType.candledEggBreakout =>
          StationSampleModel.sampleTypeBreakoutCandled10d,
        EggBreakoutType.residueHatchDay =>
          StationSampleModel.sampleTypeBreakoutResidue21d,
      };
    }
    return StationSampleModel.sampleTypeDefault;
  }

  String? _defaultBreakoutType(String? breakoutType) {
    return EggBreakoutType.fromStorageValue(breakoutType).storageValue;
  }

  int? _storageDaysForDraft(AuditModel draft) {
    return draft.esEggStorageDays ??
        draft.chickStorageDays ??
        draft.haStorageDays ??
        draft.ebStorageDays;
  }

  int? _legacyBmkWeeksForDraft(AuditModel draft) {
    return draft.esEggBmkAge ??
        draft.chickBmkAge ??
        draft.haBmkAge ??
        draft.ebBmkAge;
  }

  Future<void> _savePanelTablesForSample(
    AuditModel draft,
    StationSampleModel sample,
  ) async {
    for (final tableName in _panelTablesForDraft(draft)) {
      await _savePanelTableWithSamples(tableName, draft, [sample]);
    }
  }

  Future<void> _savePanelTableWithSamples(
    String tableName,
    AuditModel draft,
    List<StationSampleModel> samples,
  ) async {
    if (samples.isEmpty) return;
    final panel = _panelRecordForSamples(tableName, draft, samples);
    final panelSamples = [
      for (final sample in samples)
        _panelSampleRecordForStationSample(
          tableName: tableName,
          panelId: panel.id,
          draft: draft,
          sample: sample,
        ),
    ];
    await _panelSampleRepository.savePanelWithSamples(
      panel: panel,
      samples: panelSamples,
    );
  }

  List<String> _panelTablesForDraft(AuditModel draft) {
    return switch (draft.auditType) {
      'Egg' => const ['egg_storage', 'egg_quality', 'egg_weights'],
      'Chicks' => const ['chick_pasgar', 'chick_yfbm', 'chick_cvt', 'chick_pm'],
      'Hatch Analysis & Egg Breakouts' => [
        switch (EggBreakoutType.fromStorageValue(draft.ebBreakoutType)) {
          EggBreakoutType.freshEggBreakout => 'fresh_egg_breakout',
          EggBreakoutType.candledEggBreakout => 'candled_egg_breakout',
          EggBreakoutType.residueHatchDay => 'residue_breakout',
        },
      ],
      'Setters' => const ['setter_optimizing'],
      'Hatchers' => const ['hatcher_optimizing'],
      _ => const [],
    };
  }

  PanelRecord _panelRecordForSamples(
    String tableName,
    AuditModel draft,
    List<StationSampleModel> samples,
  ) {
    final compareLayer = _compareLayerForPanel(tableName, samples);
    final mode = compareLayer == null
        ? PanelRecord.modePool
        : PanelRecord.modeCompare;
    return PanelRecord(
      id: '${samples.first.auditSessionId}:$tableName:${draft.id}',
      tableName: tableName,
      sessionId: samples.first.auditSessionId,
      auditId: draft.id,
      customerId: draft.customerId,
      flockId: _blankToNull(draft.flockId),
      date: draft.date,
      hatcheryId: _blankToNull(_context?.hatcheryId),
      breed: _context?.breed ?? draft.soBreed ?? draft.hoBreed,
      flockAgeWeeks: _context?.flockAgeWeeks,
      mode: mode,
      compareLayer: compareLayer,
      notes: draft.notes,
      metricsJson: _compactJson(draft.toMap()),
      createdAt: draft.createdAt,
      updatedAt: draft.updatedAt,
    );
  }

  PanelSampleRecord _panelSampleRecordForStationSample({
    required String tableName,
    required String panelId,
    required AuditModel draft,
    required StationSampleModel sample,
  }) {
    final scopeType = _scopeTypeForPanel(tableName, sample);
    return PanelSampleRecord(
      id: '$panelId:${sample.id}',
      panelId: panelId,
      scopeType: scopeType,
      scopeLabel: _scopeLabelForSample(scopeType, sample),
      sampleIndex: sample.sampleIndex,
      houseId: scopeType == SamplingLayer.house
          ? _blankToNull(sample.houseNo)
          : null,
      houseName: scopeType == SamplingLayer.house
          ? _blankToNull(sample.houseLabel)
          : null,
      setterId:
          scopeType == SamplingLayer.setter ||
              scopeType == SamplingLayer.setterHatcher
          ? _blankToNull(sample.setterNo)
          : null,
      hatcherId:
          scopeType == SamplingLayer.hatcher ||
              scopeType == SamplingLayer.setterHatcher
          ? _blankToNull(sample.hatcherNo)
          : null,
      sampleSize: _sampleSizeForPanel(tableName, draft),
      summaryJson: sample.resultSummaryJson,
      rawJson: _compactJson(sample.toMap()),
      notes: sample.notes,
      createdAt: sample.createdAt,
      updatedAt: sample.updatedAt,
    );
  }

  SamplingLayer? _compareLayerForPanel(
    String tableName,
    List<StationSampleModel> samples,
  ) {
    for (final sample in samples) {
      if (sample.sampleMode != StationSampleModel.sampleModeComparison) {
        continue;
      }
      final scope = _scopeTypeForPanel(tableName, sample);
      if (scope != SamplingLayer.pool) return scope;
    }
    return null;
  }

  SamplingLayer _scopeTypeForPanel(
    String tableName,
    StationSampleModel sample,
  ) {
    final allowed = PanelSampleSchema.byTable(tableName).allowedLayers;
    if (sample.sampleMode != StationSampleModel.sampleModeComparison) {
      return SamplingLayer.pool;
    }
    if (allowed.contains(SamplingLayer.house) && _hasText(sample.houseNo)) {
      return SamplingLayer.house;
    }
    if (allowed.contains(SamplingLayer.setterHatcher) &&
        _hasText(sample.setterNo) &&
        _hasText(sample.hatcherNo)) {
      return SamplingLayer.setterHatcher;
    }
    if (allowed.contains(SamplingLayer.setter) && _hasText(sample.setterNo)) {
      return SamplingLayer.setter;
    }
    if (allowed.contains(SamplingLayer.hatcher) && _hasText(sample.hatcherNo)) {
      return SamplingLayer.hatcher;
    }
    return SamplingLayer.pool;
  }

  String _scopeLabelForSample(
    SamplingLayer scopeType,
    StationSampleModel sample,
  ) {
    return switch (scopeType) {
      SamplingLayer.house =>
        _blankToNull(sample.houseLabel) ??
            _blankToNull(sample.houseNo) ??
            sample.sampleLabel,
      SamplingLayer.setterHatcher =>
        '${sample.setterNo ?? ''}/${sample.hatcherNo ?? ''}',
      SamplingLayer.setter =>
        _blankToNull(sample.setterNo) ?? sample.sampleLabel,
      SamplingLayer.hatcher =>
        _blankToNull(sample.hatcherNo) ?? sample.sampleLabel,
      SamplingLayer.tray || SamplingLayer.trolley => sample.sampleLabel,
      SamplingLayer.pool => 'Random',
    };
  }

  int? _sampleSizeForPanel(String tableName, AuditModel draft) {
    return switch (tableName) {
      'egg_quality' => draft.esUvSampleSize,
      'egg_weights' => draft.esEggSampleSize,
      'chick_pasgar' => draft.pasgarSampleSize,
      'chick_weights' => draft.chickSampleSize,
      'chick_cvt' => draft.cvtSampleSize,
      'chick_pm' => draft.pmSampleSize,
      'fresh_egg_breakout' ||
      'candled_egg_breakout' ||
      'residue_breakout' => draft.ebTraySize ?? draft.haTotalEggsSet,
      _ => null,
    };
  }

  String _compactJson(Map<String, Object?> value) {
    final compact = Map<String, Object?>.from(value)
      ..removeWhere((_, entry) => entry == null);
    return jsonEncode(compact);
  }

  bool _hasText(String? value) => _blankToNull(value) != null;

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
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

  Future<void> _runFinalSaveSideEffects(AuditModel audit, String action) async {
    try {
      await _logAuditChange(audit, action);
    } catch (e) {
      safeDebugLog('Error logging audit save', error: e);
    }

    try {
      await _checkThresholdsAndAlert(audit);
    } catch (e) {
      safeDebugLog('Error checking audit thresholds', error: e);
    }

    unawaited(
      _supabaseService.syncAudit(audit.toMap()).catchError((Object e) {
        safeDebugLog('Error syncing audit', error: e);
      }),
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
