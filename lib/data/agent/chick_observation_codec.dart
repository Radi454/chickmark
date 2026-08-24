import 'dart:convert';

import '../models/chick_quality_observation.dart';
import 'station_registry.dart';

abstract final class ChickObservationCodec {
  static bool isValid(
    AgentStationSchema schema,
    ChickQualityObservation observation,
  ) {
    if (observation.domain != schema.schemaKey ||
        observation.id !=
            stableId(
              observation.sampleId,
              observation.domain,
              observation.kind,
              observation.observationKey,
              observation.ordinal,
            )) {
      return false;
    }
    return schema.fields.any((field) => _matchesField(field, observation));
  }

  static Map<String, Object?> overlayReconstructed(
    AgentStationSchema schema,
    Map<String, Object?> contextual,
    Map<String, Object?> reconstructed,
  ) {
    final result = <String, Object?>{...contextual};
    for (final field in schema.fields) {
      if (!reconstructed.containsKey(field.fieldKey)) continue;
      final rawValue = reconstructed[field.fieldKey];
      final descriptor = field.observation;
      final ignored =
          (descriptor?['ignoredProperties'] as List?)
              ?.map((item) => item.toString())
              .toList() ??
          const <String>[];
      final keyProperty = descriptor?['keyProperty'] as String?;
      if (ignored.isEmpty || keyProperty == null || rawValue is! List) {
        result[field.fieldKey] = rawValue;
        continue;
      }
      final byKey = <String, Map<String, Object?>>{};
      for (final rawItem in _list(contextual[field.fieldKey])) {
        final item = _mapOrNull(rawItem);
        final itemKey = item?[keyProperty];
        if (item != null && itemKey is String) byKey[itemKey] = item;
      }
      final merged = <Map<String, Object?>>[];
      for (final rawItem in rawValue) {
        final item = _mapOrNull(rawItem);
        if (item == null) continue;
        final cached = byKey[item[keyProperty]];
        merged.add({
          for (final key in ignored)
            if (cached?.containsKey(key) ?? false) key: cached![key],
          ...item,
        });
      }
      result[field.fieldKey] = merged;
    }
    return result;
  }

  static bool canRoundTrip(
    AgentStationSchema schema,
    Map<String, Object?> values,
  ) {
    final relevant = <String, Object?>{};
    for (final field in schema.fields) {
      if (field.observation == null || !values.containsKey(field.fieldKey)) {
        continue;
      }
      final value = values[field.fieldKey];
      if (value == null) continue;
      final normalized = _normalizeFieldValue(field, value);
      if (normalized == null) return false;
      relevant[field.fieldKey] = normalized;
    }
    if (relevant.isEmpty) return false;
    final probe = extract(
      schema: schema,
      sampleId: 'round-trip-probe',
      customerId: 'round-trip-probe',
      sessionId: 'round-trip-probe',
      values: relevant,
      observedAt: DateTime.utc(2000),
    );
    final reconstructed = reconstruct(schema, probe);
    return jsonEncode(reconstructed) == jsonEncode(relevant);
  }

