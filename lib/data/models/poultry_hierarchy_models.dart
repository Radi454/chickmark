enum PoultrySector {
  breeder('breeder'),
  broiler('broiler'),
  layer('layer');

  const PoultrySector(this.storageKey);

  final String storageKey;

  static PoultrySector fromStorage(String? value) {
    final normalized = value?.trim().toLowerCase();
    return values.firstWhere(
      (sector) => sector.storageKey == normalized,
      orElse: () => throw ArgumentError.value(value, 'value', 'Unknown sector'),
    );
  }
}

enum FlockSexProfile {
  asHatched('as_hatched'),
  male('male'),
  female('female');

  const FlockSexProfile(this.storageKey);

  final String storageKey;

  static FlockSexProfile fromStorage(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return asHatched;
    return values.firstWhere(
      (profile) => profile.storageKey == normalized,
      orElse: () => asHatched,
    );
  }
}

enum PlacementStatus {
  active('active'),
  ended('ended'),
  transferred('transferred');

  const PlacementStatus(this.storageKey);

  final String storageKey;

  static PlacementStatus fromStorage(String? value) {
    final normalized = value?.trim().toLowerCase();
    return values.firstWhere(
      (status) => status.storageKey == normalized,
      orElse: () => active,
    );
  }
}

class CustomerSectorModel {
  CustomerSectorModel({
    required this.id,
    required this.customerId,
    required this.sector,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  }) {
    _requireText(id, 'id');
    _requireText(customerId, 'customerId');
  }

  final String id;
  final String customerId;
  final PoultrySector sector;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  factory CustomerSectorModel.fromMap(Map<String, dynamic> map) {
    return CustomerSectorModel(
      id: _string(map['id']),
      customerId: _string(map['customerId']),
      sector: PoultrySector.fromStorage(map['sectorKey']?.toString()),
      isActive: _bool(map['isActive'], fallback: true),
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
      syncStatus: map['syncStatus']?.toString() ?? 'synced',
      dirtyAt: _date(map['dirtyAt']),
      lastSyncedAt: _date(map['lastSyncedAt']),
      syncError: map['syncError']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'customerId': customerId,
    'sectorKey': sector.storageKey,
    'isActive': isActive ? 1 : 0,
    'createdAt': createdAt?.toUtc().toIso8601String(),
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
    'syncStatus': syncStatus,
    'dirtyAt': dirtyAt?.toUtc().toIso8601String(),
    'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
    'syncError': syncError,
  };

  CustomerSectorModel copyWith({
    bool? isActive,
    DateTime? updatedAt,
    String? syncStatus,
    DateTime? dirtyAt,
    DateTime? lastSyncedAt,
    String? syncError,
    bool clearSyncError = false,
  }) {
    return CustomerSectorModel(
      id: id,
      customerId: customerId,
      sector: sector,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      dirtyAt: dirtyAt ?? this.dirtyAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      syncError: clearSyncError ? null : syncError ?? this.syncError,
    );
  }
}

class FarmModel {
  FarmModel({
    required this.id,
    required this.customerId,
    required this.sector,
    required this.name,
    this.location,
    this.notes,
    this.isActive = true,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  }) {
    _requireText(id, 'id');
    _requireText(customerId, 'customerId');
    _requireText(name, 'name');
  }

  final String id;
  final String customerId;
  final PoultrySector sector;
  final String name;
  final String? location;
  final String? notes;
  final bool isActive;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  factory FarmModel.fromMap(Map<String, dynamic> map) {
    return FarmModel(
      id: _string(map['id']),
      customerId: _string(map['customerId']),
      sector: PoultrySector.fromStorage(map['sectorKey']?.toString()),
      name: _string(map['name']),
      location: map['location']?.toString(),
      notes: map['notes']?.toString(),
      isActive: _bool(map['isActive'], fallback: true),
      createdBy: map['createdBy']?.toString(),
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
      syncStatus: map['syncStatus']?.toString() ?? 'synced',
      dirtyAt: _date(map['dirtyAt']),
      lastSyncedAt: _date(map['lastSyncedAt']),
      syncError: map['syncError']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'customerId': customerId,
    'sectorKey': sector.storageKey,
    'name': name.trim(),
    'location': location?.trim(),
    'notes': notes?.trim(),
    'isActive': isActive ? 1 : 0,
    'createdBy': createdBy,
    'createdAt': createdAt?.toUtc().toIso8601String(),
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
    'syncStatus': syncStatus,
    'dirtyAt': dirtyAt?.toUtc().toIso8601String(),
    'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
    'syncError': syncError,
  };

  FarmModel copyWith({
    String? name,
    String? location,
    String? notes,
    bool? isActive,
    DateTime? updatedAt,
    String? syncStatus,
  }) {
    return FarmModel(
      id: id,
      customerId: customerId,
      sector: sector,
      name: name ?? this.name,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      dirtyAt: dirtyAt,
      lastSyncedAt: lastSyncedAt,
      syncError: syncError,
    );
  }
}

class HouseModel {
  HouseModel({
    required this.id,
    required this.farmId,
    required this.name,
    this.code,
    this.capacity,
    this.notes,
    this.isActive = true,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  }) {
    _requireText(id, 'id');
    _requireText(farmId, 'farmId');
    _requireText(name, 'name');
    if (capacity != null && capacity! <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'Must be positive');
    }
  }

