/// Single source of truth for the breeder daily-report bird-movement and
/// feed arithmetic and lifecycle (breeder-flock-performance ticket 07,
/// extended by ticket 09 for feed; design doc section 5, 6, and 7: "all
/// formulas live in one tested domain service ... reused by entry, reports,
/// alerts, and export"). Entry screens, the consolidated review, alerts, and
/// export must all call into this service rather than re-deriving closing
/// balances, transfer balancing, feed-per-bird, or approval-role checks
/// themselves.
///
/// Eggs are ticket 10's domain; egg-inventory-balance arithmetic is ticket
/// 11's (`BreederEggInventoryService`) — this service only calls into it to
/// gate approval (see [approve]), never to compute a balance itself.
library;

import 'package:uuid/uuid.dart';

import '../../core/utils/calculation_utils.dart';
import '../../data/models/breeder_bird_movement_model.dart';
import '../../data/models/breeder_daily_report_model.dart';
import '../../data/models/breeder_feed_entry_model.dart';
import '../../data/models/poultry_hierarchy_models.dart';
import '../../data/repositories/breeder_bird_movement_repository.dart';
import '../../data/repositories/breeder_daily_report_repository.dart';
import '../../data/repositories/breeder_egg_production_entry_repository.dart';
import '../../data/repositories/breeder_feed_entry_repository.dart';
import '../../data/repositories/breeder_isolation_area_repository.dart';
import '../../data/repositories/poultry_hierarchy_repository.dart';
import 'breeder_alert_revision_hook.dart';
import 'breeder_egg_inventory_service.dart';
import 'breeder_egg_production_service.dart';
import 'breeder_report_revision_service.dart';

/// Roles permitted to approve a report (design doc section 5.3: "the
/// permitted approval roles are an enumerated, documented set rather than
/// an open string"). This client-side gate is mirrored, not merely
/// intended, in the cloud: ticket 16 added
/// `chickmark_private.app_can_approve_breeder_report()` (enumerating the
/// same two roles) and a BEFORE INSERT/UPDATE trigger on
/// `breeder_daily_reports` in
/// `supabase/migrations_unapplied/0014_breeder_customer_scope_and_approval_role.sql`
/// (not yet applied to the live project — see that file's header) that
/// rejects a transition into `approved` from an actor whose role does not
/// permit it, regardless of what this client-side check says. Keep both
/// lists identical; test/security/breeder_approval_rls_test.dart asserts
/// they match.
///
/// Judgment call: `users.role` — sourced from cloud `profiles.role` at
/// login (see `SupabaseService._buildUserFromAuth`) — previously only ever
/// stored `admin`, `auditor`, `customer`, or `personal` (see `UserModel`),
/// none of which is a production-manager role. Ticket 16 made
/// `production_manager` a real, assignable value: `profiles_role_check` now
/// allows it and the admin "User Access" screen
/// (`lib/features/admin/screens/admin_users_screen.dart`) can assign it,
/// scoped to customers the same way `auditor` is. `admin` is treated as "or
/// higher" per the ticket's wording.
class BreederApprovalRole {
  static const String productionManager = 'production_manager';
  static const String admin = 'admin';

  static const List<String> permitted = [productionManager, admin];

  static bool canApprove(String? role) {
    if (role == null) return false;
    return permitted.contains(role.toLowerCase().trim());
  }
}

/// Thrown when a movement's quantities would violate a domain rule:
/// a negative field, a negative resulting closing balance, or (via
/// [BreederBirdLedgerService.validateTransferBalance]) an internal transfer
/// that does not balance across its two legs.
class BreederLedgerValidationError extends Error {
  final String message;
  BreederLedgerValidationError(this.message);

  @override
  String toString() => 'BreederLedgerValidationError: $message';
}

/// Thrown when a report state transition is attempted out of order (e.g.
/// approving a Draft report) or by an actor whose role does not permit it.
class BreederReportStateError extends Error {
  final String message;
  BreederReportStateError(this.message);

  @override
  String toString() => 'BreederReportStateError: $message';
}

class BreederBirdLedgerService {
  BreederBirdLedgerService({
    BreederDailyReportRepository? reportRepository,
    BreederBirdMovementRepository? movementRepository,
    PoultryHierarchyRepository? houseRepository,
    BreederIsolationAreaRepository? isolationAreaRepository,
    BreederFeedEntryRepository? feedEntryRepository,
    BreederEggInventoryService? eggInventoryService,
    BreederReportRevisionService? revisionService,
    BreederEggProductionEntryRepository? eggProductionEntryRepository,
    BreederEggProductionService? eggProductionService,
  }) : reportRepository = reportRepository ?? BreederDailyReportRepository(),
       movementRepository =
           movementRepository ?? BreederBirdMovementRepository(),
       houseRepository = houseRepository ?? PoultryHierarchyRepository(),
       isolationAreaRepository =
           isolationAreaRepository ?? BreederIsolationAreaRepository(),
       feedEntryRepository = feedEntryRepository ?? BreederFeedEntryRepository(),
       eggInventoryService = eggInventoryService ?? BreederEggInventoryService(),
       revisionService =
           revisionService ??
           BreederReportRevisionService(
             onApprovedReportRevised: defaultBreederAlertRevisionHook,
           ),
       eggProductionEntryRepository =
           eggProductionEntryRepository ?? BreederEggProductionEntryRepository(),
       eggProductionService =
           eggProductionService ??
           BreederEggProductionService(
             entryRepository:
                 eggProductionEntryRepository ??
                 BreederEggProductionEntryRepository(),
           );

