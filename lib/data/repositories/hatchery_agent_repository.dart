import '../database/database_helper.dart';
import '../models/hatchery_agent_models.dart';

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
