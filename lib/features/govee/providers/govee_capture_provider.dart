import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/govee_capture_model.dart';
import '../../../data/models/temperature_rh_model.dart';
import '../../../data/repositories/govee_capture_repository.dart';
import '../../../core/utils/calculation_utils.dart';
import '../../../services/govee/govee_service.dart';
import '../../dashboard/models/govee_capture_summary.dart';
import '../../temperature/services/lttb_downsampler.dart';
import '../utils/govee_place_flow.dart';

enum GoveeCapturePhase {
  idle,
  validRecording,
  syncing,
  syncFailed,
  saving,
  saveFailed,
  saved,
}

enum GoveeCaptureTarget { room, insideMachine }

class GoveeCaptureProvider extends ChangeNotifier {
  static const Duration warmupDuration = Duration(seconds: 60);
  static const int maxLivePreviewReadings = 500;

  final GoveeCaptureRepository _repository;
  final GoveeService _goveeService;
  final DateTime Function() _clock;
  final Uuid _uuid = const Uuid();

  String? _customerId;
  String? _hatcheryId;
  TemperaturePlace? _place;
  String? _captureDate;
  String? _stationKey;
  String? _machineId;
  GoveeCaptureTarget _captureTarget = GoveeCaptureTarget.room;
  GoveeDailyCaptureModel? _existingCapture;
  GoveeDailyCaptureModel? _finishedCapture;
  List<GoveePlaceReadingModel> _finishedReadings = const [];
  List<GoveeCaptureSummary> _savedSummaries = const [];
  String? _selectedSavedCaptureId;
  GoveeCapturePhase _phase = GoveeCapturePhase.idle;
  DateTime? _recordingStartedAt;
  DateTime? _failedRecordingStartedAt;
  DateTime? _failedRecordingEndedAt;
  DateTime? _pendingSaveStartedAt;
  DateTime? _pendingSaveEndedAt;
  List<GoveeSensorReading> _pendingSaveReadings = const [];
  String? _error;
  String? _syncFailureDetails;
  List<String> _syncFailureDiagnostics = const [];
  TemperaturePlace? _suggestedNextPlace;
  bool _goveeListenersAttached = false;
  StreamSubscription<GoveeSensorReading>? _liveSubscription;
  final List<GoveeSensorReading> _liveRecordingReadings = [];

  GoveeCaptureProvider({
    GoveeCaptureRepository? repository,
    GoveeService? goveeService,
    DateTime Function()? clock,
    bool enablePhaseTimer = true,
  }) : _repository = repository ?? GoveeCaptureRepository(),
       _goveeService = goveeService ?? GoveeService(),
       _clock = clock ?? DateTime.now;

  String? get customerId => _customerId;
  String? get hatcheryId => _hatcheryId;
  TemperaturePlace? get place => _place;
  String? get captureDate => _captureDate;
  String? get stationKey => _stationKey;
  String? get machineId =>
      _captureTarget == GoveeCaptureTarget.insideMachine ? _machineId : null;
  String? get availableMachineId => _machineId;
  GoveeCaptureTarget get captureTarget => _captureTarget;
  bool get supportsMachineChoice =>
      _stationKey == 'setters' || _stationKey == 'hatchers';
  TemperaturePlace? get roomPlace => _roomPlaceForStation(_stationKey);
  TemperaturePlace? get insideMachinePlace =>
      _insideMachinePlaceForStation(_stationKey);
  String? get machineDisplayLabel {
    final id = _machineId?.trim();
    if (_stationKey == 'setters') {
      return id == null || id.isEmpty ? 'Inside setter' : 'Inside $id';
    }
    if (_stationKey == 'hatchers') {
      return id == null || id.isEmpty ? 'Inside hatcher' : 'Inside $id';
    }
    return id == null || id.isEmpty ? null : id;
  }

