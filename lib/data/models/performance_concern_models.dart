import 'dart:convert';

enum AlertRuleScope {
  global('global'),
  customer('customer');

  const AlertRuleScope(this.storageKey);
  final String storageKey;

  static AlertRuleScope fromStorage(Object? value) =>
      value?.toString() == 'customer' ? customer : global;
}

enum AlertRuleDirection {
  above('above'),
  below('below'),
  outsideRange('outside_range'),
  rateOfChange('rate_of_change');

  const AlertRuleDirection(this.storageKey);
  final String storageKey;

  static AlertRuleDirection fromStorage(Object? value) => values.firstWhere(
    (item) => item.storageKey == value?.toString(),
    orElse: () => above,
  );
}

enum ConcernSeverity {
  watch('watch'),
  critical('critical');

  const ConcernSeverity(this.storageKey);
  final String storageKey;

  static ConcernSeverity fromStorage(Object? value) =>
      value?.toString() == 'critical' ? critical : watch;
}

enum ConcernStatus {
  open('open'),
  monitoring('monitoring'),
  assignedToVisit('assigned_to_visit'),
  resolved('resolved'),
  dismissed('dismissed');

  const ConcernStatus(this.storageKey);
  final String storageKey;

  static ConcernStatus fromStorage(Object? value) => values.firstWhere(
    (item) => item.storageKey == value?.toString(),
    orElse: () => open,
  );
}

class PerformanceAlertRule {
  const PerformanceAlertRule({
    required this.id,
    required this.metricKey,
    required this.scopeLevel,
    required this.direction,
    required this.source,
    this.customerId,
    this.watchThreshold,
    this.criticalThreshold,
    this.lowerThreshold,
    this.upperThreshold,
    this.persistenceWindow = 1,
    this.minimumValidObservations = 1,
    this.rationale,
    this.isEnabled = true,
  });

  final String id;
  final String metricKey;
  final AlertRuleScope scopeLevel;
  final String? customerId;
  final double? watchThreshold;
  final double? criticalThreshold;
  final double? lowerThreshold;
  final double? upperThreshold;
  final AlertRuleDirection direction;
  final int persistenceWindow;
  final int minimumValidObservations;
  final String source;
  final String? rationale;
  final bool isEnabled;

  factory PerformanceAlertRule.fromMap(Map<String, Object?> map) {
    return PerformanceAlertRule(
      id: map['id']! as String,
      metricKey: map['metricKey']! as String,
      scopeLevel: AlertRuleScope.fromStorage(map['scopeLevel']),
      customerId: map['customerId'] as String?,
      watchThreshold: _number(map['watchThreshold']),
      criticalThreshold: _number(map['criticalThreshold']),
      lowerThreshold: _number(map['lowerThreshold']),
      upperThreshold: _number(map['upperThreshold']),
      direction: AlertRuleDirection.fromStorage(map['direction']),
      persistenceWindow: _integer(map['persistenceWindow']) ?? 1,
      minimumValidObservations: _integer(map['minimumValidObservations']) ?? 1,
      source: map['source']! as String,
      rationale: map['rationale'] as String?,
      isEnabled: _bool(map['isEnabled'], fallback: true),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'metricKey': metricKey,
    'scopeLevel': scopeLevel.storageKey,
    'customerId': customerId,
    'watchThreshold': watchThreshold,
    'criticalThreshold': criticalThreshold,
    'lowerThreshold': lowerThreshold,
    'upperThreshold': upperThreshold,
    'direction': direction.storageKey,
    'persistenceWindow': persistenceWindow,
    'minimumValidObservations': minimumValidObservations,
    'source': source,
    'rationale': rationale,
    'isEnabled': isEnabled ? 1 : 0,
  };
}

class PerformanceAlertObservation {
  const PerformanceAlertObservation({
    required this.metricKey,
    required this.observedAt,
    required this.value,
    this.targetValue,
    this.isValid = true,
    this.hasOperationalEvent = false,
    this.openingBirds,
    this.closingBirds,
    this.mortality,
    this.culls,
  });

  final String metricKey;
  final DateTime observedAt;
  final double? value;
  final double? targetValue;
  final bool isValid;
  final bool hasOperationalEvent;
  final int? openingBirds;
  final int? closingBirds;
  final int? mortality;
  final int? culls;

