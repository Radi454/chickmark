import 'sampling_code.dart';

class HatcheryModel {
  final String id;
  final String customerId;
  final String name;
  final String? location;
  final String? notes;
  final String? samplingCode;
  final DateTime createdAt;
  final String createdBy;

  HatcheryModel({
    required this.id,
    required this.customerId,
    required this.name,
    this.location,
    this.notes,
    String? samplingCode,
    required this.createdAt,
    required this.createdBy,
  }) : samplingCode = _normalizeSamplingCode(samplingCode);

  factory HatcheryModel.fromMap(Map<String, dynamic> map) {
    return HatcheryModel(
      id: map['id'] as String,
      customerId: map['customerId'] as String,
      name: map['name'] as String,
      location: map['location'] as String?,
      notes: map['notes'] as String?,
      samplingCode: map['samplingCode'] as String?,
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      createdBy: map['createdBy'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerId': customerId,
      'name': name,
      'location': location,
      'notes': notes,
      'samplingCode': samplingCode,
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
    };
  }
}

String? _normalizeSamplingCode(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final normalized = normalizeThreeLetterCode(raw);
  if (normalized == null) {
    throw ArgumentError.value(
      raw,
      'samplingCode',
      'Expected three letters A-Z',
    );
  }
  return normalized;
}