  GoveeDailyCaptureModel? get existingCapture => _existingCapture;
  GoveeDailyCaptureModel? get finishedCapture => _finishedCapture;
  List<GoveePlaceReadingModel> get finishedReadings =>
      List.unmodifiable(_finishedReadings);
  List<GoveeCaptureSummary> get savedSummaries =>
      List.unmodifiable(_savedSummaries);
  GoveeCaptureSummary? get selectedSavedSummary {
    final selectedId = _selectedSavedCaptureId;
    if (selectedId != null) {
      for (final summary in _savedSummaries) {
        if (summary.capture.id == selectedId) return summary;
      }
    }
    return _savedSummaries.isEmpty ? null : _savedSummaries.first;
  }

  bool get hasExistingCapture => _existingCapture != null;
  String? get error => _error;
  String? get syncFailureDetails => _syncFailureDetails;
  List<String> get syncFailureDiagnostics =>
      List.unmodifiable(_syncFailureDiagnostics);
  TemperaturePlace? get suggestedNextPlace => _suggestedNextPlace;
  GoveeCapturePhase get phase => _phase;
  bool get isRecording => _phase == GoveeCapturePhase.validRecording;
  bool get canStartRecording =>
      _customerId != null &&
      _hatcheryId != null &&
      _place != null &&
      _captureDate != null &&
      (_phase == GoveeCapturePhase.idle || _phase == GoveeCapturePhase.saved);
  bool get canStopRecording =>
      isRecording ||
      _phase == GoveeCapturePhase.syncFailed ||
      _phase == GoveeCapturePhase.saveFailed;
  bool get isBleAvailable => _goveeService.isAvailable;
  bool get isSensorConnected => _goveeService.isConnected;
  bool get isGattConnected => _goveeService.isGattConnected;
  bool get isGattConnecting => _goveeService.isGattConnecting;
  bool get isScanning => _goveeService.isScanning;
  String? get deviceName => _goveeService.deviceName;
  int? get signalStrength => _goveeService.signalStrength;
  DateTime? get liveUpdatedAt =>
      _goveeService.latestReading?.timestamp ?? _goveeService.lastSeenAt;
  double? get liveTemperatureFahrenheit =>
      _goveeService.latestReading?.temperatureFahrenheit;
  double? get liveHumidity => _goveeService.latestReading?.humidity;
  int? get batteryPercent => _goveeService.latestReading?.batteryPercent;
  List<String> get bleDiagnostics => _goveeService.diagnostics;
  List<GoveeSensorReading> get liveRecordingReadings =>
      List.unmodifiable(_liveRecordingReadings);

  Future<void> configure({
    required String customerId,
    required String hatcheryId,
    required TemperaturePlace place,
    String? captureDate,
    String? stationKey,
    String? machineId,
    GoveeCaptureTarget captureTarget = GoveeCaptureTarget.room,
  }) async {
    _customerId = customerId;
    _hatcheryId = hatcheryId;
    final resolvedStationKey = stationKey?.trim().isNotEmpty == true
        ? stationKey!.trim()
        : goveeStationKeyForTemperaturePlace(place);
    _stationKey = resolvedStationKey;
    _machineId = machineId?.trim().isEmpty ?? true ? null : machineId!.trim();
    _captureTarget = captureTarget;
    _place = _resolvedPlaceForTarget(place, resolvedStationKey, captureTarget);
    _captureDate = captureDate ?? _formatDate(_clock());
    _phase = GoveeCapturePhase.idle;
    _recordingStartedAt = null;
    _failedRecordingStartedAt = null;
    _failedRecordingEndedAt = null;
    _clearPendingSave();
    _error = null;
    _syncFailureDetails = null;
    _syncFailureDiagnostics = const [];
    _liveRecordingReadings.clear();
    _suggestedNextPlace = null;
    try {
      _existingCapture = await _repository.getCaptureForScope(
        customerId: customerId,
        hatcheryId: hatcheryId,
        stationKey: resolvedStationKey,
        place: _place!,
        machineId: this.machineId,
        captureDate: _captureDate!,
      );
      await _loadSavedSummaries(preferredCaptureId: _existingCapture?.id);
    } catch (e) {
      _existingCapture = null;
      _savedSummaries = const [];
      _selectedSavedCaptureId = null;
      _syncSelectedSavedSummary();
      _error = 'Could not load saved Govee captures for this date.';
      if (kDebugMode) {
        debugPrint('Govee capture configure failed: $e');
      }
    }
    notifyListeners();
  }