  static List<ChickQualityObservation> extract({
    required AgentStationSchema schema,
    required String sampleId,
    required String customerId,
    required String sessionId,
    required Map<String, Object?> values,
    required DateTime observedAt,
    String? source,
    String syncStatus = 'pending',
  }) {
    final observations = <ChickQualityObservation>[];
    for (final field in schema.fields) {
      final descriptor = field.observation;
      if (descriptor == null || !values.containsKey(field.fieldKey)) continue;
      final value = values[field.fieldKey];
      if (value == null) continue;
      final kind = descriptor['kind']! as String;

      void add({required String key, required int? ordinal, Object? rawValue}) {
        final numeric = rawValue is num ? rawValue.toDouble() : null;
        final text = rawValue is String ? rawValue : null;
        if (numeric == null && text == null) return;
        observations.add(
          ChickQualityObservation(
            id: stableId(sampleId, schema.schemaKey, kind, key, ordinal),
            sampleId: sampleId,
            customerId: customerId,
            sessionId: sessionId,
            domain: schema.schemaKey,
            kind: kind,
            observationKey: key,
            ordinal: ordinal,
            numericValue: numeric,
            textValue: text,
            unit: field.unit,
            qualityFlags: '[]',
            source: source,
            observedAt: observedAt,
            createdAt: observedAt,
            updatedAt: DateTime.now().toUtc(),
            syncStatus: syncStatus,
            dirtyAt: syncStatus == 'synced' ? null : DateTime.now().toUtc(),
          ),
        );
      }

      if (field.type == 'number_list') {
        final list = _list(value);
        for (var index = 0; index < list.length; index++) {
          add(
            key: descriptor['key']! as String,
            ordinal: index,
            rawValue: list[index],
          );
        }
        continue;
      }
      if (field.type == 'object_list') {
        final list = _list(value);
        final propertyDescriptors = _mapOrNull(descriptor['properties']);
        if (propertyDescriptors != null) {
          for (var index = 0; index < list.length; index++) {
            final item = _mapOrNull(list[index]);
            if (item == null) continue;
            for (final entry in propertyDescriptors.entries) {
              final property = _map(entry.value);
              add(
                key: property['key']! as String,
                ordinal: index,
                rawValue: item[entry.key],
              );
            }
          }
          continue;
        }
        final keyProperty = descriptor['keyProperty']! as String;
        final valueProperty = descriptor['valueProperty']! as String;
        final prefix = descriptor['keyPrefix']! as String;
        final presenceKey = descriptor['presenceKey'] as String?;
        if (presenceKey != null) {
          add(key: presenceKey, ordinal: null, rawValue: 0);
        }
        for (var index = 0; index < list.length; index++) {
          final item = _mapOrNull(list[index]);
          final itemKey = item?[keyProperty];
          if (item == null || itemKey is! String || itemKey.isEmpty) continue;
          add(
            key: '$prefix$itemKey',
            ordinal: index,
            rawValue: item[valueProperty],
          );
        }
        continue;
      }
      add(key: descriptor['key']! as String, ordinal: null, rawValue: value);
    }
    observations.sort(_compare);
    return List.unmodifiable(observations);
  }

