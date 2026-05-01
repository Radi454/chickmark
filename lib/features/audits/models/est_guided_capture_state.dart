import 'est_grid_data.dart';

class EstGuidedCaptureState {
  const EstGuidedCaptureState({
    required this.stepIndex,
    required this.readings,
    required this.photos,
    this.capturedImagePath,
    this.ocrValue,
    this.isProcessing = false,
    this.isAutoScanning = false,
    this.isOcrProcessing = false,
    this.isAutoScanReview = false,
    this.errorMessage,
    this.lastConfirmedKey,
    this.retakenKeys = const {},
  });

  factory EstGuidedCaptureState.initial({
    Map<String, double>? readings,
    Map<String, String>? photos,
  }) {
    final safeReadings = Map<String, double>.unmodifiable(readings ?? const {});
    final firstOpenIndex = EstGridData.scanKeys.indexWhere(
      (key) => !safeReadings.containsKey(key),
    );

    return EstGuidedCaptureState(
      stepIndex: firstOpenIndex == -1 ? 0 : firstOpenIndex,
      readings: safeReadings,
      photos: Map.unmodifiable(photos ?? const {}),
    );
  }

  final int stepIndex;
  final Map<String, double> readings;
  final Map<String, String> photos;
  final String? capturedImagePath;
  final double? ocrValue;
  final bool isProcessing;
  final bool isAutoScanning;
  final bool isOcrProcessing;
  final bool isAutoScanReview;
  final String? errorMessage;
  final String? lastConfirmedKey;
  final Set<String> retakenKeys;

  String get currentKey => EstGridData.scanKeys[stepIndex];
  int get currentStep => stepIndex + 1;
  int get totalSteps => EstGridData.scanKeys.length;
  bool get canConfirm => capturedImagePath != null && ocrValue != null;
  bool get isLastStep => stepIndex >= EstGridData.scanKeys.length - 1;
  bool get isCurrentPointConfirmed =>
      readings.containsKey(currentKey) && !retakenKeys.contains(currentKey);
  bool get canStartOcrAttempt =>
      isAutoScanning &&
      !isOcrProcessing &&
      !isProcessing &&
      capturedImagePath == null;

  List<Map<String, Object>> get structuredReadings =>
      EstGridData.toStructuredReadings(readings);

  EstGuidedCaptureState captureStarted() => _copyWith(
    capturedImagePath: null,
    ocrValue: null,
    isProcessing: true,
    isAutoScanning: false,
    isOcrProcessing: false,
    isAutoScanReview: false,
    errorMessage: null,
    lastConfirmedKey: null,
  );

  EstGuidedCaptureState captureResolved({
    required String photoPath,
    required double? ocrValue,
    String? hint,
  }) {
    if (ocrValue == null) {
      return _copyWith(
        capturedImagePath: null,
        ocrValue: null,
        isProcessing: false,
        isAutoScanning: false,
        isOcrProcessing: false,
        isAutoScanReview: false,
        errorMessage: hint ?? 'No reading found. Camera refreshed. Try again.',
      );
    }

    return _copyWith(
      capturedImagePath: photoPath,
      ocrValue: ocrValue,
      isProcessing: false,
      isAutoScanning: false,
      isOcrProcessing: false,
      isAutoScanReview: false,
      errorMessage: 'Confirm the detected reading.',
    );
  }

  EstGuidedCaptureState captureFailed(String message) => _copyWith(
    isProcessing: false,
    isAutoScanning: false,
    isOcrProcessing: false,
    isAutoScanReview: false,
    errorMessage: message,
    lastConfirmedKey: null,
  );

  EstGuidedCaptureState valueEdited(double? value) => _copyWith(
    ocrValue: value,
    errorMessage: value == null ? errorMessage : 'Confirm the edited reading.',
  );

  EstGuidedCaptureState retake() => _copyWith(
    capturedImagePath: null,
    ocrValue: null,
    isProcessing: false,
    isAutoScanning: false,
    isOcrProcessing: false,
    isAutoScanReview: false,
    errorMessage: null,
    lastConfirmedKey: null,
    retakenKeys: Set<String>.unmodifiable({
      ...retakenKeys,
      if (readings.containsKey(currentKey)) currentKey,
    }),
  );

  EstGuidedCaptureState skip() =>
      _advance(readings: readings, photos: photos, lastConfirmedKey: null);

  EstGuidedCaptureState confirm({String? photoPath}) {
    if (!canConfirm) return this;
    if (isCurrentPointConfirmed) {
      return captureFailed(
        'This EST point is already saved. Retake to replace it.',
      );
    }

    final nextReadings = Map<String, double>.from(readings)
      ..[currentKey] = ocrValue!;
    final nextPhotos = Map<String, String>.from(photos)
      ..[currentKey] = photoPath ?? capturedImagePath!;
    final nextRetakenKeys = Set<String>.from(retakenKeys)..remove(currentKey);

    return _advance(
      readings: Map.unmodifiable(nextReadings),
      photos: Map.unmodifiable(nextPhotos),
      lastConfirmedKey: currentKey,
      retakenKeys: Set.unmodifiable(nextRetakenKeys),
    );
  }

