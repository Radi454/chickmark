/// Composes the flock Overview screen's view-model from the domain
/// services tickets 06-17 already built (breeder-flock-performance ticket
/// 18, design doc section 11: "Overview: current inventory, production,
/// feed, mortality, benchmark comparisons, data completeness, and open
/// alerts").
///
/// This service computes nothing that another service does not already
/// compute or expose a building block for — it sums and averages
/// already-derived per-report figures over a trailing period (the same
/// "caller aggregates" pattern `BreederReportPeriodService.sumOverPeriod`/
/// `averageOverPeriod` already document) and packages the results together
/// with completeness, benchmark provenance, and open alerts so the Overview
/// screen never has to reach past this one composition point into a raw
/// repository itself.
///
/// Judgment calls (see ticket 18 completion report for the full reasoning):
///  - The trailing period is `[today - (periodDays - 1), today]`, not a
///    calendar-aligned week — the Overview is a "how are we doing right
///    now" landing view, not the Daily Reports screen's own weekly/
///    cumulative breakdown.
///  - Bird counts are "as of now" (the same `asOf ?? now + 1 day` cutoff
///    convention `BreederBirdLedgerService.houseBalance`/
///    `isolationAreaBalance` already use), not scoped to the trailing
///    period — an inventory figure describes the flock today, regardless of
///    which days in the period were reported.
///  - The production-percent benchmark target is looked up at the flock's
///    *current* official production week (design section 7.3 already
///    documents the resulting small bias for a period that spans a
///    production-week boundary; this does not introduce a new one).
///  - Current egg stock reuses `BreederEggInventoryService.previousBalance`
///    with an `asOf` cutoff of tomorrow — deliberately not a new "current
///    balance" formula, since `previousBalance` already sums every
///    production entry and ledger movement strictly before its cutoff date,
///    and "tomorrow" is the same "as of now" cutoff bird counts use.
///  - Mortality is a flat sum across every location (house and isolation
///    alike) with no denominator, per design section 6 ("mortality reduces
///    the flock total wherever it is recorded"); it is never a ratio, so
///    the blank-not-zero convention only applies to the *feed*/*production*
///    per-bird figures.
library;

import '../../data/models/breeder_alert_models.dart';
import '../../data/models/breeder_benchmark_models.dart';
import '../../data/models/breeder_bird_movement_model.dart';
import '../../data/models/breeder_daily_report_model.dart';
import '../../data/models/breeder_weighing_session_model.dart';
import '../../data/models/flock_model.dart';
import '../../data/repositories/breeder_bird_movement_repository.dart';
import '../../data/repositories/breeder_egg_production_entry_repository.dart';
import '../../data/repositories/breeder_feed_entry_repository.dart';
import '../../data/repositories/breeder_performance_alert_repository.dart';
import 'breeder_bird_ledger_service.dart';
import 'breeder_egg_inventory_service.dart';
import 'breeder_egg_production_service.dart';
import 'breeder_flock_lifecycle_service.dart';
import 'breeder_report_period_service.dart';
import 'breeder_weighing_service.dart';

/// The metric code for weekly hen-week production percent in
/// `breeder_metric_definitions`, as loaded from
/// `assets/benchmarks/metric_definitions.json`. Named "hen-week", never
/// "hen-day" — `metricProvenance.hen_week_production_pct` in
/// `assets/benchmarks/aviagen_ross308_parent_stock_2021_en.json` records
/// that the source column is literally "Hen-Week (%)" and that the guide
/// publishes no "Hen-Day" heading for this table at all.
const String kBreederHenWeekProductionPctMetricCode = 'hen_week_production_pct';

/// Current live-bird counts for a flock, kept as three explicit figures —
/// production houses, isolation, and the flock total — never silently
/// merged (breeder-flock-performance tickets 07/08, design doc section 6
/// and 7.1). [totalFemales]/[totalMales] come from
/// `BreederBirdLedgerService.flockTotalBalance`, the only place houses and
/// isolation are added together.
class BreederFlockBirdCounts {
  final int houseFemales;
  final int houseMales;
  final int isolationFemales;
  final int isolationMales;
  final int totalFemales;
  final int totalMales;

