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
  });
}
