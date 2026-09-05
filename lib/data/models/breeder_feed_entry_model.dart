/// One location's feed record for one sex on one daily report
/// (breeder-flock-performance ticket 09, design doc section 5.2 and 7.1:
/// "Feed by house: female feed kilograms and calculated grams per female;
/// male feed kilograms and calculated grams per male").
///
/// A feed entry's location is either a house ([houseId]) or an isolation
/// area ([isolationAreaId]) — exactly one, never both, never neither,
/// mirroring the same rule `BreederBirdMovement` enforces (design doc
/// section 6: isolation areas are separate locations, and isolation feed is
/// "reported against isolation bird counts on its own row" rather than
/// folded into a house figure). That is enforced here (the constructor
/// rejects anything else) and again by the database's own CHECK constraint.
///
/// [feedKg] is the only typed input; grams-per-bird is always derived by
/// `BreederBirdLedgerService.feedGramsPerBird` from this value and the
/// relevant closing bird count — it is never stored here and never
/// independently editable (design doc section 7: "feed grams per bird =
/// feed kilograms * 1000 / applicable live birds").
library;

class BreederFeedEntry {
  final String id;
  final String reportId;

  /// Non-null when this feed entry belongs to a production house. Exactly
  /// one of [houseId]/[isolationAreaId] is ever set.
  final String? houseId;

  /// Non-null when this feed entry belongs to a named isolation area.
  /// Exactly one of [houseId]/[isolationAreaId] is ever set.
  final String? isolationAreaId;

  final String sex;

  /// Feed weight in kilograms — the only canonical, persisted unit (design
  /// doc section 5.2.1: "Feed is entered in kilograms and derived feed per
  /// bird is reported in grams").
  final double feedKg;

  BreederFeedEntry({
    required this.id,
    required this.reportId,
    this.houseId,
    this.isolationAreaId,
    required this.sex,
    required this.feedKg,
  }) {
    final hasHouse = houseId != null && houseId!.isNotEmpty;
    final hasIsolation = isolationAreaId != null && isolationAreaId!.isNotEmpty;
    if (hasHouse == hasIsolation) {
      throw ArgumentError(
        'A feed entry must name exactly one location: a house or an '
        'isolation area (houseId=$houseId, isolationAreaId=$isolationAreaId)',
      );
    }
  }

  bool get isFemale => sex == 'female';
  bool get isMale => sex == 'male';

  /// True when this feed entry belongs to a production house.
  bool get isHouseEntry => houseId != null;

  /// True when this feed entry belongs to a named isolation area.
  bool get isIsolationEntry => isolationAreaId != null;

  /// The id of whichever location this entry names — a house or an
  /// isolation area. Convenience for display code that doesn't need to care
  /// which kind of location it is.
  String get locationId => houseId ?? isolationAreaId!;

  factory BreederFeedEntry.fromMap(Map<String, dynamic> map) {
    return BreederFeedEntry(
      id: map['id'] as String,
      reportId: map['reportId'] as String,
      houseId: map['houseId']?.toString(),
      isolationAreaId: map['isolationAreaId']?.toString(),
      sex: map['sex'] as String,
      feedKg: (map['feedKg'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'reportId': reportId,
      'houseId': houseId,
      'isolationAreaId': isolationAreaId,
      'sex': sex,
      'feedKg': feedKg,
    };
  }

  BreederFeedEntry copyWith({
    String? id,
    String? reportId,
    String? houseId,
    String? isolationAreaId,
    String? sex,
    double? feedKg,
  }) {
    return BreederFeedEntry(
      id: id ?? this.id,
      reportId: reportId ?? this.reportId,
      houseId: houseId ?? this.houseId,
      isolationAreaId: isolationAreaId ?? this.isolationAreaId,
      sex: sex ?? this.sex,
      feedKg: feedKg ?? this.feedKg,
    );
  }
}
