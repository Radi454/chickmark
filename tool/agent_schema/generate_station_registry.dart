import 'dart:convert';
import 'dart:io';

import 'package:hatchaudit/data/models/panel_sample_schema.dart';

const _sourcePath = 'tool/agent_schema/station_registry.json';
const _dartOutputPath = 'lib/data/agent/station_registry.g.dart';
const _typeScriptOutputPath =
    'supabase/functions/_shared/station_registry.generated.ts';

void main(List<String> arguments) {
  final checkOnly = arguments.contains('--check');
  final source = File(_sourcePath);
  if (!source.existsSync()) {
    stderr.writeln('Missing canonical station registry: $_sourcePath');
    exitCode = 2;
    return;
  }

  final decoded = jsonDecode(source.readAsStringSync());
  final registry = _object(decoded, 'registry');
  _validateRegistry(registry);

  final canonicalJson = const JsonEncoder.withIndent('  ').convert(registry);
  final outputs = <String, String>{
    _dartOutputPath: _dartOutput(canonicalJson),
    _typeScriptOutputPath: _typeScriptOutput(canonicalJson),
  };

  var stale = false;
  for (final entry in outputs.entries) {
    final file = File(entry.key);
    if (checkOnly) {
      if (!file.existsSync() || file.readAsStringSync() != entry.value) {
        stderr.writeln('Generated station registry is stale: ${entry.key}');
        stale = true;
      }
      continue;
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
  if (stale) exitCode = 1;
}

void _validateRegistry(Map<String, Object?> registry) {
  final version = registry['registryVersion'];
  if (version is! int || version < 1) {
    throw const FormatException('registryVersion must be a positive integer');
  }
  final parity = _object(
    registry['calculationParityVectors'],
    'calculationParityVectors',
  );
  for (final key in const [
    'percentOf',
    'cvPercent',
    'uniformityPercent',
    'pasgarScore',
    'fertility',
    'hatchability',
    'hof',
  ]) {
    if (_list(parity[key], 'calculationParityVectors.$key').isEmpty) {
      throw FormatException('calculationParityVectors.$key must not be empty');
    }
  }
  final stations = _list(registry['stations'], 'stations');
  if (stations.isEmpty) {
    throw const FormatException('stations must not be empty');
  }

  final identities = <String>{};
  for (final rawStation in stations) {
    final station = _object(rawStation, 'station');
    final schemaKey = _text(station['schemaKey'], 'schemaKey');
    final schemaVersion = station['version'];
    if (schemaVersion is! int || schemaVersion < 1) {
      throw FormatException('$schemaKey version must be positive');
    }
    if (!identities.add('$schemaKey@$schemaVersion')) {
      throw FormatException(
        'Duplicate station schema: $schemaKey@$schemaVersion',
      );
    }
    _localized(station['names'], '$schemaKey names');
    _aliases(station['aliases'], '$schemaKey aliases');
    if (_list(station['sectorKeys'], '$schemaKey sectorKeys').isEmpty) {
      throw FormatException('$schemaKey requires a sector');
    }
    if (_list(station['allowedLayers'], '$schemaKey allowedLayers').isEmpty) {
      throw FormatException('$schemaKey requires an allowed layer');
    }

    final fields = _list(station['fields'], '$schemaKey fields');
    if (fields.isEmpty) {
      throw FormatException('$schemaKey requires input fields');
    }
    final fieldKeys = <String>{};
    final localColumns = <String>{};
    final remoteColumns = <String>{};
    for (final rawField in fields) {
      final field = _object(rawField, '$schemaKey field');
      final fieldKey = _text(field['fieldKey'], '$schemaKey fieldKey');
      if (!fieldKeys.add(fieldKey)) {
        throw FormatException('$schemaKey repeats field $fieldKey');
      }
      _localized(field['names'], '$schemaKey.$fieldKey names');
      _aliases(field['aliases'], '$schemaKey.$fieldKey aliases');
      final type = _text(field['type'], '$schemaKey.$fieldKey type');
      if (!_inputTypes.contains(type)) {
        throw FormatException(
          '$schemaKey.$fieldKey has unsupported type $type',
        );
      }
      _text(field['unit'], '$schemaKey.$fieldKey unit');
      if (field['required'] is! bool || field['explicitZero'] is! bool) {
        throw FormatException(
          '$schemaKey.$fieldKey requires boolean required/explicitZero',
        );
      }
      final validation = _object(
        field['validation'],
        '$schemaKey.$fieldKey validation',
      );
      for (final dependencyKey in const [
        'maxFieldKey',
        'requiredWhenPositiveFieldKey',
      ]) {
        final dependency = validation[dependencyKey];
        if (dependency != null &&
            (dependency is! String || !fieldKeys.contains(dependency))) {
          throw FormatException(
            '$schemaKey.$fieldKey references unknown $dependencyKey '
            '$dependency',
          );
        }
      }
      _persistence(field['persistence'], '$schemaKey.$fieldKey persistence');
      _claimPersistenceColumns(
        field['persistence'],
        '$schemaKey.$fieldKey',
        localColumns,
        remoteColumns,
      );
    }

    final completion = _object(station['completion'], '$schemaKey completion');
    final requiredKeys = <String>{};
    for (final requiredKey in _list(
      completion['requiredFieldKeys'],
      '$schemaKey requiredFieldKeys',
    )) {
      if (requiredKey is! String || !fieldKeys.contains(requiredKey)) {
        throw FormatException(
          '$schemaKey completion references unknown field $requiredKey',
        );
      }
      requiredKeys.add(requiredKey);
    }
    for (final rawField in fields) {
      final field = _object(rawField, '$schemaKey field');
      final fieldKey = field['fieldKey'] as String;
      if ((field['required'] as bool) != requiredKeys.contains(fieldKey)) {
        throw FormatException(
          '$schemaKey.$fieldKey required flag and completion disagree',
        );
      }
    }
    final tableMappings = <Map<String, Object?>>[];
    for (final rawMapping in _list(
      station['persistence'],
      '$schemaKey persistence',
    )) {
      final mapping = _object(rawMapping, '$schemaKey table mapping');
      final localTable = _text(mapping['localTable'], '$schemaKey localTable');
      final remoteTable = _text(
        mapping['remoteTable'],
        '$schemaKey remoteTable',
      );
      PanelSampleSchema.byTable(localTable);
      if (remoteTable != localTable) {
        throw FormatException(
          '$schemaKey maps mismatched panel tables '
          '$localTable/$remoteTable',
        );
      }
      tableMappings.add(mapping);
    }
    final availableKeys = <String>{...fieldKeys};
    final calculationKeys = <String>{};
    for (final rawCalculation in _list(
      station['calculations'],
      '$schemaKey calculations',
    )) {
      final calculation = _object(rawCalculation, '$schemaKey calculation');
      final fieldKey = _text(
        calculation['fieldKey'],
        '$schemaKey calculated fieldKey',
      );
      if (fieldKeys.contains(fieldKey) || !calculationKeys.add(fieldKey)) {
        throw FormatException(
          '$schemaKey repeats or directly inputs calculated field $fieldKey',
        );
      }
      final kind = _text(
        calculation['kind'],
        '$schemaKey.$fieldKey calculation kind',
      );
      if (!_calculationKinds.contains(kind)) {
        throw FormatException(
          '$schemaKey.$fieldKey has unsupported calculation $kind',
        );
      }
      final inputKeys = _list(
        calculation['inputFieldKeys'],
        '$schemaKey.$fieldKey inputFieldKeys',
      );
      if (inputKeys.isEmpty ||
          inputKeys.any(
            (key) => key is! String || !availableKeys.contains(key),
          )) {
        throw FormatException(
          '$schemaKey.$fieldKey calculation has unknown input',
        );
      }
      _text(calculation['unit'], '$schemaKey.$fieldKey calculation unit');
      _persistence(
        calculation['persistence'],
        '$schemaKey.$fieldKey persistence',
      );
      _claimPersistenceColumns(
        calculation['persistence'],
        '$schemaKey.$fieldKey',
        localColumns,
        remoteColumns,
      );
      availableKeys.add(fieldKey);
    }
    final mappedTables = tableMappings
        .map((mapping) => mapping['localTable']! as String)
        .toSet();
    for (final rawField in [
      ...fields,
      ..._list(station['calculations'], '$schemaKey calculations'),
    ]) {
      final field = _object(rawField, '$schemaKey persisted field');
      final persistence = _object(
        field['persistence'],
        '$schemaKey persisted field mapping',
      );
      final localColumn = persistence['localColumn']! as String;
      final remoteColumn = persistence['remoteColumn']! as String;
      if (!_columnExists(mappedTables, localColumn)) {
        throw FormatException(
          '$schemaKey maps unknown panel column $localColumn',
        );
      }
      if (_snakeCase(localColumn) != remoteColumn) {
        throw FormatException(
          '$schemaKey.$localColumn remote column must be '
          '${_snakeCase(localColumn)}',
        );
      }
    }
  }
}

const _inputTypes = {
  'integer',
  'number',
  'string',
  'boolean',
  'number_list',
  'object_list',
};

const _calculationKinds = {
  'pasgar_score',
  'percent_of',
  'sum',
  'series_sample_size',
  'series_average',
  'series_cv',
  'series_uniformity_10pct',
  'yfbm_entry_count',
  'yfbm_average_pct',
  'yfbm_cv_pct',
  'culled_affected_pct',
  'culled_top_category',
  'culled_top_subtype',
  'fertility_from_infertile',
  'hof',
};

const _commonPanelColumns = {
  'id',
  'sessionId',
  'customerId',
  'flockId',
  'hatcheryId',
  'date',
  'breed',
  'flockAgeWeeks',
  'house',
  'setter',
  'hatcher',
  'trolley',
  'tray',
  'position',
  'storagePeriodDays',
  'bmkAgeWeeks',
  'notes',
  'createdAt',
  'updatedAt',
  'syncStatus',
  'lastSyncedAt',
  'syncError',
};

bool _columnExists(Set<String> tableNames, String column) {
  if (_commonPanelColumns.contains(column)) return true;
  return tableNames.any(
    (tableName) => PanelSampleSchema.byTable(tableName).measurementColumns.any(
      (definition) => definition.split(RegExp(r'\s+')).first == column,
    ),
  );
}

String _snakeCase(String value) {
  return value
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match[1]}_${match[2]}',
      )
      .toLowerCase();
}

