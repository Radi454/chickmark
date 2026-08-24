import 'dart:convert';

import '../../core/utils/calculation_utils.dart';
import 'station_registry.dart';

class AgentStationValueIssue {
  const AgentStationValueIssue({
    required this.fieldKey,
    required this.code,
    this.itemIndex,
    this.propertyKey,
  });

  final String fieldKey;
  final String code;
  final int? itemIndex;
  final String? propertyKey;
}

class AgentStationValidation {
  const AgentStationValidation({required this.missing, required this.issues});

  final List<String> missing;
  final List<AgentStationValueIssue> issues;

  bool get isValid => missing.isEmpty && issues.isEmpty;
}

abstract final class AgentStationAdapter {
  static AgentStationValidation validate(
    AgentStationSchema schema,
    Map<String, Object?> values,
  ) {
    final fieldsByKey = {
      for (final field in schema.fields) field.fieldKey: field,
    };
    final missing = <String>[
      for (final key in schema.requiredFieldKeys)
        if (values[key] == null) key,
    ];
    for (final field in schema.fields) {
      final dependency = _text(
        field.validation['requiredWhenPositiveFieldKey'],
      );
      if (dependency != null &&
          _positiveNumber(values[dependency]) &&
          (values[field.fieldKey] == null ||
              values[field.fieldKey]?.toString().trim().isEmpty == true)) {
        missing.add(field.fieldKey);
      }
    }

    final issues = <AgentStationValueIssue>[];
    for (final entry in values.entries) {
      final field = fieldsByKey[entry.key];
      if (field == null) {
        issues.add(
          AgentStationValueIssue(fieldKey: entry.key, code: 'unknown_field'),
        );
      } else if (entry.value != null) {
        issues.addAll(_validateField(field, entry.value, values));
      }
    }
    return AgentStationValidation(
      missing: List.unmodifiable(missing.toSet()),
      issues: List.unmodifiable(issues),
    );
  }

  static Map<String, Object?> calculate(
    AgentStationSchema schema,
    Map<String, Object?> values,
  ) {
    final calculated = <String, Object?>{};
    final available = <String, Object?>{...values};
    for (final calculation in schema.calculations) {
      final inputs = calculation.inputFieldKeys
          .map((key) => available[key])
          .toList(growable: false);
      final value = _calculate(calculation.kind, inputs);
      calculated[calculation.fieldKey] = value;
      available[calculation.fieldKey] = value;
    }
    return calculated;
  }

  static Map<String, Object?> persistenceValues(
    AgentStationSchema schema,
    Map<String, Object?> values,
  ) {
    return _persistenceValues(schema, values, columnKey: 'remoteColumn');
  }

  static Map<String, Object?> localPersistenceValues(
    AgentStationSchema schema,
    Map<String, Object?> values,
  ) {
    return _persistenceValues(schema, values, columnKey: 'localColumn');
  }

  /// Maps already-collected field values without turning Phase 2's
  /// warning-only registry checks into a persistence blocker.
  static Map<String, Object?> localPersistenceValuesUnchecked(
    AgentStationSchema schema,
    Map<String, Object?> values, {
    bool recomputeCalculations = true,
  }) {
    return _persistenceValues(
      schema,
      values,
      columnKey: 'localColumn',
      validateValues: false,
      recomputeCalculations: recomputeCalculations,
    );
  }

  static Map<String, Object?> fieldValuesFromLocalRow(
    AgentStationSchema schema,
    Map<String, Object?> row,
  ) {
    return _fieldValuesFromRow(schema, row, columnKey: 'localColumn');
  }

  static Map<String, Object?> fieldValuesFromRemoteRow(
    AgentStationSchema schema,
    Map<String, Object?> row,
  ) {
    return _fieldValuesFromRow(schema, row, columnKey: 'remoteColumn');
  }

  /// Selects persisted local values using only registry-declared columns while
  /// preserving their exact storage representation (including JSON spacing).
  static Map<String, Object?> registeredLocalColumnValues(
    AgentStationSchema schema,
    Map<String, Object?> row,
  ) {
    final result = <String, Object?>{};
    for (final field in schema.fields) {
      final column = _text(field.persistence['localColumn']);
      if (column != null && row.containsKey(column)) {
        result[column] = row[column];
      }
    }
    for (final calculation in schema.calculations) {
      final column = _text(calculation.persistence['localColumn']);
      if (column != null && row.containsKey(column)) {
        result[column] = row[column];
      }
    }
    return result;
  }