  EstGuidedCaptureState startAutoScan() {
    if (isAutoScanning) return this;
    if (isCurrentPointConfirmed) {
      return _copyWith(
        isAutoScanning: false,
        isOcrProcessing: false,
        isAutoScanReview: false,
        errorMessage: 'This EST point is already saved. Retake to replace it.',
      );
    }
    if (capturedImagePath != null) {
      return _copyWith(
        errorMessage: 'Confirm, edit, or retake the detected reading first.',
      );
    }

    return _copyWith(
      isAutoScanning: true,
      isOcrProcessing: false,
      isAutoScanReview: false,
      isProcessing: false,
      errorMessage: 'Looking for reading...',
      lastConfirmedKey: null,
    );
  }

  EstGuidedCaptureState stopAutoScan({String? message}) => _copyWith(
    isAutoScanning: false,
    isOcrProcessing: false,
    errorMessage: message,
  );

  EstGuidedCaptureState autoScanAttemptStarted() {
    if (!canStartOcrAttempt) return this;
    return _copyWith(
      isOcrProcessing: true,
      errorMessage: 'Reading ThermoScan screen...',
      lastConfirmedKey: null,
    );
  }

  EstGuidedCaptureState autoScanAttemptResolved({
    required String photoPath,
    required double? ocrValue,
    String? hint,
  }) {
    if (ocrValue == null) {
      return _copyWith(
        capturedImagePath: null,
        ocrValue: null,
        isAutoScanning: true,
        isOcrProcessing: false,
        isAutoScanReview: false,
        errorMessage: hint ?? 'Looking for reading...',
      );
    }

    return _copyWith(
      capturedImagePath: photoPath,
      ocrValue: ocrValue,
      isAutoScanning: false,
      isOcrProcessing: false,
      isAutoScanReview: true,
      errorMessage: 'Reading detected. Confirm or try again.',
    );
  }

  EstGuidedCaptureState rejectAutoScanReading() => _copyWith(
    capturedImagePath: null,
    ocrValue: null,
    isAutoScanning: true,
    isOcrProcessing: false,
    isAutoScanReview: false,
    errorMessage: 'Looking for reading...',
  );

  EstGuidedCaptureState _advance({
    required Map<String, double> readings,
    required Map<String, String> photos,
    required String? lastConfirmedKey,
    Set<String>? retakenKeys,
  }) {
    final nextIndex = _nextOpenIndex(
      fromIndex: stepIndex,
      readings: readings,
      retakenKeys: retakenKeys ?? this.retakenKeys,
    );
    return EstGuidedCaptureState(
      stepIndex: nextIndex,
      readings: Map.unmodifiable(readings),
      photos: Map.unmodifiable(photos),
      lastConfirmedKey: lastConfirmedKey,
      retakenKeys: Set.unmodifiable(retakenKeys ?? this.retakenKeys),
    );
  }

  int _nextOpenIndex({
    required int fromIndex,
    required Map<String, double> readings,
    required Set<String> retakenKeys,
  }) {
    for (var i = fromIndex + 1; i < EstGridData.scanKeys.length; i++) {
      final key = EstGridData.scanKeys[i];
      if (!readings.containsKey(key) || retakenKeys.contains(key)) return i;
    }
    return isLastStep ? stepIndex : stepIndex + 1;
  }

  EstGuidedCaptureState _copyWith({
    int? stepIndex,
    Map<String, double>? readings,
    Map<String, String>? photos,
    Object? capturedImagePath = _sentinel,
    Object? ocrValue = _sentinel,
    bool? isProcessing,
    bool? isAutoScanning,
    bool? isOcrProcessing,
    bool? isAutoScanReview,
    Object? errorMessage = _sentinel,
    Object? lastConfirmedKey = _sentinel,
    Set<String>? retakenKeys,
  }) {
    return EstGuidedCaptureState(
      stepIndex: stepIndex ?? this.stepIndex,
      readings: Map.unmodifiable(readings ?? this.readings),
      photos: Map.unmodifiable(photos ?? this.photos),
      capturedImagePath: identical(capturedImagePath, _sentinel)
          ? this.capturedImagePath
          : capturedImagePath as String?,
      ocrValue: identical(ocrValue, _sentinel)
          ? this.ocrValue
          : ocrValue as double?,
      isProcessing: isProcessing ?? this.isProcessing,
      isAutoScanning: isAutoScanning ?? this.isAutoScanning,
      isOcrProcessing: isOcrProcessing ?? this.isOcrProcessing,
      isAutoScanReview: isAutoScanReview ?? this.isAutoScanReview,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
      lastConfirmedKey: identical(lastConfirmedKey, _sentinel)
          ? this.lastConfirmedKey
          : lastConfirmedKey as String?,
      retakenKeys: Set.unmodifiable(retakenKeys ?? this.retakenKeys),
    );
  }
}

const Object _sentinel = Object();