  static Map<String, Object?> reconstruct(
    AgentStationSchema schema,
    Iterable<ChickQualityObservation> source,
  ) {
    final observations =
        source.where((item) => item.domain == schema.schemaKey).toList()
          ..sort(_compare);
    final result = <String, Object?>{};
    for (final field in schema.fields) {
      final descriptor = field.observation;
      if (descriptor == null) continue;
      final kind = descriptor['kind']! as String;
      final matchingKind = observations.where(
        (item) => item.kind == kind && _matchesField(field, item),
      );
      if (field.type == 'number_list') {
        final key = descriptor['key']! as String;
        final matching =
            matchingKind.where((item) => item.observationKey == key).toList()
              ..sort(
                (left, right) =>
                    (left.ordinal ?? -1).compareTo(right.ordinal ?? -1),
              );
        if (_hasDenseOrdinals(matching) &&
            matching.every((item) => item.numericValue != null)) {
          result[field.fieldKey] = matching
              .map((item) => item.numericValue!)
              .toList();
        }
        continue;
      }
      if (field.type == 'object_list') {
        final propertyDescriptors = _mapOrNull(descriptor['properties']);
        if (propertyDescriptors != null) {
          final byOrdinal = <int, Map<String, Object?>>{};
          for (final entry in propertyDescriptors.entries) {
            final property = _map(entry.value);
            final key = property['key']! as String;
            for (final item in matchingKind.where(
              (candidate) => candidate.observationKey == key,
            )) {
              final ordinal = item.ordinal;
              if (ordinal == null) continue;
              (byOrdinal[ordinal] ??= <String, Object?>{})[entry.key] =
                  item.numericValue ?? item.textValue;
            }
          }
          if (byOrdinal.isNotEmpty) {
            final ordinals = byOrdinal.keys.toList()..sort();
            final requiredKeys = propertyDescriptors.keys.toSet();
            if (_isDense(ordinals) &&
                byOrdinal.values.every(
                  (item) => item.keys.toSet().containsAll(requiredKeys),
                )) {
              result[field.fieldKey] = [
                for (final ordinal in ordinals) byOrdinal[ordinal]!,
              ];
            }
          }
          continue;
        }
        final prefix = descriptor['keyPrefix']! as String;
        final presenceKey = descriptor['presenceKey'] as String?;
        final keyProperty = descriptor['keyProperty']! as String;
        final valueProperty = descriptor['valueProperty']! as String;
        final itemSchema = _map(field.validation['itemSchema']);
        final properties = _map(itemSchema['properties']);
        final valueSchema = _map(properties[valueProperty]);
        final keyed =
            matchingKind
                .where(
                  (item) =>
                      item.observationKey.startsWith(prefix) &&
                      item.observationKey != presenceKey,
                )
                .toList()
              ..sort(_compare);
        keyed.sort(
          (left, right) => (left.ordinal ?? -1).compareTo(right.ordinal ?? -1),
        );
        if (keyed.isNotEmpty) {
          if (_hasDenseOrdinals(keyed) &&
              keyed.every(
                (item) => item.numericValue != null || item.textValue != null,
              )) {
            result[field.fieldKey] = [
              for (final item in keyed)
                {
                  keyProperty: item.observationKey.substring(prefix.length),
                  valueProperty: _typedNumeric(
                    item.numericValue,
                    valueSchema['type'],
                  ),
                },
            ];
          }
        } else if (presenceKey != null &&
            matchingKind.any((item) => item.observationKey == presenceKey)) {
          result[field.fieldKey] = const <Object?>[];
        }
        continue;
      }
      final key = descriptor['key']! as String;
      final matching = matchingKind.where(
        (item) => item.observationKey == key && item.ordinal == null,
      );
      if (matching.isEmpty) continue;
      final item = matching.first;
      result[field.fieldKey] = field.type == 'string'
          ? item.textValue
          : _typedNumeric(item.numericValue, field.type);
    }
    result.removeWhere((_, value) => value == null);
    return result;
  }

  static String stableId(
    String sampleId,
    String domain,
    String kind,
    String key,
    int? ordinal,
  ) {
    final canonical = jsonEncode([sampleId, domain, kind, key, ordinal]);
    return 'obs_${base64Url.encode(utf8.encode(canonical)).replaceAll('=', '')}';
  }

  static int _compare(
    ChickQualityObservation left,
    ChickQualityObservation right,
  ) {
    final kind = left.kind.compareTo(right.kind);
    if (kind != 0) return kind;
    final key = left.observationKey.compareTo(right.observationKey);
    if (key != 0) return key;
    return (left.ordinal ?? -1).compareTo(right.ordinal ?? -1);
  }

  static Object? _typedNumeric(double? value, Object? type) {
    if (value == null) return null;
    return type == 'integer' ? value.toInt() : value;
  }

