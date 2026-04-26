class HatcheryModel {
  final String id;
  final String customerId;
  final String name;
  final String? location;
  final String? notes;
  final DateTime createdAt;
  final String createdBy;

  const HatcheryModel({
    required this.id,
    required this.customerId,
    required this.name,
    this.location,
    this.notes,
    required this.createdAt,
    required this.createdBy,
  });

  factory HatcheryModel.fromMap(Map<String, dynamic> map) {
    return HatcheryModel(
      id: map['id'] as String,
      customerId: map['customerId'] as String,
      name: map['name'] as String,
      location: map['location'] as String?,
      notes: map['notes'] as String?,
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
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
    };
  }
}
