import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/temperature_rh_model.dart';
import '../../../data/repositories/temperature_rh_repository.dart';
import '../../../services/govee/govee_service.dart';

class TemperatureRhProvider extends ChangeNotifier {
  static const _lastDeviceIdKey = 'govee_last_device_id';
  static const _lastDeviceNameKey = 'govee_last_device_name';

  final TemperatureRhRepository _repository;
  final GoveeService _goveeService;
  final Uuid _uuid = const Uuid();

  bool _isInitialized = false;
  String? _lastPersistedDeviceId;

  TemperatureSessionModel? _activeSession;
  TemperaturePlace? _activePlace;
  final List<GoveeSensorReading> _liveReadings = [];
  final List<TemperatureReadingModel> _recentReadings = [];
  final List<GoveeSensorReading> _readingsBuffer = [];
  final List<TemperatureSessionModel> _completedSessions = [];
  final List<TemperatureSessionModel> _measureLogSessions = [];
  final Map<String, List<TemperatureReadingModel>> _readingsBySession = {};
  final Map<String, List<TemperatureReadingModel>>
  _measureLogReadingsBySession = {};
  StreamSubscription<GoveeSensorReading>? _readingSubscription;
  Timer? _captureTimer;
  DateTime? _lastCapturedSensorAt;
  DateTime? _lastSavedAt;
  int _sampleIntervalSeconds = 5;
  int _warmupSeconds = 120;
  bool _isStarting = false;
  bool _isFinishing = false;
  bool _isLoadingSessions = false;
  bool _isLoadingMeasureLog = false;
  bool _isPaused = false;
  bool _showSavedMessage = false;
  String? _loadedHatcheryId;
  String? _error;

  final List<TemperatureReadingModel> _rawReadings = [];
  List<TemperatureReadingModel> _compressedReadings = [];
  Timer? _auditTimer;
  TemperaturePlace? _auditPlace;
  String? _auditSessionId;
  String? _auditTempSessionId;
  String? _auditSpotLabel;
  DateTime? _auditStartedAt;
  bool _isAuditSyncing = false;
  String? _auditSyncError;

  TemperatureSessionModel? get activeSession => _activeSession;
  TemperaturePlace? get activePlace => _activePlace;
  List<GoveeSensorReading> get liveReadings => List.unmodifiable(_liveReadings);
  List<TemperatureReadingModel> get recentReadings =>
      List.unmodifiable(_recentReadings);
  List<TemperatureSessionModel> get completedSessions =>
      List.unmodifiable(_completedSessions);
  List<TemperatureSessionModel> get measureLogSessions =>
      List.unmodifiable(_measureLogSessions);
  bool get isRecording => _activeSession?.status == 'active';
  bool get isActive => isRecording && !_isPaused;
  bool get isPaused => isRecording && _isPaused;
  bool get showSavedMessage => _showSavedMessage;
  bool get isStarting => _isStarting;
  bool get isFinishing => _isFinishing;
  bool get isInitialized => _isInitialized;
  bool get isLoadingSessions => _isLoadingSessions;
  bool get isLoadingMeasureLog => _isLoadingMeasureLog;
  String? get loadedHatcheryId => _loadedHatcheryId;
  bool get isBleAvailable => _goveeService.isAvailable;
  bool get isSensorConnected => _goveeService.isConnected;
  bool get isGattConnected => _goveeService.isGattConnected;
  bool get isGattConnecting => _goveeService.isGattConnecting;
  bool get isScanning => _goveeService.isScanning;
  String? get deviceName => _goveeService.deviceName;
  int? get signalStrength => _goveeService.signalStrength;
  DateTime? get lastSensorSeenAt => _goveeService.lastSeenAt;
  int? get batteryPercent => _goveeService.latestReading?.batteryPercent;
  List<String> get bleDiagnostics => _goveeService.diagnostics;
  List<DiscoveredGoveeDevice> get discoveredDevices =>
      _goveeService.discoveredGoveeDevices;
  int get sampleIntervalSeconds => _sampleIntervalSeconds;
  String? get error => _error;
  TemperatureReadingModel? get latestReading =>
      _recentReadings.isEmpty ? null : _recentReadings.last;
  double? get liveTemperatureFahrenheit =>
      _goveeService.latestReading?.temperatureFahrenheit ??
      latestReading?.temperatureFahrenheit;
  double? get liveHumidity =>
      _goveeService.latestReading?.humidity ?? latestReading?.humidity;
  DateTime? get liveUpdatedAt =>
      _goveeService.latestReading?.timestamp ??
      latestReading?.recordedAt ??
      _goveeService.lastSeenAt;

