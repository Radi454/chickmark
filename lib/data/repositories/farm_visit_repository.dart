import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/farm_visit_models.dart';

class FarmVisitRepository {
  FarmVisitRepository({
    DatabaseHelper? databaseHelper,
    Uuid uuid = const Uuid(),
  }) : _databaseHelper = databaseHelper ?? DatabaseHelper(),
       _uuid = uuid;

  final DatabaseHelper _databaseHelper;
  final Uuid _uuid;

  Future<FarmVisitSession> createVisit({
    required String customerId,
    required String farmId,
    required DateTime visitDate,
    required VisitBriefingSnapshot briefing,
    required List<String> houseIds,
    required String createdBy,
    String? flockId,
    String? assignedAuditorId,
    String? notes,
    List<VisitInvestigationDraft> suggestedInvestigations = const [],
  }) async {
    if (houseIds.isEmpty) {
      throw ArgumentError('At least one house must be selected');
    }
    final db = await _databaseHelper.db;
    final visitId = _uuid.v4();
    final now = _now();
    await db.transaction<void>((txn) async {
      await txn.insert('farm_visit_sessions', {
        'id': visitId,
        'customerId': customerId,
        'farmId': farmId,
        'flockId': flockId,
        'visitDate': visitDate.toUtc().toIso8601String(),
        'briefingSnapshotJson': jsonEncode(briefing.toJson()),
        'status': FarmVisitStatus.planned.storageKey,
        'assignedAuditorId': assignedAuditorId ?? createdBy,
        'notes': notes,
        'createdBy': createdBy,
        'createdAt': now,
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
      });
      for (final houseId in houseIds.toSet()) {
        await txn.insert('farm_visit_houses', {
          'id': _uuid.v4(),
          'visitId': visitId,
          'houseId': houseId,
          'createdAt': now,
          'syncStatus': 'pending',
          'dirtyAt': now,
        });
      }
      for (final draft in suggestedInvestigations) {
        await _insertInvestigation(
          txn,
          draft,
          visitId: visitId,
          origin: InvestigationOrigin.suggested,
          now: now,
        );
        if (draft.sourceConcernId != null) {
          await txn.update(
            'performance_concerns',
            {
              'status': 'assigned_to_visit',
              'updatedAt': now,
              'syncStatus': 'pending',
              'dirtyAt': now,
              'syncError': null,
            },
            where: 'id = ?',
            whereArgs: [draft.sourceConcernId],
          );
        }
      }
    });
    return (await getVisit(visitId))!;
  }

  Future<FarmVisitSession?> getVisit(String id) async {
    final db = await _databaseHelper.db;
    final rows = await db.query(
      'farm_visit_sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final houses = await db.query(
      'farm_visit_houses',
      columns: const ['houseId'],
      where: 'visitId = ?',
      whereArgs: [id],
      orderBy: 'createdAt, houseId',
    );
    final investigationRows = await db.query(
      'visit_investigations',
      where: 'visitId = ?',
      whereArgs: [id],
      orderBy: 'createdAt, id',
    );
    final findingRows = await db.query(
      'visit_findings',
      where: 'visitId = ?',
      whereArgs: [id],
      orderBy: 'createdAt, id',
    );
    final causeRows = await db.query(
      'cause_assessments',
      where: 'visitId = ?',
      whereArgs: [id],
      orderBy: 'createdAt, id',
    );
    return FarmVisitSession.fromMap(
      rows.single,
      houseIds: houses.map((row) => row['houseId']! as String).toList(),
      investigations: investigationRows
          .map(VisitInvestigation.fromMap)
          .toList(),
      findings: findingRows.map(VisitFinding.fromMap).toList(),
      causeAssessments: causeRows.map(CauseAssessment.fromMap).toList(),
    );
  }

  Future<List<FarmVisitSession>> listVisits({
    required String customerId,
    String? farmId,
    String? flockId,
  }) async {
    final db = await _databaseHelper.db;
    final clauses = <String>['customerId = ?'];
    final args = <Object?>[customerId];
    if (farmId != null) {
      clauses.add('farmId = ?');
      args.add(farmId);
    }
    if (flockId != null) {
      clauses.add('flockId = ?');
      args.add(flockId);
    }
    final rows = await db.query(
      'farm_visit_sessions',
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'visitDate DESC',
    );
    final visits = <FarmVisitSession>[];
    for (final row in rows) {
      final visit = await getVisit(row['id']! as String);
      if (visit != null) visits.add(visit);
    }
    return visits;
  }

  Future<FarmVisitSession> startVisit(String id) =>
      _setVisitStatus(id, FarmVisitStatus.inProgress);

  Future<FarmVisitSession> completeVisit(String id) =>
      _setVisitStatus(id, FarmVisitStatus.completed);

