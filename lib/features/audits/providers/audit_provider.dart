import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/constants/app_thresholds.dart';
import '../../../core/security/safe_debug_log.dart';
import '../../../core/utils/bmk_age_calculator.dart';
import '../../../data/mappers/station_sample_mapper.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/sample_mode.dart';
import '../../../data/models/station_sample_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/activity_log_repository.dart';
import '../../../data/repositories/audit_repository.dart';
import '../../../data/repositories/benchmark_lookup.dart';
import '../../../data/repositories/egg_grading_repository.dart';
import '../../../data/repositories/panel_sample_repository.dart';
import '../../../data/repositories/station_sample_repository.dart';
import '../../../providers/app_provider.dart';
import '../../../services/notifications/notification_service.dart';
import '../../../services/supabase/supabase_service.dart';
import '../models/audit_context.dart';
import '../models/egg_breakout_tray_rollup.dart';
import '../models/egg_grading.dart';
import '../models/egg_breakout_sample.dart';
import '../models/residue_batch_metrics.dart';
import '../models/station_completion_validation.dart';
import '../logic/audit_meaningful_data.dart';
import '../logic/audit_value_parsing.dart';
import '../logic/panel_value_builders.dart';
import '../services/audit_panel_save_coordinator.dart';
import 'package:uuid/uuid.dart';

export '../models/audit_context.dart' show AuditContext;

class AuditProvider extends ChangeNotifier {
  AuditProvider({
    AuditRepository? repository,
    StationSampleRepository? stationSampleRepository,
    PanelSampleRepository? panelSampleRepository,
    ActivityLogRepository? activityLogRepository,
    BenchmarkLookup? benchmarkLookup,
    SupabaseService? supabaseService,
    EggGradingRepository? eggGradingRepository,
    Duration autosaveDebounceDuration = defaultAutosaveDebounceDuration,
    bool autosaveEnabled = true,
  }) : _panelSampleRepository =
           panelSampleRepository ?? PanelSampleRepository(),
       _activityLogRepository =
           activityLogRepository ?? ActivityLogRepository(),
       _benchmarkLookup = benchmarkLookup ?? BenchmarkLookup(),
       _autosaveDebounceDuration = autosaveDebounceDuration,
       _autosaveEnabled = autosaveEnabled {
    _panelSaveCoordinator = AuditPanelSaveCoordinator(
      panelSampleRepository: _panelSampleRepository,
      benchmarkLookup: _benchmarkLookup,
      context: () => _context,
      activeSessionId: () => _activeSessionId,
      stationSamples: () => _stationSamples,
      chickWeightSamples: () => _chickWeightSamples,
      eggGradingRepository: eggGradingRepository,
    );
  }

  static const Duration defaultAutosaveDebounceDuration = Duration(seconds: 1);

  final PanelSampleRepository _panelSampleRepository;
  final ActivityLogRepository _activityLogRepository;
  final BenchmarkLookup _benchmarkLookup;
  final Duration _autosaveDebounceDuration;
  final bool _autosaveEnabled;
  final Uuid _uuid = const Uuid();

  /// Owns every panel-table write/delete/prune the save path performs.
  late final AuditPanelSaveCoordinator _panelSaveCoordinator;

  // State
  AuditContext? _context;
  List<AuditModel> _drafts = [];
  List<StationSampleModel> _stationSamples = [];
  List<StationSampleModel> _chickWeightSamples = [];
  String _eggQualityScopeKind = StationSampleModel.sampleKindHouse;
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
  String? _saveError;
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
  bool get isEggQualityHouseScopeActive =>
      _context?.auditType == 'Egg' &&
      isCompareMode &&
      _stationSamples.any(
        (sample) =>
            sample.sampleMode == StationSampleModel.sampleModeComparison &&
            sample.sampleKind == StationSampleModel.sampleKindHouse,
      );
  bool get isChickQualityMachineScopeActive =>
      _context?.auditType == 'Chicks' && isCompareMode;
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

  bool stationScopeHasEnteredResults(int index) {
    if (index < 0 || index >= _drafts.length) return false;
    final draft = _drafts[index];
    return switch (draft.auditType) {
      'Egg' => hasMeaningfulEggQualityData(draft),
      'Chicks' => hasChickQualityScopeResults(draft),
      'Hatch Analysis & Egg Breakouts' => hasHatchScopeResults(draft),
      'Setters' => hasSetterScopeResults(draft),
      'Hatchers' => hasHatcherScopeResults(draft),
      _ => false,
    };
  }

  bool chickWeightScopeHasEnteredResults(int index) {
    if (index < 0 || index >= _chickWeightSamples.length) return false;
    return hasMeaningfulChickWeightSample(
      chickWeightValuesForSample(
        _chickWeightSamples[index],
        fallback: activeDraft,
      ),
    );
  }

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
    _saveError = null;
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
    final primaryExistingSamples = _primarySamplesForContext(
      existingStationSamples,
    );
    _eggQualityScopeKind = _initialEggQualityScopeKind(
      context,
      primaryExistingSamples,
    );
    _stationSamples = _buildSamplesForDrafts(
      existingStationSamples: primaryExistingSamples,
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
    final isHatcherOptimizing = _context!.auditType == 'Hatchers';
    final isMachineStation =
        _context!.auditType == 'Setters' || _context!.auditType == 'Hatchers';
    final setterId = isHatchBreakout
        ? '$hatchNumber'
        : isSetterOptimizing
        ? (hatchNumber == 1 && _context!.setterId?.trim().isNotEmpty == true
              ? _context!.setterId
              : 'S')
        : _context!.setterId;
    final hatcherId = isHatchBreakout
        ? '$hatchNumber'
        : isHatcherOptimizing
        ? (hatchNumber == 1 && _context!.hatcherId?.trim().isNotEmpty == true
              ? _context!.hatcherId
              : 'H')
        : _context!.hatcherId;
    return AuditModel(
      id: _uuid.v4(),
      auditType: _context!.auditType,
      customerId: _context!.customerId,
      flockId: isMachineStation ? null : _context!.flockId,
      date: DateTime.parse(_context!.date),
      hatchNumber: hatchNumber,
      status: 'active',
      createdBy: _currentUser?.id ?? '',
      createdAt: now,
      updatedAt: now,
      houseId: isHatchBreakout ? '1' : null,
      setterId: setterId,
      hatcherId: hatcherId,
      sessionId: _activeSessionId,
      sampleMode: SampleMode.pool,
      esEggStorageDays: _context!.auditType == 'Egg' ? 0 : null,
      esEggQualityStorageDays: _context!.auditType == 'Egg' ? 0 : null,
      chickStorageDays: _context!.auditType == 'Chicks' ? 0 : null,
      haTotalEggsSet: isHatchBreakout ? 19200 : null,
      haStorageDays: isHatchBreakout ? 0 : null,
      ebStorageDays: isHatchBreakout ? 0 : null,
      soBreed: null,
      soSetterId: isSetterOptimizing ? setterId : null,
      soIncubationAge: _context!.auditType == 'Setters' ? 1 : null,
      soIncubationHours: _context!.auditType == 'Setters' ? 0 : null,
      soMachineType: isSetterOptimizing ? 'Multi' : null,
      soBatchSize: isSetterOptimizing ? 19200 : null,
      soBatchCount: isSetterOptimizing ? 1 : null,
      soTotalEggsSet: isSetterOptimizing ? 19200 : null,
      soEstSamplesJson: isSetterOptimizing
          ? _defaultSetterEstSamplesJson()
          : null,
      hoBreed: null,
      hoHatcherId: isHatcherOptimizing ? hatcherId : null,
      hoIncubationAge: _context!.auditType == 'Hatchers' ? 18 : null,
      hoIncubationHours: _context!.auditType == 'Hatchers' ? 0 : null,
    );
  }