  List<TemperatureReadingModel> readingsForSession(String sessionId) {
    return List.unmodifiable(_readingsBySession[sessionId] ?? const []);
  }

  List<TemperatureReadingModel> readingsForMeasureLogSession(String sessionId) {
    return List.unmodifiable(
      _measureLogReadingsBySession[sessionId] ?? const [],
    );
  }

  List<TemperatureReadingModel> readingsForSessions(Iterable<String> ids) {
    final readings = <TemperatureReadingModel>[];
    for (final id in ids) {
      readings.addAll(_readingsBySession[id] ?? const []);
    }
    readings.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    return readings;
  }

  TemperatureRhProvider({
    TemperatureRhRepository? repository,
    GoveeService? goveeService,
  }) : _repository = repository ?? TemperatureRhRepository(),
       _goveeService = goveeService ?? GoveeService();

  void setWarmupSeconds(int seconds) {
    _warmupSeconds = seconds.clamp(0, 600);
    notifyListeners();
  }

  int get warmupSeconds => _warmupSeconds;

  Future<void> startAutoScan() async {
    if (!_goveeService.isScanning) {
      await _goveeService.startScan();
      if (_goveeService.isScanning || _goveeService.isConnected) return;
    }
    for (var attempt = 0; attempt < 20; attempt += 1) {
      if (_goveeService.isScanning) return;
      if (_goveeService.isAvailable) {
        await _goveeService.startScan();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  void _handleGoveeServiceChanged() {
    final deviceId = _goveeService.deviceId;
    if (_isInitialized &&
        _goveeService.isConnected &&
        deviceId != null &&
        deviceId != _lastPersistedDeviceId) {
      unawaited(_persistLastDevice());
    }
    notifyListeners();
  }

  Future<void> _persistLastDevice() async {
    final deviceId = _goveeService.deviceId;
    final deviceName = _goveeService.deviceName;
    if (deviceId == null) return;
    _lastPersistedDeviceId = deviceId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastDeviceIdKey, deviceId);
      if (deviceName != null) {
        await prefs.setString(_lastDeviceNameKey, deviceName);
      }
    } catch (_) {}
  }

  bool _providerListenersAttached = false;

  void _attachProviderListeners() {
    if (_providerListenersAttached) return;
    _providerListenersAttached = true;
    _goveeService.addListener(_handleGoveeServiceChanged);
    _readingSubscription = _goveeService.readings.listen((reading) {
      unawaited(_handleSensorReading(reading));
    });
  }

  Future<void> ensureInitialized() async {
    if (_isInitialized) return;
    _isInitialized = true;
    _goveeService.initializeBle();
    _attachProviderListeners();
    _goveeService.setAutoReconnectEnabled(true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDeviceId = prefs.getString(_lastDeviceIdKey);
      if (savedDeviceId != null) {
        _goveeService.setPreferredDeviceId(savedDeviceId);
      }
    } catch (_) {}
  }

  void setSampleIntervalSeconds(int seconds) {
    _sampleIntervalSeconds = seconds.clamp(5, 60);
    if (isActive) {
      _startCaptureTimer();
    }
    notifyListeners();
  }

  Future<void> loadCompletedSessionsForHatchery(String? hatcheryId) async {
    if (hatcheryId == null || hatcheryId.isEmpty) {
      _loadedHatcheryId = null;
      _completedSessions.clear();
      _readingsBySession.clear();
      notifyListeners();
      return;
    }

    _loadedHatcheryId = hatcheryId;
    _isLoadingSessions = true;
    _error = null;
    notifyListeners();

    try {
      final sessions = await _repository.getCompletedSessionsByHatchery(
        hatcheryId,
      );
      final readings = await _repository.getReadingsForSessions(
        sessions.map((session) => session.id).toList(),
      );
      if (_loadedHatcheryId != hatcheryId) return;
      final grouped = <String, List<TemperatureReadingModel>>{};
      for (final reading in readings) {
        grouped.putIfAbsent(reading.sessionId, () => []).add(reading);
      }
      _completedSessions
        ..clear()
        ..addAll(sessions);
      _readingsBySession
        ..clear()
        ..addAll(grouped);
    } catch (e) {
      _error = 'Could not load saved place sessions';
      if (kDebugMode) debugPrint('Temperature session load failed: $e');
    } finally {
      _isLoadingSessions = false;
      notifyListeners();
    }
  }

  Future<void> loadMeasureLog() async {
    _isLoadingMeasureLog = true;
    _error = null;
    notifyListeners();

    try {
      final sessions = await _repository.getAllSessions();
      final readings = await _repository.getReadingsForSessions(
        sessions.map((session) => session.id).toList(),
      );
      final grouped = <String, List<TemperatureReadingModel>>{};
      for (final reading in readings) {
        grouped.putIfAbsent(reading.sessionId, () => []).add(reading);
      }
      _measureLogSessions
        ..clear()
        ..addAll(sessions);
      _measureLogReadingsBySession
        ..clear()
        ..addAll(grouped);
    } catch (e) {
      _error = 'Could not load saved measures';
      if (kDebugMode) debugPrint('Temperature measure log load failed: $e');
    } finally {
      _isLoadingMeasureLog = false;
      notifyListeners();
    }
  }

  Future<void> startSession({
    required String customerId,
    required String hatcheryId,
    String? auditSessionId,
    int? warmupSeconds,
  }) async {
    _attachProviderListeners();
    if (isRecording || _isStarting) return;
    final activePlace = _activePlace;
    if (activePlace == null) {
      _error = 'Choose a current place before recording';
      notifyListeners();
      return;
    }

    _isStarting = true;
    _error = null;
    notifyListeners();

    if (warmupSeconds != null) {
      _warmupSeconds = warmupSeconds.clamp(0, 600);
    }

    final now = DateTime.now();
    final session = TemperatureSessionModel(
      id: _uuid.v4(),
      customerId: customerId,
      hatcheryId: hatcheryId,
      deviceName: _goveeService.deviceName,
      deviceId: _goveeService.deviceId,
      startedAt: now,
      activePlace: activePlace,
      status: 'active',
      warmupSeconds: _warmupSeconds,
      auditSessionId: auditSessionId,
      createdAt: now,
      updatedAt: now,
    );

    try {
      _activeSession = session;
      _recentReadings.clear();
      _readingsBuffer.clear();
      _lastCapturedSensorAt = null;
      _lastSavedAt = null;
      _isPaused = false;
      _showSavedMessage = false;
      await _repository.upsertSession(session);
      _measureLogSessions.removeWhere((item) => item.id == session.id);
      _measureLogSessions.insert(0, session);
      _measureLogReadingsBySession[session.id] = [];
      _startCaptureTimer();
      await _goveeService.startScan();
      unawaited(saveCurrentPlaceReading(force: true));
    } catch (e) {
      _error = 'Could not start temperature capture';
      if (kDebugMode) debugPrint('Temperature session start failed: $e');
    } finally {
      _isStarting = false;
      notifyListeners();
    }
  }

  Future<void> connectSensor() async {
    _error = null;
    notifyListeners();
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
      if (kDebugMode) debugPrint('Govee connect scan failed: $e');
      notifyListeners();
    }
  }

