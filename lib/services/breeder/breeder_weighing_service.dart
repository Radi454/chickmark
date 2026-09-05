/// Derived-figure and benchmark-comparison arithmetic for periodic weighing
/// sessions (breeder-flock-performance ticket 13, design doc section 5.1
/// and 9). Weighing is a workflow separate from the daily report; this
/// service is the single place that turns a session's individual
/// `breeder_weighing_samples` into mean weight, uniformity, and
/// coefficient of variation, and compares the mean against the official
/// benchmark for the flock's breed/sex/age.
///
/// ## Reused shared calculation utilities
///
/// Mean weight, standard deviation, and coefficient of variation all reuse
/// `CalculationUtils` (`average`, `stdDev`, `roundTo`) rather than a second
/// statistical convention, per design section 9: "Standard deviation and
/// coefficient of variation reuse the existing shared calculation
/// utilities so breeder figures match the rest of the app." Sample
/// (n - 1) standard deviation is used, matching
/// `docs/FORMULA_REGISTRY.md`'s "CV and Standard Deviation" convention
/// ("Egg weights, chick weights, EST/CVT, and Govee Temp/RH all use sample
/// standard deviation by default").
///
/// **Deliberate deviation from `CalculationUtils.cvPercent`:** that helper
/// returns `0.0` for fewer than two values or a zero mean, which conflicts
/// with this feature's blank-not-zero convention (design section 7.2: "A
/// zero, negative, or missing denominator yields a blank derived value,
/// never `0` and never an error"). Rather than silently changing
/// `cvPercent`'s existing behaviour — used elsewhere in the app — this
/// service computes CV directly from `CalculationUtils.stdDev` /
/// `CalculationUtils.average` and returns `null` in exactly those cases.
/// The underlying formula (`sample stdDev / mean * 100`) is identical to
/// `cvPercent`'s; only the empty/degenerate-input fallback differs. This is
/// flagged here, in `docs/FORMULA_REGISTRY.md`, and in the ticket 13
/// completion report rather than changed unilaterally in shared code used
/// by other features.
///
/// ## Uniformity definition
///
/// The design doc does not fix a uniformity definition (section 9 leaves
/// it open). This service uses the convention already established
/// elsewhere in the app for weight uniformity (chick weight, egg weight,
/// station adapter aggregation): the percentage of birds within
/// +/-[weightUniformityWindow] of the *sample* mean weight — see
/// `CalculationUtils.uniformityPercent` call sites in
/// `panel_aggregate_deriver.dart` and `station_adapter.dart`. The window is
/// a named constant, not a magic number, so it can be changed in one place.
library;

import '../../core/utils/calculation_utils.dart';
import '../../data/models/breeder_benchmark_models.dart';
import '../../data/models/breeder_weighing_session_model.dart';
import '../../data/models/flock_model.dart';
import '../../data/repositories/breeder_benchmark_repository.dart';
import '../../data/repositories/breeder_weighing_sample_repository.dart';
import '../../data/repositories/breeder_weighing_session_repository.dart';
import 'breeder_flock_lifecycle_service.dart';

/// The official metric code for body weight in
/// `breeder_metric_definitions`/`breeder_benchmark_values`, as loaded from
/// `assets/benchmarks/metric_definitions.json` (breeder-flock-performance
/// ticket 03).
const String kBreederBodyWeightMetricCode = 'body_weight_g';

/// The derived figures for one weighing session, computed from its
/// individual sample weights.
class BreederWeighingDerivedFigures {
  /// Number of samples the figures were computed from. `0` for a
  /// summary-only session with no recorded samples.
  final int sampleCount;

  /// Arithmetic mean of the sample weights, rounded to one decimal place.
  /// Null when there are no samples.
  final double? meanWeightG;

  /// Percentage of samples within +/-[BreederWeighingService
  /// .weightUniformityWindow] of [meanWeightG]. Null when there are no
  /// samples (blank-not-zero — an empty sample set has no uniformity to
  /// report, not `0%`).
  final double? uniformityPct;

  /// Sample coefficient of variation (`sample stdDev / mean * 100`),
  /// rounded to one decimal place. Null when there are fewer than two
  /// samples or the mean is zero — see the class-level doc comment on the
  /// deliberate deviation from `CalculationUtils.cvPercent`'s `0.0`
  /// fallback.
  final double? cvPct;

  const BreederWeighingDerivedFigures({
    required this.sampleCount,
    required this.meanWeightG,
    required this.uniformityPct,
    required this.cvPct,
  });

  static const empty = BreederWeighingDerivedFigures(
    sampleCount: 0,
    meanWeightG: null,
    uniformityPct: null,
    cvPct: null,
  );
}

/// The benchmark comparison recorded for a session: the official target
/// weight for the flock's breed/sex/age, plus the exact profile version and
/// comparison axis that produced it (design section 9 and 3.1).
class BreederWeighingComparison {
  final BreederBenchmarkProfile? profile;
  final ComparisonAxis? axis;
  final double? targetWeightG;

