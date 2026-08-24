import 'dart:convert';

import 'est_grid_data.dart';
import 'temperature_entry_unit.dart';

class TemperatureReadingsPayload {
  const TemperatureReadingsPayload({
    required this.unit,
    required this.readings,
  });

  final TemperatureEntryUnit unit;

  /// Values persisted in the caller's fixed canonical unit. [unit] records
  /// the entry/display unit so reopening the form restores the user's choice.
  final Map<String, double> readings;

  factory TemperatureReadingsPayload.fromDisplay({
    required TemperatureEntryUnit unit,
    required Map<String, double> readings,
    required TemperatureEntryUnit canonicalUnit,
  }) {
    return TemperatureReadingsPayload(
      unit: unit,
      readings: {
        for (final entry in readings.entries)
          entry.key: unit.toCanonical(
            entry.value,
            canonicalUnit: canonicalUnit,
          ),
      },
    );
  }

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

  Map<String, double> forDisplay({
    required TemperatureEntryUnit canonicalUnit,
  }) {
    return {
      for (final entry in readings.entries)
        entry.key: unit.fromCanonical(
          entry.value,
          canonicalUnit: canonicalUnit,
        ),
    };
  }

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
