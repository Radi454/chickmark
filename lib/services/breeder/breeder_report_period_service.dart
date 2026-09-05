/// Weekly and cumulative period aggregation for a breeder flock's daily
/// reports (breeder-flock-performance ticket 12, design doc section 5, 14,
/// and 17/18's shared-implementation note: "Put the period aggregation in
/// the existing lib/services/breeder/ service area so alerts (ticket 17)
/// and the overview (ticket 18) reuse one implementation rather than
/// re-deriving completeness.").
///
/// Daily reporting is optional (design section 5: "Daily reporting is
/// optional. A missing report means missing data, never a zero-value
/// report."). This service is the single place that turns "which calendar
/// dates in a requested period have no data" into a countable, labelled
/// fact, so no other code re-derives that logic — every period figure
/// alerts or the overview computes on top of [BreederPeriodCompleteness]
/// carries its own accurate recorded/missing counts, and this service
/// itself never imputes, interpolates, carries forward, or zero-fills a
/// missing day (design section 14: "Missing days are permitted and never
/// auto-created as zero days").
///
/// Judgment call: "recorded" means an *Approved* report exists for that
/// date, not merely a Draft or Submitted one. Design section 5.3's "Reports
/// use the latest approved revision for current calculations" already
/// establishes that only approved data is authoritative for calculation
/// purposes; a Draft or Submitted report can still change without leaving
/// any revision trail (design section 5.3: "Draft reports edit normally"),
/// so counting it as "recorded" here would let an aggregate silently shift
/// underneath a reader without the incomplete-data label ever having said
/// so.
library;

import '../../core/utils/calculation_utils.dart';
import '../../data/models/breeder_daily_report_model.dart';
import '../../data/repositories/breeder_daily_report_repository.dart';

/// How many calendar dates in a requested period have an approved report
/// and how many do not, plus exactly which dates are missing (design
/// section 12/14: "identify missing dates ... recorded and missing day
/// counts").
class BreederPeriodCompleteness {
  final DateTime start;
  final DateTime end;

  /// Every date in `[start, end]` (inclusive) that has an Approved report.
  final List<DateTime> recordedDates;

  /// Every date in `[start, end]` (inclusive) that has no Approved report —
  /// never filled in, guessed, or otherwise synthesized (design section
  /// 14).
  final List<DateTime> missingDates;

  const BreederPeriodCompleteness({
    required this.start,
    required this.end,
    required this.recordedDates,
    required this.missingDates,
  });

  int get recordedDayCount => recordedDates.length;
  int get missingDayCount => missingDates.length;
  int get totalDayCount => recordedDayCount + missingDayCount;

  /// True only when every date in the period has an approved report.
  bool get isComplete => missingDates.isEmpty;

  /// The label design section 12/14 requires whenever the period is not
  /// complete: "Weekly and cumulative calculations ... display `Incomplete
  /// Data`." A complete period carries no such label.
  String? get incompleteDataLabel {
    if (isComplete) return null;
    return 'Incomplete Data ($recordedDayCount of $totalDayCount days '
        'recorded, $missingDayCount missing)';
  }
}

/// The result of comparing an aggregated actual value against an official
/// benchmark value over a period (design section 14: "Partial results may
/// be compared with the official benchmark only with a visible partial
/// -data warning."). [completeness] is carried alongside the comparison so
/// a caller can never render one without the other.
class BreederBenchmarkPeriodComparison {
  final double? actualValue;
  final double? benchmarkValue;
  final BreederPeriodCompleteness completeness;

  const BreederBenchmarkPeriodComparison({
    required this.actualValue,
    required this.benchmarkValue,
    required this.completeness,
  });

  /// True whenever the period this comparison covers is not fully
  /// recorded — the trigger for the visible partial-data warning design
  /// section 14 requires.
  bool get isPartialData => !completeness.isComplete;

  /// The warning text to show alongside the comparison whenever
  /// [isPartialData] is true; `null` for a fully-recorded period, since an
  /// unwarranted warning is as misleading as a missing one.
  String? get partialDataWarning {
    if (!isPartialData) return null;
    return 'Partial data: based on ${completeness.recordedDayCount} of '
        '${completeness.totalDayCount} days. Comparison against the '
        'official benchmark may not be representative.';
  }
}

