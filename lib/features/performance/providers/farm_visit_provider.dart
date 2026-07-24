import 'package:flutter/foundation.dart';

import '../../../data/models/corrective_action_models.dart';
import '../../../data/models/farm_visit_models.dart';
import '../../../data/repositories/corrective_action_repository.dart';
import '../../../data/repositories/farm_visit_repository.dart';
import '../services/action_effectiveness_evaluator.dart';

class FarmVisitProvider extends ChangeNotifier {
  FarmVisitProvider({
    FarmVisitRepository? visitRepository,
    CorrectiveActionRepository? actionRepository,
    ActionEffectivenessEvaluator evaluator =
        const ActionEffectivenessEvaluator(),
  }) : _visitRepository = visitRepository ?? FarmVisitRepository(),
       _actionRepository = actionRepository ?? CorrectiveActionRepository(),
       _evaluator = evaluator,
       _isDebug = false;

  FarmVisitProvider.debug({FarmVisitSession? visit, CorrectiveAction? action})
    : _visitRepository = FarmVisitRepository(),
      _actionRepository = CorrectiveActionRepository(),
      _evaluator = const ActionEffectivenessEvaluator(),
      _visit = visit,
      _action = action,
      _isDebug = true;

  final FarmVisitRepository _visitRepository;
  final CorrectiveActionRepository _actionRepository;
  final ActionEffectivenessEvaluator _evaluator;
  final bool _isDebug;

  FarmVisitSession? _visit;
  CorrectiveAction? _action;
  bool _isLoading = false;
  String? _error;

  FarmVisitSession? get visit => _visit;
  CorrectiveAction? get action => _action;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadVisit(String id) async {
    await _runLoading(() async {
      _visit = await _visitRepository.getVisit(id);
      if (_visit == null) throw StateError('Farm visit was not found');
    });
  }

  Future<void> loadAction(String id) async {
    await _runLoading(() async {
      _action = await _actionRepository.getAction(id);
      if (_action == null) throw StateError('Corrective action was not found');
    });
  }

  Future<void> startVisit() async {
    final current = _requireVisit();
    if (_isDebug) {
      _visit = _copyVisit(current, status: FarmVisitStatus.inProgress);
      notifyListeners();
      return;
    }
    await _runLoading(() async {
      _visit = await _visitRepository.startVisit(current.id);
    });
  }

  Future<void> completeVisit() async {
    final current = _requireVisit();
    if (_isDebug) {
      _visit = _copyVisit(current, status: FarmVisitStatus.completed);
      notifyListeners();
      return;
    }
    await _runLoading(() async {
      _visit = await _visitRepository.completeVisit(current.id);
    });
  }

  Future<void> addManualInvestigation({
    required String investigationType,
    required String instruction,
    String? houseId,
    String? location,
    String? sourceConcernId,
  }) async {
    final current = _requireVisit();
    if (_isDebug) return;
    await _runLoading(() async {
      await _visitRepository.addInvestigation(
        VisitInvestigationDraft(
          visitId: current.id,
          sourceConcernId: sourceConcernId,
          houseId: houseId,
          location: location,
          origin: InvestigationOrigin.manual,
          investigationType: investigationType,
          instruction: instruction,
        ),
      );
      _visit = await _visitRepository.getVisit(current.id);
    });
  }

  Future<void> completeInvestigation(
    String investigationId,
    String resultSummary,
  ) async {
    final current = _requireVisit();
    if (_isDebug) return;
    await _runLoading(() async {
      await _visitRepository.completeInvestigation(
        investigationId,
        resultSummary: resultSummary,
      );
      _visit = await _visitRepository.getVisit(current.id);
    });
  }

  Future<void> addFinding(VisitFindingDraft draft) async {
    final current = _requireVisit();
    if (_isDebug) return;
    await _runLoading(() async {
      await _visitRepository.addFinding(draft);
      _visit = await _visitRepository.getVisit(current.id);
    });
  }

  Future<void> addCauseAssessment(CauseAssessmentDraft draft) async {
    final current = _requireVisit();
    if (_isDebug) return;
    await _runLoading(() async {
      await _visitRepository.saveCauseAssessment(draft);
      _visit = await _visitRepository.getVisit(current.id);
    });
  }

