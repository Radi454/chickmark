import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/temp_converter.dart';
import '../../../services/ocr/ocr_service.dart'
    show
        ThermoScanCropFrame,
        ThermoScanOcrResult,
        ThermoScanUnit,
        kThermoScanAutoScanInterval;
import '../../../services/photo/photo_service.dart';
import '../models/est_grid_data.dart';
import '../models/est_guided_capture_state.dart';
import 'ocr_camera_port.dart';
import 'ocr_capture_config.dart';
import 'ocr_capture_result.dart';

/// Recognises a ThermoScan reading in **Celsius** from an image path.
///
/// The seam that keeps the controller free of file I/O in tests. Production
/// wires this to `OcrService.recognizeThermoScanReadingCelsius`; tests pass a
/// pure function returning a fixed value.
typedef CelsiusRecognizer =
    Future<double?> Function(String imagePath, ThermoScanCropFrame? cropFrame);

typedef ThermoScanRecognizer =
    Future<ThermoScanOcrResult> Function(
      String imagePath,
      ThermoScanCropFrame? cropFrame,
    );

/// All capture logic for the reusable OCR flow, with no dependency on
/// `package:camera` (it talks to an [OcrCameraPort]) and no file I/O of its own
/// in tests (OCR comes through [CelsiusRecognizer]). The screen is a thin view
/// over this; unit tests drive it directly.
///
/// Model: [_capture] (an [EstGuidedCaptureState]) is the per-cell capture
/// sub-machine and the source of truth for readings/photos/active index. This
/// controller layers on free navigation (tap-select, prev/next), dirty
/// tracking, the auto-scan timer, generation-guarded async, and the
/// Celsius→display-unit conversion.
class OcrCaptureController extends ChangeNotifier {
  OcrCaptureController({
    required this.config,
    CelsiusRecognizer? recognizeCelsius,
    ThermoScanRecognizer? recognizeThermoScan,
    required PhotoService photoService,
    required OcrCameraPort cameraPort,
    Duration autoScanInterval = kThermoScanAutoScanInterval,
  }) : assert(recognizeCelsius != null || recognizeThermoScan != null),
       _recognizeThermoScan =
           recognizeThermoScan ??
           ((imagePath, cropFrame) async {
             final reading = await recognizeCelsius!(imagePath, cropFrame);
             return ThermoScanOcrResult(readingCelsius: reading);
           }),
       _photoService = photoService,
       _cameraPort = cameraPort,
       _autoScanInterval = autoScanInterval {
    _capture = EstGuidedCaptureState.initial(
      readings: config.initialReadings,
      photos: config.initialPhotos,
    );
  }

  final OcrCaptureConfig config;
  final ThermoScanRecognizer _recognizeThermoScan;
  final PhotoService _photoService;
  final OcrCameraPort _cameraPort;
  final Duration _autoScanInterval;

  late EstGuidedCaptureState _capture;
  final Set<String> _dirtyKeys = <String>{};
  ThermoScanOcrResult? _pendingOcrResult;
  bool _manualEntryActive = false;
  int _generation = 0;
  Timer? _autoScanTimer;

  // ── Read-only view for the screen ──────────────────────────────────────
  EstGuidedCaptureState get capture => _capture;
  Map<String, double> get readings => _capture.readings;
  Map<String, String> get photos => _capture.photos;
  int get activeIndex => _capture.stepIndex;
  int get totalCells => _capture.totalSteps;
  String get currentKey => _capture.currentKey;
  bool get manualEntryActive => _manualEntryActive;
  bool get isReadOnly => config.readOnly;
  bool get hasPrevious => _capture.stepIndex > 0;
  bool get hasNext => _capture.stepIndex < totalCells - 1;
  bool get allCellsFilled =>
      EstGridData.scanKeys.every(_capture.readings.containsKey);
  bool get hasUnitMismatch {
    final result = _pendingOcrResult;
    final selectedUnit = config.selectedUnit;
    return result?.readingCelsius != null &&
        result?.detectedUnit != null &&
        selectedUnit != null &&
        result!.detectedUnit != selectedUnit;
  }

  ThermoScanUnit? get detectedUnit => _pendingOcrResult?.detectedUnit;

