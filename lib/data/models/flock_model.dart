import '../../core/utils/date_utils.dart';

class FlockModel {
  static const String activeStatus = 'active';
  static const String soldStatus = 'sold';
  static const int defaultDepletionAgeWeeks = 65;

  final String id;
  final String customerId;
  final String flockId;
  final String breed;
  final DateTime entryDate;
  final bool isAgeEstimated;
  final String status;
  final int depletionAgeWeeks;
  final DateTime? soldAt;

  FlockModel({
    required this.id,
    required this.customerId,
    required this.flockId,
    required this.breed,
    required this.entryDate,
    this.isAgeEstimated = false,
    this.status = activeStatus,
    this.depletionAgeWeeks = defaultDepletionAgeWeeks,
    this.soldAt,
  });

  factory FlockModel.fromMap(Map<String, dynamic> map) {
    final parsedStatus = (map['status'] as String?)?.toLowerCase().trim();
    final depletionAge = map['depletionAgeWeeks'];

    return FlockModel(
      id: map['id'],
      customerId: map['customerId'],
      flockId: map['flockId'] ?? map['id'],
      breed: map['breed'] ?? 'Unknown',
      entryDate: DateTime.tryParse(map['entryDate'] ?? '') ?? DateTime.now(),
      isAgeEstimated:
          map['isAgeEstimated'] == 1 || map['isAgeEstimated'] == true,
      status: parsedStatus == soldStatus ? soldStatus : activeStatus,
      depletionAgeWeeks: depletionAge is int
          ? depletionAge
          : int.tryParse('${depletionAge ?? ''}') ?? defaultDepletionAgeWeeks,
      soldAt: DateTime.tryParse(map['soldAt'] ?? ''),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerId': customerId,
      'flockId': flockId,
      'breed': breed,
      'entryDate': entryDate.toIso8601String(),
      'isAgeEstimated': isAgeEstimated ? 1 : 0,
      'status': status,
      'depletionAgeWeeks': depletionAgeWeeks,
      'soldAt': soldAt?.toIso8601String(),
    };
  }

  double get currentAgeWeeks =>
      HatchDateUtils.flockAgeWeeks(entryDate).toDouble();

  bool get isSold => status == soldStatus;

  bool get hasReachedDepletionAge =>
      currentAgeWeeks >= depletionAgeWeeks && depletionAgeWeeks > 0;

  bool get isAvailableForAudit => !isSold && !hasReachedDepletionAge;

  String get availabilityLabel {
    if (isSold) return 'Sold';
    if (hasReachedDepletionAge) return 'Depleted';
    return 'Active';
  }

  FlockModel copyWith({
    String? id,
    String? customerId,
    String? flockId,
    String? breed,
    DateTime? entryDate,
    bool? isAgeEstimated,
    String? status,
    int? depletionAgeWeeks,
    DateTime? soldAt,
    bool clearSoldAt = false,
  }) {
    return FlockModel(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      flockId: flockId ?? this.flockId,
      breed: breed ?? this.breed,
      entryDate: entryDate ?? this.entryDate,
      isAgeEstimated: isAgeEstimated ?? this.isAgeEstimated,
      status: status ?? this.status,
      depletionAgeWeeks: depletionAgeWeeks ?? this.depletionAgeWeeks,
      soldAt: clearSoldAt ? null : soldAt ?? this.soldAt,
    );
  }
}
