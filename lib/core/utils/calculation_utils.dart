import 'dart:math' as math;

class CalculationUtils {
  static double cvPercent(List<double> values) {
    if (values.length < 2) return 0.0;
    final avg = average(values);
    if (avg == 0) return 0.0;
    // Use sample standard deviation (n-1 denominator).
    final mean = avg;
    final sumSq = values.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b);
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
    return double.parse((((sampleSize * 10) - sum) / sampleSize).toStringAsFixed(1));
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
    final sumSq = values.map((v) => math.pow(v - avg, 2)).reduce((a, b) => a + b);
    return math.sqrt(sumSq / values.length);
  }
}