  static Object? _normalizeFieldValue(AgentStationField field, Object? value) {
    if (field.type == 'integer') return value is int ? value : null;
    if (field.type == 'number') {
      return value is num && value.isFinite ? value.toDouble() : null;
    }
    if (field.type == 'string') return value is String ? value : null;
    final list = _list(value);
    if (value is! List && value is! String) return null;
    if (field.type == 'number_list') {
      if (list.any((item) => item is! num || !item.isFinite)) return null;
      return list.cast<num>().map((item) => item.toDouble()).toList();
    }
    if (field.type != 'object_list') return null;
    final itemSchema = _map(field.validation['itemSchema']);
    final required = (itemSchema['required']! as List).cast<String>();
    final properties = _map(itemSchema['properties']);
    final descriptor = field.observation!;
    final ignored =
        (descriptor['ignoredProperties'] as List?)
            ?.map((item) => item.toString())
            .toSet() ??
        const <String>{};
    final normalized = <Map<String, Object?>>[];
    for (final rawItem in list) {
      final item = _mapOrNull(rawItem);
      if (item == null || required.any((key) => !item.containsKey(key))) {
        return null;
      }
      if (item.keys.any(
        (key) => !properties.containsKey(key) && !ignored.contains(key),
      )) {
        return null;
      }
      final normalizedItem = <String, Object?>{};
      for (final propertyEntry in properties.entries) {
        if (!item.containsKey(propertyEntry.key)) continue;
        final definition = _map(propertyEntry.value);
        final type = definition['type'];
        final normalizedValue = switch (type) {
          'integer' when item[propertyEntry.key] is int =>
            item[propertyEntry.key],
          'number'
              when item[propertyEntry.key] is num &&
                  (item[propertyEntry.key] as num).isFinite =>
            (item[propertyEntry.key] as num).toDouble(),
          'string' when item[propertyEntry.key] is String =>
            item[propertyEntry.key],
          _ => null,
        };
        if (normalizedValue == null) return null;
        normalizedItem[propertyEntry.key] = normalizedValue;
      }
      normalized.add(normalizedItem);
    }
    return normalized;
  }

  static List<Object?> _list(Object? value) {
    if (value is List) return List<Object?>.from(value);
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) return List<Object?>.from(decoded);
      } on FormatException {
        return const [];
      }
    }
    return const [];
  }

  static Map<String, Object?> _map(Object? value) =>
      (value! as Map).map((key, item) => MapEntry(key.toString(), item));

  static Map<String, Object?>? _mapOrNull(Object? value) => value is Map
      ? value.map((key, item) => MapEntry(key.toString(), item))
      : null;

  static bool _hasDenseOrdinals(List<ChickQualityObservation> items) =>
      items.isNotEmpty &&
      items.every((item) => item.ordinal != null) &&
      _isDense(items.map((item) => item.ordinal!).toList());

  static bool _isDense(List<int> ordinals) {
    if (ordinals.isEmpty) return false;
    for (var index = 0; index < ordinals.length; index++) {
      if (ordinals[index] != index) return false;
    }
    return true;
  }

  static bool _matchesField(
    AgentStationField field,
    ChickQualityObservation item,
  ) {
    final descriptor = field.observation;
    if (descriptor == null ||
        item.kind != descriptor['kind'] ||
        item.unit != field.unit) {
      return false;
    }
    bool numeric({bool integer = false}) =>
        item.numericValue != null &&
        item.textValue == null &&
        (!integer || item.numericValue! % 1 == 0);
    bool text() => item.textValue != null && item.numericValue == null;

    if (field.type == 'number_list') {
      return item.observationKey == descriptor['key'] &&
          item.ordinal != null &&
          numeric();
    }
    if (field.type == 'object_list') {
      final properties = _mapOrNull(descriptor['properties']);
      if (properties != null) {
        for (final rawProperty in properties.values) {
          final property = _map(rawProperty);
          if (item.observationKey != property['key'] || item.ordinal == null) {
            continue;
          }
          return property['valueType'] == 'text' ? text() : numeric();
        }
        return false;
      }
      final presenceKey = descriptor['presenceKey'] as String?;
      if (item.observationKey == presenceKey) {
        return item.ordinal == null && numeric() && item.numericValue == 0;
      }
      final prefix = descriptor['keyPrefix']! as String;
      if (!item.observationKey.startsWith(prefix) ||
          item.observationKey.length == prefix.length ||
          item.ordinal == null) {
        return false;
      }
      final itemSchema = _map(field.validation['itemSchema']);
      final itemProperties = _map(itemSchema['properties']);
      final valueProperty = descriptor['valueProperty']! as String;
      final valueSchema = _map(itemProperties[valueProperty]);
      return valueSchema['type'] == 'string'
          ? text()
          : numeric(integer: valueSchema['type'] == 'integer');
    }
    if (item.observationKey != descriptor['key'] || item.ordinal != null) {
      return false;
    }
    return field.type == 'string'
        ? text()
        : numeric(integer: field.type == 'integer');
  }
}
