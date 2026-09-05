import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/breeder_daily_report_model.dart';
import 'package:hatchaudit/data/repositories/breeder_bird_movement_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_daily_report_repository.dart';
import 'package:hatchaudit/data/repositories/poultry_hierarchy_repository.dart';
import 'package:hatchaudit/data/repositories/sync_conflict_repository.dart';
import 'package:hatchaudit/services/breeder/breeder_bird_ledger_service.dart';
import 'package:hatchaudit/services/breeder/breeder_report_conflict_service.dart';

import '../../support/test_database.dart';

/// `BreederReportConflictService` and its interaction with
/// `BreederBirdLedgerService`'s state machine (breeder-flock-performance
/// ticket 15, design doc section 5.3 and 13.1): a report in `Sync Conflict`
/// blocks submit/approve, and resolving it restores the state the report
/// held immediately before the conflict was detected.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BreederReportConflictService', () {
    setUpAll(() async {
      await useIsolatedAppDatabase();
    });

    tearDownAll(() async {
      await DatabaseHelper().close();
    });

    late BreederDailyReportRepository reportRepository;
    late BreederBirdMovementRepository movementRepository;
    late PoultryHierarchyRepository houseRepository;
    late SyncConflictRepository conflictRepository;
    late BreederReportConflictService conflictService;
    late BreederBirdLedgerService ledgerService;

    setUp(() {
      reportRepository = BreederDailyReportRepository();
      movementRepository = BreederBirdMovementRepository();
      houseRepository = PoultryHierarchyRepository();
      conflictRepository = SyncConflictRepository();
      conflictService = BreederReportConflictService(
        conflictRepository: conflictRepository,
        reportRepository: reportRepository,
      );
      ledgerService = BreederBirdLedgerService(
        reportRepository: reportRepository,
        movementRepository: movementRepository,
        houseRepository: houseRepository,
      );
    });

    Future<void> seedFlock(String flockId) async {
      final db = await DatabaseHelper().db;
      await db.insert('flocks', {'id': flockId, 'flockId': flockId});
    }

    /// Puts [report] into Sync Conflict the same way
    /// `BreederReportSyncService` would after a rejected push, with a
    /// minimal but valid pair of local/remote payload snapshots.
    /// [winningRevision] and [winningSyncToken] are kept deliberately
    /// independent in these fixtures (and often set to different values in
    /// the tests below) to prove resolution never conflates ticket 12's
    /// audit `revision` counter with the sync-only concurrency token: only
    /// `sync_token` should ever be adopted as `lastSyncedRevision`.
    Future<void> forceConflict(
      BreederDailyReport report, {
      int winningRevision = 2,
      int winningSyncToken = 2,
    }) async {
      await conflictRepository.recordConflictWithPayload(
        table: 'breeder_daily_reports',
        rowId: report.id,
        localUpdatedAt: DateTime.now(),
        remoteUpdatedAt: DateTime.now(),
        localDataJson: jsonEncode({
          'header': {'id': report.id, 'revision': report.revision},
          'movements': [],
          'feed_entries': [],
          'egg_production_entries': [],
          'inventory_movements': [],
        }),
        remoteDataJson: jsonEncode({
          'header': {
            'id': report.id,
            'revision': winningRevision,
            'sync_token': winningSyncToken,
          },
          'movements': [],
          'feed_entries': [],
          'egg_production_entries': [],
          'inventory_movements': [],
        }),
      );
      await reportRepository.enterConflict(report);
    }

    test(
      'a conflicted report cannot be submitted or approved until resolved',
      () async {
        await seedFlock('flock-conflict-1');
        var report = await reportRepository.createDraft(
          flockId: 'flock-conflict-1',
          reportDate: DateTime(2026, 2, 1),
        );
        report = await ledgerService.submit(report, actorUserId: 'u1');
        expect(report.isSubmitted, isTrue);

        await forceConflict(report);
        final conflicted = (await reportRepository.getById(report.id))!;
        expect(conflicted.isSyncConflict, isTrue);
        expect(conflicted.previousState, BreederDailyReportState.submitted);

        expect(
          () => ledgerService.approve(
            conflicted,
            actorUserId: 'u2',
            actorRole: BreederApprovalRole.productionManager,
          ),
          throwsA(isA<BreederReportStateError>()),
        );

        // A fresh Draft report in conflict is equally blocked from submit.
        await seedFlock('flock-conflict-2');
        final draftReport = await reportRepository.createDraft(
          flockId: 'flock-conflict-2',
          reportDate: DateTime(2026, 2, 2),
        );
        await forceConflict(draftReport, winningRevision: 2, winningSyncToken: 2);
        final conflictedDraft = (await reportRepository.getById(
          draftReport.id,
        ))!;
        expect(
          () => ledgerService.submit(conflictedDraft, actorUserId: 'u1'),
          throwsA(isA<BreederReportStateError>()),
        );
      },
    );

    test(
      'resolving a conflict (keeping local) restores the state the report '
      'held before the conflict, and re-arms it for another push',
      () async {
        await seedFlock('flock-conflict-3');
        var report = await reportRepository.createDraft(
          flockId: 'flock-conflict-3',
          reportDate: DateTime(2026, 2, 3),
        );
        report = await ledgerService.submit(report, actorUserId: 'u1');
        // submit() bumps the audit revision 1 -> 2. The cloud's winning
        // aggregate deliberately carries a DIFFERENT `revision` (99) and
        // its own `sync_token` (7), so a passing assertion below proves
        // resolution adopts the token and leaves the audit counter alone.
        await forceConflict(report, winningRevision: 99, winningSyncToken: 7);

        final resolved = await conflictService.resolve(
          reportId: report.id,
          resolution: BreederConflictResolution.keepLocal,
          reviewedBy: 'manager-1',
        );

        expect(resolved.state, BreederDailyReportState.submitted);
        expect(resolved.previousState, isNull);
        // The concurrency token is adopted from the cloud's sync_token...
        expect(resolved.lastSyncedRevision, 7);
        // ...but the ticket-12 audit revision counter is untouched by
        // conflict resolution — it still means what it meant, unaffected
        // by the cloud's unrelated revision value (99) or by resolution
        // itself (no state transition, no post-approval correction
        // happened here).
        expect(resolved.revision, 2);

        // The conflict is now reviewed, not open.
        final stillOpen = await conflictService.openConflictFor(report.id);
        expect(stillOpen, isNull);

        // Approval is no longer blocked now that the report is back to
        // Submitted.
        final row = await reportRepository.getRawById(report.id);
        expect(row!['syncStatus'], 'pending');
      },
    );

    test(
      'resolving a conflict (keeping remote) restores state and leaves the '
      'report already synced',
      () async {
        await seedFlock('flock-conflict-4');
        final report = await reportRepository.createDraft(
          flockId: 'flock-conflict-4',
          reportDate: DateTime(2026, 2, 4),
        );
        // Distinct revision/token values here too, so the assertions below
        // prove each local column adopts the correct cloud counterpart.
        await forceConflict(report, winningRevision: 3, winningSyncToken: 5);

        final resolved = await conflictService.resolve(
          reportId: report.id,
          resolution: BreederConflictResolution.keepRemote,
          reviewedBy: 'manager-2',
        );

        expect(resolved.state, BreederDailyReportState.draft);
        expect(resolved.previousState, isNull);
        final row = await reportRepository.getRawById(report.id);
        expect(row!['syncStatus'], 'synced');
        // Keeping remote fully adopts the cloud's row, audit revision
        // included.
        expect(row['revision'], 3);
        // The concurrency token adopts the cloud's sync_token — NOT its
        // revision — so this device's next push presents the token the
        // cloud actually holds.
        expect(row['lastSyncedRevision'], 5);
      },
    );
  });
}
