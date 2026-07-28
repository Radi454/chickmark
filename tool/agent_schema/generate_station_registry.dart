import 'dart:convert';
import 'dart:io';

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
    for (final rawField in fields) {
      final field = _object(rawField, '$schemaKey field');
      final fieldKey = _text(field['fieldKey'], '$schemaKey fieldKey');
      if (!fieldKeys.add(fieldKey)) {
        throw FormatException('$schemaKey repeats field $fieldKey');
      }
      _localized(field['names'], '$schemaKey.$fieldKey names');
      _aliases(field['aliases'], '$schemaKey.$fieldKey aliases');
      _text(field['type'], '$schemaKey.$fieldKey type');
      if (field['required'] is! bool || field['explicitZero'] is! bool) {
        throw FormatException(
          '$schemaKey.$fieldKey requires boolean required/explicitZero',
        );
      }
      _object(field['validation'], '$schemaKey.$fieldKey validation');
      _persistence(field['persistence'], '$schemaKey.$fieldKey persistence');
    }

    final completion = _object(station['completion'], '$schemaKey completion');
    for (final requiredKey in _list(
      completion['requiredFieldKeys'],
      '$schemaKey requiredFieldKeys',
    )) {
      if (requiredKey is! String || !fieldKeys.contains(requiredKey)) {
        throw FormatException(
          '$schemaKey completion references unknown field $requiredKey',
        );
      }
    }
    for (final rawMapping in _list(
      station['persistence'],
      '$schemaKey persistence',
    )) {
      final mapping = _object(rawMapping, '$schemaKey table mapping');
      _text(mapping['localTable'], '$schemaKey localTable');
      _text(mapping['remoteTable'], '$schemaKey remoteTable');
    }
  }
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
