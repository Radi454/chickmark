class CustomerModel {
  final String id;
  final String name;
  final String? location;
  final String? phone;
  final String? email;
  final DateTime createdAt;
  final String createdBy;

  CustomerModel({
    required this.id,
    required this.name,
    this.location,
    this.phone,
    this.email,
    required this.createdAt,
    required this.createdBy,
  });

  factory CustomerModel.fromMap(Map<String, dynamic> map) {
    return CustomerModel(
      id: map['id'],
      name: map['name'],
      location: map['location'],
      phone: map['phone'],
      email: map['email'],
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
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
    };
  }
}
