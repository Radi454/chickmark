import 'dart:convert';

enum CorrectiveActionStatus {
  open('open'),
  inProgress('in_progress'),
  implemented('implemented'),
  completed('completed'),
  cancelled('cancelled');

  const CorrectiveActionStatus(this.storageKey);
  final String storageKey;

  static CorrectiveActionStatus fromStorage(Object? value) => values.firstWhere(
    (item) => item.storageKey == value?.toString(),
    orElse: () => open,
  );
}

enum ActionEffectiveness {
  effective('effective'),
  partiallyEffective('partially_effective'),
  ineffective('ineffective'),
  notEvaluated('not_evaluated');

  const ActionEffectiveness(this.storageKey);
  final String storageKey;

  static ActionEffectiveness fromStorage(Object? value) => values.firstWhere(
    (item) => item.storageKey == value?.toString(),
    orElse: () => notEvaluated,
  );
}

enum ActionTargetRule {
  atLeast('at_least'),
  atMost('at_most'),
  increaseBy('increase_by'),
  decreaseBy('decrease_by');

  const ActionTargetRule(this.storageKey);
  final String storageKey;

  static ActionTargetRule fromStorage(Object? value) => values.firstWhere(
    (item) => item.storageKey == value?.toString(),
    orElse: () => atLeast,
  );
}

class CorrectiveActionDraft {
  const CorrectiveActionDraft({
    required this.concernId,
    required this.instruction,
    required this.createdBy,
    this.visitId,
    this.causeAssessmentId,
    this.ownerId,
    this.ownerName,
    this.dueAt,
  });

  final String concernId;
  final String? visitId;
  final String? causeAssessmentId;
  final String instruction;
  final String? ownerId;
  final String? ownerName;
  final DateTime? dueAt;
  final String createdBy;
}

class CorrectiveAction {
  const CorrectiveAction({
    required this.id,
    required this.concernId,
    required this.instruction,
    required this.status,
    this.visitId,
    this.causeAssessmentId,
    this.ownerId,
    this.ownerName,
    this.dueAt,
    this.implementedAt,
    this.implementationConfirmedBy,
    this.completionNotes,
    this.evidenceRefs = const [],
    this.createdBy,
    this.evaluations = const [],
  });

  final String id;
  final String concernId;
  final String? visitId;
  final String? causeAssessmentId;
  final String instruction;
  final String? ownerId;
  final String? ownerName;
  final DateTime? dueAt;
  final DateTime? implementedAt;
  final String? implementationConfirmedBy;
  final CorrectiveActionStatus status;
  final String? completionNotes;
  final List<String> evidenceRefs;
  final String? createdBy;
  final List<ActionKpiEvaluation> evaluations;

  factory CorrectiveAction.fromMap(
    Map<String, Object?> map, {
    List<ActionKpiEvaluation> evaluations = const [],
  }) {
    return CorrectiveAction(
      id: map['id']! as String,
      concernId: map['concernId']! as String,
      visitId: map['visitId'] as String?,
      causeAssessmentId: map['causeAssessmentId'] as String?,
      instruction: map['instruction']! as String,
      ownerId: map['ownerId'] as String?,
      ownerName: map['ownerName'] as String?,
      dueAt: _date(map['dueAt']),
      implementedAt: _date(map['implementedAt']),
      implementationConfirmedBy: map['implementationConfirmedBy'] as String?,
      status: CorrectiveActionStatus.fromStorage(map['status']),
      completionNotes: map['completionNotes'] as String?,
      evidenceRefs: _decodeStringList(map['evidenceRefsJson']),
      createdBy: map['createdBy'] as String?,
      evaluations: evaluations,
    );
  }
}

class ActionKpiEvaluationDefinition {
  const ActionKpiEvaluationDefinition({
    required this.kpiKey,
    required this.scope,
    required this.baselineWindowStart,
    required this.baselineWindowEnd,
    required this.baselineValue,
    required this.targetRule,
    required this.targetValue,
    required this.evaluationStart,
    required this.evaluationEnd,
  });