  Future<void> selectCaptureTarget(GoveeCaptureTarget target) async {
    if (!supportsMachineChoice ||
        _customerId == null ||
        _hatcheryId == null ||
        _captureDate == null) {
      return;
    }
    final place = _resolvedPlaceForTarget(_place, _stationKey, target);
    await configure(
      customerId: _customerId!,
      hatcheryId: _hatcheryId!,
      place: place,
      captureDate: _captureDate,
      stationKey: _stationKey,
      machineId: _machineId,
      captureTarget: target,
    );
  }

  Future<void> ensureBleReady() async {
    _attachGoveeListeners();
    await _goveeService.initializeBle();
    _goveeService.setAutoReconnectEnabled(true);
  }

  Future<void> connectSensor() async {
    _attachGoveeListeners();
    _goveeService.setAutoReconnectEnabled(true);
    try {
      if (_goveeService.isConnected) {
        await _goveeService.connectDevice();
      } else if (_goveeService.isScanning) {
        await _goveeService.restartScan();
      } else {
        await _goveeService.startScan();
      }
    } catch (e) {
      _error = 'Could not scan for the Govee sensor';
      if (kDebugMode) debugPrint('Govee capture scan failed: $e');
      notifyListeners();
    }
  }

  Future<void> requestSensorReading() async {
    await ensureBleReady();
    try {
      await _goveeService.requestLiveReading();
    } catch (e) {
      _error = 'Could not request a live Govee reading';
      if (kDebugMode) debugPrint('Govee capture live read failed: $e');
      notifyListeners();
    }
  }

  Future<void> startRecording() async {
    if (_customerId == null ||
        _hatcheryId == null ||
        _place == null ||
        _captureDate == null) {
      _error = 'Choose a customer, hatchery, date, and place first';
      notifyListeners();
      return;
    }
    if (!canStartRecording) {
      return;
    }

    _attachGoveeListeners();
    _recordingStartedAt = _clock();
    _failedRecordingStartedAt = null;
    _failedRecordingEndedAt = null;
    _clearPendingSave();
    _liveRecordingReadings.clear();
    _phase = GoveeCapturePhase.validRecording;
    _error = null;
    _syncFailureDetails = null;
    _syncFailureDiagnostics = const [];
    notifyListeners();
  }