  Future<void> requestSensorReading() async {
    _error = null;
    notifyListeners();
    try {
      await _goveeService.requestLiveReading();
    } catch (e) {
      _error = 'Could not request a live Govee reading';
      if (kDebugMode) debugPrint('Govee live read failed: $e');
      notifyListeners();
    }
  }

  Future<void> disconnectSensor() async {
    await _goveeService.disconnectDevice();
    notifyListeners();
  }

  Future<void> selectGoveeDevice(String remoteId) async {
    _error = null;
    notifyListeners();
    try {
      await _goveeService.selectDevice(remoteId);
    } catch (e) {
      _error = 'Could not connect to device';
      notifyListeners();
    }
  }

  Future<void> stopSession() async {
    final session = _activeSession;
    if (session == null) return;

    _isFinishing = true;
    _error = null;
    notifyListeners();
    _captureTimer?.cancel();
    _captureTimer = null;
    try {
      final syncStartedAt = DateTime.now();
      final syncing = session.copyWith(
        endedAt: syncStartedAt,
        status: 'syncing',
        updatedAt: syncStartedAt,
      );
      _activeSession = syncing;
      await _repository.upsertSession(syncing);

      if (!_isPaused) {
        await _captureLatestReading(force: true);
      }

      final filtered = _filterReadingsForSummary();
      final summary = _computeSummary(syncing, filtered);
      final completed = summary.copyWith(
        status: 'completed',
        updatedAt: DateTime.now(),
      );

      await _repository.persistSessionSummary(completed);

      _loadedHatcheryId = completed.hatcheryId;
      _completedSessions.removeWhere((item) => item.id == completed.id);
      _completedSessions.insert(0, completed);
      _measureLogReadingsBySession[completed.id] = _recentReadings.toList();
      _readingsBySession[completed.id] = _recentReadings.toList();
      _measureLogSessions.removeWhere((item) => item.id == completed.id);
      _measureLogSessions.insert(0, completed);
      _activeSession = null;
      _activePlace = null;
      _recentReadings.clear();
      _readingsBuffer.clear();
      _lastCapturedSensorAt = null;
      _lastSavedAt = null;
      _isPaused = false;
      _showSavedMessage = true;
    } catch (e) {
      _error = 'Could not finish and sync this place session';
      if (kDebugMode) debugPrint('Temperature session finish failed: $e');
    } finally {
      _isFinishing = false;
      notifyListeners();
    }
  }