  String _defaultSetterEstSamplesJson() {
    return jsonEncode([
      {
        'id': _uuid.v4(),
        'breed': 'Ross308',
        'incubationAge': 1,
        'incubationHours': 0,
        'estReadings': <String, double>{},
        'estPhotos': <String, String>{},
        'estAvg': null,
        'estCv': null,
      },
    ]);
  }

  // Update a field in the active draft
  void updateField(String key, dynamic value) {
    if (_isReadOnly) return;

    updateHatchField(_activeHatchIndex, key, value);
  }

  /// Grading counts for the active sample. Held on the draft as JSON, which is
  /// already per-sample, so switching houses cannot move them.
  Map<String, int> get activeGradingCounts {
    return EggGradingSummary.fromJson(
      activeDraft.esGradingDefectsJson,
      sampleSize: activeDraft.esGradingSampleSize ?? 0,
      rejectedCount: activeDraft.esGradingRejectedCount ?? 0,
    ).counts;
  }

  void updateGradingCounts(Map<String, int> counts) {
    if (_isReadOnly) return;
    final summary = EggGradingSummary.fromCounts(
      sampleSize: activeDraft.esGradingSampleSize ?? 0,
      rejectedCount: activeDraft.esGradingRejectedCount ?? 0,
      counts: counts,
    );
    final map = activeDraft.toMap()
      ..['esGradingDefectsJson'] = summary.encodedJson
      ..['updatedAt'] = DateTime.now().toIso8601String();
    _drafts[_activeHatchIndex] = AuditModel.fromMap(map);
    _syncStationSampleFromDraft(_activeHatchIndex);
    _markDirtyAndScheduleAutosave();
    notifyListeners();
  }

  void updateHatchField(int hatchIndex, String key, dynamic value) {
    if (_isReadOnly) return;
    if (hatchIndex < 0 || hatchIndex >= _drafts.length) return;

    final updatedDraft = _updateAuditField(_drafts[hatchIndex], key, value);
    _drafts[hatchIndex] = updatedDraft;
    if (_isSharedEggStorageField(key)) {
      for (var i = 0; i < _drafts.length; i++) {
        if (i == hatchIndex) continue;
        _drafts[i] = _updateAuditField(_drafts[i], key, value);
        _syncStationSampleFromDraft(i);
      }
    }
    _syncStationSampleFromDraft(hatchIndex);
    _markDirtyAndScheduleAutosave();

    notifyListeners();
  }

  bool _isSharedEggStorageField(String key) {
    return _context?.auditType == 'Egg' &&
        _sharedEggStorageFields.contains(key);
  }