  Future<void> stopAndSavePlaceCapture() async {
    final isRetryingSync = _phase == GoveeCapturePhase.syncFailed;
    final isRetryingSave = _phase == GoveeCapturePhase.saveFailed;
    final startedAt = isRetryingSync
        ? _failedRecordingStartedAt
        : isRetryingSave
        ? _pendingSaveStartedAt
        : _recordingStartedAt;
    final endedAt = isRetryingSync
        ? _failedRecordingEndedAt
        : isRetryingSave
        ? _pendingSaveEndedAt
        : _clock();

    if (startedAt == null ||
        endedAt == null ||
        _customerId == null ||
        _hatcheryId == null ||
        _place == null ||
        _captureDate == null) {
      _error = 'Start recording before saving this Govee place capture';
      notifyListeners();
      return;
    }

    late final List<GoveeSensorReading> valid;
    if (isRetryingSave && _pendingSaveReadings.isNotEmpty) {
      valid = _pendingSaveReadings;
      _error = null;
      _syncFailureDetails = null;
      _syncFailureDiagnostics = const [];
    } else {
      _phase = GoveeCapturePhase.syncing;
      _error = null;
      _syncFailureDetails = null;
      _syncFailureDiagnostics = const [];
      notifyListeners();

      late final List<GoveeSensorReading> synced;
      try {
        synced = await _goveeService.syncHistory(
          startedAt: startedAt,
          endedAt: endedAt,
        );
      } catch (e) {
        _failedRecordingStartedAt = startedAt;
        _failedRecordingEndedAt = endedAt;
        _phase = GoveeCapturePhase.syncFailed;
        _error = 'Reconnect the Govee sensor, then retry this place recording.';
        _syncFailureDetails = '${e.runtimeType}: $e';
        _syncFailureDiagnostics = _buildSyncFailureDiagnostics(
          startedAt: startedAt,
          endedAt: endedAt,
        );
        if (kDebugMode) debugPrint('Govee capture history sync failed: $e');
        notifyListeners();
        return;
      }

      final validStartedAt = startedAt.add(warmupDuration);
      valid = _filterValidSyncedReadings(synced, validStartedAt, endedAt);
    }

    if (valid.isEmpty) {
      _error = 'No valid synced Govee readings were found after warmup';
      _phase = GoveeCapturePhase.validRecording;
      notifyListeners();
      return;
    }

    _phase = GoveeCapturePhase.saving;
    _pendingSaveStartedAt = startedAt;
    _pendingSaveEndedAt = endedAt;
    _pendingSaveReadings = List.unmodifiable(valid);
    notifyListeners();

    final now = _clock();
    final captureId = _uuid.v4();
    final downsampled = LttbDownsampler.downsample<GoveeSensorReading>(
      valid,
      timestampFor: (reading) => reading.timestamp,
      yFor: (reading) => reading.temperatureFahrenheit! + reading.humidity!,
    );
    final capture = GoveeDailyCaptureModel(
      id: captureId,
      customerId: _customerId!,
      hatcheryId: _hatcheryId!,
      stationKey: _stationKey,
      place: _place!,
      machineId: machineId,
      captureDate: _captureDate!,
      startedAt: startedAt,
      endedAt: endedAt,
      deviceId: _goveeService.deviceId,
      deviceName: _goveeService.deviceName,
      status: 'completed',
      tempAvg: _averageReadingValue(
        valid,
        (reading) => reading.temperatureFahrenheit,
      ),
      tempMin: _minReadingValue(
        valid,
        (reading) => reading.temperatureFahrenheit,
      ),
      tempMax: _maxReadingValue(
        valid,
        (reading) => reading.temperatureFahrenheit,
      ),
      tempSd: _standardDeviationReadingValue(
        valid,
        (reading) => reading.temperatureFahrenheit,
      ),
      tempCvPct: _coefficientOfVariationReadingValue(
        valid,
        (reading) => reading.temperatureFahrenheit,
      ),
      rhAvg: _averageReadingValue(valid, (reading) => reading.humidity),
      rhMin: _minReadingValue(valid, (reading) => reading.humidity),
      rhMax: _maxReadingValue(valid, (reading) => reading.humidity),
      rhSd: _standardDeviationReadingValue(
        valid,
        (reading) => reading.humidity,
      ),
      rhCvPct: _coefficientOfVariationReadingValue(
        valid,
        (reading) => reading.humidity,
      ),
      readingCount: downsampled.length,
      createdAt: now,
      updatedAt: now,
    );
    final readings = downsampled
        .asMap()
        .entries
        .map((entry) {
          final reading = entry.value;
          return GoveePlaceReadingModel(
            id: _uuid.v4(),
            captureId: captureId,
            readingIndex: entry.key,
            recordedAt: reading.timestamp,
            temperatureFahrenheit: reading.temperatureFahrenheit!,
            humidity: reading.humidity!,
            createdAt: now,
          );
        })
        .toList(growable: false);

    final savedCapture = capture.copyWith(
      chartPointsJson: GoveePlaceReadingModel.listToJson(readings),
    );
    try {
      await _repository.saveReplacement(
        capture: savedCapture,
        readings: readings,
      );
      await _loadSavedSummaries(
        preferredCaptureId: savedCapture.id,
        fallbackSummary: GoveeCaptureSummary(
          capture: savedCapture,
          readings: readings,
        ),
      );
    } catch (e) {
      _phase = GoveeCapturePhase.saveFailed;
      _error =
          'Could not save this Govee place capture. Retry save before starting another place.';
      _syncFailureDetails = '${e.runtimeType}: $e';
      _syncFailureDiagnostics = _buildSaveFailureDiagnostics(
        startedAt: startedAt,
        endedAt: endedAt,
        readingCount: readings.length,
      );
      if (kDebugMode) debugPrint('Govee capture save failed: $e');
      notifyListeners();
      return;
    }
    _recordingStartedAt = null;
    _failedRecordingStartedAt = null;
    _failedRecordingEndedAt = null;
    _clearPendingSave();
    _syncFailureDetails = null;
    _syncFailureDiagnostics = const [];
    _phase = GoveeCapturePhase.saved;
    _suggestedNextPlace = nextGoveePlace(_place!);
    _existingCapture = null;
    notifyListeners();
  }