  Future<void> togglePause() async {
    if (!isRecording) return;
    _isPaused = !_isPaused;
    if (_isPaused) {
      _captureTimer?.cancel();
      _captureTimer = null;
    } else {
      _startCaptureTimer();
      unawaited(_captureLatestReading(force: true));
    }
    notifyListeners();
  }

  Future<void> setActivePlace(TemperaturePlace place) async {
    if (isRecording) {
      _error = 'Finish the current place before choosing another place';
      notifyListeners();
      return;
    }
    _activePlace = place;
    _showSavedMessage = false;
    final session = _activeSession;
    if (session != null) {
      final updated = session.copyWith(
        activePlace: place,
        updatedAt: DateTime.now(),
      );
      _activeSession = updated;
      await _repository.upsertSession(updated);
    }
    if (isActive) {
      unawaited(_captureLatestReading(force: true));
    }
    notifyListeners();
  }

  Future<void> saveCurrentPlaceReading({bool force = false}) async {
    final sensorReading = _goveeService.latestReading;
    if (sensorReading == null) {
      _error = 'Waiting for a live sensor reading';
      notifyListeners();
      return;
    }
    await _captureSensorReading(sensorReading, force: force);
  }

  Future<void> _handleSensorReading(GoveeSensorReading reading) async {
    _liveReadings.add(reading);
    if (_liveReadings.length > 600) {
      _liveReadings.removeRange(0, _liveReadings.length - 600);
    }
    notifyListeners();

    if (!isActive || !_shouldAutoSave(reading.timestamp)) return;
    await _captureSensorReading(reading);
  }