  final BreederDailyReportRepository reportRepository;
  final BreederBirdMovementRepository movementRepository;
  final PoultryHierarchyRepository houseRepository;

  /// Feed entries (breeder-flock-performance ticket 09). See
  /// [recordFeedEntry] and [feedGramsPerBird] below.
  final BreederFeedEntryRepository feedEntryRepository;

  /// Isolation areas (breeder-flock-performance ticket 08). A flock can have
  /// several named isolation areas; birds moved there via an internal
  /// transfer leave the house total and enter the isolation total without
  /// changing the flock's total physically-live count (design doc section
  /// 6). See [isolationAreaBalance]/[isolationFlockBalance]/
  /// [flockTotalBalance] below.
  final BreederIsolationAreaRepository isolationAreaRepository;

  /// Egg-inventory balance validation (breeder-flock-performance ticket 11,
  /// design doc section 14: "Inventory equations must balance before
  /// approval"). [approve] calls
  /// [BreederEggInventoryService.validateBalancesForApproval] through this
  /// rather than a second, parallel approval mechanism.
  final BreederEggInventoryService eggInventoryService;

  /// Post-approval correction audit trail (breeder-flock-performance
  /// ticket 12, design doc section 5.3 and 12). See [correctHeader] below —
  /// the one correction path this ticket wires up — and
  /// `BreederReportRevisionService`'s own doc comment for why the diff
  /// -and-log engine lives there rather than duplicated per corrected
  /// table.
  final BreederReportRevisionService revisionService;

  /// Correcting an egg-production grade count (breeder-flock-performance
  /// ticket 12, extending ticket 10's persistence and ticket 11's ledger)
  /// needs both a direct repository handle — to look up the specific
  /// already-recorded row a correction addresses by id, which
  /// [BreederEggProductionService]'s own (report, location, grade)-keyed
  /// API does not offer — and the service itself, so the actual write goes
  /// through the same negative-count guard every other production write
  /// uses. See [correctEggProductionEntry] below.
  final BreederEggProductionEntryRepository eggProductionEntryRepository;
  final BreederEggProductionService eggProductionService;

  // ---------------------------------------------------------------------
  // Pure arithmetic (design doc section 7): `closing birds = opening birds
  // - permanent removals +/- transfers`. Static and side-effect free so
  // entry, review, alerts, and export can all call the exact same formula.
  // ---------------------------------------------------------------------

  /// Computes the closing balance for one house/sex movement row. Rejects
  /// any negative input field and rejects a resulting negative closing
  /// balance — both are domain errors, never clamped to zero silently.
  static int closingBirds({
    required int opening,
    int mortality = 0,
    int culls = 0,
    int sale = 0,
    int kitchenRemoval = 0,
    int euthanasia = 0,
    int transferIn = 0,
    int transferOut = 0,
  }) {
    _requireNonNegative({
      'opening': opening,
      'mortality': mortality,
      'culls': culls,
      'sale': sale,
      'kitchenRemoval': kitchenRemoval,
      'euthanasia': euthanasia,
      'transferIn': transferIn,
      'transferOut': transferOut,
    });
    final closing =
        opening -
        mortality -
        culls -
        sale -
        kitchenRemoval -
        euthanasia +
        transferIn -
        transferOut;
    if (closing < 0) {
      throw BreederLedgerValidationError(
        'Movement produces a negative closing balance ($closing)',
      );
    }
    return closing;
  }

  static void _requireNonNegative(Map<String, int> fields) {
    for (final entry in fields.entries) {
      if (entry.value < 0) {
        throw BreederLedgerValidationError(
          '${entry.key} cannot be negative (was ${entry.value})',
        );
      }
    }
  }

  /// Internal transfers must balance across their two legs: every bird
  /// moved out of one house on this report must be accounted for as a
  /// transfer into another house on the same report, per sex (design doc
  /// section 5 validation rule and section 6). Throws
  /// [BreederLedgerValidationError] when a sex's total transferIn does not
  /// equal its total transferOut across [movements].
  static void validateTransferBalance(List<BreederBirdMovement> movements) {
    final bySex = <String, List<BreederBirdMovement>>{};
    for (final movement in movements) {
      bySex.putIfAbsent(movement.sex, () => []).add(movement);
    }
    for (final entry in bySex.entries) {
      final totalIn = entry.value.fold<int>(0, (a, m) => a + m.transferIn);
      final totalOut = entry.value.fold<int>(0, (a, m) => a + m.transferOut);
      if (totalIn != totalOut) {
        throw BreederLedgerValidationError(
          'Internal transfers do not balance for ${entry.key}: '
          'in=$totalIn out=$totalOut',
        );
      }
    }
  }

  // ---------------------------------------------------------------------
  // Opening balance derivation (design doc section 6): "opening balance
  // derives from the previous ledger state (or the house opening counts on
  // the first day), not from free typing."
  // ---------------------------------------------------------------------

