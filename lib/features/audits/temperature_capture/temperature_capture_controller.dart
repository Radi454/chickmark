import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../services/photo/photo_service.dart';
import '../models/est_grid_data.dart';
import '../models/est_guided_capture_state.dart';
import 'temperature_camera_port.dart';
import 'temperature_capture_config.dart';
import 'temperature_capture_result.dart';

/// Capture logic for the reusable temperature grid flow.
///
/// The flow is intentionally manual: stage a photo for the active grid point,
/// let the auditor type the reading, save it, and advance to the next open
/// point. The controller owns navigation, dirty tracking, async generation
/// guards, and temporary-photo cleanup; station screens own persistence.
class TemperatureCaptureController extends ChangeNotifier {
  TemperatureCaptureController({
    required this.config,
    required PhotoService photoService,
    required TemperatureCameraPort cameraPort,
  }) : _photoService = photoService,
       _cameraPort = cameraPort {
    final initial = EstGuidedCaptureState.initial(
      readings: config.initialReadings,
      photos: config.initialPhotos,
    );
    final initialIndex = config.initialKey == null
        ? -1
        : EstGridData.scanKeys.indexOf(config.initialKey!);
    _capture = initialIndex < 0
        ? initial
        : EstGuidedCaptureState(
            stepIndex: initialIndex,
            readings: initial.readings,
            photos: initial.photos,
          );
    _manualEntryActive =
        config.initialKey != null &&
        (config.initialReadings.containsKey(config.initialKey) ||
            config.initialPhotos.containsKey(config.initialKey));
  }

  final TemperatureCaptureConfig config;
  final PhotoService _photoService;
  final TemperatureCameraPort _cameraPort;

  late EstGuidedCaptureState _capture;
  final Set<String> _dirtyKeys = <String>{};
  bool _manualEntryActive = false;
  int _generation = 0;

  EstGuidedCaptureState get capture => _capture;
  Map<String, double> get readings => _capture.readings;
  Map<String, String> get photos => _capture.photos;
  int get activeIndex => _capture.stepIndex;
  int get totalCells => _capture.totalSteps;
  String get currentKey => _capture.currentKey;
  bool get manualEntryActive => _manualEntryActive;
  bool get isReadOnly => config.readOnly;
  bool get allCellsFilled =>
      EstGridData.scanKeys.every(_capture.readings.containsKey);

  double? get pendingValue => _capture.pendingValue;

  /// Photo path staged for the active cell, or saved evidence for that cell.
  String? get pendingPhotoPath =>
      _capture.capturedImagePath ?? _capture.photos[currentKey];

  String labelFor(String key) {
    final custom = config.targetLabelBuilder?.call(key);
    if (custom != null && custom.trim().isNotEmpty) return custom;
    final parts = key.split('_');
    if (parts.length != 2) return key;
    return '${EstGridData.label(parts[0])} - ${EstGridData.label(parts[1])}';
  }

  void selectCell(int index) {
    if (index < 0 || index >= totalCells) return;
    if (index == _capture.stepIndex && !_manualEntryActive) return;
    _bumpGeneration();
    _discardUnconfirmedPhoto();
    _manualEntryActive = false;
    _capture = EstGuidedCaptureState(
      stepIndex: index,
      readings: _capture.readings,
      photos: _capture.photos,
    );
    notifyListeners();
  }

  void selectKey(String key) {
    final index = EstGridData.scanKeys.indexOf(key);
    if (index >= 0) selectCell(index);
  }

  Future<void> captureOnce() async {
    if (config.readOnly) return;
    if (_capture.isProcessing) return;
    final generation = _bumpGeneration();
    _discardUnconfirmedPhoto();
    _manualEntryActive = false;
    _capture = _capture.captureStarted();
    notifyListeners();

    String? savedPath;
    final sourcePath = await _cameraPort.takePicture();
    if (sourcePath != null) {
      savedPath = await _photoService.saveCapturedPhotoPath(sourcePath);
      _deleteIfPresent(sourcePath);
    } else if (_cameraPort.hasCameraError) {
      savedPath = await _photoService.pickPhoto(fromCamera: true);
    }

    if (_isStale(generation)) {
      _deleteIfPresent(savedPath);
      return;
    }
    if (savedPath == null) {
      _capture = _capture.captureFailed(
        'Inline camera is still starting. Try again.',
      );
      notifyListeners();
      return;
    }

    _manualEntryActive = true;
    _capture = _capture.captureResolved(photoPath: savedPath);
    notifyListeners();
  }

