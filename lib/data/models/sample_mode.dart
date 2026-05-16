class SampleMode {
  SampleMode._();

  static const String pool = 'pool';
  static const String compare = 'comparison';

  static String normalize(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == compare || normalized == 'compare') return compare;
    return pool;
  }

  static bool isCompare(String? value) => normalize(value) == compare;
}