  const BreederFlockBirdCounts({
    required this.houseFemales,
    required this.houseMales,
    required this.isolationFemales,
    required this.isolationMales,
    required this.totalFemales,
    required this.totalMales,
  });
}

/// Production, feed, and mortality summed/averaged over the Overview's
/// trailing period from already-recorded, already-approved daily reports.
/// Every ratio is `null` (never `0`) when nothing in the period yields a
/// usable value — see `CalculationUtils.divideOrNull`/`percentOf`'s
/// blank-not-zero convention, which every figure here is built from.
class BreederFlockOverviewPeriodTotals {
  /// Total eggs of every grade, house and isolation combined, across the
  /// period's recorded days. `null` when no day in the period was recorded
  /// at all (design section 14: a missing day is never zero-filled).
  final int? totalEggs;

  /// Total mortality (house and isolation) across the period's recorded
  /// days. `null` when no day in the period was recorded.
  final int? mortalityTotal;

  /// Total feed (house and isolation, both sexes) in kilograms across the
  /// period's recorded days. `null` when no day in the period was recorded.
  final double? feedKgTotal;

  /// Average of each recorded day's house-scope daily production percent
  /// (design section 7: `total eggs / closing live females * 100`).
  /// `null` when no recorded day produced a usable value.
  final double? avgProductionPercent;

  /// Average of each recorded day's house-scope feed grams per female.
  final double? avgFeedGramsPerFemale;

  /// Average of each recorded day's house-scope feed grams per male.
  final double? avgFeedGramsPerMale;

  const BreederFlockOverviewPeriodTotals({
    required this.totalEggs,
    required this.mortalityTotal,
    required this.feedKgTotal,
    required this.avgProductionPercent,
    required this.avgFeedGramsPerFemale,
    required this.avgFeedGramsPerMale,
  });
}

/// One egg grade's current stock balance (breeder-flock-performance ticket
/// 11), as of "now" rather than as of a specific report.
class BreederCurrentEggStock {
  final String gradeId;
  final String gradeName;
  final int closingBalance;

  const BreederCurrentEggStock({
    required this.gradeId,
    required this.gradeName,
    required this.closingBalance,
  });
}

/// The full Overview view-model for one flock (breeder-flock-performance
/// ticket 18). Every figure here was computed by an existing ticket 06-17
/// service; this class only packages the results together.
class BreederFlockOverview {
  final FlockModel flock;
  final FlockAgeSummary age;

  /// The flock's official production week on the default axis
  /// (breeder-flock-performance ticket 06). [isPreProduction] reads exactly
  /// off this — the Overview never invents a production week of its own.
  final ProductionWeekResult productionWeek;

  /// Both comparison axes offered for the flock (design section 3.1) — the
  /// Overview surfaces which axis and which benchmark profile version
  /// produced every comparison it shows.
  final ComparisonAxisOffer axisOffer;

  final BreederFlockBirdCounts birds;

  final DateTime periodStart;
  final DateTime periodEnd;
  final BreederPeriodCompleteness completeness;
  final BreederFlockOverviewPeriodTotals periodTotals;

  /// The production-percent comparison against the official hen-week
  /// target, carrying [completeness] alongside it so the partial-data
  /// warning is never separated from the number it qualifies (design
  /// section 14).
  final BreederBenchmarkPeriodComparison productionBenchmark;

  final List<BreederCurrentEggStock> eggStock;

  final BreederWeighingSession? latestFemaleWeighingSession;
  final BreederWeighingComparison? latestFemaleWeighingComparison;
  final BreederWeighingSession? latestMaleWeighingSession;
  final BreederWeighingComparison? latestMaleWeighingComparison;

  /// Every open (non-closed) alert for the flock, most severe/most recent
  /// first as returned by
  /// `BreederPerformanceAlertRepository.listForFlock(openOnly: true)`.
  final List<BreederPerformanceAlert> openAlerts;

