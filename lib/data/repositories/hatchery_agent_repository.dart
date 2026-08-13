import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/customer_model.dart';
import '../models/flock_model.dart';
import '../models/hatchery_agent_models.dart';
import '../models/hatchery_model.dart';

class HatcheryAgentLinkCatalog {
  const HatcheryAgentLinkCatalog({
    this.customers = const [],
    this.flocks = const [],
    this.hatcheries = const [],
  });

  final List<CustomerModel> customers;
  final List<FlockModel> flocks;
  final List<HatcheryModel> hatcheries;

  List<FlockModel> flocksForCustomer(String? customerId) {
    if (customerId == null) return const [];
    return flocks
        .where((flock) => flock.customerId == customerId)
        .toList(growable: false);
  }

  List<HatcheryModel> hatcheriesForCustomer(String? customerId) {
    if (customerId == null) return const [];
    return hatcheries
        .where((hatchery) => hatchery.customerId == customerId)
        .toList(growable: false);
  }
}

class HatcheryAgentRepository {
  HatcheryAgentRepository({DatabaseHelper? databaseHelper})
    : _databaseHelper = databaseHelper ?? DatabaseHelper();

  final DatabaseHelper _databaseHelper;

  Future<void> createSubmissionGraph({
    required HatcheryAgentSubmission submission,
    required HatcheryDraftBatch batch,
    required List<HatcheryDraftRow> rows,
    List<HatcheryAgentQuestion> questions = const [],
    List<HatcheryAgentAuditEvent> events = const [],
  }) async {
    final db = await _databaseHelper.db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.insert(
        'agent_submissions',
        _pendingWrite(submission.toMap(), now),
      );
      await txn.insert(
        'hatchery_draft_batches',
        _pendingWrite(batch.toMap(), now),
      );
      for (final row in rows) {
        await txn.insert(
          'hatchery_draft_rows',
          _pendingWrite(row.toMap(), now),
        );
      }
      for (final question in questions) {
        await txn.insert(
          'agent_questions',
          _pendingWrite(question.toMap(), now),
        );
      }
      for (final event in events) {
        await txn.insert(
          'hatchery_agent_audit_events',
          _pendingWrite(event.toMap(), now),
        );
      }
    });
  }

  Future<AgentSettings> loadSettings() async {
    final db = await _databaseHelper.db;
    var rows = await db.query(
      'agent_settings',
      where: 'id = ?',
      whereArgs: const [1],
      limit: 1,
    );
    if (rows.isEmpty) {
      await saveSettings(const AgentSettings());
      rows = await db.query(
        'agent_settings',
        where: 'id = ?',
        whereArgs: const [1],
        limit: 1,
      );
    }
    return AgentSettings.fromMap(rows.single);
  }

  Future<void> saveSettings(AgentSettings settings) async {
    final db = await _databaseHelper.db;
    final now = DateTime.now().toUtc().toIso8601String();
    final values = _pendingWrite(settings.toMap(), now);
    final changed = await db.update(
      'agent_settings',
      values,
      where: 'id = ?',
      whereArgs: [settings.id],
    );
    if (changed == 0) {
      await db.insert('agent_settings', values);
    }
  }

  Future<void> saveConfirmedSettings(AgentSettings settings) async {
    final db = await _databaseHelper.db;
    final now = DateTime.now().toUtc().toIso8601String();
    final values = <String, Object?>{
      ...settings.toMap(),
      'syncStatus': 'synced',
      'dirtyAt': null,
      'lastSyncedAt': now,
      'syncError': null,
    };
    final changed = await db.update(
      'agent_settings',
      values,
      where: 'id = ?',
      whereArgs: [settings.id],
    );
    if (changed == 0) {
      await db.insert('agent_settings', values);
    }
  }

  Future<HatcheryAgentLinkCatalog> loadLinkCatalog() async {
    final db = await _databaseHelper.db;
    final customerRows = await db.query(
      'customers',
      orderBy: 'name COLLATE NOCASE ASC, id ASC',
    );
    final flockRows = await db.query(
      'flocks',
      orderBy: 'flockId COLLATE NOCASE ASC, id ASC',
    );
    final hatcheryRows = await db.query(
      'hatcheries',
      orderBy: 'name COLLATE NOCASE ASC, id ASC',
    );
    return HatcheryAgentLinkCatalog(
      customers: List.unmodifiable(customerRows.map(CustomerModel.fromMap)),
      flocks: List.unmodifiable(flockRows.map(FlockModel.fromMap)),
      hatcheries: List.unmodifiable(hatcheryRows.map(HatcheryModel.fromMap)),
    );
  }

  Future<List<TelegramStaffLink>> listPendingStaffLinks() async {
    final db = await _databaseHelper.db;
    final rows = await db.query(
      'telegram_staff_links',
      where: 'status = ?',
      whereArgs: [TelegramStaffLinkStatus.pending.storageKey],
      orderBy: 'updatedAt DESC, createdAt DESC, id ASC',
    );
    return rows.map(TelegramStaffLink.fromMap).toList(growable: false);
  }

  Future<List<TelegramStaffLink>> listStaffLinks() async {
    final db = await _databaseHelper.db;
    final rows = await db.query(
      'telegram_staff_links',
      where: 'status = ?',
      whereArgs: [TelegramStaffLinkStatus.allowed.storageKey],
      orderBy: 'displayName COLLATE NOCASE ASC, telegramUserId ASC, id ASC',
    );
    return rows.map(TelegramStaffLink.fromMap).toList(growable: false);
  }

  Future<void> approveStaffLink({
    required String linkId,
    required TelegramAgentAccessRole accessRole,
    required String? customerId,
    required String decidedBy,
    required DateTime decidedAt,
  }) async {
    final normalizedCustomerId = customerId?.trim();
    final hasCustomer =
        normalizedCustomerId != null && normalizedCustomerId.isNotEmpty;
    if (accessRole == TelegramAgentAccessRole.customer && !hasCustomer) {
      throw ArgumentError.value(
        customerId,
        'customerId',
        'Customer access requires one customer',
      );
    }
    if (accessRole == TelegramAgentAccessRole.admin && hasCustomer) {
      throw ArgumentError.value(
        customerId,
        'customerId',
        'Admin access cannot be restricted to one customer',
      );
    }

    final db = await _databaseHelper.db;
    final now = decidedAt.toUtc().toIso8601String();
    await db.transaction((txn) async {
      if (hasCustomer) {
        final customers = await txn.query(
          'customers',
          columns: const ['id'],
          where: 'id = ?',
          whereArgs: [normalizedCustomerId],
          limit: 1,
        );
        if (customers.isEmpty) {
          throw StateError('Assigned customer does not exist');
        }
      }
      final changed = await txn.update(
        'telegram_staff_links',
        {
          'status': TelegramStaffLinkStatus.allowed.storageKey,
          'accessRole': accessRole.storageKey,
          'customerId': hasCustomer ? normalizedCustomerId : null,
          'invitedBy': decidedBy,
          'updatedAt': now,
          'syncStatus': 'pending',
          'dirtyAt': now,
          'syncError': null,
        },
        where: 'id = ?',
        whereArgs: [linkId],
      );
      if (changed != 1) {
        throw StateError('Telegram staff link does not exist');
      }
    });
  }

  Future<void> setStaffLinkStatus({
    required String linkId,
    required TelegramStaffLinkStatus status,
    required String decidedBy,
    required DateTime decidedAt,
  }) async {
    if (status == TelegramStaffLinkStatus.allowed) {
      throw ArgumentError(
        'Allowed access must be assigned through approveStaffLink',
      );
    }
    final db = await _databaseHelper.db;
    final now = decidedAt.toUtc().toIso8601String();
    await db.update(
      'telegram_staff_links',
      {
        'status': status.storageKey,
        'invitedBy': decidedBy,
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
        'syncError': null,
      },
      where: 'id = ?',
      whereArgs: [linkId],
    );
  }

  Future<List<HatcheryDraftBatchSummary>> listBatchSummaries() async {
    final db = await _databaseHelper.db;
    final rows = await db.rawQuery('''
      SELECT
        batch.id,
        batch.submissionId,
        batch.status,
        batch.sourceSummary,
        submission.submittedAt,
        submission.sourceKind,
        submission.sourceText,
        submission.sourceFileName,
        submission.staffLinkId,
        submission.telegramUserId,
        COUNT(row.id) AS rowCount,
        SUM(CASE WHEN row.status = 'needs_review' THEN 1 ELSE 0 END)
          AS needsReviewCount,
        SUM(CASE WHEN row.status = 'approved' THEN 1 ELSE 0 END)
          AS approvedCount,
        SUM(CASE WHEN row.status = 'rejected' THEN 1 ELSE 0 END)
          AS rejectedCount
      FROM hatchery_draft_batches AS batch
      INNER JOIN agent_submissions AS submission
        ON submission.id = batch.submissionId
      LEFT JOIN hatchery_draft_rows AS row
        ON row.batchId = batch.id
      GROUP BY batch.id
      ORDER BY submission.submittedAt DESC, batch.id DESC
    ''');
    return rows.map(HatcheryDraftBatchSummary.fromMap).toList(growable: false);
  }

  Future<HatcheryDraftBatchDetails?> loadBatchDetails(String batchId) async {
    final db = await _databaseHelper.db;
    final batchRows = await db.query(
      'hatchery_draft_batches',
      where: 'id = ?',
      whereArgs: [batchId],
      limit: 1,
    );
    if (batchRows.isEmpty) return null;

    final batch = HatcheryDraftBatch.fromMap(batchRows.single);
    final submissionRows = await db.query(
      'agent_submissions',
      where: 'id = ?',
      whereArgs: [batch.submissionId],
      limit: 1,
    );
    if (submissionRows.isEmpty) {
      throw StateError('Draft batch is missing its submission');
    }

    final rowMaps = await db.query(
      'hatchery_draft_rows',
      where: 'batchId = ?',
      whereArgs: [batchId],
      orderBy: 'rowOrdinal ASC, id ASC',
    );
    final questionMaps = await db.query(
      'agent_questions',
      where: 'submissionId = ?',
      whereArgs: [batch.submissionId],
      orderBy: 'rowOrdinal ASC, createdAt ASC, id ASC',
    );
    final eventMaps = await db.query(
      'hatchery_agent_audit_events',
      where: 'submissionId = ?',
      whereArgs: [batch.submissionId],
      orderBy: 'createdAt ASC, id ASC',
    );

    return HatcheryDraftBatchDetails(
      submission: HatcheryAgentSubmission.fromMap(submissionRows.single),
      batch: batch,
      rows: rowMaps.map(HatcheryDraftRow.fromMap).toList(growable: false),
      questions: questionMaps
          .map(HatcheryAgentQuestion.fromMap)
          .toList(growable: false),
      events: eventMaps
          .map(HatcheryAgentAuditEvent.fromMap)
          .toList(growable: false),
    );
  }

  Future<HatcheryHistoricalPoint?> previousApprovedComparable({
    required String customerId,
    required String flockId,
    required String stationName,
    required String breed,
    required DateTime hatchDate,
  }) async {
    final db = await _databaseHelper.db;
    final rows = await db.query(
      'hatchery_daily_records',
      columns: const ['id', 'hatchDate', 'hatchabilityPct'],
      where:
          'customerId = ? AND flockId = ? AND stationName = ? '
          'AND breed = ? AND hatchDate < ?',
      whereArgs: [
        customerId,
        flockId,
        stationName,
        breed,
        hatchDate.toUtc().toIso8601String(),
      ],
      orderBy: 'hatchDate DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : HatcheryHistoricalPoint.fromMap(rows.single);
  }

  Future<HatcheryDailyRecord> approveDraftRow({
    required String rowId,
    required String approvedBy,
    required DateTime approvedAt,
  }) async {
    final db = await _databaseHelper.db;
    return db.transaction((txn) async {
      final rowMaps = await txn.query(
        'hatchery_draft_rows',
        where: 'id = ?',
        whereArgs: [rowId],
        limit: 1,
      );
      if (rowMaps.isEmpty) {
        throw StateError('Draft row not found');
      }
      final row = HatcheryDraftRow.fromMap(rowMaps.single);
      final batch = await _loadBatch(txn, row.batchId);

      if (row.status == HatcheryDraftRowStatus.approved) {
        final approvedRecordId = row.approvedRecordId;
        if (approvedRecordId == null) {
          throw StateError('Approved draft row is missing its final record');
        }
        final records = await txn.query(
          'hatchery_daily_records',
          where: 'id = ?',
          whereArgs: [approvedRecordId],
          limit: 1,
        );
        if (records.isEmpty) {
          throw StateError('Approved draft row final record was not found');
        }
        return HatcheryDailyRecord.fromMap(records.single);
      }
      if (row.status == HatcheryDraftRowStatus.rejected) {
        throw StateError('Rejected draft rows cannot be approved');
      }

      final customerId = _requiredText(row.customerId, 'customerId');
      final flockId = _requiredText(row.flockId, 'flockId');
      final stationName = _requiredText(row.stationName, 'stationName');
      final breed = _requiredText(row.breed, 'breed');
      final eggsPlaced = _requiredValue(row.eggsPlaced, 'eggsPlaced');
      final hatchDate = _requiredValue(row.hatchDate, 'hatchDate');
      final totalProduction = _requiredValue(
        row.totalProduction,
        'totalProduction',
      );
      final hatchabilityPct = _requiredValue(
        row.hatchabilityPct,
        'hatchabilityPct',
      );
      final reviewedAt = approvedAt.toUtc();
      final now = reviewedAt.toIso8601String();
      final record = HatcheryDailyRecord(
        id: const Uuid().v4(),
        sourceDraftRowId: row.id,
        customerId: customerId,
        flockId: flockId,
        hatcheryId: row.hatcheryId,
        stationName: stationName,
        breed: breed,
        eggsPlaced: eggsPlaced,
        productionDate: row.productionDate,
        placementDate: row.placementDate,
        eggWeightG: row.eggWeightG,
        fertilityPct: row.fertilityPct,
        transferWeightG: row.transferWeightG,
        setterNumber: row.setterNumber,
        hatcherNumber: row.hatcherNumber,
        hatchDate: hatchDate,
        healthyChicks: row.healthyChicks,
        secondGradeChicks: row.secondGradeChicks,
        condemnedChicks: row.condemnedChicks,
        totalProduction: totalProduction,
        hatchabilityPct: hatchabilityPct,
        approvedBy: approvedBy,
        approvedAt: reviewedAt,
        createdAt: reviewedAt,
        updatedAt: reviewedAt,
      );

      await txn.insert(
        'hatchery_daily_records',
        _pendingWrite(record.toMap(), now),
      );
      await txn.update(
        'hatchery_draft_rows',
        {
          'status': HatcheryDraftRowStatus.approved.storageKey,
          'approvedRecordId': record.id,
          'reviewedBy': approvedBy,
          'reviewedAt': now,
          'updatedAt': now,
          'syncStatus': 'pending',
          'dirtyAt': now,
          'syncError': null,
        },
        where: 'id = ?',
        whereArgs: [row.id],
      );
      await txn.insert(
        'hatchery_agent_audit_events',
        _pendingWrite(
          HatcheryAgentAuditEvent(
            id: const Uuid().v4(),
            submissionId: batch.submissionId,
            rowId: row.id,
            actorType: 'admin',
            actorId: approvedBy,
            eventType: 'row_approved',
            createdAt: reviewedAt,
            detailsJson: jsonEncode({'approvedRecordId': record.id}),
          ).toMap(),
          now,
        ),
      );
      await _recalculateBatchStatus(txn, batch.id, now);
      return record;
    });
  }

  Future<void> rejectDraftRow({
    required String rowId,
    required String rejectedBy,
    required DateTime rejectedAt,
    String? reason,
  }) async {
    final db = await _databaseHelper.db;
    await db.transaction((txn) async {
      final rowMaps = await txn.query(
        'hatchery_draft_rows',
        where: 'id = ?',
        whereArgs: [rowId],
        limit: 1,
      );
      if (rowMaps.isEmpty) {
        throw StateError('Draft row not found');
      }
      final row = HatcheryDraftRow.fromMap(rowMaps.single);
      final batch = await _loadBatch(txn, row.batchId);
      if (row.status == HatcheryDraftRowStatus.approved) {
        throw StateError('Approved draft rows cannot be rejected');
      }
      if (row.status == HatcheryDraftRowStatus.rejected) return;

      final reviewedAt = rejectedAt.toUtc();
      final now = reviewedAt.toIso8601String();
      await txn.update(
        'hatchery_draft_rows',
        {
          'status': HatcheryDraftRowStatus.rejected.storageKey,
          'reviewedBy': rejectedBy,
          'reviewedAt': now,
          'updatedAt': now,
          'syncStatus': 'pending',
          'dirtyAt': now,
          'syncError': null,
        },
        where: 'id = ?',
        whereArgs: [row.id],
      );
      final normalizedReason = reason?.trim();
      await txn.insert(
        'hatchery_agent_audit_events',
        _pendingWrite(
          HatcheryAgentAuditEvent(
            id: const Uuid().v4(),
            submissionId: batch.submissionId,
            rowId: row.id,
            actorType: 'admin',
            actorId: rejectedBy,
            eventType: 'row_rejected',
            createdAt: reviewedAt,
            detailsJson: normalizedReason == null || normalizedReason.isEmpty
                ? null
                : jsonEncode({'reason': normalizedReason}),
          ).toMap(),
          now,
        ),
      );
      await _recalculateBatchStatus(txn, batch.id, now);
    });
  }

  Future<void> updateDraftRow(HatcheryDraftRow row) async {
    final db = await _databaseHelper.db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final existingMaps = await txn.query(
        'hatchery_draft_rows',
        where: 'id = ?',
        whereArgs: [row.id],
        limit: 1,
      );
      if (existingMaps.isEmpty) {
        throw StateError('Draft row not found');
      }
      final existing = HatcheryDraftRow.fromMap(existingMaps.single);
      if (existing.status == HatcheryDraftRowStatus.approved ||
          existing.status == HatcheryDraftRowStatus.rejected) {
        throw StateError('Reviewed draft rows cannot be edited');
      }
      final values = _pendingWrite(row.toMap(), now)
        ..remove('id')
        ..['batchId'] = existing.batchId
        ..['rowOrdinal'] = existing.rowOrdinal
        ..['status'] = existing.status.storageKey
        ..['approvedRecordId'] = existing.approvedRecordId
        ..['reviewedBy'] = existing.reviewedBy
        ..['reviewedAt'] = existing.reviewedAt?.toUtc().toIso8601String()
        ..['createdAt'] = existing.createdAt?.toUtc().toIso8601String();
      await txn.update(
        'hatchery_draft_rows',
        values,
        where: 'id = ?',
        whereArgs: [row.id],
      );
    });
  }

  Future<HatcheryDraftBatch> _loadBatch(
    DatabaseExecutor db,
    String batchId,
  ) async {
    final batchMaps = await db.query(
      'hatchery_draft_batches',
      where: 'id = ?',
      whereArgs: [batchId],
      limit: 1,
    );
    if (batchMaps.isEmpty) {
      throw StateError('Draft row is missing its batch');
    }
    return HatcheryDraftBatch.fromMap(batchMaps.single);
  }

  Future<void> _recalculateBatchStatus(
    DatabaseExecutor db,
    String batchId,
    String now,
  ) async {
    final rows = await db.query(
      'hatchery_draft_rows',
      columns: const ['status'],
      where: 'batchId = ?',
      whereArgs: [batchId],
    );
    final statuses = rows
        .map((row) => HatcheryDraftRowStatus.fromStorage(row['status']))
        .toList(growable: false);
    final approvedCount = statuses
        .where((status) => status == HatcheryDraftRowStatus.approved)
        .length;
    final rejectedCount = statuses
        .where((status) => status == HatcheryDraftRowStatus.rejected)
        .length;
    final pendingCount = statuses.length - approvedCount - rejectedCount;
    final status = pendingCount == 0
        ? (approvedCount > 0
              ? AgentSubmissionStatus.approved
              : AgentSubmissionStatus.rejected)
        : (approvedCount > 0
              ? AgentSubmissionStatus.partiallyApproved
              : AgentSubmissionStatus.needsAdminReview);

    await db.update(
      'hatchery_draft_batches',
      {
        'status': status.storageKey,
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
        'syncError': null,
      },
      where: 'id = ?',
      whereArgs: [batchId],
    );
  }

  String _requiredText(String? value, String field) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      throw StateError('Draft row requires $field');
    }
    return normalized;
  }

  T _requiredValue<T>(T? value, String field) {
    if (value == null) {
      throw StateError('Draft row requires $field');
    }
    return value;
  }

  Map<String, Object?> _pendingWrite(Map<String, Object?> values, String now) {
    final pending = <String, Object?>{
      ...values,
      'syncStatus': 'pending',
      'dirtyAt': now,
      'syncError': null,
    };
    if (pending.containsKey('createdAt') && pending['createdAt'] == null) {
      pending['createdAt'] = now;
    }
    if (pending.containsKey('updatedAt')) {
      pending['updatedAt'] = now;
    }
    return pending;
  }
}
