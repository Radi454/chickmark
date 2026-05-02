import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/govee_capture_model.dart';
import '../../../data/models/temperature_rh_model.dart';
import '../../../data/repositories/govee_capture_repository.dart';
import '../../../services/govee/govee_service.dart';
import '../utils/govee_place_flow.dart';

enum GoveeSpotPhase {
  idle,
  warmup,
  validRecording,
  readyForNext,
  autoEnded,
  syncing,
  complete,
  review,
  saving,
  saved,
}

class GoveeCaptureProvider extends ChangeNotifier {
  static const int spotCount = 3;
  static const Duration warmupDuration = Duration(seconds: 60);
  static const Duration minimumValidDuration = Duration(seconds: 60);
  static const Duration maximumValidDuration = Duration(minutes: 15);

  final GoveeCaptureRepository _repository;
  final GoveeService _goveeService;
  final DateTime Function() _clock;
  final bool _enablePhaseTimer;
  final Uuid _uuid = const Uuid();

  String? _customerId;
  String? _hatcheryId;
  TemperaturePlace? _place;
  String? _captureDate;
  GoveeDailyCaptureModel? _existingCapture;
  GoveeSpotPhase _phase = GoveeSpotPhase.idle;
  DateTime? _warmupStartedAt;
  String? _error;
  final List<_PendingSpotCapture> _pendingSpots = [];
  _SpotSyncWindow? _failedSyncWindow;
  TemperaturePlace? _suggestedNextPlace;
  Timer? _phaseTimer;

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
  GoveeDailyCaptureModel? get existingCapture => _existingCapture;
  bool get hasExistingCapture => _existingCapture != null;
  String? get error => _error;
  TemperaturePlace? get suggestedNextPlace => _suggestedNextPlace;
  int get completedSpotCount => _pendingSpots.length;
  int get currentSpotIndex => math.min(_pendingSpots.length + 1, spotCount);

  GoveeSpotPhase get phase {
    _refreshTimedPhase();
    return _phase;
  }

  bool get canFinishCurrentSpot {
    _refreshTimedPhase();
    return _phase == GoveeSpotPhase.readyForNext ||
        _phase == GoveeSpotPhase.autoEnded;
  }

  Future<void> configure({
    required String customerId,
    required String hatcheryId,
    required TemperaturePlace place,
    String? captureDate,
  }) async {
    _customerId = customerId;
    _hatcheryId = hatcheryId;
    _place = place;
    _captureDate = captureDate ?? _formatDate(_clock());
    _phase = GoveeSpotPhase.idle;
    _warmupStartedAt = null;
    _failedSyncWindow = null;
    _stopPhaseTimer();
    _error = null;
    _pendingSpots.clear();
    _suggestedNextPlace = null;
    _existingCapture = await _repository.getCaptureForScope(
      customerId: customerId,
      hatcheryId: hatcheryId,
      place: place,
      captureDate: _captureDate!,
    );
    notifyListeners();
  }

  Future<void> startCurrentSpot() async {
    if (_customerId == null || _hatcheryId == null || _place == null) {
      _error = 'Choose a customer, hatchery, date, and place first';
      notifyListeners();
      return;
    }
    if (_pendingSpots.length >= spotCount ||
        _phase == GoveeSpotPhase.syncing ||
        _phase == GoveeSpotPhase.saving) {
      return;
    }

    _warmupStartedAt = _clock();
    _failedSyncWindow = null;
    _phase = GoveeSpotPhase.warmup;
    _startPhaseTimer();
    _error = null;
    notifyListeners();
  }

  Future<void> finishCurrentSpot() async {
    if (!canFinishCurrentSpot &&
        (_phase != GoveeSpotPhase.readyForNext || _failedSyncWindow == null)) {
      _error = 'Complete warmup and the minimum valid window first';
      notifyListeners();
      return;
    }

    final syncWindow = _failedSyncWindow ?? _buildCurrentSyncWindow();
    if (syncWindow == null) {
      _error = 'Complete warmup and the minimum valid window first';
      notifyListeners();
      return;
    }

    _phase = GoveeSpotPhase.syncing;
    _stopPhaseTimer();
    _error = null;
    notifyListeners();

    final List<GoveeSensorReading> synced;
    try {
      synced = await _goveeService.syncHistory(
        startedAt: syncWindow.validStartedAt,
        endedAt: syncWindow.validEndedAt,
      );
    } catch (_) {
      _markSyncFailed(syncWindow);
      return;
    }
    final valid = _filterValidSyncedReadings(
      synced,
      syncWindow.validStartedAt,
      syncWindow.validEndedAt,
    );

    if (valid.length < 60) {
      _markSyncFailed(syncWindow);
      return;
    }

    final compressed = compressSyncedReadings(valid, targetCount: 60);
    _pendingSpots.add(
      _PendingSpotCapture(
        spotIndex: _pendingSpots.length + 1,
        warmupStartedAt: syncWindow.warmupStartedAt,
        validStartedAt: syncWindow.validStartedAt,
        validEndedAt: syncWindow.validEndedAt,
        readings: compressed,
      ),
    );
    _failedSyncWindow = null;
    _warmupStartedAt = null;
    _phase = _pendingSpots.length >= spotCount
        ? GoveeSpotPhase.review
        : GoveeSpotPhase.complete;
    notifyListeners();
  }

