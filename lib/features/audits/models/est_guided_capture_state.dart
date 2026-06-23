import 'est_grid_data.dart';

class EstGuidedCaptureState {
  const EstGuidedCaptureState({
    required this.stepIndex,
    required this.readings,
    required this.photos,
    this.capturedImagePath,
    this.pendingValue,
    this.isProcessing = false,
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
  final double? pendingValue;
  final bool isProcessing;
  final String? errorMessage;
  final String? lastConfirmedKey;
  final Set<String> retakenKeys;

  String get currentKey => EstGridData.scanKeys[stepIndex];
  int get currentStep => stepIndex + 1;
  int get totalSteps => EstGridData.scanKeys.length;
  bool get canConfirm => pendingValue != null;
  bool get isLastStep => stepIndex >= EstGridData.scanKeys.length - 1;
  bool get isCurrentPointConfirmed =>
      readings.containsKey(currentKey) && !retakenKeys.contains(currentKey);

  List<Map<String, Object>> get structuredReadings =>
      EstGridData.toStructuredReadings(readings);

  EstGuidedCaptureState captureStarted() => _copyWith(
    capturedImagePath: null,
    pendingValue: null,
    isProcessing: true,
    errorMessage: null,
    lastConfirmedKey: null,
  );

  EstGuidedCaptureState captureResolved({
    required String photoPath,
    String? hint,
  }) => _copyWith(
    capturedImagePath: photoPath,
    pendingValue: null,
    isProcessing: false,
    errorMessage: hint ?? 'Photo captured. Enter the reading.',
  );

  EstGuidedCaptureState captureFailed(String message) => _copyWith(
    isProcessing: false,
    errorMessage: message,
    lastConfirmedKey: null,
  );

  EstGuidedCaptureState valueEdited(double? value) => _copyWith(
    pendingValue: value,
    errorMessage: value == null ? errorMessage : 'Confirm the typed reading.',
  );

  EstGuidedCaptureState retake() => _copyWith(
    capturedImagePath: null,
    pendingValue: null,
    isProcessing: false,
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
      ..[currentKey] = pendingValue!;
    final nextPhotos = Map<String, String>.from(photos);
    final evidencePath = photoPath ?? capturedImagePath;
    if (evidencePath != null && evidencePath.isNotEmpty) {
      nextPhotos[currentKey] = evidencePath;
    }
    final nextRetakenKeys = Set<String>.from(retakenKeys)..remove(currentKey);

    return _advance(
      readings: Map.unmodifiable(nextReadings),
      photos: Map.unmodifiable(nextPhotos),
      lastConfirmedKey: currentKey,
      retakenKeys: Set.unmodifiable(nextRetakenKeys),
    );
  }

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
    Object? pendingValue = _sentinel,
    bool? isProcessing,
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
      pendingValue: identical(pendingValue, _sentinel)
          ? this.pendingValue
          : pendingValue as double?,
      isProcessing: isProcessing ?? this.isProcessing,
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
