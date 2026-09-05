/// Single source of truth for the breeder daily-report egg-grade partition
/// and egg-production arithmetic (breeder-flock-performance ticket 10,
/// design doc section 5, 7, 7.1, 7.2, and 12: "all formulas live in one
/// tested domain service ... reused by entry, reports, alerts, and
/// export"). Entry screens, the consolidated review, alerts, and export
/// must all call into this service rather than re-deriving total eggs,
/// grade percentages, production percent, or grade-priority resolution
/// themselves.
///
/// Bird movements and feed are `BreederBirdLedgerService`'s domain; this
/// service only ever reads a report's already-recorded closing balances
/// from it (or from movements passed in by the caller) — it never computes
/// or persists a movement itself.
library;

import 'package:uuid/uuid.dart';

import '../../core/utils/calculation_utils.dart';
import '../../data/models/breeder_bird_movement_model.dart';
import '../../data/models/breeder_egg_grade_definition_model.dart';
import '../../data/models/breeder_egg_production_entry_model.dart';
import '../../data/repositories/breeder_egg_grade_definition_repository.dart';
import '../../data/repositories/breeder_egg_production_entry_repository.dart';

/// Thrown when an egg-production entry would violate a domain rule: a
/// negative count, a non-positive egg weight, or (via
/// [BreederEggProductionService.resolveHighestPriorityGrade]) an empty
/// candidate list or a duplicate priority in the active grade set.
class BreederEggProductionValidationError extends Error {
  final String message;
  BreederEggProductionValidationError(this.message);

  @override
  String toString() => 'BreederEggProductionValidationError: $message';
}

class BreederEggProductionService {
  BreederEggProductionService({
    BreederEggGradeDefinitionRepository? gradeRepository,
    BreederEggProductionEntryRepository? entryRepository,
  }) : gradeRepository = gradeRepository ?? BreederEggGradeDefinitionRepository(),
       entryRepository = entryRepository ?? BreederEggProductionEntryRepository();

  final BreederEggGradeDefinitionRepository gradeRepository;
  final BreederEggProductionEntryRepository entryRepository;

  static const Uuid _uuid = Uuid();
  String _generateId() => _uuid.v4();

  // ---------------------------------------------------------------------
  // Grade priority resolution (design doc section 5.2 and 12): "an egg is
  // counted under the highest-priority grade it matches". Lower
  // `priority` numbers are higher priority (see
  // `BreederEggGradeDefinition`'s doc comment and the seeded order in
  // `breeder_egg_grade_definition_seeds.dart`).
  // ---------------------------------------------------------------------

  /// Given every grade an egg's physical description matches
  /// ([matchingGrades] — e.g. both "cracked" and "double yolk" for a
  /// cracked double-yolk egg), returns the single grade it is actually
  /// counted under: the one with the lowest [BreederEggGradeDefinition
  /// .priority] number. Throws [BreederEggProductionValidationError] if
  /// [matchingGrades] is empty — every laid egg must match at least one
  /// grade (the partition is exhaustive), so an empty match list is a
  /// caller bug, not a legitimate "no grade" outcome.
  static BreederEggGradeDefinition resolveHighestPriorityGrade(
    List<BreederEggGradeDefinition> matchingGrades,
  ) {
    if (matchingGrades.isEmpty) {
      throw BreederEggProductionValidationError(
        'An egg must match at least one grade description',
      );
    }
    return matchingGrades.reduce(
      (a, b) => a.priority <= b.priority ? a : b,
    );
  }

  /// Validates that [grades] carries no duplicate [BreederEggGradeDefinition
  /// .priority] among its active members (design doc section 12 invariant:
  /// "unique egg-grade priority within the active grade set"). The database
  /// also enforces this via a partial unique index
  /// (`idx_breeder_egg_grade_definitions_active_priority`); this is a
  /// defensive, in-memory check for callers (e.g. a future admin screen)
  /// that build a candidate grade set before persisting it.
  static void validateUniqueActivePriorities(
    List<BreederEggGradeDefinition> grades,
  ) {
    final seen = <int>{};
    for (final grade in grades) {
      if (!grade.isActive) continue;
      if (!seen.add(grade.priority)) {
        throw BreederEggProductionValidationError(
          'Duplicate priority ${grade.priority} among active egg grades',
        );
      }
    }
  }