  const BreederWeighingComparison({this.profile, this.axis, this.targetWeightG});

  static const none = BreederWeighingComparison();

  /// True when the guide publishes no body-weight target for this
  /// flock/sex/age at all (as opposed to there being no active profile for
  /// the breed). Ross 308 publishes no uniformity or CV target (design
  /// section 9 / ticket 03), which this class does not model since
  /// uniformity/CV are always shown without a target rather than compared
  /// against one — see `BreederWeighingSession` doc comment.
  bool get hasTarget => targetWeightG != null;
}

class BreederWeighingService {
  BreederWeighingService({
    BreederWeighingSessionRepository? sessionRepository,
    BreederWeighingSampleRepository? sampleRepository,
    BreederBenchmarkRepository? benchmarkRepository,
    BreederFlockLifecycleService? lifecycleService,
  }) : sessionRepository = sessionRepository ?? BreederWeighingSessionRepository(),
       sampleRepository = sampleRepository ?? BreederWeighingSampleRepository(),
       benchmarkRepository = benchmarkRepository ?? BreederBenchmarkRepository(),
       lifecycleService = lifecycleService ?? BreederFlockLifecycleService();

  final BreederWeighingSessionRepository sessionRepository;
  final BreederWeighingSampleRepository sampleRepository;
  final BreederBenchmarkRepository benchmarkRepository;
  final BreederFlockLifecycleService lifecycleService;

  /// Uniformity window: a bird counts as "uniform" when its weight falls
  /// within this fraction of the sample mean, in either direction (i.e.
  /// [mean * (1 - weightUniformityWindow), mean * (1 + weightUniformityWindow)]).
  /// `0.10` is the conventional +/-10%-of-mean weight uniformity window
  /// already used elsewhere in the app for chick/egg weight uniformity
  /// (`panel_aggregate_deriver.dart`, `station_adapter.dart`'s
  /// `_uniformity10`) — reused here so breeder uniformity means the same
  /// thing as uniformity everywhere else in ChickMark, per design section
  /// 9's instruction to reuse shared calculation conventions. Named so the
  /// window can be changed in one place rather than hunted through call
  /// sites.
  static const double weightUniformityWindow = 0.10;

  /// Derives mean weight, uniformity, and CV from [weights]. Pure
  /// function — does not read or write the database.
  BreederWeighingDerivedFigures deriveFigures(List<double> weights) {
    if (weights.isEmpty) return BreederWeighingDerivedFigures.empty;

    final mean = CalculationUtils.average(weights);
    final meanRounded = CalculationUtils.roundTo(mean);

    final uniformity = CalculationUtils.uniformityPercent(
      weights,
      mean * (1 - weightUniformityWindow),
      mean * (1 + weightUniformityWindow),
    );

    double? cv;
    if (weights.length >= 2 && mean != 0) {
      final stdDev = CalculationUtils.stdDev(weights, sample: true);
      cv = CalculationUtils.roundTo((stdDev / mean) * 100);
    }

    return BreederWeighingDerivedFigures(
      sampleCount: weights.length,
      meanWeightG: meanRounded,
      uniformityPct: uniformity,
      cvPct: cv,
    );
  }

  /// The official body-weight target for [flock]'s breed/[sex] at
  /// [sessionDate]'s age, on the flock's default (official) comparison
  /// axis, plus the exact profile and axis used.
  ///
  /// **Judgment call:** unlike the daily report's production-week lookup,
  /// this always uses [ComparisonAxis.official] rather than offering the
  /// milestone-aligned axis `BreederFlockLifecycleService.comparisonAxes`
  /// can produce. The design doc does not call for a milestone-aligned
  /// weight comparison, and body weight (unlike production week) is not
  /// keyed to the 5%-production milestone that axis exists to correct for
  /// — a session records its own real date, so there is no schedule drift
  /// to align away. `comparisonAxes` is still called (for the matched
  /// profile lookup), but its `official` result feeds every session; a
  /// future ticket that wants milestone-aligned weight comparisons can add
  /// it explicitly. Returns
  /// [BreederWeighingComparison.none] when no active benchmark profile
  /// matches the flock's breed. `targetWeightG` is null (no target, not a
  /// missing profile) when the profile has no body-weight row for that
  /// age/sex — e.g. a source that only publishes weekly rows and the
  /// session falls between them.
  Future<BreederWeighingComparison> officialWeightTarget({
    required FlockModel flock,
    required String sex,
    required DateTime sessionDate,
  }) async {
    final axesOffer = await lifecycleService.comparisonAxes(
      flock,
      now: sessionDate,
    );
    final profile = axesOffer.profile;
    if (profile == null) return BreederWeighingComparison.none;

    final axis = const ComparisonAxis.official();
    final ageWeeks = lifecycleService.ageSummary(flock, now: sessionDate).ageWeeks;
    final guideAgeWeeks = axis.guideAgeWeeksFor(ageWeeks);
    if (guideAgeWeeks < 0) {
      return BreederWeighingComparison(profile: profile, axis: axis, targetWeightG: null);
    }

    final metricDefs = await benchmarkRepository.getMetricDefinitionsById();
    final bodyWeightMetric = metricDefs.values.firstWhere(
      (m) => m.code == kBreederBodyWeightMetricCode,
      orElse: () => throw StateError(
        'No "$kBreederBodyWeightMetricCode" metric definition is loaded',
      ),
    );

    final values = await benchmarkRepository.getValuesForProfile(profile.id);
    BreederBenchmarkValue? match;
    for (final value in values) {
      if (value.metricId != bodyWeightMetric.id) continue;
      if (value.sex != sex) continue;
      if (value.ageWeek != guideAgeWeeks) continue;
      match = value;
      break;
    }

    return BreederWeighingComparison(
      profile: profile,
      axis: axis,
      targetWeightG: match?.targetValue,
    );
  }

