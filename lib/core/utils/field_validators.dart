class FieldValidators {
  static String? positiveInt(String? v, {int max = 9999}) {
    if (v == null || v.trim().isEmpty) return null;
    final n = int.tryParse(v.trim());
    if (n == null) return 'Must be a whole number';
    if (n <= 0) return 'Must be > 0';
    if (n > max) return 'Must be <= $max';
    return null;
  }

  static String? positiveDouble(String? v, {double max = 999999}) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim());
    if (n == null) return 'Must be a number';
    if (n <= 0) return 'Must be > 0';
    if (n > max) return 'Must be <= ${max.toStringAsFixed(max.truncateToDouble() == max ? 0 : 1)}';
    return null;
  }

  static const _tempMinF = 90.0;
  static const _tempMaxF = 120.0;
  static const _tempMinC = 32.0;
  static const _tempMaxC = 49.0;

  static String? temperature(String? v, {required bool isFahrenheit}) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim());
    if (n == null) return 'Must be a number';
    final min = isFahrenheit ? _tempMinF : _tempMinC;
    final max = isFahrenheit ? _tempMaxF : _tempMaxC;
    if (n < min || n > max) {
      return '${min.toInt()}-${max.toInt()}${isFahrenheit ? '°F' : '°C'} expected';
    }
    return null;
  }

  static String? percentage(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim());
    if (n == null) return 'Must be a number';
    if (n < 0 || n > 100) return '0-100 expected';
    return null;
  }

  static String? sampleSize(String? v, {int max = 500}) {
    return positiveInt(v, max: max);
  }

  static String? weightGrams(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim());
    if (n == null) return 'Must be a number';
    if (n <= 0 || n > 200) return '0-200g expected';
    return null;
  }

  static const _co2Max = 5000.0;

  static String? co2(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim());
    if (n == null) return 'Must be a number';
    if (n < 0 || n > _co2Max) return '0-${_co2Max.toInt()} ppm expected';
    return null;
  }

  static const _airVelocityMax = 5.0;

  static String? airVelocity(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim());
    if (n == null) return 'Must be a number';
    if (n < 0 || n > _airVelocityMax) return '0-${_airVelocityMax.toInt()} m/s expected';
    return null;
  }

  static String? pasgarCount(String? v, {required int sampleSize}) {
    if (v == null || v.trim().isEmpty) return null;
    final n = int.tryParse(v.trim());
    if (n == null) return 'Must be a whole number';
    if (n < 0) return 'Must be >= 0';
    if (n > sampleSize) return 'Must be <= sample size ($sampleSize)';
    return null;
  }
}