  Future<void> savePlaceCapture({required List<String> spotLabels}) async {
    if (_pendingSpots.length != spotCount ||
        _customerId == null ||
        _hatcheryId == null ||
        _place == null ||
        _captureDate == null) {
      _error = 'Complete all three Govee spots before saving';
      notifyListeners();
      return;
    }

    _phase = GoveeSpotPhase.saving;
    _error = null;
    notifyListeners();

    final now = _clock();
    final captureId = _uuid.v4();
    final allReadings = _pendingSpots.expand((spot) => spot.readings).toList();
    final capture = GoveeDailyCaptureModel(
      id: captureId,
      customerId: _customerId!,
      hatcheryId: _hatcheryId!,
      place: _place!,
      captureDate: _captureDate!,
      deviceId: _goveeService.deviceId,
      deviceName: _goveeService.deviceName,
      status: 'completed',
      tempAvg: _averageReadingValue(
        allReadings,
        (reading) => reading.temperatureFahrenheit,
      ),
      tempMin: _minReadingValue(
        allReadings,
        (reading) => reading.temperatureFahrenheit,
      ),
      tempMax: _maxReadingValue(
        allReadings,
        (reading) => reading.temperatureFahrenheit,
      ),
      rhAvg: _averageReadingValue(allReadings, (reading) => reading.humidity),
      rhMin: _minReadingValue(allReadings, (reading) => reading.humidity),
      rhMax: _maxReadingValue(allReadings, (reading) => reading.humidity),
      spotCount: spotCount,
      readingCount: allReadings.length,
      createdAt: now,
      updatedAt: now,
    );

    final spots = <GoveeSpotCaptureModel>[];
    final readings = <GoveeSpotReadingModel>[];
    for (var i = 0; i < _pendingSpots.length; i += 1) {
      final pending = _pendingSpots[i];
      final spotId = _uuid.v4();
      final label = i < spotLabels.length && spotLabels[i].trim().isNotEmpty
          ? spotLabels[i].trim()
          : 'Spot ${i + 1}';
      spots.add(
        GoveeSpotCaptureModel(
          id: spotId,
          captureId: captureId,
          spotIndex: pending.spotIndex,
          spotLabel: label,
          warmupStartedAt: pending.warmupStartedAt,
          validStartedAt: pending.validStartedAt,
          validEndedAt: pending.validEndedAt,
          validDurationSeconds: pending.validEndedAt
              .difference(pending.validStartedAt)
              .inSeconds,
          tempAvg: _averageReadingValue(
            pending.readings,
            (reading) => reading.temperatureFahrenheit,
          ),
          tempMin: _minReadingValue(
            pending.readings,
            (reading) => reading.temperatureFahrenheit,
          ),
          tempMax: _maxReadingValue(
            pending.readings,
            (reading) => reading.temperatureFahrenheit,
          ),
          rhAvg: _averageReadingValue(
            pending.readings,
            (reading) => reading.humidity,
          ),
          rhMin: _minReadingValue(
            pending.readings,
            (reading) => reading.humidity,
          ),
          rhMax: _maxReadingValue(
            pending.readings,
            (reading) => reading.humidity,
          ),
          readingCount: pending.readings.length,
          createdAt: now,
          updatedAt: now,
        ),
      );

      readings.addAll(
        pending.readings.asMap().entries.map((entry) {
          final reading = entry.value;
          return GoveeSpotReadingModel(
            id: _uuid.v4(),
            captureId: captureId,
            spotId: spotId,
            readingIndex: entry.key,
            recordedAt: reading.timestamp,
            temperatureFahrenheit: reading.temperatureFahrenheit!,
            humidity: reading.humidity!,
            rssi: _goveeService.signalStrength,
            deviceName: _goveeService.deviceName,
            createdAt: now,
          );
        }),
      );
    }

    await _repository.saveReplacement(
      capture: capture,
      spots: spots,
      readings: readings,
    );
    clearAfterSaveAndSuggestNextPlace();
  }