  const BreederFlockOverview({
    required this.flock,
    required this.age,
    required this.productionWeek,
    required this.axisOffer,
    required this.birds,
    required this.periodStart,
    required this.periodEnd,
    required this.completeness,
    required this.periodTotals,
    required this.productionBenchmark,
    required this.eggStock,
    required this.latestFemaleWeighingSession,
    required this.latestFemaleWeighingComparison,
    required this.latestMaleWeighingSession,
    required this.latestMaleWeighingComparison,
    required this.openAlerts,
  });

  bool get isPreProduction => productionWeek.isPreProduction;
}

class BreederFlockOverviewService {
  BreederFlockOverviewService({
    BreederFlockLifecycleService? lifecycleService,
    BreederBirdLedgerService? birdLedgerService,
    BreederEggInventoryService? eggInventoryService,
    BreederWeighingService? weighingService,
    BreederReportPeriodService? periodService,
    BreederBirdMovementRepository? movementRepository,
    BreederFeedEntryRepository? feedEntryRepository,
    BreederEggProductionEntryRepository? eggProductionEntryRepository,
    BreederPerformanceAlertRepository? alertRepository,
  }) : lifecycleService = lifecycleService ?? BreederFlockLifecycleService(),
       birdLedgerService = birdLedgerService ?? BreederBirdLedgerService(),
       eggInventoryService = eggInventoryService ?? BreederEggInventoryService(),
       weighingService = weighingService ?? BreederWeighingService(),
       periodService = periodService ?? BreederReportPeriodService(),
       movementRepository =
           movementRepository ?? BreederBirdMovementRepository(),
       feedEntryRepository = feedEntryRepository ?? BreederFeedEntryRepository(),
       eggProductionEntryRepository =
           eggProductionEntryRepository ?? BreederEggProductionEntryRepository(),
       alertRepository = alertRepository ?? BreederPerformanceAlertRepository();

  final BreederFlockLifecycleService lifecycleService;
  final BreederBirdLedgerService birdLedgerService;
  final BreederEggInventoryService eggInventoryService;
  final BreederWeighingService weighingService;
  final BreederReportPeriodService periodService;
  final BreederBirdMovementRepository movementRepository;
  final BreederFeedEntryRepository feedEntryRepository;
  final BreederEggProductionEntryRepository eggProductionEntryRepository;
  final BreederPerformanceAlertRepository alertRepository;

  DateTime _dateOnly(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);

  /// Loads the full Overview view-model for [flock]. [periodDays] is the
  /// trailing window (inclusive of today) production/feed/mortality and
  /// completeness are computed over; defaults to 7 (the last week).
  Future<BreederFlockOverview> loadOverview({
    required FlockModel flock,
    DateTime? now,
    int periodDays = 7,
  }) async {
    if (periodDays <= 0) {
      throw ArgumentError.value(periodDays, 'periodDays', 'must be positive');
    }
    final effectiveNow = now ?? DateTime.now();
    final today = _dateOnly(effectiveNow);
    final periodStart = today.subtract(Duration(days: periodDays - 1));
    final asOfNow = today.add(const Duration(days: 1));

    final age = lifecycleService.ageSummary(flock, now: effectiveNow);
    final axisOffer = await lifecycleService.comparisonAxes(
      flock,
      now: effectiveNow,
    );
    final productionWeek = axisOffer.official;

    final birds = await _loadBirdCounts(flock, asOf: asOfNow);

    final completeness = await periodService.completenessFor(
      flockId: flock.id,
      start: periodStart,
      end: today,
    );
    final approvedReports = await periodService.approvedReportsInRange(
      flockId: flock.id,
      start: periodStart,
      end: today,
    );
    final periodTotals = await _aggregatePeriod(approvedReports);

    final productionTarget = await _officialProductionPercentTarget(
      profile: axisOffer.profile,
      productionWeek: productionWeek,
    );
    final productionBenchmark = periodService.compareToBenchmark(
      actualValue: periodTotals.avgProductionPercent,
      benchmarkValue: productionTarget,
      completeness: completeness,
    );

    final eggStock = await _currentEggStock(flock, asOf: asOfNow);

    final femaleWeighing = await _latestWeighingWithComparison(
      flock,
      BreederWeighingSessionSex.female,
    );
    final maleWeighing = await _latestWeighingWithComparison(
      flock,
      BreederWeighingSessionSex.male,
    );

    final openAlerts = await alertRepository.listForFlock(
      flock.id,
      openOnly: true,
    );

    return BreederFlockOverview(
      flock: flock,
      age: age,
      productionWeek: productionWeek,
      axisOffer: axisOffer,
      birds: birds,
      periodStart: periodStart,
      periodEnd: today,
      completeness: completeness,
      periodTotals: periodTotals,
      productionBenchmark: productionBenchmark,
      eggStock: eggStock,
      latestFemaleWeighingSession: femaleWeighing.$1,
      latestFemaleWeighingComparison: femaleWeighing.$2,
      latestMaleWeighingSession: maleWeighing.$1,
      latestMaleWeighingComparison: maleWeighing.$2,
      openAlerts: openAlerts,
    );
  }