  final String id;
  final String farmId;
  final String name;
  final String? code;
  final int? capacity;
  final String? notes;
  final bool isActive;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  factory HouseModel.fromMap(Map<String, dynamic> map) {
    return HouseModel(
      id: _string(map['id']),
      farmId: _string(map['farmId']),
      name: _string(map['name']),
      code: map['code']?.toString(),
      capacity: _integer(map['capacity']),
      notes: map['notes']?.toString(),
      isActive: _bool(map['isActive'], fallback: true),
      createdBy: map['createdBy']?.toString(),
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
      syncStatus: map['syncStatus']?.toString() ?? 'synced',
      dirtyAt: _date(map['dirtyAt']),
      lastSyncedAt: _date(map['lastSyncedAt']),
      syncError: map['syncError']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'farmId': farmId,
    'name': name.trim(),
    'code': code?.trim(),
    'capacity': capacity,
    'notes': notes?.trim(),
    'isActive': isActive ? 1 : 0,
    'createdBy': createdBy,
    'createdAt': createdAt?.toUtc().toIso8601String(),
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
    'syncStatus': syncStatus,
    'dirtyAt': dirtyAt?.toUtc().toIso8601String(),
    'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
    'syncError': syncError,
  };

  HouseModel copyWith({
    String? name,
    String? code,
    int? capacity,
    String? notes,
    bool? isActive,
    DateTime? updatedAt,
    String? syncStatus,
  }) {
    return HouseModel(
      id: id,
      farmId: farmId,
      name: name ?? this.name,
      code: code ?? this.code,
      capacity: capacity ?? this.capacity,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      dirtyAt: dirtyAt,
      lastSyncedAt: lastSyncedAt,
      syncError: syncError,
    );
  }
}

class FlockPlacementModel {
  FlockPlacementModel({
    required this.id,
    required this.flockId,
    required this.houseId,
    required this.placedBirds,
    required this.placedAt,
    this.endedAt,
    this.status = PlacementStatus.active,
    this.notes,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  }) {
    _requireText(id, 'id');
    _requireText(flockId, 'flockId');
    _requireText(houseId, 'houseId');
    if (placedBirds <= 0) {
      throw ArgumentError.value(placedBirds, 'placedBirds', 'Must be positive');
    }
  }

  final String id;
  final String flockId;
  final String houseId;
  final int placedBirds;
  final DateTime placedAt;
  final DateTime? endedAt;
  final PlacementStatus status;
  final String? notes;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  factory FlockPlacementModel.fromMap(Map<String, dynamic> map) {
    return FlockPlacementModel(
      id: _string(map['id']),
      flockId: _string(map['flockId']),
      houseId: _string(map['houseId']),
      placedBirds: _integer(map['placedBirds']) ?? 0,
      placedAt:
          _date(map['placedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      endedAt: _date(map['endedAt']),
      status: PlacementStatus.fromStorage(map['status']?.toString()),
      notes: map['notes']?.toString(),
      createdBy: map['createdBy']?.toString(),
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
      syncStatus: map['syncStatus']?.toString() ?? 'synced',
      dirtyAt: _date(map['dirtyAt']),
      lastSyncedAt: _date(map['lastSyncedAt']),
      syncError: map['syncError']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'flockId': flockId,
    'houseId': houseId,
    'placedBirds': placedBirds,
    'placedAt': placedAt.toUtc().toIso8601String(),
    'endedAt': endedAt?.toUtc().toIso8601String(),
    'status': status.storageKey,
    'notes': notes?.trim(),
    'createdBy': createdBy,
    'createdAt': createdAt?.toUtc().toIso8601String(),
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
    'syncStatus': syncStatus,
    'dirtyAt': dirtyAt?.toUtc().toIso8601String(),
    'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
    'syncError': syncError,
  };

  FlockPlacementModel copyWith({
    DateTime? endedAt,
    PlacementStatus? status,
    String? notes,
    DateTime? updatedAt,
    String? syncStatus,
  }) {
    return FlockPlacementModel(
      id: id,
      flockId: flockId,
      houseId: houseId,
      placedBirds: placedBirds,
      placedAt: placedAt,
      endedAt: endedAt ?? this.endedAt,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      dirtyAt: dirtyAt,
      lastSyncedAt: lastSyncedAt,
      syncError: syncError,
    );
  }
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty');
  }
}

String _string(Object? value) => value?.toString() ?? '';

DateTime? _date(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

int? _integer(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

bool _bool(Object? value, {required bool fallback}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  return value.toString().toLowerCase() == 'true';
}
