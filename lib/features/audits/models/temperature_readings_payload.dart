import 'dart:convert';

import 'est_grid_data.dart';
import 'temperature_entry_unit.dart';

class TemperatureReadingsPayload {
  const TemperatureReadingsPayload({
    required this.unit,
    required this.readings,
  });

  final TemperatureEntryUnit unit;
  final Map<String, double> readings;

  factory TemperatureReadingsPayload.decode(
    String? source, {
    required TemperatureEntryUnit legacyUnit,
  }) {
    if (source == null || source.trim().isEmpty) {
      return TemperatureReadingsPayload(unit: legacyUnit, readings: const {});
    }
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map) {
        final rawReadings = decoded['readings'] is Map
            ? decoded['readings'] as Map
            : decoded;
        return TemperatureReadingsPayload(
          unit: _unitFromValue(decoded['unit']) ?? legacyUnit,
          readings: EstGridData.normalizeReadings(rawReadings),
        );
      }
      if (decoded is List) {
        return TemperatureReadingsPayload(
          unit: legacyUnit,
          readings: _readingsFromList(decoded),
        );
      }
    } catch (_) {
      // Malformed persisted JSON should behave like a blank legacy payload.
    }
    return TemperatureReadingsPayload(unit: legacyUnit, readings: const {});
  }

  String toJsonString() {
    return jsonEncode(toJsonMap());
  }

  Map<String, Object> toJsonMap() {
    return {'unit': unit.suffix, 'readings': readings};
  }

  int get count => readings.length;

  static TemperatureEntryUnit? _unitFromValue(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'c' || '°c' || 'celsius' => TemperatureEntryUnit.celsius,
      'f' || '°f' || 'fahrenheit' => TemperatureEntryUnit.fahrenheit,
      _ => null,
    };
  }

  static Map<String, double> _readingsFromList(List<dynamic> values) {
    final readings = <String, double>{};
    for (var i = 0; i < values.length && i < EstGridData.scanKeys.length; i++) {
      final value = values[i];
      final parsed = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '');
      if (parsed != null) readings[EstGridData.scanKeys[i]] = parsed;
    }
    return readings;
  }
}
