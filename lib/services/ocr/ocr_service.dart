import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  bool _isAvailable = false;

  bool get isAvailable => _isAvailable;

  OcrService() {
    _checkCameraAvailability();
  }

  Future<void> _checkCameraAvailability() async {
    try {
      _isAvailable = !kIsWeb;
    } catch (e) {
      _isAvailable = false;
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
      // Silent error logging
      return null;
    }
  }

  Future<double?> recognizeThermoScanReadingCelsius(String imagePath) async {
    final text = await recognizeText(imagePath);
    if (text == null) return null;
    return extractThermoScanReadingCelsius(text);
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
