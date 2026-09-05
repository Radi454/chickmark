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

/// A house belongs to exactly one flock: a farm and a flock are the same
/// thing in this business, so there is no separate farm to own it and no
/// per-house placement date. `flocks.entryDate` is the single placement date
/// for every house in the flock, and [openingFemales]/[openingMales] carry
/// the opening bird balance a house started with.
class HouseModel {
  HouseModel({
    required this.id,
    required this.flockId,
    required this.name,
    this.code,
    this.capacity,
    this.openingFemales = 0,
    this.openingMales = 0,
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
    _requireText(flockId, 'flockId');
    _requireText(name, 'name');
    if (capacity != null && capacity! <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'Must be positive');
    }
    if (openingFemales < 0) {
      throw ArgumentError.value(
        openingFemales,
        'openingFemales',
        'Must not be negative',
      );
    }
    if (openingMales < 0) {
      throw ArgumentError.value(
        openingMales,
        'openingMales',
        'Must not be negative',
      );
    }
  }

  final String id;
  final String flockId;
  final String name;
  final String? code;
  final int? capacity;
  final int openingFemales;
  final int openingMales;
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
      flockId: _string(map['flockId']),
      name: _string(map['name']),
      code: map['code']?.toString(),
      capacity: _integer(map['capacity']),
      openingFemales: _integer(map['openingFemales']) ?? 0,
      openingMales: _integer(map['openingMales']) ?? 0,
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
    'flockId': flockId,
    'name': name.trim(),
    'code': code?.trim(),
    'capacity': capacity,
    'openingFemales': openingFemales,
    'openingMales': openingMales,
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
    int? openingFemales,
    int? openingMales,
    String? notes,
    bool? isActive,
    DateTime? updatedAt,
    String? syncStatus,
  }) {
    return HouseModel(
      id: id,
      flockId: flockId,
      name: name ?? this.name,
      code: code ?? this.code,
      capacity: capacity ?? this.capacity,
      openingFemales: openingFemales ?? this.openingFemales,
      openingMales: openingMales ?? this.openingMales,
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
