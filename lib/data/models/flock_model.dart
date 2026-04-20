import '../../core/utils/date_utils.dart';

class FlockModel {
  final String id;
  final String customerId;
  final String flockId;
  final String breed;
  final DateTime entryDate;

  FlockModel({
    required this.id,
    required this.customerId,
    required this.flockId,
    required this.breed,
    required this.entryDate,
  });

  factory FlockModel.fromMap(Map<String, dynamic> map) {
    return FlockModel(
      id: map['id'],
      customerId: map['customerId'],
      flockId: map['flockId'] ?? map['id'],
      breed: map['breed'] ?? 'Unknown',
      entryDate: DateTime.tryParse(map['entryDate'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerId': customerId,
      'flockId': flockId,
      'breed': breed,
      'entryDate': entryDate.toIso8601String(),
    };
  }

  double get currentAgeWeeks =>
      HatchDateUtils.flockAgeWeeks(entryDate).toDouble();
}
