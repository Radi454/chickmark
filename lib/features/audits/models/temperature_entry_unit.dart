import '../../../core/utils/temp_converter.dart';
import '../../../services/ocr/ocr_service.dart' show ThermoScanUnit;

enum TemperatureEntryUnit {
  fahrenheit,
  celsius;

  String get suffix => this == fahrenheit ? '°F' : '°C';

  ThermoScanUnit get thermoScanUnit =>
      this == fahrenheit ? ThermoScanUnit.fahrenheit : ThermoScanUnit.celsius;

  double convert(double value, TemperatureEntryUnit target) {
    if (this == target) return value;
    return target == fahrenheit
        ? TempConverter.toFahrenheit(value)
        : TempConverter.toCelsius(value);
  }

  double toCanonical(
    double value, {
    required TemperatureEntryUnit canonicalUnit,
  }) => convert(value, canonicalUnit);

  double fromCanonical(
    double value, {
    required TemperatureEntryUnit canonicalUnit,
  }) => canonicalUnit.convert(value, this);
}
