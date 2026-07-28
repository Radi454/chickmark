import 'dart:collection';
import 'dart:convert';

import 'station_registry.g.dart';

class AgentLocalizedText {
  const AgentLocalizedText({required this.en, required this.ar});

  final String en;
  final String ar;

  factory AgentLocalizedText.fromJson(Map<String, Object?> json) {
    return AgentLocalizedText(
      en: json['en']! as String,
      ar: json['ar']! as String,
    );
  }
}

class AgentPersistenceMapping {
  const AgentPersistenceMapping({
    required this.localTable,
    required this.remoteTable,
  });

  final String localTable;
  final String remoteTable;

  factory AgentPersistenceMapping.fromJson(Map<String, Object?> json) {
    return AgentPersistenceMapping(
      localTable: json['localTable']! as String,
      remoteTable: json['remoteTable']! as String,
    );
  }
}

class AgentStationField {
  AgentStationField({
    required this.fieldKey,
    required this.names,
    required Map<String, List<String>> aliases,
    required this.type,
    required this.unit,
    required this.required,
    required this.explicitZero,
    required Map<String, Object?> validation,
    required Map<String, Object?> persistence,
  }) : aliases = UnmodifiableMapView(
         aliases.map(
           (language, values) =>
               MapEntry(language, List<String>.unmodifiable(values)),
         ),
       ),
       validation = UnmodifiableMapView(validation),
       persistence = UnmodifiableMapView(persistence);

  final String fieldKey;
  final AgentLocalizedText names;
  final Map<String, List<String>> aliases;
  final String type;
  final String unit;
  final bool required;
  final bool explicitZero;
  final Map<String, Object?> validation;
  final Map<String, Object?> persistence;

  factory AgentStationField.fromJson(Map<String, Object?> json) {
    return AgentStationField(
      fieldKey: json['fieldKey']! as String,
      names: AgentLocalizedText.fromJson(_object(json['names'])),
      aliases: _stringListMap(json['aliases']),
      type: json['type']! as String,
      unit: json['unit']! as String,
      required: json['required']! as bool,
      explicitZero: json['explicitZero']! as bool,
      validation: _object(json['validation']),
      persistence: _object(json['persistence']),
    );
  }
}

class AgentStationSchema {
  AgentStationSchema({
    required this.schemaKey,
    required this.version,
    required List<String> sectorKeys,
    required this.stationKey,
    required this.moduleKey,
    required this.names,
    required Map<String, List<String>> aliases,
    required List<String> allowedLayers,
    required List<AgentStationField> fields,
    required List<String> requiredFieldKeys,
    required List<AgentPersistenceMapping> persistence,
  }) : sectorKeys = List.unmodifiable(sectorKeys),
       aliases = UnmodifiableMapView(
         aliases.map(
           (language, values) =>
               MapEntry(language, List<String>.unmodifiable(values)),
         ),
       ),
       allowedLayers = List.unmodifiable(allowedLayers),
       fields = List.unmodifiable(fields),
       requiredFieldKeys = List.unmodifiable(requiredFieldKeys),
       persistence = List.unmodifiable(persistence);

  final String schemaKey;
  final int version;
  final List<String> sectorKeys;
  final String stationKey;
  final String moduleKey;
  final AgentLocalizedText names;
  final Map<String, List<String>> aliases;
  final List<String> allowedLayers;
  final List<AgentStationField> fields;
  final List<String> requiredFieldKeys;
  final List<AgentPersistenceMapping> persistence;

  String get identity => '$schemaKey@$version';

  factory AgentStationSchema.fromJson(Map<String, Object?> json) {
    final completion = _object(json['completion']);
    return AgentStationSchema(
      schemaKey: json['schemaKey']! as String,
      version: json['version']! as int,
      sectorKeys: _strings(json['sectorKeys']),
      stationKey: json['stationKey']! as String,
      moduleKey: json['moduleKey']! as String,
      names: AgentLocalizedText.fromJson(_object(json['names'])),
      aliases: _stringListMap(json['aliases']),
      allowedLayers: _strings(json['allowedLayers']),
      fields: _objects(
        json['fields'],
      ).map(AgentStationField.fromJson).toList(growable: false),
      requiredFieldKeys: _strings(completion['requiredFieldKeys']),
      persistence: _objects(
        json['persistence'],
      ).map(AgentPersistenceMapping.fromJson).toList(growable: false),
    );
  }
}

abstract final class AgentStationRegistry {
  static final List<AgentStationSchema> schemas = _loadSchemas();

  static AgentStationSchema require(String schemaKey, int version) {
    return schemas.firstWhere(
      (schema) => schema.schemaKey == schemaKey && schema.version == version,
      orElse: () => throw ArgumentError.value(
        '$schemaKey@$version',
        'schema',
        'Unknown station schema',
      ),
    );
  }

  static List<AgentStationSchema> applicableTo(Set<String> sectorKeys) {
    return List.unmodifiable(
      schemas.where((schema) => schema.sectorKeys.any(sectorKeys.contains)),
    );
  }

  static List<AgentStationSchema> _loadSchemas() {
    final root = _object(jsonDecode(generatedAgentStationRegistryJson));
    return List.unmodifiable(
      _objects(root['stations']).map(AgentStationSchema.fromJson),
    );
  }
}

Map<String, Object?> _object(Object? value) {
  return (value! as Map).map((key, item) => MapEntry(key.toString(), item));
}

List<Map<String, Object?>> _objects(Object? value) {
  return (value! as List).map(_object).toList(growable: false);
}

List<String> _strings(Object? value) {
  return (value! as List).cast<String>().toList(growable: false);
}

Map<String, List<String>> _stringListMap(Object? value) {
  return _object(value).map((key, item) => MapEntry(key, _strings(item)));
}