  Future<int> openingBalanceFor({
    required String flockId,
    required String houseId,
    required String sex,
    required DateTime reportDate,
  }) async {
    final previous = await movementRepository.previousClosing(
      flockId: flockId,
      houseId: houseId,
      sex: sex,
      beforeDate: reportDate,
    );
    if (previous != null) return previous;

    final houses = await houseRepository.listHouses(
      flockId,
      activeOnly: false,
    );
    HouseModel? house;
    for (final candidate in houses) {
      if (candidate.id == houseId) {
        house = candidate;
        break;
      }
    }
    if (house == null) return 0;
    return sex == BreederBirdMovementSex.female
        ? house.openingFemales
        : house.openingMales;
  }

  /// The isolation-area counterpart of [openingBalanceFor]. An isolation
  /// area has no opening-count field of its own — birds only ever arrive
  /// there via an internal transfer from a house — so with no prior
  /// movement recorded the opening balance is simply 0, never a fallback
  /// onto some other count (design doc section 6).
  Future<int> isolationOpeningBalanceFor({
    required String flockId,
    required String isolationAreaId,
    required String sex,
    required DateTime reportDate,
  }) async {
    final previous = await movementRepository.previousClosingForIsolationArea(
      flockId: flockId,
      isolationAreaId: isolationAreaId,
      sex: sex,
      beforeDate: reportDate,
    );
    return previous ?? 0;
  }

  // ---------------------------------------------------------------------
  // Live balances (design doc section 6): females and males, separately,
  // at house and flock level, derived from movements plus house opening
  // counts. Never directly editable.
  // ---------------------------------------------------------------------

  /// The latest recorded closing balance for one house/sex, as of the most
  /// recent report on or before [asOf] (defaults to "latest available").
  /// Falls back to the house's opening count when no report has been filed
  /// yet.
  Future<int> houseBalance({
    required String flockId,
    required String houseId,
    required String sex,
    DateTime? asOf,
  }) async {
    final cutoff = asOf ?? DateTime.now().add(const Duration(days: 1));
    final previous = await movementRepository.previousClosing(
      flockId: flockId,
      houseId: houseId,
      sex: sex,
      beforeDate: cutoff,
    );
    if (previous != null) return previous;

    final houses = await houseRepository.listHouses(
      flockId,
      activeOnly: false,
    );
    for (final house in houses) {
      if (house.id == houseId) {
        return sex == BreederBirdMovementSex.female
            ? house.openingFemales
            : house.openingMales;
      }
    }
    return 0;
  }

  /// The sum of every active house's [houseBalance] for [sex] — the
  /// flock-level live balance **in production houses**. This deliberately
  /// never includes isolation birds (design doc section 7.1: "house-level
  /// denominators exclude isolation") — the only way to get a house+
  /// isolation total is to call [flockTotalBalance] explicitly.
  Future<int> flockBalance({
    required String flockId,
    required String sex,
    DateTime? asOf,
  }) async {
    final houses = await houseRepository.listHouses(flockId);
    var total = 0;
    for (final house in houses) {
      total += await houseBalance(
        flockId: flockId,
        houseId: house.id,
        sex: sex,
        asOf: asOf,
      );
    }
    return total;
  }

  /// The latest recorded closing balance for one isolation area/sex, as of
  /// the most recent report on or before [asOf]. An isolation area has no
  /// opening count of its own to fall back to, so no movement yet recorded
  /// means a balance of 0 (breeder-flock-performance ticket 08).
  Future<int> isolationAreaBalance({
    required String flockId,
    required String isolationAreaId,
    required String sex,
    DateTime? asOf,
  }) async {
    final cutoff = asOf ?? DateTime.now().add(const Duration(days: 1));
    final previous = await movementRepository.previousClosingForIsolationArea(
      flockId: flockId,
      isolationAreaId: isolationAreaId,
      sex: sex,
      beforeDate: cutoff,
    );
    return previous ?? 0;
  }

  /// The sum of every one of the flock's isolation areas' [isolationAreaBalance]
  /// for [sex] — live birds in isolation, flock-wide. Reported on its own
  /// row and never folded into [flockBalance] (design doc section 6 and
  /// 7.1).
  Future<int> isolationFlockBalance({
    required String flockId,
    required String sex,
    DateTime? asOf,
  }) async {
    final areas = await isolationAreaRepository.listAreas(flockId);
    var total = 0;
    for (final area in areas) {
      total += await isolationAreaBalance(
        flockId: flockId,
        isolationAreaId: area.id,
        sex: sex,
        asOf: asOf,
      );
    }
    return total;
  }

  /// Total physically live birds in the flock: production houses plus
  /// isolation (design doc section 6: "leaves total physically live flock
  /// birds unchanged" describes an internal house<->isolation transfer, and
  /// section 7.1 fixes which figure feeds which ratio). This is the *only*
  /// place [flockBalance] and [isolationFlockBalance] are added together —
  /// a caller that needs a house-scope-only denominator must call
  /// [flockBalance] (or [houseBalance]) directly, never this method, so the
  /// three figures are never silently merged.
  Future<int> flockTotalBalance({
    required String flockId,
    required String sex,
    DateTime? asOf,
  }) async {
    final houses = await flockBalance(flockId: flockId, sex: sex, asOf: asOf);
    final isolation = await isolationFlockBalance(
      flockId: flockId,
      sex: sex,
      asOf: asOf,
    );
    return houses + isolation;
  }