  static Map<String, Object?> _persistenceValues(
    AgentStationSchema schema,
    Map<String, Object?> values, {
    required String columnKey,
    bool validateValues = true,
    bool recomputeCalculations = true,
  }) {
    if (validateValues) {
      final validation = validate(schema, values);
      if (!validation.isValid) {
        throw ArgumentError('Station values are not valid');
      }
    }
    final calculated = recomputeCalculations
        ? calculate(schema, values)
        : {
            for (final calculation in schema.calculations)
              if (values.containsKey(calculation.fieldKey))
                calculation.fieldKey: values[calculation.fieldKey],
          };
    final result = <String, Object?>{};
    for (final field in schema.fields) {
      if (!values.containsKey(field.fieldKey)) continue;
      final column = _text(field.persistence[columnKey]);
      if (column == null) continue;
      final value = values[field.fieldKey];
      result[column] = switch (field.type) {
        'number_list' || 'object_list' when value == null => null,
        // Phase 2 UI drafts still carry JSON-backed lists as encoded strings.
        // Preserve them exactly while the registry remains the authority for
        // which field maps to which column.
        'number_list' || 'object_list' when value is String => value,
        'number_list' || 'object_list' => jsonEncode(value),
        'boolean' when field.persistence['encoding'] == 'integer_boolean' =>
          value == true ? 1 : 0,
        _ => value,
      };
    }
    for (final calculation in schema.calculations) {
      final column = _text(calculation.persistence[columnKey]);
      if (column != null && calculated.containsKey(calculation.fieldKey)) {
        result[column] = calculated[calculation.fieldKey];
      }
    }
    return result;
  }

  static Map<String, Object?> _fieldValuesFromRow(
    AgentStationSchema schema,
    Map<String, Object?> row, {
    required String columnKey,
  }) {
    final result = <String, Object?>{};
    for (final field in schema.fields) {
      final column = _text(field.persistence[columnKey]);
      if (column == null || !row.containsKey(column) || row[column] == null) {
        continue;
      }
      result[field.fieldKey] = _decodePersistenceValue(field, row[column]);
    }
    for (final calculation in schema.calculations) {
      final column = _text(calculation.persistence[columnKey]);
      if (column == null || !row.containsKey(column) || row[column] == null) {
        continue;
      }
      result[calculation.fieldKey] = row[column];
    }
    return result;
  }
}

Object? _decodePersistenceValue(AgentStationField field, Object? value) {
  if (field.type == 'boolean' &&
      field.persistence['encoding'] == 'integer_boolean' &&
      value is num) {
    return value != 0;
  }
  if ((field.type == 'number_list' || field.type == 'object_list') &&
      value is String) {
    try {
      return jsonDecode(value);
    } on FormatException {
      return value;
    }
  }
  return value;
}

List<AgentStationValueIssue> _validateField(
  AgentStationField field,
  Object? value,
  Map<String, Object?> allValues,
) {
  final issues = <AgentStationValueIssue>[];
  void issue(String code) {
    issues.add(AgentStationValueIssue(fieldKey: field.fieldKey, code: code));
  }

  final hasValidType = switch (field.type) {
    'integer' => value is int,
    'number' => value is num && value.isFinite,
    'string' => value is String,
    'boolean' => value is bool,
    'number_list' =>
      value is List && value.every((item) => item is num && item.isFinite),
    'object_list' => value is List && value.every((item) => item is Map),
    _ => false,
  };
  if (!hasValidType) {
    issue('invalid_type');
    return issues;
  }

  final validation = field.validation;
  if (value == 0 && !field.explicitZero) issue('zero_not_allowed');
  if (value is num) {
    final minimum = validation['min'];
    final maximum = validation['max'];
    if (minimum is num && value < minimum) issue('below_minimum');
    if (maximum is num && value > maximum) issue('above_maximum');
    final maximumKey = _text(validation['maxFieldKey']);
    final dynamicMaximum = maximumKey == null ? null : allValues[maximumKey];
    if (dynamicMaximum is num && value > dynamicMaximum) {
      issue('above_dynamic_maximum');
    }
  }
  if (value is String) {
    final minimumLength = validation['minLength'];
    if (minimumLength is num && value.trim().length < minimumLength) {
      issue('too_short');
    }
  }
  if (value is List) {
    final minimumItems = validation['minItems'];
    final maximumItems = validation['maxItems'];
    if (minimumItems is num && value.length < minimumItems) {
      issue('too_few_items');
    }
    if (maximumItems is num && value.length > maximumItems) {
      issue('too_many_items');
    }
  }
  if (field.type == 'number_list' && value is List) {
    final minimum = validation['itemMin'];
    final maximum = validation['itemMax'];
    if (value.cast<num>().any(
      (item) =>
          (minimum is num && item < minimum) ||
          (maximum is num && item > maximum),
    )) {
      issue('item_out_of_range');
    }
  }
  if (field.type == 'object_list' && value is List) {
    issues.addAll(
      _validateObjectItems(field.fieldKey, value, validation, allValues),
    );
  }
  final choices = validation['choices'];
  if (choices is List && !choices.contains(value)) issue('invalid_choice');
  return issues;
}

