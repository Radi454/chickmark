/// Single source of truth for breeder flock age, production week, and
/// comparison-axis calculations (breeder-flock-performance ticket 06,
/// design doc section 7: "put the calculations in one place"). Later
/// tickets (daily report, weighing, alerts) must call into this service
/// rather than re-deriving age/production-week/axis logic themselves.
///
/// Three rules this service exists to enforce everywhere in the app:
///  - Total age always comes from `flocks.entryDate` via
///    `HatchDateUtils.flockAgeDays`/`flockAgeWeeks` — never a second age
///    calculator.
///  - Production week is always read from the active benchmark profile's
///    official `productionWeek` column, never derived from a manually
///    entered production-start date, physical transfer, or first-egg date.
///  - Depletion is never forced at a fixed age (`flocks.depletionAgeWeeks`
///    is not read here or anywhere else in this feature).
library;

import '../../core/utils/date_utils.dart';
import '../../data/models/breeder_benchmark_models.dart';
import '../../data/models/breeder_flock_milestone_model.dart';
import '../../data/models/flock_model.dart';
import '../../data/repositories/breeder_benchmark_repository.dart';
import '../../data/repositories/breeder_flock_milestone_repository.dart';

/// Which axis a production-week or benchmark-comparison result was computed
/// against. `official` is the default, always-available age-based mapping
/// from the guide. `milestoneAligned` shifts the guide's rows by the
/// difference between the flock's recorded 5%-production milestone and the
/// guide's own official age for that milestone — offered only when that
/// difference exceeds [BreederFlockLifecycleService.axisToleranceWeeks].
enum ComparisonAxisKind { official, milestoneAligned }

/// Describes exactly which axis produced a result, plus enough to shift a
/// benchmark row's age when looking it up. [offsetWeeks] is always 0 for
/// [ComparisonAxisKind.official]. For [ComparisonAxisKind.milestoneAligned]
/// it is `recordedFivePercentAgeWeeks - officialFivePercentAgeWeeks`: the
/// number of weeks the flock's real schedule sits behind (positive) or
/// ahead of (negative) the guide's schedule.
class ComparisonAxis {
  final ComparisonAxisKind kind;
  final int offsetWeeks;

  const ComparisonAxis.official() : kind = ComparisonAxisKind.official, offsetWeeks = 0;

  const ComparisonAxis.milestoneAligned(this.offsetWeeks)
    : kind = ComparisonAxisKind.milestoneAligned;

  /// The guide age (in weeks) to look benchmark rows up at, given the
  /// flock's real [actualAgeWeeks]. Equal to [actualAgeWeeks] on the
  /// official axis; shifted by [offsetWeeks] on the milestone-aligned axis.
  int guideAgeWeeksFor(int actualAgeWeeks) => actualAgeWeeks - offsetWeeks;

  @override
  String toString() =>
      kind == ComparisonAxisKind.official
          ? 'ComparisonAxis.official'
          : 'ComparisonAxis.milestoneAligned(offsetWeeks: $offsetWeeks)';
}

/// Total age of a flock, computed only from `flocks.entryDate`.
class FlockAgeSummary {
  final int ageDays;
  final int ageWeeks;

  const FlockAgeSummary({required this.ageDays, required this.ageWeeks});
}

/// The result of looking up a flock's official production week. Carries the
/// axis and benchmark profile version that produced it, per design section
/// 3.1: "every stored comparison ... records which axis produced it
/// alongside the benchmark profile version."
class ProductionWeekResult {
  /// The active benchmark profile matched to the flock's breed, or null if
  /// none is active for that breed (in which case the flock cannot be
  /// placed on any production-week axis at all).
  final BreederBenchmarkProfile? profile;
  final ComparisonAxis axis;
  final int ageDays;
  final int ageWeeks;

  /// The guide-equivalent age (in weeks) actually used to look up the
  /// benchmark row, after applying [axis]'s offset.
  final int guideAgeWeeks;