  // ---------------------------------------------------------------------
  // Movement persistence: computes closing via the pure formula above,
  // then persists through the repository (which itself enforces
  // house-belongs-to-flock via a database trigger).
  // ---------------------------------------------------------------------

  /// Records one location/sex movement row for a Draft report. The location
  /// is either [houseId] or [isolationAreaId] — exactly one must be given;
  /// passing both or neither throws [BreederLedgerValidationError]. Mortality,
  /// culls, sale, kitchen removal, and euthanasia reduce the flock total
  /// wherever they are recorded, houses and isolation alike — only a
  /// transfer moves birds between locations without changing the flock
  /// total (design doc section 6).
  ///
  /// [opening] must already be resolved (e.g. via [openingBalanceFor] or
  /// [isolationOpeningBalanceFor]) — this method does not look it up
  /// itself, so a caller correcting an already-entered row can pass the
  /// same opening balance back unchanged.
  Future<BreederBirdMovement> recordMovement({
    required String reportId,
    String? houseId,
    String? isolationAreaId,
    required String sex,
    required int opening,
    int mortality = 0,
    int culls = 0,
    int sale = 0,
    int kitchenRemoval = 0,
    int euthanasia = 0,
    int transferIn = 0,
    int transferOut = 0,
    String? id,
  }) async {
    if (!BreederBirdMovementSex.isValid(sex)) {
      throw ArgumentError.value(sex, 'sex', 'must be female or male');
    }
    _requireExactlyOneLocation(houseId, isolationAreaId);
    final closing = closingBirds(
      opening: opening,
      mortality: mortality,
      culls: culls,
      sale: sale,
      kitchenRemoval: kitchenRemoval,
      euthanasia: euthanasia,
      transferIn: transferIn,
      transferOut: transferOut,
    );
    final movement = BreederBirdMovement(
      id: id ?? _generateId(),
      reportId: reportId,
      houseId: houseId,
      isolationAreaId: isolationAreaId,
      sex: sex,
      opening: opening,
      mortality: mortality,
      culls: culls,
      sale: sale,
      kitchenRemoval: sex == BreederBirdMovementSex.female ? kitchenRemoval : 0,
      euthanasia: sex == BreederBirdMovementSex.male ? euthanasia : 0,
      transferIn: transferIn,
      transferOut: transferOut,
      closing: closing,
    );
    return movementRepository.upsert(movement);
  }

  /// A movement's location is either a house or an isolation area — exactly
  /// one, never both, never neither (breeder-flock-performance ticket 08).
  static void _requireExactlyOneLocation(
    String? houseId,
    String? isolationAreaId,
  ) {
    final hasHouse = houseId != null && houseId.isNotEmpty;
    final hasIsolation = isolationAreaId != null && isolationAreaId.isNotEmpty;
    if (hasHouse == hasIsolation) {
      throw BreederLedgerValidationError(
        'A movement must name exactly one location: a house or an '
        'isolation area (houseId=$houseId, isolationAreaId=$isolationAreaId)',
      );
    }
  }

  // House-by-house entry records each location's own transferIn/transferOut
  // fields directly through [recordMovement] — a transfer out of house A
  // and the matching transfer into isolation area B (or another house) are
  // two independent form entries on two different location screens.
  // Because they are entered independently, they can disagree (a typo, a
  // location forgotten); [validateTransferBalance] is what the consolidated
  // review and [submit] use to catch that before the report leaves Draft.
  // Note that [validateTransferBalance] groups only by sex, not by location
  // kind, so a house<->isolation transfer balances the same way a
  // house<->house transfer does.

  static const Uuid _uuid = Uuid();
  String _generateId() => _uuid.v4();

  // ---------------------------------------------------------------------
  // Header edits (design doc section 5.1/5.2: inside/outside temperature,
  // light hours, notes). Only meaningful on a Draft report — "Draft reports
  // can be edited normally" (design section 5.3); any later correction is a
  // revision, out of scope until ticket 12.
  // ---------------------------------------------------------------------

  /// Persists an edit to the report header. [lightHours], when given, must
  /// be within a plausible day (0-24); anything else is a domain error, not
  /// a silently-clamped value.
  Future<BreederDailyReport> updateHeader(
    BreederDailyReport report, {
    double? insideTemperature,
    bool clearInsideTemperature = false,
    double? outsideTemperature,
    bool clearOutsideTemperature = false,
    double? lightHours,
    bool clearLightHours = false,
    String? notes,
    bool clearNotes = false,
  }) async {
    if (!report.isDraft) {
      throw BreederReportStateError(
        'Only a Draft report header can be edited (was ${report.state})',
      );
    }
    if (lightHours != null && (lightHours < 0 || lightHours > 24)) {
      throw BreederLedgerValidationError(
        'lightHours must be between 0 and 24 (was $lightHours)',
      );
    }
    final updated = report.copyWith(
      insideTemperature: insideTemperature,
      clearInsideTemperature: clearInsideTemperature,
      outsideTemperature: outsideTemperature,
      clearOutsideTemperature: clearOutsideTemperature,
      lightHours: lightHours,
      clearLightHours: clearLightHours,
      notes: notes,
      clearNotes: clearNotes,
    );
    await reportRepository.updateHeader(updated);
    return updated;
  }

