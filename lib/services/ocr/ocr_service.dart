import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;

const bool kThermoScanQualityChecksEnabled = true;
const double kThermoScanFrameWidth = 190;
const double kThermoScanFrameHeight = 110;
const double kThermoScanFramePadding = 0.14;
const double kThermoScanBlurThreshold = 1.0;
const double kThermoScanBrightnessThreshold = 34;
const double kThermoScanMinimumDigitSize = 0.14;
const Duration kThermoScanOcrTimeout = Duration(milliseconds: 1800);
const Duration kThermoScanHintThrottle = Duration(milliseconds: 1300);
const int kThermoScanMaxConsecutiveAutoScanFailures = 12;

enum ThermoScanQualityRejection { blur, lighting, distance }

class ThermoScanCropFrame {
  const ThermoScanCropFrame({
    required this.previewWidth,
    required this.previewHeight,
    this.frameWidth = kThermoScanFrameWidth,
    this.frameHeight = kThermoScanFrameHeight,
    this.devicePixelRatio = 1,
  });

  final double previewWidth;
  final double previewHeight;
  final double frameWidth;
  final double frameHeight;
  final double devicePixelRatio;

  Map<String, double> toJson() => {
    'previewWidth': previewWidth,
    'previewHeight': previewHeight,
    'frameWidth': frameWidth,
    'frameHeight': frameHeight,
    'devicePixelRatio': devicePixelRatio,
  };
}

class ThermoScanPreprocessResult {
  const ThermoScanPreprocessResult({
    required this.prepared,
    required this.shouldRunOcr,
    this.outputPath,
    this.rejectionReason,
    this.hint,
    this.qualityChecksRan = false,
    this.qualityChecksFailed = false,
  });

  final bool prepared;
  final bool shouldRunOcr;
  final String? outputPath;
  final ThermoScanQualityRejection? rejectionReason;
  final String? hint;
  final bool qualityChecksRan;
  final bool qualityChecksFailed;

  factory ThermoScanPreprocessResult.fromJson(Map<String, Object?> json) {
    final reasonName = json['rejectionReason'] as String?;
    return ThermoScanPreprocessResult(
      prepared: json['prepared'] == true,
      shouldRunOcr: json['shouldRunOcr'] == true,
      outputPath: json['outputPath'] as String?,
      rejectionReason: reasonName == null
          ? null
          : ThermoScanQualityRejection.values.firstWhere(
              (value) => value.name == reasonName,
            ),
      hint: json['hint'] as String?,
      qualityChecksRan: json['qualityChecksRan'] == true,
      qualityChecksFailed: json['qualityChecksFailed'] == true,
    );
  }
}

class ThermoScanOcrResult {
  const ThermoScanOcrResult({
    this.readingCelsius,
    this.hint,
    this.rawText,
    this.rejectionReason,
    this.didRunOcr = false,
    this.timedOut = false,
    this.busy = false,
    this.scanDuration = Duration.zero,
  });

  final double? readingCelsius;
  final String? hint;
  final String? rawText;
  final ThermoScanQualityRejection? rejectionReason;
  final bool didRunOcr;
  final bool timedOut;
  final bool busy;
  final Duration scanDuration;
}

class OcrService {
  bool _isAvailable = false;
  bool _recognitionInFlight = false;

  bool get isAvailable => _isAvailable;

  OcrService() {
    _checkCameraAvailability();
  }

  Future<void> _checkCameraAvailability() async {
    try {
      _isAvailable = !kIsWeb;
    } catch (e) {
      _isAvailable = false;
      if (kDebugMode) {
        debugPrint('OCR availability check failed: $e');
      }
    }
  }

