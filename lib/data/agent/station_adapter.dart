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

enum AgentStationQualityTier { flag, warn, block }

class AgentStationQualityContext {
  const AgentStationQualityContext({
    required this.domain,
    required this.schemaVersion,
    required this.scopeType,
    required this.scopeKey,
    required this.sampleKey,
  });

  final String domain;
  final int schemaVersion;
  final String scopeType;
  final String scopeKey;
  final String sampleKey;
}

class AgentStationQualityFlag {
  const AgentStationQualityFlag({
    required this.tier,
    required this.schemaKey,
    required this.fieldKey,
    required this.code,
    this.itemIndex,
    this.propertyKey,
  });

  final AgentStationQualityTier tier;
  final String schemaKey;
  final String fieldKey;
  final String code;
  final int? itemIndex;
  final String? propertyKey;

  Map<String, Object?> toJson() => {
    'tier': tier.name.toUpperCase(),
    'schemaKey': schemaKey,
    'fieldKey': fieldKey,
    'code': code,
    if (itemIndex != null) 'itemIndex': itemIndex,
    if (propertyKey != null) 'propertyKey': propertyKey,
  };
}

class AgentStationQualityClassification {
  const AgentStationQualityClassification({
    required this.status,
    required this.flags,
  });

  final String status;
  final List<AgentStationQualityFlag> flags;

  String get canonicalJson =>
      jsonEncode([for (final flag in flags) flag.toJson()]);
}

abstract final class AgentStationAdapter {
  static AgentStationQualityClassification classifyQuality(
    AgentStationSchema schema,
    Map<String, Object?> values, {
    required AgentStationQualityContext context,
  }) {
    final flags = <AgentStationQualityFlag>[];
    final policy = AgentStationRegistry.qualityClassification;

    void policyFlag(Map<String, Object?> rule, {String fieldKey = r'$sample'}) {
      flags.add(
        AgentStationQualityFlag(
          tier: _qualityTier(rule['tier']),
          schemaKey: schema.schemaKey,
          fieldKey: fieldKey,
          code: rule['code']! as String,
        ),
      );
    }

    final structural = _map(policy['structural']);
    if (context.domain != schema.schemaKey) {
      policyFlag(_map(structural['domainMismatch']));
    }
    if (context.schemaVersion != schema.version) {
      policyFlag(_map(structural['schemaVersionMismatch']));
    }
    if (!schema.allowedLayers.contains(context.scopeType)) {
      policyFlag(_map(structural['scopeNotAllowed']));
    }
    if (_malformedQualityIdentity(context)) {
      policyFlag(_map(structural['malformedIdentity']));
    }

    final calculationKeys = {
      for (final calculation in schema.calculations) calculation.fieldKey,
    };
    final validation = validate(schema, {
      for (final entry in values.entries)
        if (!calculationKeys.contains(entry.key)) entry.key: entry.value,
    });
    final missingRule = _map(policy['missing']);
    for (final fieldKey in validation.missing) {
      policyFlag(missingRule, fieldKey: fieldKey);
    }
    final issueTiers = _map(policy['validationIssueTiers']);
    for (final issue in validation.issues) {
      final tierName = issueTiers[issue.code]?.toString();
      if (tierName == null) {
        throw StateError(
          'Registry quality policy does not classify ${issue.code}',
        );
      }
      flags.add(
        AgentStationQualityFlag(
          tier: _qualityTier(tierName),
          schemaKey: schema.schemaKey,
          fieldKey: issue.fieldKey,
          code: issue.code,
          itemIndex: issue.itemIndex,
          propertyKey: issue.propertyKey,
        ),
      );
    }
    final malformedInputKeys = validation.issues
        .where(
          (issue) =>
              issue.code == 'invalid_type' ||
              issue.code == 'invalid_item_type' ||
              issue.code == 'item_required',
        )
        .map((issue) => issue.fieldKey)
        .toSet();

    final missingRawRule = _map(policy['missingRawEvidence']);
    for (final field in schema.fields) {
      if (field.type != 'number_list' && field.type != 'object_list') continue;
      if (values[field.fieldKey] == null &&
          schema.calculations.any(
            (calculation) => values.containsKey(calculation.fieldKey),
          )) {
        policyFlag(missingRawRule, fieldKey: field.fieldKey);
      }
    }

    final mismatchRule = _map(policy['derivedCacheMismatch']);
    for (final calculation in schema.calculations) {
      if (!values.containsKey(calculation.fieldKey)) continue;
      final inputsPresent = calculation.inputFieldKeys.every(
        (key) => values[key] != null,
      );
      if (!inputsPresent ||
          calculation.inputFieldKeys.any(malformedInputKeys.contains)) {
        policyFlag(mismatchRule, fieldKey: calculation.fieldKey);
        continue;
      }
      final calculated = _calculate(
        calculation.kind,
        calculation.inputFieldKeys.map((key) => values[key]).toList(),
      );
      if (!_qualityValuesEqual(values[calculation.fieldKey], calculated)) {
        policyFlag(mismatchRule, fieldKey: calculation.fieldKey);
      }
    }

    final unique = <String, AgentStationQualityFlag>{};
    for (final flag in flags) {
      unique[jsonEncode(flag.toJson())] = flag;
    }
    final ordered = unique.values.toList()
      ..sort((left, right) {
        final tier = left.tier.index.compareTo(right.tier.index);
        if (tier != 0) return tier;
        final schema = left.schemaKey.compareTo(right.schemaKey);
        if (schema != 0) return schema;
        final field = left.fieldKey.compareTo(right.fieldKey);
        if (field != 0) return field;
        final code = left.code.compareTo(right.code);
        if (code != 0) return code;
        final item = (left.itemIndex ?? -1).compareTo(right.itemIndex ?? -1);
        if (item != 0) return item;
        return (left.propertyKey ?? '').compareTo(right.propertyKey ?? '');
      });
    final status =
        ordered.any((flag) => flag.tier == AgentStationQualityTier.block)
        ? 'BLOCK'
        : ordered.any((flag) => flag.tier == AgentStationQualityTier.warn)
        ? 'WARN'
        : ordered.isNotEmpty
        ? 'FLAG'
        : 'OK';
    return AgentStationQualityClassification(
      status: status,
      flags: List.unmodifiable(ordered),
    );
  }

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
      if (inputs.any((value) => value == null)) continue;
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
    'culled_affected_pct' =>
      (inputs[0] as num) <= 0
          ? null
          : _objectList(
                  inputs[1],
                ).fold<num>(0, (sum, item) => sum + (item['count'] as num)) /
                (inputs[0] as num) *
                100,
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

AgentStationQualityTier _qualityTier(Object? value) {
  return switch (value?.toString()) {
    'BLOCK' => AgentStationQualityTier.block,
    'WARN' => AgentStationQualityTier.warn,
    'FLAG' => AgentStationQualityTier.flag,
    _ => throw StateError('Unknown registry quality tier: $value'),
  };
}

bool _malformedQualityIdentity(AgentStationQualityContext context) {
  if (context.domain.trim().isEmpty ||
      context.schemaVersion < 1 ||
      context.scopeType.trim().isEmpty ||
      context.sampleKey.trim().isEmpty) {
    return true;
  }
  try {
    return jsonDecode(context.scopeKey) is! Map;
  } on FormatException {
    return true;
  }
}

bool _qualityValuesEqual(Object? left, Object? right) {
  if (left is num && right is num) {
    return (left.toDouble() - right.toDouble()).abs() < 0.000000001;
  }
  try {
    return jsonEncode(left) == jsonEncode(right);
  } on JsonUnsupportedObjectError {
    return left == right;
  }
}

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
