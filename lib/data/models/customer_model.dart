import 'sampling_code.dart';

class CustomerModel {
  final String id;
  final String name;
  final String? location;
  final String? phone;
  final String? email;
  final String? samplingCode;
  final DateTime createdAt;
  final String createdBy;

  CustomerModel({
    required this.id,
    required this.name,
    this.location,
    this.phone,
    this.email,
    String? samplingCode,
    required this.createdAt,
    required this.createdBy,
  }) : samplingCode = _normalizeSamplingCode(samplingCode);

  factory CustomerModel.fromMap(Map<String, dynamic> map) {
    return CustomerModel(
      id: map['id'],
      name: map['name'],
      location: map['location'],
      phone: map['phone'],
      email: map['email'],
      samplingCode: map['samplingCode'] as String?,
      createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
      createdBy: map['createdBy'] ?? 'unknown',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'location': location,
      'phone': phone,
      'email': email,
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
