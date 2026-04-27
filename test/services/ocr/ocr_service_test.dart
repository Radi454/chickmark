import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/ocr/ocr_service.dart';

void main() {
  group('OcrService.extractThermoScanReadingCelsius', () {
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
  });
}
