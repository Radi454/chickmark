import 'dart:math';

class Calculations {
  static double average(List<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  static double stdDev(List<double> values) {
    if (values.length < 2) return 0;
    final avg = average(values);
    final variance =
        values.map((v) => pow(v - avg, 2)).reduce((a, b) => a + b) /
            (values.length - 1);
    return sqrt(variance);
  }

  static double cvPercent(List<double> values) {
    final avg = average(values);
    if (avg == 0) return 0;
    return (stdDev(values) / avg) * 100;
  }

  static double uniformityPercent(List<double> values) {
    if (values.isEmpty) return 0;
    final avg = average(values);
    final lower = avg * 0.9;
    final upper = avg * 1.1;
    final inRange = values.where((v) => v >= lower && v <= upper).length;
    return (inRange / values.length) * 100;
  }

  static String pasgarColor(double score) {
    if (score >= 9.0) return 'green';
    if (score >= 7.0) return 'amber';
    return 'red';
  }

  static String wingColor(double percent) {
    if (percent >= 90) return 'green';
    if (percent >= 75) return 'amber';
    return 'red';
  }
}
