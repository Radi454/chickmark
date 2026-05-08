import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/govee_capture_model.dart';
import '../../../data/models/temperature_rh_model.dart';
import '../../../data/repositories/govee_capture_repository.dart';
import '../../../services/govee/govee_service.dart';
import '../../temperature/services/lttb_downsampler.dart';
import '../utils/govee_place_flow.dart';

enum GoveeCapturePhase {
  idle,
  validRecording,
  syncing,
  syncFailed,
  saving,
  saved,
}

enum GoveeCaptureTarget { room, insideMachine }

class GoveeCaptureProvider extends ChangeNotifier {
  static const Duration _historyReadingBucketDuration = Duration(minutes: 1);

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
  GoveeCapturePhase _phase = GoveeCapturePhase.idle;
  DateTime? _recordingStartedAt;
  DateTime? _failedRecordingStartedAt;
  DateTime? _failedRecordingEndedAt;
  String? _error;
  String? _syncFailureDetails;
  List<String> _syncFailureDiagnostics = const [];
  TemperaturePlace? _suggestedNextPlace;
  bool _goveeListenersAttached = false;
  Timer? _phaseTimer;
  StreamSubscription<GoveeSensorReading>? _liveSubscription;
  final List<GoveeSensorReading> _liveRecordingReadings = [];

  GoveeCaptureProvider({
    GoveeCaptureRepository? repository,
    GoveeService? goveeService,
    DateTime Function()? clock,
    bool enablePhaseTimer = true,
  }) : _repository = repository ?? GoveeCaptureRepository(),
       _goveeService = goveeService ?? GoveeService(),
       _clock = clock ?? DateTime.now,
       _enablePhaseTimer = enablePhaseTimer;

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
    if (_phase != GoveeCapturePhase.validRecording || startedAt == null) {
      return 0;
    }
    final elapsed = _clock().difference(startedAt);
    if (elapsed.isNegative) return 0;
    return elapsed.inSeconds;
  }

  bool get canStartRecording =>
      _customerId != null &&
      _hatcheryId != null &&
      _place != null &&
      _captureDate != null &&
      (_phase == GoveeCapturePhase.idle || _phase == GoveeCapturePhase.saved);
  bool get canStopRecording =>
      _phase == GoveeCapturePhase.syncFailed ||
      _phase == GoveeCapturePhase.validRecording;
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
    _stopPhaseTimer();
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
    _error = null;
    _syncFailureDetails = null;
    _syncFailureDiagnostics = const [];
    _liveRecordingReadings.clear();
    _finishedCapture = null;
    _finishedReadings = const [];
    _suggestedNextPlace = null;
    _existingCapture = await _repository.getCaptureForScope(
      customerId: customerId,
      hatcheryId: hatcheryId,
      stationKey: resolvedStationKey,
      place: _place!,
      machineId: this.machineId,
      captureDate: _captureDate!,
    );
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
    _liveRecordingReadings.clear();
    _finishedCapture = null;
    _finishedReadings = const [];
    _phase = GoveeCapturePhase.validRecording;
    _error = null;
    _syncFailureDetails = null;
    _syncFailureDiagnostics = const [];
    _startPhaseTimer();
    notifyListeners();
  }

  Future<void> stopAndSavePlaceCapture() async {
    final startedAt = _phase == GoveeCapturePhase.syncFailed
        ? _failedRecordingStartedAt
        : _recordingStartedAt;
    final endedAt = _phase == GoveeCapturePhase.syncFailed
        ? _failedRecordingEndedAt
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

    final valid = _filterValidSyncedReadings(synced, startedAt, endedAt);

    if (valid.isEmpty) {
      _error = 'No valid synced Govee readings were found';
      _phase = GoveeCapturePhase.validRecording;
      _startPhaseTimer();
      notifyListeners();
      return;
    }

    _phase = GoveeCapturePhase.saving;
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

    await _repository.saveReplacement(capture: capture, readings: readings);
    _finishedCapture = capture;
    _finishedReadings = readings;
    _recordingStartedAt = null;
    _failedRecordingStartedAt = null;
    _failedRecordingEndedAt = null;
    _syncFailureDetails = null;
    _syncFailureDiagnostics = const [];
    _phase = GoveeCapturePhase.saved;
    _stopPhaseTimer();
    _suggestedNextPlace = nextGoveePlace(_place!);
    _existingCapture = null;
    notifyListeners();
  }

  void clearAfterSaveAndSuggestNextPlace() {
    _finishedCapture = null;
    _finishedReadings = const [];
    _liveRecordingReadings.clear();
    _recordingStartedAt = null;
    _failedRecordingStartedAt = null;
    _failedRecordingEndedAt = null;
    _syncFailureDetails = null;
    _syncFailureDiagnostics = const [];
    _phase = GoveeCapturePhase.saved;
    _stopPhaseTimer();
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
    notifyListeners();
  }

  @override
  void dispose() {
    _stopPhaseTimer();
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
      final readingBucketEndedAt = reading.timestamp.add(
        _historyReadingBucketDuration,
      );
      if (!readingBucketEndedAt.isAfter(startedAt) ||
          reading.timestamp.isAfter(endedAt)) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  void _startPhaseTimer() {
    if (!_enablePhaseTimer) return;
    _phaseTimer?.cancel();
    _phaseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_phase != GoveeCapturePhase.validRecording) {
        _stopPhaseTimer();
        return;
      }
      notifyListeners();
    });
  }

  void _stopPhaseTimer() {
    _phaseTimer?.cancel();
    _phaseTimer = null;
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

  static double? _averageReadingValue(
    List<GoveeSensorReading> readings,
    double? Function(GoveeSensorReading reading) valueFor,
  ) {
    final values = readings.map(valueFor).whereType<double>().toList();
    if (values.isEmpty) return null;
    return _roundTwo(values.reduce((a, b) => a + b) / values.length);
  }

  static double? _minReadingValue(
    List<GoveeSensorReading> readings,
    double? Function(GoveeSensorReading reading) valueFor,
  ) {
    final values = readings.map(valueFor).whereType<double>().toList();
    if (values.isEmpty) return null;
    return _roundTwo(values.reduce(math.min));
  }

  static double? _maxReadingValue(
    List<GoveeSensorReading> readings,
    double? Function(GoveeSensorReading reading) valueFor,
  ) {
    final values = readings.map(valueFor).whereType<double>().toList();
    if (values.isEmpty) return null;
    return _roundTwo(values.reduce(math.max));
  }

  static double? _standardDeviationReadingValue(
    List<GoveeSensorReading> readings,
    double? Function(GoveeSensorReading reading) valueFor,
  ) {
    final values = readings.map(valueFor).whereType<double>().toList();
    if (values.isEmpty) return null;
    final avg = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values
            .map((value) => math.pow(value - avg, 2))
            .reduce((a, b) => a + b) /
        values.length;
    return _roundTwo(math.sqrt(variance));
  }

  static double? _coefficientOfVariationReadingValue(
    List<GoveeSensorReading> readings,
    double? Function(GoveeSensorReading reading) valueFor,
  ) {
    final values = readings.map(valueFor).whereType<double>().toList();
    if (values.isEmpty) return null;
    final avg = values.reduce((a, b) => a + b) / values.length;
    if (avg == 0) return null;
    final variance =
        values
            .map((value) => math.pow(value - avg, 2))
            .reduce((a, b) => a + b) /
        values.length;
    return _roundTwo(math.sqrt(variance) / avg * 100);
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