  /// The official production week from the benchmark profile, or null
  /// before the guide's production range begins (or when there is no
  /// matching profile).
  final int? productionWeek;

  const ProductionWeekResult({
    required this.profile,
    required this.axis,
    required this.ageDays,
    required this.ageWeeks,
    required this.guideAgeWeeks,
    required this.productionWeek,
  });

  /// True when the flock has not yet reached the guide's production range
  /// on this axis. The flock should be displayed as pre-production.
  bool get isPreProduction => productionWeek == null;
}

/// Both comparison axes offered for a flock, per design section 3.1. The
/// official axis is always present; [milestoneAligned] is only populated
/// when the flock's recorded 5%-production milestone differs from the
/// guide's official 5%-production age by more than
/// [BreederFlockLifecycleService.axisToleranceWeeks].
class ComparisonAxisOffer {
  final BreederBenchmarkProfile? profile;
  final ProductionWeekResult official;
  final ProductionWeekResult? milestoneAligned;

  const ComparisonAxisOffer({
    required this.profile,
    required this.official,
    this.milestoneAligned,
  });

  bool get hasMilestoneAlignedAxis => milestoneAligned != null;
}

class BreederFlockLifecycleService {
  BreederFlockLifecycleService({
    BreederBenchmarkRepository? benchmarkRepository,
    BreederFlockMilestoneRepository? milestoneRepository,
  }) : benchmarkRepository = benchmarkRepository ?? BreederBenchmarkRepository(),
       milestoneRepository = milestoneRepository ?? BreederFlockMilestoneRepository();

  final BreederBenchmarkRepository benchmarkRepository;
  final BreederFlockMilestoneRepository milestoneRepository;

  /// The milestone-aligned axis is only offered once the flock's recorded
  /// 5%-production milestone differs from the guide's official age for it
  /// by strictly more than this many weeks (design section 3.1).
  static const int axisToleranceWeeks = 1;

  /// Total age from `flocks.entryDate`. Delegates entirely to
  /// `HatchDateUtils` — this is the only place in the feature allowed to
  /// call it, so every screen and later ticket goes through here instead of
  /// re-deriving age.
  FlockAgeSummary ageSummary(FlockModel flock, {DateTime? now}) {
    return FlockAgeSummary(
      ageDays: HatchDateUtils.flockAgeDays(flock.entryDate, now: now),
      ageWeeks: HatchDateUtils.flockAgeWeeks(flock.entryDate, now: now),
    );
  }

  /// The flock's official production week on the default (age-based) axis.
  /// Before the guide's production range begins, [ProductionWeekResult
  /// .productionWeek] is null and the flock reads as pre-production.
  Future<ProductionWeekResult> officialProductionWeek(
    FlockModel flock, {
    DateTime? now,
  }) async {
    return _productionWeekOnAxis(
      flock,
      const ComparisonAxis.official(),
      now: now,
    );
  }

  /// Whether the flock has entered the benchmark profile's official
  /// production range on the default (age-based) axis
  /// (breeder-flock-performance ticket 10, design doc section 5.1: "the
  /// egg section appears only when the benchmark profile says the flock
  /// has entered production"). Delegates entirely to
  /// [officialProductionWeek] — the daily report entry/review screens call
  /// this rather than re-deriving "in production" from age or milestones
  /// themselves.
  Future<bool> hasEnteredProductionRange(FlockModel flock, {DateTime? now}) async {
    final result = await officialProductionWeek(flock, now: now);
    return !result.isPreProduction;
  }

