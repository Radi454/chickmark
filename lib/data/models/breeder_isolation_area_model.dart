/// A named isolation area belonging to exactly one breeder flock
/// (breeder-flock-performance ticket 08, design doc section 6). A flock can
/// have several isolation areas; each one's [name] must be unique within its
/// flock (case-insensitive) so entry and review can list houses and
/// isolation areas together without ambiguity. Uniqueness and
/// flock-ownership are additionally enforced by the database (a unique
/// index and a foreign key), not just here.
library;

class BreederIsolationArea {
  BreederIsolationArea({
    required this.id,
    required this.flockId,
    required this.name,
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
  }

  final String id;
  final String flockId;
  final String name;
  final String? notes;
  final bool isActive;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  factory BreederIsolationArea.fromMap(Map<String, dynamic> map) {
    return BreederIsolationArea(
      id: _string(map['id']),
      flockId: _string(map['flockId']),
      name: _string(map['name']),
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

  BreederIsolationArea copyWith({
    String? id,
    String? flockId,
    String? name,
    String? notes,
    bool? isActive,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
    DateTime? dirtyAt,
    DateTime? lastSyncedAt,
    String? syncError,
  }) {
    return BreederIsolationArea(
      id: id ?? this.id,
      flockId: flockId ?? this.flockId,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      dirtyAt: dirtyAt ?? this.dirtyAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      syncError: syncError ?? this.syncError,
    );
  }
}

void _requireText(String value, String field) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, field, 'Must not be empty');
  }
}

String _string(Object? value) => value?.toString() ?? '';

bool _bool(Object? value, {required bool fallback}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  return value.toString() == '1' || value.toString().toLowerCase() == 'true';
}

DateTime? _date(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
