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
import '../../../data/repositories/benchmark_lookup.dart';
import '../../../data/repositories/panel_sample_repository.dart';
import '../../../data/repositories/station_sample_repository.dart';
import '../../../providers/app_provider.dart';
import '../../../services/notifications/notification_service.dart';
import '../../../services/supabase/supabase_service.dart';
import '../models/culled_chicks_analysis.dart';
import '../models/egg_breakout_tray_rollup.dart';
import '../models/egg_breakout_sample.dart';
import '../models/residue_batch_metrics.dart';
import '../models/station_completion_validation.dart';
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

typedef _PanelSavePair = ({AuditModel draft, StationSampleModel sample});

class AuditProvider extends ChangeNotifier {
  AuditProvider({
    AuditRepository? repository,
    StationSampleRepository? stationSampleRepository,
    PanelSampleRepository? panelSampleRepository,
    ActivityLogRepository? activityLogRepository,
    BenchmarkLookup? benchmarkLookup,
    SupabaseService? supabaseService,
    Duration autosaveDebounceDuration = defaultAutosaveDebounceDuration,
    bool autosaveEnabled = true,
  }) : _panelSampleRepository =
           panelSampleRepository ?? PanelSampleRepository(),
       _activityLogRepository =
           activityLogRepository ?? ActivityLogRepository(),
       _benchmarkLookup = benchmarkLookup ?? BenchmarkLookup(),
       _autosaveDebounceDuration = autosaveDebounceDuration,
       _autosaveEnabled = autosaveEnabled;

  static const Duration defaultAutosaveDebounceDuration = Duration(seconds: 1);