  Future<void> setCauseStatus(
    String causeId,
    CauseAssessmentStatus status,
  ) async {
    final current = _requireVisit();
    if (_isDebug) {
      final causes = [
        for (final cause in current.causeAssessments)
          if (cause.id == causeId) _copyCause(cause, status) else cause,
      ];
      _visit = _copyVisit(current, causeAssessments: causes);
      notifyListeners();
      return;
    }
    await _runLoading(() async {
      await _visitRepository.setCauseStatus(causeId, status);
      _visit = await _visitRepository.getVisit(current.id);
    });
  }

  Future<CorrectiveAction> createAction(
    CorrectiveActionDraft draft, {
    required List<ActionKpiEvaluationDefinition> evaluations,
  }) async {
    late CorrectiveAction created;
    await _runLoading(() async {
      created = await _actionRepository.createAction(
        draft,
        evaluations: evaluations,
      );
      _action = created;
    });
    return created;
  }

  Future<void> confirmActionImplementation({
    required String confirmedBy,
    required DateTime implementedAt,
  }) async {
    final current = _requireAction();
    await _runLoading(() async {
      _action = await _actionRepository.confirmImplementation(
        current.id,
        confirmedBy: confirmedBy,
        implementedAt: implementedAt,
      );
    });
  }

  Future<ActionEvaluationResult> evaluateActionKpi({
    required String evaluationId,
    required List<ActionKpiObservation> observations,
    required String evaluatedBy,
    required DateTime evaluatedAt,
  }) async {
    final current = _requireAction();
    final evaluation = current.evaluations.firstWhere(
      (item) => item.id == evaluationId,
    );
    final result = _evaluator.evaluate(
      definition: evaluation.toDefinition(),
      implementationConfirmed:
          current.implementationConfirmedBy?.isNotEmpty == true,
      evaluatedAt: evaluatedAt,
      observations: observations,
    );
    await recordEvaluation(
      evaluationId: evaluationId,
      result: result,
      evaluatedBy: evaluatedBy,
      evaluatedAt: evaluatedAt,
    );
    return result;
  }

  Future<void> recordEvaluation({
    required String evaluationId,
    required ActionEvaluationResult result,
    required String evaluatedBy,
    required DateTime evaluatedAt,
  }) async {
    final current = _requireAction();
    await _runLoading(() async {
      await _actionRepository.recordEvaluation(
        evaluationId,
        result: result,
        evaluatedBy: evaluatedBy,
        evaluatedAt: evaluatedAt,
      );
      _action = await _actionRepository.getAction(current.id);
    });
  }

  FarmVisitSession _requireVisit() {
    final current = _visit;
    if (current == null) throw StateError('No farm visit is loaded');
    return current;
  }

  CorrectiveAction _requireAction() {
    final current = _action;
    if (current == null) throw StateError('No corrective action is loaded');
    return current;
  }

  Future<void> _runLoading(Future<void> Function() operation) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await operation();
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

FarmVisitSession _copyVisit(
  FarmVisitSession source, {
  FarmVisitStatus? status,
  List<CauseAssessment>? causeAssessments,
}) {
  return FarmVisitSession(
    id: source.id,
    customerId: source.customerId,
    farmId: source.farmId,
    flockId: source.flockId,
    visitDate: source.visitDate,
    briefing: source.briefing,
    status: status ?? source.status,
    assignedAuditorId: source.assignedAuditorId,
    startedAt: source.startedAt,
    completedAt: source.completedAt,
    notes: source.notes,
    createdBy: source.createdBy,
    houseIds: source.houseIds,
    investigations: source.investigations,
    findings: source.findings,
    causeAssessments: causeAssessments ?? source.causeAssessments,
  );
}

CauseAssessment _copyCause(
  CauseAssessment source,
  CauseAssessmentStatus status,
) {
  return CauseAssessment(
    id: source.id,
    visitId: source.visitId,
    concernId: source.concernId,
    probableCause: source.probableCause,
    alternativeCauses: source.alternativeCauses,
    supportingEvidenceIds: source.supportingEvidenceIds,
    conflictingEvidenceIds: source.conflictingEvidenceIds,
    status: status,
    authoredBy: source.authoredBy,
  );
}