  /// Reading currently staged for confirm (display unit), or null.
  double? get pendingValue => _capture.ocrValue;

  /// Photo path staged for the active cell (pending capture or saved evidence).
  String? get pendingPhotoPath =>
      _capture.capturedImagePath ?? _capture.photos[currentKey];

  String labelFor(String key) {
    final custom = config.targetLabelBuilder?.call(key);
    if (custom != null && custom.trim().isNotEmpty) return custom;
    final parts = key.split('_');
    if (parts.length != 2) return key;
    return '${EstGridData.label(parts[0])} - ${EstGridData.label(parts[1])}';
  }

  // ── Navigation ─────────────────────────────────────────────────────────
  /// Select a cell by index (tap-select / prev / next). Clamped, no wrap.
  /// Re-seats the capture sub-machine, discarding any unconfirmed in-flight
  /// photo for the cell being left.
  void selectCell(int index) {
    if (index < 0 || index >= totalCells) return;
    if (index == _capture.stepIndex && !_manualEntryActive) return;
    _bumpGeneration();
    _cancelTimer();
    _discardUnconfirmedPhoto();
    _pendingOcrResult = null;
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

  void previous() => selectCell(_capture.stepIndex - 1);
  void next() => selectCell(_capture.stepIndex + 1);

  // ── Auto-scan ──────────────────────────────────────────────────────────
  void startAutoScan() {
    if (config.readOnly) return;
    if (!_cameraPort.isCameraReady) return;
    if (_capture.isCurrentPointConfirmed) return;
    if (_capture.capturedImagePath != null) return;
    _bumpGeneration();
    _manualEntryActive = false;
    _capture = _capture.startAutoScan();
    notifyListeners();
    if (_capture.isAutoScanning) _ensureTimer();
  }

  void stopAutoScan({String? message}) {
    _bumpGeneration();
    _cancelTimer();
    _capture = _capture.stopAutoScan(message: message);
    notifyListeners();
  }

  /// One auto-scan tick. Called by the timer in production; called directly in
  /// tests. Guarded so a late OCR result after navigation/dispose is a no-op.
  Future<void> runAutoScanAttempt() async {
    if (!_capture.canStartOcrAttempt) return;
    final generation = _generation;
    _capture = _capture.autoScanAttemptStarted();
    notifyListeners();

    final sourcePath = await _cameraPort.takePictureForAutoScan();
    if (_isStale(generation)) {
      _deleteIfPresent(sourcePath);
      return;
    }
    if (sourcePath == null) {
      _cancelTimer();
      _capture = _capture.stopAutoScan(
        message: 'Auto scan stopped. Use Capture or Camera app.',
      );
      notifyListeners();
      return;
    }

    final result = await _recognizeThermoScan(
      sourcePath,
      _cameraPort.ocrCropFrame,
    );
    if (_isStale(generation)) {
      _deleteIfPresent(sourcePath);
      return;
    }
    if (result.readingCelsius == null) {
      _deleteIfPresent(sourcePath);
      _capture = _capture.autoScanAttemptResolved(
        photoPath: sourcePath,
        ocrValue: null,
      );
      notifyListeners();
      return;
    }

    _cancelTimer();
    _pendingOcrResult = result;
    if (hasUnitMismatch) {
      _capture = _capture.unitMismatchDetected(
        photoPath: sourcePath,
        autoScanReview: true,
      );
      notifyListeners();
      return;
    }
    _capture = _capture.autoScanAttemptResolved(
      photoPath: sourcePath,
      ocrValue: _toDisplay(result.readingCelsius!),
    );
    notifyListeners();
  }

  // ── Single capture ─────────────────────────────────────────────────────
  Future<void> captureOnce() => _capture0(useNativeCamera: false);

  Future<void> captureViaNativeCamera() => _capture0(useNativeCamera: true);

  Future<void> _capture0({required bool useNativeCamera}) async {
    if (config.readOnly) return;
    if (_capture.isProcessing || _capture.isOcrProcessing) return;
    final generation = _bumpGeneration();
    _cancelTimer();
    _discardUnconfirmedPhoto();
    _pendingOcrResult = null;
    _manualEntryActive = false;
    _capture = _capture.captureStarted();
    notifyListeners();

    String? savedPath;
    if (useNativeCamera) {
      savedPath = await _photoService.pickPhoto(fromCamera: true);
    } else {
      final sourcePath = await _cameraPort.takePicture();
      if (sourcePath != null) {
        savedPath = await _photoService.saveCapturedPhotoPath(sourcePath);
        _deleteIfPresent(sourcePath);
      } else if (_cameraPort.hasCameraError) {
        savedPath = await _photoService.pickPhoto(fromCamera: true);
      }
    }

    if (_isStale(generation)) {
      _deleteIfPresent(savedPath);
      return;
    }
    if (savedPath == null) {
      _capture = _capture.captureFailed(
        useNativeCamera
            ? 'No image captured.'
            : 'Inline camera is still starting. Try again or use Camera app.',
      );
      notifyListeners();
      return;
    }

    final result = await _recognizeThermoScan(
      savedPath,
      _cameraPort.ocrCropFrame,
    );
    if (_isStale(generation)) {
      _deleteIfPresent(savedPath);
      return;
    }
    if (result.readingCelsius == null) {
      // Reading unreadable — drop the saved frame and let the user retry or
      // switch to manual entry. (Rejecting a *successful* read keeps its photo.)
      _deleteIfPresent(savedPath);
      _capture = _capture.captureResolved(photoPath: savedPath, ocrValue: null);
      notifyListeners();
      return;
    }

    _pendingOcrResult = result;
    if (hasUnitMismatch) {
      _capture = _capture.unitMismatchDetected(
        photoPath: savedPath,
        autoScanReview: false,
      );
      notifyListeners();
      return;
    }
    _capture = _capture.captureResolved(
      photoPath: savedPath,
      ocrValue: _toDisplay(result.readingCelsius!),
    );
    notifyListeners();
  }

  // ── Confirm / reject / manual ──────────────────────────────────────────
  /// Save the staged reading+photo to the active cell, then auto-advance to the
  /// next OPEN cell (stay put if none remain).
  Future<void> confirm() async {
    if (config.readOnly) return;
    if (!_capture.canConfirm) return;
    if (_capture.isCurrentPointConfirmed) {
      _capture = _capture.captureFailed(
        'This point is already saved. Retake to replace it.',
      );
      notifyListeners();
      return;
    }

    final generation = _bumpGeneration();
    _cancelTimer();
    final key = _capture.currentKey;
    var evidence = _capture.capturedImagePath!;

    // Auto-scan review photos are temp files until confirmed.
    if (_capture.isAutoScanReview) {
      final saved = await _photoService.saveCapturedPhotoPath(evidence);
      if (_isStale(generation)) {
        _deleteIfPresent(evidence);
        _deleteIfPresent(saved);
        return;
      }
      if (saved == null) {
        _capture = _capture.stopAutoScan(
          message: 'Could not save evidence photo. Try again.',
        );
        notifyListeners();
        return;
      }
      _deleteIfPresent(evidence);
      evidence = saved;
    }

    _dirtyKeys.add(key);
    _manualEntryActive = false;
    _capture = _capture.confirm(photoPath: evidence);
    _stayIfNoOpenCell(key);
    notifyListeners();
  }

  /// Reject a staged OCR reading and switch the active cell to manual entry,
  /// keeping the captured frame as pending evidence (committed on save).
  void rejectToManual() {
    if (config.readOnly) return;
    _bumpGeneration();
    _cancelTimer();
    _manualEntryActive = true;
    _pendingOcrResult = null;
    _capture = _capture.valueEdited(null); // clear staged value, keep photo
    notifyListeners();
  }

  /// Enter manual entry for the active cell without a prior capture.
  void beginManualEntry() {
    if (config.readOnly) return;
    _bumpGeneration();
    _cancelTimer();
    _manualEntryActive = true;
    _pendingOcrResult = null;
    notifyListeners();
  }

  /// Commit a manually typed [value] (display unit) to the active cell. Saves
  /// any pending captured frame as evidence. Manual entry does NOT auto-advance.
  Future<void> commitManualEntry(double value) async {
    if (config.readOnly) return;
    final generation = _bumpGeneration();
    _cancelTimer();
    final key = _capture.currentKey;

    String? evidence = _capture.photos[key];
    final pending = _capture.capturedImagePath;
    if (pending != null) {
      if (_capture.isAutoScanReview) {
        // Auto-scan frame is still a temp file → persist it now.
        final saved = await _photoService.saveCapturedPhotoPath(pending);
        if (_isStale(generation)) {
          _deleteIfPresent(pending);
          _deleteIfPresent(saved);
          return;
        }
        _deleteIfPresent(pending);
        if (saved != null) evidence = saved;
      } else {
        // Single-capture frame was already saved permanently — reuse as-is.
        evidence = pending;
      }
    }

    final nextReadings = Map<String, double>.from(_capture.readings)
      ..[key] = value;
    final nextPhotos = Map<String, String>.from(_capture.photos);
    if (evidence != null) nextPhotos[key] = evidence;
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
    notifyListeners();
  }

  /// Leave manual entry without saving (back to scanning/review for the cell).
  void cancelManualEntry() {
    if (!_manualEntryActive) return;
    _manualEntryActive = false;
    notifyListeners();
  }

  void useDetectedReading() {
    final celsius = _pendingOcrResult?.readingCelsius;
    if (!hasUnitMismatch || celsius == null) return;
    _pendingOcrResult = null;
    _capture = _capture.valueEdited(_toDisplay(celsius));
    notifyListeners();
  }

  /// Discard the staged capture and re-scan the active cell.
  void retake() {
    if (config.readOnly) return;
    _bumpGeneration();
    _cancelTimer();
    _discardUnconfirmedPhoto();
    _pendingOcrResult = null;
    _manualEntryActive = false;
    _capture = _capture.retake();
    notifyListeners();
  }

  // ── Result ─────────────────────────────────────────────────────────────
  /// Dirty-only readings+photos to hand back to the caller.
  OcrCaptureResult result() {
    final readings = <String, double>{};
    final photos = <String, String>{};
    for (final key in _dirtyKeys) {
      final value = _capture.readings[key];
      if (value != null) readings[key] = value;
      final photo = _capture.photos[key];
      if (photo != null && photo.isNotEmpty) photos[key] = photo;
    }
    return OcrCaptureResult(readings: readings, photos: photos);
  }

  // ── Internals ──────────────────────────────────────────────────────────
  double _toDisplay(double celsius) {
    final selectedUnit = config.selectedUnit;
    if (selectedUnit == ThermoScanUnit.fahrenheit) {
      return TempConverter.toFahrenheit(celsius);
    }
    if (selectedUnit == ThermoScanUnit.celsius) return celsius;
    return config.convertCelsiusToFahrenheit
        ? TempConverter.toFahrenheit(celsius)
        : celsius;
  }

  /// After a confirm-advance landed on a filled cell with nothing open, return
  /// to the just-confirmed cell so we never imply more work remains.
  void _stayIfNoOpenCell(String confirmedKey) {
    final hasOpen = EstGridData.scanKeys.any(
      (k) => !_capture.readings.containsKey(k),
    );
    if (hasOpen) return;
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

  void _ensureTimer() {
    if (_autoScanTimer?.isActive ?? false) return;
    _autoScanTimer = Timer.periodic(
      _autoScanInterval,
      (_) => runAutoScanAttempt(),
    );
  }

  void _cancelTimer() {
    _autoScanTimer?.cancel();
    _autoScanTimer = null;
  }

  /// Delete the active cell's pending capture if it isn't confirmed evidence.
  void _discardUnconfirmedPhoto() {
    final path = _capture.capturedImagePath;
    if (path == null || path.isEmpty) return;
    if (_capture.isCurrentPointConfirmed) return; // belongs to the caller now
    if (_capture.photos[_capture.currentKey] == path) return; // saved evidence
    _deleteIfPresent(path);
  }

  void _deleteIfPresent(String? path) {
    if (path == null || path.isEmpty) return;
    unawaited(_photoService.deletePhoto(path));
  }

  @override
  void dispose() {
    _bumpGeneration();
    _cancelTimer();
    _discardUnconfirmedPhoto();
    super.dispose();
  }
}