  Future<String?> recognizeText(String imagePath) async {
    if (!isAvailable) {
      return null;
    }
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      try {
        final recognizedText = await textRecognizer.processImage(inputImage);
        return recognizedText.text;
      } finally {
        await textRecognizer.close();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('OCR text recognition failed for $imagePath: $e');
      }
      return null;
    }
  }

  Future<double?> recognizeThermoScanReadingCelsius(String imagePath) async {
    final result = await analyzeThermoScanReadingCelsius(imagePath);
    return result.readingCelsius;
  }

  Future<ThermoScanOcrResult> analyzeThermoScanReadingCelsius(
    String imagePath, {
    ThermoScanCropFrame? cropFrame,
    bool enableQualityChecks = kThermoScanQualityChecksEnabled,
    Duration ocrTimeout = kThermoScanOcrTimeout,
  }) async {
    final stopwatch = Stopwatch()..start();
    if (_recognitionInFlight) {
      return ThermoScanOcrResult(busy: true, scanDuration: stopwatch.elapsed);
    }
    String? preparedPath;
    var deferPreparedDeletion = false;
    try {
      final prepared = await _prepareThermoScanImageForOcr(
        imagePath,
        cropFrame: cropFrame,
        enableQualityChecks: enableQualityChecks,
      );
      preparedPath = prepared.outputPath;
      if (!prepared.shouldRunOcr) {
        _debugLog(
          quality: prepared.rejectionReason?.name ?? 'skipped',
          rejectedReason: prepared.rejectionReason?.name,
          duration: stopwatch.elapsed,
        );
        return ThermoScanOcrResult(
          hint: prepared.hint,
          rejectionReason: prepared.rejectionReason,
          scanDuration: stopwatch.elapsed,
        );
      }

      if (_recognitionInFlight) {
        return ThermoScanOcrResult(busy: true, scanDuration: stopwatch.elapsed);
      }

      _recognitionInFlight = true;
      String? text;
      final pathForDeferredDeletion = preparedPath;
      final recognitionFuture = recognizeText(preparedPath ?? imagePath)
          .whenComplete(() async {
            _recognitionInFlight = false;
            if (deferPreparedDeletion &&
                pathForDeferredDeletion != null &&
                pathForDeferredDeletion != imagePath) {
              try {
                await File(pathForDeferredDeletion).delete();
              } catch (_) {
                // Temporary OCR frames are best-effort cleanup only.
              }
            }
          });
      try {
        text = await recognitionFuture.timeout(ocrTimeout);
      } on TimeoutException {
        deferPreparedDeletion = true;
        preparedPath = null;
        _debugLog(quality: 'timeout', duration: stopwatch.elapsed);
        return ThermoScanOcrResult(
          timedOut: true,
          didRunOcr: true,
          scanDuration: stopwatch.elapsed,
        );
      }
      if (text == null) {
        _debugLog(quality: 'no-text', duration: stopwatch.elapsed);
        return ThermoScanOcrResult(
          didRunOcr: true,
          scanDuration: stopwatch.elapsed,
        );
      }
      final reading = extractThermoScanReadingCelsius(text);
      _debugLog(
        quality: prepared.qualityChecksRan ? 'checked' : 'skipped',
        rawText: text,
        duration: stopwatch.elapsed,
      );
      return ThermoScanOcrResult(
        readingCelsius: reading,
        rawText: text,
        didRunOcr: true,
        scanDuration: stopwatch.elapsed,
      );
    } finally {
      if (preparedPath != null && preparedPath != imagePath) {
        try {
          await File(preparedPath).delete();
        } catch (_) {
          // Temporary OCR frames are best-effort cleanup only.
        }
      }
    }
  }

  static Future<ThermoScanPreprocessResult> prepareThermoScanImageForOcr({
    required String sourcePath,
    required String outputPath,
    ThermoScanCropFrame? cropFrame,
    bool enableQualityChecks = kThermoScanQualityChecksEnabled,
  }) async {
    final raw = await compute(_preprocessThermoScanImageForOcr, {
      'sourcePath': sourcePath,
      'outputPath': outputPath,
      'cropFrame': cropFrame?.toJson(),
      'enableQualityChecks': enableQualityChecks,
    });
    return ThermoScanPreprocessResult.fromJson(raw);
  }

  static Future<bool> preprocessThermoScanImageForOcr({
    required String sourcePath,
    required String outputPath,
  }) {
    return prepareThermoScanImageForOcr(
      sourcePath: sourcePath,
      outputPath: outputPath,
      enableQualityChecks: false,
    ).then((result) => result.prepared && result.shouldRunOcr);
  }

  Future<ThermoScanPreprocessResult> _prepareThermoScanImageForOcr(
    String imagePath, {
    ThermoScanCropFrame? cropFrame,
    required bool enableQualityChecks,
  }) async {
    final sourceFile = File(imagePath);
    if (!await sourceFile.exists()) {
      return const ThermoScanPreprocessResult(
        prepared: false,
        shouldRunOcr: true,
      );
    }

    final tempPath = path.join(
      Directory.systemTemp.path,
      'thermoscan_ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    final processed = await prepareThermoScanImageForOcr(
      sourcePath: imagePath,
      outputPath: tempPath,
      cropFrame: cropFrame,
      enableQualityChecks: enableQualityChecks,
    );
    return processed;
  }

  void _debugLog({
    required String quality,
    String? rawText,
    String? rejectedReason,
    required Duration duration,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      'ThermoScan OCR quality=$quality '
      'rejected=${rejectedReason ?? 'none'} '
      'durationMs=${duration.inMilliseconds} '
      'rawText=${rawText == null ? 'null' : rawText.replaceAll('\n', ' | ')}',
    );
  }

  static double? extractThermoScanReadingCelsius(String text) {
    final candidates = <_ThermoScanCandidate>[
      ..._splitSevenSegmentCandidates(text),
      ..._numericTokenCandidates(text),
    ];
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.firstOrNull?.celsius;
  }

  static Iterable<_ThermoScanCandidate> _numericTokenCandidates(String text) {
    final matches = RegExp(
      r'(-?\d+(?:[.,]\d+)?)\s*(?:°\s*)?([cCfF])?',
    ).allMatches(text);

    final candidates = <_ThermoScanCandidate>[];
    for (final match in matches) {
      final rawValue = match.group(1);
      final value = double.tryParse(rawValue?.replaceAll(',', '.') ?? '');
      if (rawValue == null || value == null) continue;
      final unit = match.group(2)?.toUpperCase();

      candidates.addAll(
        _candidatesForValue(rawValue: rawValue, value: value, unit: unit),
      );
    }
    return candidates;
  }

  static Iterable<_ThermoScanCandidate> _splitSevenSegmentCandidates(
    String text,
  ) {
    final matches = RegExp(
      r'\b(\d{2,3})\s+(\d)\b\s*(?:°\s*)?([cCfF])?',
      multiLine: true,
    ).allMatches(text);

    final candidates = <_ThermoScanCandidate>[];
    for (final match in matches) {
      final whole = match.group(1);
      final tenths = match.group(2);
      if (whole == null || tenths == null) continue;
      final value = double.tryParse('$whole.$tenths');
      if (value == null) continue;
      final unit = match.group(3)?.toUpperCase();
      candidates.addAll(
        _candidatesForValue(
          rawValue: '$whole$tenths',
          value: value,
          unit: unit,
          baseScore: 95,
        ),
      );
    }
    return candidates;
  }

  static Iterable<_ThermoScanCandidate> _candidatesForValue({
    required String rawValue,
    required double value,
    required String? unit,
    int baseScore = 80,
  }) {
    final candidates = <_ThermoScanCandidate>[];
    final normalizedUnit = unit?.toUpperCase();

    void addCelsius(double temp, int score) {
      if (_isReasonableCelsius(temp)) {
        candidates.add(_ThermoScanCandidate(temp, score));
      }
    }

    void addFahrenheit(double temp, int score) {
      if (_isReasonableFahrenheit(temp)) {
        candidates.add(_ThermoScanCandidate(_fahrenheitToCelsius(temp), score));
      }
    }

    if (normalizedUnit == 'C') {
      addCelsius(value, baseScore + 20);
    } else if (normalizedUnit == 'F') {
      addFahrenheit(value, baseScore + 20);
    } else if (value >= 45) {
      addFahrenheit(value, baseScore);
    } else {
      addCelsius(value, baseScore);
    }

    final recovered = _recoverMissedDecimal(rawValue);
    if (recovered != null && recovered != value) {
      if (normalizedUnit == 'C') {
        addCelsius(recovered, baseScore + 10);
      } else if (normalizedUnit == 'F') {
        addFahrenheit(recovered, baseScore + 10);
      } else if (recovered >= 45) {
        addFahrenheit(recovered, baseScore - 5);
      } else {
        addCelsius(recovered, baseScore - 5);
      }
    }

    return candidates;
  }

  static double? _recoverMissedDecimal(String rawValue) {
    if (rawValue.contains('.') || rawValue.contains(',')) return null;
    final digits = rawValue.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 3) {
      return double.tryParse(
        '${digits.substring(0, 2)}.${digits.substring(2)}',
      );
    }
    if (digits.length == 4) {
      final wholeDigits = digits.startsWith('0') ? 2 : 3;
      return double.tryParse(
        '${digits.substring(0, wholeDigits)}.${digits.substring(wholeDigits)}',
      );
    }
    return null;
  }

  static bool _isReasonableCelsius(double value) => value >= 10 && value <= 45;

  static bool _isReasonableFahrenheit(double value) =>
      value >= 50 && value <= 115;

  static double _fahrenheitToCelsius(double tempF) => (tempF - 32) * 5 / 9;
}