  Future<BreederFlockBirdCounts> _loadBirdCounts(
    FlockModel flock, {
    required DateTime asOf,
  }) async {
    final houseFemales = await birdLedgerService.flockBalance(
      flockId: flock.id,
      sex: BreederBirdMovementSex.female,
      asOf: asOf,
    );
    final houseMales = await birdLedgerService.flockBalance(
      flockId: flock.id,
      sex: BreederBirdMovementSex.male,
      asOf: asOf,
    );
    final isolationFemales = await birdLedgerService.isolationFlockBalance(
      flockId: flock.id,
      sex: BreederBirdMovementSex.female,
      asOf: asOf,
    );
    final isolationMales = await birdLedgerService.isolationFlockBalance(
      flockId: flock.id,
      sex: BreederBirdMovementSex.male,
      asOf: asOf,
    );
    // flockTotalBalance is the only place houses and isolation are summed
    // (see BreederBirdLedgerService's own doc comment) — never re-added
    // here, even though houseFemales + isolationFemales would give the same
    // number, so a future change to that method's rule is never silently
    // bypassed by this screen.
    final totalFemales = await birdLedgerService.flockTotalBalance(
      flockId: flock.id,
      sex: BreederBirdMovementSex.female,
      asOf: asOf,
    );
    final totalMales = await birdLedgerService.flockTotalBalance(
      flockId: flock.id,
      sex: BreederBirdMovementSex.male,
      asOf: asOf,
    );
    return BreederFlockBirdCounts(
      houseFemales: houseFemales,
      houseMales: houseMales,
      isolationFemales: isolationFemales,
      isolationMales: isolationMales,
      totalFemales: totalFemales,
      totalMales: totalMales,
    );
  }