class BreederReportPeriodService {
  BreederReportPeriodService({
    BreederDailyReportRepository? reportRepository,
  }) : reportRepository = reportRepository ?? BreederDailyReportRepository();

  final BreederDailyReportRepository reportRepository;

  DateTime _dateOnly(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);

  /// Which calendar dates in `[start, end]` (inclusive) have an Approved
  /// report for [flockId] and which do not. [start] must not be after
  /// [end].
  Future<BreederPeriodCompleteness> completenessFor({
    required String flockId,
    required DateTime start,
    required DateTime end,
  }) async {
    final startDay = _dateOnly(start);
    final endDay = _dateOnly(end);
    if (endDay.isBefore(startDay)) {
      throw ArgumentError('end ($end) must not be before start ($start)');
    }

    final reports = await reportRepository.listForFlock(flockId);
    final approvedDates = <String>{
      for (final report in reports)
        if (report.isApproved) report.reportDateKey,
    };

    final recorded = <DateTime>[];
    final missing = <DateTime>[];
    for (
      var day = startDay;
      !day.isAfter(endDay);
      day = day.add(const Duration(days: 1))
    ) {
      if (approvedDates.contains(BreederDailyReport.dateKey(day))) {
        recorded.add(day);
      } else {
        missing.add(day);
      }
    }
    return BreederPeriodCompleteness(
      start: startDay,
      end: endDay,
      recordedDates: recorded,
      missingDates: missing,
    );
  }

  /// Convenience for a 7-day week starting on [weekStart] (inclusive).
  Future<BreederPeriodCompleteness> weeklyCompleteness({
    required String flockId,
    required DateTime weekStart,
  }) {
    return completenessFor(
      flockId: flockId,
      start: weekStart,
      end: weekStart.add(const Duration(days: 6)),
    );
  }

  /// Every Approved report for [flockId] whose date falls in
  /// `[start, end]` (inclusive) — the raw material a caller aggregates
  /// (sums, averages) into a period figure. Deliberately returns only the
  /// reports that actually exist; a caller must derive [totalDayCount] from
  /// [completenessFor] rather than from `.length` here, since `.length`
  /// alone cannot distinguish "every day recorded" from "half the days
  /// recorded".
  Future<List<BreederDailyReport>> approvedReportsInRange({
    required String flockId,
    required DateTime start,
    required DateTime end,
  }) async {
    final startDay = _dateOnly(start);
    final endDay = _dateOnly(end);
    final reports = await reportRepository.listForFlock(flockId);
    return reports
        .where(
          (r) =>
              r.isApproved &&
              !r.reportDate.isBefore(startDay) &&
              !r.reportDate.isAfter(endDay),
        )
        .toList();
  }

  /// Averages only the present values in [valuesForRecordedDays] — never a
  /// zero-fill for a missing day, since a missing day contributes no entry
  /// to this list at all (design section 14). Returns `null` (never `0`)
  /// when nothing is present, matching `CalculationUtils.divideOrNull`'s
  /// "blank, never zero" convention for an empty denominator.
  double? averageOverPeriod(
    List<double?> valuesForRecordedDays, {
    int decimalPlaces = 1,
  }) {
    final present = valuesForRecordedDays.whereType<double>().toList();
    if (present.isEmpty) return null;
    return CalculationUtils.roundTo(
      CalculationUtils.average(present),
      decimalPlaces: decimalPlaces,
    );
  }

  /// Sums only the present values in [valuesForRecordedDays] — same
  /// never-impute rule as [averageOverPeriod]. Returns `null` when nothing
  /// is present.
  double? sumOverPeriod(List<double?> valuesForRecordedDays) {
    final present = valuesForRecordedDays.whereType<double>().toList();
    if (present.isEmpty) return null;
    return present.reduce((a, b) => a + b);
  }

  /// Packages an aggregated [actualValue] against [benchmarkValue] together
  /// with [completeness] so a caller can never show the comparison without
  /// also knowing (and being able to show) whether it is partial (design
  /// section 14: "Partial results may be compared with the official
  /// benchmark only with a visible partial-data warning").
  BreederBenchmarkPeriodComparison compareToBenchmark({
    required double? actualValue,
    required double? benchmarkValue,
    required BreederPeriodCompleteness completeness,
  }) {
    return BreederBenchmarkPeriodComparison(
      actualValue: actualValue,
      benchmarkValue: benchmarkValue,
      completeness: completeness,
    );
  }
}