  /// Corrects the header of an already-Approved report (breeder-flock
  /// -performance ticket 12, design doc section 5.3: "Any correction after
  /// approval requires a reason and creates permanent revision history").
  /// Unlike [updateHeader] — which is for a Draft report and writes no
  /// history at all — this requires [reason] and [actorUserId], diffs the
  /// old header values against the new ones via
  /// [BreederReportRevisionService.recordCorrection], and returns the
  /// report with its `revision` counter incremented by exactly one (never
  /// per changed field). A correction that changes no field is a no-op:
  /// nothing is written, and the counter is left untouched.
  Future<BreederDailyReport> correctHeader(
    BreederDailyReport report, {
    required String reason,
    required String actorUserId,
    double? insideTemperature,
    bool clearInsideTemperature = false,
    double? outsideTemperature,
    bool clearOutsideTemperature = false,
    double? lightHours,
    bool clearLightHours = false,
    String? notes,
    bool clearNotes = false,
  }) async {
    _requireApprovedForCorrection(report);
    _requireCorrectionReasonAndActor(reason, actorUserId);
    if (lightHours != null && (lightHours < 0 || lightHours > 24)) {
      throw BreederLedgerValidationError(
        'lightHours must be between 0 and 24 (was $lightHours)',
      );
    }
    final proposed = report.copyWith(
      insideTemperature: insideTemperature,
      clearInsideTemperature: clearInsideTemperature,
      outsideTemperature: outsideTemperature,
      clearOutsideTemperature: clearOutsideTemperature,
      lightHours: lightHours,
      clearLightHours: clearLightHours,
      notes: notes,
      clearNotes: clearNotes,
    );
    final oldValues = <String, dynamic>{
      'insideTemperature': report.insideTemperature,
      'outsideTemperature': report.outsideTemperature,
      'lightHours': report.lightHours,
      'notes': report.notes,
    };
    final newValues = <String, dynamic>{
      'insideTemperature': proposed.insideTemperature,
      'outsideTemperature': proposed.outsideTemperature,
      'lightHours': proposed.lightHours,
      'notes': proposed.notes,
    };
    // Validation (state, reason, actor, lightHours range) all happens
    // above, BEFORE this write — a rejected correction must never mutate
    // the report first and throw second, or a reason-less "correction"
    // could silently land with no audit trail at all.
    await reportRepository.updateHeader(proposed);
    return revisionService.recordCorrection(
      report: proposed,
      tableName: 'breeder_daily_reports',
      rowId: report.id,
      oldValues: oldValues,
      newValues: newValues,
      reason: reason,
      actorUserId: actorUserId,
    );
  }

  /// Shared gate every post-approval correction method opens with: only an
  /// Approved report can be corrected this way (breeder-flock-performance
  /// ticket 12, design doc section 5.3).
  void _requireApprovedForCorrection(BreederDailyReport report) {
    if (!report.isApproved) {
      throw BreederReportStateError(
        'Only an Approved report can be corrected (was ${report.state}); a '
        'Draft report should be edited normally instead',
      );
    }
  }

  /// Shared reason/actor validation every post-approval correction method
  /// runs BEFORE touching any repository — so a correction rejected for a
  /// missing reason or actor never mutates data first (design doc section
  /// 5.3: "requires a reason").
  void _requireCorrectionReasonAndActor(String reason, String actorUserId) {
    BreederReportRevisionService.requireReason(reason);
    if (actorUserId.trim().isEmpty) {
      throw BreederReportCorrectionError(
        'An identified actor is required to correct an approved report',
      );
    }
  }