  Future<VisitInvestigation> addInvestigation(
    VisitInvestigationDraft draft,
  ) async {
    if (draft.visitId == null || draft.visitId!.isEmpty) {
      throw ArgumentError('A visit id is required');
    }
    final db = await _databaseHelper.db;
    final id = await _insertInvestigation(
      db,
      draft,
      visitId: draft.visitId!,
      origin: draft.origin,
      now: _now(),
    );
    return (await _getInvestigation(id))!;
  }

  Future<VisitInvestigation> completeInvestigation(
    String id, {
    required String resultSummary,
  }) async {
    final db = await _databaseHelper.db;
    final now = _now();
    await db.update(
      'visit_investigations',
      {
        'status': InvestigationStatus.completed.storageKey,
        'resultSummary': resultSummary,
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
        'syncError': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return (await _getInvestigation(id))!;
  }

  Future<VisitFinding> addFinding(VisitFindingDraft draft) async {
    final db = await _databaseHelper.db;
    final id = _uuid.v4();
    final now = _now();
    await db.insert('visit_findings', {
      'id': id,
      'visitId': draft.visitId,
      'investigationId': draft.investigationId,
      'findingType': draft.findingType,
      'severity': draft.severity,
      'measuredValue': draft.measuredValue,
      'unit': draft.unit,
      'observationJson': jsonEncode(draft.observation),
      'houseId': draft.houseId,
      'location': draft.location,
      'staffExplanation': draft.staffExplanation,
      'attachmentRefsJson': jsonEncode(draft.attachmentRefs),
      'authoredBy': draft.authoredBy,
      'createdAt': now,
      'updatedAt': now,
      'syncStatus': 'pending',
      'dirtyAt': now,
    });
    return (await _getFinding(id))!;
  }

  Future<CauseAssessment> saveCauseAssessment(
    CauseAssessmentDraft draft,
  ) async {
    final db = await _databaseHelper.db;
    final id = _uuid.v4();
    final now = _now();
    await db.insert('cause_assessments', {
      'id': id,
      'visitId': draft.visitId,
      'concernId': draft.concernId,
      'probableCause': draft.probableCause,
      'alternativeCausesJson': jsonEncode(draft.alternativeCauses),
      'supportingEvidenceJson': jsonEncode(draft.supportingEvidenceIds),
      'conflictingEvidenceJson': jsonEncode(draft.conflictingEvidenceIds),
      'status': draft.status.storageKey,
      'authoredBy': draft.authoredBy,
      'createdAt': now,
      'updatedAt': now,
      'syncStatus': 'pending',
      'dirtyAt': now,
    });
    return (await _getCauseAssessment(id))!;
  }

  Future<CauseAssessment> setCauseStatus(
    String id,
    CauseAssessmentStatus status,
  ) async {
    final db = await _databaseHelper.db;
    final now = _now();
    await db.update(
      'cause_assessments',
      {
        'status': status.storageKey,
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
        'syncError': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return (await _getCauseAssessment(id))!;
  }

  Future<String> _insertInvestigation(
    DatabaseExecutor db,
    VisitInvestigationDraft draft, {
    required String visitId,
    required InvestigationOrigin origin,
    required String now,
  }) async {
    final id = _uuid.v4();
    await db.insert('visit_investigations', {
      'id': id,
      'visitId': visitId,
      'sourceConcernId': draft.sourceConcernId,
      'houseId': draft.houseId,
      'location': draft.location,
      'origin': origin.storageKey,
      'investigationType': draft.investigationType,
      'instruction': draft.instruction,
      'status': InvestigationStatus.pending.storageKey,
      'createdAt': now,
      'updatedAt': now,
      'syncStatus': 'pending',
      'dirtyAt': now,
    });
    return id;
  }

  Future<FarmVisitSession> _setVisitStatus(
    String id,
    FarmVisitStatus status,
  ) async {
    final db = await _databaseHelper.db;
    final now = _now();
    await db.update(
      'farm_visit_sessions',
      {
        'status': status.storageKey,
        if (status == FarmVisitStatus.inProgress) 'startedAt': now,
        if (status == FarmVisitStatus.completed) 'completedAt': now,
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
        'syncError': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return (await getVisit(id))!;
  }

  Future<VisitInvestigation?> _getInvestigation(String id) async {
    final db = await _databaseHelper.db;
    final rows = await db.query(
      'visit_investigations',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : VisitInvestigation.fromMap(rows.single);
  }

  Future<VisitFinding?> _getFinding(String id) async {
    final db = await _databaseHelper.db;
    final rows = await db.query(
      'visit_findings',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : VisitFinding.fromMap(rows.single);
  }

  Future<CauseAssessment?> _getCauseAssessment(String id) async {
    final db = await _databaseHelper.db;
    final rows = await db.query(
      'cause_assessments',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : CauseAssessment.fromMap(rows.single);
  }

  String _now() => DateTime.now().toUtc().toIso8601String();
}
