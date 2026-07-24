import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/corrective_action_models.dart';

class CorrectiveActionRepository {
  CorrectiveActionRepository({
    DatabaseHelper? databaseHelper,
    Uuid uuid = const Uuid(),
  }) : _databaseHelper = databaseHelper ?? DatabaseHelper(),
       _uuid = uuid;

  final DatabaseHelper _databaseHelper;
  final Uuid _uuid;

  Future<CorrectiveAction> createAction(
    CorrectiveActionDraft draft, {
    required List<ActionKpiEvaluationDefinition> evaluations,
  }) async {
    if (evaluations.isEmpty) {
      throw ArgumentError('At least one target KPI is required');
    }
    final db = await _databaseHelper.db;
    final id = _uuid.v4();
    final now = _now();
    await db.transaction<void>((txn) async {
      await txn.insert('corrective_actions', {
        'id': id,
        'concernId': draft.concernId,
        'visitId': draft.visitId,
        'causeAssessmentId': draft.causeAssessmentId,
        'instruction': draft.instruction,
        'ownerId': draft.ownerId,
        'ownerName': draft.ownerName,
        'dueAt': draft.dueAt?.toUtc().toIso8601String(),
        'status': CorrectiveActionStatus.open.storageKey,
        'createdBy': draft.createdBy,
        'createdAt': now,
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
      });
      for (final definition in evaluations) {
        _validateWindow(definition);
        await txn.insert('action_kpi_evaluations', {
          'id': _uuid.v4(),
          'actionId': id,
          'kpiKey': definition.kpiKey,
          'scopeJson': jsonEncode(definition.scope),
          'baselineWindowStart': definition.baselineWindowStart
              .toUtc()
              .toIso8601String(),
          'baselineWindowEnd': definition.baselineWindowEnd
              .toUtc()
              .toIso8601String(),
          'baselineValue': definition.baselineValue,
          'targetRule': definition.targetRule.storageKey,
          'targetValue': definition.targetValue,
          'evaluationStart': definition.evaluationStart
              .toUtc()
              .toIso8601String(),
          'evaluationEnd': definition.evaluationEnd.toUtc().toIso8601String(),
          'effectiveness': ActionEffectiveness.notEvaluated.storageKey,
          'createdAt': now,
          'updatedAt': now,
          'syncStatus': 'pending',
          'dirtyAt': now,
        });
      }
    });
    return (await getAction(id))!;
  }

  Future<CorrectiveAction?> getAction(String id) async {
    final db = await _databaseHelper.db;
    final rows = await db.query(
      'corrective_actions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final evaluationRows = await db.query(
      'action_kpi_evaluations',
      where: 'actionId = ?',
      whereArgs: [id],
      orderBy: 'createdAt, id',
    );
    return CorrectiveAction.fromMap(
      rows.single,
      evaluations: evaluationRows.map(ActionKpiEvaluation.fromMap).toList(),
    );
  }

  Future<List<CorrectiveAction>> listForConcern(String concernId) async {
    final db = await _databaseHelper.db;
    final rows = await db.query(
      'corrective_actions',
      columns: const ['id'],
      where: 'concernId = ?',
      whereArgs: [concernId],
      orderBy: 'createdAt DESC',
    );
    final actions = <CorrectiveAction>[];
    for (final row in rows) {
      final action = await getAction(row['id']! as String);
      if (action != null) actions.add(action);
    }
    return actions;
  }

  Future<CorrectiveAction> confirmImplementation(
    String id, {
    required String confirmedBy,
    required DateTime implementedAt,
  }) async {
    final db = await _databaseHelper.db;
    final now = _now();
    await db.update(
      'corrective_actions',
      {
        'status': CorrectiveActionStatus.implemented.storageKey,
        'implementedAt': implementedAt.toUtc().toIso8601String(),
        'implementationConfirmedBy': confirmedBy,
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
        'syncError': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return (await getAction(id))!;
  }

  Future<ActionKpiEvaluation> recordEvaluation(
    String evaluationId, {
    required ActionEvaluationResult result,
    required String evaluatedBy,
    required DateTime evaluatedAt,
  }) async {
    final db = await _databaseHelper.db;
    final now = _now();
    await db.update(
      'action_kpi_evaluations',
      {
        'observedValue': result.observedValue,
        'effectiveness': result.effectiveness.storageKey,
        'evaluationReason': result.reason,
        'evaluatedBy': evaluatedBy,
        'evaluatedAt': evaluatedAt.toUtc().toIso8601String(),
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
        'syncError': null,
      },
      where: 'id = ?',
      whereArgs: [evaluationId],
    );
    return (await _getEvaluation(evaluationId))!;
  }

  Future<CorrectiveAction> completeAction(
    String id, {
    required String completionNotes,
    List<String> evidenceRefs = const [],
  }) async {
    final db = await _databaseHelper.db;
    final now = _now();
    await db.update(
      'corrective_actions',
      {
        'status': CorrectiveActionStatus.completed.storageKey,
        'completionNotes': completionNotes,
        'evidenceRefsJson': jsonEncode(evidenceRefs),
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
        'syncError': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return (await getAction(id))!;
  }

  Future<ActionKpiEvaluation?> _getEvaluation(String id) async {
    final db = await _databaseHelper.db;
    final rows = await db.query(
      'action_kpi_evaluations',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : ActionKpiEvaluation.fromMap(rows.single);
  }

  void _validateWindow(ActionKpiEvaluationDefinition definition) {
    if (definition.baselineWindowEnd.isBefore(definition.baselineWindowStart)) {
      throw ArgumentError('Baseline window end must not precede its start');
    }
    if (definition.evaluationEnd.isBefore(definition.evaluationStart)) {
      throw ArgumentError('Evaluation window end must not precede its start');
    }
  }

  String _now() => DateTime.now().toUtc().toIso8601String();
}