  /// Corrects one already-recorded bird-movement row (breeder-flock
  /// -performance ticket 12, design doc section 5.2 and 12: mortality,
  /// culls/sorts, sale, kitchen removal (female) or euthanasia (male), and
  /// transfers are precisely the paper-report figures that get corrected
  /// in practice — a transposed mortality count, a cull entered against
  /// the wrong house). [opening] is never correctable here: it is derived
  /// from the previous day's ledger state (or the house's opening counts),
  /// not a value this report itself owns, so a wrong opening balance is a
  /// data problem on an earlier report, not this one. `closing` is always
  /// recomputed from the corrected fields via [closingBirds] — never typed
  /// — and inherits that method's existing negative-closing-balance
  /// rejection.
  ///
  /// Every one of the movement's own fields that is not explicitly passed
  /// keeps its current value. After recomputing `closing`,
  /// [validateTransferBalance] is re-run across the *whole report's*
  /// movements with the correction applied, so a correction that would
  /// leave a transfer unbalanced is rejected before anything is persisted
  /// — the same invariant [submit] already enforces before a report ever
  /// reaches Approved.
  Future<BreederDailyReport> correctMovement(
    BreederDailyReport report, {
    required String movementId,
    required String reason,
    required String actorUserId,
    int? mortality,
    int? culls,
    int? sale,
    int? kitchenRemoval,
    int? euthanasia,
    int? transferIn,
    int? transferOut,
  }) async {
    _requireApprovedForCorrection(report);
    _requireCorrectionReasonAndActor(reason, actorUserId);

    final existing = await movementRepository.getById(movementId);
    if (existing == null) {
      throw BreederLedgerValidationError(
        'No bird movement found with id $movementId',
      );
    }
    if (existing.reportId != report.id) {
      throw BreederLedgerValidationError(
        'Movement $movementId does not belong to report ${report.id}',
      );
    }

    final newMortality = mortality ?? existing.mortality;
    final newCulls = culls ?? existing.culls;
    final newSale = sale ?? existing.sale;
    final newKitchenRemoval = existing.sex == BreederBirdMovementSex.female
        ? (kitchenRemoval ?? existing.kitchenRemoval)
        : 0;
    final newEuthanasia = existing.sex == BreederBirdMovementSex.male
        ? (euthanasia ?? existing.euthanasia)
        : 0;
    final newTransferIn = transferIn ?? existing.transferIn;
    final newTransferOut = transferOut ?? existing.transferOut;

    // Throws BreederLedgerValidationError for a negative field or a
    // resulting negative closing balance — nothing has been persisted yet.
    final newClosing = closingBirds(
      opening: existing.opening,
      mortality: newMortality,
      culls: newCulls,
      sale: newSale,
      kitchenRemoval: newKitchenRemoval,
      euthanasia: newEuthanasia,
      transferIn: newTransferIn,
      transferOut: newTransferOut,
    );

    final updatedMovement = existing.copyWith(
      mortality: newMortality,
      culls: newCulls,
      sale: newSale,
      kitchenRemoval: newKitchenRemoval,
      euthanasia: newEuthanasia,
      transferIn: newTransferIn,
      transferOut: newTransferOut,
      closing: newClosing,
    );

    final otherMovements = await movementRepository.getForReport(report.id);
    final withCorrection = [
      for (final m in otherMovements)
        if (m.id != existing.id) m,
      updatedMovement,
    ];
    // Throws BreederLedgerValidationError if this correction would leave a
    // transfer unbalanced — validated before the write, matching [submit].
    validateTransferBalance(withCorrection);

    final oldValues = <String, dynamic>{
      'mortality': existing.mortality,
      'culls': existing.culls,
      'sale': existing.sale,
      'kitchenRemoval': existing.kitchenRemoval,
      'euthanasia': existing.euthanasia,
      'transferIn': existing.transferIn,
      'transferOut': existing.transferOut,
      'closing': existing.closing,
    };
    final newValues = <String, dynamic>{
      'mortality': newMortality,
      'culls': newCulls,
      'sale': newSale,
      'kitchenRemoval': newKitchenRemoval,
      'euthanasia': newEuthanasia,
      'transferIn': newTransferIn,
      'transferOut': newTransferOut,
      'closing': newClosing,
    };

    await movementRepository.upsert(updatedMovement);
    return revisionService.recordCorrection(
      report: report,
      tableName: 'breeder_bird_movements',
      rowId: existing.id,
      oldValues: oldValues,
      newValues: newValues,
      reason: reason,
      actorUserId: actorUserId,
    );
  }

  /// Corrects one already-recorded feed entry's kilograms
  /// (breeder-flock-performance ticket 12, design doc section 5.2 and 9).
  /// `feedGramsPerBird` is never itself stored, so correcting `feedKg` here
  /// automatically flows through to that derived figure wherever it is
  /// displayed — there is nothing else to correct on this row.
  Future<BreederDailyReport> correctFeedEntry(
    BreederDailyReport report, {
    required String feedEntryId,
    required double feedKg,
    required String reason,
    required String actorUserId,
  }) async {
    _requireApprovedForCorrection(report);
    _requireCorrectionReasonAndActor(reason, actorUserId);
    if (feedKg < 0) {
      throw BreederLedgerValidationError(
        'feedKg cannot be negative (was $feedKg)',
      );
    }
    final existing = await feedEntryRepository.getById(feedEntryId);
    if (existing == null) {
      throw BreederLedgerValidationError(
        'No feed entry found with id $feedEntryId',
      );
    }
    if (existing.reportId != report.id) {
      throw BreederLedgerValidationError(
        'Feed entry $feedEntryId does not belong to report ${report.id}',
      );
    }
    if (existing.feedKg == feedKg) {
      // No-op: nothing to persist, and `recordCorrection` would write
      // nothing anyway — skip the write entirely.
      return report;
    }

    final updated = existing.copyWith(feedKg: feedKg);
    await feedEntryRepository.upsert(updated);
    return revisionService.recordCorrection(
      report: report,
      tableName: 'breeder_feed_entries',
      rowId: existing.id,
      oldValues: {'feedKg': existing.feedKg},
      newValues: {'feedKg': feedKg},
      reason: reason,
      actorUserId: actorUserId,
    );
  }

