import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../agent/station_adapter.dart';
import '../agent/station_registry.dart';
import '../database/database_helper.dart';
import '../models/agent_intake_models.dart';
import '../models/audit_session_model.dart';

class AgentIntakeRepository {
  AgentIntakeRepository({DatabaseHelper? databaseHelper})
    : _databaseHelper = databaseHelper ?? DatabaseHelper();

  final DatabaseHelper _databaseHelper;

  Future<List<AgentIntakeSession>> listAwaitingReview() async {
    final db = await _databaseHelper.db;
    final rows = await db.query(
      'agent_intake_sessions',
      where: 'state = ? AND userConfirmedAt IS NOT NULL',
      whereArgs: [AgentIntakeState.awaitingAdminReview.storageKey],
      orderBy: 'updatedAt DESC, createdAt DESC, id ASC',
    );
    return List.unmodifiable(rows.map(AgentIntakeSession.fromMap));
  }

  Future<AgentIntakeDetails?> loadDetails(String intakeId) async {
    final db = await _databaseHelper.db;
    final sessionRows = await db.query(
      'agent_intake_sessions',
      where: 'id = ?',
      whereArgs: [intakeId],
      limit: 1,
    );
    if (sessionRows.isEmpty) return null;
    final valueRows = await db.query(
      'agent_intake_values',
      where: 'intakeSessionId = ?',
      whereArgs: [intakeId],
      orderBy: 'fieldKey ASC, id ASC',
    );
    final turnRows = await db.query(
      'agent_intake_turns',
      where: 'intakeSessionId = ?',
      whereArgs: [intakeId],
      orderBy: 'createdAt ASC, id ASC',
    );
    return AgentIntakeDetails(
      session: AgentIntakeSession.fromMap(sessionRows.single),
      values: valueRows.map(AgentIntakeValue.fromMap).toList(growable: false),
      turns: turnRows.map(AgentIntakeTurn.fromMap).toList(growable: false),
    );
  }

  Future<List<AuditSessionModel>> listMatchingAuditSessions(
    AgentIntakeSession intake,
  ) async {
    final customerId = intake.customerId;
    final flockId = intake.flockId;
    final hatcheryId = intake.hatcheryId;
    if (customerId == null || flockId == null || hatcheryId == null) {
      return const [];
    }
    final db = await _databaseHelper.db;
    final rows = await db.query(
      'audit_sessions',
      where:
          'customerId = ? AND flockId = ? AND hatcheryId = ? '
          'AND substr(date, 1, 10) = ?',
      whereArgs: [customerId, flockId, hatcheryId, _dayText(intake.auditDate)],
      orderBy: 'updatedAt DESC, createdAt DESC, id ASC',
    );
    return List.unmodifiable(rows.map(AuditSessionModel.fromMap));
  }

  Future<void> updateValue({
    required String intakeId,
    required String fieldKey,
    required Object? value,
    DateTime? updatedAt,
  }) async {
    final db = await _databaseHelper.db;
    final now = (updatedAt ?? DateTime.now()).toUtc();
    final nowText = now.toIso8601String();
    await db.transaction<void>((txn) async {
      final session = await _requiredReviewSession(txn, intakeId);
      final schema = AgentStationRegistry.require(
        session.schemaKey,
        session.schemaVersion,
      );
      if (!schema.fields.any((field) => field.fieldKey == fieldKey)) {
        throw ArgumentError.value(
          fieldKey,
          'fieldKey',
          'Unsupported station field',
        );
      }
      final nextValues = Map<String, Object?>.from(session.workingValues);
      nextValues[fieldKey] = value;
      final validation = AgentStationAdapter.validate(schema, nextValues);
      if (!validation.isValid) {
        final issue = validation.issues
            .where((candidate) => candidate.fieldKey == fieldKey)
            .firstOrNull;
        throw ArgumentError.value(
          value,
          fieldKey,
          issue?.code ?? 'Station values are incomplete or invalid',
        );
      }

      final valueId = '$intakeId:$fieldKey';
      final existing = await txn.query(
        'agent_intake_values',
        columns: const ['createdAt'],
        where: 'id = ?',
        whereArgs: [valueId],
        limit: 1,
      );
      final valueRow = <String, Object?>{
        'id': valueId,
        'intakeSessionId': intakeId,
        'fieldKey': fieldKey,
        'valueJson': jsonEncode(value),
        'sourcePhrase': 'Admin review correction',
        'confidence': 1.0,
        'clarificationReason': null,
        'createdAt': existing.isEmpty ? nowText : existing.single['createdAt'],
        'updatedAt': nowText,
        'syncStatus': 'pending',
        'dirtyAt': nowText,
        'lastSyncedAt': null,
        'syncError': null,
      };
      if (existing.isEmpty) {
        await txn.insert('agent_intake_values', valueRow);
      } else {
        await txn.update(
          'agent_intake_values',
          valueRow,
          where: 'id = ?',
          whereArgs: [valueId],
        );
      }
      await txn.update(
        'agent_intake_sessions',
        {
          'workingValuesJson': jsonEncode(nextValues),
          'updatedAt': nowText,
          'syncStatus': 'pending',
          'dirtyAt': nowText,
          'lastSyncedAt': null,
          'syncError': null,
        },
        where: 'id = ?',
        whereArgs: [intakeId],
      );
    });
  }