void _localized(Object? value, String path) {
  final localized = _object(value, path);
  _text(localized['en'], '$path.en');
  _text(localized['ar'], '$path.ar');
}

void _aliases(Object? value, String path) {
  final aliases = _object(value, path);
  for (final language in const ['en', 'ar']) {
    final values = _list(aliases[language], '$path.$language');
    if (values.isEmpty ||
        values.any((value) => value is! String || value.trim().isEmpty)) {
      throw FormatException('$path.$language requires non-empty aliases');
    }
  }
}

void _persistence(Object? value, String path) {
  final mapping = _object(value, path);
  _text(mapping['localColumn'], '$path.localColumn');
  _text(mapping['remoteColumn'], '$path.remoteColumn');
}

void _claimPersistenceColumns(
  Object? value,
  String path,
  Set<String> localColumns,
  Set<String> remoteColumns,
) {
  final mapping = _object(value, '$path persistence');
  final local = _text(mapping['localColumn'], '$path localColumn');
  final remote = _text(mapping['remoteColumn'], '$path remoteColumn');
  if (!localColumns.add(local)) {
    throw FormatException('$path repeats local column $local');
  }
  if (!remoteColumns.add(remote)) {
    throw FormatException('$path repeats remote column $remote');
  }
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map) throw FormatException('$path must be an object');
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Object?> _list(Object? value, String path) {
  if (value is! List) throw FormatException('$path must be a list');
  return List<Object?>.from(value);
}

