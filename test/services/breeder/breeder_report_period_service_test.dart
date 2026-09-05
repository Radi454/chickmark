import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/breeder_daily_report_model.dart';
import 'package:hatchaudit/data/repositories/breeder_daily_report_repository.dart';
import 'package:hatchaudit/services/breeder/breeder_report_period_service.dart';

import '../../support/test_database.dart';

/// `BreederReportPeriodService` (breeder-flock-performance ticket 12,
/// design doc section 5, 12, and 14): weekly and cumulative figures stay
/// available when days are missing, but the service must say plainly which
/// dates are missing, how many days are recorded versus missing, never
/// impute a missing day, and mark a benchmark comparison as partial
/// whenever the underlying period is incomplete.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  tearDownAll(() async {
    await DatabaseHelper().close();
  });

  late BreederDailyReportRepository reportRepository;
  late BreederReportPeriodService periodService;

  setUp(() {
    reportRepository = BreederDailyReportRepository();
    periodService = BreederReportPeriodService(
      reportRepository: reportRepository,
    );
  });

  Future<void> seedFlock(String flockId) async {
    final db = await DatabaseHelper().db;
    await db.insert('flocks', {'id': flockId, 'flockId': flockId});
  }

  Future<void> seedApprovedReport(String flockId, DateTime date) async {
    var report = await reportRepository.createDraft(
      flockId: flockId,
      reportDate: date,
    );
    report = await reportRepository.applyTransition(
      report,
      newState: BreederDailyReportState.submitted,
      submittedBy: 'entry-user',
      submittedAt: date,
    );
    await reportRepository.applyTransition(
      report,
      newState: BreederDailyReportState.approved,
      approvedBy: 'manager-1',
      approvedAt: date,
    );
  }

  Future<void> seedDraftReport(String flockId, DateTime date) async {
    await reportRepository.createDraft(flockId: flockId, reportDate: date);
  }

  group('weekly completeness', () {
    test('a full week of approved reports is complete, with no missing dates', () async {
      const flockId = 'flock-week-full';
      await seedFlock(flockId);
      final weekStart = DateTime(2026, 2, 2); // Monday
      for (var i = 0; i < 7; i++) {
        await seedApprovedReport(flockId, weekStart.add(Duration(days: i)));
      }

      final completeness = await periodService.weeklyCompleteness(
        flockId: flockId,
        weekStart: weekStart,
      );

      expect(completeness.isComplete, isTrue);
      expect(completeness.recordedDayCount, 7);
      expect(completeness.missingDayCount, 0);
      expect(completeness.missingDates, isEmpty);
      expect(completeness.incompleteDataLabel, isNull);
    });

    test('a week with some missing dates is detected correctly, with accurate counts', () async {
      const flockId = 'flock-week-partial';
      await seedFlock(flockId);
      final weekStart = DateTime(2026, 2, 9);
      // Only 3 of 7 days approved; 2 more exist as unapproved Drafts, which
      // must NOT count as "recorded" (design section 5.3: only approved
      // data is authoritative for calculations).
      await seedApprovedReport(flockId, weekStart);
      await seedApprovedReport(flockId, weekStart.add(const Duration(days: 1)));
      await seedApprovedReport(flockId, weekStart.add(const Duration(days: 4)));
      await seedDraftReport(flockId, weekStart.add(const Duration(days: 2)));
      await seedDraftReport(flockId, weekStart.add(const Duration(days: 5)));

      final completeness = await periodService.weeklyCompleteness(
        flockId: flockId,
        weekStart: weekStart,
      );

      expect(completeness.isComplete, isFalse);
      expect(completeness.recordedDayCount, 3);
      expect(completeness.missingDayCount, 4);
      expect(completeness.totalDayCount, 7);
      expect(
        completeness.missingDates.map(BreederDailyReport.dateKey).toList(),
        [
          BreederDailyReport.dateKey(weekStart.add(const Duration(days: 2))),
          BreederDailyReport.dateKey(weekStart.add(const Duration(days: 3))),
          BreederDailyReport.dateKey(weekStart.add(const Duration(days: 5))),
          BreederDailyReport.dateKey(weekStart.add(const Duration(days: 6))),
        ],
      );
      expect(completeness.incompleteDataLabel, contains('Incomplete Data'));
      expect(completeness.incompleteDataLabel, contains('3 of 7'));
      expect(completeness.incompleteDataLabel, contains('4 missing'));
    });
  });

  group('cumulative completeness', () {
    test('a cumulative range across several weeks detects missing dates correctly', () async {
      const flockId = 'flock-cumulative';
      await seedFlock(flockId);
      final start = DateTime(2026, 3, 1);
      final end = DateTime(2026, 3, 20); // 20 days total
      // Approve every day except 5 scattered ones.
      final skip = {3, 7, 8, 15, 19};
      for (var i = 0; i < 20; i++) {
        if (skip.contains(i)) continue;
        await seedApprovedReport(flockId, start.add(Duration(days: i)));
      }

      final completeness = await periodService.completenessFor(
        flockId: flockId,
        start: start,
        end: end,
      );

      expect(completeness.totalDayCount, 20);
      expect(completeness.recordedDayCount, 15);
      expect(completeness.missingDayCount, 5);
      expect(completeness.missingDates, hasLength(5));
    });

    test('rejects an end date before the start date', () async {
      const flockId = 'flock-bad-range';
      await seedFlock(flockId);
      expect(
        () => periodService.completenessFor(
          flockId: flockId,
          start: DateTime(2026, 4, 10),
          end: DateTime(2026, 4, 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('never imputes', () {
    test('averageOverPeriod ignores missing days rather than treating them as zero', () async {
      // Two recorded days (10 and 20) and, implicitly, missing days simply
      // never appear in the list at all — never as a 0 entry.
      final average = periodService.averageOverPeriod([10.0, 20.0]);
      expect(average, 15.0);
    });

    test('averageOverPeriod returns null (never 0) when nothing is recorded', () {
      final average = periodService.averageOverPeriod(const []);
      expect(average, isNull);
    });

    test('sumOverPeriod only sums present values', () {
      final sum = periodService.sumOverPeriod([5.0, null, 7.0]);
      expect(sum, 12.0);
    });
  });

  group('benchmark comparison partial-data warning', () {
    test('a complete period carries no partial-data warning', () async {
      const flockId = 'flock-compare-complete';
      await seedFlock(flockId);
      final weekStart = DateTime(2026, 5, 4);
      for (var i = 0; i < 7; i++) {
        await seedApprovedReport(flockId, weekStart.add(Duration(days: i)));
      }
      final completeness = await periodService.weeklyCompleteness(
        flockId: flockId,
        weekStart: weekStart,
      );
      final comparison = periodService.compareToBenchmark(
        actualValue: 92.0,
        benchmarkValue: 95.0,
        completeness: completeness,
      );
      expect(comparison.isPartialData, isFalse);
      expect(comparison.partialDataWarning, isNull);
    });

    test('a partial period carries a visible partial-data warning', () async {
      const flockId = 'flock-compare-partial';
      await seedFlock(flockId);
      final weekStart = DateTime(2026, 5, 11);
      await seedApprovedReport(flockId, weekStart);
      await seedApprovedReport(flockId, weekStart.add(const Duration(days: 1)));
      final completeness = await periodService.weeklyCompleteness(
        flockId: flockId,
        weekStart: weekStart,
      );
      final comparison = periodService.compareToBenchmark(
        actualValue: 92.0,
        benchmarkValue: 95.0,
        completeness: completeness,
      );
      expect(comparison.isPartialData, isTrue);
      expect(comparison.partialDataWarning, isNotNull);
      expect(comparison.partialDataWarning, contains('Partial data'));
      expect(comparison.partialDataWarning, contains('2 of 7'));
    });
  });
}