  /// Corrects one already-recorded egg-production grade count
  /// (breeder-flock-performance ticket 12, design doc section 5.2, 7, and
  /// 12). Total eggs, egg-grade percent, and production percent are never
  /// stored — `BreederEggProductionService` always derives them fresh from
  /// `breeder_egg_production_entries` — so correcting [count] here flows
  /// through to every one of those figures automatically; there is no
  /// separate "totals" row to keep in sync.
  ///
  /// Because today's production feeds the egg-inventory ledger's available
  /// balance (`BreederEggInventoryService.todaysProduction`), lowering a
  /// count that has already been dispatched, sold, or otherwise drawn down
  /// could drive that grade's closing inventory balance negative. This is
  /// validated via
  /// [BreederEggInventoryService.validateProductionOverrideForGrade]
  /// BEFORE the corrected count is persisted, throwing
  /// [BreederEggInventoryValidationError] and writing nothing if it would
  /// — the same "cannot correct your way into an unbalanced ledger" rule
  /// [BreederEggInventoryService.validateBalancesForApproval] enforces at
  /// approval time.
  Future<BreederDailyReport> correctEggProductionEntry(
    BreederDailyReport report, {
    required String entryId,
    required int count,
    required String reason,
    required String actorUserId,
  }) async {
    _requireApprovedForCorrection(report);
    _requireCorrectionReasonAndActor(reason, actorUserId);
    if (count < 0) {
      throw BreederLedgerValidationError(
        'count cannot be negative (was $count)',
      );
    }
    final existing = await eggProductionEntryRepository.getById(entryId);
    if (existing == null) {
      throw BreederLedgerValidationError(
        'No egg production entry found with id $entryId',
      );
    }
    if (existing.reportId != report.id) {
      throw BreederLedgerValidationError(
        'Egg production entry $entryId does not belong to report '
        '${report.id}',
      );
    }
    if (existing.count == count) {
      return report;
    }

    final currentGradeTotal = await eggInventoryService.todaysProduction(
      reportId: report.id,
      gradeId: existing.gradeId,
    );
    final overrideTotal = currentGradeTotal - existing.count + count;
    // Throws BreederEggInventoryValidationError if this would drive the
    // grade's closing inventory balance negative — nothing has been
    // persisted yet.
    await eggInventoryService.validateProductionOverrideForGrade(
      report: report,
      gradeId: existing.gradeId,
      todaysProductionOverride: overrideTotal,
    );

    await eggProductionService.recordGradeCount(
      reportId: report.id,
      houseId: existing.houseId,
      isolationAreaId: existing.isolationAreaId,
      gradeId: existing.gradeId,
      count: count,
      id: existing.id,
    );
    return revisionService.recordCorrection(
      report: report,
      tableName: 'breeder_egg_production_entries',
      rowId: existing.id,
      oldValues: {'count': existing.count},
      newValues: {'count': count},
      reason: reason,
      actorUserId: actorUserId,
    );
  }

  /// Corrects one already-recorded egg-inventory movement's quantity
  /// (breeder-flock-performance ticket 12, design doc section 8, 12, and
  /// 14). Routes through
  /// [BreederEggInventoryService.correctMovement], which appends a
  /// documented reversal of the original row followed by a new row
  /// carrying the corrected quantity — the original row is never mutated
  /// in place (design section 8: "Correction or cancellation after
  /// approval uses a documented reversing movement rather than destructive
  /// deletion"). [BreederEggInventoryService.correctMovement] itself
  /// rejects a correction that would drive the grade's closing balance
  /// negative before writing anything.
  ///
  /// [rowId] in the resulting revision entry names the *original*
  /// movement's id — the row identity a reader corrected — even though the
  /// ledger itself never mutates that row and instead gains two new ones.
  Future<BreederDailyReport> correctEggInventoryMovement(
    BreederDailyReport report, {
    required String movementId,
    required int quantity,
    required String reason,
    required String actorUserId,
  }) async {
    _requireApprovedForCorrection(report);
    _requireCorrectionReasonAndActor(reason, actorUserId);

    final existing = await eggInventoryService.movementRepository.getById(
      movementId,
    );
    if (existing == null) {
      throw BreederLedgerValidationError(
        'No egg inventory movement found with id $movementId',
      );
    }
    if (existing.reportId != report.id) {
      throw BreederLedgerValidationError(
        'Egg inventory movement $movementId does not belong to report '
        '${report.id}',
      );
    }
    if (existing.quantity == quantity) {
      return report;
    }

    // Throws BreederEggInventoryValidationError (and writes nothing) if
    // this would drive the grade's closing balance negative.
    await eggInventoryService.correctMovement(
      report: report,
      movementId: movementId,
      newQuantity: quantity,
      reason: reason,
      actorUserId: actorUserId,
    );

    return revisionService.recordCorrection(
      report: report,
      tableName: 'breeder_egg_inventory_movements',
      rowId: existing.id,
      oldValues: {'quantity': existing.quantity},
      newValues: {'quantity': quantity},
      reason: reason,
      actorUserId: actorUserId,
    );
  }

  // ---------------------------------------------------------------------
  // Feed (breeder-flock-performance ticket 09, design doc section 5.2, 7,
  // and 7.1). Feed is entered in kilograms per location per sex; grams per
  // bird is always derived here, never typed or stored.
  // ---------------------------------------------------------------------

  /// Records one location/sex feed entry (kilograms) for a Draft report. As
  /// with [recordMovement], the location is either [houseId] or
  /// [isolationAreaId] — exactly one must be given.
  Future<BreederFeedEntry> recordFeedEntry({
    required String reportId,
    String? houseId,
    String? isolationAreaId,
    required String sex,
    required double feedKg,
    String? id,
  }) async {
    if (!BreederBirdMovementSex.isValid(sex)) {
      throw ArgumentError.value(sex, 'sex', 'must be female or male');
    }
    _requireExactlyOneLocation(houseId, isolationAreaId);
    if (feedKg < 0) {
      throw BreederLedgerValidationError(
        'feedKg cannot be negative (was $feedKg)',
      );
    }
    final entry = BreederFeedEntry(
      id: id ?? _generateId(),
      reportId: reportId,
      houseId: houseId,
      isolationAreaId: isolationAreaId,
      sex: sex,
      feedKg: feedKg,
    );
    return feedEntryRepository.upsert(entry);
  }

