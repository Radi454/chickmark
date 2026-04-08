class Customer {
  final String id;
  String name;
  String? email;
  String? phone;
  String? address;
  DateTime createdAt;

  Customer({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.address,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'email': email, 'phone': phone,
    'address': address, 'created_at': createdAt.toIso8601String(),
  };

  factory Customer.fromMap(Map<String, dynamic> m) => Customer(
    id: m['id'], name: m['name'], email: m['email'], phone: m['phone'],
    address: m['address'], createdAt: DateTime.parse(m['created_at']),
  );
}