  /// Recomputes and persists a session's derived figures and benchmark
  /// comparison from its current sample rows (or clears them, for a
  /// summary-only session with no samples). This is the only writer of
  /// `breeder_weighing_sessions.derived*`/`comparison*` columns.
  Future<BreederWeighingSession> computeAndSaveDerived({
    required BreederWeighingSession session,
    required FlockModel flock,
  }) async {
    final samples = await sampleRepository.getForSession(session.id);
    final weights = samples.map((s) => s.weightGrams).toList();
    final figures = deriveFigures(weights);
    final comparison = await officialWeightTarget(
      flock: flock,
      sex: session.sex,
      sessionDate: session.sessionDate,
    );

    final updated = session.copyWith(
      derivedMeanWeightG: figures.meanWeightG,
      derivedUniformityPct: figures.uniformityPct,
      derivedCvPct: figures.cvPct,
      clearDerived: figures.meanWeightG == null,
      comparisonProfileId: comparison.profile?.id,
      comparisonProfileGuideVersion: comparison.profile?.guideVersion,
      comparisonAxisKind: comparison.axis == null
          ? null
          : (comparison.axis!.kind == ComparisonAxisKind.official
                ? BreederWeighingComparisonAxisKind.official
                : BreederWeighingComparisonAxisKind.milestoneAligned),
      comparisonAxisOffsetWeeks: comparison.axis?.offsetWeeks,
      comparisonTargetWeightG: comparison.targetWeightG,
      clearComparison: comparison.profile == null,
    );

    await sessionRepository.update(updated);
    return updated;
  }

  /// Creates a session, optionally records its individual sample weights,
  /// and computes+saves derived figures and the benchmark comparison in one
  /// call. [weights] may be empty for a summary-only session.
  Future<BreederWeighingSession> createSession({
    required FlockModel flock,
    required String houseId,
    required DateTime sessionDate,
    required String sex,
    required String method,
    required int sampleSize,
    String? notes,
    List<double> weights = const [],
  }) async {
    if (sampleSize <= 0) {
      throw ArgumentError.value(sampleSize, 'sampleSize', 'Must be positive');
    }
    if (sex != BreederWeighingSessionSex.female && sex != BreederWeighingSessionSex.male) {
      throw ArgumentError.value(sex, 'sex', 'Must be female or male');
    }
    for (final weight in weights) {
      if (weight < 0) {
        throw ArgumentError.value(weight, 'weights', 'A bird weight cannot be negative');
      }
    }

    final session = await sessionRepository.create(
      flockId: flock.id,
      houseId: houseId,
      sessionDate: sessionDate,
      sex: sex,
      method: method,
      sampleSize: sampleSize,
      notes: notes,
    );

    if (weights.isNotEmpty) {
      await sampleRepository.replaceForSession(
        sessionId: session.id,
        weights: weights,
      );
    }

    return computeAndSaveDerived(session: session, flock: flock);
  }

  /// Replaces a session's sample weights and recomputes+saves derived
  /// figures and the comparison. Passing an empty [weights] list turns the
  /// session into a summary-only one (derived figures cleared).
  Future<BreederWeighingSession> updateSamples({
    required BreederWeighingSession session,
    required FlockModel flock,
    required List<double> weights,
  }) async {
    for (final weight in weights) {
      if (weight < 0) {
        throw ArgumentError.value(weight, 'weights', 'A bird weight cannot be negative');
      }
    }
    if (weights.isEmpty) {
      await sampleRepository.deleteForSession(session.id);
    } else {
      await sampleRepository.replaceForSession(
        sessionId: session.id,
        weights: weights,
      );
    }
    return computeAndSaveDerived(session: session, flock: flock);
  }
}