class _ThermoScanCandidate {
  const _ThermoScanCandidate(this.celsius, this.score);

  final double celsius;
  final int score;
}

Future<Map<String, Object?>> _preprocessThermoScanImageForOcr(
  Map<String, Object?> args,
) async {
  final sourcePath = args['sourcePath'] as String?;
  final outputPath = args['outputPath'] as String?;
  if (sourcePath == null || outputPath == null) {
    return _preprocessResult(prepared: false, shouldRunOcr: true);
  }

  try {
    final sourceBytes = await File(sourcePath).readAsBytes();
    final decoded = image.decodeImage(sourceBytes);
    if (decoded == null) {
      return _preprocessResult(prepared: false, shouldRunOcr: true);
    }

    var normalized = image.bakeOrientation(decoded);
    if (normalized.width > normalized.height) {
      normalized = image.copyRotate(normalized, angle: 90);
    }

    final cropRect = _cropRectForImage(
      normalized,
      args['cropFrame'] as Map<String, Object?>?,
    );
    final cropped = image.copyCrop(
      normalized,
      x: cropRect.x,
      y: cropRect.y,
      width: cropRect.width,
      height: cropRect.height,
    );

    final enableQualityChecks =
        args['enableQualityChecks'] as bool? ?? kThermoScanQualityChecksEnabled;
    if (enableQualityChecks) {
      final quality = _qualityCheck(cropped);
      if (!quality.shouldRunOcr) {
        return _preprocessResult(
          prepared: true,
          shouldRunOcr: false,
          rejectionReason: quality.rejectionReason,
          hint: quality.hint,
          qualityChecksRan: true,
        );
      }
    }

    final grayscaled = image.grayscale(cropped);
    final contrasted = image.contrast(grayscaled, contrast: 112);
    final outputBytes = image.encodeJpg(contrasted, quality: 86);
    await File(outputPath).writeAsBytes(outputBytes, flush: true);
    return _preprocessResult(
      prepared: true,
      shouldRunOcr: true,
      outputPath: outputPath,
      qualityChecksRan: enableQualityChecks,
    );
  } catch (e) {
    try {
      await File(outputPath).delete();
    } catch (_) {
      // Best-effort cleanup only.
    }
    if (kDebugMode) {
      debugPrint('ThermoScan OCR preprocessing failed for $sourcePath: $e');
    }
    return _preprocessResult(
      prepared: false,
      shouldRunOcr: true,
      qualityChecksFailed: true,
    );
  }
}

