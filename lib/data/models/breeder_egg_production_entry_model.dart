/// One location's egg-grade count for one daily report (breeder-flock
/// -performance ticket 10, design doc section 5.2 and 7: "Egg production by
/// house: first grade and percentage; second grade and percentage; ...
/// calculated total eggs; calculated production percentage; egg weight").
///
/// A production entry's location is either a house ([houseId]) or an
/// isolation area ([isolationAreaId]) — exactly one, never both, never
/// neither — mirroring `BreederBirdMovement`/`BreederFeedEntry` (design
/// section 6: isolation is a separate location, its eggs are reported on
/// their own row and excluded from the house-scope production percent).
///
/// [count] is the only per-grade typed input; `total eggs`,
/// `egg-grade percent`, and `daily production percent` are always derived
/// by `BreederEggProductionService`, never stored here.
///
/// [eggWeightGrams] is a location-level attribute (the paper form records
/// one egg weight per house, not per grade) that is deliberately stored on
/// every grade row for that (report, location) rather than in a separate
/// table, since design doc section 12 lists only this one production-entry
/// table. `BreederEggProductionService.recordEggWeight` is the only writer
/// and keeps it identical across every grade row of the same location —
/// this model does not itself enforce that cross-row consistency, matching
/// how `BreederBirdMovement.closing` is computed exclusively by
/// `BreederBirdLedgerService` rather than by the model.
library;

class BreederEggProductionEntry {
  final String id;
  final String reportId;

  /// Non-null when this entry belongs to a production house. Exactly one
  /// of [houseId]/[isolationAreaId] is ever set.
  final String? houseId;

  /// Non-null when this entry belongs to a named isolation area. Exactly
  /// one of [houseId]/[isolationAreaId] is ever set.
  final String? isolationAreaId;

  final String gradeId;

  /// Eggs counted under this grade for this location. Never negative.
  final int count;

  /// Egg weight in grams for this location (design section 5.2.1: "Egg
  /// weight is in grams"). Duplicated across every grade row of the same
  /// (report, location) — see class doc comment.
  final double? eggWeightGrams;

  BreederEggProductionEntry({
    required this.id,
    required this.reportId,
    this.houseId,
    this.isolationAreaId,
    required this.gradeId,
    this.count = 0,
    this.eggWeightGrams,
  }) {
    final hasHouse = houseId != null && houseId!.isNotEmpty;
    final hasIsolation = isolationAreaId != null && isolationAreaId!.isNotEmpty;
    if (hasHouse == hasIsolation) {
      throw ArgumentError(
        'An egg production entry must name exactly one location: a house '
        'or an isolation area (houseId=$houseId, '
        'isolationAreaId=$isolationAreaId)',
      );
    }
  }

  /// True when this entry belongs to a production house.
  bool get isHouseEntry => houseId != null;

  /// True when this entry belongs to a named isolation area.
  bool get isIsolationEntry => isolationAreaId != null;

  /// The id of whichever location this entry names.
  String get locationId => houseId ?? isolationAreaId!;

  factory BreederEggProductionEntry.fromMap(Map<String, dynamic> map) {
    return BreederEggProductionEntry(
      id: map['id'] as String,
      reportId: map['reportId'] as String,
      houseId: map['houseId']?.toString(),
      isolationAreaId: map['isolationAreaId']?.toString(),
      gradeId: map['gradeId'] as String,
      count: (map['count'] as num?)?.toInt() ?? 0,
      eggWeightGrams: (map['eggWeightGrams'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'reportId': reportId,
      'houseId': houseId,
      'isolationAreaId': isolationAreaId,
      'gradeId': gradeId,
      'count': count,
      'eggWeightGrams': eggWeightGrams,
    };
  }

  BreederEggProductionEntry copyWith({
    String? id,
    String? reportId,
    String? houseId,
    String? isolationAreaId,
    String? gradeId,
    int? count,
    double? eggWeightGrams,
    bool clearEggWeightGrams = false,
  }) {
    return BreederEggProductionEntry(
      id: id ?? this.id,
      reportId: reportId ?? this.reportId,
      houseId: houseId ?? this.houseId,
      isolationAreaId: isolationAreaId ?? this.isolationAreaId,
      gradeId: gradeId ?? this.gradeId,
      count: count ?? this.count,
      eggWeightGrams: clearEggWeightGrams
          ? null
          : (eggWeightGrams ?? this.eggWeightGrams),
    );
  }
}
