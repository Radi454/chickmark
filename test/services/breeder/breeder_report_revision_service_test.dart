import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/breeder_daily_report_model.dart';
import 'package:hatchaudit/data/repositories/breeder_daily_report_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_report_revision_repository.dart';
import 'package:hatchaudit/services/breeder/breeder_bird_ledger_service.dart';
import 'package:hatchaudit/services/breeder/breeder_report_revision_service.dart';

import '../../support/test_database.dart';

/// `BreederReportRevisionService` and `BreederBirdLedgerService
/// .correctHeader` (breeder-flock-performance ticket 12, design doc section
/// 5.3, 12, and 13.1): a correction to an already-Approved report requires
/// a reason, writes one immutable revision row per changed field, bumps the
/// report's revision counter exactly once per correction, and a Draft
/// report's edits never write revision history at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  tearDownAll(() async {
    await DatabaseHelper().close();
  });

  late BreederDailyReportRepository reportRepository;
  late BreederReportRevisionRepository revisionRepository;
  late BreederReportRevisionService revisionService;
  late BreederBirdLedgerService ledgerService;

  setUp(() {
    reportRepository = BreederDailyReportRepository();
    revisionRepository = BreederReportRevisionRepository();
    revisionService = BreederReportRevisionService(
      revisionRepository: revisionRepository,
      reportRepository: reportRepository,
    );
    ledgerService = BreederBirdLedgerService(
      reportRepository: reportRepository,
      revisionService: revisionService,
    );
  });

  Future<void> seedFlock(String flockId) async {
    final db = await DatabaseHelper().db;
    await db.insert('flocks', {'id': flockId, 'flockId': flockId});
  }

  Future<BreederDailyReport> seedApprovedReport(
    String flockId,
    DateTime date,
  ) async {
    await seedFlock(flockId);
    var report = await reportRepository.createDraft(
      flockId: flockId,
      reportDate: date,
      insideTemperature: 20.0,
      outsideTemperature: 25.0,
      lightHours: 16.0,
      notes: 'original notes',
    );
    report = await reportRepository.applyTransition(
      report,
      newState: BreederDailyReportState.submitted,
      submittedBy: 'entry-user',
      submittedAt: date,
    );
    report = await reportRepository.applyTransition(
      report,
      newState: BreederDailyReportState.approved,
      approvedBy: 'manager-1',
      approvedAt: date,
    );
    return report;
  }

  group('BreederReportRevisionService.recordCorrection', () {
    test('requires a non-blank reason', () async {
      await seedFlock('flock-reason');
      final report = BreederDailyReport(
        id: 'report-reason-1',
        flockId: 'flock-reason',
        reportDate: DateTime(2026, 1, 1),
        state: BreederDailyReportState.approved,
        revision: 1,
      );
      expect(
        () => revisionService.recordCorrection(
          report: report,
          tableName: 'breeder_daily_reports',
          rowId: report.id,
          oldValues: {'notes': 'a'},
          newValues: {'notes': 'b'},
          reason: '   ',
          actorUserId: 'user-1',
        ),
        throwsA(isA<BreederReportCorrectionError>()),
      );
    });

    test('requires a non-blank actor', () async {
      await seedFlock('flock-actor');
      final report = BreederDailyReport(
        id: 'report-actor-1',
        flockId: 'flock-actor',
        reportDate: DateTime(2026, 1, 1),
        state: BreederDailyReportState.approved,
        revision: 1,
      );
      expect(
        () => revisionService.recordCorrection(
          report: report,
          tableName: 'breeder_daily_reports',
          rowId: report.id,
          oldValues: {'notes': 'a'},
          newValues: {'notes': 'b'},
          reason: 'a good reason',
          actorUserId: '',
        ),
        throwsA(isA<BreederReportCorrectionError>()),
      );
    });

    test('a no-op correction (nothing changed) writes nothing and does not bump the counter', () async {
      final report = await seedApprovedReport('flock-noop', DateTime(2026, 1, 2));
      final updated = await revisionService.recordCorrection(
        report: report,
        tableName: 'breeder_daily_reports',
        rowId: report.id,
        oldValues: {'notes': 'same'},
        newValues: {'notes': 'same'},
        reason: 'attempted correction',
        actorUserId: 'user-1',
      );
      expect(updated.revision, report.revision);
      final history = await revisionService.historyFor(report.id);
      expect(history, isEmpty);
    });
  });

  group('BreederBirdLedgerService.correctHeader', () {
    test('a correction to an approved report requires a reason', () async {
      final report = await seedApprovedReport('flock-correct-reason', DateTime(2026, 1, 3));
      expect(
        () => ledgerService.correctHeader(
          report,
          reason: '',
          actorUserId: 'manager-1',
          notes: 'updated notes',
        ),
        throwsA(isA<BreederReportCorrectionError>()),
      );
    });

    test(
      'writes one complete revision entry per changed field: actor, time, '
      'old value, and new value',
      () async {
        final report = await seedApprovedReport(
          'flock-correct-entry',
          DateTime(2026, 1, 4),
        );
        final before = DateTime.now();
        final updated = await ledgerService.correctHeader(
          report,
          reason: 'Thermometer was miscalibrated',
          actorUserId: 'manager-1',
          insideTemperature: 21.5,
          outsideTemperature: report.outsideTemperature,
          lightHours: report.lightHours,
          notes: report.notes,
        );

        final history = await revisionService.historyFor(report.id);
        expect(history, hasLength(1));
        final entry = history.single;
        expect(entry.fieldName, 'insideTemperature');
        expect(entry.oldValue, '20.0');
        expect(entry.newValue, '21.5');
        expect(entry.reason, 'Thermometer was miscalibrated');
        expect(entry.actorUserId, 'manager-1');
        expect(entry.tableName, 'breeder_daily_reports');
        expect(entry.rowId, report.id);
        expect(entry.revisionAfter, updated.revision);
        expect(
          entry.changedAt.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue,
        );
      },
    );

    test('the revision counter increments by exactly one per correction, even with multiple changed fields', () async {
      final report = await seedApprovedReport(
        'flock-correct-counter',
        DateTime(2026, 1, 5),
      );
      final startingRevision = report.revision;

      final updated = await ledgerService.correctHeader(
        report,
        reason: 'Multiple fields were wrong',
        actorUserId: 'manager-1',
        insideTemperature: 22.0,
        outsideTemperature: 26.0,
        lightHours: report.lightHours,
        notes: 'corrected notes',
      );

      expect(updated.revision, startingRevision + 1);
      final history = await revisionService.historyFor(report.id);
      expect(history, hasLength(3));
      for (final entry in history) {
        expect(entry.revisionAfter, updated.revision);
      }
    });

    test(
      'calculations use the latest approved revision: the stored report '
      'row reflects the corrected values, not the pre-correction ones',
      () async {
        final report = await seedApprovedReport(
          'flock-correct-latest',
          DateTime(2026, 1, 6),
        );
        await ledgerService.correctHeader(
          report,
          reason: 'first correction',
          actorUserId: 'manager-1',
          insideTemperature: 22.0,
          outsideTemperature: report.outsideTemperature,
          lightHours: report.lightHours,
          notes: report.notes,
        );
        final afterFirst = await reportRepository.getById(report.id);
        final secondUpdate = await ledgerService.correctHeader(
          afterFirst!,
          reason: 'second correction',
          actorUserId: 'manager-2',
          insideTemperature: 23.0,
          outsideTemperature: afterFirst.outsideTemperature,
          lightHours: afterFirst.lightHours,
          notes: afterFirst.notes,
        );

        final latest = await reportRepository.getById(report.id);
        expect(latest!.insideTemperature, 23.0);
        expect(latest.revision, secondUpdate.revision);
        expect(latest.revision, report.revision + 2);

        final history = await revisionService.historyFor(report.id);
        expect(history, hasLength(2));
        expect(history.first.oldValue, '20.0');
        expect(history.first.newValue, '22.0');
        expect(history.last.oldValue, '22.0');
        expect(history.last.newValue, '23.0');
      },
    );

    test('correctHeader refuses a Draft report — updateHeader is the Draft edit path', () async {
      await seedFlock('flock-correct-draft');
      final report = await reportRepository.createDraft(
        flockId: 'flock-correct-draft',
        reportDate: DateTime(2026, 1, 7),
        notes: 'draft notes',
      );
      expect(
        () => ledgerService.correctHeader(
          report,
          reason: 'should not be allowed',
          actorUserId: 'user-1',
          notes: 'edited',
        ),
        throwsA(isA<BreederReportStateError>()),
      );
    });

    test(
      'a Draft report edited via updateHeader writes no revision history at all',
      () async {
        await seedFlock('flock-draft-no-history');
        final report = await reportRepository.createDraft(
          flockId: 'flock-draft-no-history',
          reportDate: DateTime(2026, 1, 8),
          notes: 'draft notes',
        );
        await ledgerService.updateHeader(report, notes: 'edited draft notes');
        final history = await revisionService.historyFor(report.id);
        expect(history, isEmpty);
      },
    );
  });

  group('onApprovedReportRevised (ticket 17\'s single hook)', () {
    test(
      'is invoked with the revised report and reason once a correction '
      'actually writes revision history',
      () async {
        final calls = <(BreederDailyReport, String)>[];
        final hookedRevisionService = BreederReportRevisionService(
          revisionRepository: revisionRepository,
          reportRepository: reportRepository,
          onApprovedReportRevised: (report, reason) async {
            calls.add((report, reason));
          },
        );
        final hookedLedgerService = BreederBirdLedgerService(
          reportRepository: reportRepository,
          revisionService: hookedRevisionService,
        );

        final report = await seedApprovedReport(
          'flock-hook',
          DateTime(2026, 1, 9),
        );
        await hookedLedgerService.correctHeader(
          report,
          reason: 'corrected a transposed reading',
          actorUserId: 'user-1',
          notes: 'corrected notes',
        );

        expect(calls, hasLength(1));
        expect(calls.single.$1.flockId, 'flock-hook');
        expect(calls.single.$2, 'corrected a transposed reading');
      },
    );

    test('is never invoked for a no-op correction', () async {
      final calls = <(BreederDailyReport, String)>[];
      final hookedRevisionService = BreederReportRevisionService(
        revisionRepository: revisionRepository,
        reportRepository: reportRepository,
        onApprovedReportRevised: (report, reason) async {
          calls.add((report, reason));
        },
      );
      final report = await seedApprovedReport(
        'flock-hook-noop',
        DateTime(2026, 1, 10),
      );
      await hookedRevisionService.recordCorrection(
        report: report,
        tableName: 'breeder_daily_reports',
        rowId: report.id,
        oldValues: {'notes': 'same'},
        newValues: {'notes': 'same'},
        reason: 'attempted correction',
        actorUserId: 'user-1',
      );
      expect(calls, isEmpty);
    });
  });
}
