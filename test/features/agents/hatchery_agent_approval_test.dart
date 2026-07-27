import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/hatchery_agent_models.dart';
import 'package:hatchaudit/data/repositories/hatchery_agent_repository.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = await useIsolatedAppDatabase();
  });

  setUp(() async {
    await resetAppDatabase();
    await _clearTestData();
    await _seedCustomerFlockHatchery();
  });

  tearDownAll(() async {
    await resetAppDatabase();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test(
    'approving a draft row creates final hatchery record and marks row approved',
    () async {
      final repo = HatcheryAgentRepository();
      await _seedDraftBatch(repo, rows: [_draftRow(id: 'row-1')]);

      final saved = await repo.approveDraftRow(
        rowId: 'row-1',
        approvedBy: 'admin-1',
        approvedAt: DateTime.utc(2026, 7, 27, 10),
      );

      expect(saved.hatchabilityPct, closeTo(60, 0.1));
      expect(saved.sourceDraftRowId, 'row-1');
      expect(saved.approvedBy, 'admin-1');

      final details = await repo.loadBatchDetails('batch-1');
      expect(details!.rows.single.status, HatcheryDraftRowStatus.approved);
      expect(details.rows.single.approvedRecordId, saved.id);
      expect(details.batch.status, AgentSubmissionStatus.approved);
      expect(details.events.single.eventType, 'row_approved');
      expect(details.events.single.actorId, 'admin-1');

      final db = await DatabaseHelper().db;
      final finalRows = await db.query('hatchery_daily_records');
      expect(finalRows, hasLength(1));
      expect(finalRows.single['sourceDraftRowId'], 'row-1');
      for (final table in const [
        'hatchery_daily_records',
        'hatchery_draft_rows',
        'hatchery_draft_batches',
        'hatchery_agent_audit_events',
      ]) {
        final rows = await db.query(table);
        expect(
          rows.every(
            (row) => row['syncStatus'] == 'pending' && row['dirtyAt'] != null,
          ),
          isTrue,
          reason: '$table approval changes must be queued for sync',
        );
      }
    },
  );

  test('approval rejects row without matched customer and flock ids', () async {
    final repo = HatcheryAgentRepository();
    await _seedDraftBatch(
      repo,
      rows: [_draftRow(id: 'row-unmatched', customerId: null, flockId: null)],
    );

    await expectLater(
      repo.approveDraftRow(
        rowId: 'row-unmatched',
        approvedBy: 'admin-1',
        approvedAt: DateTime.utc(2026, 7, 27),
      ),
      throwsA(isA<StateError>()),
    );

    final details = await repo.loadBatchDetails('batch-1');
    expect(details!.rows.single.status, HatcheryDraftRowStatus.needsReview);
    expect(details.events, isEmpty);
    final db = await DatabaseHelper().db;
    expect(await db.query('hatchery_daily_records'), isEmpty);
  });

  test(
    'rejecting a row records the reason without creating final data',
    () async {
      final repo = HatcheryAgentRepository();
      await _seedDraftBatch(repo, rows: [_draftRow(id: 'row-1')]);

      await repo.rejectDraftRow(
        rowId: 'row-1',
        rejectedBy: 'admin-1',
        rejectedAt: DateTime.utc(2026, 7, 27, 11),
        reason: 'Wrong flock',
      );

      final details = await repo.loadBatchDetails('batch-1');
      expect(details!.rows.single.status, HatcheryDraftRowStatus.rejected);
      expect(details.rows.single.reviewedBy, 'admin-1');
      expect(details.batch.status, AgentSubmissionStatus.rejected);
      expect(details.events.single.eventType, 'row_rejected');
      expect(
        jsonDecode(details.events.single.detailsJson!)['reason'],
        'Wrong flock',
      );

      final db = await DatabaseHelper().db;
      expect(await db.query('hatchery_daily_records'), isEmpty);
      expect(
        (await db.query('hatchery_agent_audit_events')).single['syncStatus'],
        'pending',
      );
    },
  );

  test(
    'mixed row decisions recalculate partial and completed batch status',
    () async {
      final repo = HatcheryAgentRepository();
      await _seedDraftBatch(
        repo,
        rows: [
          _draftRow(id: 'row-1', rowOrdinal: 1),
          _draftRow(id: 'row-2', rowOrdinal: 2),
        ],
      );

      await repo.approveDraftRow(
        rowId: 'row-1',
        approvedBy: 'admin-1',
        approvedAt: DateTime.utc(2026, 7, 27, 10),
      );

      var details = await repo.loadBatchDetails('batch-1');
      expect(details!.batch.status, AgentSubmissionStatus.partiallyApproved);

      await repo.rejectDraftRow(
        rowId: 'row-2',
        rejectedBy: 'admin-1',
        rejectedAt: DateTime.utc(2026, 7, 27, 11),
      );

      details = await repo.loadBatchDetails('batch-1');
      expect(details!.batch.status, AgentSubmissionStatus.approved);
      expect(details.rows.map((row) => row.status), [
        HatcheryDraftRowStatus.approved,
        HatcheryDraftRowStatus.rejected,
      ]);
    },
  );

  test(
    'updating a draft row saves edited values and queues the row for sync',
    () async {
      final repo = HatcheryAgentRepository();
      await _seedDraftBatch(repo, rows: [_draftRow(id: 'row-1')]);
      final original = (await repo.loadBatchDetails('batch-1'))!.rows.single;

      await repo.updateDraftRow(
        original.copyWith(
          stationName: 'Station B',
          eggsPlaced: 2000,
          totalProduction: 1500,
          hatchabilityPct: 75,
        ),
      );

      final edited = (await repo.loadBatchDetails('batch-1'))!.rows.single;
      expect(edited.stationName, 'Station B');
      expect(edited.eggsPlaced, 2000);
      expect(edited.totalProduction, 1500);
      expect(edited.hatchabilityPct, 75);

      final db = await DatabaseHelper().db;
      final stored = (await db.query(
        'hatchery_draft_rows',
        where: 'id = ?',
        whereArgs: ['row-1'],
      )).single;
      expect(stored['syncStatus'], 'pending');
      expect(stored['dirtyAt'], isNotNull);
    },
  );
}

Future<void> _clearTestData() async {
  final db = await DatabaseHelper().db;
  for (final table in const [
    'hatchery_daily_records',
    'hatchery_agent_audit_events',
    'hatchery_draft_rows',
    'hatchery_draft_batches',
    'agent_questions',
    'agent_submissions',
    'hatcheries',
    'flocks',
    'customers',
  ]) {
    await db.delete(table);
  }
}

Future<void> _seedCustomerFlockHatchery() async {
  final db = await DatabaseHelper().db;
  await db.insert('customers', {
    'id': 'customer-1',
    'name': 'Customer One',
    'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
    'createdBy': 'test',
  });
  await db.insert('flocks', {
    'id': 'flock-1',
    'customerId': 'customer-1',
    'flockId': 'Ross 1',
    'breed': 'Ross',
    'entryDate': DateTime.utc(2025, 12, 1).toIso8601String(),
  });
  await db.insert('hatcheries', {
    'id': 'hatchery-1',
    'customerId': 'customer-1',
    'name': 'Main Hatchery',
    'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
    'createdBy': 'test',
  });
}

Future<void> _seedDraftBatch(
  HatcheryAgentRepository repository, {
  required List<HatcheryDraftRow> rows,
}) {
  return repository.createSubmissionGraph(
    submission: HatcheryAgentSubmission(
      id: 'submission-1',
      sourceKind: AgentSourceKind.text,
      sourceText: 'Draft hatchery results',
      status: AgentSubmissionStatus.needsAdminReview,
      submittedAt: DateTime.utc(2026, 7, 27, 8),
    ),
    batch: const HatcheryDraftBatch(
      id: 'batch-1',
      submissionId: 'submission-1',
      status: AgentSubmissionStatus.needsAdminReview,
    ),
    rows: rows,
  );
}

HatcheryDraftRow _draftRow({
  required String id,
  int rowOrdinal = 1,
  String? customerId = 'customer-1',
  String? flockId = 'flock-1',
}) {
  return HatcheryDraftRow(
    id: id,
    batchId: 'batch-1',
    rowOrdinal: rowOrdinal,
    status: HatcheryDraftRowStatus.needsReview,
    customerId: customerId,
    customerName: 'Customer One',
    flockId: flockId,
    flockName: 'Ross 1',
    hatcheryId: 'hatchery-1',
    stationName: 'Station A',
    breed: 'Ross',
    eggsPlaced: 1000,
    hatchDate: DateTime.utc(2026, 7, 27),
    healthyChicks: 550,
    secondGradeChicks: 30,
    condemnedChicks: 20,
    totalProduction: 600,
    hatchabilityPct: 60,
    confidencePct: 92,
  );
}