  Future<BreederFlockOverviewPeriodTotals> _aggregatePeriod(
    List<BreederDailyReport> approvedReports,
  ) async {
    int? totalEggs;
    int? mortalityTotal;
    double? feedKgTotal;
    final dailyProductionPct = <double?>[];
    final dailyFeedPerFemale = <double?>[];
    final dailyFeedPerMale = <double?>[];

    for (final report in approvedReports) {
      final movements = await movementRepository.getForReport(report.id);
      final feedEntries = await feedEntryRepository.getForReport(report.id);
      final eggEntries = await eggProductionEntryRepository.getForReport(
        report.id,
      );

      final dayMortality = movements.fold<int>(0, (a, m) => a + m.mortality);
      mortalityTotal = (mortalityTotal ?? 0) + dayMortality;

      final dayFeedKg = feedEntries.fold<double>(0, (a, e) => a + e.feedKg);
      feedKgTotal = (feedKgTotal ?? 0) + dayFeedKg;

      final closingFemalesHouse =
          BreederEggProductionService.closingFemalesHouseScope(movements);
      var closingMalesHouse = 0;
      for (final movement in movements) {
        if (movement.isHouseMovement && movement.isMale) {
          closingMalesHouse += movement.closing;
        }
      }

      var femaleFeedKgHouse = 0.0;
      var maleFeedKgHouse = 0.0;
      for (final entry in feedEntries) {
        if (!entry.isHouseEntry) continue;
        if (entry.sex == BreederBirdMovementSex.female) {
          femaleFeedKgHouse += entry.feedKg;
        } else if (entry.sex == BreederBirdMovementSex.male) {
          maleFeedKgHouse += entry.feedKg;
        }
      }
      dailyFeedPerFemale.add(
        BreederBirdLedgerService.feedGramsPerBird(
          feedKg: femaleFeedKgHouse,
          closingLiveBirds: closingFemalesHouse,
        ),
      );
      dailyFeedPerMale.add(
        BreederBirdLedgerService.feedGramsPerBird(
          feedKg: maleFeedKgHouse,
          closingLiveBirds: closingMalesHouse,
        ),
      );

      var dayTotalEggs = 0;
      var totalEggsHouseScope = 0;
      for (final entry in eggEntries) {
        dayTotalEggs += entry.count;
        if (entry.isHouseEntry) totalEggsHouseScope += entry.count;
      }
      totalEggs = (totalEggs ?? 0) + dayTotalEggs;
      dailyProductionPct.add(
        BreederEggProductionService.dailyProductionPercent(
          totalEggsHouseScope: totalEggsHouseScope,
          closingLiveFemalesHouseScope: closingFemalesHouse,
        ),
      );
    }

    return BreederFlockOverviewPeriodTotals(
      totalEggs: totalEggs,
      mortalityTotal: mortalityTotal,
      feedKgTotal: feedKgTotal,
      avgProductionPercent: periodService.averageOverPeriod(dailyProductionPct),
      avgFeedGramsPerFemale: periodService.averageOverPeriod(dailyFeedPerFemale),
      avgFeedGramsPerMale: periodService.averageOverPeriod(dailyFeedPerMale),
    );
  }

  Future<double?> _officialProductionPercentTarget({
    required BreederBenchmarkProfile? profile,
    required ProductionWeekResult productionWeek,
  }) async {
    if (profile == null || productionWeek.isPreProduction) return null;
    final metricDefs = await lifecycleService.benchmarkRepository
        .getMetricDefinitionsById();
    BreederMetricDefinition? metric;
    for (final def in metricDefs.values) {
      if (def.code == kBreederHenWeekProductionPctMetricCode) {
        metric = def;
        break;
      }
    }
    if (metric == null) return null;

    final values = await lifecycleService.benchmarkRepository
        .getValuesForProfile(profile.id);
    for (final value in values) {
      if (value.metricId == metric.id &&
          value.sex == BreederBirdMovementSex.female &&
          value.ageWeek == productionWeek.guideAgeWeeks) {
        return value.targetValue;
      }
    }
    return null;
  }

  Future<List<BreederCurrentEggStock>> _currentEggStock(
    FlockModel flock, {
    required DateTime asOf,
  }) async {
    final grades = await eggInventoryService.gradeRepository.listActiveGrades();
    final result = <BreederCurrentEggStock>[];
    for (final grade in grades) {
      final balance = await eggInventoryService.previousBalance(
        flockId: flock.id,
        gradeId: grade.id,
        reportDate: asOf,
      );
      result.add(
        BreederCurrentEggStock(
          gradeId: grade.id,
          gradeName: grade.name,
          closingBalance: balance,
        ),
      );
    }
    return result;
  }

  Future<(BreederWeighingSession?, BreederWeighingComparison?)>
  _latestWeighingWithComparison(FlockModel flock, String sex) async {
    final sessions = await weighingService.sessionRepository.listForFlock(
      flock.id,
    );
    BreederWeighingSession? latest;
    for (final session in sessions) {
      if (session.sex == sex) {
        latest = session;
        break;
      }
    }
    if (latest == null) return (null, null);
    final comparison = await weighingService.officialWeightTarget(
      flock: flock,
      sex: sex,
      sessionDate: latest.sessionDate,
    );
    return (latest, comparison);
  }
}
