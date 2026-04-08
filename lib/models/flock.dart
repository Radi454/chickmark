class Flock {
  final String id;
  final String customerId;
  String flockCode;
  String breed;
  DateTime entryDate;
  String status; // 'active' or 'sold'
  DateTime createdAt;

  Flock({
    required this.id,
    required this.customerId,
    required this.flockCode,
    required this.breed,
    required this.entryDate,
    this.status = 'active',
    required this.createdAt,
  });

  double get currentAgeWeeks => DateTime.now().difference(entryDate).inDays / 7;
  double get eggProductionAgeWeeks => currentAgeWeeks + 3;

  Map<String, dynamic> toMap() => {
    'id': id, 'customer_id': customerId, 'flock_code': flockCode,
    'breed': breed, 'entry_date': entryDate.toIso8601String(),
    'status': status, 'created_at': createdAt.toIso8601String(),
  };

  factory Flock.fromMap(Map<String, dynamic> m) => Flock(
    id: m['id'], customerId: m['customer_id'], flockCode: m['flock_code'],
    breed: m['breed'], entryDate: DateTime.parse(m['entry_date']),
    status: m['status'] ?? 'active', createdAt: DateTime.parse(m['created_at']),
  );
}