  void clearAfterSaveAndSuggestNextPlace() {
    _liveRecordingReadings.clear();
    _recordingStartedAt = null;
    _failedRecordingStartedAt = null;
    _failedRecordingEndedAt = null;
    _clearPendingSave();
    _syncFailureDetails = null;
    _syncFailureDiagnostics = const [];
    _phase = GoveeCapturePhase.saved;
    _syncSelectedSavedSummary();
    notifyListeners();
  }

  void selectSavedCapture(String captureId) {
    if (_savedSummaries.every((summary) => summary.capture.id != captureId)) {
      return;
    }
    _selectedSavedCaptureId = captureId;
    _syncSelectedSavedSummary();
    notifyListeners();
  }

  void _attachGoveeListeners() {
    if (_goveeListenersAttached) return;
    _goveeListenersAttached = true;
    _goveeService.addListener(_handleGoveeServiceChanged);
    _liveSubscription = _goveeService.readings.listen(_handleLiveReading);
  }

  void _handleGoveeServiceChanged() {
    notifyListeners();
  }

  void _handleLiveReading(GoveeSensorReading reading) {
    if (_phase != GoveeCapturePhase.validRecording) return;
    if (reading.temperatureFahrenheit == null || reading.humidity == null) {
      return;
    }
    final startedAt = _recordingStartedAt;
    if (startedAt != null && reading.timestamp.isBefore(startedAt)) return;
    _liveRecordingReadings.add(reading);
    final overflow = _liveRecordingReadings.length - maxLivePreviewReadings;
    if (overflow > 0) {
      _liveRecordingReadings.removeRange(0, overflow);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_liveSubscription?.cancel());
    if (_goveeListenersAttached) {
      _goveeService.removeListener(_handleGoveeServiceChanged);
    }
    super.dispose();
  }