Map<String, Object?> _preprocessResult({
  required bool prepared,
  required bool shouldRunOcr,
  String? outputPath,
  ThermoScanQualityRejection? rejectionReason,
  String? hint,
  bool qualityChecksRan = false,
  bool qualityChecksFailed = false,
}) => {
  'prepared': prepared,
  'shouldRunOcr': shouldRunOcr,
  'outputPath': outputPath,
  'rejectionReason': rejectionReason?.name,
  'hint': hint,
  'qualityChecksRan': qualityChecksRan,
  'qualityChecksFailed': qualityChecksFailed,
};

({int x, int y, int width, int height}) _cropRectForImage(
  image.Image normalized,
  Map<String, Object?>? cropFrame,
) {
  if (cropFrame != null) {
    final mapped = _mappedFrameCropRect(normalized, cropFrame);
    if (mapped != null) return mapped;
  }
  return _fallbackCenterCropRect(normalized);
}

({int x, int y, int width, int height})? _mappedFrameCropRect(
  image.Image normalized,
  Map<String, Object?> cropFrame,
) {
  final previewWidth = (cropFrame['previewWidth'] as num?)?.toDouble();
  final previewHeight = (cropFrame['previewHeight'] as num?)?.toDouble();
  final frameWidth =
      (cropFrame['frameWidth'] as num?)?.toDouble() ?? kThermoScanFrameWidth;
  final frameHeight =
      (cropFrame['frameHeight'] as num?)?.toDouble() ?? kThermoScanFrameHeight;
  if (previewWidth == null ||
      previewHeight == null ||
      previewWidth <= 0 ||
      previewHeight <= 0 ||
      frameWidth <= 0 ||
      frameHeight <= 0) {
    return null;
  }

  final sourceWidth = normalized.width.toDouble();
  final sourceHeight = normalized.height.toDouble();
  final scale = math.max(
    previewWidth / sourceWidth,
    previewHeight / sourceHeight,
  );
  if (!scale.isFinite || scale <= 0) return null;

  final displayedWidth = sourceWidth * scale;
  final displayedHeight = sourceHeight * scale;
  final hiddenX = math.max(0.0, (displayedWidth - previewWidth) / 2);
  final hiddenY = math.max(0.0, (displayedHeight - previewHeight) / 2);
  final displayX = hiddenX + ((previewWidth - frameWidth) / 2);
  final displayY = hiddenY + ((previewHeight - frameHeight) / 2);
  final sourceX = displayX / scale;
  final sourceY = displayY / scale;
  final sourceW = frameWidth / scale;
  final sourceH = frameHeight / scale;
  return _paddedClampedRect(
    normalized,
    x: sourceX,
    y: sourceY,
    width: sourceW,
    height: sourceH,
  );
}