  void beginManualEntry() {
    if (config.readOnly) return;
    _bumpGeneration();
    _manualEntryActive = true;
    notifyListeners();
  }

  Future<void> commitManualEntry(double value) async {
    if (config.readOnly) return;
    final key = _capture.currentKey;
    final evidence = _capture.capturedImagePath ?? _capture.photos[key];
    final nextReadings = Map<String, double>.from(_capture.readings)
      ..[key] = value;
    final nextPhotos = Map<String, String>.from(_capture.photos);
    if (evidence != null && evidence.isNotEmpty) {
      nextPhotos[key] = evidence;
    }
    final nextRetaken = Set<String>.from(_capture.retakenKeys)..remove(key);

    _dirtyKeys.add(key);
    _manualEntryActive = false;
    _capture = EstGuidedCaptureState(
      stepIndex: _capture.stepIndex,
      readings: Map.unmodifiable(nextReadings),
      photos: Map.unmodifiable(nextPhotos),
      lastConfirmedKey: key,
      retakenKeys: Set.unmodifiable(nextRetaken),
    );
    _advanceAfterSave(key);
    notifyListeners();
  }

  void cancelManualEntry() {
    if (!_manualEntryActive) return;
    _manualEntryActive = false;
    notifyListeners();
  }

  Future<void> confirm() async {
    final value = pendingValue;
    if (value == null) return;
    await commitManualEntry(value);
  }

  void retake() {
    if (config.readOnly) return;
    _bumpGeneration();
    _discardUnconfirmedPhoto();
    _manualEntryActive = false;
    _capture = _capture.retake();
    notifyListeners();
  }

  TemperatureCaptureResult result() {
    final readings = <String, double>{};
    final photos = <String, String>{};
    for (final key in _dirtyKeys) {
      final value = _capture.readings[key];
      if (value != null) readings[key] = value;
      final photo = _capture.photos[key];
      if (photo != null && photo.isNotEmpty) photos[key] = photo;
    }
    return TemperatureCaptureResult(readings: readings, photos: photos);
  }

  void _advanceAfterSave(String confirmedKey) {
    final currentIndex = EstGridData.scanKeys.indexOf(confirmedKey);
    if (currentIndex < 0) return;
    for (var i = currentIndex + 1; i < EstGridData.scanKeys.length; i++) {
      final key = EstGridData.scanKeys[i];
      if (!_capture.readings.containsKey(key)) {
        _capture = EstGuidedCaptureState(
          stepIndex: i,
          readings: _capture.readings,
          photos: _capture.photos,
        );
        return;
      }
    }
    final index = EstGridData.scanKeys.indexOf(confirmedKey);
    if (index < 0) return;
    _capture = EstGuidedCaptureState(
      stepIndex: index,
      readings: _capture.readings,
      photos: _capture.photos,
    );
  }

  int _bumpGeneration() => ++_generation;
  bool _isStale(int generation) => generation != _generation;

  void _discardUnconfirmedPhoto() {
    final path = _capture.capturedImagePath;
    if (path == null || path.isEmpty) return;
    if (_capture.isCurrentPointConfirmed) return;
    if (_capture.photos[_capture.currentKey] == path) return;
    _deleteIfPresent(path);
  }

  void _deleteIfPresent(String? path) {
    if (path == null || path.isEmpty) return;
    unawaited(_photoService.deletePhoto(path));
  }

  @override
  void dispose() {
    _bumpGeneration();
    _discardUnconfirmedPhoto();
    super.dispose();
  }
}
