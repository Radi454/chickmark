/// A system-defined egg grade (breeder-flock-performance ticket 10, design
/// doc section 5.2 and 12: "Egg grades are system-defined database records
/// in `breeder_egg_grade_definitions`, not UI-only strings"). Grades are a
/// strict partition of every laid egg: mutually exclusive and collectively
/// exhaustive, so grade counts always sum to calculated total eggs.
///
/// Real eggs can satisfy more than one description at once — a cracked
/// double-yolk egg is both cracked and a double yolk. [priority] is what
/// resolves that: an egg is counted under the highest-priority grade it
/// matches. Lower [priority] numbers are higher priority (checked first),
/// so `priority: 1` always wins over `priority: 6` when an egg matches
/// both. Priority is unique within the active grade set (design section 12
/// invariant) — enforced here defensively and by a partial unique database
/// index (`idx_breeder_egg_grade_definitions_active_priority`,
/// `WHERE isActive = 1`).
///
/// See `kBreederEggGradeDefinitionSeeds` in
/// `lib/data/database/seeds/breeder_egg_grade_definition_seeds.dart` for the
/// seeded priority order and the judgment call behind it (most severe
/// physical defect wins, "first grade" is the catch-all default with the
/// lowest priority).
library;

class BreederEggGradeCode {
  static const String firstGrade = 'first_grade';
  static const String secondGrade = 'second_grade';
  static const String sortReject = 'sort_reject';
  static const String doubleYolk = 'double_yolk';
  static const String cracked = 'cracked';
  static const String damaged = 'damaged';

  static const List<String> all = [
    firstGrade,
    secondGrade,
    sortReject,
    doubleYolk,
    cracked,
    damaged,
  ];
}

class BreederEggGradeDefinition {
  final String id;
  final String code;
  final String name;

  /// Lower number = higher priority = checked first when an egg matches
  /// more than one grade's description. Unique within the active set.
  final int priority;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  BreederEggGradeDefinition({
    required this.id,
    required this.code,
    required this.name,
    required this.priority,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty');
    }
    if (code.trim().isEmpty) {
      throw ArgumentError.value(code, 'code', 'Must not be empty');
    }
    if (priority <= 0) {
      throw ArgumentError.value(priority, 'priority', 'Must be positive');
    }
  }

  factory BreederEggGradeDefinition.fromMap(Map<String, dynamic> map) {
    return BreederEggGradeDefinition(
      id: map['id'] as String,
      code: map['code'] as String,
      name: map['name'] as String,
      priority: (map['priority'] as num).toInt(),
      isActive: (map['isActive'] as num?)?.toInt() != 0,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString())
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString())
          : null,
      syncStatus: map['syncStatus']?.toString() ?? 'synced',
      dirtyAt: map['dirtyAt'] != null
          ? DateTime.tryParse(map['dirtyAt'].toString())
          : null,
      lastSyncedAt: map['lastSyncedAt'] != null
          ? DateTime.tryParse(map['lastSyncedAt'].toString())
          : null,
      syncError: map['syncError']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'priority': priority,
      'isActive': isActive ? 1 : 0,
      'createdAt': createdAt?.toUtc().toIso8601String(),
      'updatedAt': updatedAt?.toUtc().toIso8601String(),
      'syncStatus': syncStatus,
      'dirtyAt': dirtyAt?.toUtc().toIso8601String(),
      'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
      'syncError': syncError,
    };
  }
}