  void _startCaptureTimer() {
    _captureTimer?.cancel();
    _captureTimer = Timer.periodic(Duration(seconds: _sampleIntervalSeconds), (
      _,
    ) {
      unawaited(_captureLatestReading());
    });
  }

  Future<void> _captureLatestReading({bool force = false}) async {
    final sensorReading = _goveeService.latestReading;
    if (sensorReading == null) return;
    await _captureSensorReading(sensorReading, force: force);
  }

  Future<void> _captureSensorReading(
    GoveeSensorReading sensorReading, {
    bool force = false,
  }) async {
    final session = _activeSession;
    final activePlace = _activePlace;
    if (session == null || activePlace == null) return;
    if (!force &&
        _lastCapturedSensorAt != null &&
        !sensorReading.timestamp.isAfter(_lastCapturedSensorAt!)) {
      return;
    }

    final temp = sensorReading.temperatureFahrenheit;
    final humidity = sensorReading.humidity;
    if (temp == null || humidity == null) return;

    final now = DateTime.now();
    final reading = TemperatureReadingModel(
      id: _uuid.v4(),
      sessionId: session.id,
      customerId: session.customerId,
      hatcheryId: session.hatcheryId,
      place: activePlace,
      temperatureFahrenheit: temp,
      humidity: humidity,
      rssi: _goveeService.signalStrength,
      deviceName: _goveeService.deviceName,
      recordedAt: now,
      createdAt: now,
    );

    _lastCapturedSensorAt = sensorReading.timestamp;
    _lastSavedAt = now;
    _error = null;
    _readingsBuffer.add(sensorReading);
    _recentReadings.add(reading);
    _measureLogReadingsBySession
        .putIfAbsent(session.id, () => <TemperatureReadingModel>[])
        .add(reading);
    await _updateSessionDeviceDetailsIfNeeded();
    if (_recentReadings.length > 600) {
      _recentReadings.removeRange(0, _recentReadings.length - 600);
    }
    notifyListeners();
  }

  bool _shouldAutoSave(DateTime timestamp) {
    final lastSavedAt = _lastSavedAt;
    return lastSavedAt == null ||
        timestamp.difference(lastSavedAt).inSeconds >= _sampleIntervalSeconds;
  }

  Future<void> _updateSessionDeviceDetailsIfNeeded() async {
    final session = _activeSession;
    final deviceName = _goveeService.deviceName;
    final deviceId = _goveeService.deviceId;
    if (session == null ||
        ((session.deviceName != null || deviceName == null) &&
            (session.deviceId != null || deviceId == null))) {
      return;
    }

    final updated = session.copyWith(
      deviceName: deviceName,
      deviceId: deviceId,
    );
    _activeSession = updated;
    await _repository.upsertSession(updated);
  }

  List<GoveeSensorReading> _filterReadingsForSummary() {
    final session = _activeSession;
    if (session == null) return [];
    final warmupEnd = session.startedAt.add(Duration(seconds: _warmupSeconds));
    return _readingsBuffer.where((reading) {
      if (reading.temperatureFahrenheit == null || reading.humidity == null) {
        return false;
      }
      final temp = reading.temperatureFahrenheit!;
      final humidity = reading.humidity!;
      if (temp < -40 || temp > 160 || humidity < 0 || humidity > 100) {
        return false;
      }
      if (!reading.timestamp.isAfter(warmupEnd)) {
        return false;
      }
      return true;
    }).toList();
  }

