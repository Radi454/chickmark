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

class GoveeAvailableDevice {
  final String remoteId;
  final String name;
  final int? rssi;
  final DateTime lastSeen;
  final bool selected;

  const GoveeAvailableDevice({
    required this.remoteId,
    required this.name,
    this.rssi,
    required this.lastSeen,
    required this.selected,
  });
}

class GoveeCaptureProvider extends ChangeNotifier {
  static const int maxLivePreviewReadings = 500;
  static const Duration _manualScanDiscoveryTimeout = Duration(seconds: 30);

  final GoveeCaptureRepository _repository;
  final GoveeService _goveeService;
  final DateTime Function() _clock;
  final bool _enablePhaseTimer;
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
  Timer? _phaseTimer;
  int _recordingElapsedSeconds = 0;
  final List<GoveeSensorReading> _livePreviewBufferedReadings = [];
  final List<GoveeSensorReading> _liveRecordingReadings = [];

  GoveeCaptureProvider({
    GoveeCaptureRepository? repository,
    GoveeService? goveeService,
    DateTime Function()? clock,
    bool enablePhaseTimer = true,
  }) : _repository = repository ?? GoveeCaptureRepository(),
       _goveeService = goveeService ?? GoveeService(),
       _enablePhaseTimer = enablePhaseTimer,
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
  int get recordingElapsedSeconds {
    final startedAt = _recordingStartedAt;
    if (_phase == GoveeCapturePhase.validRecording && startedAt != null) {
      return _elapsedSecondsSince(startedAt, _clock());
    }
    return _recordingElapsedSeconds;
  }

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
  String? get deviceId => _goveeService.deviceId;
  int? get signalStrength => _goveeService.signalStrength;
  DateTime? get liveUpdatedAt =>
      _goveeService.latestReading?.timestamp ?? _goveeService.lastSeenAt;
  double? get liveTemperatureFahrenheit =>
      _goveeService.latestReading?.temperatureFahrenheit;
  double? get liveHumidity => _goveeService.latestReading?.humidity;
  int? get batteryPercent => _goveeService.latestReading?.batteryPercent;
  List<String> get bleDiagnostics => _goveeService.diagnostics;
  List<GoveeAvailableDevice> get availableDevices {
    final selectedId = _goveeService.deviceId;
    final devices = _goveeService.discoveredGoveeDevices
        .map(
          (device) => GoveeAvailableDevice(
            remoteId: device.remoteId,
            name: device.name.trim().isEmpty ? 'Govee sensor' : device.name,
            rssi: device.rssi,
            lastSeen: device.lastSeen,
            selected: device.remoteId == selectedId,
          ),
        )
        .toList(growable: false);
    final sorted = List<GoveeAvailableDevice>.from(devices)
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return List.unmodifiable(sorted);
  }