  /// Feed grams per bird for one location's feed entry (design section 7.1:
  /// "feed grams per female divides by the closing live females in that
  /// house"; "feed grams per male divides by the closing live males in that
  /// house"; isolation feed divides by that isolation area's own count on
  /// its own row). [closingLiveBirds] is that report's own recorded closing
  /// balance for the same location and sex — deliberately not
  /// [houseBalance]/[isolationAreaBalance], which look *backward* to the
  /// most recent report strictly *before* a given date and would silently
  /// divide by yesterday's count instead of today's. A report's own closing
  /// balance is already the ledger's computed, isolation-correctly-scoped
  /// value (a house movement's `closing` can never include isolation
  /// birds, and an isolation movement's `closing` is that area's own
  /// count), so no house-balance/isolation-balance lookup is needed here —
  /// only reused, never hand-rolled, arithmetic.
  ///
  /// Returns `null` (never `0`, never a thrown error) when
  /// [closingLiveBirds] is missing, zero, or negative (design section 7.2).
  static double? feedGramsPerBird({
    required double feedKg,
    required int? closingLiveBirds,
  }) {
    if (feedKg < 0) {
      throw BreederLedgerValidationError(
        'feedKg cannot be negative (was $feedKg)',
      );
    }
    return CalculationUtils.divideOrNull(
      feedKg * 1000,
      closingLiveBirds,
      decimalPlaces: 1,
    );
  }

  // ---------------------------------------------------------------------
  // State machine (design doc section 5.3, scoped to this ticket's
  // Draft -> Submitted -> Approved slice; Revised and Sync Conflict are
  // later tickets).
  // ---------------------------------------------------------------------

  /// Moves a Draft report to Submitted. Validates that every movement's
  /// transfers balance first — a report with an unbalanced internal
  /// transfer cannot be submitted.
  Future<BreederDailyReport> submit(
    BreederDailyReport report, {
    required String actorUserId,
  }) async {
    if (report.isSyncConflict) {
      throw BreederReportStateError(
        'This report has an unresolved sync conflict and cannot be '
        'submitted until it is resolved',
      );
    }
    if (!report.isDraft) {
      throw BreederReportStateError(
        'Only a Draft report can be submitted (was ${report.state})',
      );
    }
    final movements = await movementRepository.getForReport(report.id);
    validateTransferBalance(movements);
    return reportRepository.applyTransition(
      report,
      newState: BreederDailyReportState.submitted,
      submittedBy: actorUserId,
      submittedAt: DateTime.now(),
    );
  }

  /// Moves a Submitted report to Approved. Requires [actorRole] to satisfy
  /// [BreederApprovalRole.canApprove] — a production-manager role or
  /// higher. Enforced client-side only in this ticket; the matching
  /// Supabase policy is ticket 16.
  ///
  /// [eggProductionDenominatorFemales], [benchmarkProfileVersionAtApproval],
  /// and [comparisonAxisAtApproval] are the egg-production approval
  /// snapshot (breeder-flock-performance ticket 10, design doc section
  /// 7.1: "The denominator actually used is retained in the approved
  /// report snapshot for auditability, together with the benchmark
  /// profile version and comparison axis"). This service does not compute
  /// them itself — it has no dependency on `BreederEggProductionService` or
  /// `BreederFlockLifecycleService` — the caller (the review screen)
  /// computes them and passes them through; all three stay null for a
  /// report approved before the flock entered egg production.
  ///
  /// Also validates the egg-inventory ledger via
  /// [BreederEggInventoryService.validateBalancesForApproval]
  /// (breeder-flock-performance ticket 11, design doc section 14:
  /// "Inventory equations must balance before approval, and a report that
  /// does not balance cannot be approved") — the single approval gate this
  /// method has always been, never a second, parallel mechanism. Pre
  /// -production reports pass trivially: every active grade's production
  /// and movements are zero, so every closing balance is zero.
  Future<BreederDailyReport> approve(
    BreederDailyReport report, {
    required String actorUserId,
    required String? actorRole,
    int? eggProductionDenominatorFemales,
    String? benchmarkProfileVersionAtApproval,
    String? comparisonAxisAtApproval,
  }) async {
    if (report.isSyncConflict) {
      throw BreederReportStateError(
        'This report has an unresolved sync conflict and cannot be '
        'approved until it is resolved (design doc section 5.3: a '
        'conflicted report "cannot be submitted or approved")',
      );
    }
    if (!report.isSubmitted) {
      throw BreederReportStateError(
        'Only a Submitted report can be approved (was ${report.state})',
      );
    }
    if (!BreederApprovalRole.canApprove(actorRole)) {
      throw BreederReportStateError(
        'Role "$actorRole" is not permitted to approve a report',
      );
    }
    await eggInventoryService.validateBalancesForApproval(report);
    return reportRepository.applyTransition(
      report,
      newState: BreederDailyReportState.approved,
      approvedBy: actorUserId,
      approvedAt: DateTime.now(),
      eggProductionDenominatorFemales: eggProductionDenominatorFemales,
      benchmarkProfileVersionAtApproval: benchmarkProfileVersionAtApproval,
      comparisonAxisAtApproval: comparisonAxisAtApproval,
    );
  }
}
