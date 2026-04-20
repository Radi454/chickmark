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

  List<String> get hatcheryCauses => hatcheryCausesJson != null
      ? List<String>.from(jsonDecode(hatcheryCausesJson!))
      : [];
  List<String> get farmFlockCauses => farmFlockCausesJson != null
      ? List<String>.from(jsonDecode(farmFlockCausesJson!))
      : [];

  // Section-keyed getters for troubleshooting sheet
  Map<String, List<String>> get hatcheryCausesBySection {
    if (hatcheryCausesJson == null) return {};
    try {
      final Map<String, dynamic> decoded = jsonDecode(hatcheryCausesJson!);
      return decoded.map((key, value) => MapEntry(
            key,
            List<String>.from(value as List),
          ));
    } catch (e) {
      return {};
    }
  }

  Map<String, List<String>> get farmFlockCausesBySection {
    if (farmFlockCausesJson == null) return {};
    try {
      final Map<String, dynamic> decoded = jsonDecode(farmFlockCausesJson!);
      return decoded.map((key, value) => MapEntry(
            key,
            List<String>.from(value as List),
          ));
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
