import 'dart:math' as math;

class CalculationUtils {
  static double cvPercent(List<double> values) {
    if (values.length < 2) return 0.0;
    final avg = average(values);
    if (avg == 0) return 0.0;
    // Use sample standard deviation (n-1 denominator).
    final mean = avg;
    final sumSq = values
        .map((v) => math.pow(v - mean, 2))
        .reduce((a, b) => a + b);
    final std = math.sqrt(sumSq / (values.length - 1));
    return double.parse(((std / avg) * 100).toStringAsFixed(1));
  }

  static double uniformityPercent(List<double> values, double min, double max) {
    if (values.isEmpty) return 0.0;
    final inRange = values.where((v) => v >= min && v <= max).length;
    // Percent INSIDE range (AVG ± 10%)
    return double.parse(((inRange / values.length) * 100).toStringAsFixed(1));
  }

  static double pasgarScore(int sampleSize, List<int> defectCounts) {
    if (sampleSize == 0) return 0.0;
    final sum = defectCounts.fold(0, (a, b) => a + b);
    // ((sampleSize * 10) - sum) / sampleSize
    return double.parse(
      (((sampleSize * 10) - sum) / sampleSize).toStringAsFixed(1),
    );
  }

  static double fertility(int fertile, int clear) {
    final total = fertile + clear;
    if (total == 0) return 100.0;
    return double.parse(((fertile / total) * 100).toStringAsFixed(1));
  }

  static double hatchability(int hatched, int total) {
    if (total == 0) return 0.0;
    return double.parse(((hatched / total) * 100).toStringAsFixed(1));
  }

  static double hof(double hatchability, double fertility) {
    if (fertility == 0) return 0.0;
    return double.parse(((hatchability / fertility) * 100).toStringAsFixed(1));
  }

  static double average(List<double> values) {
    if (values.isEmpty) return 0.0;
    final sum = values.reduce((a, b) => a + b);
    return sum / values.length;
  }

  static double stdDev(List<double> values) {
    if (values.isEmpty) return 0.0;
    final avg = average(values);
    final sumSq = values
        .map((v) => math.pow(v - avg, 2))
        .reduce((a, b) => a + b);
    return math.sqrt(sumSq / values.length);
  }

  /// Returns a shell-temperature zone label for °C readings.
  /// Optimal: 19–21 °C.  Low: <19 °C.  High: >21 °C.
  static String shellTempZone(double tempC) {
    if (tempC < 19) return 'Low';
    if (tempC > 21) return 'High';
    return 'Optimal';
  }

  /// Returns a shell-temperature color indicator for °C readings.
  static TemperatureStatus shellTempStatus(double tempC) {
    if (tempC < 19) return TemperatureStatus.low;
    if (tempC > 21) return TemperatureStatus.high;
    return TemperatureStatus.optimal;
  }

  /// Returns EST zone label for °F readings.
  /// Optimal: 100–101 °F.  Low: <100 °F.  High: >101 °F.
  static String estZone(double tempF) {
    if (tempF < 100) return 'Low';
    if (tempF > 101) return 'High';
    return 'Optimal';
  }

  static TemperatureStatus estStatus(double tempF) {
    if (tempF < 100) return TemperatureStatus.low;
    if (tempF > 101) return TemperatureStatus.high;
    return TemperatureStatus.optimal;
  }

  /// Returns CVT zone label for °F readings.
  /// Optimal: 103–105 °F.  Low: <103 °F.  High: >105 °F.
  static String cvtZone(double tempF) {
    if (tempF < 103) return 'Low';
    if (tempF > 105) return 'High';
    return 'Optimal';
  }

  static TemperatureStatus cvtStatus(double tempF) {
    if (tempF < 103) return TemperatureStatus.low;
    if (tempF > 105) return TemperatureStatus.high;
    return TemperatureStatus.optimal;
  }

  /// Computes UV affected percentage from count and sample size.
  static double uvAffectedPct(int affectedCount, int sampleSize) {
    if (sampleSize == 0) return 0.0;
    return double.parse(
      ((affectedCount / sampleSize) * 100).toStringAsFixed(1),
    );
  }

  /// Aggregates multiple UV affected percentages into an overall average.
  static double overallUvAffectedAvg(List<double> percentages) {
    if (percentages.isEmpty) return 0.0;
    final sum = percentages.reduce((a, b) => a + b);
    return double.parse((sum / percentages.length).toStringAsFixed(1));
  }
}

enum TemperatureStatus { low, optimal, high }