  TemperatureSessionModel _computeSummary(
    TemperatureSessionModel session,
    List<GoveeSensorReading> readings,
  ) {
    if (readings.isEmpty) {
      return session.copyWith(
        tempChartPointsJson: '[]',
        rhChartPointsJson: '[]',
      );
    }

    final temps = readings.map((r) => r.temperatureFahrenheit!).toList();
    final humidities = readings.map((r) => r.humidity!).toList();

    final tempMin = temps.reduce(math.min);
    final tempMax = temps.reduce(math.max);
    final tempAvg = temps.reduce((a, b) => a + b) / temps.length;
    final tempCv = _computeCv(temps, tempAvg);

    final rhMin = humidities.reduce(math.min);
    final rhMax = humidities.reduce(math.max);
    final rhAvg = humidities.reduce((a, b) => a + b) / humidities.length;
    final rhCv = _computeCv(humidities, rhAvg);

    final chartPoints = _downsampleChartPoints(readings, session.startedAt);

    return session.copyWith(
      tempAvg: _roundTwo(tempAvg),
      tempMin: _roundTwo(tempMin),
      tempMax: _roundTwo(tempMax),
      tempCvPct: _roundTwo(tempCv),
      rhAvg: _roundTwo(rhAvg),
      rhMin: _roundTwo(rhMin),
      rhMax: _roundTwo(rhMax),
      rhCvPct: _roundTwo(rhCv),
      readingCount: readings.length,
      tempChartPointsJson: chartPoints.tempJson,
      rhChartPointsJson: chartPoints.rhJson,
    );
  }

  double _computeCv(List<double> values, double mean) {
    if (values.length < 2 || mean == 0) return 0;
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
        values.length;
    final stdDev = math.sqrt(variance);
    return (stdDev / mean) * 100;
  }

  _ChartPointsResult _downsampleChartPoints(
    List<GoveeSensorReading> readings,
    DateTime startTime,
  ) {
    if (readings.isEmpty) {
      return const _ChartPointsResult(tempJson: '[]', rhJson: '[]');
    }

    final chartReadings = _downsampleSensorReadings(readings);
    final tempPoints = <ChartPoint>[];
    final rhPoints = <ChartPoint>[];

    tempPoints.add(
      ChartPoint(
        timestamp: chartReadings.first.timestamp,
        value: _roundTwo(chartReadings.first.temperatureFahrenheit!),
      ),
    );
    rhPoints.add(
      ChartPoint(
        timestamp: chartReadings.first.timestamp,
        value: _roundTwo(chartReadings.first.humidity!),
      ),
    );
    for (final reading in chartReadings.skip(1)) {
      tempPoints.add(
        ChartPoint(
          timestamp: reading.timestamp,
          value: _roundTwo(reading.temperatureFahrenheit!),
        ),
      );
      rhPoints.add(
        ChartPoint(
          timestamp: reading.timestamp,
          value: _roundTwo(reading.humidity!),
        ),
      );
    }

    return _ChartPointsResult(
      tempJson: ChartPoint.listToJson(tempPoints),
      rhJson: ChartPoint.listToJson(rhPoints),
    );
  }