  Future<void> reject({
    required String intakeId,
    required String reason,
    required String reviewedBy,
    DateTime? reviewedAt,
  }) async {
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw ArgumentError.value(
        reason,
        'reason',
        'A rejection reason is required',
      );
    }
    final db = await _databaseHelper.db;
    final now = (reviewedAt ?? DateTime.now()).toUtc().toIso8601String();
    await db.transaction<void>((txn) async {
      await _requiredReviewSession(txn, intakeId);
      await txn.update(
        'agent_intake_sessions',
        {
          'state': AgentIntakeState.rejected.storageKey,
          'reviewedBy': reviewedBy,
          'reviewedAt': now,
          'rejectionReason': normalizedReason,
          'updatedAt': now,
          'syncStatus': 'pending',
          'dirtyAt': now,
          'lastSyncedAt': null,
          'syncError': null,
        },
        where: 'id = ?',
        whereArgs: [intakeId],
      );
    });
  }

  Future<void> markApproved({
    required String intakeId,
    required String auditSessionId,
    required String panelRowId,
    required String reviewedBy,
    DateTime? reviewedAt,
  }) async {
    final db = await _databaseHelper.db;
    final now = (reviewedAt ?? DateTime.now()).toUtc().toIso8601String();
    await db.transaction<void>((txn) async {
      final rows = await txn.query(
        'agent_intake_sessions',
        where: 'id = ?',
        whereArgs: [intakeId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Agent intake not found');
      final session = AgentIntakeSession.fromMap(rows.single);
      if (session.state == AgentIntakeState.approved) {
        if (session.approvedSessionId == auditSessionId &&
            session.approvedPanelRowId == panelRowId) {
          return;
        }
        throw StateError('Agent intake was approved to another record');
      }
      if (session.state != AgentIntakeState.awaitingAdminReview) {
        throw StateError('Agent intake is not awaiting admin review');
      }

      await _ensureSyncedAuditSession(
        txn,
        session: session,
        auditSessionId: auditSessionId,
        reviewedBy: reviewedBy,
        timestamp: now,
      );
      await txn.update(
        'agent_intake_sessions',
        {
          'state': AgentIntakeState.approved.storageKey,
          'approvedSessionId': auditSessionId,
          'approvedPanelRowId': panelRowId,
          'reviewedBy': reviewedBy,
          'reviewedAt': now,
          'rejectionReason': null,
          'updatedAt': now,
          'syncStatus': 'synced',
          'dirtyAt': null,
          'lastSyncedAt': now,
          'syncError': null,
        },
        where: 'id = ?',
        whereArgs: [intakeId],
      );
    });
  }

  Future<AgentIntakeSession> _requiredReviewSession(
    DatabaseExecutor db,
    String intakeId,
  ) async {
    final rows = await db.query(
      'agent_intake_sessions',
      where: 'id = ?',
      whereArgs: [intakeId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Agent intake not found');
    final session = AgentIntakeSession.fromMap(rows.single);
    if (session.state != AgentIntakeState.awaitingAdminReview) {
      throw StateError('Agent intake is not awaiting admin review');
    }
    return session;
  }

  Future<void> _ensureSyncedAuditSession(
    DatabaseExecutor db, {
    required AgentIntakeSession session,
    required String auditSessionId,
    required String reviewedBy,
    required String timestamp,
  }) async {
    final existing = await db.query(
      'audit_sessions',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [auditSessionId],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    final customerId = session.customerId;
    final flockId = session.flockId;
    final hatcheryId = session.hatcheryId;
    if (customerId == null || flockId == null || hatcheryId == null) {
      throw StateError('Approved agent intake context is incomplete');
    }
    final schema = AgentStationRegistry.require(
      session.schemaKey,
      session.schemaVersion,
    );
    await db.insert('audit_sessions', {
      'id': auditSessionId,
      'customerId': customerId,
      'flockId': flockId,
      'hatcheryId': hatcheryId,
      'date': _dayText(session.auditDate),
      'status': 'in_progress',
      'selectedStationKeys': jsonEncode([schema.stationKey]),
      'stationsCompleted': jsonEncode([schema.stationKey]),
      'createdBy': reviewedBy,
      'createdAt': timestamp,
      'updatedAt': timestamp,
      'syncStatus': 'synced',
      'dirtyAt': null,
      'lastSyncedAt': timestamp,
      'syncError': null,
    });
  }
}

String _dayText(DateTime value) {
  final utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}