({int x, int y, int width, int height}) _fallbackCenterCropRect(
  image.Image normalized,
) {
  const frameAspect = kThermoScanFrameWidth / kThermoScanFrameHeight;
  final maxCropWidth = (normalized.width * 0.72).round();
  final maxCropHeight = (normalized.height * 0.38).round();
  var cropWidth = maxCropWidth.clamp(1, normalized.width);
  var cropHeight = (cropWidth / frameAspect).round();

  if (cropHeight > maxCropHeight) {
    cropHeight = maxCropHeight.clamp(1, normalized.height);
    cropWidth = (cropHeight * frameAspect).round().clamp(1, normalized.width);
  }

  return _paddedClampedRect(
    normalized,
    x: (normalized.width - cropWidth) / 2,
    y: (normalized.height - cropHeight) / 2,
    width: cropWidth.toDouble(),
    height: cropHeight.toDouble(),
    padding: 0,
  );
}

({int x, int y, int width, int height}) _paddedClampedRect(
  image.Image source, {
  required double x,
  required double y,
  required double width,
  required double height,
  double padding = kThermoScanFramePadding,
}) {
  final padX = width * padding;
  final padY = height * padding;
  final left = (x - padX).floor().clamp(0, source.width - 1);
  final top = (y - padY).floor().clamp(0, source.height - 1);
  final right = (x + width + padX).ceil().clamp(left + 1, source.width);
  final bottom = (y + height + padY).ceil().clamp(top + 1, source.height);
  return (x: left, y: top, width: right - left, height: bottom - top);
}

