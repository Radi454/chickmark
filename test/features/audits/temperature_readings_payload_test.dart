import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/models/temperature_entry_unit.dart';
import 'package:hatchaudit/features/audits/models/temperature_readings_payload.dart';

void main() {
  group('TemperatureReadingsPayload', () {
    test('round-trips readings with the selected unit', () {
      const payload = TemperatureReadingsPayload(
        unit: TemperatureEntryUnit.celsius,
        readings: {'front_top': 20.1, 'middle_middle': 20.5},
      );

      final restored = TemperatureReadingsPayload.decode(
        payload.toJsonString(),
        legacyUnit: TemperatureEntryUnit.fahrenheit,
      );

      expect(restored.unit, TemperatureEntryUnit.celsius);
      expect(restored.readings, {'front_top': 20.1, 'middle_middle': 20.5});
    });

    test('decodes legacy plain reading maps with the caller fallback unit', () {
      final restored = TemperatureReadingsPayload.decode(
        '{"front_top":100.4,"middle_middle":100.6}',
        legacyUnit: TemperatureEntryUnit.fahrenheit,
      );

      expect(restored.unit, TemperatureEntryUnit.fahrenheit);
      expect(restored.readings, {'front_top': 100.4, 'middle_middle': 100.6});
    });

    test('stores Celsius entry values canonically in Fahrenheit', () {
      final payload = TemperatureReadingsPayload.fromDisplay(
        unit: TemperatureEntryUnit.celsius,
        readings: const {'front_top': 40.0, 'middle_middle': 39.5},
        canonicalUnit: TemperatureEntryUnit.fahrenheit,
      );

      expect(payload.unit, TemperatureEntryUnit.celsius);
      expect(payload.readings['front_top'], closeTo(104.0, 0.001));
      expect(payload.readings['middle_middle'], closeTo(103.1, 0.001));

      final restored = TemperatureReadingsPayload.decode(
        payload.toJsonString(),
        legacyUnit: TemperatureEntryUnit.fahrenheit,
      );
      final displayed = restored.forDisplay(
        canonicalUnit: TemperatureEntryUnit.fahrenheit,
      );
      expect(displayed['front_top'], closeTo(40.0, 0.001));
      expect(displayed['middle_middle'], closeTo(39.5, 0.001));
    });
  });
}
