import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../services/ocr/egg_count_ocr_service.dart';
import '../../../services/photo/photo_service.dart';
import 'egg_count_capture_result.dart';
import 'ocr_camera_port.dart';

typedef EggCountAnalyzer = Future<EggCountOcrResult> Function(String imagePath);

class EggCountCaptureController extends ChangeNotifier {
  EggCountCaptureController({
    required this.title,
    required EggCountAnalyzer analyzeEggCount,
    required PhotoService photoService,
    required OcrCameraPort cameraPort,
    int initialCount = 0,
    List<String> initialPhotos = const [],
  }) : _analyzeEggCount = analyzeEggCount,
       _photoService = photoService,
       _cameraPort = cameraPort,
       _totalCount = initialCount,
       _photos = List<String>.from(initialPhotos);

  final String title;
  final EggCountAnalyzer _analyzeEggCount;
  final PhotoService _photoService;
  final OcrCameraPort _cameraPort;
  int _generation = 0;
  int _totalCount;
  List<String> _photos;
  String? _pendingPhotoPath;
  int? _pendingCount;
  EggCountOcrConfidence _pendingConfidence = EggCountOcrConfidence.none;
  String? _message;
  bool _isProcessing = false;
  bool _manualEntryActive = false;

  int get totalCount => _totalCount;
  List<String> get photos => List.unmodifiable(_photos);
  String? get pendingPhotoPath => _pendingPhotoPath;
  int? get pendingCount => _pendingCount;
  EggCountOcrConfidence get pendingConfidence => _pendingConfidence;
  String? get message => _message;
  bool get isProcessing => _isProcessing;
  bool get manualEntryActive => _manualEntryActive;
  bool get hasPending => _pendingPhotoPath != null && _pendingCount != null;

  Future<void> captureOnce() => _capture(useNativeCamera: false);

  Future<void> captureViaNativeCamera() => _capture(useNativeCamera: true);

  Future<void> _capture({required bool useNativeCamera}) async {
    if (_isProcessing) return;
    final generation = _bumpGeneration();
    _discardPendingPhoto();
    _pendingPhotoPath = null;
    _pendingCount = null;
    _pendingConfidence = EggCountOcrConfidence.none;
    _manualEntryActive = false;
    _message = null;
    _isProcessing = true;
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
      _isProcessing = false;
      _message = useNativeCamera
          ? 'No image captured.'
          : 'Inline camera is still starting. Try again or use Camera app.';
      notifyListeners();
      return;
    }

    final result = await _analyzeEggCount(savedPath);
    if (_isStale(generation)) {
      _deleteIfPresent(savedPath);
      return;
    }

    _isProcessing = false;
    _pendingPhotoPath = savedPath;
    _pendingCount = result.count;
    _pendingConfidence = result.confidence;
    _message = result.count == null
        ? result.hint ?? 'Could not count eggs. Enter this photo manually.'
        : null;
    if (_pendingCount == null) _manualEntryActive = true;
    notifyListeners();
  }

  Future<void> confirmPending() async {
    final count = _pendingCount;
    final photo = _pendingPhotoPath;
    if (count == null || photo == null) return;
    _totalCount += count;
    _photos = [..._photos, photo];
    _pendingPhotoPath = null;
    _pendingCount = null;
    _pendingConfidence = EggCountOcrConfidence.none;
    _manualEntryActive = false;
    _message = null;
    notifyListeners();
  }

  void rejectToManual() {
    if (_pendingPhotoPath == null) return;
    _pendingCount = null;
    _manualEntryActive = true;
    notifyListeners();
  }

  void beginManualEntry() {
    _manualEntryActive = true;
    notifyListeners();
  }

  Future<void> commitManualCount(int count) async {
    if (count < 0) return;
    final pendingPhoto = _pendingPhotoPath;
    if (pendingPhoto == null) {
      _totalCount = count;
    } else {
      _totalCount += count;
      _photos = [..._photos, pendingPhoto];
      _pendingPhotoPath = null;
      _pendingCount = null;
      _pendingConfidence = EggCountOcrConfidence.none;
    }
    _manualEntryActive = false;
    _message = null;
    notifyListeners();
  }

  void cancelManualEntry() {
    _manualEntryActive = false;
    notifyListeners();
  }

  void retake() {
    _bumpGeneration();
    _discardPendingPhoto();
    _pendingPhotoPath = null;
    _pendingCount = null;
    _pendingConfidence = EggCountOcrConfidence.none;
    _manualEntryActive = false;
    _message = null;
    notifyListeners();
  }

  void removePhoto(int index) {
    if (index < 0 || index >= _photos.length) return;
    final next = List<String>.from(_photos)..removeAt(index);
    _photos = next;
    notifyListeners();
  }

  EggCountCaptureResult result() {
    return EggCountCaptureResult(
      count: _totalCount,
      photos: List.unmodifiable(_photos),
    );
  }

  int _bumpGeneration() => ++_generation;
  bool _isStale(int generation) => generation != _generation;

  void _discardPendingPhoto() {
    final path = _pendingPhotoPath;
    if (path == null || path.isEmpty) return;
    if (_photos.contains(path)) return;
    _deleteIfPresent(path);
  }

  void _deleteIfPresent(String? path) {
    if (path == null || path.isEmpty) return;
    unawaited(_photoService.deletePhoto(path));
  }

  @override
  void dispose() {
    _bumpGeneration();
    _discardPendingPhoto();
    super.dispose();
  }
}
