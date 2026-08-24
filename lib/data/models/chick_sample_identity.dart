import 'dart:convert';

import 'panel_sample_schema.dart';

abstract final class ChickSampleIdentity {
  static String buildScopeKey({
    required SamplingLayer scopeType,
    String? house,
    String? setter,
    String? hatcher,
    String? trolley,
    String? tray,
    String? position,
  }) {
    if (scopeType == SamplingLayer.pool) return '{}';

    final normalized = <String, String>{};
    void add(String key, String? raw) {
      final value = _text(raw);
      if (value != null) normalized[key] = value;
    }

    add('house', house);
    add('setter', setter);
    add('hatcher', hatcher);
    add('trolley', trolley);
    add('tray', tray);
    add('position', position);
    for (final requiredKey in _requiredScopeKeys(scopeType)) {
      if (!normalized.containsKey(requiredKey)) {
        throw ArgumentError.value(
          normalized[requiredKey],
          requiredKey,
          '${scopeType.dbValue} scope requires $requiredKey',
        );
      }
    }
    final sorted = <String, String>{
      for (final key in normalized.keys.toList()..sort()) key: normalized[key]!,
    };
    return jsonEncode(sorted);
  }

  static String buildLegacyScopeKey({
    required SamplingLayer scopeType,
    String? house,
    String? setter,
    String? hatcher,
    String? trolley,
    String? tray,
    String? position,
  }) {
    if (scopeType == SamplingLayer.pool) return '{}';
    final values = <String, String?>{
      'house': _text(house),
      'setter': _text(setter),
      'hatcher': _text(hatcher),
      'trolley': _text(trolley),
      'tray': _text(tray),
      'position': _text(position),
    };
    final includedKeys = <String>{
      ..._requiredScopeKeys(scopeType),
      ...values.entries
          .where((entry) => entry.value != null)
          .map((entry) => entry.key),
    }.toList()..sort();
    return jsonEncode({for (final key in includedKeys) key: values[key]});
  }

  static String buildSampleKey({
    required String domain,
    required String sessionId,
    required SamplingLayer scopeType,
    required String scopeKey,
    required int replicate,
  }) {
    final normalizedDomain = _text(domain);
    final normalizedSessionId = _text(sessionId);
    if (normalizedDomain == null) {
      throw ArgumentError.value(domain, 'domain', 'must not be blank');
    }
    if (normalizedSessionId == null) {
      throw ArgumentError.value(sessionId, 'sessionId', 'must not be blank');
    }
    if (_text(scopeKey) == null) {
      throw ArgumentError.value(scopeKey, 'scopeKey', 'must not be blank');
    }
    if (replicate < 1) {
      throw ArgumentError.value(replicate, 'replicate', 'must be positive');
    }
    final encoded = utf8.encode(
      jsonEncode([
        normalizedDomain,
        normalizedSessionId,
        scopeType.dbValue,
        scopeKey,
        replicate,
      ]),
    );
    return base64Url.encode(encoded).replaceAll('=', '');
  }

  static List<String> _requiredScopeKeys(SamplingLayer scopeType) {
    return switch (scopeType) {
      SamplingLayer.pool => const [],
      SamplingLayer.house => const ['house'],
      SamplingLayer.setter => const ['setter'],
      SamplingLayer.hatcher => const ['hatcher'],
      SamplingLayer.setterHatcher => const ['setter', 'hatcher'],
      SamplingLayer.trolley => const ['trolley'],
      SamplingLayer.tray => const ['tray'],
    };
  }

  static String? _text(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
