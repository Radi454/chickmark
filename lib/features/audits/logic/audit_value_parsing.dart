import 'dart:convert';

/// Parses a JSON source string as a list of maps, returning an empty list on error.
List<Map<String, dynamic>> decodedMaps(String? source) {
  if (source == null || source.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(source);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  } catch (_) {
    return const [];
  }
}

/// Returns the count of items in a decoded JSON list.
int decodedListLength(String? source) => decodedMaps(source).length;

/// Parses a JSON source string as a single map, returning null on error.
Map<String, Object?>? decodedMap(String? source) {
  if (source == null || source.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(source);
    if (decoded is! Map) return null;
    return Map<String, Object?>.from(decoded);
  } catch (_) {
    return null;
  }
}

/// Coerces a value to a double, handling nums and numeric strings.
double? asDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

/// Coerces a value to an int, handling nums and numeric strings.
int? asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

/// Calculates a percentage: (count / total) * 100, with zero-division guard.
double? pct(Object? count, Object? total) {
  final numerator = asInt(count);
  final denominator = asInt(total);
  if (numerator == null || denominator == null || denominator <= 0) {
    return null;
  }
  return numerator * 100 / denominator;
}

/// Encodes a map as compact JSON, omitting null values.
String compactJson(Map<String, Object?> value) {
  final compact = Map<String, Object?>.from(value)
    ..removeWhere((_, entry) => entry == null);
  return jsonEncode(compact);
}

/// Checks if a string has non-blank text.
bool hasText(String? value) => blankToNull(value) != null;

/// Trims a string and returns null if empty; otherwise returns the trimmed value.
String? blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