String _text(Object? value, String path) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$path must be non-empty text');
  }
  return value;
}

String _dartOutput(String canonicalJson) {
  return '''// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: $_sourcePath

const generatedAgentStationRegistryJson = r\'\'\'
$canonicalJson
\'\'\';
''';
}

String _typeScriptOutput(String canonicalJson) {
  return '''// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: $_sourcePath
// deno-fmt-ignore-file

export interface AgentStationSchema {
  readonly schemaKey: string
  readonly version: number
  readonly sectorKeys: readonly string[]
  readonly stationKey: string
  readonly moduleKey: string
  readonly names: Readonly<Record<'en' | 'ar', string>>
  readonly aliases: Readonly<Record<'en' | 'ar', readonly string[]>>
  readonly allowedLayers: readonly string[]
  readonly fields: readonly Record<string, unknown>[]
  readonly calculations: readonly Record<string, unknown>[]
  readonly completion: Readonly<{ requiredFieldKeys: readonly string[] }>
  readonly persistence: readonly Readonly<{
    localTable: string
    remoteTable: string
  }>[]
  readonly read: Readonly<{
    dimensions: readonly string[]
    measures: readonly string[]
  }>
  readonly warnings: readonly Record<string, unknown>[]
}

export const agentStationRegistry = $canonicalJson as const

export function requireStationSchema(
  schemaKey: string,
  version: number,
): AgentStationSchema {
  const schema = agentStationRegistry.stations.find((candidate) =>
    candidate.schemaKey === schemaKey && candidate.version === version
  )
  if (!schema) throw new Error('Unknown station schema')
  return schema
}

export function applicableStationSchemas(
  sectorKeys: readonly string[],
): readonly AgentStationSchema[] {
  const allowed = new Set(sectorKeys)
  return agentStationRegistry.stations.filter((schema) =>
    schema.sectorKeys.some((sectorKey) => allowed.has(sectorKey))
  )
}
''';
}
