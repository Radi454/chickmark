/// A periodic weighing session for one flock/house/sex/date
/// (breeder-flock-performance ticket 13, design doc section 5.1 and 9):
/// "Periodic weight and uniformity entry is a separate workflow linked to
/// flock, house, sex, and date." A session is never attached to a
/// `breeder_daily_reports` row.
///
/// [derivedMeanWeightG]/[derivedUniformityPct]/[derivedCvPct] and the
/// `comparison*` fields are caches written exclusively by
/// `BreederWeighingService.computeAndSaveDerived` — never independently
/// editable. The authoritative inputs are the session's
/// `BreederWeighingSample` rows (via `BreederWeighingSampleRepository`), or
/// none at all for a summary-only session, in which case the derived
/// figures stay null rather than becoming `0`.
///
/// [comparisonProfileId]/[comparisonProfileGuideVersion]/
/// [comparisonAxisKind]/[comparisonAxisOffsetWeeks] preserve the exact
/// benchmark profile version and comparison axis used for
/// [comparisonTargetWeightG] (design section 9 and 3.1: "every stored
/// comparison ... records which axis produced it alongside the benchmark
/// profile version"). [comparisonProfileGuideVersion] is a denormalized
/// snapshot of `BreederBenchmarkProfile.guideVersion` at comparison time,
/// so the exact version used remains legible even if the profile is later
/// archived or superseded.
library;

class BreederWeighingSessionSex {
  static const female = 'female';
  static const male = 'male';
  static const all = [female, male];
}

class BreederWeighingComparisonAxisKind {
  static const official = 'official';
  static const milestoneAligned = 'milestoneAligned';
}

class BreederWeighingSession {
  final String id;
  final String flockId;
  final String houseId;
  final DateTime sessionDate;
  final String sex;
  final String method;
  final int sampleSize;
  final String? notes;

  final double? derivedMeanWeightG;
  final double? derivedUniformityPct;
  final double? derivedCvPct;

  final String? comparisonProfileId;
  final String? comparisonProfileGuideVersion;
  final String? comparisonAxisKind;
  final int? comparisonAxisOffsetWeeks;
  final double? comparisonTargetWeightG;

  const BreederWeighingSession({
    required this.id,
    required this.flockId,
    required this.houseId,
    required this.sessionDate,
    required this.sex,
    required this.method,
    required this.sampleSize,
    this.notes,
    this.derivedMeanWeightG,
    this.derivedUniformityPct,
    this.derivedCvPct,
    this.comparisonProfileId,
    this.comparisonProfileGuideVersion,
    this.comparisonAxisKind,
    this.comparisonAxisOffsetWeeks,
    this.comparisonTargetWeightG,
  });

  static String dateKey(DateTime date) =>
      DateTime(date.year, date.month, date.day).toIso8601String().split('T').first;