  // ---------------------------------------------------------------------
  // Pure arithmetic (design doc section 7): totals and percentages. Static
  // and side-effect free so entry, review, alerts, and export can all call
  // the exact same formula.
  // ---------------------------------------------------------------------

  /// `total eggs = sum of all egg-grade counts` (design section 7) — never
  /// independently typed, always derived from [counts]. Rejects a negative
  /// count; the database CHECK constraint on `breeder_egg_production_entries
  /// .count` is the second line of defense.
  static int totalEggs(Iterable<int> counts) {
    var total = 0;
    for (final count in counts) {
      if (count < 0) {
        throw BreederEggProductionValidationError(
          'An egg-grade count cannot be negative (was $count)',
        );
      }
      total += count;
    }
    return total;
  }

  /// `egg-grade percent = grade count / total eggs * 100` (design section
  /// 7 and 7.1: "egg-grade percent divides by calculated total eggs for the
  /// same scope"). Returns `null` (never `0`, never an error) when
  /// [totalEggsForScope] is zero, negative, or missing (design section
  /// 7.2) — reuses `CalculationUtils.percentOf` rather than inventing new
  /// rounding/percentage behaviour.
  static double? eggGradePercent({
    required int gradeCount,
    required int? totalEggsForScope,
  }) {
    return CalculationUtils.percentOf(gradeCount, totalEggsForScope);
  }

  /// `daily production percent = total eggs / closing live females * 100`
  /// (design section 7), using the house-scope total eggs and the closing
  /// live females **in production houses** as the denominator (design
  /// section 7.1) — isolation eggs and isolation females are both excluded,
  /// so numerator and denominator stay scoped together. [totalEggsHouseScope]
  /// and [closingLiveFemalesHouseScope] must already exclude isolation;
  /// this method does not itself distinguish house from isolation rows.
  ///
  /// Returns `null` (never `0`, never an error) when the denominator is
  /// zero, negative, or missing (design section 7.2).
  static double? dailyProductionPercent({
    required int totalEggsHouseScope,
    required int? closingLiveFemalesHouseScope,
  }) {
    return CalculationUtils.percentOf(
      totalEggsHouseScope,
      closingLiveFemalesHouseScope,
    );
  }

  /// The isolation counterpart of [dailyProductionPercent] (design section
  /// 7.1: "Isolation production, when recorded, is reported separately and
  /// never folded into the house figure"). Divides isolation eggs by
  /// isolation closing females — never mixed with the house-scope figures.
  static double? isolationProductionPercent({
    required int totalEggsIsolationScope,
    required int? closingLiveFemalesIsolationScope,
  }) {
    return CalculationUtils.percentOf(
      totalEggsIsolationScope,
      closingLiveFemalesIsolationScope,
    );
  }

  /// Sums the closing female balance across every **house** movement
  /// (never isolation) for a report — the denominator design section 7.1
  /// requires for [dailyProductionPercent]. Matches ticket 09's approach
  /// for feed: this is the report's own recorded closing balance, not a
  /// backward-looking ledger lookup (`BreederBirdLedgerService.houseBalance`
  /// answers "as of some date", not "on this report").
  static int closingFemalesHouseScope(List<BreederBirdMovement> movements) {
    var total = 0;
    for (final movement in movements) {
      if (movement.isHouseMovement && movement.isFemale) {
        total += movement.closing;
      }
    }
    return total;
  }

  /// The isolation counterpart of [closingFemalesHouseScope].
  static int closingFemalesIsolationScope(
    List<BreederBirdMovement> movements,
  ) {
    var total = 0;
    for (final movement in movements) {
      if (movement.isIsolationMovement && movement.isFemale) {
        total += movement.closing;
      }
    }
    return total;
  }

  // ---------------------------------------------------------------------
  // Entry persistence.
  // ---------------------------------------------------------------------

