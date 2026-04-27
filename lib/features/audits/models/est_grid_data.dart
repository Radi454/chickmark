class EstGridData {
  EstGridData._();

  static const locations = ['front', 'middle', 'back'];
  static const levels = ['top', 'middle', 'bottom'];
  static const scanKeys = [
    'front_top',
    'front_middle',
    'front_bottom',
    'middle_top',
    'middle_middle',
    'middle_bottom',
    'back_top',
    'back_middle',
    'back_bottom',
  ];

  static String key(String location, String level) => '${location}_$level';

  static List<Map<String, Object>> toStructuredReadings(
    Map<String, double> readings,
  ) {
    final structured = <Map<String, Object>>[];
    for (final key in scanKeys) {
      final value = readings[key];
      if (value == null) continue;
      final parts = key.split('_');
      structured.add({
        'position': label(parts[0]),
        'level': label(parts[1]),
        'value': value,
      });
    }
    return structured;
  }

  static Map<String, double> normalizeReadings(Map<dynamic, dynamic> readings) {
    final normalized = <String, double>{};
    for (final entry in readings.entries) {
      final rawKey = entry.key?.toString();
      final value = _toDouble(entry.value);
      if (rawKey == null || value == null) continue;

      final canonicalKey = rawKey.startsWith('door_')
          ? rawKey.replaceFirst('door_', 'front_')
          : rawKey;
      if (_isKnownKey(canonicalKey)) {
        normalized[canonicalKey] = value;
      }
    }
    return normalized;
  }

  static bool _isKnownKey(String key) {
    for (final location in locations) {
      for (final level in levels) {
        if (key == '${location}_$level') return true;
      }
    }
    return false;
  }

  static double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String label(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}
