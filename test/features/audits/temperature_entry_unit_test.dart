import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/models/temperature_entry_unit.dart';

void main() {
  test('converts display fahrenheit to canonical celsius', () {
    expect(
      TemperatureEntryUnit.fahrenheit.toCanonical(
        104.0,
        canonicalUnit: TemperatureEntryUnit.celsius,
      ),
      closeTo(40.0, 0.01),
    );
  });

  test('converts canonical celsius to display fahrenheit once', () {
    final canonical = TemperatureEntryUnit.celsius.toCanonical(
      40.0,
      canonicalUnit: TemperatureEntryUnit.celsius,
    );

    expect(
      TemperatureEntryUnit.fahrenheit.fromCanonical(
        canonical,
        canonicalUnit: TemperatureEntryUnit.celsius,
      ),
      closeTo(104.0, 0.01),
    );
  });
}
