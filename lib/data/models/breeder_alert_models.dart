/// Performance-alert data model (breeder-flock-performance ticket 17,
/// design doc section 10 and 12).
///
/// `breeder_alert_rules` is system-wide reference data (seeded, read-only
/// client-side — mirrors `breeder_metric_definitions`/
/// `breeder_benchmark_profiles`): the app's OWN operational judgement about
/// how far a metric may drift from the official benchmark before a Watch or
/// a Critical alert is warranted, and how many consecutive qualifying
/// observations are required before that judgement fires at all. These
/// thresholds are never Aviagen's, Cobb's, or any breed company's — see
/// [BreederAlertRule.usesOfficialBound] for the one exception the design
/// carves out (a metric the official guide itself bounds).
///
/// `breeder_performance_alerts` is the operational record of one deviation
/// against one customer/flock/(house)/metric/period, carrying both the
/// actual value and whatever the official guide published for comparison
/// (target and/or bound), the app's own severity classification, which
/// benchmark profile version and comparison axis (ticket 06) produced the
/// comparison, and a `new`/`seen`/`closed` lifecycle state.
library;

/// The fixed vocabulary of metrics this feature alerts on. Deliberately
/// smaller than the full `breeder_metric_definitions` catalogue: alerting
/// is scoped to the metrics judged operationally significant enough to
/// interrupt a user (design section 10 gives no exhaustive list, so this
/// set is this ticket's own judgment call — see the implementation report).
/// [uniformityPct] and [cvPct] intentionally have NO row in
/// `breeder_metric_definitions` or any benchmark profile: the Ross 308
/// guide publishes no uniformity or CV target at all (design section 10),
/// so a rule against either metric can never legitimately set
/// [BreederAlertRule.usesOfficialBound] true.
class BreederAlertMetric {
  static const String bodyWeightG = 'body_weight_g';
  static const String henWeekProductionPct = 'hen_week_production_pct';
  static const String liveabilityRearingPct = 'liveability_rearing_pct';
  static const String uniformityPct = 'uniformity_pct';
  static const String cvPct = 'cv_pct';

  static const List<String> all = [
    bodyWeightG,
    henWeekProductionPct,
    liveabilityRearingPct,
    uniformityPct,
    cvPct,
  ];

  static bool isValid(String value) => all.contains(value);
}

class BreederAlertScope {
  static const String flock = 'flock';
  static const String house = 'house';
  static const List<String> all = [flock, house];
}

class BreederAlertPeriodType {
  static const String daily = 'daily';
  static const String weekly = 'weekly';
  static const String cumulative = 'cumulative';
  static const List<String> all = [daily, weekly, cumulative];
}

/// Which side of the target/bound counts as a deviation for a given rule.
/// `below` fires when the actual value falls under the target/lower bound
/// (e.g. body weight, production, liveability); `above` fires when it rises
/// over the target/upper bound (e.g. CV — tighter is better, so a rising CV
/// is the deviation); `either` fires on both sides (e.g. body weight, which
/// is unhealthy both under- and over-target).
class BreederAlertDirection {
  static const String below = 'below';
  static const String above = 'above';
  static const String either = 'either';
  static const List<String> all = [below, above, either];
}

class BreederAlertSeverity {
  static const String watch = 'watch';
  static const String critical = 'critical';
  static const List<String> all = [watch, critical];
}

class BreederPerformanceAlertState {
  static const String new_ = 'new';
  static const String seen = 'seen';
  static const String closed = 'closed';
  static const List<String> all = [new_, seen, closed];
}

/// A system-wide Watch/Critical deviation rule (design section 10).
class BreederAlertRule {
  final String id;
  final String metricCode;
  final String scope;
  final String periodType;
  final String direction;

  /// Percentage-point (relative, `usesOfficialBound == false`) or
  /// percentage-of-bound (`usesOfficialBound == true`) deviation at which a
  /// Watch alert is warranted. Always the app's own judgement — see
  /// [usesOfficialBound]'s doc comment for how it is used differently in
  /// each mode.
  final double watchDeviationPct;

