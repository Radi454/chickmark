import 'dart:convert';

class TroubleshootingModel {
  final String id;
  final String? hatcheryCausesJson;
  final String? farmFlockCausesJson;

  TroubleshootingModel({
    required this.id,
    this.hatcheryCausesJson,
    this.farmFlockCausesJson,
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

  factory TroubleshootingModel.fromMap(Map<String, dynamic> map) {
    return TroubleshootingModel(
      id: map['id'],
      hatcheryCausesJson: map['hatcheryCauses'],
      farmFlockCausesJson: map['farmFlockCauses'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'hatcheryCauses': hatcheryCausesJson,
      'farmFlockCauses': farmFlockCausesJson,
    };
  }
}