({bool shouldRunOcr, ThermoScanQualityRejection? rejectionReason, String? hint})
_qualityCheck(image.Image cropped) {
  final stats = _imageStats(cropped);
  if (stats.foregroundCoverage > 0 &&
      stats.foregroundCoverage < kThermoScanMinimumDigitSize) {
    return (
      shouldRunOcr: false,
      rejectionReason: ThermoScanQualityRejection.distance,
      hint: 'Move closer',
    );
  }

  if (stats.edgeScore < kThermoScanBlurThreshold) {
    return (
      shouldRunOcr: false,
      rejectionReason: ThermoScanQualityRejection.blur,
      hint: 'Move slightly back',
    );
  }

  if (stats.averageBrightness < kThermoScanBrightnessThreshold ||
      stats.averageBrightness > 255 - kThermoScanBrightnessThreshold) {
    return (
      shouldRunOcr: false,
      rejectionReason: ThermoScanQualityRejection.lighting,
      hint: 'Reduce glare',
    );
  }

  return (shouldRunOcr: true, rejectionReason: null, hint: null);
}

({double averageBrightness, double edgeScore, double foregroundCoverage})
_imageStats(image.Image source) {
  var total = 0.0;
  var edgeTotal = 0.0;
  var edgeCount = 0;
  var minX = source.width;
  var minY = source.height;
  var maxX = -1;
  var maxY = -1;
  final sampleStep = math.max(1, math.min(source.width, source.height) ~/ 96);

  for (var y = 0; y < source.height; y += sampleStep) {
    for (var x = 0; x < source.width; x += sampleStep) {
      final current = _luma(source.getPixel(x, y));
      total += current;
      if (x + sampleStep < source.width) {
        edgeTotal += (current - _luma(source.getPixel(x + sampleStep, y)))
            .abs();
        edgeCount++;
      }
      if (y + sampleStep < source.height) {
        edgeTotal += (current - _luma(source.getPixel(x, y + sampleStep)))
            .abs();
        edgeCount++;
      }
    }
  }

  final sampleColumns = (source.width / sampleStep).ceil();
  final sampleRows = (source.height / sampleStep).ceil();
  final average = total / math.max(1, sampleColumns * sampleRows);
  final foregroundThreshold = 28.0;
  for (var y = 0; y < source.height; y += sampleStep) {
    for (var x = 0; x < source.width; x += sampleStep) {
      final delta = (_luma(source.getPixel(x, y)) - average).abs();
      if (delta >= foregroundThreshold) {
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
      }
    }
  }

  var coverage = 0.0;
  if (maxX >= minX && maxY >= minY) {
    final foregroundWidth = maxX - minX + sampleStep;
    final foregroundHeight = maxY - minY + sampleStep;
    coverage = math.min(
      foregroundWidth / source.width,
      foregroundHeight / source.height,
    );
  }

  return (
    averageBrightness: average,
    edgeScore: edgeCount == 0 ? 0 : edgeTotal / edgeCount,
    foregroundCoverage: coverage,
  );
}

double _luma(image.Pixel pixel) =>
    (0.299 * pixel.r) + (0.587 * pixel.g) + (0.114 * pixel.b);