  void clearAfterSaveAndSuggestNextPlace() {
    final previousPlace = _place;
    _pendingSpots.clear();
    _warmupStartedAt = null;
    _failedSyncWindow = null;
    _stopPhaseTimer();
    _phase = GoveeSpotPhase.saved;
    _suggestedNextPlace = previousPlace == null
        ? null
        : nextGoveePlace(previousPlace);
    if (_suggestedNextPlace != null) {
      _place = _suggestedNextPlace;
    }
    _existingCapture = null;
    notifyListeners();
  }

  static List<GoveeSensorReading> compressSyncedReadings(
    List<GoveeSensorReading> readings, {
    int targetCount = 60,
  }) {
    final valid =
        readings
            .where(
              (reading) =>
                  reading.temperatureFahrenheit != null &&
                  reading.humidity != null,
            )
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (valid.length <= targetCount) return valid;

    final first = valid.first.timestamp;
    final last = valid.last.timestamp;
    final durationMs = math.max(1, last.difference(first).inMilliseconds);
    final intervalMs = durationMs / targetCount;
    final buckets = List.generate(targetCount, (_) => <GoveeSensorReading>[]);

    for (final reading in valid) {
      final elapsedMs = reading.timestamp.difference(first).inMilliseconds;
      final bucketIndex = math
          .min(targetCount - 1, math.max(0, (elapsedMs / intervalMs).floor()))
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

  void _refreshTimedPhase() {
    final warmupStartedAt = _warmupStartedAt;
    if (warmupStartedAt == null ||
        _failedSyncWindow != null ||
        (_phase != GoveeSpotPhase.warmup &&
            _phase != GoveeSpotPhase.validRecording &&
            _phase != GoveeSpotPhase.readyForNext)) {
      return;
    }

    final elapsed = _clock().difference(warmupStartedAt);
    if (elapsed >= warmupDuration + maximumValidDuration) {
      _phase = GoveeSpotPhase.autoEnded;
    } else if (elapsed >= warmupDuration + minimumValidDuration) {
      _phase = GoveeSpotPhase.readyForNext;
    } else if (elapsed >= warmupDuration) {
      _phase = GoveeSpotPhase.validRecording;
    } else {
      _phase = GoveeSpotPhase.warmup;
    }
  }

  void _startPhaseTimer() {
    _stopPhaseTimer();
    if (!_enablePhaseTimer) return;
    _phaseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final previous = _phase;
      _refreshTimedPhase();
      if (_phase != previous) {
        notifyListeners();
      }
      if (_phase == GoveeSpotPhase.autoEnded) {
        _stopPhaseTimer();
      }
    });
  }

  void _stopPhaseTimer() {
    _phaseTimer?.cancel();
    _phaseTimer = null;
  }

  _SpotSyncWindow? _buildCurrentSyncWindow() {
    final warmupStartedAt = _warmupStartedAt;
    if (warmupStartedAt == null) return null;
    final validStartedAt = warmupStartedAt.add(warmupDuration);
    final latestValidEndedAt = validStartedAt.add(maximumValidDuration);
    final now = _clock();
    final validEndedAt = now.isAfter(latestValidEndedAt)
        ? latestValidEndedAt
        : now;
    return _SpotSyncWindow(
      warmupStartedAt: warmupStartedAt,
      validStartedAt: validStartedAt,
      validEndedAt: validEndedAt,
    );
  }

  void _markSyncFailed(_SpotSyncWindow syncWindow) {
    _failedSyncWindow = syncWindow;
    _error =
        'Govee sync did not complete. Keep the H5051 powered on and near the app, reconnect Govee, then retry sync.';
    _phase = GoveeSpotPhase.readyForNext;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopPhaseTimer();
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

  static double _roundTwo(double value) => (value * 100).round() / 100;

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class _PendingSpotCapture {
  final int spotIndex;
  final DateTime warmupStartedAt;
  final DateTime validStartedAt;
  final DateTime validEndedAt;
  final List<GoveeSensorReading> readings;

  const _PendingSpotCapture({
    required this.spotIndex,
    required this.warmupStartedAt,
    required this.validStartedAt,
    required this.validEndedAt,
    required this.readings,
  });
}

class _SpotSyncWindow {
  final DateTime warmupStartedAt;
  final DateTime validStartedAt;
  final DateTime validEndedAt;

  const _SpotSyncWindow({
    required this.warmupStartedAt,
    required this.validStartedAt,
    required this.validEndedAt,
  });
}