  PerformanceAlertObservation copyWith({bool? hasOperationalEvent}) {
    return PerformanceAlertObservation(
      metricKey: metricKey,
      observedAt: observedAt,
      value: value,
      targetValue: targetValue,
      isValid: isValid,
      hasOperationalEvent: hasOperationalEvent ?? this.hasOperationalEvent,
      openingBirds: openingBirds,
      closingBirds: closingBirds,
      mortality: mortality,
      culls: culls,
    );
  }
}

class PerformanceAlertDetection {
  const PerformanceAlertDetection({
    required this.ruleId,
    required this.metricKey,
    required this.severity,
    required this.observedAt,
    required this.windowStart,
    required this.windowEnd,
    required this.actualValue,
    required this.customerId,
    this.baselineValue,
    this.targetValue,
    this.farmId,
    this.flockId,
    this.placementId,
    this.houseId,
    this.evidence = const {},
    this.investigationKeys = const [],
  });

  final String ruleId;
  final String metricKey;
  final ConcernSeverity severity;
  final DateTime observedAt;
  final DateTime windowStart;
  final DateTime windowEnd;
  final double actualValue;
  final double? baselineValue;
  final double? targetValue;
  final String customerId;
  final String? farmId;
  final String? flockId;
  final String? placementId;
  final String? houseId;
  final Map<String, Object?> evidence;
  final List<String> investigationKeys;
}

class PerformanceConcern {
  const PerformanceConcern({
    required this.id,
    required this.customerId,
    required this.metricKey,
    required this.severity,
    required this.firstObservedAt,
    required this.lastObservedAt,
    required this.status,
    this.ruleId,
    this.farmId,
    this.flockId,
    this.placementId,
    this.houseId,
    this.evidenceWindowStart,
    this.evidenceWindowEnd,
    this.baselineValue,
    this.targetValue,
    this.actualValue,
    this.evidence = const {},
    this.resolvedAt,
    this.resolvedBy,
    this.resolutionNotes,
    this.dismissedAt,
    this.dismissedBy,
    this.dismissalReason,
    this.recurrenceOfId,
  });

  final String id;
  final String? ruleId;
  final String customerId;
  final String? farmId;
  final String? flockId;
  final String? placementId;
  final String? houseId;
  final String metricKey;
  final ConcernSeverity severity;
  final DateTime firstObservedAt;
  final DateTime lastObservedAt;
  final DateTime? evidenceWindowStart;
  final DateTime? evidenceWindowEnd;
  final double? baselineValue;
  final double? targetValue;
  final double? actualValue;
  final Map<String, Object?> evidence;
  final ConcernStatus status;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? resolutionNotes;
  final DateTime? dismissedAt;
  final String? dismissedBy;
  final String? dismissalReason;
  final String? recurrenceOfId;

  factory PerformanceConcern.fromMap(Map<String, Object?> map) {
    final evidenceText = map['evidenceJson']?.toString();
    return PerformanceConcern(
      id: map['id']! as String,
      ruleId: map['ruleId'] as String?,
      customerId: map['customerId']! as String,
      farmId: map['farmId'] as String?,
      flockId: map['flockId'] as String?,
      placementId: map['placementId'] as String?,
      houseId: map['houseId'] as String?,
      metricKey: map['metricKey']! as String,
      severity: ConcernSeverity.fromStorage(map['severity']),
      firstObservedAt: DateTime.parse(map['firstObservedAt']! as String),
      lastObservedAt: DateTime.parse(map['lastObservedAt']! as String),
      evidenceWindowStart: _date(map['evidenceWindowStart']),
      evidenceWindowEnd: _date(map['evidenceWindowEnd']),
      baselineValue: _number(map['baselineValue']),
      targetValue: _number(map['targetValue']),
      actualValue: _number(map['actualValue']),
      evidence: evidenceText == null || evidenceText.isEmpty
          ? const {}
          : Map<String, Object?>.from(jsonDecode(evidenceText) as Map),
      status: ConcernStatus.fromStorage(map['status']),
      resolvedAt: _date(map['resolvedAt']),
      resolvedBy: map['resolvedBy'] as String?,
      resolutionNotes: map['resolutionNotes'] as String?,
      dismissedAt: _date(map['dismissedAt']),
      dismissedBy: map['dismissedBy'] as String?,
      dismissalReason: map['dismissalReason'] as String?,
      recurrenceOfId: map['recurrenceOfId'] as String?,
    );
  }
}

double? _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
int? _integer(Object? value) =>
    value is int ? value : int.tryParse('${value ?? ''}');
bool _bool(Object? value, {bool fallback = false}) =>
    value == null ? fallback : value == true || value == 1 || value == '1';
DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());
