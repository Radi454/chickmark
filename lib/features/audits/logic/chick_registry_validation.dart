import 'dart:convert';

import '../../../data/agent/station_adapter.dart';
import '../../../data/agent/station_registry.dart';

class ChickRegistryWarning {
  const ChickRegistryWarning({
    required this.schemaKey,
    required this.fieldKey,
    required this.code,
  });

  final String schemaKey;
  final String fieldKey;
  final String code;
}

/// Validates each chick domain independently with only its registry-declared
/// local columns. This avoids `unknown_field` noise from feeding a whole audit
/// map into a single-domain schema. Warnings are advisory; callers never use
/// them to block offline persistence.
List<ChickRegistryWarning> validateChickRegistryDomains({
  required Map<String, Object?> chickQualityValues,
  required Map<String, Object?> chickWeightValues,
}) {
  final warnings = <ChickRegistryWarning>[];
  for (final schema in AgentStationRegistry.schemas.where(
    (schema) => schema.stationKey == 'chicks',
  )) {
    final localTable = schema.persistence.first.localTable;
    final source = localTable == 'chick_weights'
        ? chickWeightValues
        : chickQualityValues;
    final values = <String, Object?>{};
    for (final field in schema.fields) {
      final localColumn = field.persistence['localColumn']?.toString();
      if (localColumn == null || !source.containsKey(localColumn)) continue;
      final value = _registryValue(field, source[localColumn]);
      if (value != null) values[field.fieldKey] = value;
    }
    if (values.isEmpty) continue;

    final validation = AgentStationAdapter.validate(schema, values);
    for (final field in validation.missing) {
      warnings.add(
        ChickRegistryWarning(
          schemaKey: schema.schemaKey,
          fieldKey: field,
          code: 'required',
        ),
      );
    }
    for (final issue in validation.issues) {
      warnings.add(
        ChickRegistryWarning(
          schemaKey: schema.schemaKey,
          fieldKey: issue.fieldKey,
          code: issue.code,
        ),
      );
    }
  }
  return List.unmodifiable(warnings);
}

Object? _registryValue(AgentStationField field, Object? value) {
  if (value == null) return null;
  final choices = (field.validation['choices'] as List?)
      ?.map((choice) => choice.toString())
      .toList(growable: false);
  if (value is String && choices != null) {
    final normalized = value.trim().toLowerCase();
    for (final choice in choices) {
      if (choice.toLowerCase() == normalized) return choice;
    }
  }
  if (value is! String) return value;
  if (field.type != 'number_list' && field.type != 'object_list') return value;
  try {
    final decoded = jsonDecode(value);
    if (field.type == 'number_list' && decoded is Map) {
      final readings = decoded['readings'];
      if (readings is Map) return readings.values.toList(growable: false);
    }
    if (field.type == 'object_list' && decoded is List) {
      final itemSchema = field.validation['itemSchema'];
      if (itemSchema is Map) {
        final properties = itemSchema['properties'];
        if (properties is Map) {
          final allowed = properties.keys.map((key) => key.toString()).toSet();
          return [
            for (final item in decoded)
              if (item is Map)
                {
                  for (final entry in item.entries)
                    if (allowed.contains(entry.key.toString()))
                      entry.key.toString(): entry.value,
                }
              else
                item,
          ];
        }
      }
    }
    return decoded;
  } catch (_) {
    return value;
  }
}