  factory BreederWeighingSession.fromMap(Map<String, dynamic> map) {
    return BreederWeighingSession(
      id: map['id'] as String,
      flockId: map['flockId'] as String,
      houseId: map['houseId'] as String,
      sessionDate: DateTime.parse(map['sessionDate'] as String),
      sex: map['sex'] as String,
      method: map['method'] as String,
      sampleSize: (map['sampleSize'] as num).toInt(),
      notes: map['notes'] as String?,
      derivedMeanWeightG: (map['derivedMeanWeightG'] as num?)?.toDouble(),
      derivedUniformityPct: (map['derivedUniformityPct'] as num?)?.toDouble(),
      derivedCvPct: (map['derivedCvPct'] as num?)?.toDouble(),
      comparisonProfileId: map['comparisonProfileId'] as String?,
      comparisonProfileGuideVersion:
          map['comparisonProfileGuideVersion'] as String?,
      comparisonAxisKind: map['comparisonAxisKind'] as String?,
      comparisonAxisOffsetWeeks:
          (map['comparisonAxisOffsetWeeks'] as num?)?.toInt(),
      comparisonTargetWeightG:
          (map['comparisonTargetWeightG'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'flockId': flockId,
      'houseId': houseId,
      'sessionDate': dateKey(sessionDate),
      'sex': sex,
      'method': method,
      'sampleSize': sampleSize,
      'notes': notes,
      'derivedMeanWeightG': derivedMeanWeightG,
      'derivedUniformityPct': derivedUniformityPct,
      'derivedCvPct': derivedCvPct,
      'comparisonProfileId': comparisonProfileId,
      'comparisonProfileGuideVersion': comparisonProfileGuideVersion,
      'comparisonAxisKind': comparisonAxisKind,
      'comparisonAxisOffsetWeeks': comparisonAxisOffsetWeeks,
      'comparisonTargetWeightG': comparisonTargetWeightG,
    };
  }

  BreederWeighingSession copyWith({
    String? houseId,
    DateTime? sessionDate,
    String? sex,
    String? method,
    int? sampleSize,
    String? notes,
    bool clearNotes = false,
    double? derivedMeanWeightG,
    double? derivedUniformityPct,
    double? derivedCvPct,
    bool clearDerived = false,
    String? comparisonProfileId,
    String? comparisonProfileGuideVersion,
    String? comparisonAxisKind,
    int? comparisonAxisOffsetWeeks,
    double? comparisonTargetWeightG,
    bool clearComparison = false,
  }) {
    return BreederWeighingSession(
      id: id,
      flockId: flockId,
      houseId: houseId ?? this.houseId,
      sessionDate: sessionDate ?? this.sessionDate,
      sex: sex ?? this.sex,
      method: method ?? this.method,
      sampleSize: sampleSize ?? this.sampleSize,
      notes: clearNotes ? null : (notes ?? this.notes),
      derivedMeanWeightG: clearDerived
          ? null
          : (derivedMeanWeightG ?? this.derivedMeanWeightG),
      derivedUniformityPct: clearDerived
          ? null
          : (derivedUniformityPct ?? this.derivedUniformityPct),
      derivedCvPct: clearDerived ? null : (derivedCvPct ?? this.derivedCvPct),
      comparisonProfileId: clearComparison
          ? null
          : (comparisonProfileId ?? this.comparisonProfileId),
      comparisonProfileGuideVersion: clearComparison
          ? null
          : (comparisonProfileGuideVersion ?? this.comparisonProfileGuideVersion),
      comparisonAxisKind: clearComparison
          ? null
          : (comparisonAxisKind ?? this.comparisonAxisKind),
      comparisonAxisOffsetWeeks: clearComparison
          ? null
          : (comparisonAxisOffsetWeeks ?? this.comparisonAxisOffsetWeeks),
      comparisonTargetWeightG: clearComparison
          ? null
          : (comparisonTargetWeightG ?? this.comparisonTargetWeightG),
    );
  }

  /// True once samples have been recorded and derived (mean weight is
  /// always present when derivation has happened, even if the sample count
  /// was 1). False for a summary-only session with no samples.
  bool get hasDerivedFigures => derivedMeanWeightG != null;
}

/// One individual bird's weight for a session
/// (breeder-flock-performance ticket 13, design doc section 9: "optionally
/// records individual bird weights"). [weightGrams] is never negative.
class BreederWeighingSample {
  final String id;
  final String sessionId;
  final double weightGrams;

  BreederWeighingSample({
    required this.id,
    required this.sessionId,
    required this.weightGrams,
  }) {
    if (weightGrams < 0) {
      throw ArgumentError.value(
        weightGrams,
        'weightGrams',
        'A bird weight cannot be negative',
      );
    }
  }

  factory BreederWeighingSample.fromMap(Map<String, dynamic> map) {
    return BreederWeighingSample(
      id: map['id'] as String,
      sessionId: map['sessionId'] as String,
      weightGrams: (map['weightGrams'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'sessionId': sessionId, 'weightGrams': weightGrams};
  }
}
