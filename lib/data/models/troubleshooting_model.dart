import 'dart:convert';

class TroubleshootingModel {
  final String id;
  final String? hatcheryCausesJson;
  final String? farmFlockCausesJson;
  final String? benchmarkJson;
  final String? interpretationJson;
  final String? sourceRefsJson;

  TroubleshootingModel({
    required this.id,
    this.hatcheryCausesJson,
    this.farmFlockCausesJson,
    this.benchmarkJson,
    this.interpretationJson,
    this.sourceRefsJson,
  });

  List<String> get hatcheryCauses =>
      hatcheryCausesBySection.values.expand((items) => items).toList();
  List<String> get farmFlockCauses =>
      farmFlockCausesBySection.values.expand((items) => items).toList();

  // Section-keyed getters for troubleshooting sheet
  Map<String, List<String>> get hatcheryCausesBySection {
    if (hatcheryCausesJson == null) return {};
    try {
      final Map<String, dynamic> decoded = jsonDecode(hatcheryCausesJson!);
      return decoded.map(
        (key, value) => MapEntry(key, List<String>.from(value as List)),
      );
    } catch (e) {
      return {};
    }
  }

  Map<String, List<String>> get farmFlockCausesBySection {
    if (farmFlockCausesJson == null) return {};
    try {
      final Map<String, dynamic> decoded = jsonDecode(farmFlockCausesJson!);
      return decoded.map(
        (key, value) => MapEntry(key, List<String>.from(value as List)),
      );
    } catch (e) {
      return {};
    }
  }

  Map<String, dynamic> get benchmark => _decodeObject(benchmarkJson);
  Map<String, dynamic> get interpretation => _decodeObject(interpretationJson);

  List<Map<String, String>> get sourceRefs {
    if (sourceRefsJson == null) return [];
    try {
      final decoded = jsonDecode(sourceRefsJson!);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(
            (item) => item.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Map<String, dynamic> _decodeObject(String? source) {
    if (source == null) return {};
    try {
      final decoded = jsonDecode(source);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  factory TroubleshootingModel.fromMap(Map<String, dynamic> map) {
    return TroubleshootingModel(
      id: map['id'],
      hatcheryCausesJson: map['hatcheryCauses'],
      farmFlockCausesJson: map['farmFlockCauses'],
      benchmarkJson: map['benchmarkJson'],
      interpretationJson: map['interpretationJson'],
      sourceRefsJson: map['sourceRefsJson'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'hatcheryCauses': hatcheryCausesJson,
      'farmFlockCauses': farmFlockCausesJson,
      'benchmarkJson': benchmarkJson,
      'interpretationJson': interpretationJson,
      'sourceRefsJson': sourceRefsJson,
    };
  }
}
