import 'dart:convert';

import 'station_adapter.dart';
import 'station_registry.dart';

abstract final class ChickQualityClassifier {
  static AgentStationQualityClassification classifyRow(
    String tableName,
    Map<String, Object?> row,
  ) {
    if (tableName != 'chick_quality' && tableName != 'chick_weights') {
      throw ArgumentError.value(tableName, 'tableName', 'Not a Chick table');
    }
    final rowDomain = row['domain']?.toString() ?? '';
    final schemas = AgentStationRegistry.schemas.where((schema) {
      if (schema.stationKey != 'chicks' ||
          schema.persistence.first.localTable != tableName) {
        return false;
      }
      return rowDomain == 'chicks.legacy_combined' ||
          rowDomain.isEmpty ||
          rowDomain == schema.schemaKey;
    });
    final flags = <AgentStationQualityFlag>[];
    var classifiedSchema = false;
    for (final schema in schemas) {
      final values = AgentStationAdapter.fieldValuesFromLocalRow(schema, row);
      for (final calculation in schema.calculations) {
        final column = calculation.persistence['localColumn']?.toString();
        if (column != null && row[column] != null) {
          values[calculation.fieldKey] = row[column];
        }
      }
      if (values.isEmpty) continue;
      classifiedSchema = true;
      final result = AgentStationAdapter.classifyQuality(
        schema,
        values,
        context: AgentStationQualityContext(
          domain: rowDomain == 'chicks.legacy_combined'
              ? schema.schemaKey
              : rowDomain,
          schemaVersion: row['schemaVersion'] is int
              ? row['schemaVersion']! as int
              : 0,
          scopeType: row['scopeType']?.toString() ?? '',
          scopeKey: row['scopeKey']?.toString() ?? '',
          sampleKey: row['sampleKey']?.toString() ?? '',
        ),
      );
      flags.addAll(result.flags);
    }

    if (!classifiedSchema) {
      flags.add(
        _policyFlag(
          AgentStationRegistry.qualityClassification['missingRawEvidence'],
          schemaKey: rowDomain.isEmpty ? 'chicks.unknown' : rowDomain,
        ),
      );
    }
    if (rowDomain != 'chicks.legacy_combined' &&
        !AgentStationRegistry.schemas.any(
          (schema) =>
              schema.stationKey == 'chicks' &&
              schema.persistence.first.localTable == tableName &&
              schema.schemaKey == rowDomain,
        )) {
      final structural = Map<String, Object?>.from(
        AgentStationRegistry.qualityClassification['structural']! as Map,
      );
      flags.add(
        _policyFlag(
          structural['domainMismatch'],
          schemaKey: rowDomain.isEmpty ? 'chicks.unknown' : rowDomain,
        ),
      );
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
        return left.code.compareTo(right.code);
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

  static AgentStationQualityFlag _policyFlag(
    Object? rawRule, {
    required String schemaKey,
  }) {
    final rule = Map<String, Object?>.from(rawRule! as Map);
    final tier = switch (rule['tier']) {
      'FLAG' => AgentStationQualityTier.flag,
      'WARN' => AgentStationQualityTier.warn,
      'BLOCK' => AgentStationQualityTier.block,
      _ => throw StateError('Unknown registry quality tier: ${rule['tier']}'),
    };
    return AgentStationQualityFlag(
      tier: tier,
      schemaKey: schemaKey,
      fieldKey: r'$sample',
      code: rule['code']! as String,
    );
  }

  static Map<String, Object?> stampRow(
    String tableName,
    Map<String, Object?> row,
  ) {
    final result = classifyRow(tableName, row);
    return {
      ...row,
      'qualityStatus': result.status,
      'qualityFlags': result.canonicalJson,
    };
  }
}
