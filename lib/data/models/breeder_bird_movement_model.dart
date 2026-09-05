/// One location's bird-movement ledger row for one sex on one daily report
/// (breeder-flock-performance ticket 07, design doc section 5.2 and 6;
/// extended by ticket 08, design doc section 6, to add isolation areas as a
/// second kind of location).
///
/// A movement's location is either a house ([houseId]) or an isolation area
/// ([isolationAreaId]) — exactly one, never both, never neither. That is
/// enforced here (the constructor rejects anything else) and again by the
/// database's own CHECK constraint, so a row can never be persisted
/// ambiguous about where it happened.
///
/// `opening` and `closing` are derived and persisted by
/// `BreederBirdLedgerService` — never typed directly by a user. The
/// underlying table additionally enforces
/// `closing = opening - removals + transfers` as a CHECK constraint so a
/// row can never be stored inconsistent with its own inputs.
library;

class BreederBirdMovementSex {
  static const String female = 'female';
  static const String male = 'male';

  static const List<String> all = [female, male];

  static bool isValid(String value) => all.contains(value);
}

class BreederBirdMovement {
  final String id;
  final String reportId;

  /// Non-null when this movement happened in a production house. Exactly
  /// one of [houseId]/[isolationAreaId] is ever set.
  final String? houseId;

  /// Non-null when this movement happened in a named isolation area.
  /// Exactly one of [houseId]/[isolationAreaId] is ever set.
  final String? isolationAreaId;

  final String sex;

  final int opening;
  final int mortality;
  final int culls;
  final int sale;

  /// Female-only removal ("kitchen removal"). Always 0 for a male row.
  final int kitchenRemoval;

  /// Male-only removal ("euthanasia"). Always 0 for a female row.
  final int euthanasia;

  final int transferIn;
  final int transferOut;
  final int closing;

  BreederBirdMovement({
    required this.id,
    required this.reportId,
    this.houseId,
    this.isolationAreaId,
    required this.sex,
    required this.opening,
    this.mortality = 0,
    this.culls = 0,
    this.sale = 0,
    this.kitchenRemoval = 0,
    this.euthanasia = 0,
    this.transferIn = 0,
    this.transferOut = 0,
    required this.closing,
  }) {
    final hasHouse = houseId != null && houseId!.isNotEmpty;
    final hasIsolation = isolationAreaId != null && isolationAreaId!.isNotEmpty;
    if (hasHouse == hasIsolation) {
      throw ArgumentError(
        'A movement must name exactly one location: a house or an '
        'isolation area (houseId=$houseId, isolationAreaId=$isolationAreaId)',
      );
    }
  }

  bool get isFemale => sex == BreederBirdMovementSex.female;
  bool get isMale => sex == BreederBirdMovementSex.male;

  /// True when this movement happened in a production house.
  bool get isHouseMovement => houseId != null;

  /// True when this movement happened in a named isolation area.
  bool get isIsolationMovement => isolationAreaId != null;

  /// The id of whichever location this movement names — a house or an
  /// isolation area. Convenience for display code that doesn't need to care
  /// which kind of location it is.
  String get locationId => houseId ?? isolationAreaId!;

  /// The sex-specific removal that occupies the "kitchen removal /
  /// euthanasia" slot in the paper report (design section 5.2).
  int get sexSpecificRemoval => isFemale ? kitchenRemoval : euthanasia;

  int get permanentRemovals =>
      mortality + culls + sale + kitchenRemoval + euthanasia;

  int get netTransfers => transferIn - transferOut;

  factory BreederBirdMovement.fromMap(Map<String, dynamic> map) {
    return BreederBirdMovement(
      id: map['id'] as String,
      reportId: map['reportId'] as String,
      houseId: map['houseId']?.toString(),
      isolationAreaId: map['isolationAreaId']?.toString(),
      sex: map['sex'] as String,
      opening: (map['opening'] as num?)?.toInt() ?? 0,
      mortality: (map['mortality'] as num?)?.toInt() ?? 0,
      culls: (map['culls'] as num?)?.toInt() ?? 0,
      sale: (map['sale'] as num?)?.toInt() ?? 0,
      kitchenRemoval: (map['kitchenRemoval'] as num?)?.toInt() ?? 0,
      euthanasia: (map['euthanasia'] as num?)?.toInt() ?? 0,
      transferIn: (map['transferIn'] as num?)?.toInt() ?? 0,
      transferOut: (map['transferOut'] as num?)?.toInt() ?? 0,
      closing: (map['closing'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'reportId': reportId,
      'houseId': houseId,
      'isolationAreaId': isolationAreaId,
      'sex': sex,
      'opening': opening,
      'mortality': mortality,
      'culls': culls,
      'sale': sale,
      'kitchenRemoval': kitchenRemoval,
      'euthanasia': euthanasia,
      'transferIn': transferIn,
      'transferOut': transferOut,
      'closing': closing,
    };
  }

  BreederBirdMovement copyWith({
    String? id,
    String? reportId,
    String? houseId,
    String? isolationAreaId,
    String? sex,
    int? opening,
    int? mortality,
    int? culls,
    int? sale,
    int? kitchenRemoval,
    int? euthanasia,
    int? transferIn,
    int? transferOut,
    int? closing,
  }) {
    return BreederBirdMovement(
      id: id ?? this.id,
      reportId: reportId ?? this.reportId,
      houseId: houseId ?? this.houseId,
      isolationAreaId: isolationAreaId ?? this.isolationAreaId,
      sex: sex ?? this.sex,
      opening: opening ?? this.opening,
      mortality: mortality ?? this.mortality,
      culls: culls ?? this.culls,
      sale: sale ?? this.sale,
      kitchenRemoval: kitchenRemoval ?? this.kitchenRemoval,
      euthanasia: euthanasia ?? this.euthanasia,
      transferIn: transferIn ?? this.transferIn,
      transferOut: transferOut ?? this.transferOut,
      closing: closing ?? this.closing,
    );
  }
}