  final String kpiKey;
  final Map<String, Object?> scope;
  final DateTime baselineWindowStart;
  final DateTime baselineWindowEnd;
  final double baselineValue;
  final ActionTargetRule targetRule;
  final double targetValue;
  final DateTime evaluationStart;
  final DateTime evaluationEnd;
}

class ActionKpiEvaluation {
  const ActionKpiEvaluation({
    required this.id,
    required this.actionId,
    required this.kpiKey,
    required this.scope,
    required this.baselineWindowStart,
    required this.baselineWindowEnd,
    required this.baselineValue,
    required this.targetRule,
    required this.targetValue,
    required this.evaluationStart,
    required this.evaluationEnd,
    required this.effectiveness,
    this.observedValue,
    this.evaluationReason,
    this.evaluatedBy,
    this.evaluatedAt,
  });

  final String id;
  final String actionId;
  final String kpiKey;
  final Map<String, Object?> scope;
  final DateTime baselineWindowStart;
  final DateTime baselineWindowEnd;
  final double baselineValue;
  final ActionTargetRule targetRule;
  final double targetValue;
  final DateTime evaluationStart;
  final DateTime evaluationEnd;
  final double? observedValue;
  final ActionEffectiveness effectiveness;
  final String? evaluationReason;
  final String? evaluatedBy;
  final DateTime? evaluatedAt;

  factory ActionKpiEvaluation.fromMap(Map<String, Object?> map) {
    return ActionKpiEvaluation(
      id: map['id']! as String,
      actionId: map['actionId']! as String,
      kpiKey: map['kpiKey']! as String,
      scope: _decodeObjectMap(map['scopeJson']),
      baselineWindowStart: DateTime.parse(
        map['baselineWindowStart']! as String,
      ),
      baselineWindowEnd: DateTime.parse(map['baselineWindowEnd']! as String),
      baselineValue: _number(map['baselineValue'])!,
      targetRule: ActionTargetRule.fromStorage(map['targetRule']),
      targetValue: _number(map['targetValue'])!,
      evaluationStart: DateTime.parse(map['evaluationStart']! as String),
      evaluationEnd: DateTime.parse(map['evaluationEnd']! as String),
      observedValue: _number(map['observedValue']),
      effectiveness: ActionEffectiveness.fromStorage(map['effectiveness']),
      evaluationReason: map['evaluationReason'] as String?,
      evaluatedBy: map['evaluatedBy'] as String?,
      evaluatedAt: _date(map['evaluatedAt']),
    );
  }

  ActionKpiEvaluationDefinition toDefinition() {
    return ActionKpiEvaluationDefinition(
      kpiKey: kpiKey,
      scope: scope,
      baselineWindowStart: baselineWindowStart,
      baselineWindowEnd: baselineWindowEnd,
      baselineValue: baselineValue,
      targetRule: targetRule,
      targetValue: targetValue,
      evaluationStart: evaluationStart,
      evaluationEnd: evaluationEnd,
    );
  }
}

class ActionKpiObservation {
  const ActionKpiObservation({
    required this.kpiKey,
    required this.scope,
    required this.observedAt,
    required this.value,
    this.isValid = true,
  });

  final String kpiKey;
  final Map<String, Object?> scope;
  final DateTime observedAt;
  final double value;
  final bool isValid;
}

class ActionEvaluationResult {
  const ActionEvaluationResult({
    required this.effectiveness,
    required this.baselineValue,
    required this.observedValue,
    required this.reason,
  });

  final ActionEffectiveness effectiveness;
  final double baselineValue;
  final double? observedValue;
  final String reason;
}

Map<String, Object?> _decodeObjectMap(Object? value) {
  if (value == null || value.toString().isEmpty) return const {};
  final decoded = jsonDecode(value.toString());
  return decoded is Map ? Map<String, Object?>.from(decoded) : const {};
}

List<String> _decodeStringList(Object? value) {
  if (value == null || value.toString().isEmpty) return const [];
  final decoded = jsonDecode(value.toString());
  return decoded is List
      ? decoded.map((item) => item.toString()).toList()
      : const [];
}

double? _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('${value ?? ''}');

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());