  /// Records one location/grade egg count for a Draft report. The location
  /// is either [houseId] or [isolationAreaId] — exactly one must be given.
  Future<BreederEggProductionEntry> recordGradeCount({
    required String reportId,
    String? houseId,
    String? isolationAreaId,
    required String gradeId,
    required int count,
    String? id,
  }) async {
    _requireExactlyOneLocation(houseId, isolationAreaId);
    if (count < 0) {
      throw BreederEggProductionValidationError(
        'count cannot be negative (was $count)',
      );
    }
    final existing = houseId != null
        ? await entryRepository.getByReportHouseGrade(reportId, houseId, gradeId)
        : await entryRepository.getByReportIsolationAreaGrade(
            reportId,
            isolationAreaId!,
            gradeId,
          );
    final entry = BreederEggProductionEntry(
      id: id ?? existing?.id ?? _generateId(),
      reportId: reportId,
      houseId: houseId,
      isolationAreaId: isolationAreaId,
      gradeId: gradeId,
      count: count,
      eggWeightGrams: existing?.eggWeightGrams,
    );
    return entryRepository.upsert(entry);
  }

  /// Records the location-level egg weight (grams — design section 5.2.1)
  /// for every grade row already recorded against [houseId]/[isolationAreaId]
  /// on [reportId], keeping it identical across every one of that
  /// location's grade rows (see `BreederEggProductionEntry`'s doc comment
  /// for why it is duplicated rather than held in a separate table). Rows
  /// that do not exist yet for this location are unaffected — call
  /// [recordGradeCount] first (or [initializeEntriesForLocation]) so every
  /// active grade has a row to carry the weight on.
  Future<void> recordEggWeight({
    required String reportId,
    String? houseId,
    String? isolationAreaId,
    required double eggWeightGrams,
  }) async {
    _requireExactlyOneLocation(houseId, isolationAreaId);
    if (eggWeightGrams <= 0) {
      throw BreederEggProductionValidationError(
        'eggWeightGrams must be positive (was $eggWeightGrams)',
      );
    }
    final entries = await entryRepository.getForReport(reportId);
    for (final entry in entries) {
      final sameLocation = houseId != null
          ? entry.houseId == houseId
          : entry.isolationAreaId == isolationAreaId;
      if (!sameLocation) continue;
      await entryRepository.upsert(
        entry.copyWith(eggWeightGrams: eggWeightGrams),
      );
    }
  }

  /// Ensures a zero-count row exists for every active grade at
  /// [houseId]/[isolationAreaId] on [reportId] — the entry screen's
  /// counterpart of `BreederBirdLedgerService`'s lazy movement
  /// initialization, so [recordEggWeight] always has rows to attach the
  /// weight to even before any grade count has been typed.
  Future<List<BreederEggProductionEntry>> initializeEntriesForLocation({
    required String reportId,
    String? houseId,
    String? isolationAreaId,
  }) async {
    _requireExactlyOneLocation(houseId, isolationAreaId);
    final grades = await gradeRepository.listActiveGrades();
    final result = <BreederEggProductionEntry>[];
    for (final grade in grades) {
      final existing = houseId != null
          ? await entryRepository.getByReportHouseGrade(
              reportId,
              houseId,
              grade.id,
            )
          : await entryRepository.getByReportIsolationAreaGrade(
              reportId,
              isolationAreaId!,
              grade.id,
            );
      if (existing != null) {
        result.add(existing);
        continue;
      }
      final created = await entryRepository.upsert(
        BreederEggProductionEntry(
          id: _generateId(),
          reportId: reportId,
          houseId: houseId,
          isolationAreaId: isolationAreaId,
          gradeId: grade.id,
          count: 0,
        ),
      );
      result.add(created);
    }
    return result;
  }

  static void _requireExactlyOneLocation(
    String? houseId,
    String? isolationAreaId,
  ) {
    final hasHouse = houseId != null && houseId.isNotEmpty;
    final hasIsolation = isolationAreaId != null && isolationAreaId.isNotEmpty;
    if (hasHouse == hasIsolation) {
      throw BreederEggProductionValidationError(
        'An egg production entry must name exactly one location: a house '
        'or an isolation area (houseId=$houseId, '
        'isolationAreaId=$isolationAreaId)',
      );
    }
  }
}
