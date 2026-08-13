import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/hatchery_agent_models.dart';
import 'package:hatchaudit/data/repositories/hatchery_agent_repository.dart';
import 'package:hatchaudit/data/repositories/performance_sync_repository.dart';
import 'package:sqflite/sqflite.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = await useIsolatedAppDatabase();
  });

  setUp(() async {
    await resetAppDatabase();
    await _clearAgentTables();
    await _seedCustomerFlockHatchery();
  });

  tearDownAll(() async {
    await resetAppDatabase();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test('createSubmissionGraph stores one batch with multiple rows', () async {
    final repo = HatcheryAgentRepository();

    await repo.createSubmissionGraph(
      submission: _submission(id: 'submission-1'),
      batch: _batch(id: 'batch-1', submissionId: 'submission-1'),
      rows: [
        _row(id: 'row-1', batchId: 'batch-1', rowOrdinal: 1),
        _row(id: 'row-2', batchId: 'batch-1', rowOrdinal: 2),
      ],
      questions: [
        HatcheryAgentQuestion(
          id: 'question-1',
          submissionId: 'submission-1',
          rowOrdinal: 2,
          fieldKey: 'flockAgeWeeks',
          questionTextEn: 'What is the flock age?',
          questionTextAr: 'ما عمر القطيع؟',
        ),
      ],
      events: [
        HatcheryAgentAuditEvent(
          id: 'event-1',
          submissionId: 'submission-1',
          rowId: 'row-1',
          actorType: 'agent',
          eventType: 'row_extracted',
          createdAt: DateTime.utc(2026, 7, 27, 8, 1),
        ),
      ],
    );

    final details = await repo.loadBatchDetails('batch-1');

    expect(details, isNotNull);
    expect(details!.submission.id, 'submission-1');
    expect(details.rows, hasLength(2));
    expect(details.rows.map((row) => row.rowOrdinal), [1, 2]);
    expect(details.questions.single.fieldKey, 'flockAgeWeeks');
    expect(details.events.single.eventType, 'row_extracted');
    expect(() => details.rows[0] = details.rows.first, throwsUnsupportedError);

    final db = await DatabaseHelper().db;
    for (final table in const [
      'agent_submissions',
      'agent_questions',
      'hatchery_draft_batches',
      'hatchery_draft_rows',
      'hatchery_agent_audit_events',
    ]) {
      final rows = await db.query(table);
      expect(rows, isNotEmpty, reason: '$table should have graph rows');
      expect(
        rows.every((row) => row['syncStatus'] == 'pending'),
        isTrue,
        reason: '$table writes should be pending sync',
      );
      expect(
        rows.every((row) => row['dirtyAt'] != null),
        isTrue,
        reason: '$table writes should record dirtyAt',
      );
    }
  });

  test(
    'createSubmissionGraph rolls back the whole graph on row failure',
    () async {
      final repo = HatcheryAgentRepository();

      await expectLater(
        repo.createSubmissionGraph(
          submission: _submission(id: 'submission-rollback'),
          batch: _batch(
            id: 'batch-rollback',
            submissionId: 'submission-rollback',
          ),
          rows: [
            _row(id: 'duplicate-row', batchId: 'batch-rollback', rowOrdinal: 1),
            _row(id: 'duplicate-row', batchId: 'batch-rollback', rowOrdinal: 2),
          ],
        ),
        throwsA(isA<DatabaseException>()),
      );

      final db = await DatabaseHelper().db;
      expect(
        await db.query(
          'agent_submissions',
          where: 'id = ?',
          whereArgs: ['submission-rollback'],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'hatchery_draft_batches',
          where: 'id = ?',
          whereArgs: ['batch-rollback'],
        ),
        isEmpty,
      );
    },
  );

  test(
    'loadSettings creates defaults and saveSettings upserts changes',
    () async {
      final repo = HatcheryAgentRepository();

      final defaults = await repo.loadSettings();

      expect(defaults.telegramEnabled, isTrue);
      expect(defaults.hatchabilityWarningThresholdPoints, 3);
      expect(defaults.minimumReadyConfidencePct, 85);

      await repo.saveSettings(
        const AgentSettings(
          telegramEnabled: false,
          hatchabilityWarningThresholdPoints: 4,
          minimumReadyConfidencePct: 90,
        ),
      );

      final saved = await repo.loadSettings();
      expect(saved.telegramEnabled, isFalse);
      expect(saved.hatchabilityWarningThresholdPoints, 4);
      expect(saved.minimumReadyConfidencePct, 90);

      final db = await DatabaseHelper().db;
      final rows = await db.query('agent_settings');
      expect(rows, hasLength(1));
      expect(rows.single['syncStatus'], 'pending');
      expect(rows.single['dirtyAt'], isNotNull);
    },
  );

  test('saveConfirmedSettings stores a synced cloud mirror', () async {
    final repo = HatcheryAgentRepository();
    final confirmed = AgentSettings(
      telegramEnabled: false,
      hatchabilityWarningThresholdPoints: 4,
      minimumReadyConfidencePct: 90,
      updatedAt: DateTime.utc(2026, 8, 13, 18),
    );

    await repo.saveConfirmedSettings(confirmed);

    final db = await DatabaseHelper().db;
    final rows = await db.query(
      'agent_settings',
      where: 'id = ?',
      whereArgs: const [1],
    );
    expect(rows, hasLength(1));
    expect(rows.single['telegramEnabled'], 0);
    expect(rows.single['hatchabilityWarningThresholdPoints'], 4);
    expect(rows.single['minimumReadyConfidencePct'], 90);
    expect(rows.single['syncStatus'], 'synced');
    expect(rows.single['dirtyAt'], isNull);
    expect(rows.single['lastSyncedAt'], isNotNull);
    expect(rows.single['syncError'], isNull);
  });

  test(
    'listBatchSummaries returns newest submissions first with row counts',
    () async {
      final repo = HatcheryAgentRepository();
      await repo.createSubmissionGraph(
        submission: _submission(
          id: 'submission-old',
          submittedAt: DateTime.utc(2026, 7, 26),
        ),
        batch: _batch(id: 'batch-old', submissionId: 'submission-old'),
        rows: [_row(id: 'row-old', batchId: 'batch-old', rowOrdinal: 1)],
      );
      await repo.createSubmissionGraph(
        submission: _submission(
          id: 'submission-new',
          submittedAt: DateTime.utc(2026, 7, 27),
        ),
        batch: _batch(id: 'batch-new', submissionId: 'submission-new'),
        rows: [
          _row(id: 'row-new-1', batchId: 'batch-new', rowOrdinal: 1),
          _row(id: 'row-new-2', batchId: 'batch-new', rowOrdinal: 2),
        ],
      );

      final summaries = await repo.listBatchSummaries();

      expect(summaries.map((summary) => summary.id), [
        'batch-new',
        'batch-old',
      ]);
      expect(summaries.first.submittedAt, DateTime.utc(2026, 7, 27));
      expect(summaries.first.rowCount, 2);
      expect(summaries.first.needsReviewCount, 2);
    },
  );

  test('loadLinkCatalog exposes customer-scoped edit choices', () async {
    final catalog = await HatcheryAgentRepository().loadLinkCatalog();

    expect(
      catalog.customers.map((customer) => customer.id),
      contains('customer-1'),
    );
    final flock = catalog.flocks.singleWhere((item) => item.id == 'flock-1');
    expect(flock.customerId, 'customer-1');
    final hatchery = catalog.hatcheries.singleWhere(
      (item) => item.id == 'hatchery-1',
    );
    expect(hatchery.customerId, 'customer-1');
  });

  test(
    'listPendingStaffLinks returns only newest pending Telegram requests',
    () async {
      final db = await DatabaseHelper().db;
      await db.insert('telegram_staff_links', {
        'id': 'pending-old',
        'telegramUserId': '111',
        'telegramChatId': 'chat-old',
        'displayName': 'Old Staff',
        'username': 'oldstaff',
        'status': 'pending',
        'createdAt': DateTime.utc(2026, 7, 26, 8).toIso8601String(),
        'updatedAt': DateTime.utc(2026, 7, 26, 8).toIso8601String(),
      });
      await db.insert('telegram_staff_links', {
        'id': 'pending-new',
        'telegramUserId': '222',
        'telegramChatId': 'chat-new',
        'displayName': 'New Staff',
        'username': 'newstaff',
        'status': 'pending',
        'createdAt': DateTime.utc(2026, 7, 27, 8).toIso8601String(),
        'updatedAt': DateTime.utc(2026, 7, 27, 8).toIso8601String(),
      });
      await db.insert('telegram_staff_links', {
        'id': 'allowed-1',
        'telegramUserId': '333',
        'telegramChatId': 'chat-allowed',
        'displayName': 'Allowed Staff',
        'status': 'allowed',
        'accessRole': 'admin',
        'createdAt': DateTime.utc(2026, 7, 27, 9).toIso8601String(),
        'updatedAt': DateTime.utc(2026, 7, 27, 9).toIso8601String(),
      });

      final pending = await HatcheryAgentRepository().listPendingStaffLinks();

      expect(pending.map((link) => link.id), ['pending-new', 'pending-old']);
      expect(pending.first.telegramUserId, '222');
      expect(pending.first.displayName, 'New Staff');
      expect(pending.first.username, 'newstaff');
      expect(pending.first.status, TelegramStaffLinkStatus.pending);

      final all = await HatcheryAgentRepository().listStaffLinks();
      expect(all.map((link) => link.id), contains('allowed-1'));
      expect(
        all.firstWhere((link) => link.id == 'allowed-1').accessRole,
        TelegramAgentAccessRole.admin,
      );
    },
  );

  test(
    'approveStaffLink atomically stores customer scope and dirty metadata',
    () async {
      final db = await DatabaseHelper().db;
      await db.insert('telegram_staff_links', {
        'id': 'pending-1',
        'telegramUserId': '111',
        'telegramChatId': 'chat-1',
        'displayName': 'Pending Staff',
        'status': 'pending',
        'createdAt': DateTime.utc(2026, 7, 27, 8).toIso8601String(),
        'updatedAt': DateTime.utc(2026, 7, 27, 8).toIso8601String(),
        'syncStatus': 'synced',
      });

      await HatcheryAgentRepository().approveStaffLink(
        linkId: 'pending-1',
        accessRole: TelegramAgentAccessRole.customer,
        customerId: 'customer-1',
        decidedBy: 'admin-1',
        decidedAt: DateTime.utc(2026, 7, 27, 9),
      );

      final rows = await db.query(
        'telegram_staff_links',
        where: 'id = ?',
        whereArgs: ['pending-1'],
      );
      expect(rows.single['status'], 'allowed');
      expect(rows.single['accessRole'], 'customer');
      expect(rows.single['customerId'], 'customer-1');
      expect(rows.single['invitedBy'], 'admin-1');
      expect(
        rows.single['updatedAt'],
        DateTime.utc(2026, 7, 27, 9).toIso8601String(),
      );
      expect(rows.single['syncStatus'], 'pending');
      expect(rows.single['dirtyAt'], isNotNull);
    },
  );

  test(
    'approveStaffLink rejects inconsistent or unknown customer scope',
    () async {
      final db = await DatabaseHelper().db;
      await db.insert('telegram_staff_links', {
        'id': 'pending-1',
        'telegramUserId': '111',
        'status': 'pending',
      });
      final repository = HatcheryAgentRepository();

      await expectLater(
        repository.approveStaffLink(
          linkId: 'pending-1',
          accessRole: TelegramAgentAccessRole.customer,
          customerId: null,
          decidedBy: 'admin-1',
          decidedAt: DateTime.utc(2026, 7, 27, 9),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.approveStaffLink(
          linkId: 'pending-1',
          accessRole: TelegramAgentAccessRole.admin,
          customerId: 'customer-1',
          decidedBy: 'admin-1',
          decidedAt: DateTime.utc(2026, 7, 27, 9),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.approveStaffLink(
          linkId: 'pending-1',
          accessRole: TelegramAgentAccessRole.customer,
          customerId: 'missing-customer',
          decidedBy: 'admin-1',
          decidedAt: DateTime.utc(2026, 7, 27, 9),
        ),
        throwsStateError,
      );

      final row = (await db.query(
        'telegram_staff_links',
        where: 'id = ?',
        whereArgs: ['pending-1'],
      )).single;
      expect(row['status'], 'pending');
    },
  );

  test('approveStaffLink permits unrestricted admin access', () async {
    final db = await DatabaseHelper().db;
    await db.insert('telegram_staff_links', {
      'id': 'pending-admin',
      'telegramUserId': '222',
      'status': 'pending',
    });

    await HatcheryAgentRepository().approveStaffLink(
      linkId: 'pending-admin',
      accessRole: TelegramAgentAccessRole.admin,
      customerId: null,
      decidedBy: 'admin-1',
      decidedAt: DateTime.utc(2026, 7, 27, 9),
    );

    final row = (await db.query(
      'telegram_staff_links',
      where: 'id = ?',
      whereArgs: ['pending-admin'],
    )).single;
    expect(row['status'], 'allowed');
    expect(row['accessRole'], 'admin');
    expect(row['customerId'], isNull);
  });

  test('previousApprovedComparable uses exact key before hatch date', () async {
    final db = await DatabaseHelper().db;
    await _insertDailyRecord(
      db,
      id: 'match-old',
      hatchDate: DateTime.utc(2026, 7, 20),
      hatchabilityPct: 80,
    );
    await _insertDailyRecord(
      db,
      id: 'match-latest',
      hatchDate: DateTime.utc(2026, 7, 25),
      hatchabilityPct: 82.5,
    );
    await _insertDailyRecord(
      db,
      id: 'after-cutoff',
      hatchDate: DateTime.utc(2026, 7, 28),
      hatchabilityPct: 90,
    );
    await _insertDailyRecord(
      db,
      id: 'different-breed',
      hatchDate: DateTime.utc(2026, 7, 26),
      hatchabilityPct: 70,
      breed: 'Cobb',
    );

    final point = await HatcheryAgentRepository().previousApprovedComparable(
      customerId: 'customer-1',
      flockId: 'flock-1',
      stationName: 'Station A',
      breed: 'Ross',
      hatchDate: DateTime.utc(2026, 7, 27),
    );

    expect(point, isNotNull);
    expect(point!.recordId, 'match-latest');
    expect(point.hatchabilityPct, 82.5);
  });

  test('operational sync order includes the hatchery agent graph', () {
    expect(
      PerformanceSyncRepository.postFlockPushOrder,
      containsAllInOrder(const [
        'telegram_staff_links',
        'agent_settings',
        'agent_submissions',
        'agent_questions',
        'hatchery_draft_batches',
        'hatchery_draft_rows',
        'hatchery_agent_audit_events',
        'hatchery_daily_records',
      ]),
    );
  });
}

Future<void> _clearAgentTables() async {
  final db = await DatabaseHelper().db;
  for (final table in const [
    'hatchery_daily_records',
    'hatchery_agent_audit_events',
    'hatchery_draft_rows',
    'hatchery_draft_batches',
    'agent_questions',
    'agent_submissions',
    'agent_settings',
    'telegram_staff_links',
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
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  await db.insert('flocks', {
    'id': 'flock-1',
    'customerId': 'customer-1',
    'flockId': 'Ross 1',
    'breed': 'Ross',
    'entryDate': DateTime.utc(2025, 12, 1).toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  await db.insert('hatcheries', {
    'id': 'hatchery-1',
    'customerId': 'customer-1',
    'name': 'Main Hatchery',
    'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
    'createdBy': 'test',
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

HatcheryAgentSubmission _submission({
  required String id,
  DateTime? submittedAt,
}) {
  return HatcheryAgentSubmission(
    id: id,
    telegramUpdateId: 'update-$id',
    telegramMessageId: 'message-$id',
    telegramChatId: 'chat-1',
    telegramUserId: 'user-1',
    sourceKind: AgentSourceKind.text,
    sourceText: 'Hatchery source',
    status: AgentSubmissionStatus.needsAdminReview,
    submittedAt: submittedAt ?? DateTime.utc(2026, 7, 27, 8),
  );
}

HatcheryDraftBatch _batch({required String id, required String submissionId}) {
  return HatcheryDraftBatch(
    id: id,
    submissionId: submissionId,
    status: AgentSubmissionStatus.needsAdminReview,
    sourceSummary: 'Extracted hatchery rows',
  );
}

HatcheryDraftRow _row({
  required String id,
  required String batchId,
  required int rowOrdinal,
}) {
  return HatcheryDraftRow(
    id: id,
    batchId: batchId,
    rowOrdinal: rowOrdinal,
    status: HatcheryDraftRowStatus.needsReview,
    customerId: 'customer-1',
    customerName: 'Customer One',
    flockId: 'flock-1',
    flockName: 'Ross 1',
    hatcheryId: 'hatchery-1',
    stationName: 'Station A',
    breed: 'Ross',
    eggsPlaced: 1000,
    hatchDate: DateTime.utc(2026, 7, 27),
    totalProduction: 850,
    hatchabilityPct: 85,
    confidencePct: 92,
  );
}

Future<void> _insertDailyRecord(
  Database db, {
  required String id,
  required DateTime hatchDate,
  required double hatchabilityPct,
  String breed = 'Ross',
}) {
  return db.insert('hatchery_daily_records', {
    'id': id,
    'customerId': 'customer-1',
    'flockId': 'flock-1',
    'hatcheryId': 'hatchery-1',
    'stationName': 'Station A',
    'breed': breed,
    'eggsPlaced': 1000,
    'hatchDate': hatchDate.toIso8601String(),
    'totalProduction': hatchabilityPct * 10,
    'hatchabilityPct': hatchabilityPct,
    'syncStatus': 'synced',
  });
}
