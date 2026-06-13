import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/ocr/ocr_service.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

void main() {
  group('OcrService.extractThermoScanReadingCelsius', () {
    test('preserves fahrenheit unit on the accepted large reading', () {
      final estimate = OcrService.estimateThermoScanReading([
        '102.2 M\n104.6 °F\n3 7 30 30',
      ]);

      expect(estimate.displayValue, 104.6);
      expect(estimate.detectedUnit, ThermoScanUnit.fahrenheit);
      expect(estimate.readingCelsius, closeTo(40.33, 0.01));
    });

    test('normalizes common seven-segment OCR characters', () {
      final estimate = OcrService.estimateThermoScanReading(['1O4,6 °F']);

      expect(estimate.displayValue, 104.6);
      expect(estimate.detectedUnit, ThermoScanUnit.fahrenheit);
    });

    test('returns celsius value when OCR text includes celsius unit', () {
      expect(OcrService.extractThermoScanReadingCelsius('20.4 °C'), 20.4);
    });

    test(
      'converts fahrenheit value when OCR text includes fahrenheit unit',
      () {
        expect(
          OcrService.extractThermoScanReadingCelsius('100.4 °F'),
          closeTo(38.0, 0.1),
        );
      },
    );

    test('treats bare values at or above 45 as fahrenheit', () {
      expect(
        OcrService.extractThermoScanReadingCelsius('100.4'),
        closeTo(38.0, 0.1),
      );
    });

    test('extracts a plausible reading from noisy ThermoScan text', () {
      expect(
        OcrService.extractThermoScanReadingCelsius(
          'ThermoScan\nMEM 03\n100.4 F\nscan ok',
        ),
        closeTo(38.0, 0.1),
      );
    });

    test('recovers missed decimal from bare seven-segment celsius reading', () {
      expect(
        OcrService.extractThermoScanReadingCelsius('MONTH DAY\n233\nC'),
        closeTo(23.3, 0.1),
      );
    });

    test(
      'recovers missed decimal from bare seven-segment fahrenheit reading',
      () {
        expect(
          OcrService.extractThermoScanReadingCelsius('Lo\n1004\nF'),
          closeTo(38.0, 0.1),
        );
      },
    );

    test(
      'recovers split seven-segment reading from ThermoScan screen text',
      () {
        expect(
          OcrService.extractThermoScanReadingCelsius('MONTH DAY\n23 9\n°C'),
          closeTo(23.9, 0.1),
        );
      },
    );

    test('rejects explicit impossible fahrenheit readings', () {
      expect(OcrService.extractThermoScanReadingCelsius('233 °F'), isNull);
    });

    test('returns null when no temperature reading is present', () {
      expect(
        OcrService.extractThermoScanReadingCelsius('ThermoScan ready'),
        isNull,
      );
    });

    test('returns high confidence when multiple OCR outputs agree', () {
      final estimate = OcrService.estimateThermoScanReadingCelsius([
        'ThermoScan\n100.4 F',
        'scan\n100.5 °F',
        'MEM\n1004\nF',
      ]);

      expect(estimate.readingCelsius, closeTo(38.0, 0.1));
      expect(estimate.confidence, ThermoScanOcrConfidence.high);
      expect(estimate.supportingReadings, greaterThanOrEqualTo(2));
    });

    test('marks a single recovered-decimal reading as medium confidence', () {
      final estimate = OcrService.estimateThermoScanReadingCelsius([
        'MONTH DAY\n233\nC',
      ]);

      expect(estimate.readingCelsius, closeTo(23.3, 0.1));
      expect(estimate.confidence, ThermoScanOcrConfidence.medium);
      expect(estimate.supportingReadings, 1);
    });

    test('rejects isolated recovered-decimal digit noise without a unit', () {
      for (final text in const ['230', '2301', '211\n2301']) {
        final estimate = OcrService.estimateThermoScanReadingCelsius([text]);

        expect(
          estimate.readingCelsius,
          isNull,
          reason: 'Unexpected reading from "$text"',
        );
        expect(estimate.confidence, ThermoScanOcrConfidence.none);
      }
    });
  });

  group('OcrService.analyzeThermoScanReadingCelsius', () {
    test(
      'uses fallback variants only when the primary variant has no reading',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'ocr_analyze_variants_',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final sourcePath = path.join(tempDir.path, 'source.jpg');
        final source = img.Image(width: 360, height: 240);
        for (final pixel in source) {
          final inDisplay =
              pixel.x >= 130 &&
              pixel.x <= 230 &&
              pixel.y >= 90 &&
              pixel.y <= 150;
          pixel
            ..r = inDisplay ? 40 : 150
            ..g = inDisplay ? 40 : 150
            ..b = inDisplay ? 40 : 150
            ..a = 255;
        }
        await File(sourcePath).writeAsBytes(img.encodeJpg(source, quality: 95));

        final seenPaths = <String>[];
        final service = OcrService(
          isAvailableOverride: true,
          textRecognizer: (imagePath) async {
            seenPaths.add(imagePath);
            if (imagePath.contains('balanced')) return 'ThermoScan ready';
            return '100.4 F';
          },
        );

        final result = await service.analyzeThermoScanReadingCelsius(
          sourcePath,
          enableQualityChecks: false,
        );

        expect(seenPaths.length, greaterThanOrEqualTo(2));
        expect(result.attemptedVariants, greaterThanOrEqualTo(2));
        expect(result.readingCelsius, closeTo(38.0, 0.1));
        expect(result.confidence, ThermoScanOcrConfidence.high);
      },
    );

    test(
      'returns a primary reading before slow fallback variants exhaust timeout',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'ocr_primary_timeout_',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final sourcePath = path.join(tempDir.path, 'source.jpg');
        final source = img.Image(width: 360, height: 240);
        for (final pixel in source) {
          pixel
            ..r = 150
            ..g = 150
            ..b = 150
            ..a = 255;
        }
        await File(sourcePath).writeAsBytes(img.encodeJpg(source, quality: 95));

        final seenPaths = <String>[];
        final service = OcrService(
          isAvailableOverride: true,
          textRecognizer: (imagePath) async {
            seenPaths.add(imagePath);
            if (imagePath.contains('balanced')) {
              await Future<void>.delayed(const Duration(milliseconds: 120));
              return '100.4 F';
            }
            await Future<void>.delayed(const Duration(milliseconds: 900));
            return 'noise';
          },
        );

        final result = await service.analyzeThermoScanReadingCelsius(
          sourcePath,
          enableQualityChecks: false,
          ocrTimeout: const Duration(milliseconds: 600),
        );

        expect(result.timedOut, isFalse);
        expect(result.attemptedVariants, 1);
        expect(seenPaths.length, 1);
        expect(result.readingCelsius, closeTo(38.0, 0.1));
      },
    );
  });
}
