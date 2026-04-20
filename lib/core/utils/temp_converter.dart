class TempConverter {
  static double toCelsius(double fahrenheit) =>
      ((fahrenheit - 32) * 5 / 9).toDouble();
  static double toFahrenheit(double celsius) =>
      ((celsius * 9 / 5) + 32).toDouble();
  static String display(double value, {bool showCelsius = false}) {
    if (showCelsius) {
      final c = toCelsius(value);
      return "${c.toStringAsFixed(1)}°C";
    } else {
      return "${value.toStringAsFixed(1)}°F";
    }
  }
}