  static const Set<String> _sharedEggStorageFields = {
    'esCo2',
    'esCo2Photo',
    'esTurningTimes',
    'esEggStorageDays',
    'esEggQualityStorageDays',
    'esEggBmkAge',
    'esEggBmkWeight',
    'es_estReadingsJson',
    'es_estPhotosJson',
    'es_estAvg',
    'es_estCv',
    'es_traySpacing',
    'es_coolerProximity',
    'es_wallProximity',
    'es_condensation',
  };

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
    final preservedEggStoragePatch =
        _shouldPreserveEggStoragePatchForMetadata(fields)
        ? _sharedEggStoragePatch(draft)
        : null;
    var sample = activeStationSample;
    final hasHouseNo = fields.containsKey('houseNo');
    final houseNo = fields['houseNo'] as String? ?? sample.houseNo;
    final fallbackScopeSerial = _scopeSerialForSample(sample, houseNo: houseNo);
    final houseLabel =
        fields['houseLabel'] as String? ??
        (hasHouseNo &&
                sample.sampleMode == StationSampleModel.sampleModeComparison
            ? _houseScopeLabelForNo(
                houseNo: houseNo,
                fallbackIndex: fallbackScopeSerial,
              )
            : sample.houseLabel);
    final setterNo = fields['setterNo'] as String? ?? sample.setterNo;
    final hatcherNo = fields['hatcherNo'] as String? ?? sample.hatcherNo;
    final eggProductionDate =
        fields['eggProductionDate'] as DateTime? ?? sample.eggProductionDate;
    final storageDays =
        fields['storageDays'] as int? ?? sample.storageDays ?? 0;
    final calculatedBmkAgeDays =
        fields['calculatedBmkAgeDays'] as int? ??
        BmkAgeCalculator.calculateDays(
          currentFlockAgeDays: BmkAgeCalculator.currentFlockAgeDaysFromWeeks(
            _context?.flockAgeWeeks,
          ),
          auditDate: draft.date,
          eggProductionDate: eggProductionDate,
          legacyBmkAgeWeeks: legacyBmkWeeksForDraft(draft),
          storageDays: storageDays,
          flockEntryDate: _context?.flockEntryDate,
        );
    sample = sample.copyWith(
      sampleLabel:
          fields['sampleLabel'] as String? ??
          _sampleLabelForMetadataUpdate(
            draft: draft,
            sample: sample,
            houseNo: houseNo,
            setterNo: setterNo,
            hatcherNo: hatcherNo,
            fallbackIndex: fallbackScopeSerial,
          ),
      batchNo: fields['batchNo'] as String? ?? sample.batchNo,
      houseNo: houseNo,
      houseLabel: houseLabel,
      hatchNo: fields['hatchNo'] as String? ?? sample.hatchNo,
      eggProductionDate: eggProductionDate,
      settingDate: fields['settingDate'] as DateTime? ?? sample.settingDate,
      hatchDate: fields['hatchDate'] as DateTime? ?? sample.hatchDate,
      storageDays: storageDays,
      incubationDay: fields['incubationDay'] as int? ?? sample.incubationDay,
      setterNo: setterNo,
      hatcherNo: hatcherNo,
      notes: fields['notes'] as String? ?? sample.notes,
      calculatedBmkAgeDays: calculatedBmkAgeDays,
      updatedAt: now,
    );
    _stationSamples[_activeHatchIndex] = sample;
    _applySamplePatchToDraft(_activeHatchIndex);
    if (preservedEggStoragePatch != null) {
      final map = _drafts[_activeHatchIndex].toMap()
        ..addAll(preservedEggStoragePatch);
      _drafts[_activeHatchIndex] = AuditModel.fromMap(map);
    }
    _markDirtyAndScheduleAutosave();
    notifyListeners();
  }

  bool _shouldPreserveEggStoragePatchForMetadata(Map<String, dynamic> fields) {
    if (_context?.auditType != 'Egg') return false;
    const identityFields = {
      'sampleLabel',
      'batchNo',
      'houseNo',
      'houseLabel',
      'hatchNo',
      'setterNo',
      'hatcherNo',
      'notes',
    };
    return fields.keys.every(identityFields.contains);
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
        _saveError = null;
        if (_changeVersion > saveVersion && _isDirty) {
          _scheduleAutosave();
        }
      } else {
        _saveError = 'Could not save this station. Try again.';
      }
      return saved;
    } finally {
      _saveFuture = null;
    }
  }

  Future<bool> clearStationData(String stationKey) async {
    if (_isReadOnly) return false;
    final currentContext = _context;
    if (currentContext == null) return false;
    final tables = _panelTablesForStationKey(stationKey);
    if (tables.isEmpty) return false;

    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    final autosaveInFlight = _autosaveFuture;
    if (autosaveInFlight != null) {
      await autosaveInFlight;
    }
    final saveInFlight = _saveFuture;
    if (saveInFlight != null) {
      await saveInFlight;
    }

    final sessionId = _activeSessionId ?? activeDraft.sessionId;
    final readOnly = _isReadOnly;
    final currentUser = _currentUser;
    _isLoading = true;
    _notifyListeners();

    try {
      if (sessionId != null && sessionId.isNotEmpty) {
        for (final table in tables) {
          await _panelSampleRepository.deleteRowsBySessionId(table, sessionId);
        }
      }
      initialize(
        currentContext,
        readOnly: readOnly,
        currentUser: currentUser,
        sessionId: sessionId,
        notify: false,
      );
      return true;
    } catch (e) {
      safeDebugLog('Error clearing audit station', error: e);
      return false;
    } finally {
      _isLoading = false;
      _notifyListeners();
    }
  }

  List<String> _panelTablesForStationKey(String stationKey) {
    return switch (stationKey) {
      'egg' => const ['egg_storage', 'egg_quality'],
      'chicks' => const ['chick_quality', 'chick_weights'],
      'hatch_analysis_egg_breakouts' => const [
        'fresh_egg_breakout',
        'candled_egg_breakout',
        'residue_breakout',
      ],
      'setters' => const ['setter_optimizing'],
      'hatchers' => const ['hatcher_optimizing'],
      _ => const [],
    };
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
      final panelSavePairs = <PanelSavePair>[];
      for (var i = 0; i < draftsToSave.length; i++) {
        final draft = runFinalSaveSideEffects
            ? _asStatus(draftsToSave[i], 'active')
            : _asStatus(draftsToSave[i], 'draft');
        savedDrafts.add(draft);
        if (runFinalSaveSideEffects) {
          if (markAllTabsSaved) {
            _savedTabs[i] = {0, 1, 2, 3, 4};
          } else if (tabIndex != null) {
            _savedTabs.putIfAbsent(i, () => {}).add(tabIndex);
          }
          finalSaveSideEffects.add((audit: draft, action: 'save'));
        }

        final sample = samplesToSave[i];
        if (sample != null) {
          panelSavePairs.add((draft: draft, sample: sample));
          if (i < _stationSamples.length) {
            _stationSamples[i] = sample;
          }
        }
      }
      await _panelSaveCoordinator.savePanelTables(
        panelSavePairs: panelSavePairs,
        draftsToSave: draftsToSave,
        removedStationSampleIds: removedStationSampleIds,
      );
      for (var i = 0; i < chickWeightSamplesToSave.length; i++) {
        final sample = chickWeightSamplesToSave[i];
        if (i < _chickWeightSamples.length) {
          _chickWeightSamples[i] = sample;
        }
      }
      if (savedDrafts.isNotEmpty && chickWeightSamplesToSave.isNotEmpty) {
        await _panelSaveCoordinator.saveChickWeightPanels(
          draft: savedDrafts.first,
          samplesToSave: chickWeightSamplesToSave,
        );
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
        'label': 'Gizzard Erosions',
        'count': a.pmGizzardErosionsCount,
        'severity': a.pmGizzardErosionsSeverity,
      },
      {
        'label': 'Air Sac Caseations',
        'count': a.pmAirSacCaseationsCount,
        'severity': a.pmAirSacCaseationsSeverity,
      },
      {
        'label': 'Urolithiasis (Urate Deposits)',
        'count': a.pmUrolithiasisCount,
        'severity': a.pmUrolithiasisSeverity,
      },
      {
        'label': 'Nephritis',
        'count': a.pmNephritisCount,
        'severity': a.pmNephritisSeverity,
      },
      {
        'label': 'General Septicemia',
        'count': a.pmGeneralSepticemiaCount,
        'severity': a.pmGeneralSepticemiaSeverity,
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

    for (final lesion in decodedMaps(a.pmOtherLesionsJson)) {
      final name = (lesion['name'] as String? ?? '').trim();
      final count = asInt(lesion['count']);
      final severity = (lesion['severity'] as String? ?? '').trim();
      if ((count ?? 0) > 0) {
        if (name.isEmpty) {
          errors.add('Other lesion name is required when count > 0');
        }
        if (severity.isEmpty) {
          final label = name.isEmpty ? 'Other lesion' : name;
          errors.add('$label requires severity when count > 0');
        }
      }
    }

    return errors;
  }

  StationCompletionValidation validateStationCompletion(String stationKey) {
    if (_saveError != null || _autosaveError != null) {
      return StationCompletionValidation.failed(stationKey);
    }
    if (_drafts.any(
      (draft) => hasCoreStationData(
        draft,
        hasAnyMeaningfulChickWeightSample: _chickWeightSamples.any(
          (sample) => hasMeaningfulChickWeightSample(
            chickWeightValuesForSample(sample, fallback: draft),
          ),
        ),
        contextSetterId: _context?.setterId,
        contextHatcherId: _context?.hatcherId,
      ),
    )) {
      return StationCompletionValidation.complete(stationKey);
    }
    if (_drafts.any(
          (draft) => hasAnyMeaningfulStationData(
            draft,
            hasAnyMeaningfulChickWeightSample: _chickWeightSamples.any(
              (sample) => hasMeaningfulChickWeightSample(
                chickWeightValuesForSample(sample, fallback: draft),
              ),
            ),
            contextSetterId: _context?.setterId,
            contextHatcherId: _context?.hatcherId,
          ),
        ) ||
        _drafts.any(treatBlankDraftAsSavedIncomplete)) {
      return StationCompletionValidation.savedButIncomplete(stationKey);
    }
    return StationCompletionValidation.emptyOrDiscarded(stationKey);
  }

  // Add a new hatch to the session
  void addHatch() {
    addSample();
  }

  void addEggQualityScopeSample(String sampleKind) {
    if (_isReadOnly) return;
    if (_context?.auditType != 'Egg') {
      addSample();
      return;
    }

    _eggQualityScopeKind = StationSampleModel.sampleKindHouse;
    final wasCompareMode = isCompareMode;
    if (!wasCompareMode) {
      setStationSampleMode(StationSampleModel.sampleModeComparison);
      updateSampleMetadata({'houseNo': 'H', 'houseLabel': 'House'});
      return;
    }

    addSample();
    updateSampleMetadata({'houseNo': 'H', 'houseLabel': 'House'});
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
    if (_context?.auditType == 'Egg') {
      map.addAll(_sharedEggStoragePatch(activeDraft));
    }
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

  void addChickQualityMachineScopeSample() {
    if (_isReadOnly || !_isChicksContext) return;
    final wasPooled = !isCompareMode;
    if (wasPooled) {
      setStationSampleMode(StationSampleModel.sampleModeComparison);
    } else {
      addSample();
    }

    updateSampleMetadata({
      'houseNo': '',
      'houseLabel': '',
      'setterNo': 'S',
      'hatcherNo': 'H',
    });
  }

  void removeActiveChickQualityMachineScopeSample() {
    if (_isReadOnly || !_isChicksContext || !isCompareMode) return;
    if (_drafts.length <= 1) {
      setStationSampleMode(StationSampleModel.sampleModePooled);
      return;
    }
    removeActiveSample();
  }

  Map<String, dynamic> _sharedEggStoragePatch(AuditModel source) {
    final sourceMap = source.toMap();
    return {
      for (final key in _sharedEggStorageFields)
        if (sourceMap.containsKey(key)) key: sourceMap[key],
    };
  }

  void removeActiveHatch() {
    removeActiveSample();
  }

  void removeActiveEggQualityScopeSample(String sampleKind) {
    if (_isReadOnly) return;
    if (_context?.auditType != 'Egg') {
      removeActiveSample();
      return;
    }

    _removeSelectedEggQualityHouse();
  }

  void _removeSelectedEggQualityHouse() {
    if (!isCompareMode) return;

    final activeHouseKey = blankToNull(activeStationSample.houseNo);
    final houseIndex = _selectedEggQualityHouseIndex(activeHouseKey);
    if (houseIndex == -1) {
      removeActiveSample();
      return;
    }

    _removeEggQualityScopeIndexes({houseIndex});
  }

  int _selectedEggQualityHouseIndex(String? activeHouseKey) {
    if (activeStationSample.sampleKind == StationSampleModel.sampleKindHouse) {
      return _activeHatchIndex;
    }

    if (activeHouseKey == null) return -1;
    return _stationSamples.indexWhere(
      (sample) =>
          sample.sampleKind == StationSampleModel.sampleKindHouse &&
          (blankToNull(sample.houseNo) ?? blankToNull(sample.sampleLabel)) ==
              activeHouseKey,
    );
  }

  void _removeEggQualityScopeIndexes(Set<int> indexesToRemove) {
    if (indexesToRemove.isEmpty) return;

    final orderedIndexes = indexesToRemove.toList()..sort();
    for (final index in orderedIndexes) {
      _removedStationSampleIds.add(_stationSamples[index].id);
      _removedLegacyAuditIds.add(_drafts[index].id);
    }

    final retainedDrafts = <AuditModel>[];
    final retainedSamples = <StationSampleModel>[];
    for (var i = 0; i < _drafts.length; i++) {
      if (indexesToRemove.contains(i)) continue;
      retainedDrafts.add(_drafts[i]);
      retainedSamples.add(_stationSamples[i]);
    }

    if (retainedDrafts.isEmpty) {
      _resetEggQualityToPooled(activeDraft);
      _markDirtyAndScheduleAutosave();
      notifyListeners();
      return;
    }

    final firstRemovedIndex = orderedIndexes.first;
    _drafts = retainedDrafts;
    _stationSamples = retainedSamples;
    _activeHatchIndex = firstRemovedIndex.clamp(0, _drafts.length - 1).toInt();
    final keepsEggQualityScope =
        _context?.auditType == 'Egg' &&
        retainedSamples.any(
          (sample) => sample.sampleKind == StationSampleModel.sampleKindHouse,
        );
    final legacyMode = keepsEggQualityScope || _drafts.length > 1
        ? SampleMode.compare
        : SampleMode.pool;
    if (legacyMode == SampleMode.pool) {
      _eggQualityScopeKind = StationSampleModel.sampleKindHouse;
    }
    final compareGroupKey = legacyMode == SampleMode.compare
        ? _activeCompareGroupKey()
        : null;

    for (var i = 0; i < _drafts.length; i++) {
      final map = _drafts[i].toMap();
      map['sampleMode'] = legacyMode;
      map['compareGroupKey'] = compareGroupKey;
      map['hatchNumber'] = legacyMode == SampleMode.pool ? 1 : i + 1;
      map['updatedAt'] = DateTime.now().toIso8601String();
      _drafts[i] = AuditModel.fromMap(map);
      _syncStationSampleFromDraft(i);
    }

    final nextSavedTabs = <int, Set<int>>{};
    for (final entry in _savedTabs.entries) {
      if (indexesToRemove.contains(entry.key)) continue;
      final removedBefore = indexesToRemove
          .where((index) => index < entry.key)
          .length;
      nextSavedTabs[entry.key - removedBefore] = entry.value;
    }
    _savedTabs
      ..clear()
      ..addAll(nextSavedTabs);
    _markDirtyAndScheduleAutosave();
    notifyListeners();
  }

  void _resetEggQualityToPooled(AuditModel source) {
    final retainedDraftMap = source.toMap()
      ..addAll(_sharedEggStoragePatch(source))
      ..['sampleMode'] = SampleMode.pool
      ..['compareGroupKey'] = null
      ..['hatchNumber'] = 1
      ..['updatedAt'] = DateTime.now().toIso8601String();

    _drafts = [AuditModel.fromMap(retainedDraftMap)];
    _activeHatchIndex = 0;
    _eggQualityScopeKind = StationSampleModel.sampleKindHouse;
    _stationSamples = [
      _createSampleForDraft(
        _drafts.first,
        0,
        eggQualityScopeKind: StationSampleModel.sampleKindHouse,
      ),
    ];
    _savedTabs.clear();
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
    final keepsEggHouseScope =
        _context?.auditType == 'Egg' &&
        _stationSamples.any(
          (sample) => sample.sampleKind == StationSampleModel.sampleKindHouse,
        );
    final legacyMode = _drafts.length == 1 && !keepsEggHouseScope
        ? SampleMode.pool
        : SampleMode.compare;
    final compareGroupKey = legacyMode == SampleMode.compare
        ? _activeCompareGroupKey()
        : null;

    for (var i = 0; i < _drafts.length; i++) {
      final map = _drafts[i].toMap();
      map['sampleMode'] = legacyMode;
      map['compareGroupKey'] = compareGroupKey;
      map['hatchNumber'] = legacyMode == SampleMode.pool ? 1 : i + 1;
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
      safeDebugLog(
        'Legacy audit edit requested after panel-only cutover',
        error: auditId,
      );
    } catch (e) {
      safeDebugLog('Error loading audit', error: e);
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
    final wasPooled = !isChickWeightCompareMode;
    if (wasPooled) {
      setChickWeightSampleMode(StationSampleModel.sampleModeComparison);
    } else {
      final mode = StationSampleModel.sampleModeComparison;
      final groupKey = _activeChickWeightCompareGroupKey();
      _chickWeightSamples.add(
        _createChickWeightSample(
          _chickWeightSamples.length,
          mode,
          groupKey,
          inheritDraftResult: false,
        ),
      );
      _activeChickWeightSampleIndex = _chickWeightSamples.length - 1;
      _normalizeChickWeightSamples();
    }

    updateChickWeightSampleMetadata({'houseNo': 'H', 'houseLabel': 'House'});
    _markDirtyAndScheduleAutosave();
    notifyListeners();
  }

  void removeActiveChickWeightSample() {
    if (_isReadOnly ||
        !_isChicksContext ||
        !isChickWeightCompareMode ||
        _chickWeightSamples.isEmpty) {
      return;
    }

    if (_chickWeightSamples.length <= 1) {
      setChickWeightSampleMode(StationSampleModel.sampleModePooled);
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
    final hasHouseNo = fields.containsKey('houseNo');
    final rawHouseNo = fields['houseNo'] as String? ?? sample.houseNo;
    final isComparison =
        sample.sampleMode == StationSampleModel.sampleModeComparison;
    final houseNo =
        hasHouseNo && isComparison && blankToNull(rawHouseNo) == null
        ? _defaultChickWeightHouseNo(_activeChickWeightSampleIndex)
        : rawHouseNo;
    final houseLabel =
        fields['houseLabel'] as String? ??
        (hasHouseNo
            ? _chickWeightHouseLabelForNo(
                houseNo: houseNo,
                index: _activeChickWeightSampleIndex,
              )
            : sample.houseLabel);
    _chickWeightSamples[_activeChickWeightSampleIndex] = sample.copyWith(
      sampleLabel:
          fields['sampleLabel'] as String? ??
          (hasHouseNo
              ? _chickWeightHouseSampleLabel(
                  houseNo: houseNo,
                  index: _activeChickWeightSampleIndex,
                )
              : sample.sampleLabel),
      houseNo: houseNo,
      houseLabel: houseLabel,
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
      'chickSampleSize': _weightSampleSizeFromWeightsJson(weightsJson),
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
    map['chickSampleSize'] = _weightSampleSizeFromWeightsJson(weightsJson);
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

  String _initialEggQualityScopeKind(
    AuditContext context,
    List<StationSampleModel>? samples,
  ) {
    return StationSampleModel.sampleKindHouse;
  }

  String _normalizeEggQualityScopeKind(String sampleKind) {
    return StationSampleModel.sampleKindHouse;
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
    String? groupKey, {
    bool inheritDraftResult = true,
  }) {
    final now = DateTime.now();
    final draft = activeDraft;
    final isComparison = sampleMode == StationSampleModel.sampleModeComparison;
    final houseNo = isComparison ? _defaultChickWeightHouseNo(index) : null;
    final houseLabel = _chickWeightHouseLabelForNo(
      houseNo: houseNo,
      index: index,
    );
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
      sampleLabel: _chickWeightHouseSampleLabel(houseNo: houseNo, index: index),
      sampleType: StationSampleModel.sampleTypeDefault,
      groupKey: isComparison ? groupKey : null,
      groupLabel: isComparison ? 'House comparison' : null,
      houseNo: houseNo,
      houseLabel: houseLabel,
      storageDays: draft.chickStorageDays ?? 0,
      calculatedBmkAgeDays: BmkAgeCalculator.calculateDays(
        currentFlockAgeDays: BmkAgeCalculator.currentFlockAgeDaysFromWeeks(
          _context?.flockAgeWeeks,
        ),
        auditDate: draft.date,
        legacyBmkAgeWeeks: legacyBmkWeeksForDraft(draft),
        storageDays: draft.chickStorageDays ?? 0,
        flockEntryDate: _context?.flockEntryDate,
      ),
      benchmarkBreed: _context?.breed,
      resultSummaryJson: inheritDraftResult
          ? _chickWeightResultSummaryJsonFromDraft(draft)
          : null,
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
    final defaultHouseNo = _defaultChickWeightHouseNo(index);
    final houseNo = isComparison
        ? _defaultOrBlankHouseNo(
                sample.houseNo,
                index: index,
                sampleIndex: sample.sampleIndex,
              )
              ? defaultHouseNo
              : sample.houseNo
        : null;
    final houseLabel = isComparison
        ? _defaultOrBlankHouseLabel(
                sample.houseLabel,
                index: index,
                sampleIndex: sample.sampleIndex,
              )
              ? _chickWeightHouseLabelForNo(houseNo: houseNo, index: index)
              : sample.houseLabel
        : null;
    final sampleLabel = _chickWeightHouseSampleLabel(
      houseNo: houseNo,
      index: index,
    );
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
      sampleLabel: sampleLabel,
      sampleType: sample.sampleType,
      breakoutType: sample.breakoutType,
      groupKey: isComparison ? groupKey : null,
      groupLabel: isComparison ? 'House comparison' : null,
      batchNo: sample.batchNo,
      houseNo: houseNo,
      houseLabel: houseLabel,
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

  String _defaultChickWeightHouseNo(int index) => 'H${index + 1}';

  String _defaultChickWeightHouseLabel(int index) => 'House ${index + 1}';

  String _chickWeightHouseSampleLabel({
    required String? houseNo,
    required int index,
  }) {
    final raw = blankToNull(houseNo);
    if (raw == null) {
      return index == 0 ? 'Pool' : _defaultChickWeightHouseNo(index);
    }
    final digits = RegExp(r'\d+').allMatches(raw).map((m) => m.group(0)).join();
    if (digits.isNotEmpty) return 'H$digits';
    return raw;
  }

  String? _chickWeightHouseLabelForNo({
    required String? houseNo,
    required int index,
  }) {
    final raw = blankToNull(houseNo);
    if (raw == null) {
      return index == 0 ? null : _defaultChickWeightHouseLabel(index);
    }
    final digits = RegExp(r'\d+').allMatches(raw).map((m) => m.group(0)).join();
    if (digits.isNotEmpty) return 'House $digits';
    return raw;
  }

  bool _defaultOrBlankHouseNo(
    String? value, {
    required int index,
    required int sampleIndex,
  }) {
    final trimmed = blankToNull(value);
    if (trimmed == null) return true;
    return trimmed == _defaultChickWeightHouseNo(index) ||
        trimmed == 'H$sampleIndex';
  }

  bool _defaultOrBlankHouseLabel(
    String? value, {
    required int index,
    required int sampleIndex,
  }) {
    final trimmed = blankToNull(value);
    if (trimmed == null) return true;
    return trimmed == _defaultChickWeightHouseLabel(index) ||
        trimmed == 'House $sampleIndex';
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
      final scopedFresh = _createSampleForDraft(
        draft,
        index,
        eggQualityScopeKind: _existingEggQualityScopeKindForSync(
          draft,
          existing,
        ),
      );
      final preserveExistingHierarchy = _sampleHasHierarchy(existing);

      return existing.copyWith(
        legacyAuditId: scopedFresh.legacyAuditId,
        stationType: scopedFresh.stationType,
        sectorType: scopedFresh.sectorType,
        sampleKind: preserveExistingHierarchy
            ? existing.sampleKind
            : scopedFresh.sampleKind,
        sampleMode: scopedFresh.sampleMode,
        comparisonType: preserveExistingHierarchy
            ? existing.comparisonType
            : scopedFresh.comparisonType,
        sampleIndex: scopedFresh.sampleIndex,
        sampleLabel: preserveExistingHierarchy
            ? existing.sampleLabel
            : scopedFresh.sampleLabel,
        sampleType: scopedFresh.sampleType,
        breakoutType: scopedFresh.breakoutType,
        groupKey: scopedFresh.groupKey,
        groupLabel: preserveExistingHierarchy
            ? existing.groupLabel
            : scopedFresh.groupLabel,
        batchNo: scopedFresh.batchNo,
        houseNo: preserveExistingHierarchy
            ? existing.houseNo
            : scopedFresh.houseNo,
        houseLabel: preserveExistingHierarchy
            ? existing.houseLabel
            : scopedFresh.houseLabel,
        hatchNo: scopedFresh.hatchNo,
        storageDays: scopedFresh.storageDays,
        incubationDay: scopedFresh.incubationDay,
        setterNo: preserveExistingHierarchy
            ? existing.setterNo
            : scopedFresh.setterNo,
        hatcherNo: preserveExistingHierarchy
            ? existing.hatcherNo
            : scopedFresh.hatcherNo,
        calculatedBmkAgeDays: scopedFresh.calculatedBmkAgeDays,
        benchmarkBreed: scopedFresh.benchmarkBreed,
        benchmarkAgeDays: scopedFresh.benchmarkAgeDays,
        resultSummaryJson: scopedFresh.resultSummaryJson,
        updatedAt: scopedFresh.updatedAt,
      );
    });
  }

  bool _sampleHasHierarchy(StationSampleModel sample) {
    return hasText(sample.houseNo) ||
        hasText(sample.houseLabel) ||
        hasText(sample.setterNo) ||
        hasText(sample.hatcherNo);
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

  StationSampleModel _createSampleForDraft(
    AuditModel draft,
    int index, {
    String? eggQualityScopeKind,
  }) {
    final now = DateTime.now();
    final isMachineStation =
        draft.auditType == 'Setters' || draft.auditType == 'Hatchers';
    final eggScopeKind = _eggQualityScopeKindForDraft(
      draft,
      eggQualityScopeKind,
    );
    return StationSampleModel(
      id: _uuid.v4(),
      auditSessionId: _activeSessionId ?? draft.sessionId ?? '',
      legacyAuditId: draft.id,
      stationType: StationSampleMapper.stationTypeForAuditType(draft.auditType),
      sectorType: _defaultSectorType(draft.auditType),
      sampleKind: _defaultSampleKind(
        draft.auditType,
        eggQualityScopeKind: eggScopeKind,
      ),
      sampleMode: SampleMode.isCompare(draft.sampleMode)
          ? StationSampleModel.sampleModeComparison
          : StationSampleModel.sampleModePooled,
      comparisonType: _defaultComparisonType(
        draft.auditType,
        draft.sampleMode,
        eggQualityScopeKind: eggScopeKind,
      ),
      sampleIndex: index + 1,
      sampleLabel: _sampleLabelForDraft(
        draft,
        index,
        eggQualityScopeKind: eggScopeKind,
      ),
      sampleType: _defaultSampleType(draft.auditType, draft.ebBreakoutType),
      breakoutType: _defaultBreakoutType(draft.ebBreakoutType),
      groupKey: draft.compareGroupKey,
      groupLabel: _groupLabelForDraft(draft, eggQualityScopeKind: eggScopeKind),
      batchNo: draft.hatchNumber.toString(),
      houseNo: _houseNoForDraft(
        draft,
        index,
        eggQualityScopeKind: eggScopeKind,
      ),
      houseLabel: _houseLabelForDraft(
        draft,
        index,
        eggQualityScopeKind: eggScopeKind,
      ),
      hatchNo: draft.hatchNumber.toString(),
      storageDays: storageDaysForDraft(draft),
      incubationDay: draft.soIncubationAge ?? draft.hoIncubationAge,
      setterNo: _setterNoForDraft(
        draft,
        index: index,
        eggQualityScopeKind: eggScopeKind,
      ),
      hatcherNo: _hatcherNoForDraft(
        draft,
        index: index,
        eggQualityScopeKind: eggScopeKind,
      ),
      calculatedBmkAgeDays: isMachineStation
          ? null
          : BmkAgeCalculator.calculateDays(
              currentFlockAgeDays:
                  BmkAgeCalculator.currentFlockAgeDaysFromWeeks(
                    _context?.flockAgeWeeks,
                  ),
              auditDate: draft.date,
              legacyBmkAgeWeeks: legacyBmkWeeksForDraft(draft),
              storageDays: storageDaysForDraft(draft),
              flockEntryDate: _context?.flockEntryDate,
            ),
      benchmarkBreed: isMachineStation
          ? null
          : _context?.breed ?? draft.soBreed ?? draft.hoBreed,
      resultSummaryJson: StationSampleMapper.resultSummaryJsonForAudit(draft),
      createdAt: draft.createdAt,
      updatedAt: now,
    );
  }

  void _syncStationSampleFromDraft(int index) {
    if (index < 0 || index >= _drafts.length) return;
    if (_stationSamples.length != _drafts.length) {
      _stationSamples = _buildSamplesForDrafts(
        existingStationSamples: _stationSamples,
      );
      return;
    }
    final existing = _stationSamples[index];
    final fresh = _createSampleForDraft(
      _drafts[index],
      index,
      eggQualityScopeKind: _existingEggQualityScopeKindForSync(
        _drafts[index],
        existing,
      ),
    );
    final isComparisonDraft = SampleMode.isCompare(_drafts[index].sampleMode);
    final leavingComparison =
        !isComparisonDraft &&
        existing.sampleMode == StationSampleModel.sampleModeComparison;
    final isEggHouseSample =
        fresh.sampleKind == StationSampleModel.sampleKindHouse;
    final isMachineSample =
        fresh.sampleKind == StationSampleModel.sampleKindMachine;
    final keepGeneratedEggHouseMetadata =
        _drafts[index].auditType == 'Egg' &&
        isComparisonDraft &&
        isEggHouseSample &&
        _eggQualityScopeKind == StationSampleModel.sampleKindHouse;
    final keepGeneratedMachineMetadata =
        _drafts[index].auditType == 'Chicks' && isComparisonDraft;
    final keepGeneratedSetterMetadata =
        _drafts[index].auditType == 'Setters' && isComparisonDraft;
    final keepGeneratedHatcherMetadata =
        _drafts[index].auditType == 'Hatchers' && isComparisonDraft;
    final keepGeneratedSampleMetadata =
        keepGeneratedEggHouseMetadata ||
        keepGeneratedMachineMetadata ||
        keepGeneratedSetterMetadata ||
        keepGeneratedHatcherMetadata;
    final clearChickMachineHouseMetadata =
        _drafts[index].auditType == 'Chicks' &&
        isComparisonDraft &&
        isMachineSample;
    final keepCustomEggHouseMetadata =
        keepGeneratedEggHouseMetadata && hasText(existing.houseNo);
    final keepEnteredMachineHouseMetadata =
        keepGeneratedMachineMetadata && hasText(existing.houseNo);
    final sampleLabel = keepCustomEggHouseMetadata
        ? _houseScopeSampleLabel(
            houseNo: existing.houseNo,
            fallbackIndex: index + 1,
          )
        : fresh.sampleLabel;
    final houseNo =
        keepCustomEggHouseMetadata || keepEnteredMachineHouseMetadata
        ? existing.houseNo
        : fresh.houseNo;
    final houseLabel =
        keepCustomEggHouseMetadata || keepEnteredMachineHouseMetadata
        ? (hasText(existing.houseLabel)
              ? existing.houseLabel
              : _houseScopeLabelForNo(
                  houseNo: existing.houseNo,
                  fallbackIndex: index + 1,
                ))
        : fresh.houseLabel;
    final next = fresh.copyWith(
      id: existing.id,
      auditSessionId: _activeSessionId ?? existing.auditSessionId,
      legacyAuditId: _drafts[index].id,
      stationType: fresh.stationType,
      sectorType: fresh.sectorType,
      sampleKind: fresh.sampleKind,
      sampleMode: fresh.sampleMode,
      comparisonType: isComparisonDraft
          ? (keepGeneratedSampleMetadata
                ? fresh.comparisonType
                : existing.comparisonType ?? fresh.comparisonType)
          : fresh.comparisonType,
      sampleLabel: keepGeneratedSampleMetadata || leavingComparison
          ? sampleLabel
          : existing.sampleLabel,
      sampleType: existing.sampleType,
      breakoutType: existing.breakoutType,
      groupKey: isComparisonDraft
          ? _drafts[index].compareGroupKey ?? existing.groupKey
          : fresh.groupKey,
      groupLabel: isComparisonDraft
          ? (keepGeneratedSampleMetadata
                ? fresh.groupLabel
                : existing.groupLabel)
          : fresh.groupLabel,
      batchNo: existing.batchNo,
      houseNo: clearChickMachineHouseMetadata
          ? ''
          : keepGeneratedEggHouseMetadata || leavingComparison
          ? houseNo
          : existing.houseNo,
      houseLabel: clearChickMachineHouseMetadata
          ? ''
          : keepGeneratedEggHouseMetadata || leavingComparison
          ? houseLabel
          : existing.houseLabel,
      hatchNo: existing.hatchNo,
      eggProductionDate: existing.eggProductionDate,
      settingDate: existing.settingDate,
      hatchDate: existing.hatchDate,
      setterNo:
          keepGeneratedEggHouseMetadata ||
              keepGeneratedMachineMetadata ||
              keepGeneratedSetterMetadata ||
              _drafts[index].auditType == 'Setters'
          ? fresh.setterNo
          : existing.setterNo,
      hatcherNo:
          keepGeneratedEggHouseMetadata ||
              keepGeneratedMachineMetadata ||
              keepGeneratedHatcherMetadata ||
              _drafts[index].auditType == 'Hatchers'
          ? fresh.hatcherNo
          : existing.hatcherNo,
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

  String _eggQualityScopeKindForDraft(
    AuditModel draft,
    String? preferredScopeKind,
  ) {
    if (draft.auditType != 'Egg' || !SampleMode.isCompare(draft.sampleMode)) {
      return _eggQualityScopeKind;
    }
    return _normalizeEggQualityScopeKind(
      preferredScopeKind ?? _eggQualityScopeKind,
    );
  }

  String? _existingEggQualityScopeKindForSync(
    AuditModel draft,
    StationSampleModel existing,
  ) {
    if (draft.auditType != 'Egg' || !SampleMode.isCompare(draft.sampleMode)) {
      return null;
    }
    if (existing.sampleMode != StationSampleModel.sampleModeComparison) {
      return null;
    }
    return _normalizeEggQualityScopeKind(existing.sampleKind);
  }

  String? _defaultComparisonType(
    String auditType,
    String sampleMode, {
    String? eggQualityScopeKind,
  }) {
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

  String _defaultSampleKind(String auditType, {String? eggQualityScopeKind}) {
    return switch (auditType) {
      'Egg' => eggQualityScopeKind ?? _eggQualityScopeKind,
      'Chicks' ||
      'Setters' ||
      'Hatchers' => StationSampleModel.sampleKindMachine,
      'Hatch Analysis & Egg Breakouts' => StationSampleModel.sampleKindBatch,
      _ => StationSampleModel.sampleKindPooled,
    };
  }

  String _sampleLabelForDraft(
    AuditModel draft,
    int index, {
    String? eggQualityScopeKind,
  }) {
    if (draft.auditType == 'Egg' && SampleMode.isCompare(draft.sampleMode)) {
      return 'H${index + 1}';
    }
    if (draft.auditType == 'Chicks' && SampleMode.isCompare(draft.sampleMode)) {
      return _chickMachineSampleLabel(
        setterNo: _setterNoForDraft(draft, index: index),
        hatcherNo: _hatcherNoForDraft(draft, index: index),
        fallbackIndex: index + 1,
      );
    }
    if (draft.auditType == 'Setters' &&
        SampleMode.isCompare(draft.sampleMode)) {
      return _machineSampleLabel(
        _setterNoForDraft(draft),
        prefix: 'S',
        fallbackIndex: index + 1,
      );
    }
    if (draft.auditType == 'Hatchers' &&
        SampleMode.isCompare(draft.sampleMode)) {
      return _machineSampleLabel(
        _hatcherNoForDraft(draft),
        prefix: 'H',
        fallbackIndex: index + 1,
      );
    }
    return 'Sample ${index + 1}';
  }

  String? _setterNoForDraft(
    AuditModel draft, {
    int? index,
    String? eggQualityScopeKind,
  }) {
    if (draft.auditType == 'Egg') {
      return null;
    }
    if (draft.auditType == 'Chicks' && SampleMode.isCompare(draft.sampleMode)) {
      return draft.setterId ?? draft.soSetterId ?? 'S${(index ?? 0) + 1}';
    }
    if (draft.auditType == 'Setters') {
      return blankToNull(draft.soSetterId) ??
          blankToNull(draft.setterId) ??
          'S';
    }
    return draft.setterId ?? draft.soSetterId;
  }

  String? _hatcherNoForDraft(
    AuditModel draft, {
    int? index,
    String? eggQualityScopeKind,
  }) {
    if (draft.auditType == 'Egg') {
      return null;
    }
    if (draft.auditType == 'Chicks' && SampleMode.isCompare(draft.sampleMode)) {
      return draft.hatcherId ?? draft.hoHatcherId ?? 'H${(index ?? 0) + 1}';
    }
    if (draft.auditType == 'Hatchers') {
      return blankToNull(draft.hoHatcherId) ??
          blankToNull(draft.hatcherId) ??
          'H';
    }
    return draft.hatcherId ?? draft.hoHatcherId;
  }

  String? _groupLabelForDraft(AuditModel draft, {String? eggQualityScopeKind}) {
    if (draft.compareGroupKey == null) return null;
    if (draft.auditType == 'Egg') {
      return 'House comparison';
    }
    if (draft.auditType == 'Chicks') return 'Machine comparison';
    if (draft.auditType == 'Setters') return 'Setter comparison';
    if (draft.auditType == 'Hatchers') return 'Hatcher comparison';
    return 'Comparison';
  }

  int _scopeSerialForSample(StationSampleModel sample, {String? houseNo}) {
    var serial = 0;

    for (final candidate in _stationSamples) {
      if (candidate.stationType != sample.stationType ||
          candidate.sectorType != sample.sectorType ||
          candidate.sampleKind != sample.sampleKind) {
        continue;
      }

      serial++;
      if (candidate.id == sample.id) return serial;
    }

    return sample.sampleIndex > 0 ? sample.sampleIndex : 1;
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
    required String? houseNo,
    required String? setterNo,
    required String? hatcherNo,
    required int fallbackIndex,
  }) {
    if (sample.sampleMode != StationSampleModel.sampleModeComparison) {
      return sample.sampleLabel;
    }
    if (draft.auditType == 'Egg' &&
        sample.sampleKind == StationSampleModel.sampleKindHouse) {
      return _houseScopeSampleLabel(
        houseNo: houseNo,
        fallbackIndex: fallbackIndex,
      );
    }
    if (draft.auditType == 'Chicks') {
      return _chickMachineSampleLabel(
        setterNo: setterNo,
        hatcherNo: hatcherNo,
        fallbackIndex: fallbackIndex,
      );
    }
    if (draft.auditType == 'Setters') {
      return _machineSampleLabel(
        setterNo,
        prefix: 'S',
        fallbackIndex: fallbackIndex,
      );
    }
    if (draft.auditType == 'Hatchers') {
      return _machineSampleLabel(
        hatcherNo,
        prefix: 'H',
        fallbackIndex: fallbackIndex,
      );
    }
    return sample.sampleLabel;
  }

  String _houseScopeSampleLabel({
    required String? houseNo,
    required int fallbackIndex,
  }) {
    final raw = blankToNull(houseNo);
    if (raw == null) return 'H$fallbackIndex';
    final digits = RegExp(r'\d+').allMatches(raw).map((m) => m.group(0)).join();
    if (digits.isNotEmpty) return 'H$digits';
    return raw;
  }

  String? _houseScopeLabelForNo({
    required String? houseNo,
    required int fallbackIndex,
  }) {
    final raw = blankToNull(houseNo);
    if (raw == null) return 'House $fallbackIndex';
    final digits = RegExp(r'\d+').allMatches(raw).map((m) => m.group(0)).join();
    if (digits.isNotEmpty) return 'House $digits';
    return raw;
  }

  String? _houseNoForDraft(
    AuditModel draft,
    int index, {
    String? eggQualityScopeKind,
  }) {
    if (draft.auditType != 'Egg' ||
        !SampleMode.isCompare(draft.sampleMode) ||
        eggQualityScopeKind != StationSampleModel.sampleKindHouse) {
      return null;
    }
    return 'H${index + 1}';
  }

  String? _houseLabelForDraft(
    AuditModel draft,
    int index, {
    String? eggQualityScopeKind,
  }) {
    if (draft.auditType != 'Egg' ||
        !SampleMode.isCompare(draft.sampleMode) ||
        eggQualityScopeKind != StationSampleModel.sampleKindHouse) {
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

  int? _weightSampleSizeFromWeightsJson(String weightsJson) {
    final decoded = _decodedWeights(weightsJson);
    return weightSampleSizeFromDecoded(decoded);
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

    if (audit.esEstAvg != null &&
        (audit.esEstAvg! < AppThresholds.shellTempMin ||
            audit.esEstAvg! > AppThresholds.shellTempMax)) {
      await NotificationService.showAlert(
        title: 'Shell Temperature Alert',
        body:
            'EST ${audit.esEstAvg!.toStringAsFixed(1)} is outside the target range.',
        payload: audit.id,
      );
    }
  }
}