  /// Both comparison axes for the flock (design section 3.1): the official
  /// age-based axis always, plus a milestone-aligned axis when the flock's
  /// recorded 5%-production milestone differs from the guide's official age
  /// for it by more than [axisToleranceWeeks]. The milestone axis is never
  /// a silent replacement for the official one — both are returned side by
  /// side.
  Future<ComparisonAxisOffer> comparisonAxes(
    FlockModel flock, {
    DateTime? now,
  }) async {
    final official = await _productionWeekOnAxis(
      flock,
      const ComparisonAxis.official(),
      now: now,
    );

    final profile = official.profile;
    if (profile == null) {
      return ComparisonAxisOffer(profile: null, official: official);
    }

    final offsetWeeks = await _fivePercentOffsetWeeks(flock, profile);
    if (offsetWeeks == null || offsetWeeks.abs() <= axisToleranceWeeks) {
      return ComparisonAxisOffer(profile: profile, official: official);
    }

    final milestoneAxis = ComparisonAxis.milestoneAligned(offsetWeeks);
    final milestoneAligned = await _productionWeekOnAxis(
      flock,
      milestoneAxis,
      now: now,
    );

    return ComparisonAxisOffer(
      profile: profile,
      official: official,
      milestoneAligned: milestoneAligned,
    );
  }

  /// The flock's recorded 5%-production milestone, if any has been logged.
  Future<BreederFlockMilestone?> fivePercentMilestone(String flockId) {
    return milestoneRepository.getByType(
      flockId,
      BreederFlockMilestoneType.fivePercentProduction,
    );
  }

  /// All recorded milestones for the flock, oldest first.
  Future<List<BreederFlockMilestone>> milestonesForFlock(String flockId) {
    return milestoneRepository.getForFlock(flockId);
  }

  /// Records or corrects a dated operational milestone for the flock.
  /// [eventType] must be one of [BreederFlockMilestoneType.all].
  Future<BreederFlockMilestone> recordMilestone({
    required String flockId,
    required String eventType,
    required DateTime eventDate,
    String? notes,
  }) {
    return milestoneRepository.recordMilestone(
      flockId: flockId,
      eventType: eventType,
      eventDate: eventDate,
      notes: notes,
    );
  }

  Future<ProductionWeekResult> _productionWeekOnAxis(
    FlockModel flock,
    ComparisonAxis axis, {
    DateTime? now,
  }) async {
    final age = ageSummary(flock, now: now);
    final profile = await benchmarkRepository.getActiveProfileForBreed(
      flock.breed,
    );
    if (profile == null) {
      return ProductionWeekResult(
        profile: null,
        axis: axis,
        ageDays: age.ageDays,
        ageWeeks: age.ageWeeks,
        guideAgeWeeks: axis.guideAgeWeeksFor(age.ageWeeks),
        productionWeek: null,
      );
    }

    final guideAgeWeeks = axis.guideAgeWeeksFor(age.ageWeeks);
    final productionWeek = guideAgeWeeks < 0
        ? null
        : await benchmarkRepository.getOfficialProductionWeek(
            profileId: profile.id,
            ageWeek: guideAgeWeeks,
          );

    return ProductionWeekResult(
      profile: profile,
      axis: axis,
      ageDays: age.ageDays,
      ageWeeks: age.ageWeeks,
      guideAgeWeeks: guideAgeWeeks,
      productionWeek: productionWeek,
    );
  }

  /// `recordedFivePercentAgeWeeks - officialFivePercentAgeWeeks`: the
  /// flock's real age (in weeks) when its 5%-production milestone was
  /// recorded, minus the guide's own official age for that milestone.
  /// Null when there is no recorded milestone or the profile has no
  /// official production-start age to compare against.
  Future<int?> _fivePercentOffsetWeeks(
    FlockModel flock,
    BreederBenchmarkProfile profile,
  ) async {
    final milestone = await fivePercentMilestone(flock.id);
    if (milestone == null) return null;

    final officialAgeWeeks = await benchmarkRepository
        .getOfficialProductionStartAgeWeek(profile.id);
    if (officialAgeWeeks == null) return null;

    final recordedAgeWeeks = HatchDateUtils.flockAgeWeeks(
      flock.entryDate,
      now: milestone.eventDate,
    );
    return recordedAgeWeeks - officialAgeWeeks;
  }
}