List<AgentStationValueIssue> _validateObjectItems(
  String fieldKey,
  List<Object?> items,
  Map<String, Object?> validation,
  Map<String, Object?> allValues,
) {
  final itemSchema = _map(validation['itemSchema']);
  final required = _strings(itemSchema['required']);
  final properties = _map(itemSchema['properties']);
  final issues = <AgentStationValueIssue>[];
  for (var index = 0; index < items.length; index++) {
    final item = _map(items[index]);
    for (final propertyKey in required) {
      if (item[propertyKey] == null) {
        issues.add(
          AgentStationValueIssue(
            fieldKey: fieldKey,
            code: 'item_required',
            itemIndex: index,
            propertyKey: propertyKey,
          ),
        );
      }
    }
    for (final entry in item.entries) {
      final rule = _map(properties[entry.key]);
      if (rule.isEmpty) {
        issues.add(
          AgentStationValueIssue(
            fieldKey: fieldKey,
            code: 'unknown_item_property',
            itemIndex: index,
            propertyKey: entry.key,
          ),
        );
        continue;
      }
      final value = entry.value;
      final validType = switch (rule['type']) {
        'integer' => value is int,
        'number' => value is num && value.isFinite,
        'string' => value is String,
        _ => false,
      };
      if (!validType) {
        issues.add(
          AgentStationValueIssue(
            fieldKey: fieldKey,
            code: 'invalid_item_type',
            itemIndex: index,
            propertyKey: entry.key,
          ),
        );
        continue;
      }
      if (value is num) {
        final minimum = rule['min'];
        if (minimum is num && value < minimum) {
          issues.add(
            AgentStationValueIssue(
              fieldKey: fieldKey,
              code: 'item_below_minimum',
              itemIndex: index,
              propertyKey: entry.key,
            ),
          );
        }
        final maximumKey = _text(rule['maxFieldKey']);
        final maximumPropertyKey = _text(rule['maxPropertyKey']);
        final maximum = maximumKey != null
            ? allValues[maximumKey]
            : maximumPropertyKey != null
            ? item[maximumPropertyKey]
            : rule['max'];
        if (maximum is num && value > maximum) {
          issues.add(
            AgentStationValueIssue(
              fieldKey: fieldKey,
              code: 'item_above_maximum',
              itemIndex: index,
              propertyKey: entry.key,
            ),
          );
        }
      }
      final choices = rule['choices'];
      if (choices is List && !choices.contains(value)) {
        issues.add(
          AgentStationValueIssue(
            fieldKey: fieldKey,
            code: 'invalid_item_choice',
            itemIndex: index,
            propertyKey: entry.key,
          ),
        );
      }
    }
  }
  return issues;
}

