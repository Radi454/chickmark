/// A flock's egg production for one collection date, optionally broken down
/// by house (breeder-flock-performance ticket 14, design doc section 8 and
/// 12): "A batch represents a flock's egg production for a collection
/// date, with optional per-house contributions."
///
/// Judgment call: a batch is scoped to a single egg grade
/// (`breeder_egg_grade_definitions`), one row per (flock, collectionDate,
/// grade) — the design text names no grade on the batch itself, but ticket
/// 11's `breeder_egg_inventory_movements` ledger (which a hatchery dispatch
/// must post to) is strictly per-grade, and the acceptance criteria require
/// rejecting "dispatch beyond the available grade balance". Giving every
/// batch its own grade makes that check well-defined without inventing a
/// second, parallel per-grade breakdown inside a gradeless batch.
library;

class EggBatch {
  final String id;
  final String flockId;
  final DateTime collectionDate;
  final String gradeId;

  /// Never negative (design section 14: "Negative quantities are
  /// rejected").
  final int eggCount;
  final String? notes;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  EggBatch({
    required this.id,
    required this.flockId,
    required this.collectionDate,
    required this.gradeId,
    required this.eggCount,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  }) {
    if (eggCount < 0) {
      throw ArgumentError.value(eggCount, 'eggCount', 'must not be negative');
    }
  }

  static String dateKey(DateTime date) =>
      DateTime(date.year, date.month, date.day).toIso8601String().split('T').first;

  factory EggBatch.fromMap(Map<String, dynamic> map) {
    return EggBatch(
      id: map['id'] as String,
      flockId: map['flockId'] as String,
      collectionDate: DateTime.parse(map['collectionDate'] as String),
      gradeId: map['gradeId'] as String,
      eggCount: (map['eggCount'] as num?)?.toInt() ?? 0,
      notes: map['notes'] as String?,
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
      'flockId': flockId,
      'collectionDate': dateKey(collectionDate),
      'gradeId': gradeId,
      'eggCount': eggCount,
      'notes': notes,
    };
  }
}

/// One house's optional contribution to an [EggBatch] (design section 8 and
/// 12: "optional per-house contributions"). A batch may have zero, some, or
/// all of its houses represented here — the sum of every source row for a
/// batch is validated (by `EggBatchService`, not this model) to never
/// exceed the batch's own `eggCount`.
class EggBatchHouseSource {
  final String id;
  final String batchId;
  final String houseId;

  /// Never negative.
  final int eggCount;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  EggBatchHouseSource({
    required this.id,
    required this.batchId,
    required this.houseId,
    required this.eggCount,
    this.createdAt,
    this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  }) {
    if (eggCount < 0) {
      throw ArgumentError.value(eggCount, 'eggCount', 'must not be negative');
    }
  }

  factory EggBatchHouseSource.fromMap(Map<String, dynamic> map) {
    return EggBatchHouseSource(
      id: map['id'] as String,
      batchId: map['batchId'] as String,
      houseId: map['houseId'] as String,
      eggCount: (map['eggCount'] as num?)?.toInt() ?? 0,
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
      'batchId': batchId,
      'houseId': houseId,
      'eggCount': eggCount,
    };
  }
}
