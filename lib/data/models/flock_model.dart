import '../../core/utils/date_utils.dart';
import 'poultry_hierarchy_models.dart';

class FlockModel {
  static const String activeStatus = 'active';
  static const String soldStatus = 'sold';
  static const int defaultDepletionAgeWeeks = 65;

  final String id;
  final String customerId;
  final String flockId;
  final String breed;
  final DateTime entryDate;
  final String? farmId;
  final PoultrySector? sector;
  final FlockSexProfile sexProfile;
  final String? targetProfileId;
  final String? productionPhase;
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
    this.farmId,
    this.sector,
    this.sexProfile = FlockSexProfile.asHatched,
    this.targetProfileId,
    this.productionPhase,
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
      farmId: map['farmId']?.toString(),
      sector: _parseSector(map['sectorKey']),
      sexProfile: FlockSexProfile.fromStorage(map['sexProfile']?.toString()),
      targetProfileId: map['targetProfileId']?.toString(),
      productionPhase: map['productionPhase']?.toString(),
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
      'farmId': farmId,
      'sectorKey': sector?.storageKey,
      'sexProfile': sexProfile.storageKey,
      'targetProfileId': targetProfileId,
      'productionPhase': productionPhase,
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
    String? farmId,
    PoultrySector? sector,
    FlockSexProfile? sexProfile,
    String? targetProfileId,
    String? productionPhase,
    bool? isAgeEstimated,
    String? status,
    int? depletionAgeWeeks,
    DateTime? soldAt,
    bool clearFarmId = false,
    bool clearSector = false,
    bool clearTargetProfileId = false,
    bool clearProductionPhase = false,
    bool clearSoldAt = false,
  }) {
    return FlockModel(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      flockId: flockId ?? this.flockId,
      breed: breed ?? this.breed,
      entryDate: entryDate ?? this.entryDate,
      farmId: clearFarmId ? null : farmId ?? this.farmId,
      sector: clearSector ? null : sector ?? this.sector,
      sexProfile: sexProfile ?? this.sexProfile,
      targetProfileId: clearTargetProfileId
          ? null
          : targetProfileId ?? this.targetProfileId,
      productionPhase: clearProductionPhase
          ? null
          : productionPhase ?? this.productionPhase,
      isAgeEstimated: isAgeEstimated ?? this.isAgeEstimated,
      status: status ?? this.status,
      depletionAgeWeeks: depletionAgeWeeks ?? this.depletionAgeWeeks,
      soldAt: clearSoldAt ? null : soldAt ?? this.soldAt,
    );
  }
}

PoultrySector? _parseSector(Object? value) {
  final text = value?.toString();
  if (text == null || text.trim().isEmpty) return null;
  try {
    return PoultrySector.fromStorage(text);
  } on ArgumentError {
    return null;
  }
}