  List<GoveeSensorReading> _downsampleSensorReadings(
    List<GoveeSensorReading> readings, {
    int maxPoints = 60,
  }) {
    final sorted = readings.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (sorted.length <= maxPoints) return sorted;

    final first = sorted.first.timestamp;
    final last = sorted.last.timestamp;
    final durationMs = math.max(1, last.difference(first).inMilliseconds);
    final intervalMs = durationMs / maxPoints;
    final buckets = List.generate(maxPoints, (_) => <GoveeSensorReading>[]);

    for (final reading in sorted) {
      final elapsedMs = reading.timestamp.difference(first).inMilliseconds;
      final bucketIndex = math
          .min(maxPoints - 1, math.max(0, (elapsedMs / intervalMs).floor()))
          .toInt();
      buckets[bucketIndex].add(reading);
    }

    return buckets.where((bucket) => bucket.isNotEmpty).map((bucket) {
      var tempSum = 0.0;
      var rhSum = 0.0;
      var timestampSum = 0;
      int? battery;
      for (final reading in bucket) {
        tempSum += reading.temperatureFahrenheit!;
        rhSum += reading.humidity!;
        timestampSum += reading.timestamp.millisecondsSinceEpoch;
        battery = reading.batteryPercent ?? battery;
      }
      return GoveeSensorReading(
        temperatureFahrenheit: _roundTwo(tempSum / bucket.length),
        humidity: _roundTwo(rhSum / bucket.length),
        batteryPercent: battery,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          timestampSum ~/ bucket.length,
        ),
      );
    }).toList();
  }

  List<GoveeSensorReading> _filterHistoryReadings(
    List<GoveeSensorReading> readings, {
    required DateTime startedAt,
    required DateTime endedAt,
  }) {
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

  List<TemperatureReadingModel> _buildTemperatureReadingsFromHistory(
    List<GoveeSensorReading> readings, {
    required String sessionId,
    required TemperaturePlace place,
  }) {
    return readings.map((reading) {
      return TemperatureReadingModel(
        id: _uuid.v4(),
        sessionId: sessionId,
        customerId: '',
        hatcheryId: '',
        place: place,
        temperatureFahrenheit: reading.temperatureFahrenheit!,
        humidity: reading.humidity!,
        rssi: _goveeService.signalStrength,
        deviceName: _goveeService.deviceName,
        recordedAt: reading.timestamp,
        createdAt: DateTime.now(),
      );
    }).toList();
  }

  double _roundTwo(double value) {
    return (value * 100).round() / 100;
  }

  List<TemperatureReadingModel> get recentReadingsSnapshot =>
      List.unmodifiable(_recentReadings);

  double? get liveTempAvg {
    if (_readingsBuffer.isEmpty) return null;
    final valid = _readingsBuffer
        .where((r) => r.temperatureFahrenheit != null)
        .toList();
    if (valid.isEmpty) return null;
    return _roundTwo(
      valid.map((r) => r.temperatureFahrenheit!).reduce((a, b) => a + b) /
          valid.length,
    );
  }

  double? get liveRhAvg {
    if (_readingsBuffer.isEmpty) return null;
    final valid = _readingsBuffer.where((r) => r.humidity != null).toList();
    if (valid.isEmpty) return null;
    return _roundTwo(
      valid.map((r) => r.humidity!).reduce((a, b) => a + b) / valid.length,
    );
  }

  Duration get elapsedTime {
    final session = _activeSession;
    if (session == null) return Duration.zero;
    return DateTime.now().difference(session.startedAt);
  }

  int get warmupRemainingSeconds {
    final session = _activeSession;
    if (session == null) return 0;
    final warmupEnd = session.startedAt.add(Duration(seconds: _warmupSeconds));
    final remaining = warmupEnd.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  bool get isInWarmup => warmupRemainingSeconds > 0;

  int get bufferedReadingCount => _readingsBuffer.length;

  int get postWarmupReadingCount => _filterReadingsForSummary().length;

  List<TemperatureReadingModel> get auditCompressedReadings =>
      _compressedReadings;
  bool get isAuditRecording => _auditTimer != null;
  bool get isAuditSyncing => _isAuditSyncing;
  String? get auditSyncError => _auditSyncError;

  void _compress() {
    if (_rawReadings.length <= 60) {
      _compressedReadings = List.from(_rawReadings);
      return;
    }
    final step = _rawReadings.length / 60;
    _compressedReadings = List.generate(
      60,
      (i) => _rawReadings[(i * step).round().clamp(0, _rawReadings.length - 1)],
    );
  }

  void startAuditSession(
    TemperaturePlace place,
    String auditSessionId, {
    String? spotLabel,
  }) {
    _auditPlace = place;
    _auditSessionId = auditSessionId;
    _auditTempSessionId = _uuid.v4();
    _auditSpotLabel = spotLabel;
    _auditStartedAt = DateTime.now();
    _auditSyncError = null;
    _rawReadings.clear();
    _compressedReadings = [];
    _auditTimer?.cancel();
    _auditTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final reading = _buildReadingFromCurrentGoveeData();
      if (reading == null) return;
      _rawReadings.add(reading);
      _compress();
      notifyListeners();
    });
  }

  TemperatureReadingModel? _buildReadingFromCurrentGoveeData() {
    final latestReading = _goveeService.latestReading;
    if (latestReading == null) return null;
    final temp = latestReading.temperatureFahrenheit;
    final humidity = latestReading.humidity;
    if (temp == null || humidity == null) return null;

    final now = DateTime.now();
    return TemperatureReadingModel(
      id: _uuid.v4(),
      sessionId: _auditTempSessionId!,
      customerId: '',
      hatcheryId: '',
      place: _auditPlace!,
      temperatureFahrenheit: temp,
      humidity: humidity,
      rssi: _goveeService.signalStrength,
      deviceName: _goveeService.deviceName,
      recordedAt: now,
      createdAt: now,
    );
  }

  Future<void> stopAndSaveAuditSession() async {
    _auditTimer?.cancel();
    _auditTimer = null;
    final place = _auditPlace;
    final auditSessionId = _auditSessionId;
    final tempSessionId = _auditTempSessionId;
    final startedAt = _auditStartedAt;
    final spotLabel = _auditSpotLabel;
    final endedAt = DateTime.now();

    if (place == null ||
        auditSessionId == null ||
        tempSessionId == null ||
        startedAt == null) {
      _auditPlace = null;
      _auditSessionId = null;
      _auditTempSessionId = null;
      _auditSpotLabel = null;
      _auditStartedAt = null;
      _rawReadings.clear();
      _compressedReadings = [];
      return;
    }

    _isAuditSyncing = true;
    _auditSyncError = null;
    notifyListeners();

    try {
      final syncedReadings = await _goveeService.syncHistory(
        startedAt: startedAt,
        endedAt: endedAt,
      );
      final validReadings = _filterHistoryReadings(
        syncedReadings,
        startedAt: startedAt,
        endedAt: endedAt,
      );

      if (validReadings.isEmpty) {
        _auditSyncError = 'No synced Govee history found for this spot';
        return;
      }

      final compressedSensorReadings = _downsampleSensorReadings(validReadings);
      final compressedReadings = _buildTemperatureReadingsFromHistory(
        compressedSensorReadings,
        sessionId: tempSessionId,
        place: place,
      );

      final now = DateTime.now();
      final session = TemperatureSessionModel(
        id: tempSessionId,
        customerId: '',
        hatcheryId: '',
        deviceId: _goveeService.deviceId,
        deviceName: _goveeService.deviceName,
        spotLabel: spotLabel,
        captureSource: 'govee_history_sync',
        startedAt: startedAt,
        endedAt: endedAt,
        activePlace: place,
        status: 'completed',
        auditSessionId: auditSessionId,
        createdAt: now,
        updatedAt: now,
      );
      final summary = _computeSummary(session, validReadings);

      await _repository.upsertSession(summary);
      await _repository.insertReadings(compressedReadings);
    } finally {
      _isAuditSyncing = false;
      _auditPlace = null;
      _auditSessionId = null;
      _auditTempSessionId = null;
      _auditSpotLabel = null;
      _auditStartedAt = null;
      _rawReadings.clear();
      _compressedReadings = [];
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _auditTimer?.cancel();
    _captureTimer?.cancel();
    _readingSubscription?.cancel();
    _goveeService.removeListener(_handleGoveeServiceChanged);
    _goveeService.dispose();
    super.dispose();
  }
}

class _ChartPointsResult {
  final String tempJson;
  final String rhJson;

  const _ChartPointsResult({required this.tempJson, required this.rhJson});
}