  List<GoveeSensorReading> _filterValidSyncedReadings(
    List<GoveeSensorReading> readings,
    DateTime startedAt,
    DateTime endedAt,
  ) {
    return readings.where((reading) {
      final temp = reading.temperatureFahrenheit;
      final humidity = reading.humidity;
      if (temp == null || humidity == null) return false;
      if (temp < -40 || temp > 160 || humidity < 0 || humidity > 100) {
        return false;
      }
      if (reading.timestamp.isBefore(startedAt) ||
          reading.timestamp.isAfter(endedAt)) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  List<String> _buildSyncFailureDiagnostics({
    required DateTime startedAt,
    required DateTime endedAt,
  }) {
    final diagnostics = _goveeService.diagnostics;
    final start = math.max(0, diagnostics.length - 8);
    return [
      _syncContextLine(startedAt: startedAt, endedAt: endedAt),
      ...diagnostics.sublist(start),
    ];
  }

  List<String> _buildSaveFailureDiagnostics({
    required DateTime startedAt,
    required DateTime endedAt,
    required int readingCount,
  }) {
    return [
      _syncContextLine(startedAt: startedAt, endedAt: endedAt),
      'Prepared $readingCount representative readings for local save.',
    ];
  }

  void _clearPendingSave() {
    _pendingSaveStartedAt = null;
    _pendingSaveEndedAt = null;
    _pendingSaveReadings = const [];
  }

  String _syncContextLine({
    required DateTime startedAt,
    required DateTime endedAt,
  }) {
    final device = _goveeService.deviceName?.trim().isNotEmpty == true
        ? _goveeService.deviceName!.trim()
        : 'Unknown device';
    final id = _goveeService.deviceId?.trim().isNotEmpty == true
        ? _goveeService.deviceId!.trim()
        : 'no id';
    final rssi = _goveeService.signalStrength == null
        ? 'RSSI unknown'
        : 'RSSI ${_goveeService.signalStrength}';
    final gatt = _goveeService.isGattConnected
        ? 'GATT connected'
        : 'GATT disconnected';
    return 'Device: $device ($id), $gatt, $rssi, window ${startedAt.toIso8601String()} to ${endedAt.toIso8601String()}';
  }

  Future<void> _loadSavedSummaries({
    String? preferredCaptureId,
    GoveeCaptureSummary? fallbackSummary,
  }) async {
    if (_customerId == null || _hatcheryId == null || _captureDate == null) {
      _savedSummaries = const [];
      _selectedSavedCaptureId = null;
      _syncSelectedSavedSummary();
      return;
    }

    final captures = await _repository.getCapturesForDashboard(
      customerId: _customerId!,
      hatcheryId: _hatcheryId!,
      captureDate: _captureDate,
    );
    final summaries = <GoveeCaptureSummary>[];
    for (final capture in captures) {
      summaries.add(
        GoveeCaptureSummary(
          capture: capture,
          readings: await _repository.getReadingsForCapture(capture.id),
        ),
      );
    }

    if (fallbackSummary != null &&
        summaries.every(
          (summary) => summary.capture.id != fallbackSummary.capture.id,
        )) {
      summaries.removeWhere(
        (summary) =>
            _sameSavedCaptureScope(summary.capture, fallbackSummary.capture),
      );
      summaries.add(fallbackSummary);
    }

    _savedSummaries = _dedupeSavedSummaries(summaries)
      ..sort(_compareSavedSummaries);
    _selectedSavedCaptureId = _preferredSavedCaptureId(preferredCaptureId);
    _syncSelectedSavedSummary();
  }

  List<GoveeCaptureSummary> _dedupeSavedSummaries(
    List<GoveeCaptureSummary> summaries,
  ) {
    final byScope = <String, GoveeCaptureSummary>{};
    for (final summary in summaries) {
      final key = _savedCaptureScopeKey(summary.capture);
      final existing = byScope[key];
      if (existing == null ||
          existing.capture.updatedAt.isBefore(summary.capture.updatedAt)) {
        byScope[key] = summary;
      }
    }
    return byScope.values.toList(growable: false);
  }

  int _compareSavedSummaries(GoveeCaptureSummary a, GoveeCaptureSummary b) {
    final flowCompare = _placeFlowIndex(
      a.capture.place,
    ).compareTo(_placeFlowIndex(b.capture.place));
    if (flowCompare != 0) return flowCompare;
    final machineCompare = (a.capture.machineId ?? '').compareTo(
      b.capture.machineId ?? '',
    );
    if (machineCompare != 0) return machineCompare;
    return b.capture.updatedAt.compareTo(a.capture.updatedAt);
  }

  String? _preferredSavedCaptureId(String? preferredCaptureId) {
    if (preferredCaptureId != null &&
        _savedSummaries.any(
          (summary) => summary.capture.id == preferredCaptureId,
        )) {
      return preferredCaptureId;
    }
    final currentScopeCapture = _savedSummaryForCurrentScope();
    if (currentScopeCapture != null) return currentScopeCapture.capture.id;
    return _savedSummaries.isEmpty ? null : _savedSummaries.first.capture.id;
  }

  GoveeCaptureSummary? _savedSummaryForCurrentScope() {
    for (final summary in _savedSummaries) {
      final capture = summary.capture;
      if (capture.place == _place &&
          _normalizedMachineId(capture.machineId) ==
              _normalizedMachineId(machineId) &&
          capture.captureDate == _captureDate) {
        return summary;
      }
    }
    return null;
  }

  void _syncSelectedSavedSummary() {
    final summary = selectedSavedSummary;
    _finishedCapture = summary?.capture;
    _finishedReadings = summary?.readings ?? const [];
  }

  bool _sameSavedCaptureScope(
    GoveeDailyCaptureModel a,
    GoveeDailyCaptureModel b,
  ) {
    return _savedCaptureScopeKey(a) == _savedCaptureScopeKey(b);
  }

  String _savedCaptureScopeKey(GoveeDailyCaptureModel capture) {
    return [
      capture.customerId,
      capture.hatcheryId,
      capture.captureDate,
      capture.place.name,
      _normalizedMachineId(capture.machineId),
    ].join('|');
  }

  int _placeFlowIndex(TemperaturePlace place) {
    final index = goveePlaceFlow.indexOf(place);
    return index < 0 ? goveePlaceFlow.length : index;
  }

  String _normalizedMachineId(String? machineId) => machineId?.trim() ?? '';

  static double? _averageReadingValue(
    List<GoveeSensorReading> readings,
    double? Function(GoveeSensorReading reading) valueFor,
  ) {
    final values = readings.map(valueFor).whereType<double>().toList();
    if (values.isEmpty) return null;
    return _roundTwo(CalculationUtils.average(values));
  }

  static double? _minReadingValue(
    List<GoveeSensorReading> readings,
    double? Function(GoveeSensorReading reading) valueFor,
  ) {
    final values = readings.map(valueFor).whereType<double>().toList();
    if (values.isEmpty) return null;
    return _roundTwo(CalculationUtils.minValue(values)!);
  }

  static double? _maxReadingValue(
    List<GoveeSensorReading> readings,
    double? Function(GoveeSensorReading reading) valueFor,
  ) {
    final values = readings.map(valueFor).whereType<double>().toList();
    if (values.isEmpty) return null;
    return _roundTwo(CalculationUtils.maxValue(values)!);
  }

  static double? _standardDeviationReadingValue(
    List<GoveeSensorReading> readings,
    double? Function(GoveeSensorReading reading) valueFor,
  ) {
    final values = readings.map(valueFor).whereType<double>().toList();
    if (values.isEmpty) return null;
    return _roundTwo(CalculationUtils.stdDev(values));
  }

  static double? _coefficientOfVariationReadingValue(
    List<GoveeSensorReading> readings,
    double? Function(GoveeSensorReading reading) valueFor,
  ) {
    final values = readings.map(valueFor).whereType<double>().toList();
    if (values.isEmpty) return null;
    if (CalculationUtils.average(values) == 0) return null;
    return CalculationUtils.cvPercent(values, decimalPlaces: 2);
  }

  static double _roundTwo(double value) => (value * 100).round() / 100;

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  TemperaturePlace _resolvedPlaceForTarget(
    TemperaturePlace? fallback,
    String? stationKey,
    GoveeCaptureTarget target,
  ) {
    if (target == GoveeCaptureTarget.insideMachine) {
      return _insideMachinePlaceForStation(stationKey) ??
          fallback ??
          TemperaturePlace.eggStorageRoom;
    }
    return _roomPlaceForStation(stationKey) ??
        fallback ??
        TemperaturePlace.eggStorageRoom;
  }

  TemperaturePlace? _roomPlaceForStation(String? stationKey) {
    return switch (stationKey) {
      'setters' => TemperaturePlace.setterRoom,
      'hatchers' => TemperaturePlace.hatcherRoom,
      _ => null,
    };
  }

  TemperaturePlace? _insideMachinePlaceForStation(String? stationKey) {
    return switch (stationKey) {
      'setters' => TemperaturePlace.insideSetter,
      'hatchers' => TemperaturePlace.insideHatcher,
      _ => null,
    };
  }
}