  List<GoveeSensorReading> get liveRecordingReadings =>
      List.unmodifiable(_liveRecordingReadings);
  List<GoveeSensorReading> get livePreviewReadings {
    if (isRecording) {
      if (_liveRecordingReadings.isNotEmpty) {
        return List.unmodifiable(_liveRecordingReadings);
      }
      final latest = _goveeService.latestReading;
      if (latest == null ||
          latest.temperatureFahrenheit == null ||
          latest.humidity == null) {
        return const [];
      }
      final startedAt = _recordingStartedAt;
      if (startedAt != null && latest.timestamp.isBefore(startedAt)) {
        return const [];
      }
      return List.unmodifiable([latest]);
    }
    if (_livePreviewBufferedReadings.isNotEmpty) {
      return List.unmodifiable(_livePreviewBufferedReadings);
    }
    if (_liveRecordingReadings.isNotEmpty) {
      return List.unmodifiable(_liveRecordingReadings);
    }
    final latest = _goveeService.latestReading;
    if (latest == null ||
        latest.temperatureFahrenheit == null ||
        latest.humidity == null) {
      return const [];
    }
    return List.unmodifiable([latest]);
  }

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
    _stopPhaseTimer(reset: true);
    _recordingStartedAt = null;
    _failedRecordingStartedAt = null;
    _failedRecordingEndedAt = null;
    _clearPendingSave();
    _error = null;
    _syncFailureDetails = null;
    _syncFailureDiagnostics = const [];
    _livePreviewBufferedReadings.clear();
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
        await _goveeService.restartScan(
          discoveryTimeout: _manualScanDiscoveryTimeout,
        );
      } else {
        await _goveeService.startScan(
          discoveryTimeout: _manualScanDiscoveryTimeout,
        );
      }
    } catch (e) {
      _error = 'Could not scan for the Govee sensor';
      if (kDebugMode) debugPrint('Govee capture scan failed: $e');
      notifyListeners();
    }
  }

  Future<bool> _connectSensorForRecording() async {
    _attachGoveeListeners();
    _goveeService.setAutoReconnectEnabled(true);
    try {
      if (_goveeService.isGattConnected) {
        return true;
      }
      if (_goveeService.isConnected) {
        await _goveeService.connectDevice();
      } else if (_goveeService.isScanning) {
        await _goveeService.restartScan(
          discoveryTimeout: _manualScanDiscoveryTimeout,
        );
      } else {
        await _goveeService.startScan(
          discoveryTimeout: _manualScanDiscoveryTimeout,
        );
      }
      return true;
    } catch (e) {
      _error = 'Could not scan for the Govee sensor';
      if (kDebugMode) debugPrint('Govee capture scan failed: $e');
      notifyListeners();
      return false;
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

  Future<void> disconnectSensor() async {
    try {
      _goveeService.setAutoReconnectEnabled(false);
      await _goveeService.disconnectDevice();
    } catch (e) {
      _error = 'Could not disconnect the Govee sensor';
      if (kDebugMode) debugPrint('Govee capture disconnect failed: $e');
    } finally {
      notifyListeners();
    }
  }

  Future<void> selectSensorDevice(String remoteId) async {
    _attachGoveeListeners();
    try {
      _goveeService.setAutoReconnectEnabled(true);
      await _goveeService.selectDevice(remoteId);
    } catch (e) {
      _error = 'Could not connect to the selected Govee sensor';
      if (kDebugMode) debugPrint('Govee capture device select failed: $e');
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

    if (!await _connectSensorForRecording()) return;
    _recordingStartedAt = _clock();
    _failedRecordingStartedAt = null;
    _failedRecordingEndedAt = null;
    _clearPendingSave();
    _livePreviewBufferedReadings.clear();
    _liveRecordingReadings.clear();
    _phase = GoveeCapturePhase.validRecording;
    _recordingElapsedSeconds = 0;
    _error = null;
    _syncFailureDetails = null;
    _syncFailureDiagnostics = const [];
    _startPhaseTimer();
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
    List<GoveeSensorReading>? syncedForDiagnostics;
    final liveFallbackReadings = List<GoveeSensorReading>.from(
      _liveRecordingReadings,
    );
    if (isRetryingSave && _pendingSaveReadings.isNotEmpty) {
      valid = _pendingSaveReadings;
      _error = null;
      _syncFailureDetails = null;
      _syncFailureDiagnostics = const [];
    } else {
      _stopPhaseTimer();
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
        syncedForDiagnostics = synced;
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

      final syncedValid = _filterValidSyncedReadings(
        synced,
        startedAt,
        endedAt,
      );
      valid = syncedValid.isNotEmpty
          ? syncedValid
          : _filterValidSyncedReadings(
              liveFallbackReadings,
              startedAt,
              endedAt,
            );
    }

    if (valid.isEmpty) {
      _error =
          'No valid synced Govee readings were found inside this recording window.';
      if (syncedForDiagnostics != null) {
        _syncFailureDetails =
            'History sync returned ${syncedForDiagnostics.length} readings, but none matched the recording window.';
        _syncFailureDiagnostics = _buildNoValidReadingsDiagnostics(
          startedAt: startedAt,
          endedAt: endedAt,
          syncedReadings: syncedForDiagnostics,
        );
      }
      _phase = GoveeCapturePhase.idle;
      _recordingStartedAt = null;
      _failedRecordingStartedAt = null;
      _failedRecordingEndedAt = null;
      _clearPendingSave();
      _liveRecordingReadings.clear();
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
      readingCount: valid.length,
      createdAt: now,
      updatedAt: now,
    );
    final readings = valid
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
    _stopPhaseTimer(reset: true);
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
    if (reading.temperatureFahrenheit == null || reading.humidity == null) {
      return;
    }
    if (!isRecording) {
      if (_phase != GoveeCapturePhase.idle &&
          _phase != GoveeCapturePhase.saved) {
        return;
      }
      _appendLiveReading(_livePreviewBufferedReadings, reading);
      notifyListeners();
      return;
    }
    final startedAt = _recordingStartedAt;
    if (startedAt == null || !reading.timestamp.isBefore(startedAt)) {
      _appendLiveReading(_liveRecordingReadings, reading);
      notifyListeners();
    }
  }

  void _appendLiveReading(
    List<GoveeSensorReading> readings,
    GoveeSensorReading reading,
  ) {
    readings.add(reading);
    final overflow = readings.length - maxLivePreviewReadings;
    if (overflow > 0) {
      readings.removeRange(0, overflow);
    }
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    unawaited(_liveSubscription?.cancel());
    if (_goveeListenersAttached) {
      _goveeService.removeListener(_handleGoveeServiceChanged);
    }
    super.dispose();
  }

  void _startPhaseTimer() {
    _phaseTimer?.cancel();
    if (!_enablePhaseTimer) return;
    _phaseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final startedAt = _recordingStartedAt;
      if (_phase != GoveeCapturePhase.validRecording || startedAt == null) {
        _stopPhaseTimer();
        return;
      }
      final elapsed = _elapsedSecondsSince(startedAt, _clock());
      if (elapsed == _recordingElapsedSeconds) return;
      _recordingElapsedSeconds = elapsed;
      notifyListeners();
    });
  }

  void _stopPhaseTimer({bool reset = false}) {
    _phaseTimer?.cancel();
    _phaseTimer = null;
    if (reset) {
      _recordingElapsedSeconds = 0;
      return;
    }
    final startedAt = _recordingStartedAt;
    if (startedAt != null) {
      _recordingElapsedSeconds = _elapsedSecondsSince(startedAt, _clock());
    }
  }

  int _elapsedSecondsSince(DateTime startedAt, DateTime now) {
    return math.max(0, now.difference(startedAt).inSeconds);
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
      if (!_readingOverlapsWindow(reading, startedAt, endedAt)) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  bool _readingOverlapsWindow(
    GoveeSensorReading reading,
    DateTime startedAt,
    DateTime endedAt,
  ) {
    final bucketStartedAt = reading.bucketStartedAt;
    final bucketEndedAt = reading.bucketEndedAt;
    if (bucketStartedAt == null || bucketEndedAt == null) {
      return !reading.timestamp.isBefore(startedAt) &&
          !reading.timestamp.isAfter(endedAt);
    }
    return bucketEndedAt.isAfter(startedAt) &&
        !bucketStartedAt.isAfter(endedAt);
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

  List<String> _buildNoValidReadingsDiagnostics({
    required DateTime startedAt,
    required DateTime endedAt,
    required List<GoveeSensorReading> syncedReadings,
  }) {
    var missingValues = 0;
    var invalidValues = 0;
    var beforeValidWindow = 0;
    var afterStop = 0;
    for (final reading in syncedReadings) {
      final temp = reading.temperatureFahrenheit;
      final humidity = reading.humidity;
      if (temp == null || humidity == null) {
        missingValues += 1;
      } else if (temp < -40 || temp > 160 || humidity < 0 || humidity > 100) {
        invalidValues += 1;
      } else if (!_readingOverlapsWindow(reading, startedAt, endedAt)) {
        final bucketStartedAt = reading.bucketStartedAt ?? reading.timestamp;
        final bucketEndedAt = reading.bucketEndedAt ?? reading.timestamp;
        if (!bucketEndedAt.isAfter(startedAt)) {
          beforeValidWindow += 1;
        } else if (bucketStartedAt.isAfter(endedAt)) {
          afterStop += 1;
        }
      }
    }

    final sorted = List<GoveeSensorReading>.from(syncedReadings)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final span = sorted.isEmpty
        ? 'Synced timestamp span: none'
        : 'Synced timestamp span: ${sorted.first.timestamp.toIso8601String()} to ${sorted.last.timestamp.toIso8601String()}';
    final diagnostics = _goveeService.diagnostics;
    final start = math.max(0, diagnostics.length - 6);
    return [
      _syncContextLine(startedAt: startedAt, endedAt: endedAt),
      'Recording window: ${startedAt.toIso8601String()} to ${endedAt.toIso8601String()}',
      'Synced readings: ${syncedReadings.length}; before valid window: $beforeValidWindow; after stop: $afterStop; missing Temp/RH: $missingValues; invalid values: $invalidValues.',
      span,
      ...diagnostics.sublist(start),
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
