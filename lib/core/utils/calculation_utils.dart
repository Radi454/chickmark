import 'dart:math' as math;

class CalculationUtils {
  static const int pasgarScoredDefectCategoryCount = 5;
  static const int pasgarTrackedDefectCategoryCount = 6;

  static double cvPercent(
    List<double> values, {
    int decimalPlaces = 1,
    bool sample = true,
  }) {
    if (values.length < 2) return 0.0;
    final avg = average(values);
    if (avg == 0) return 0.0;
    final std = stdDev(values, sample: sample);
    return roundTo((std / avg) * 100, decimalPlaces: decimalPlaces);
  }

  static double uniformityPercent(List<double> values, double min, double max) {
    if (values.isEmpty) return 0.0;
    final inRange = values.where((v) => v >= min && v <= max).length;
    return percentOf(inRange, values.length) ?? 0.0;
  }

  static double pasgarScore(int sampleSize, List<int> defectCounts) {
    if (sampleSize <= 0) return 0.0;
    final sum = defectCounts
        .take(pasgarScoredDefectCategoryCount)
        .map((count) => count.clamp(0, sampleSize).toInt())
        .fold(0, (a, b) => a + b);
    final score = ((sampleSize * 10) - sum) / sampleSize;
    return roundTo(score.clamp(5.0, 10.0));
  }

  static double fertility(int fertile, int clear) {
    final total = fertile + clear;
    if (total == 0) return 100.0;
    return percentOf(fertile, total) ?? 0.0;
  }

  static double hatchability(int hatched, int total) {
    if (total == 0) return 0.0;
    return percentOf(hatched, total) ?? 0.0;
  }

  static double hof(double hatchability, double fertility) {
    if (fertility == 0) return 0.0;
    return percentOf(hatchability, fertility, allowAbove100: true) ?? 0.0;
  }

  static double average(List<double> values) {
    if (values.isEmpty) return 0.0;
    final sum = values.reduce((a, b) => a + b);
    return sum / values.length;
  }

  static double? minValue(List<double> values) {
    if (values.isEmpty) return null;
    return values.reduce(math.min);
  }

  static double? maxValue(List<double> values) {
    if (values.isEmpty) return null;
    return values.reduce(math.max);
  }

  static double stdDev(List<double> values, {bool sample = true}) {
    if (values.isEmpty) return 0.0;
    if (sample && values.length < 2) return 0.0;
    final avg = average(values);
    final sumSq = values
        .map((v) => math.pow(v - avg, 2))
        .reduce((a, b) => a + b);
    final denominator = sample ? values.length - 1 : values.length;
    return math.sqrt(sumSq / denominator);
  }

  static double populationStdDev(List<double> values) {
    return stdDev(values, sample: false);
  }

  static double? percentOf(
    num? count,
    num? total, {
    int decimalPlaces = 1,
    bool allowAbove100 = false,
  }) {
    if (count == null || total == null) return null;
    if (count < 0 || total <= 0) return null;
    final pct = (count / total) * 100;
    if (!allowAbove100 && pct > 100) return null;
    return roundTo(pct.toDouble(), decimalPlaces: decimalPlaces);
  }

  static double roundTo(double value, {int decimalPlaces = 1}) {
    return double.parse(value.toStringAsFixed(decimalPlaces));
  }

  /// Divides [numerator] by [denominator], returning `null` when the
  /// denominator is missing, zero, or negative — the same "blank, never 0,
  /// never an error" convention [percentOf] already follows for
  /// non-positive totals, generalized for calculations that are not
  /// themselves a 0-100 percentage (e.g. breeder feed grams per bird, design
  /// doc section 7.2: "A zero, negative, or missing denominator yields a
  /// blank derived value, never `0` and never an error").
  static double? divideOrNull(
    num? numerator,
    num? denominator, {
    int decimalPlaces = 1,
  }) {
    if (numerator == null || denominator == null) return null;
    if (denominator <= 0) return null;
    return roundTo((numerator / denominator).toDouble(), decimalPlaces: decimalPlaces);
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

  /// Returns setter EST zone label for °F readings.
  /// Allowed: 99.5–102 °F. Optimal: 100–101 °F.
  static String setterEstZone(double tempF) {
    if (tempF < 99.5) return 'Low';
    if (tempF > 102) return 'High';
    if (tempF >= 100 && tempF <= 101) return 'Optimal';
    return 'Allowed';
  }

  /// Returns setter EST color indicator for °F readings.
  /// The three-state status keeps allowed-but-not-optimal values visible as
  /// low/high warnings while the zone label carries the allowed range.
  static TemperatureStatus setterEstStatus(double tempF) {
    if (tempF >= 100 && tempF <= 101) return TemperatureStatus.optimal;
    if (tempF > 101) return TemperatureStatus.high;
    return TemperatureStatus.low;
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
    return percentOf(affectedCount, sampleSize) ?? 0.0;
  }

  /// Aggregates multiple UV affected percentages into an overall average.
  static double overallUvAffectedAvg(List<double> percentages) {
    if (percentages.isEmpty) return 0.0;
    final sum = percentages.reduce((a, b) => a + b);
    return roundTo(sum / percentages.length);
  }
}

enum TemperatureStatus { low, optimal, high }