Object? _calculate(String kind, List<Object?> inputs) {
  return switch (kind) {
    'pasgar_score' => CalculationUtils.pasgarScore(
      (inputs.first as num).toInt(),
      inputs
          .skip(1)
          .cast<num>()
          .map((value) => value.toInt())
          .toList(growable: false),
    ),
    'percent_of' => CalculationUtils.percentOf(
      inputs[0] as num,
      inputs[1] as num,
    ),
    'sum' => inputs.cast<num>().fold<num>(0, (sum, value) => sum + value),
    'series_sample_size' => _numberList(inputs[0]).length,
    'series_average' => _average(_numberList(inputs[0])),
    'series_cv' => CalculationUtils.cvPercent(_numberList(inputs[0])),
    'series_uniformity_10pct' => _uniformity10(_numberList(inputs[0])),
    'yfbm_entry_count' => _objectList(inputs[0]).length,
    'yfbm_average_pct' => _average(_yfbmPercentages(inputs[0])),
    'yfbm_cv_pct' => CalculationUtils.cvPercent(_yfbmPercentages(inputs[0])),
    'culled_affected_pct' => CalculationUtils.percentOf(
      _objectList(
        inputs[1],
      ).fold<num>(0, (sum, item) => sum + (item['count'] as num)),
      inputs[0] as num,
    ),
    'culled_top_category' => _topCulledDefect(inputs[0])?.$1,
    'culled_top_subtype' => _topCulledDefect(inputs[0])?.$2,
    'fertility_from_infertile' => CalculationUtils.percentOf(
      (inputs[0] as num) - (inputs[1] as num),
      inputs[0] as num,
    ),
    'hof' => CalculationUtils.percentOf(
      inputs[0] as num,
      inputs[1] as num,
      allowAbove100: true,
    ),
    _ => throw UnsupportedError('Unsupported station calculation: $kind'),
  };
}

double _average(List<double> values) {
  return CalculationUtils.roundTo(CalculationUtils.average(values));
}

double _uniformity10(List<double> values) {
  final mean = CalculationUtils.average(values);
  return CalculationUtils.uniformityPercent(values, mean * 0.9, mean * 1.1);
}

List<double> _numberList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<num>()
      .map((item) => item.toDouble())
      .toList(growable: false);
}

List<Map<String, Object?>> _objectList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map(_map).toList(growable: false);
}

List<double> _yfbmPercentages(Object? value) {
  return _objectList(value)
      .map(
        (entry) => CalculationUtils.percentOf(
          entry['yolkWeight'] as num?,
          entry['chickWeight'] as num?,
        ),
      )
      .whereType<double>()
      .toList(growable: false);
}

(String, String)? _topCulledDefect(Object? value) {
  (String, String, num)? top;
  for (final entry in _objectList(value)) {
    final defect = _culledDefects[entry['id']];
    final count = entry['count'];
    if (defect == null || count is! num || !count.isFinite || count <= 0) {
      continue;
    }
    if (top == null || count > top.$3) {
      top = (defect.$1, defect.$2, count);
    }
  }
  return top == null ? null : (top.$1, top.$2);
}

const _culledDefects = <Object?, (String, String)>{
  'navel_open_unhealed': ('Navel', 'Open / unhealed navel'),
  'navel_string': ('Navel', 'String navel'),
  'navel_black_button': ('Navel', 'Black button'),
  'navel_residual_yolk_large_abdomen': (
    'Belly',
    'Residual yolk / large abdomen',
  ),
  'sticky_sticky_chick': ('Sticky', 'Sticky chick'),
  'sticky_dehydrated_burned_chick': ('Dehydrated', 'Dehydrated / burned chick'),
  'legs_spraddle_leg': ('Legs', 'Spraddle leg'),
  'legs_curled_toes': ('Legs', 'Curled toes'),
  'legs_twisted_legs_feet': ('Legs', 'Twisted legs / feet'),
  'legs_red_hocks': ('Legs', 'Red hocks'),
  'head_crossed_crooked_beak': ('Head', 'Crossed beak / crooked beak'),
  'head_missing_eye_one_eye': ('Head', 'Missing eye / one eye'),
  'head_exposed_brain': ('Head', 'Exposed brain'),
  'neuro_stargazer_nervous_signs': ('Neuro', 'Stargazer / nervous signs'),
  'neuro_wry_neck': ('Neuro', 'Wry neck'),
  'small_weak_small_chick': ('Small/Weak', 'Small chick'),
  'hair_chick_sparse_down': ('Hair Chick', 'Hair chick / sparse down'),
};

Map<String, Object?> _map(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<String> _strings(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

bool _positiveNumber(Object? value) {
  return value is num && value.isFinite && value > 0;
}
