import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/utils/temp_converter.dart';

void main() {
  group('TempConverter', () {
    test('toCelsius(32.0) == 0.0', () {
      expect(TempConverter.toCelsius(32.0), 0.0);
    });
    test('toCelsius(212.0) == 100.0', () {
      expect(TempConverter.toCelsius(212.0), 100.0);
    });
    test('toFahrenheit(0.0) == 32.0', () {
      expect(TempConverter.toFahrenheit(0.0), 32.0);
    });
    test('toFahrenheit(100.0) == 212.0', () {
      expect(TempConverter.toFahrenheit(100.0), 212.0);
    });
    test('display(98.6, showCelsius: false) == "98.6°F"', () {
      expect(TempConverter.display(98.6, showCelsius: false), "98.6°F");
    });
    test('display(98.6, showCelsius: true) == "37.0°C"', () {
      expect(TempConverter.display(98.6, showCelsius: true), "37.0°C");
    });
  });
}