  /// As [watchDeviationPct], for Critical. Ignored entirely when
  /// [usesOfficialBound] is true: in that mode Critical means "breached the
  /// official bound", a fixed line rather than a percentage.
  final double criticalDeviationPct;

  /// How many consecutive qualifying observations (design section 10: "how
  /// many consecutive observations required") must be seen before this rule
  /// is allowed to create or escalate an alert at all — see
  /// `BreederAlertEvaluationService`'s doc comment for the exact contract.
  final int consecutiveObservationsRequired;

  /// True only when the official guide itself publishes a lower/upper
  /// bound for [metricCode] (design section 10 / ticket 03: Ross 308
  /// publishes bounds for a few metrics, e.g. rearing liveability, but a
  /// target-only value — no bound — for most, and NO value at all for
  /// uniformity/CV). When true, a Critical alert cites the official bound
  /// directly (`thresholdIsOfficial = true` on the resulting alert); the
  /// Watch zone approaching that bound is still the app's own early
  /// -warning judgement, since the guide publishes no such warning zone
  /// (`thresholdIsOfficial = false` for a Watch alert even under this
  /// rule). When false, both Watch and Critical are entirely the app's own
  /// relative-deviation-from-target judgement.
  final bool usesOfficialBound;
  final bool isActive;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BreederAlertRule({
    required this.id,
    required this.metricCode,
    required this.scope,
    required this.periodType,
    required this.direction,
    required this.watchDeviationPct,
    required this.criticalDeviationPct,
    required this.consecutiveObservationsRequired,
    required this.usesOfficialBound,
    this.isActive = true,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BreederAlertRule.fromMap(Map<String, dynamic> map) {
    return BreederAlertRule(
      id: map['id'] as String,
      metricCode: map['metricCode'] as String,
      scope: map['scope'] as String,
      periodType: map['periodType'] as String,
      direction: map['direction'] as String,
      watchDeviationPct: (map['watchDeviationPct'] as num).toDouble(),
      criticalDeviationPct: (map['criticalDeviationPct'] as num).toDouble(),
      consecutiveObservationsRequired:
          (map['consecutiveObservationsRequired'] as num).toInt(),
      usesOfficialBound: (map['usesOfficialBound'] as int? ?? 0) == 1,
      isActive: (map['isActive'] as int? ?? 1) == 1,
      notes: map['notes']?.toString(),
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'metricCode': metricCode,
      'scope': scope,
      'periodType': periodType,
      'direction': direction,
      'watchDeviationPct': watchDeviationPct,
      'criticalDeviationPct': criticalDeviationPct,
      'consecutiveObservationsRequired': consecutiveObservationsRequired,
      'usesOfficialBound': usesOfficialBound ? 1 : 0,
      'isActive': isActive ? 1 : 0,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

/// One recorded deviation against a customer/flock/(house)/metric/period
/// (design section 10 and 12).
class BreederPerformanceAlert {
  final String id;
  final String? customerId;
  final String flockId;
  final String? houseId;
  final String ruleId;
  final String metricCode;
  final String scope;
  final String periodType;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double actualValue;
  final double? officialTargetValue;
  final double? officialLowerBound;
  final double? officialUpperBound;

  /// True when the threshold actually cited for THIS alert's severity is
  /// the official guide's own published bound; false when it is the app's
  /// own operational judgement (design section 10's central rule). Recorded
  /// per-alert (not read live off the rule) so the label stays accurate
  /// even if the rule is edited later.
  final bool thresholdIsOfficial;
  final double deviationValue;
  final double? deviationPct;
  final String severity;
  final int consecutiveObservationCount;
  final String? benchmarkProfileId;

  /// The benchmark guide version in effect when this alert was (last)
  /// evaluated (ticket 03's `guideVersion`) — carried on the alert itself
  /// so history stays accurate if the profile is later superseded.
  final String? benchmarkProfileVersion;

  /// Ticket 06's comparison axis that produced [officialTargetValue]/
  /// [officialLowerBound]/[officialUpperBound]. Null only when no benchmark
  /// profile matched at all.
  final String? comparisonAxisKind;
  final int? comparisonAxisOffsetWeeks;

  /// Every approved report date (design section 12) whose data fed this
  /// alert's most recent evaluation — never a hard foreign key, since the
  /// daily-report aggregate pushes through its own guarded transaction (see
  /// `PerformanceSyncRepository.breederAggregatePullOnly`'s doc comment) and
  /// must not gate this table's push order. Used by
  /// `BreederAlertEvaluationService.recomputeAffectedByRevision` to find
  /// every alert a report revision might have invalidated.
  final List<DateTime> evidenceReportDates;

  final String state;

  /// System-authored reason recorded when a revision clears this alert's
  /// condition (design section 10: "closed with a system reason recording
  /// the revision that cleared it") — null for every other close, and for
  /// every non-closed alert.
  final String? closedReason;
  final DateTime? closedAt;
  final DateTime? acknowledgedAt;
  final String? acknowledgedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BreederPerformanceAlert({
    required this.id,
    this.customerId,
    required this.flockId,
    this.houseId,
    required this.ruleId,
    required this.metricCode,
    required this.scope,
    required this.periodType,
    required this.periodStart,
    required this.periodEnd,
    required this.actualValue,
    this.officialTargetValue,
    this.officialLowerBound,
    this.officialUpperBound,
    required this.thresholdIsOfficial,
    required this.deviationValue,
    this.deviationPct,
    required this.severity,
    this.consecutiveObservationCount = 1,
    this.benchmarkProfileId,
    this.benchmarkProfileVersion,
    this.comparisonAxisKind,
    this.comparisonAxisOffsetWeeks,
    required this.evidenceReportDates,
    this.state = BreederPerformanceAlertState.new_,
    this.closedReason,
    this.closedAt,
    this.acknowledgedAt,
    this.acknowledgedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isOpen => state != BreederPerformanceAlertState.closed;

  static String _dateKey(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).toIso8601String();

  static List<DateTime> _decodeDates(Object? raw) {
    if (raw == null) return const [];
    final list = raw is String
        ? (raw.isEmpty ? const [] : raw.split(','))
        : const <String>[];
    return list
        .map((value) => DateTime.parse(value.toString()))
        .toList(growable: false);
  }

  static String _encodeDates(List<DateTime> dates) =>
      dates.map(_dateKey).join(',');

  factory BreederPerformanceAlert.fromMap(Map<String, dynamic> map) {
    return BreederPerformanceAlert(
      id: map['id'] as String,
      customerId: map['customerId']?.toString(),
      flockId: map['flockId'] as String,
      houseId: map['houseId']?.toString(),
      ruleId: map['ruleId'] as String,
      metricCode: map['metricCode'] as String,
      scope: map['scope'] as String,
      periodType: map['periodType'] as String,
      periodStart: DateTime.parse(map['periodStart'] as String),
      periodEnd: DateTime.parse(map['periodEnd'] as String),
      actualValue: (map['actualValue'] as num).toDouble(),
      officialTargetValue: (map['officialTargetValue'] as num?)?.toDouble(),
      officialLowerBound: (map['officialLowerBound'] as num?)?.toDouble(),
      officialUpperBound: (map['officialUpperBound'] as num?)?.toDouble(),
      thresholdIsOfficial: (map['thresholdIsOfficial'] as int? ?? 0) == 1,
      deviationValue: (map['deviationValue'] as num).toDouble(),
      deviationPct: (map['deviationPct'] as num?)?.toDouble(),
      severity: map['severity'] as String,
      consecutiveObservationCount:
          (map['consecutiveObservationCount'] as num?)?.toInt() ?? 1,
      benchmarkProfileId: map['benchmarkProfileId']?.toString(),
      benchmarkProfileVersion: map['benchmarkProfileVersion']?.toString(),
      comparisonAxisKind: map['comparisonAxisKind']?.toString(),
      comparisonAxisOffsetWeeks: (map['comparisonAxisOffsetWeeks'] as num?)
          ?.toInt(),
      evidenceReportDates: _decodeDates(map['evidenceReportDatesJson']),
      state: map['state'] as String? ?? BreederPerformanceAlertState.new_,
      closedReason: map['closedReason']?.toString(),
      closedAt: map['closedAt'] == null
          ? null
          : DateTime.parse(map['closedAt'] as String),
      acknowledgedAt: map['acknowledgedAt'] == null
          ? null
          : DateTime.parse(map['acknowledgedAt'] as String),
      acknowledgedBy: map['acknowledgedBy']?.toString(),
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerId': customerId,
      'flockId': flockId,
      'houseId': houseId,
      'ruleId': ruleId,
      'metricCode': metricCode,
      'scope': scope,
      'periodType': periodType,
      'periodStart': _dateKey(periodStart),
      'periodEnd': _dateKey(periodEnd),
      'actualValue': actualValue,
      'officialTargetValue': officialTargetValue,
      'officialLowerBound': officialLowerBound,
      'officialUpperBound': officialUpperBound,
      'thresholdIsOfficial': thresholdIsOfficial ? 1 : 0,
      'deviationValue': deviationValue,
      'deviationPct': deviationPct,
      'severity': severity,
      'consecutiveObservationCount': consecutiveObservationCount,
      'benchmarkProfileId': benchmarkProfileId,
      'benchmarkProfileVersion': benchmarkProfileVersion,
      'comparisonAxisKind': comparisonAxisKind,
      'comparisonAxisOffsetWeeks': comparisonAxisOffsetWeeks,
      'evidenceReportDatesJson': _encodeDates(evidenceReportDates),
      'state': state,
      'closedReason': closedReason,
      'closedAt': closedAt == null ? null : _dateKey(closedAt!),
      'acknowledgedAt': acknowledgedAt == null
          ? null
          : _dateKey(acknowledgedAt!),
      'acknowledgedBy': acknowledgedBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  BreederPerformanceAlert copyWith({
    double? actualValue,
    double? officialTargetValue,
    double? officialLowerBound,
    double? officialUpperBound,
    bool? thresholdIsOfficial,
    double? deviationValue,
    double? deviationPct,
    String? severity,
    int? consecutiveObservationCount,
    String? benchmarkProfileId,
    String? benchmarkProfileVersion,
    String? comparisonAxisKind,
    int? comparisonAxisOffsetWeeks,
    List<DateTime>? evidenceReportDates,
    String? state,
    String? closedReason,
    DateTime? closedAt,
    DateTime? acknowledgedAt,
    String? acknowledgedBy,
    DateTime? updatedAt,
  }) {
    return BreederPerformanceAlert(
      id: id,
      customerId: customerId,
      flockId: flockId,
      houseId: houseId,
      ruleId: ruleId,
      metricCode: metricCode,
      scope: scope,
      periodType: periodType,
      periodStart: periodStart,
      periodEnd: periodEnd,
      actualValue: actualValue ?? this.actualValue,
      officialTargetValue: officialTargetValue ?? this.officialTargetValue,
      officialLowerBound: officialLowerBound ?? this.officialLowerBound,
      officialUpperBound: officialUpperBound ?? this.officialUpperBound,
      thresholdIsOfficial: thresholdIsOfficial ?? this.thresholdIsOfficial,
      deviationValue: deviationValue ?? this.deviationValue,
      deviationPct: deviationPct ?? this.deviationPct,
      severity: severity ?? this.severity,
      consecutiveObservationCount:
          consecutiveObservationCount ?? this.consecutiveObservationCount,
      benchmarkProfileId: benchmarkProfileId ?? this.benchmarkProfileId,
      benchmarkProfileVersion:
          benchmarkProfileVersion ?? this.benchmarkProfileVersion,
      comparisonAxisKind: comparisonAxisKind ?? this.comparisonAxisKind,
      comparisonAxisOffsetWeeks:
          comparisonAxisOffsetWeeks ?? this.comparisonAxisOffsetWeeks,
      evidenceReportDates: evidenceReportDates ?? this.evidenceReportDates,
      state: state ?? this.state,
      closedReason: closedReason ?? this.closedReason,
      closedAt: closedAt ?? this.closedAt,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      acknowledgedBy: acknowledgedBy ?? this.acknowledgedBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