  final PanelSampleRepository _panelSampleRepository;
  final ActivityLogRepository _activityLogRepository;
  final BenchmarkLookup _benchmarkLookup;
  final Duration _autosaveDebounceDuration;
  final bool _autosaveEnabled;
  final Uuid _uuid = const Uuid();

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
  bool get isEggQualityMachineScopeActive =>
      _context?.auditType == 'Egg' &&
      isCompareMode &&
      _stationSamples.any(
        (sample) =>
            sample.sampleMode == StationSampleModel.sampleModeComparison &&
            sample.sampleKind == StationSampleModel.sampleKindMachine,
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
    'esShellTemp',
    'esShellTempPhoto',
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
    if (_tryUpdateSelectedEggQualityHouseMetadata(fields)) return;

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

  bool _tryUpdateSelectedEggQualityHouseMetadata(Map<String, dynamic> fields) {
    if (_context?.auditType != 'Egg' ||
        activeStationSample.sampleKind !=
            StationSampleModel.sampleKindMachine ||
        !fields.containsKey('houseNo') ||
        fields.containsKey('setterNo') ||
        fields.containsKey('hatcherNo')) {
      return false;
    }
    const allowedFields = {'houseNo', 'houseLabel', 'sampleLabel'};
    if (!fields.keys.every(allowedFields.contains)) return false;

    final previousHouseKey = _blankToNull(activeStationSample.houseNo);
    if (previousHouseKey == null) return false;

    final houseIndex = _selectedEggQualityHouseIndex(previousHouseKey);
    if (houseIndex == -1) return false;

    final now = DateTime.now();
    final houseSample = _stationSamples[houseIndex];
    final houseNo = fields['houseNo'] as String? ?? houseSample.houseNo;
    final fallbackScopeSerial = _scopeSerialForSample(
      houseSample,
      houseNo: houseNo,
    );
    final houseLabel =
        fields['houseLabel'] as String? ??
        _houseScopeLabelForNo(
          houseNo: houseNo,
          fallbackIndex: fallbackScopeSerial,
        );
    final sampleLabel =
        fields['sampleLabel'] as String? ??
        _houseScopeSampleLabel(
          houseNo: houseNo,
          fallbackIndex: fallbackScopeSerial,
        );

    _stationSamples[houseIndex] = houseSample.copyWith(
      sampleLabel: sampleLabel,
      houseNo: houseNo,
      houseLabel: houseLabel,
      updatedAt: now,
    );

    for (var i = 0; i < _stationSamples.length; i++) {
      if (i == houseIndex) continue;
      final sample = _stationSamples[i];
      if (sample.sampleKind == StationSampleModel.sampleKindMachine &&
          _blankToNull(sample.houseNo) == previousHouseKey) {
        _stationSamples[i] = sample.copyWith(
          houseNo: houseNo,
          houseLabel: houseLabel,
          updatedAt: now,
        );
      }
    }

    _markDirtyAndScheduleAutosave();
    notifyListeners();
    return true;
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
      final panelSavePairs = <_PanelSavePair>[];
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
      final scopedPanelSavePairs = _scopedPanelSavePairs(panelSavePairs);
      final meaningfulScopedPanelSavePairs = scopedPanelSavePairs
          .where(_hasMeaningfulPanelData)
          .toList();
      final eggPanelSavePairs = panelSavePairs
          .where((pair) => pair.draft.auditType == 'Egg')
          .toList();
      final eggQualityPanelSavePairs = meaningfulScopedPanelSavePairs
          .where((pair) => pair.draft.auditType == 'Egg')
          .toList();
      await _deletePanelRowsForRemovedSamples(
        draftsToSave: draftsToSave,
        removedStationSampleIds: removedStationSampleIds,
      );
      await _deleteDiscardedPanelRows(scopedPanelSavePairs);
      if (eggPanelSavePairs.isNotEmpty) {
        await _savePooledEggStoragePanelTable(eggPanelSavePairs);
        if (!_hasAnyMeaningfulEggQualityData(eggQualityPanelSavePairs)) {
          await _deleteEggQualityRowsBySessionId(eggPanelSavePairs);
        }
      }
      for (final pair in meaningfulScopedPanelSavePairs) {
        await _savePanelTablesForSample(
          pair.draft,
          pair.sample,
          skipTables: pair.draft.auditType == 'Egg'
              ? {
                  'egg_storage',
                  if (!_hasMeaningfulEggQualityData(pair.draft)) 'egg_quality',
                }
              : const <String>{},
        );
      }
      await _pruneStalePanelHierarchyRows(meaningfulScopedPanelSavePairs);
      await _pruneStaleBreakoutRows(meaningfulScopedPanelSavePairs);
      for (var i = 0; i < chickWeightSamplesToSave.length; i++) {
        final sample = chickWeightSamplesToSave[i];
        if (i < _chickWeightSamples.length) {
          _chickWeightSamples[i] = sample;
        }
      }
      if (savedDrafts.isNotEmpty && chickWeightSamplesToSave.isNotEmpty) {
        final chickWeightDraft = savedDrafts.first;
        final meaningfulChickWeightSamples = [
          for (final sample in chickWeightSamplesToSave)
            if (_hasMeaningfulChickWeightSample(chickWeightDraft, sample))
              sample,
        ];
        await _deleteDiscardedChickWeightRows(
          chickWeightSamplesToSave,
          meaningfulChickWeightSamples,
        );
        if (meaningfulChickWeightSamples.isEmpty) {
          final sessionId = chickWeightSamplesToSave.first.auditSessionId;
          if (sessionId.isNotEmpty) {
            await _panelSampleRepository.deleteRowsBySessionId(
              'chick_weights',
              sessionId,
            );
          }
        } else {
          await _saveChickWeightPanelSamples(
            chickWeightDraft,
            meaningfulChickWeightSamples,
          );
        }
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

    for (final lesion in _decodedMaps(a.pmOtherLesionsJson)) {
      final name = (lesion['name'] as String? ?? '').trim();
      final count = _asInt(lesion['count']);
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
    if (_drafts.any(_hasCoreStationData)) {
      return StationCompletionValidation.complete(stationKey);
    }
    if (_drafts.any(_hasAnyMeaningfulStationData)) {
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

    final normalizedScopeKind = _normalizeEggQualityScopeKind(sampleKind);
    if (normalizedScopeKind == StationSampleModel.sampleKindHouse &&
        isEggQualityMachineScopeActive &&
        !isEggQualityHouseScopeActive) {
      _resetEggQualityMachineScope();
    }
    final wasCompareMode = isCompareMode;
    final parentHouseNo = _blankToNull(activeStationSample.houseNo);
    final parentHouseLabel = _blankToNull(activeStationSample.houseLabel);
    _eggQualityScopeKind = normalizedScopeKind;
    if (!wasCompareMode) {
      setStationSampleMode(StationSampleModel.sampleModeComparison);
      if (normalizedScopeKind == StationSampleModel.sampleKindHouse) {
        updateSampleMetadata({'houseNo': 'H', 'houseLabel': 'House'});
        return;
      }
      if (normalizedScopeKind == StationSampleModel.sampleKindMachine) {
        final fields = <String, dynamic>{'setterNo': 'S', 'hatcherNo': 'H'};
        if (parentHouseNo != null) fields['houseNo'] = parentHouseNo;
        if (parentHouseLabel != null) fields['houseLabel'] = parentHouseLabel;
        updateSampleMetadata(fields);
        return;
      }
    }

    addSample();
    if (normalizedScopeKind == StationSampleModel.sampleKindHouse) {
      updateSampleMetadata({'houseNo': 'H', 'houseLabel': 'House'});
      return;
    }
    if (normalizedScopeKind == StationSampleModel.sampleKindMachine) {
      final fields = <String, dynamic>{'setterNo': 'S', 'hatcherNo': 'H'};
      if (parentHouseNo != null) fields['houseNo'] = parentHouseNo;
      if (parentHouseLabel != null) fields['houseLabel'] = parentHouseLabel;
      updateSampleMetadata(fields);
    }
  }

  void _resetEggQualityMachineScope() {
    if (_drafts.isEmpty) return;

    final retainedDraftMap = _drafts.first.toMap()
      ..addAll(_sharedEggStoragePatch(activeDraft))
      ..['sampleMode'] = SampleMode.pool
      ..['compareGroupKey'] = null
      ..['hatchNumber'] = 1
      ..['updatedAt'] = DateTime.now().toIso8601String();

    _removedStationSampleIds.addAll(_stationSamples.map((sample) => sample.id));
    _removedLegacyAuditIds.addAll(_drafts.skip(1).map((draft) => draft.id));
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

    final normalizedScopeKind = _normalizeEggQualityScopeKind(sampleKind);
    if (normalizedScopeKind == StationSampleModel.sampleKindHouse) {
      _removeSelectedEggQualityHouseWithMachines();
      return;
    }

    _removeSelectedEggQualityMachine();
  }

  void _removeSelectedEggQualityHouseWithMachines() {
    if (!isCompareMode) return;

    final activeHouseKey = _blankToNull(activeStationSample.houseNo);
    final houseIndex = _selectedEggQualityHouseIndex(activeHouseKey);
    if (houseIndex == -1) {
      removeActiveSample();
      return;
    }

    final removedHouse = _stationSamples[houseIndex];
    final houseKey =
        _blankToNull(removedHouse.houseNo) ??
        _blankToNull(removedHouse.sampleLabel);
    final indexesToRemove = <int>{houseIndex};
    if (houseKey != null) {
      for (var i = 0; i < _stationSamples.length; i++) {
        final sample = _stationSamples[i];
        if (sample.sampleKind == StationSampleModel.sampleKindMachine &&
            _blankToNull(sample.houseNo) == houseKey) {
          indexesToRemove.add(i);
        }
      }
    }

    _removeEggQualityScopeIndexes(indexesToRemove);
  }

  void _removeSelectedEggQualityMachine() {
    if (!isCompareMode) return;

    if (activeStationSample.sampleKind ==
        StationSampleModel.sampleKindMachine) {
      final activeHouseKey = _blankToNull(activeStationSample.houseNo);
      _removeEggQualityScopeIndexes({
        _activeHatchIndex,
      }, preferredHouseKey: activeHouseKey);
      return;
    }

    final activeHouseKey =
        _blankToNull(activeStationSample.houseNo) ??
        _blankToNull(activeStationSample.sampleLabel);
    if (activeHouseKey == null) return;

    final machineIndexes = <int>[];
    for (var i = 0; i < _stationSamples.length; i++) {
      final sample = _stationSamples[i];
      if (sample.sampleKind == StationSampleModel.sampleKindMachine &&
          _blankToNull(sample.houseNo) == activeHouseKey) {
        machineIndexes.add(i);
      }
    }
    if (machineIndexes.isEmpty) return;

    _removeEggQualityScopeIndexes({
      machineIndexes.last,
    }, preferredActiveSampleId: activeStationSample.id);
  }

  int _selectedEggQualityHouseIndex(String? activeHouseKey) {
    if (activeStationSample.sampleKind == StationSampleModel.sampleKindHouse) {
      return _activeHatchIndex;
    }

    if (activeHouseKey == null) return -1;
    return _stationSamples.indexWhere(
      (sample) =>
          sample.sampleKind == StationSampleModel.sampleKindHouse &&
          (_blankToNull(sample.houseNo) ?? _blankToNull(sample.sampleLabel)) ==
              activeHouseKey,
    );
  }

  void _removeEggQualityScopeIndexes(
    Set<int> indexesToRemove, {
    String? preferredActiveSampleId,
    String? preferredHouseKey,
  }) {
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
    if (preferredActiveSampleId != null) {
      final preferredActiveIndex = _stationSamples.indexWhere(
        (sample) => sample.id == preferredActiveSampleId,
      );
      if (preferredActiveIndex != -1) {
        _activeHatchIndex = preferredActiveIndex;
      }
    } else if (preferredHouseKey != null) {
      final preferredHouseIndex = _defaultEggQualityIndexForHouse(
        preferredHouseKey,
      );
      if (preferredHouseIndex != -1) {
        _activeHatchIndex = preferredHouseIndex;
      }
    }
    final keepsEggQualityScope =
        _context?.auditType == 'Egg' &&
        retainedSamples.any(
          (sample) =>
              sample.sampleKind == StationSampleModel.sampleKindHouse ||
              sample.sampleKind == StationSampleModel.sampleKindMachine,
        );
    final legacyMode = _drafts.length == 1 && !keepsEggQualityScope
        ? SampleMode.pool
        : SampleMode.compare;
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
    final legacyMode = _drafts.length == 1
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
    _activeHatchIndex = _defaultLeafScopeIndex(index);
    notifyListeners();
  }

  int _defaultLeafScopeIndex(int index) {
    if (index < 0 || index >= _stationSamples.length) return index;
    final sample = _stationSamples[index];
    if (_context?.auditType != 'Egg' ||
        sample.sampleKind != StationSampleModel.sampleKindHouse) {
      return index;
    }

    final houseKey = _eggQualityHouseKey(sample);
    if (houseKey == null) return index;
    final firstChildIndex = _stationSamples.indexWhere(
      (candidate) =>
          candidate.sampleKind == StationSampleModel.sampleKindMachine &&
          _blankToNull(candidate.houseNo) == houseKey,
    );
    return firstChildIndex == -1 ? index : firstChildIndex;
  }

  int _defaultEggQualityIndexForHouse(String houseKey) {
    final firstChildIndex = _stationSamples.indexWhere(
      (candidate) =>
          candidate.sampleKind == StationSampleModel.sampleKindMachine &&
          _blankToNull(candidate.houseNo) == houseKey,
    );
    if (firstChildIndex != -1) return firstChildIndex;

    return _stationSamples.indexWhere(
      (candidate) =>
          candidate.sampleKind == StationSampleModel.sampleKindHouse &&
          _eggQualityHouseKey(candidate) == houseKey,
    );
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
        hasHouseNo && isComparison && _blankToNull(rawHouseNo) == null
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
    if (context.auditType != 'Egg' || samples == null) {
      return StationSampleModel.sampleKindHouse;
    }
    for (final sample in samples) {
      if (sample.sampleKind == StationSampleModel.sampleKindMachine) {
        return StationSampleModel.sampleKindMachine;
      }
      if (sample.sampleKind == StationSampleModel.sampleKindHouse) {
        return StationSampleModel.sampleKindHouse;
      }
    }
    return StationSampleModel.sampleKindHouse;
  }

  String _normalizeEggQualityScopeKind(String sampleKind) {
    return sampleKind == StationSampleModel.sampleKindMachine
        ? StationSampleModel.sampleKindMachine
        : StationSampleModel.sampleKindHouse;
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
        legacyBmkAgeWeeks: _legacyBmkWeeksForDraft(draft),
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
    final raw = _blankToNull(houseNo);
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
    final raw = _blankToNull(houseNo);
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
    final trimmed = _blankToNull(value);
    if (trimmed == null) return true;
    return trimmed == _defaultChickWeightHouseNo(index) ||
        trimmed == 'H$sampleIndex';
  }

  bool _defaultOrBlankHouseLabel(
    String? value, {
    required int index,
    required int sampleIndex,
  }) {
    final trimmed = _blankToNull(value);
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
    return _hasText(sample.houseNo) ||
        _hasText(sample.houseLabel) ||
        _hasText(sample.setterNo) ||
        _hasText(sample.hatcherNo);
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
      storageDays: _storageDaysForDraft(draft),
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
              legacyBmkAgeWeeks: _legacyBmkWeeksForDraft(draft),
              storageDays: _storageDaysForDraft(draft),
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
    final isEggMachineSample =
        fresh.sampleKind == StationSampleModel.sampleKindMachine;
    final keepGeneratedEggHouseMetadata =
        _drafts[index].auditType == 'Egg' &&
        isComparisonDraft &&
        isEggHouseSample &&
        _eggQualityScopeKind == StationSampleModel.sampleKindHouse;
    final keepGeneratedEggMachineMetadata =
        _drafts[index].auditType == 'Egg' &&
        isComparisonDraft &&
        isEggMachineSample &&
        _eggQualityScopeKind == StationSampleModel.sampleKindMachine;
    final keepGeneratedMachineMetadata =
        (_drafts[index].auditType == 'Chicks' && isComparisonDraft) ||
        keepGeneratedEggMachineMetadata;
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
        isEggMachineSample;
    final keepCustomEggHouseMetadata =
        keepGeneratedEggHouseMetadata &&
        !_defaultEggHouseNo(
          existing.houseNo,
          index: index,
          sampleIndex: existing.sampleIndex,
        );
    final keepEnteredMachineHouseMetadata =
        (keepGeneratedEggMachineMetadata || keepGeneratedMachineMetadata) &&
        _hasText(existing.houseNo);
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
        ? (_defaultEggHouseLabel(
                existing.houseLabel,
                index: index,
                sampleIndex: existing.sampleIndex,
              )
              ? _houseScopeLabelForNo(
                  houseNo: existing.houseNo,
                  fallbackIndex: index + 1,
                )
              : existing.houseLabel)
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
          : keepGeneratedEggHouseMetadata ||
                keepGeneratedEggMachineMetadata ||
                leavingComparison
          ? houseNo
          : existing.houseNo,
      houseLabel: clearChickMachineHouseMetadata
          ? ''
          : keepGeneratedEggHouseMetadata ||
                keepGeneratedEggMachineMetadata ||
                leavingComparison
          ? houseLabel
          : existing.houseLabel,
      hatchNo: existing.hatchNo,
      eggProductionDate: existing.eggProductionDate,
      settingDate: existing.settingDate,
      hatchDate: existing.hatchDate,
      setterNo:
          keepGeneratedEggHouseMetadata ||
              keepGeneratedEggMachineMetadata ||
              keepGeneratedMachineMetadata ||
              keepGeneratedSetterMetadata ||
              _drafts[index].auditType == 'Setters'
          ? fresh.setterNo
          : existing.setterNo,
      hatcherNo:
          keepGeneratedEggHouseMetadata ||
              keepGeneratedEggMachineMetadata ||
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
        return eggQualityScopeKind == StationSampleModel.sampleKindMachine
            ? StationSampleModel.comparisonTypeMachine
            : StationSampleModel.comparisonTypeHouse;
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
      if (eggQualityScopeKind == StationSampleModel.sampleKindMachine) {
        return _eggMachineSampleLabel(
          setterNo: _setterNoForDraft(
            draft,
            index: index,
            eggQualityScopeKind: eggQualityScopeKind,
          ),
          hatcherNo: _hatcherNoForDraft(
            draft,
            index: index,
            eggQualityScopeKind: eggQualityScopeKind,
          ),
          fallbackIndex: index + 1,
        );
      }
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
      if (eggQualityScopeKind != StationSampleModel.sampleKindMachine ||
          !SampleMode.isCompare(draft.sampleMode)) {
        return null;
      }
      return draft.setterId ?? draft.soSetterId ?? 'S${(index ?? 0) + 1}';
    }
    if (draft.auditType == 'Chicks' && SampleMode.isCompare(draft.sampleMode)) {
      return draft.setterId ?? draft.soSetterId ?? 'S${(index ?? 0) + 1}';
    }
    if (draft.auditType == 'Setters') {
      return _blankToNull(draft.soSetterId) ??
          _blankToNull(draft.setterId) ??
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
      if (eggQualityScopeKind != StationSampleModel.sampleKindMachine ||
          !SampleMode.isCompare(draft.sampleMode)) {
        return null;
      }
      return draft.hatcherId ?? draft.hoHatcherId ?? 'H${(index ?? 0) + 1}';
    }
    if (draft.auditType == 'Chicks' && SampleMode.isCompare(draft.sampleMode)) {
      return draft.hatcherId ?? draft.hoHatcherId ?? 'H${(index ?? 0) + 1}';
    }
    if (draft.auditType == 'Hatchers') {
      return _blankToNull(draft.hoHatcherId) ??
          _blankToNull(draft.hatcherId) ??
          'H';
    }
    return draft.hatcherId ?? draft.hoHatcherId;
  }

  String? _groupLabelForDraft(AuditModel draft, {String? eggQualityScopeKind}) {
    if (draft.compareGroupKey == null) return null;
    if (draft.auditType == 'Egg') {
      return eggQualityScopeKind == StationSampleModel.sampleKindMachine
          ? 'Machine comparison'
          : 'House comparison';
    }
    if (draft.auditType == 'Chicks') return 'Machine comparison';
    if (draft.auditType == 'Setters') return 'Setter comparison';
    if (draft.auditType == 'Hatchers') return 'Hatcher comparison';
    return 'Comparison';
  }

  int _scopeSerialForSample(StationSampleModel sample, {String? houseNo}) {
    final targetHouseNo = _blankToNull(houseNo ?? sample.houseNo);
    var serial = 0;

    for (final candidate in _stationSamples) {
      if (candidate.stationType != sample.stationType ||
          candidate.sectorType != sample.sectorType ||
          candidate.sampleKind != sample.sampleKind) {
        continue;
      }

      if (sample.stationType == 'egg' &&
          sample.sampleKind == StationSampleModel.sampleKindMachine) {
        final candidateHouseNo = candidate.id == sample.id
            ? targetHouseNo
            : _blankToNull(candidate.houseNo);
        if (targetHouseNo == null) {
          if (candidateHouseNo != null) continue;
        } else if (candidateHouseNo != targetHouseNo) {
          continue;
        }
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

  String _eggMachineSampleLabel({
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
    if (draft.auditType == 'Egg' &&
        sample.sampleKind == StationSampleModel.sampleKindMachine) {
      return _eggMachineSampleLabel(
        setterNo: setterNo,
        hatcherNo: hatcherNo,
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
    final raw = _blankToNull(houseNo);
    if (raw == null) return 'H$fallbackIndex';
    final digits = RegExp(r'\d+').allMatches(raw).map((m) => m.group(0)).join();
    if (digits.isNotEmpty) return 'H$digits';
    return raw;
  }

  String? _houseScopeLabelForNo({
    required String? houseNo,
    required int fallbackIndex,
  }) {
    final raw = _blankToNull(houseNo);
    if (raw == null) return 'House $fallbackIndex';
    final digits = RegExp(r'\d+').allMatches(raw).map((m) => m.group(0)).join();
    if (digits.isNotEmpty) return 'House $digits';
    return raw;
  }

  bool _defaultEggHouseNo(
    String? value, {
    required int index,
    required int sampleIndex,
  }) {
    final trimmed = _blankToNull(value);
    if (trimmed == null) return true;
    return trimmed == 'H${index + 1}' || trimmed == 'H$sampleIndex';
  }

  bool _defaultEggHouseLabel(
    String? value, {
    required int index,
    required int sampleIndex,
  }) {
    final trimmed = _blankToNull(value);
    if (trimmed == null) return true;
    return trimmed == 'House ${index + 1}' || trimmed == 'House $sampleIndex';
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

  int? _storageDaysForDraft(AuditModel draft) {
    final storageDays =
        draft.esEggStorageDays ??
        draft.chickStorageDays ??
        draft.haStorageDays ??
        draft.ebStorageDays;
    if (storageDays != null) return storageDays;
    return switch (draft.auditType) {
      'Egg' || 'Chicks' || 'Hatch Analysis & Egg Breakouts' => 0,
      _ => null,
    };
  }

  int? _storageDaysForPanel(String tableName, AuditModel draft) {
    if (tableName == 'egg_quality') {
      return draft.esEggQualityStorageDays ?? draft.esEggStorageDays ?? 0;
    }
    return _storageDaysForDraft(draft);
  }

  int? _legacyBmkWeeksForDraft(AuditModel draft) {
    return draft.esEggBmkAge ??
        draft.chickBmkAge ??
        draft.haBmkAge ??
        draft.ebBmkAge;
  }

  Future<void> _savePanelTablesForSample(
    AuditModel draft,
    StationSampleModel sample, {
    Set<String> skipTables = const <String>{},
  }) async {
    for (final tableName in _panelTablesForDraft(draft)) {
      if (skipTables.contains(tableName)) continue;
      if (_isEggBreakoutPanelTable(tableName)) {
        await _saveEggBreakoutPanelTable(tableName, draft, sample);
      } else {
        await _savePanelTableWithSamples(tableName, draft, [sample]);
      }
    }
  }

  Future<void> _savePooledEggStoragePanelTable(
    List<({AuditModel draft, StationSampleModel sample})> pairs,
  ) async {
    if (pairs.isEmpty) return;
    final sessionId = pairs.first.sample.auditSessionId;
    if (sessionId.isEmpty) return;

    final draft = _pooledEggStorageDraft([
      for (final pair in pairs) pair.draft,
    ]);
    if (!_hasMeaningfulEggStorageData(draft)) {
      await _panelSampleRepository.deleteRowsBySessionId(
        'egg_storage',
        sessionId,
      );
      return;
    }

    await _panelSampleRepository.deleteHierarchyRowsBySessionId(
      'egg_storage',
      sessionId,
    );
    await _savePanelTableWithSamples('egg_storage', draft, [
      _pooledEggStorageSample(pairs.first.sample, draft),
    ]);
  }

  AuditModel _pooledEggStorageDraft(List<AuditModel> drafts) {
    final base = drafts.first;
    final map = base.toMap();
    for (final key in _pooledEggStorageFieldKeys) {
      map[key] = _firstMeaningfulDraftValue(drafts, key, map[key]);
    }
    map['notes'] = _firstMeaningfulDraftValue(drafts, 'notes', map['notes']);
    map['sampleMode'] = SampleMode.pool;
    map['compareGroupKey'] = null;
    map['hatchNumber'] = 1;
    map['updatedAt'] = DateTime.now().toIso8601String();
    return AuditModel.fromMap(map);
  }

  StationSampleModel _pooledEggStorageSample(
    StationSampleModel sample,
    AuditModel draft,
  ) {
    final now = DateTime.now();
    return StationSampleModel(
      id: sample.id,
      auditSessionId: sample.auditSessionId,
      legacyAuditId: draft.id,
      stationType: sample.stationType,
      sectorType: sample.sectorType,
      sampleKind: StationSampleModel.sampleKindPooled,
      sampleMode: StationSampleModel.sampleModePooled,
      sampleIndex: 1,
      sampleLabel: 'Sample 1',
      sampleType: sample.sampleType,
      breakoutType: sample.breakoutType,
      batchNo: sample.batchNo,
      hatchNo: sample.hatchNo,
      storageDays: _storageDaysForDraft(draft),
      incubationDay: sample.incubationDay,
      calculatedBmkAgeDays: sample.calculatedBmkAgeDays,
      benchmarkBreed: sample.benchmarkBreed,
      benchmarkAgeDays: sample.benchmarkAgeDays,
      benchmarkSource: sample.benchmarkSource,
      benchmarkSnapshotJson: sample.benchmarkSnapshotJson,
      resultSummaryJson: StationSampleMapper.resultSummaryJsonForAudit(draft),
      notes: draft.notes ?? sample.notes,
      createdAt: sample.createdAt,
      updatedAt: now,
    );
  }

  static const _pooledEggStorageFieldKeys = [
    'esEggStorageDays',
    'es_estReadingsJson',
    'es_estPhotosJson',
    'es_estAvg',
    'es_estCv',
    'esShellTemp',
    'esTurningTimes',
    'esUvTrays',
    'es_traySpacing',
    'es_coolerProximity',
    'es_condensation',
  ];

  Object? _firstMeaningfulDraftValue(
    List<AuditModel> drafts,
    String key,
    Object? fallback,
  ) {
    for (final draft in drafts) {
      final value = draft.toMap()[key];
      if (_isMeaningfulPooledEggStorageValue(key, value)) return value;
    }
    return fallback;
  }

  bool _isMeaningfulPooledEggStorageValue(String key, Object? value) {
    if (value == null) return false;
    if (key == 'esEggStorageDays' && value is num) return value != 0;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isNotEmpty && trimmed != '[]' && trimmed != '{}';
    }
    return true;
  }

  bool _hasMeaningfulEggStorageData(AuditModel draft) {
    return _isMeaningfulPooledEggStorageValue(
          'esEggStorageDays',
          draft.esEggStorageDays,
        ) ||
        _hasMeaningfulJsonObject(draft.esEstReadingsJson) ||
        _hasMeaningfulJsonObject(draft.esEstPhotosJson) ||
        draft.esEstAvg != null ||
        draft.esEstCv != null ||
        draft.esShellTemp != null ||
        draft.esTurningTimes != null ||
        _hasText(draft.esTraySpacing) ||
        _hasText(draft.esCoolerProximity) ||
        draft.esCondensation != null ||
        _hasMeaningfulEggStorageTrayData(draft.esUvTrays) ||
        _hasText(draft.notes);
  }

  bool _hasAnyMeaningfulStationData(AuditModel draft) {
    return switch (draft.auditType) {
      'Egg' =>
        _hasMeaningfulEggStorageData(draft) ||
            _hasMeaningfulEggQualityData(draft),
      'Chicks' => _hasMeaningfulChickData(draft),
      'Hatch Analysis & Egg Breakouts' => _hasMeaningfulHatchData(draft),
      'Setters' => _hasMeaningfulSetterData(draft),
      'Hatchers' => _hasMeaningfulHatcherData(draft),
      _ => false,
    };
  }

  bool _hasCoreStationData(AuditModel draft) {
    return switch (draft.auditType) {
      'Egg' =>
        _hasMeaningfulEggStorageCoreData(draft) ||
            _hasMeaningfulEggQualityCoreData(draft),
      'Chicks' => _hasMeaningfulChickCoreData(draft),
      'Hatch Analysis & Egg Breakouts' => _hasMeaningfulHatchCompletionCoreData(
        draft,
      ),
      'Setters' => _hasMeaningfulSetterCoreData(draft),
      'Hatchers' => _hasMeaningfulHatcherCoreData(draft),
      _ => false,
    };
  }

  bool _hasMeaningfulChickCoreData(AuditModel draft) {
    return _hasMeaningfulPasgarData(draft) ||
        _hasMeaningfulChickWeightData(draft);
  }

  bool _hasMeaningfulEggStorageCoreData(AuditModel draft) {
    return _isMeaningfulPooledEggStorageValue(
          'esEggStorageDays',
          draft.esEggStorageDays,
        ) ||
        _hasMeaningfulJsonObject(draft.esEstReadingsJson) ||
        _hasMeaningfulJsonObject(draft.esEstPhotosJson) ||
        draft.esEstAvg != null ||
        draft.esEstCv != null ||
        draft.esShellTemp != null ||
        draft.esTurningTimes != null ||
        _hasText(draft.esTraySpacing) ||
        _hasText(draft.esCoolerProximity) ||
        draft.esCondensation != null ||
        _hasMeaningfulEggStorageTrayData(draft.esUvTrays);
  }

  bool _hasMeaningfulEggQualityCoreData(AuditModel draft) {
    return _hasMeaningfulEggQualityTrayData(draft.esUvTrays) ||
        _hasMeaningfulWeightList(draft.esEggWeights) ||
        (draft.esEggSampleSize ?? 0) > 0 ||
        draft.esEggAvgWeight != null ||
        draft.esEggUniformityPct != null ||
        draft.esEggCvPct != null;
  }

  bool _hasMeaningfulChickData(AuditModel draft) {
    return _hasMeaningfulChickCoreData(draft) ||
        draft.chaCo2 != null ||
        _hasText(draft.chaCo2Photo) ||
        draft.chaPm10 != null ||
        _hasText(draft.chaPm10Photo) ||
        draft.chaPm25 != null ||
        _hasText(draft.chaPm25Photo) ||
        draft.chaAirVelocitySpot1 != null ||
        _hasText(draft.chaAirVelocitySpot1Photo) ||
        draft.chaAirVelocitySpot2 != null ||
        _hasText(draft.chaAirVelocitySpot2Photo) ||
        draft.chaAirVelocitySpot3 != null ||
        _hasText(draft.chaAirVelocitySpot3Photo) ||
        draft.chaAirInlet != null ||
        _hasText(draft.chaAirInletPhoto) ||
        draft.chaAirOutlet != null ||
        _hasText(draft.chaAirOutletPhoto) ||
        draft.chaNoiseLevel != null ||
        _hasText(draft.chaNoiseLevelPhoto) ||
        _hasText(draft.yfbmPhoto) ||
        _hasMeaningfulJsonData(draft.yfbmEntries) ||
        draft.yfbmAvgPct != null ||
        draft.yfbmCvPct != null ||
        (draft.cvtSampleSize ?? 0) > 0 ||
        _hasText(draft.cvtTopBasket) ||
        draft.cvtTopTemp != null ||
        _hasText(draft.cvtTopPhoto) ||
        _hasText(draft.cvtMiddleBasket) ||
        draft.cvtMiddleTemp != null ||
        _hasText(draft.cvtMiddlePhoto) ||
        _hasText(draft.cvtBottomBasket) ||
        draft.cvtBottomTemp != null ||
        _hasText(draft.cvtBottomPhoto) ||
        draft.cvtAvg != null ||
        draft.cvtCvPct != null ||
        _hasMeaningfulJsonObject(draft.cvtReadingsJson) ||
        _hasMeaningfulJsonObject(draft.cvtPhotosJson) ||
        _hasMeaningfulPmData(draft) ||
        (draft.culledChicksTotalEggSet ?? 0) > 0 ||
        _hasMeaningfulJsonData(draft.culledChicksAnalysisJson) ||
        draft.culledChicksAffectedPct != null ||
        _hasText(draft.culledChicksTopCategory) ||
        _hasText(draft.culledChicksTopSubtype) ||
        _hasText(draft.notes);
  }

  bool _hasMeaningfulPasgarData(AuditModel draft) {
    return (draft.pasgarSampleSize ?? 0) > 0 ||
        (draft.pasgarReflexes ?? 0) > 0 ||
        _hasText(draft.pasgarReflexesPhoto) ||
        (draft.pasgarBeak ?? 0) > 0 ||
        _hasText(draft.pasgarBeakPhoto) ||
        (draft.pasgarNavel ?? 0) > 0 ||
        _hasText(draft.pasgarNavelPhoto) ||
        (draft.pasgarBelly ?? 0) > 0 ||
        _hasText(draft.pasgarBellyPhoto) ||
        (draft.pasgarLeg ?? 0) > 0 ||
        _hasText(draft.pasgarLegPhoto) ||
        (draft.pasgarFeatherDev ?? 0) > 0 ||
        _hasText(draft.pasgarFeatherDevPhoto) ||
        draft.pasgarFinalScore != null;
  }

  bool _hasMeaningfulChickWeightData(AuditModel draft) {
    return _hasMeaningfulWeightList(draft.chickWeights) ||
        (draft.chickSampleSize ?? 0) > 0 ||
        draft.chickAvgWeight != null ||
        draft.chickUniformityPct != null ||
        draft.chickCvPct != null ||
        _chickWeightSamples.any(
          (sample) => _hasMeaningfulChickWeightSample(draft, sample),
        );
  }

  bool _hasMeaningfulPmData(AuditModel draft) {
    return (draft.pmSampleSize ?? 0) > 0 ||
        _hasText(draft.pmCollectionPoint) ||
        (draft.pmOmphalitisCount ?? 0) > 0 ||
        _hasText(draft.pmOmphalitisSeverity) ||
        (draft.pmGaseousCecaCount ?? 0) > 0 ||
        _hasText(draft.pmGaseousCecaSeverity) ||
        (draft.pmGizzardErosionsCount ?? 0) > 0 ||
        _hasText(draft.pmGizzardErosionsSeverity) ||
        (draft.pmAirSacCaseationsCount ?? 0) > 0 ||
        _hasText(draft.pmAirSacCaseationsSeverity) ||
        (draft.pmUrolithiasisCount ?? 0) > 0 ||
        _hasText(draft.pmUrolithiasisSeverity) ||
        (draft.pmNephritisCount ?? 0) > 0 ||
        _hasText(draft.pmNephritisSeverity) ||
        (draft.pmGeneralSepticemiaCount ?? 0) > 0 ||
        _hasText(draft.pmGeneralSepticemiaSeverity) ||
        _hasMeaningfulJsonObject(draft.pmOtherLesionsJson) ||
        _hasText(draft.pmSuspectedCauseAuto) ||
        _hasText(draft.pmSuspectedCauseManual) ||
        _hasMeaningfulJsonData(draft.pmPhotosJson);
  }

  bool _hasMeaningfulHatchData(AuditModel draft) {
    return _hasMeaningfulHatchCoreData(draft) || _hasText(draft.notes);
  }

  bool _hasMeaningfulHatchCompletionCoreData(AuditModel draft) {
    return (draft.haHatched ?? 0) > 0 ||
        (draft.haCulled ?? 0) > 0 ||
        (draft.haDead ?? 0) > 0 ||
        draft.haHatchability != null ||
        draft.haFertility != null ||
        draft.haHof != null ||
        _hasMeaningfulJsonData(draft.haTrays) ||
        (draft.haPipped ?? 0) > 0 ||
        (draft.haInfertileClear ?? 0) > 0 ||
        (draft.haEarlyDead ?? 0) > 0 ||
        (draft.haMidDead ?? 0) > 0 ||
        (draft.haMidLateDead ?? 0) > 0 ||
        (draft.haLateDead ?? 0) > 0 ||
        (draft.haContaminatedExploders ?? 0) > 0 ||
        _hasMeaningfulJsonData(draft.haBenchmarkStatusesJson) ||
        _hasMeaningfulBreakoutSamples(draft);
  }

  bool _hasMeaningfulHatchCoreData(AuditModel draft) {
    return (draft.haTotalEggsSet ?? 0) > 0 ||
        _hasMeaningfulHatchCompletionCoreData(draft);
  }

  bool _hasMeaningfulBreakoutSamples(AuditModel draft) {
    if (_hasMeaningfulJsonData(draft.ebTrayBreakoutJson)) return true;
    return (draft.ebTraySize ?? 0) > 0 ||
        (draft.ebInfertileCount ?? 0) > 0 ||
        (draft.ebEarlyDeadCount ?? 0) > 0 ||
        (draft.ebMidDeadCount ?? 0) > 0 ||
        (draft.ebLateDeadCount ?? 0) > 0 ||
        (draft.ebInternalPipCount ?? 0) > 0 ||
        (draft.ebExternalPipCount ?? 0) > 0 ||
        (draft.ebCrackedCount ?? 0) > 0 ||
        (draft.ebContaminatedCount ?? 0) > 0 ||
        (draft.ebMalpositionCount ?? 0) > 0 ||
        (draft.ebExposedBrainCount ?? 0) > 0 ||
        (draft.ebCrossedBeakCount ?? 0) > 0 ||
        (draft.ebCulledDeadCount ?? 0) > 0;
  }

  bool _hasMeaningfulSetterData(AuditModel draft) {
    return _hasMeaningfulSetterCoreData(draft) ||
        draft.soActualF != null ||
        draft.soActualRh != null ||
        _hasText(draft.soBreed) ||
        _hasText(draft.soMachineScreenPhoto) ||
        _hasText(draft.notes);
  }

  bool _hasMeaningfulSetterCoreData(AuditModel draft) {
    return _hasMeaningfulMachineId(
          draft.soSetterId,
          defaultValue: 'S',
          contextValue: _context?.setterId,
        ) ||
        draft.soCo2 != null ||
        _hasText(draft.soCo2Photo) ||
        _hasMeaningfulJsonObject(draft.soEstReadings) ||
        _hasMeaningfulJsonObject(draft.soEstPhotos) ||
        draft.soEstAvg != null ||
        draft.soEstCv != null ||
        ((draft.soIncubationAge ?? 1) != 1) ||
        ((draft.soIncubationHours ?? 0) != 0) ||
        draft.soTurningAngle != null ||
        draft.soSetpointF != null ||
        draft.soSetpointRh != null ||
        _hasMeaningfulSetterEstSamples(draft);
  }

  bool _hasMeaningfulSetterEstSamples(AuditModel draft) {
    for (final sample in _decodedMaps(draft.soEstSamplesJson)) {
      if (_hasText(sample['breed'] as String?) &&
          sample['breed'] != 'Ross308') {
        return true;
      }
      if ((_asInt(sample['incubationAge']) ?? 1) != 1) return true;
      if ((_asInt(sample['incubationHours']) ?? 0) != 0) return true;
      if (_isMeaningfulJsonValue(sample['estReadings'])) return true;
      if (_isMeaningfulJsonValue(sample['estPhotos'])) return true;
      if (sample['estAvg'] != null || sample['estCv'] != null) return true;
    }
    return false;
  }

  bool _hasMeaningfulHatcherData(AuditModel draft) {
    return _hasMeaningfulHatcherCoreData(draft) ||
        _hasText(draft.hoBreed) ||
        draft.hoTransferDay != null ||
        _hasText(draft.notes);
  }

  bool _hasMeaningfulHatcherCoreData(AuditModel draft) {
    return _hasMeaningfulMachineId(
          draft.hoHatcherId,
          defaultValue: 'H',
          contextValue: _context?.hatcherId,
        ) ||
        ((draft.hoIncubationAge ?? 18) != 18) ||
        ((draft.hoIncubationHours ?? 0) != 0) ||
        draft.hoSetpointF != null ||
        draft.hoSetpointRh != null ||
        draft.hoCo2 != null ||
        _hasText(draft.hoCo2Photo) ||
        _hasMeaningfulJsonObject(draft.hoCvtReadings) ||
        _hasMeaningfulJsonObject(draft.hoCvtPhotos) ||
        draft.hoCvtAvg != null ||
        draft.hoCvtCv != null ||
        draft.hoChickPanting != null ||
        _hasText(draft.hoChickPantingPhoto) ||
        _hasText(draft.hoMeconium);
  }

  bool _hasMeaningfulMachineId(
    String? value, {
    required String defaultValue,
    String? contextValue,
  }) {
    final id = _blankToNull(value);
    final contextId = _blankToNull(contextValue);
    return id != null && id != defaultValue && id != contextId;
  }

  bool _hasMeaningfulJsonObject(String? source) {
    final decoded = _decodedMap(source);
    if (decoded == null || decoded.isEmpty) return false;
    return decoded.values.any(_isMeaningfulJsonValue);
  }

  bool _hasMeaningfulJsonData(String? source) {
    if (source == null || source.trim().isEmpty) return false;
    try {
      return _isMeaningfulJsonValue(jsonDecode(source));
    } catch (_) {
      return false;
    }
  }

  bool _hasMeaningfulEggStorageTrayData(String? source) {
    return _decodedMaps(source).any((tray) {
      return (_asInt(tray['totalEggs']) ?? 0) > 0 ||
          (_asInt(tray['upsideDown']) ?? 0) > 0 ||
          _isMeaningfulJsonValue(tray['photoPath']);
    });
  }

  bool _hasAnyMeaningfulEggQualityData(
    List<({AuditModel draft, StationSampleModel sample})> pairs,
  ) {
    return pairs.any((pair) => _hasMeaningfulEggQualityData(pair.draft));
  }

  List<_PanelSavePair> _scopedPanelSavePairs(List<_PanelSavePair> pairs) {
    if (pairs.isEmpty) return pairs;

    final hatchBreakoutPrunedPairs = _pruneHatchBreakoutParentPairs(pairs);
    final eggHouseKeysWithMachineChildren = <String>{};
    for (final pair in hatchBreakoutPrunedPairs) {
      final sample = pair.sample;
      if (pair.draft.auditType != 'Egg' ||
          sample.sampleKind != StationSampleModel.sampleKindMachine) {
        continue;
      }
      final houseKey = _blankToNull(sample.houseNo);
      if (houseKey != null) eggHouseKeysWithMachineChildren.add(houseKey);
    }
    if (eggHouseKeysWithMachineChildren.isEmpty) {
      return hatchBreakoutPrunedPairs;
    }

    return [
      for (final pair in hatchBreakoutPrunedPairs)
        if (!_isDefaultedEggQualityParentPair(
          pair,
          eggHouseKeysWithMachineChildren,
        ))
          pair,
    ];
  }

  List<_PanelSavePair> _pruneHatchBreakoutParentPairs(
    List<_PanelSavePair> pairs,
  ) {
    final paths = <_BreakoutHierarchyPath>[];
    for (var i = 0; i < pairs.length; i++) {
      final pair = pairs[i];
      if (pair.draft.auditType != 'Hatch Analysis & Egg Breakouts') {
        continue;
      }
      for (final tableName in _panelTablesForDraft(pair.draft)) {
        if (!_isEggBreakoutPanelTable(tableName)) continue;
        paths.addAll(_breakoutHierarchyPathsForPair(i, tableName, pair));
      }
    }
    if (paths.length < 2) return pairs;

    final parentPairIndexes = <int>{};
    for (final path in paths) {
      if (!path.canHaveChildren) continue;
      final hasChild = paths.any(
        (candidate) =>
            candidate.pairIndex != path.pairIndex && path.isParentOf(candidate),
      );
      if (hasChild) parentPairIndexes.add(path.pairIndex);
    }
    if (parentPairIndexes.isEmpty) return pairs;

    return [
      for (var i = 0; i < pairs.length; i++)
        if (!parentPairIndexes.contains(i)) pairs[i],
    ];
  }

  List<_BreakoutHierarchyPath> _breakoutHierarchyPathsForPair(
    int pairIndex,
    String tableName,
    _PanelSavePair pair,
  ) {
    final entries = _breakoutLeafEntriesForTable(tableName, pair.draft);
    if (entries.isEmpty) {
      final panel = _panelRecordForSamples(tableName, pair.draft, [
        pair.sample,
      ]);
      final panelSample = _panelSampleRecordForStationSample(
        tableName: tableName,
        panelId: panel.id,
        draft: pair.draft,
        sample: pair.sample,
      );
      return [
        _BreakoutHierarchyPath(
          pairIndex: pairIndex,
          sessionId: pair.sample.auditSessionId,
          tableName: tableName,
          scopeType: panelSample.scopeType,
          house: _blankToNull(panelSample.houseId),
          setter: _blankToNull(panelSample.setterId),
          hatcher: _blankToNull(panelSample.hatcherId),
          trolley: _blankToNull(panelSample.trolleyLabel),
          tray: _blankToNull(panelSample.trayLabel),
          position: _blankToNull(panelSample.position),
        ),
      ];
    }

    final breakoutType = _breakoutTypeForTable(tableName);
    final useDraftBatchHierarchy =
        breakoutType != EggBreakoutType.freshEggBreakout &&
        SampleMode.isCompare(pair.draft.sampleMode);
    return [
      for (final entry in entries)
        _BreakoutHierarchyPath(
          pairIndex: pairIndex,
          sessionId: pair.sample.auditSessionId,
          tableName: tableName,
          scopeType: _breakoutScopeTypeForEntry(
            tableName: tableName,
            entry: entry,
            breakoutType: breakoutType,
          ),
          house: breakoutType == EggBreakoutType.freshEggBreakout
              ? _blankToNull(entry.house)
              : _blankToNull(entry.house) ??
                    (useDraftBatchHierarchy
                        ? _blankToNull(pair.draft.houseId)
                        : null),
          setter: breakoutType == EggBreakoutType.freshEggBreakout
              ? null
              : _blankToNull(entry.setter) ??
                    (useDraftBatchHierarchy
                        ? _blankToNull(pair.draft.setterId)
                        : null),
          hatcher: breakoutType == EggBreakoutType.freshEggBreakout
              ? null
              : _blankToNull(entry.hatcher) ??
                    (useDraftBatchHierarchy
                        ? _blankToNull(pair.draft.hatcherId)
                        : null),
          trolley: breakoutType == EggBreakoutType.freshEggBreakout
              ? null
              : _blankToNull(entry.trolley),
          tray: _blankToNull(entry.tray),
          position: breakoutType == EggBreakoutType.freshEggBreakout
              ? null
              : _blankToNull(entry.position),
        ),
    ];
  }

  bool _isDefaultedEggQualityParentPair(
    _PanelSavePair pair,
    Set<String> houseKeysWithMachineChildren,
  ) {
    final sample = pair.sample;
    if (pair.draft.auditType != 'Egg' ||
        sample.sampleKind != StationSampleModel.sampleKindHouse) {
      return false;
    }
    final houseKey = _eggQualityHouseKey(sample);
    return houseKey != null && houseKeysWithMachineChildren.contains(houseKey);
  }

  String? _eggQualityHouseKey(StationSampleModel sample) {
    return _blankToNull(sample.houseNo) ?? _blankToNull(sample.sampleLabel);
  }

  Future<void> _deleteEggQualityRowsBySessionId(
    List<_PanelSavePair> pairs,
  ) async {
    if (pairs.isEmpty) return;
    final sessionId = pairs.first.sample.auditSessionId;
    if (sessionId.isEmpty) return;
    await _panelSampleRepository.deleteRowsBySessionId(
      'egg_quality',
      sessionId,
    );
  }

  bool _hasMeaningfulPanelData(_PanelSavePair pair) {
    return _panelTablesForDraft(
      pair.draft,
    ).any((tableName) => _hasMeaningfulPanelTableData(tableName, pair.draft));
  }

  bool _hasMeaningfulPanelTableData(String tableName, AuditModel draft) {
    return switch (tableName) {
      'egg_storage' => _hasMeaningfulEggStorageData(draft),
      'egg_quality' => _hasMeaningfulEggQualityData(draft),
      'chick_quality' => _hasMeaningfulChickData(draft),
      'fresh_egg_breakout' ||
      'candled_egg_breakout' ||
      'residue_breakout' => _hasMeaningfulHatchData(draft),
      'setter_optimizing' => _hasMeaningfulSetterData(draft),
      'hatcher_optimizing' => _hasMeaningfulHatcherData(draft),
      _ => false,
    };
  }

  Future<void> _deleteDiscardedPanelRows(List<_PanelSavePair> pairs) async {
    final deleted = <String>{};
    for (final pair in pairs) {
      if (pair.draft.auditType == 'Egg') continue;
      final sessionId = pair.sample.auditSessionId;
      if (sessionId.isEmpty) continue;
      for (final tableName in _panelTablesForDraft(pair.draft)) {
        if (_hasMeaningfulPanelTableData(tableName, pair.draft)) continue;
        final key = '$sessionId::$tableName';
        if (!deleted.add(key)) continue;
        await _panelSampleRepository.deleteRowsBySessionId(
          tableName,
          sessionId,
        );
      }
    }
  }

  Future<void> _deleteDiscardedChickWeightRows(
    List<StationSampleModel> allSamples,
    List<StationSampleModel> meaningfulSamples,
  ) async {
    if (allSamples.isEmpty) return;
    final meaningfulIds = meaningfulSamples.map((sample) => sample.id).toSet();
    final discardedIds = {
      for (final sample in allSamples)
        if (!meaningfulIds.contains(sample.id)) sample.id,
    };
    if (discardedIds.isEmpty) return;
    final sessionId = allSamples.first.auditSessionId;
    if (sessionId.isEmpty) return;
    await _panelSampleRepository.deleteRowsBySessionIdForSampleIds(
      'chick_weights',
      sessionId,
      discardedIds,
    );
  }

  Future<void> _deletePanelRowsForRemovedSamples({
    required List<AuditModel> draftsToSave,
    required List<String> removedStationSampleIds,
  }) async {
    final sampleIds = removedStationSampleIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (sampleIds.isEmpty || draftsToSave.isEmpty) return;

    final sessionId =
        _activeSessionId ??
        draftsToSave.first.sessionId ??
        (_stationSamples.isEmpty ? null : _stationSamples.first.auditSessionId);
    if (sessionId == null || sessionId.isEmpty) return;

    final tableNames = <String>{
      for (final draft in draftsToSave) ..._panelTablesForDraft(draft),
      if (_isChicksContext) 'chick_weights',
    };
    for (final tableName in tableNames) {
      await _panelSampleRepository.deleteRowsBySessionIdForSampleIds(
        tableName,
        sessionId,
        sampleIds,
      );
    }
  }

  Future<void> _pruneStalePanelHierarchyRows(List<_PanelSavePair> pairs) async {
    if (pairs.isEmpty) return;
    final pairsByKey = <String, List<_PanelSavePair>>{};
    final tableByKey = <String, String>{};
    for (final pair in pairs) {
      final sessionId = pair.sample.auditSessionId;
      if (sessionId.isEmpty) continue;
      for (final tableName in _panelTablesForScopedPrune(pair)) {
        final key = '$sessionId::$tableName';
        tableByKey[key] = tableName;
        pairsByKey.putIfAbsent(key, () => <_PanelSavePair>[]).add(pair);
      }
    }
    for (final entry in pairsByKey.entries) {
      final separatorIndex = entry.key.indexOf('::');
      final sessionId = entry.key.substring(0, separatorIndex);
      final tableName = tableByKey[entry.key];
      if (tableName == null) continue;
      await _pruneStalePanelHierarchyRowsForTable(
        tableName,
        sessionId,
        entry.value,
      );
    }
  }

  Iterable<String> _panelTablesForScopedPrune(_PanelSavePair pair) sync* {
    for (final tableName in _panelTablesForDraft(pair.draft)) {
      if (tableName == 'egg_storage') continue;
      if (_isEggBreakoutPanelTable(tableName)) continue;
      if (pair.draft.auditType == 'Egg' &&
          tableName == 'egg_quality' &&
          !_hasMeaningfulEggQualityData(pair.draft)) {
        continue;
      }
      yield tableName;
    }
  }

  Future<void> _pruneStalePanelHierarchyRowsForTable(
    String tableName,
    String sessionId,
    List<_PanelSavePair> pairs,
  ) async {
    if (pairs.isEmpty) return;
    final keepIds = <String>{};
    final keepHierarchyRows = <Map<String, Object?>>[];
    for (final pair in pairs) {
      final row = _panelHierarchyRowForSample(
        tableName,
        pair.draft,
        pair.sample,
      );
      keepIds.add(row['id']! as String);
      keepHierarchyRows.add(row);
    }
    await _panelSampleRepository.deleteHierarchyRowsBySessionIdExcept(
      tableName,
      sessionId,
      keepIds,
      keepHierarchyRows: keepHierarchyRows,
    );
  }

  Future<void> _pruneStaleBreakoutRows(List<_PanelSavePair> pairs) async {
    if (pairs.isEmpty) return;
    final pairsByKey = <String, List<_PanelSavePair>>{};
    final tableByKey = <String, String>{};
    for (final pair in pairs) {
      final sessionId = pair.sample.auditSessionId;
      if (sessionId.isEmpty) continue;
      for (final tableName in _panelTablesForDraft(pair.draft)) {
        if (!_isEggBreakoutPanelTable(tableName)) continue;
        final key = '$sessionId::$tableName';
        tableByKey[key] = tableName;
        pairsByKey.putIfAbsent(key, () => <_PanelSavePair>[]).add(pair);
      }
    }

    for (final entry in pairsByKey.entries) {
      final separatorIndex = entry.key.indexOf('::');
      final sessionId = entry.key.substring(0, separatorIndex);
      final tableName = tableByKey[entry.key];
      if (tableName == null) continue;
      final keepIds = <String>{};
      final keepHierarchyRows = <Map<String, Object?>>[];
      for (final pair in entry.value) {
        final rows = await _breakoutPanelRowsForTable(
          tableName,
          pair.draft,
          pair.sample,
        );
        for (final row in rows) {
          keepIds.add(row.sample.id);
          keepHierarchyRows.add(_panelHierarchyRowForPanelSample(row.sample));
        }
      }
      await _panelSampleRepository.deleteRowsBySessionIdExcept(
        tableName,
        sessionId,
        keepIds,
        keepHierarchyRows: keepHierarchyRows,
      );
    }
  }

  Map<String, Object?> _panelHierarchyRowForPanelSample(
    PanelSampleRecord sample,
  ) {
    return {
      'id': sample.id,
      'house': _blankToNull(sample.houseId) ?? _blankToNull(sample.houseName),
      'setter': _blankToNull(sample.setterId),
      'hatcher': _blankToNull(sample.hatcherId),
      'trolley':
          _blankToNull(sample.trolleyLabel) ?? _blankToNull(sample.trolleyId),
      'tray': _blankToNull(sample.trayLabel) ?? _blankToNull(sample.trayId),
      'position': _blankToNull(sample.position),
    };
  }

  Map<String, Object?> _panelHierarchyRowForSample(
    String tableName,
    AuditModel draft,
    StationSampleModel sample,
  ) {
    final panel = _panelRecordForSamples(tableName, draft, [sample]);
    final panelSample = _panelSampleRecordForStationSample(
      tableName: tableName,
      panelId: panel.id,
      draft: draft,
      sample: sample,
    );
    return {
      'id': panelSample.id,
      'house':
          _blankToNull(panelSample.houseId) ??
          _blankToNull(panelSample.houseName) ??
          _blankToNull(panel.house),
      'setter':
          _blankToNull(panelSample.setterId) ?? _blankToNull(panel.setter),
      'hatcher':
          _blankToNull(panelSample.hatcherId) ?? _blankToNull(panel.hatcher),
      'trolley':
          _blankToNull(panelSample.trolleyLabel) ??
          _blankToNull(panelSample.trolleyId) ??
          _blankToNull(panel.trolley),
      'tray':
          _blankToNull(panelSample.trayLabel) ??
          _blankToNull(panelSample.trayId) ??
          _blankToNull(panel.tray),
      'position':
          _blankToNull(panelSample.position) ?? _blankToNull(panel.position),
    };
  }

  bool _hasMeaningfulEggQualityData(AuditModel draft) {
    return _hasMeaningfulEggQualityTrayData(draft.esUvTrays) ||
        _hasMeaningfulWeightList(draft.esEggWeights) ||
        (draft.esEggSampleSize ?? 0) > 0 ||
        draft.esEggAvgWeight != null ||
        draft.esEggUniformityPct != null ||
        draft.esEggCvPct != null ||
        _hasText(draft.notes);
  }

  bool _hasMeaningfulEggQualityTrayData(String? source) {
    return _decodedMaps(source).any((tray) {
      return tray['qualityTouched'] == true ||
          (_asInt(tray['cuticleDamage']) ?? 0) > 0 ||
          (_asInt(tray['washed']) ?? 0) > 0 ||
          (_asInt(tray['dirty']) ?? 0) > 0 ||
          _isMeaningfulJsonValue(tray['photoPath']);
    });
  }

  bool _hasMeaningfulWeightList(String? source) {
    if (source == null || source.trim().isEmpty) return false;
    return _weightSampleSizeFromDecoded(_decodedWeights(source)) != null;
  }

  bool _hasMeaningfulChickWeightSample(
    AuditModel draft,
    StationSampleModel sample,
  ) {
    final values = _chickWeightValuesForSample(sample, fallback: draft);
    return _hasMeaningfulWeightList(values['weightsJson'] as String?) ||
        (_asInt(values['sampleSize']) ?? 0) > 0 ||
        values['avgWeight'] != null ||
        values['uniformityPct'] != null ||
        values['cvPct'] != null;
  }

  bool _isMeaningfulJsonValue(Object? value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is Iterable) return value.any(_isMeaningfulJsonValue);
    if (value is Map) return value.values.any(_isMeaningfulJsonValue);
    return true;
  }

  Future<void> _saveEggBreakoutPanelTable(
    String tableName,
    AuditModel draft,
    StationSampleModel sample,
  ) async {
    final rows = await _breakoutPanelRowsForTable(tableName, draft, sample);
    for (final row in rows) {
      await _panelSampleRepository.savePanelWithSamples(
        panel: row.panel,
        samples: [row.sample],
      );
    }
  }

  Future<List<({PanelRecord panel, PanelSampleRecord sample})>>
  _breakoutPanelRowsForTable(
    String tableName,
    AuditModel draft,
    StationSampleModel sample,
  ) async {
    final entries = _breakoutLeafEntriesForTable(tableName, draft);
    if (entries.isEmpty) {
      final panel = _panelRecordForSamples(tableName, draft, [sample]);
      return [
        (
          panel: panel,
          sample: _panelSampleRecordForStationSample(
            tableName: tableName,
            panelId: panel.id,
            draft: draft,
            sample: sample,
          ),
        ),
      ];
    }

    final breakoutType = _breakoutTypeForTable(tableName);
    final benchmark = await _breakoutBenchmarkForDraft(draft, breakoutType);
    final basePanel = _panelRecordForSamples(tableName, draft, [sample]);
    final baseRowId = '${basePanel.id}:${sample.id}';
    final rows = <({PanelRecord panel, PanelSampleRecord sample})>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final label = _breakoutTrayLabel(entry, i);
      final isFresh = breakoutType == EggBreakoutType.freshEggBreakout;
      final useDraftBatchHierarchy =
          !isFresh && SampleMode.isCompare(draft.sampleMode);
      final entryHouse = _blankToNull(entry.house);
      final entrySetter = _blankToNull(entry.setter);
      final entryHatcher = _blankToNull(entry.hatcher);
      final houseValue = isFresh
          ? entryHouse
          : entryHouse ??
                (useDraftBatchHierarchy ? _blankToNull(draft.houseId) : null);
      final setterValue = isFresh
          ? null
          : entrySetter ??
                (useDraftBatchHierarchy ? _blankToNull(draft.setterId) : null);
      final hatcherValue = isFresh
          ? null
          : entryHatcher ??
                (useDraftBatchHierarchy ? _blankToNull(draft.hatcherId) : null);
      final values = _breakoutValuesForEntry(
        tableName,
        draft,
        entry,
        benchmark,
      );
      final scopeType = _breakoutScopeTypeForEntry(
        tableName: tableName,
        entry: entry,
        breakoutType: breakoutType,
      );
      final panel = PanelRecord(
        id: basePanel.id,
        tableName: tableName,
        sessionId: basePanel.sessionId,
        customerId: basePanel.customerId,
        flockId: basePanel.flockId,
        hatcheryId: basePanel.hatcheryId,
        date: basePanel.date,
        breed: basePanel.breed,
        flockAgeWeeks: basePanel.flockAgeWeeks,
        storagePeriodDays: basePanel.storagePeriodDays,
        bmkAgeWeeks: _asInt(values['bmkAgeWeeks']) ?? basePanel.bmkAgeWeeks,
        mode: scopeType == SamplingLayer.pool
            ? PanelRecord.modePool
            : PanelRecord.modeCompare,
        scopeType: scopeType,
        scopeLabel: _breakoutScopeLabelForEntry(scopeType, entry, label),
        sampleIndex: i + 1,
        groupKey: basePanel.groupKey,
        groupLabel:
            basePanel.groupLabel ?? _breakoutGroupLabelForScope(scopeType),
        notes: basePanel.notes,
        syncStatus: basePanel.syncStatus,
        lastSyncedAt: basePanel.lastSyncedAt,
        syncError: basePanel.syncError,
        values: values,
        createdAt: basePanel.createdAt,
        updatedAt: basePanel.updatedAt,
      );
      final panelSample = PanelSampleRecord(
        id: _breakoutEntryRowId(baseRowId, i, entry, scopeType),
        panelId: basePanel.id,
        scopeType: scopeType,
        scopeLabel: _breakoutScopeLabelForEntry(scopeType, entry, label),
        sampleIndex: i + 1,
        houseId: houseValue,
        houseName: houseValue,
        setterId: setterValue,
        hatcherId: hatcherValue,
        trolleyId: isFresh || _scopeBeforeTrolley(scopeType)
            ? null
            : _blankToNull(entry.trolley),
        trolleyLabel: isFresh || _scopeBeforeTrolley(scopeType)
            ? null
            : _blankToNull(entry.trolley),
        trayId: scopeType == SamplingLayer.tray
            ? _blankToNull(entry.tray) ?? _blankToNull(entry.id)
            : null,
        trayLabel: scopeType == SamplingLayer.tray
            ? _blankToNull(entry.tray) ?? label
            : null,
        position: isFresh || scopeType != SamplingLayer.tray
            ? null
            : _blankToNull(entry.position),
        sampleSize: entry.totalSample,
        summaryJson: jsonEncode(entry.toJson()),
        rawJson: _compactJson({
          ...sample.toMap(),
          'breakoutTray': entry.toJson(),
        }),
        notes: sample.notes,
        createdAt: sample.createdAt,
        updatedAt: sample.updatedAt,
      );
      rows.add((panel: panel, sample: panelSample));
    }
    return rows;
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

  Future<void> _saveChickWeightPanelSamples(
    AuditModel draft,
    List<StationSampleModel> samples,
  ) async {
    final pairs = [
      for (final sample in samples)
        (
          draft: _draftWithChickWeightSampleValues(draft, sample),
          sample: sample,
        ),
    ];
    for (final pair in pairs) {
      await _savePanelTableWithSamples('chick_weights', pair.draft, [
        pair.sample,
      ]);
    }
    await _pruneStalePanelHierarchyRowsForTable(
      'chick_weights',
      samples.first.auditSessionId,
      pairs,
    );
  }

  List<String> _panelTablesForDraft(AuditModel draft) {
    return switch (draft.auditType) {
      'Egg' => const ['egg_storage', 'egg_quality'],
      'Chicks' => const ['chick_quality'],
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
      customerId: draft.customerId,
      flockId: _blankToNull(draft.flockId),
      date: draft.date,
      hatcheryId: _blankToNull(_context?.hatcheryId),
      breed: _context?.breed ?? draft.soBreed ?? draft.hoBreed,
      flockAgeWeeks: _context?.flockAgeWeeks,
      storagePeriodDays: _storageDaysForPanel(tableName, draft),
      bmkAgeWeeks: _legacyBmkWeeksForDraft(draft),
      mode: mode,
      scopeType: compareLayer ?? SamplingLayer.pool,
      notes: draft.notes,
      values: _panelValuesForDraft(tableName, draft),
      createdAt: draft.createdAt,
      updatedAt: draft.updatedAt,
    );
  }

  Map<String, Object?> _panelValuesForDraft(
    String tableName,
    AuditModel draft,
  ) {
    return switch (tableName) {
      'egg_storage' => _eggStorageValues(draft),
      'egg_quality' => _eggQualityValues(draft),
      'chick_quality' => _chickQualityValues(draft),
      'chick_weights' => _chickWeightValues(draft),
      'fresh_egg_breakout' => _freshBreakoutValues(draft),
      'candled_egg_breakout' => _candledBreakoutValues(draft),
      'residue_breakout' => _residueBreakoutValues(draft),
      'setter_optimizing' => {
        'machineType': draft.soMachineType,
        'setpointF': draft.soSetpointF,
        'actualF': draft.soActualF,
        'setpointRh': draft.soSetpointRh,
        'actualRh': draft.soActualRh,
        'batchSize': draft.soBatchSize,
        'batchCount': draft.soBatchCount,
        'totalEggsSet': draft.soTotalEggsSet,
        'turningAngle': draft.soTurningAngle,
        'co2Ppm': draft.soCo2,
        'co2Photo': draft.soCo2Photo,
        'estBreed': draft.soBreed,
        'incubationAgeDays': draft.soIncubationAge,
        'incubationHours': draft.soIncubationHours,
        'estReadingsJson': draft.soEstReadings,
        'estPhotosJson': draft.soEstPhotos,
        'estSamplesJson': draft.soEstSamplesJson,
        'estSampleSize': _decodedReadingCount(draft.soEstReadings),
        'estAvg': draft.soEstAvg,
        'estCvPct': draft.soEstCv,
        'machineScreenPhoto': draft.soMachineScreenPhoto,
      },
      'hatcher_optimizing' => {
        'setpointF': draft.hoSetpointF,
        'setpointRh': draft.hoSetpointRh,
        'incubationAgeDays': draft.hoIncubationAge,
        'incubationHours': draft.hoIncubationHours,
        'co2Ppm': draft.hoCo2,
        'co2Photo': draft.hoCo2Photo,
        'cvtReadingsJson': draft.hoCvtReadings,
        'cvtPhotosJson': draft.hoCvtPhotos,
        'cvtSampleSize': _decodedReadingCount(draft.hoCvtReadings),
        'cvtAvg': draft.hoCvtAvg,
        'cvtCvPct': draft.hoCvtCv,
        'chickPanting': _boolToInt(draft.hoChickPanting),
        'chickPantingPhoto': draft.hoChickPantingPhoto,
        'meconium': draft.hoMeconium,
        'transferDay': draft.hoTransferDay,
      },
      _ => const <String, Object?>{},
    };
  }

  Map<String, Object?> _eggStorageValues(AuditModel draft) {
    final trays = _decodedMaps(draft.esUvTrays);
    var trayEggCount = 0;
    var upsideDown = 0;
    for (final tray in trays) {
      trayEggCount += _asInt(tray['totalEggs']) ?? 0;
      upsideDown += _asInt(tray['upsideDown']) ?? 0;
    }
    return {
      'storagePeriodDays': draft.esEggStorageDays ?? 0,
      'estReadingsJson': draft.esEstReadingsJson,
      'estAvg': draft.esEstAvg,
      'estCvPct': draft.esEstCv,
      'shellTemp': draft.esShellTemp,
      'turningTimes': draft.esTurningTimes,
      'traySpacing': draft.esTraySpacing,
      'coolerProximity': draft.esCoolerProximity,
      'condensationPresent': _boolToInt(draft.esCondensation),
      'upsideDownCount': upsideDown,
      'upsideDownPct': _pct(upsideDown, trayEggCount),
    };
  }

  Map<String, Object?> _eggQualityValues(AuditModel draft) {
    final trays = _decodedMaps(draft.esUvTrays);
    var trayEggCount = 0;
    var cuticleDamage = 0;
    var washed = 0;
    var dirty = 0;
    for (final tray in trays) {
      trayEggCount += _asInt(tray['totalEggs']) ?? 0;
      cuticleDamage += _asInt(tray['cuticleDamage']) ?? 0;
      washed += _asInt(tray['washed']) ?? 0;
      dirty += _asInt(tray['dirty']) ?? 0;
    }
    final affected = cuticleDamage + washed + dirty;
    final uvDenominator = trayEggCount == 0
        ? draft.esUvSampleSize
        : trayEggCount;
    return {
      'storagePeriodDays':
          draft.esEggQualityStorageDays ?? draft.esEggStorageDays ?? 0,
      'uvTrayEggCount': uvDenominator,
      'uvCuticleDamageCount': cuticleDamage,
      'uvCuticleDamagePct': _pct(cuticleDamage, uvDenominator),
      'uvWashedCount': washed,
      'uvWashedPct': _pct(washed, uvDenominator),
      'uvDirtyCount': dirty,
      'uvDirtyPct': _pct(dirty, uvDenominator),
      'uvAffectedCount': affected,
      'uvAffectedPct': _pct(affected, uvDenominator),
      'eggWeightsJson': draft.esEggWeights,
      'eggSampleSize': draft.esEggSampleSize,
      'eggAvgWeight': draft.esEggAvgWeight,
      'eggUniformityPct': draft.esEggUniformityPct,
      'eggCvPct': draft.esEggCvPct,
      'eggBmkAgeWeeks': draft.esEggBmkAge,
      'eggBmkWeight': draft.esEggBmkWeight,
    };
  }

  Map<String, Object?> _chickQualityValues(AuditModel draft) {
    final size = draft.pasgarSampleSize;
    final culledChicksTotalEggSet =
        draft.culledChicksTotalEggSet ??
        (draft.culledChicksAnalysisJson == null
            ? null
            : kDefaultCulledChicksTotalEggSet);
    final culledChicksSummary = CulledChicksAnalysisSummary.fromJson(
      draft.culledChicksAnalysisJson,
      totalEggSet: culledChicksTotalEggSet,
    );
    return {
      'pasgarSampleSize': size,
      'pasgarReflexesCount': draft.pasgarReflexes,
      'pasgarBeakCount': draft.pasgarBeak,
      'pasgarNavelCount': draft.pasgarNavel,
      'pasgarBellyCount': draft.pasgarBelly,
      'pasgarLegCount': draft.pasgarLeg,
      'pasgarFeatherDevCount': draft.pasgarFeatherDev,
      'pasgarReflexesPct': _pct(draft.pasgarReflexes, size),
      'pasgarBeakPct': _pct(draft.pasgarBeak, size),
      'pasgarNavelPct': _pct(draft.pasgarNavel, size),
      'pasgarBellyPct': _pct(draft.pasgarBelly, size),
      'pasgarLegPct': _pct(draft.pasgarLeg, size),
      'pasgarFeatherDevPct': _pct(draft.pasgarFeatherDev, size),
      'pasgarFinalScore': draft.pasgarFinalScore,
      'co2Ppm': draft.chaCo2,
      'co2Photo': draft.chaCo2Photo,
      'pm10': draft.chaPm10,
      'pm10Photo': draft.chaPm10Photo,
      'pm25': draft.chaPm25,
      'pm25Photo': draft.chaPm25Photo,
      'airVelocitySpot1': draft.chaAirVelocitySpot1,
      'airVelocitySpot1Photo': draft.chaAirVelocitySpot1Photo,
      'airVelocitySpot2': draft.chaAirVelocitySpot2,
      'airVelocitySpot2Photo': draft.chaAirVelocitySpot2Photo,
      'airVelocitySpot3': draft.chaAirVelocitySpot3,
      'airVelocitySpot3Photo': draft.chaAirVelocitySpot3Photo,
      'airInlet': draft.chaAirInlet,
      'airInletPhoto': draft.chaAirInletPhoto,
      'airOutlet': draft.chaAirOutlet,
      'airOutletPhoto': draft.chaAirOutletPhoto,
      'noiseLevel': draft.chaNoiseLevel,
      'noiseLevelPhoto': draft.chaNoiseLevelPhoto,
      'yfbmPhoto': draft.yfbmPhoto,
      'yfbmEntriesJson': draft.yfbmEntries,
      'yfbmEntryCount': _decodedListLength(draft.yfbmEntries),
      'yfbmAvgPct': draft.yfbmAvgPct,
      'yfbmCvPct': draft.yfbmCvPct,
      'cvtReadingsJson': draft.cvtReadingsJson,
      'cvtPhotosJson': draft.cvtPhotosJson,
      'cvtSampleSize': draft.cvtSampleSize,
      'cvtTopBasket': draft.cvtTopBasket,
      'cvtTopTemp': draft.cvtTopTemp,
      'cvtTopPhoto': draft.cvtTopPhoto,
      'cvtMiddleBasket': draft.cvtMiddleBasket,
      'cvtMiddleTemp': draft.cvtMiddleTemp,
      'cvtMiddlePhoto': draft.cvtMiddlePhoto,
      'cvtBottomBasket': draft.cvtBottomBasket,
      'cvtBottomTemp': draft.cvtBottomTemp,
      'cvtBottomPhoto': draft.cvtBottomPhoto,
      'cvtAvgTemp': draft.cvtAvg,
      'cvtCvPct': draft.cvtCvPct,
      ..._chickPmValues(draft),
      'culledChicksTotalEggSet': culledChicksTotalEggSet,
      'culledChicksAnalysisJson': culledChicksSummary.encodedJson,
      'culledChicksAffectedPct': culledChicksSummary.affectedPct,
      'culledChicksTopCategory': culledChicksSummary.topCategory,
      'culledChicksTopSubtype': culledChicksSummary.topSubtype,
    };
  }

  Map<String, Object?> _chickWeightValues(AuditModel draft) {
    return {
      'weightsJson': draft.chickWeights,
      'sampleSize': draft.chickSampleSize,
      'avgWeight': draft.chickAvgWeight,
      'uniformityPct': draft.chickUniformityPct,
      'cvPct': draft.chickCvPct,
      'bmkAgeWeeks': draft.chickBmkAge,
      'bmkWeight': draft.chickBmkWeight,
    };
  }

  AuditModel _draftWithChickWeightSampleValues(
    AuditModel draft,
    StationSampleModel sample,
  ) {
    final values = _chickWeightValuesForSample(sample, fallback: draft);
    final map = draft.toMap()
      ..['chickWeights'] = values['weightsJson']
      ..['chickSampleSize'] = values['sampleSize']
      ..['chickAvgWeight'] = values['avgWeight']
      ..['chickUniformityPct'] = values['uniformityPct']
      ..['chickCvPct'] = values['cvPct']
      ..['chickBmkAge'] = values['bmkAgeWeeks']
      ..['chickBmkWeight'] = values['bmkWeight'];
    return AuditModel.fromMap(map);
  }

  Map<String, Object?> _chickWeightValuesForSample(
    StationSampleModel sample, {
    required AuditModel fallback,
  }) {
    final summary = _decodedMap(sample.resultSummaryJson);
    if (summary == null) {
      if (sample.sampleMode == StationSampleModel.sampleModeComparison) {
        return _emptyChickWeightValues(fallback);
      }
      return _chickWeightValues(fallback);
    }

    final weights = summary['chickWeights'];
    return {
      'weightsJson': weights is List ? jsonEncode(weights) : null,
      'sampleSize': weights is List
          ? _weightSampleSizeFromDecoded(weights)
          : null,
      'avgWeight': _asDouble(summary['chickAvgWeight']),
      'uniformityPct': _asDouble(summary['chickUniformityPct']),
      'cvPct': _asDouble(summary['chickCvPct']),
      'bmkAgeWeeks': fallback.chickBmkAge,
      'bmkWeight': fallback.chickBmkWeight,
    };
  }

  Map<String, Object?> _emptyChickWeightValues(AuditModel fallback) {
    return {
      'weightsJson': null,
      'sampleSize': null,
      'avgWeight': null,
      'uniformityPct': null,
      'cvPct': null,
      'bmkAgeWeeks': fallback.chickBmkAge,
      'bmkWeight': fallback.chickBmkWeight,
    };
  }

  Map<String, Object?> _chickPmValues(AuditModel draft) {
    return {
      'pmSampleSize': draft.pmSampleSize,
      'pmCollectionPoint': draft.pmCollectionPoint,
      'pmOmphalitisCount': draft.pmOmphalitisCount,
      'pmOmphalitisSeverity': draft.pmOmphalitisSeverity,
      'pmGaseousCecaCount': draft.pmGaseousCecaCount,
      'pmGaseousCecaSeverity': draft.pmGaseousCecaSeverity,
      'pmGizzardErosionsCount': draft.pmGizzardErosionsCount,
      'pmGizzardErosionsSeverity': draft.pmGizzardErosionsSeverity,
      'pmAirSacCaseationsCount': draft.pmAirSacCaseationsCount,
      'pmAirSacCaseationsSeverity': draft.pmAirSacCaseationsSeverity,
      'pmUrolithiasisCount': draft.pmUrolithiasisCount,
      'pmUrolithiasisSeverity': draft.pmUrolithiasisSeverity,
      'pmNephritisCount': draft.pmNephritisCount,
      'pmNephritisSeverity': draft.pmNephritisSeverity,
      'pmGeneralSepticemiaCount': draft.pmGeneralSepticemiaCount,
      'pmGeneralSepticemiaSeverity': draft.pmGeneralSepticemiaSeverity,
      'pmOtherLesionsJson': draft.pmOtherLesionsJson,
      'pmSuspectedCauseAuto': draft.pmSuspectedCauseAuto,
      'pmSuspectedCauseManual': draft.pmSuspectedCauseManual,
      'pmPhotosJson': draft.pmPhotosJson,
    };
  }

  bool _isEggBreakoutPanelTable(String tableName) {
    return tableName == 'fresh_egg_breakout' ||
        tableName == 'candled_egg_breakout' ||
        tableName == 'residue_breakout';
  }

  EggBreakoutType _breakoutTypeForTable(String tableName) {
    return switch (tableName) {
      'fresh_egg_breakout' => EggBreakoutType.freshEggBreakout,
      'candled_egg_breakout' => EggBreakoutType.candledEggBreakout,
      'residue_breakout' => EggBreakoutType.residueHatchDay,
      _ => EggBreakoutType.fromStorageValue(null),
    };
  }

  List<EggBreakoutSampleEntry> _breakoutTrayEntriesForTable(
    String tableName,
    AuditModel draft,
  ) {
    return _breakoutEntriesForTable(
      tableName,
      draft,
    ).where((entry) => entry.sampleMode == EggBreakoutSampleMode.tray).toList();
  }

  List<EggBreakoutSampleEntry> _breakoutPoolEntriesForTable(
    String tableName,
    AuditModel draft,
  ) {
    return _breakoutEntriesForTable(
      tableName,
      draft,
    ).where((entry) => entry.sampleMode == EggBreakoutSampleMode.pool).toList();
  }

  List<EggBreakoutSampleEntry> _breakoutLeafEntriesForTable(
    String tableName,
    AuditModel draft,
  ) {
    final trayEntries = _breakoutTrayEntriesForTable(tableName, draft);
    if (trayEntries.isNotEmpty) return trayEntries;
    return _breakoutPoolEntriesForTable(tableName, draft);
  }

  List<EggBreakoutSampleEntry> _breakoutEntriesForTable(
    String tableName,
    AuditModel draft,
  ) {
    final type = _breakoutTypeForTable(tableName);
    return EggBreakoutSampleEntry.decodeList(
      draft.ebTrayBreakoutJson,
      fallbackBreakoutType: EggBreakoutType.fromStorageValue(
        draft.ebBreakoutType,
      ),
    ).where((entry) => entry.breakoutType == type).toList();
  }

  Future<Map<String, Object?>?> _breakoutBenchmarkForDraft(
    AuditModel draft,
    EggBreakoutType breakoutType,
  ) async {
    final ageDays = breakoutType.calculateBmkAgeDays(
      currentFlockAgeDays: BmkAgeCalculator.currentFlockAgeDays(
        flockAgeWeeks: _context?.flockAgeWeeks,
        flockEntryDate: _context?.flockEntryDate,
        auditDate: draft.date,
      ),
      storageDays: draft.ebStorageDays ?? draft.haStorageDays ?? 0,
      candlingDay: draft.ebBreakoutAgeDays ?? 10,
    );
    if (ageDays == null) return null;
    try {
      return await _benchmarkLookup.nearestBreakoutBenchmark(
        calculatedBmkAgeDays: ageDays,
      );
    } catch (error) {
      safeDebugLog('Error loading breakout benchmark for save', error: error);
      return null;
    }
  }

  Map<String, Object?> _breakoutBmkContextValues(
    AuditModel draft,
    EggBreakoutType breakoutType,
  ) {
    final storageDays = draft.ebStorageDays ?? draft.haStorageDays ?? 0;
    final bmkAgeDays = breakoutType.calculateBmkAgeDays(
      currentFlockAgeDays: BmkAgeCalculator.currentFlockAgeDays(
        flockAgeWeeks: _context?.flockAgeWeeks,
        flockEntryDate: _context?.flockEntryDate,
        auditDate: draft.date,
      ),
      storageDays: storageDays,
      candlingDay: draft.ebBreakoutAgeDays ?? 10,
    );
    return {
      'storagePeriodDays': storageDays,
      'bmkAgeWeeks':
          BmkAgeCalculator.displayWeekForDays(bmkAgeDays) ??
          draft.ebBmkAge ??
          draft.haBmkAge,
    };
  }

  String _breakoutTrayLabel(EggBreakoutSampleEntry entry, int index) {
    final label = entry.label.trim();
    return label.isEmpty ? 'Tray ${index + 1}' : label;
  }

  String _breakoutEntryRowId(
    String baseRowId,
    int index,
    EggBreakoutSampleEntry entry,
    SamplingLayer scopeType,
  ) {
    if (index == 0) return baseRowId;
    final entryId = _blankToNull(entry.id) ?? 'tray-${index + 1}';
    return '$baseRowId:${scopeType.dbValue}:${index + 1}:$entryId';
  }

  SamplingLayer _breakoutScopeTypeForEntry({
    required String tableName,
    required EggBreakoutSampleEntry entry,
    required EggBreakoutType breakoutType,
  }) {
    final allowed = PanelSampleSchema.byTable(tableName).allowedLayers;
    final isFresh = breakoutType == EggBreakoutType.freshEggBreakout;
    if (entry.sampleMode == EggBreakoutSampleMode.tray &&
        allowed.contains(SamplingLayer.tray)) {
      return SamplingLayer.tray;
    }
    if (!isFresh &&
        _blankToNull(entry.trolley) != null &&
        allowed.contains(SamplingLayer.trolley)) {
      return SamplingLayer.trolley;
    }
    if (!isFresh &&
        _blankToNull(entry.setter) != null &&
        _blankToNull(entry.hatcher) != null &&
        allowed.contains(SamplingLayer.setterHatcher)) {
      return SamplingLayer.setterHatcher;
    }
    if (!isFresh &&
        _blankToNull(entry.setter) != null &&
        allowed.contains(SamplingLayer.setter)) {
      return SamplingLayer.setter;
    }
    if (!isFresh &&
        _blankToNull(entry.hatcher) != null &&
        allowed.contains(SamplingLayer.hatcher)) {
      return SamplingLayer.hatcher;
    }
    if (_blankToNull(entry.house) != null &&
        allowed.contains(SamplingLayer.house)) {
      return SamplingLayer.house;
    }
    return SamplingLayer.pool;
  }

  String _breakoutScopeLabelForEntry(
    SamplingLayer scopeType,
    EggBreakoutSampleEntry entry,
    String fallbackLabel,
  ) {
    return switch (scopeType) {
      SamplingLayer.house => _blankToNull(entry.house) ?? fallbackLabel,
      SamplingLayer.setterHatcher =>
        '${_blankToNull(entry.setter) ?? ''}/${_blankToNull(entry.hatcher) ?? ''}',
      SamplingLayer.setter => _blankToNull(entry.setter) ?? fallbackLabel,
      SamplingLayer.hatcher => _blankToNull(entry.hatcher) ?? fallbackLabel,
      SamplingLayer.trolley => _blankToNull(entry.trolley) ?? fallbackLabel,
      SamplingLayer.tray => _blankToNull(entry.tray) ?? fallbackLabel,
      SamplingLayer.batch => fallbackLabel,
      SamplingLayer.pool => 'Random',
    };
  }

  String? _breakoutGroupLabelForScope(SamplingLayer scopeType) {
    return switch (scopeType) {
      SamplingLayer.house => 'House comparison',
      SamplingLayer.setter ||
      SamplingLayer.hatcher ||
      SamplingLayer.setterHatcher => 'Machine comparison',
      SamplingLayer.trolley => 'Trolley comparison',
      SamplingLayer.tray => 'Tray comparison',
      SamplingLayer.batch => 'Batch comparison',
      SamplingLayer.pool => null,
    };
  }

  bool _scopeBeforeTrolley(SamplingLayer scopeType) {
    return scopeType == SamplingLayer.pool ||
        scopeType == SamplingLayer.house ||
        scopeType == SamplingLayer.setter ||
        scopeType == SamplingLayer.hatcher ||
        scopeType == SamplingLayer.setterHatcher ||
        scopeType == SamplingLayer.batch;
  }

  Map<String, Object?> _breakoutValuesForEntry(
    String tableName,
    AuditModel draft,
    EggBreakoutSampleEntry entry,
    Map<String, Object?>? benchmark,
  ) {
    return switch (tableName) {
      'fresh_egg_breakout' => _freshBreakoutValuesForEntry(
        draft,
        entry,
        benchmark,
      ),
      'candled_egg_breakout' => _candledBreakoutValuesForEntry(
        draft,
        entry,
        benchmark,
      ),
      'residue_breakout' => _residueBreakoutValuesForEntry(
        draft,
        entry,
        benchmark,
      ),
      _ => const <String, Object?>{},
    };
  }

  Map<String, Object?> _freshBreakoutValuesForEntry(
    AuditModel draft,
    EggBreakoutSampleEntry entry,
    Map<String, Object?>? benchmark, {
    EggBreakoutType breakoutType = EggBreakoutType.freshEggBreakout,
  }) {
    final total = entry.totalSample;
    final infertilePct = _pct(entry.counts['infertile'], total);
    final early24hPct = _pct(entry.counts['early24h'], total);
    final early48hPct = _pct(entry.counts['early48h'], total);
    final bloodRingPct = _pct(entry.counts['early72hBloodRing'], total);
    return {
      ..._breakoutBmkContextValues(draft, breakoutType),
      'traySize': total ?? entry.traySize,
      'infertileCount': entry.counts['infertile'],
      'early24hCount': entry.counts['early24h'],
      'early48hCount': entry.counts['early48h'],
      'bloodRingCount': entry.counts['early72hBloodRing'],
      'infertilePct': infertilePct,
      'early24hPct': early24hPct,
      'early48hPct': early48hPct,
      'bloodRingPct': bloodRingPct,
      'infertileDiffPct': _breakoutDiffPct(
        benchmark,
        'infertile',
        infertilePct,
      ),
      'early24hDiffPct': _breakoutDiffPct(benchmark, 'early24h', early24hPct),
      'early48hDiffPct': _breakoutDiffPct(benchmark, 'early48h', early48hPct),
      'bloodRingDiffPct': _breakoutDiffPct(
        benchmark,
        'early72hBloodRing',
        bloodRingPct,
      ),
    };
  }

  Map<String, Object?> _candledBreakoutValuesForEntry(
    AuditModel draft,
    EggBreakoutSampleEntry entry,
    Map<String, Object?>? benchmark,
  ) {
    final blackEyePct = _pct(entry.counts['blackEye'], entry.totalSample);
    return {
      ..._freshBreakoutValuesForEntry(
        draft,
        entry,
        benchmark,
        breakoutType: EggBreakoutType.candledEggBreakout,
      ),
      'candlingDay': draft.ebBreakoutAgeDays,
      'position': _blankToNull(entry.position),
      'blackEyeCount': entry.counts['blackEye'],
      'blackEyePct': blackEyePct,
      'blackEyeDiffPct': _breakoutDiffPct(benchmark, 'blackEye', blackEyePct),
    };
  }

  Map<String, Object?> _residueBreakoutValuesForEntry(
    AuditModel draft,
    EggBreakoutSampleEntry entry,
    Map<String, Object?>? benchmark,
  ) {
    final total = entry.totalSample;
    final infertilePct = _pct(entry.counts['infertile'], total);
    final earlyDeadPct = _pct(entry.counts['earlyDead'], total);
    final midDeadPct = _pct(entry.counts['midDead'], total);
    final lateDeadPct = _pct(entry.counts['lateDead'], total);
    final externalPipPct = _pct(entry.counts['externalPip'], total);
    final crackedPct = _pct(entry.counts['cracked'], total);
    final contaminatedPct = _pct(entry.counts['contaminated'], total);
    return {
      ..._breakoutBmkContextValues(draft, EggBreakoutType.residueHatchDay),
      'position': _blankToNull(entry.position),
      'traySize': total ?? entry.traySize,
      'infertileCount': entry.counts['infertile'],
      'earlyDeadCount': entry.counts['earlyDead'],
      'midDeadCount': entry.counts['midDead'],
      'lateDeadCount': entry.counts['lateDead'],
      'externalPipCount': entry.counts['externalPip'],
      'crackedCount': entry.counts['cracked'],
      'contaminatedCount': entry.counts['contaminated'],
      'infertilePct': infertilePct,
      'earlyDeadPct': earlyDeadPct,
      'midDeadPct': midDeadPct,
      'lateDeadPct': lateDeadPct,
      'externalPipPct': externalPipPct,
      'crackedPct': crackedPct,
      'contaminatedPct': contaminatedPct,
      'infertileDiffPct': _breakoutDiffPct(
        benchmark,
        'infertile',
        infertilePct,
      ),
      'earlyDeadDiffPct': _breakoutDiffPct(
        benchmark,
        'earlyDead',
        earlyDeadPct,
      ),
      'midDeadDiffPct': _breakoutDiffPct(benchmark, 'midDead', midDeadPct),
      'lateDeadDiffPct': _breakoutDiffPct(benchmark, 'lateDead', lateDeadPct),
      'externalPipDiffPct': _breakoutDiffPct(
        benchmark,
        'externalPip',
        externalPipPct,
      ),
      'crackedDiffPct': _breakoutDiffPct(benchmark, 'cracked', crackedPct),
      'contaminatedDiffPct': _breakoutDiffPct(
        benchmark,
        'contaminated',
        contaminatedPct,
      ),
      'totalEggsSet': draft.haTotalEggsSet,
      'hatchedCount': draft.haHatched,
      'culledCount': draft.haCulled,
      'deadCount': draft.haDead,
      'hatchabilityPct': draft.haHatchability,
      'fertilityPct': draft.haFertility,
      'hofPct': draft.haHof,
      'culledPct': _pct(draft.haCulled, draft.haTotalEggsSet),
      'deadPct': _pct(draft.haDead, draft.haTotalEggsSet),
    };
  }

  double? _breakoutDiffPct(
    Map<String, Object?>? benchmark,
    String countKey,
    double? currentPct,
  ) {
    if (benchmark == null || currentPct == null) return null;
    final column = _breakoutBmkColumnForCountKey(countKey);
    if (column == null) return null;
    final bmkPct = _asDouble(benchmark[column]);
    if (bmkPct == null) return null;
    return currentPct - bmkPct;
  }

  String? _breakoutBmkColumnForCountKey(String countKey) {
    return switch (countKey) {
      'early72hBloodRing' => 'bloodRingPct',
      'externalPip' => 'externalPipPct',
      'contaminated' => 'contamPct',
      'infertile' ||
      'early24h' ||
      'early48h' ||
      'blackEye' ||
      'earlyDead' ||
      'midDead' ||
      'lateDead' ||
      'cracked' => '${countKey}Pct',
      _ => null,
    };
  }

  Map<String, Object?> _freshBreakoutValues(
    AuditModel draft, {
    EggBreakoutType breakoutType = EggBreakoutType.freshEggBreakout,
  }) {
    final rollup = _breakoutRollup(draft, breakoutType: breakoutType);
    return {
      ..._breakoutBmkContextValues(draft, breakoutType),
      'traySize': rollup.totalSample ?? draft.ebTraySize,
      'infertileCount': rollup.counts['infertile'] ?? draft.ebInfertileCount,
      'early24hCount': rollup.counts['early24h'],
      'early48hCount': rollup.counts['early48h'],
      'bloodRingCount': rollup.counts['early72hBloodRing'],
      'infertilePct': _pct(rollup.counts['infertile'], rollup.totalSample),
      'early24hPct': _pct(rollup.counts['early24h'], rollup.totalSample),
      'early48hPct': _pct(rollup.counts['early48h'], rollup.totalSample),
      'bloodRingPct': _pct(
        rollup.counts['early72hBloodRing'],
        rollup.totalSample,
      ),
    };
  }

  Map<String, Object?> _candledBreakoutValues(AuditModel draft) {
    final values = _freshBreakoutValues(
      draft,
      breakoutType: EggBreakoutType.candledEggBreakout,
    );
    final rollup = _breakoutRollup(
      draft,
      breakoutType: EggBreakoutType.candledEggBreakout,
    );
    return {
      ...values,
      'candlingDay': draft.ebBreakoutAgeDays,
      'position': _firstBreakoutPosition(
        draft,
        breakoutType: EggBreakoutType.candledEggBreakout,
      ),
      'blackEyeCount': rollup.counts['blackEye'],
      'blackEyePct': _pct(rollup.counts['blackEye'], rollup.totalSample),
    };
  }

  Map<String, Object?> _residueBreakoutValues(AuditModel draft) {
    final rollup = _breakoutRollup(
      draft,
      breakoutType: EggBreakoutType.residueHatchDay,
    );
    return {
      ..._breakoutBmkContextValues(draft, EggBreakoutType.residueHatchDay),
      'position': _firstBreakoutPosition(
        draft,
        breakoutType: EggBreakoutType.residueHatchDay,
      ),
      'traySize': rollup.totalSample ?? draft.ebTraySize,
      'infertileCount': rollup.counts['infertile'] ?? draft.ebInfertileCount,
      'earlyDeadCount': rollup.counts['earlyDead'] ?? draft.ebEarlyDeadCount,
      'midDeadCount': rollup.counts['midDead'] ?? draft.ebMidDeadCount,
      'lateDeadCount': rollup.counts['lateDead'] ?? draft.ebLateDeadCount,
      'externalPipCount':
          rollup.counts['externalPip'] ?? draft.ebExternalPipCount,
      'crackedCount': rollup.counts['cracked'] ?? draft.ebCrackedCount,
      'contaminatedCount':
          rollup.counts['contaminated'] ?? draft.ebContaminatedCount,
      'infertilePct': _pct(rollup.counts['infertile'], rollup.totalSample),
      'earlyDeadPct': _pct(rollup.counts['earlyDead'], rollup.totalSample),
      'midDeadPct': _pct(rollup.counts['midDead'], rollup.totalSample),
      'lateDeadPct': _pct(rollup.counts['lateDead'], rollup.totalSample),
      'externalPipPct': _pct(rollup.counts['externalPip'], rollup.totalSample),
      'crackedPct': _pct(rollup.counts['cracked'], rollup.totalSample),
      'contaminatedPct': _pct(
        rollup.counts['contaminated'],
        rollup.totalSample,
      ),
      'totalEggsSet': draft.haTotalEggsSet,
      'hatchedCount': draft.haHatched,
      'culledCount': draft.haCulled,
      'deadCount': draft.haDead,
      'hatchabilityPct': draft.haHatchability,
      'fertilityPct': draft.haFertility,
      'hofPct': draft.haHof,
      'culledPct': _pct(draft.haCulled, draft.haTotalEggsSet),
      'deadPct': _pct(draft.haDead, draft.haTotalEggsSet),
    };
  }

  ({Map<String, int> counts, int? totalSample}) _breakoutRollup(
    AuditModel draft, {
    EggBreakoutType? breakoutType,
  }) {
    final allEntries = EggBreakoutSampleEntry.decodeList(
      draft.ebTrayBreakoutJson,
      fallbackBreakoutType: EggBreakoutType.fromStorageValue(
        draft.ebBreakoutType,
      ),
    );
    final entries = breakoutType == null
        ? allEntries
        : allEntries
              .where((entry) => entry.breakoutType == breakoutType)
              .toList();
    final counts = <String, int>{};
    var total = 0;
    for (final entry in entries) {
      total += entry.totalSample ?? 0;
      for (final item in entry.counts.entries) {
        counts[item.key] = (counts[item.key] ?? 0) + item.value;
      }
    }
    if (counts.isEmpty && allEntries.isEmpty) {
      counts.addAll({
        if (draft.ebInfertileCount != null)
          'infertile': draft.ebInfertileCount!,
        if (draft.ebEarlyDeadCount != null)
          'earlyDead': draft.ebEarlyDeadCount!,
        if (draft.ebMidDeadCount != null) 'midDead': draft.ebMidDeadCount!,
        if (draft.ebLateDeadCount != null) 'lateDead': draft.ebLateDeadCount!,
        if (draft.ebExternalPipCount != null)
          'externalPip': draft.ebExternalPipCount!,
        if (draft.ebCrackedCount != null) 'cracked': draft.ebCrackedCount!,
        if (draft.ebContaminatedCount != null)
          'contaminated': draft.ebContaminatedCount!,
      });
    }
    return (
      counts: counts,
      totalSample: total == 0
          ? (allEntries.isEmpty ? draft.ebTraySize : null)
          : total,
    );
  }

  String? _firstBreakoutPosition(
    AuditModel draft, {
    EggBreakoutType? breakoutType,
  }) {
    final allEntries = EggBreakoutSampleEntry.decodeList(
      draft.ebTrayBreakoutJson,
      fallbackBreakoutType: EggBreakoutType.fromStorageValue(
        draft.ebBreakoutType,
      ),
    );
    final entries = breakoutType == null
        ? allEntries
        : allEntries.where((entry) => entry.breakoutType == breakoutType);
    for (final entry in entries) {
      final position = entry.position?.trim();
      if (position != null && position.isNotEmpty) return position;
    }
    return null;
  }

  List<Map<String, dynamic>> _decodedMaps(String? source) {
    if (source == null || source.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  int _decodedListLength(String? source) => _decodedMaps(source).length;

  int? _decodedReadingCount(String? source) {
    if (source == null || source.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is List) return decoded.length;
      if (decoded is Map) return decoded.length;
    } catch (_) {
      return null;
    }
    return null;
  }

  int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString());
  }

  double? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Map<String, Object?>? _decodedMap(String? source) {
    if (source == null || source.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return null;
      return Map<String, Object?>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  int? _weightSampleSizeFromWeightsJson(String weightsJson) {
    final decoded = _decodedWeights(weightsJson);
    return _weightSampleSizeFromDecoded(decoded);
  }

  int? _weightSampleSizeFromDecoded(Object? decoded) {
    if (decoded is! List) return null;
    final count = decoded
        .map(_asDouble)
        .where((weight) => weight != null && weight > 0)
        .length;
    return count == 0 ? null : count;
  }

  double? _pct(Object? count, Object? total) {
    final numerator = _asInt(count);
    final denominator = _asInt(total);
    if (numerator == null || denominator == null || denominator <= 0) {
      return null;
    }
    return numerator * 100 / denominator;
  }

  int? _boolToInt(bool? value) {
    if (value == null) return null;
    return value ? 1 : 0;
  }

  PanelSampleRecord _panelSampleRecordForStationSample({
    required String tableName,
    required String panelId,
    required AuditModel draft,
    required StationSampleModel sample,
  }) {
    final scopeType = _scopeTypeForPanel(tableName, sample, draft);
    final isHatchBreakout = draft.auditType == 'Hatch Analysis & Egg Breakouts';
    final sampleHouseNo = isHatchBreakout
        ? _blankToNull(draft.houseId)
        : _blankToNull(sample.houseNo);
    final sampleHouseLabel = isHatchBreakout
        ? _blankToNull(draft.houseId)
        : _blankToNull(sample.houseLabel);
    final sampleSetterNo = isHatchBreakout
        ? _blankToNull(draft.setterId)
        : _blankToNull(sample.setterNo);
    final sampleHatcherNo = isHatchBreakout
        ? _blankToNull(draft.hatcherId)
        : _blankToNull(sample.hatcherNo);
    final usesHouse =
        _scopeIncludesHouse(scopeType) &&
        (sampleHouseNo != null || sampleHouseLabel != null);
    final usesSetter =
        tableName == 'setter_optimizing' ||
        scopeType == SamplingLayer.setter ||
        scopeType == SamplingLayer.setterHatcher;
    final usesHatcher =
        tableName == 'hatcher_optimizing' ||
        scopeType == SamplingLayer.hatcher ||
        scopeType == SamplingLayer.setterHatcher;
    return PanelSampleRecord(
      id: '$panelId:${sample.id}',
      panelId: panelId,
      scopeType: scopeType,
      scopeLabel: _scopeLabelForSample(scopeType, sample),
      sampleIndex: sample.sampleIndex,
      houseId: usesHouse ? sampleHouseNo : null,
      houseName: usesHouse ? sampleHouseLabel : null,
      setterId: usesSetter ? sampleSetterNo : null,
      hatcherId: usesHatcher ? sampleHatcherNo : null,
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
    StationSampleModel sample, [
    AuditModel? draft,
  ]) {
    final allowed = PanelSampleSchema.byTable(tableName).allowedLayers;
    final isHatchBreakout =
        draft?.auditType == 'Hatch Analysis & Egg Breakouts';
    final sampleSetterNo = isHatchBreakout
        ? _blankToNull(draft?.setterId)
        : _blankToNull(sample.setterNo);
    final sampleHatcherNo = isHatchBreakout
        ? _blankToNull(draft?.hatcherId)
        : _blankToNull(sample.hatcherNo);
    final isComparison =
        sample.sampleMode == StationSampleModel.sampleModeComparison ||
        (draft != null && SampleMode.isCompare(draft.sampleMode));
    if (!isComparison) {
      return SamplingLayer.pool;
    }
    if (sample.sampleKind == StationSampleModel.sampleKindMachine &&
        allowed.contains(SamplingLayer.setterHatcher) &&
        sampleSetterNo != null &&
        sampleHatcherNo != null) {
      return SamplingLayer.setterHatcher;
    }
    if (allowed.contains(SamplingLayer.setterHatcher) &&
        sampleSetterNo != null &&
        sampleHatcherNo != null) {
      return SamplingLayer.setterHatcher;
    }
    if (allowed.contains(SamplingLayer.setter) && sampleSetterNo != null) {
      return SamplingLayer.setter;
    }
    if (allowed.contains(SamplingLayer.hatcher) && sampleHatcherNo != null) {
      return SamplingLayer.hatcher;
    }
    if (allowed.contains(SamplingLayer.house)) {
      return SamplingLayer.house;
    }
    return SamplingLayer.pool;
  }

  bool _scopeIncludesHouse(SamplingLayer scopeType) {
    return scopeType == SamplingLayer.house ||
        scopeType == SamplingLayer.setter ||
        scopeType == SamplingLayer.hatcher ||
        scopeType == SamplingLayer.setterHatcher ||
        scopeType == SamplingLayer.trolley ||
        scopeType == SamplingLayer.tray;
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
      SamplingLayer.batch => sample.groupLabel ?? sample.sampleLabel,
      SamplingLayer.pool => 'Random',
    };
  }

  int? _sampleSizeForPanel(String tableName, AuditModel draft) {
    return switch (tableName) {
      'egg_quality' => draft.esEggSampleSize,
      'chick_quality' =>
        draft.pasgarSampleSize ??
            draft.cvtSampleSize ??
            draft.pmSampleSize ??
            draft.culledChicksTotalEggSet,
      'chick_weights' => draft.chickSampleSize,
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

class _BreakoutHierarchyPath {
  const _BreakoutHierarchyPath({
    required this.pairIndex,
    required this.sessionId,
    required this.tableName,
    required this.scopeType,
    this.house,
    this.setter,
    this.hatcher,
    this.trolley,
    this.tray,
    this.position,
  });

  final int pairIndex;
  final String sessionId;
  final String tableName;
  final SamplingLayer scopeType;
  final String? house;
  final String? setter;
  final String? hatcher;
  final String? trolley;
  final String? tray;
  final String? position;

  bool get canHaveChildren => _samplingLayerDepth(scopeType) < 4;

  bool isParentOf(_BreakoutHierarchyPath child) {
    if (sessionId != child.sessionId || tableName != child.tableName) {
      return false;
    }
    if (_samplingLayerDepth(child.scopeType) <=
        _samplingLayerDepth(scopeType)) {
      return false;
    }
    return switch (scopeType) {
      SamplingLayer.pool => true,
      SamplingLayer.house => _matches(house, child.house),
      SamplingLayer.setter =>
        _matches(house, child.house) && _matches(setter, child.setter),
      SamplingLayer.hatcher =>
        _matches(house, child.house) && _matches(hatcher, child.hatcher),
      SamplingLayer.setterHatcher =>
        _matches(house, child.house) &&
            _matches(setter, child.setter) &&
            _matches(hatcher, child.hatcher),
      SamplingLayer.trolley =>
        _matches(house, child.house) &&
            _matches(setter, child.setter) &&
            _matches(hatcher, child.hatcher) &&
            _matches(trolley, child.trolley),
      SamplingLayer.tray || SamplingLayer.batch => false,
    };
  }

  static bool _matches(String? parentValue, String? childValue) {
    return parentValue == null || parentValue == childValue;
  }
}

int _samplingLayerDepth(SamplingLayer scopeType) {
  return switch (scopeType) {
    SamplingLayer.pool => 0,
    SamplingLayer.house => 1,
    SamplingLayer.setter ||
    SamplingLayer.hatcher ||
    SamplingLayer.setterHatcher => 2,
    SamplingLayer.trolley => 3,
    SamplingLayer.tray => 4,
    SamplingLayer.batch => 1,
  };
}
