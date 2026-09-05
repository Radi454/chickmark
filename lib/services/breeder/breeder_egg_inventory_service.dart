/// Single source of truth for the breeder daily-report egg-inventory-ledger
/// arithmetic and validation (breeder-flock-performance ticket 11, design
/// doc section 7, 8, 12, and 14: "all formulas live in one tested domain
/// service ... reused by entry, reports, alerts, and export"). Entry
/// screens, the consolidated review, and the approval gate must all call
/// into this service rather than re-deriving available/closing balances,
/// previous-balance lookups, or adjustment/reversal rules themselves.
///
/// Bird movements, feed, and egg production are the other breeder services'
/// domains; this service only ever *reads* a report's already-recorded egg
/// production entries (via `BreederEggProductionEntryRepository`) to derive
/// "today's production" per grade — it never computes or persists a
/// production entry itself.
library;

import 'package:uuid/uuid.dart';

import '../../data/models/breeder_daily_report_model.dart';
import '../../data/models/breeder_egg_inventory_movement_model.dart';
import '../../data/repositories/breeder_egg_grade_definition_repository.dart';
import '../../data/repositories/breeder_egg_inventory_movement_repository.dart';
import '../../data/repositories/breeder_egg_production_entry_repository.dart';

/// Thrown when a movement or adjustment would violate a domain rule: a
/// negative quantity, an over-dispatch/sale/kitchen/gift that would drive
/// the closing balance negative, or a missing reason/actor/time on an
/// adjustment or reversal.
class BreederEggInventoryValidationError extends Error {
  final String message;
  BreederEggInventoryValidationError(this.message);

  @override
  String toString() => 'BreederEggInventoryValidationError: $message';
}

/// Thrown when a movement is recorded (other than a reversal) against a
/// report that has already left Draft — the ledger is append-only for
/// historical movements (design section 8): a correction after Draft must
/// go through [BreederEggInventoryService.reverseMovement].
class BreederEggInventoryStateError extends Error {
  final String message;
  BreederEggInventoryStateError(this.message);

  @override
  String toString() => 'BreederEggInventoryStateError: $message';
}

/// One grade's fully-derived inventory row for a single report (design
/// section 5.2: "Egg inventory by grade"). Every field but the four typed
/// movement quantities is computed, never independently editable.
class BreederEggInventoryBalance {
  final String gradeId;
  final int previousBalance;
  final int todaysProduction;
  final int availableBalance;
  final int dispatched;
  final int sold;
  final int kitchen;
  final int gifts;
  final int netAdjustment;
  final int closingBalance;

  const BreederEggInventoryBalance({
    required this.gradeId,
    required this.previousBalance,
    required this.todaysProduction,
    required this.availableBalance,
    required this.dispatched,
    required this.sold,
    required this.kitchen,
    required this.gifts,
    required this.netAdjustment,
    required this.closingBalance,
  });
}

class BreederEggInventoryService {
  BreederEggInventoryService({
    BreederEggInventoryMovementRepository? movementRepository,
    BreederEggGradeDefinitionRepository? gradeRepository,
    BreederEggProductionEntryRepository? productionEntryRepository,
  }) : movementRepository =
           movementRepository ?? BreederEggInventoryMovementRepository(),
       gradeRepository = gradeRepository ?? BreederEggGradeDefinitionRepository(),
       productionEntryRepository =
           productionEntryRepository ?? BreederEggProductionEntryRepository();

  final BreederEggInventoryMovementRepository movementRepository;
  final BreederEggGradeDefinitionRepository gradeRepository;
  final BreederEggProductionEntryRepository productionEntryRepository;

  static const Uuid _uuid = Uuid();
  String _generateId() => _uuid.v4();

  // ---------------------------------------------------------------------
  // Pure arithmetic (design doc section 7):
  //   available egg balance = previous balance + today's production
  //   closing egg balance = available balance - dispatch - sale - kitchen
  //     - gifts +/- approved adjustments
  // Static and side-effect free so entry, review, and approval all call the
  // exact same formula.
  // ---------------------------------------------------------------------

  static int availableBalance({
    required int previousBalance,
    required int todaysProduction,
  }) {
    _requireNonNegative({
      'previousBalance': previousBalance,
      'todaysProduction': todaysProduction,
    });
    return previousBalance + todaysProduction;
  }

  /// [netAdjustment] is already signed (positive for a net increase,
  /// negative for a net decrease) — see
  /// [BreederEggInventoryMovement.signedEffect]. Rejects a resulting
  /// negative closing balance (design section 14: "Closing balance can
  /// never go negative") rather than clamping it.
  static int closingBalance({
    required int availableBalance,
    required int dispatched,
    required int sold,
    required int kitchen,
    required int gifts,
    int netAdjustment = 0,
  }) {
    _requireNonNegative({
      'availableBalance': availableBalance,
      'dispatched': dispatched,
      'sold': sold,
      'kitchen': kitchen,
      'gifts': gifts,
    });
    final closing =
        availableBalance - dispatched - sold - kitchen - gifts + netAdjustment;
    if (closing < 0) {
      throw BreederEggInventoryValidationError(
        'Egg inventory movement would drive the closing balance negative '
        '($closing) — cannot dispatch, sell, give away, or eat more eggs '
        'of a grade than are available',
      );
    }
    return closing;
  }

  static void _requireNonNegative(Map<String, int> fields) {
    for (final entry in fields.entries) {
      if (entry.value < 0) {
        throw BreederEggInventoryValidationError(
          '${entry.key} cannot be negative (was ${entry.value})',
        );
      }
    }
  }

  // ---------------------------------------------------------------------
  // Previous balance and today's production (design doc section 7 and 14:
  // "Opening balances derive from previous ledger state").
  // ---------------------------------------------------------------------

  /// The prior ledger state for (flock, grade) as of [reportDate]: every
  /// egg produced plus every signed movement recorded on a report dated
  /// strictly before [reportDate], summed flat — a ledger's balance at any
  /// point is simply the sum of everything before it, so this is never a
  /// recursive "yesterday's closing" lookup.
  Future<int> previousBalance({
    required String flockId,
    required String gradeId,
    required DateTime reportDate,
  }) async {
    final priorProduction = await productionEntryRepository
        .sumCountForFlockGradeBeforeDate(
          flockId: flockId,
          gradeId: gradeId,
          beforeDate: reportDate,
        );
    final priorMovements = await movementRepository.getForFlockGradeBeforeDate(
      flockId: flockId,
      gradeId: gradeId,
      beforeDate: reportDate,
    );
    final netPriorMovements = _netEffect(priorMovements);
    return priorProduction + netPriorMovements;
  }

  /// Today's production for (report, grade) — always derived from
  /// `breeder_egg_production_entries`, never re-entered or duplicated here
  /// (design section 11).
  Future<int> todaysProduction({
    required String reportId,
    required String gradeId,
  }) {
    return productionEntryRepository.sumCountForReportAndGrade(
      reportId,
      gradeId,
    );
  }

  static int _netEffect(List<BreederEggInventoryMovement> movements) {
    var total = 0;
    for (final movement in movements) {
      total += movement.signedEffect;
    }
    return total;
  }

  /// The fully-derived inventory row for (report, grade) — every field the
  /// entry/review screens display, computed fresh from the ledger and
  /// today's production every time (design section 7.2: derived values are
  /// never independently editable).
  Future<BreederEggInventoryBalance> balanceFor({
    required String flockId,
    required String reportId,
    required DateTime reportDate,
    required String gradeId,
  }) async {
    final previous = await previousBalance(
      flockId: flockId,
      gradeId: gradeId,
      reportDate: reportDate,
    );
    final production = await todaysProduction(
      reportId: reportId,
      gradeId: gradeId,
    );
    final available = availableBalance(
      previousBalance: previous,
      todaysProduction: production,
    );
    final todaysMovements = await movementRepository.getForReportAndGrade(
      reportId,
      gradeId,
    );
    final dispatched = _sumKind(
      todaysMovements,
      BreederEggInventoryMovementKind.hatcheryDispatch,
    );
    final sold = _sumKind(todaysMovements, BreederEggInventoryMovementKind.sale);
    final kitchen = _sumKind(
      todaysMovements,
      BreederEggInventoryMovementKind.kitchen,
    );
    final gifts = _sumKind(todaysMovements, BreederEggInventoryMovementKind.gift);
    final netAdjustment = _netEffect(
      todaysMovements
          .where((m) => m.kind == BreederEggInventoryMovementKind.adjustment)
          .toList(),
    );
    final closing = closingBalance(
      availableBalance: available,
      dispatched: dispatched,
      sold: sold,
      kitchen: kitchen,
      gifts: gifts,
      netAdjustment: netAdjustment,
    );
    return BreederEggInventoryBalance(
      gradeId: gradeId,
      previousBalance: previous,
      todaysProduction: production,
      availableBalance: available,
      dispatched: dispatched,
      sold: sold,
      kitchen: kitchen,
      gifts: gifts,
      netAdjustment: netAdjustment,
      closingBalance: closing,
    );
  }

  /// [balanceFor] for every active grade (design section 5.2).
  Future<List<BreederEggInventoryBalance>> balancesForReport(
    BreederDailyReport report, {
    String? flockId,
  }) async {
    final grades = await gradeRepository.listActiveGrades();
    final result = <BreederEggInventoryBalance>[];
    for (final grade in grades) {
      result.add(
        await balanceFor(
          flockId: flockId ?? report.flockId,
          reportId: report.id,
          reportDate: report.reportDate,
          gradeId: grade.id,
        ),
      );
    }
    return result;
  }

  /// The net total for one plain kind (dispatch/sale/kitchen/gift): every
  /// non-reversal row's quantity, minus any reversal of that kind (a
  /// reversal hands the quantity back, so it reduces how much is still
  /// counted as dispatched/sold/kitchen/gifted today — design section 8).
  /// This is what feeds [closingBalance], so a reversed dispatch correctly
  /// restores the closing balance rather than leaving it silently
  /// unaffected.
  static int _sumKind(List<BreederEggInventoryMovement> movements, String kind) {
    var total = 0;
    for (final movement in movements) {
      if (movement.kind != kind) continue;
      total += movement.isReversal ? -movement.quantity : movement.quantity;
    }
    return total;
  }

  // ---------------------------------------------------------------------
  // Movement persistence (design section 8 and 14).
  // ---------------------------------------------------------------------

  /// Records (or corrects, while still Draft) one of the four plain
  /// movement kinds for (report, grade). Throws
  /// [BreederEggInventoryStateError] once [report] has left Draft — from
  /// then on, [reverseMovement] is the only way to correct a historical
  /// movement (design section 8, append-only ledger).
  Future<BreederEggInventoryMovement> recordMovement({
    required BreederDailyReport report,
    required String gradeId,
    required String kind,
    required int quantity,
    String? id,
  }) async {
    if (kind == BreederEggInventoryMovementKind.adjustment) {
      throw ArgumentError.value(
        kind,
        'kind',
        'use recordAdjustment for an adjustment movement',
      );
    }
    if (!report.isDraft) {
      throw BreederEggInventoryStateError(
        'Only a Draft report\'s egg inventory movements can be edited '
        'directly (was ${report.state}) — use reverseMovement to correct a '
        'historical movement',
      );
    }
    if (quantity < 0) {
      throw BreederEggInventoryValidationError(
        'quantity cannot be negative (was $quantity)',
      );
    }
    final existing = await movementRepository.getEditableRow(
      report.id,
      gradeId,
      kind,
    );
    final movement = BreederEggInventoryMovement(
      id: id ?? existing?.id ?? _generateId(),
      reportId: report.id,
      gradeId: gradeId,
      kind: kind,
      quantity: quantity,
    );
    // Validate against the balance the whole set of today's movements would
    // produce with this change applied, before persisting it — the entry
    // -time defense described in design section 14, independent of the
    // approval-time re-check in [validateBalancesForApproval].
    await _assertWouldNotGoNegative(
      flockId: report.flockId,
      reportId: report.id,
      reportDate: report.reportDate,
      gradeId: gradeId,
      candidate: movement,
    );
    return movementRepository.upsert(movement);
  }

  /// Records an approved adjustment (design section 14: "Adjustments
  /// require a reason, an actor, and a time"). Always appends a new row —
  /// an adjustment is never upserted/overwritten, matching the append-only
  /// ledger.
  Future<BreederEggInventoryMovement> recordAdjustment({
    required BreederDailyReport report,
    required String gradeId,
    required String direction,
    required int quantity,
    required String reason,
    required String actorUserId,
    DateTime? occurredAt,
    String? id,
  }) async {
    if (quantity < 0) {
      throw BreederEggInventoryValidationError(
        'quantity cannot be negative (was $quantity)',
      );
    }
    if (reason.trim().isEmpty) {
      throw BreederEggInventoryValidationError(
        'An adjustment requires a non-empty reason',
      );
    }
    if (actorUserId.trim().isEmpty) {
      throw BreederEggInventoryValidationError(
        'An adjustment requires an actor',
      );
    }
    final movement = BreederEggInventoryMovement(
      id: id ?? _generateId(),
      reportId: report.id,
      gradeId: gradeId,
      kind: BreederEggInventoryMovementKind.adjustment,
      quantity: quantity,
      adjustmentDirection: direction,
      reason: reason.trim(),
      actorUserId: actorUserId,
      occurredAt: occurredAt ?? DateTime.now(),
    );
    await _assertWouldNotGoNegative(
      flockId: report.flockId,
      reportId: report.id,
      reportDate: report.reportDate,
      gradeId: gradeId,
      candidate: movement,
    );
    return movementRepository.insertAppend(movement);
  }

  /// Records one `hatchery_dispatch` movement for an approved
  /// `egg_shipments` row (breeder-flock-performance ticket 14, design
  /// section 8: "Approving a hatchery dispatch produces the corresponding
  /// inventory movement... one dispatch, one ledger movement"). Always
  /// appends a new row via [BreederEggInventoryMovementRepository
  /// .insertAppend] — never [recordMovement]'s upsert, since a shipment can
  /// be approved for a report that has long since left Draft (the
  /// [recordMovement] entry-time upsert path only applies to a report's own
  /// in-progress dispatched/sold/kitchen/gift fields) — and the ledger may
  /// already carry another shipment's dispatch for the same (report,
  /// grade), which must not be silently replaced.
  ///
  /// Re-validates the whole (report, grade) balance with [reason]'s
  /// candidate row *added* to every already-recorded movement (never
  /// substituted for one, via `appendOnly: true`) before persisting —
  /// design section 12's "no egg dispatch beyond available inventory",
  /// reusing this service's existing arithmetic rather than a second
  /// implementation.
  Future<BreederEggInventoryMovement> recordHatcheryDispatch({
    required BreederDailyReport report,
    required String gradeId,
    required int quantity,
    required String reason,
    String? actorUserId,
    DateTime? occurredAt,
    String? id,
  }) async {
    if (quantity < 0) {
      throw BreederEggInventoryValidationError(
        'quantity cannot be negative (was $quantity)',
      );
    }
    if (reason.trim().isEmpty) {
      throw BreederEggInventoryValidationError(
        'A hatchery dispatch requires a non-empty reason',
      );
    }
    final movement = BreederEggInventoryMovement(
      id: id ?? _generateId(),
      reportId: report.id,
      gradeId: gradeId,
      kind: BreederEggInventoryMovementKind.hatcheryDispatch,
      quantity: quantity,
      reason: reason.trim(),
      actorUserId: actorUserId,
      occurredAt: occurredAt ?? DateTime.now(),
    );
    await _assertWouldNotGoNegative(
      flockId: report.flockId,
      reportId: report.id,
      reportDate: report.reportDate,
      gradeId: gradeId,
      candidate: movement,
      appendOnly: true,
    );
    return movementRepository.insertAppend(movement);
  }

  /// Records a documented reversal of [movementId] (design section 8:
  /// "Correction or cancellation after approval uses a documented reversing
  /// movement rather than destructive deletion"). Always appends a new row
  /// — the original row is never edited or deleted, and this is the only
  /// correction path once a report has left Draft.
  Future<BreederEggInventoryMovement> reverseMovement({
    required String movementId,
    required String reason,
    required String actorUserId,
    DateTime? occurredAt,
    String? id,
  }) async {
    final original = await movementRepository.getById(movementId);
    if (original == null) {
      throw BreederEggInventoryValidationError(
        'No egg inventory movement found with id $movementId',
      );
    }
    if (reason.trim().isEmpty) {
      throw BreederEggInventoryValidationError(
        'A reversal requires a non-empty reason',
      );
    }
    if (actorUserId.trim().isEmpty) {
      throw BreederEggInventoryValidationError(
        'A reversal requires an actor',
      );
    }
    final reversal = BreederEggInventoryMovement(
      id: id ?? _generateId(),
      reportId: original.reportId,
      gradeId: original.gradeId,
      kind: original.kind,
      quantity: original.quantity,
      adjustmentDirection: original.adjustmentDirection,
      reason: reason.trim(),
      actorUserId: actorUserId,
      occurredAt: occurredAt ?? DateTime.now(),
      reversedMovementId: original.id,
    );
    return movementRepository.insertAppend(reversal);
  }

  Future<void> _assertWouldNotGoNegative({
    required String flockId,
    required String reportId,
    required DateTime reportDate,
    required String gradeId,
    required BreederEggInventoryMovement candidate,
    bool appendOnly = false,
  }) async {
    final previous = await previousBalance(
      flockId: flockId,
      gradeId: gradeId,
      reportDate: reportDate,
    );
    final production = await todaysProduction(
      reportId: reportId,
      gradeId: gradeId,
    );
    final available = availableBalance(
      previousBalance: previous,
      todaysProduction: production,
    );
    final existingMovements = await movementRepository.getForReportAndGrade(
      reportId,
      gradeId,
    );
    // [candidate] either replaces the single existing editable row of its
    // own plain kind (an upsert-in-progress dispatch/sale/kitchen/gift), or
    // — for an adjustment, which is always appended rather than replaced,
    // or when [appendOnly] is explicitly requested (breeder-flock
    // -performance ticket 14: a hatchery-dispatch movement posted for an
    // `egg_shipments` approval is always a brand-new row alongside any
    // other shipment's dispatch already recorded against the same
    // (report, grade), never a replacement of it) — adds to the existing
    // set untouched.
    final isPlainKindReplace =
        !appendOnly &&
        candidate.kind != BreederEggInventoryMovementKind.adjustment;
    final withCandidate = [
      for (final m in existingMovements)
        if (!(isPlainKindReplace && m.kind == candidate.kind && !m.isReversal))
          m,
      candidate,
    ];
    final dispatched = _sumKind(
      withCandidate,
      BreederEggInventoryMovementKind.hatcheryDispatch,
    );
    final sold = _sumKind(withCandidate, BreederEggInventoryMovementKind.sale);
    final kitchen = _sumKind(
      withCandidate,
      BreederEggInventoryMovementKind.kitchen,
    );
    final gifts = _sumKind(withCandidate, BreederEggInventoryMovementKind.gift);
    final netAdjustment = _netEffect(
      withCandidate
          .where((m) => m.kind == BreederEggInventoryMovementKind.adjustment)
          .toList(),
    );
    // Throws BreederEggInventoryValidationError if this would go negative.
    closingBalance(
      availableBalance: available,
      dispatched: dispatched,
      sold: sold,
      kitchen: kitchen,
      gifts: gifts,
      netAdjustment: netAdjustment,
    );
  }

  // ---------------------------------------------------------------------
  // Approval gate (design section 14: "Inventory equations must balance
  // before approval"). Called from `BreederBirdLedgerService.approve` —
  // never a second, parallel approval mechanism.
  // ---------------------------------------------------------------------

  /// Recomputes every active grade's closing balance for [report] and
  /// throws [BreederEggInventoryValidationError] if any would be negative.
  /// This re-check exists because an entry made after another one — e.g.
  /// today's production count lowered *after* a dispatch was already
  /// recorded against it — is not caught by [recordMovement]'s own
  /// point-in-time check; approval is what design section 14 actually names
  /// as the gate ("a report whose inventory does not balance cannot be
  /// approved").
  /// Recomputes grade [gradeId]'s closing balance for [report] as it would
  /// be if [todaysProductionOverride] eggs had been produced today instead
  /// of whatever `breeder_egg_production_entries` currently sums to, and
  /// throws [BreederEggInventoryValidationError] if that would be negative
  /// — the check `BreederBirdLedgerService.correctEggProductionEntry`
  /// (breeder-flock-performance ticket 12) runs BEFORE persisting a
  /// corrected egg-grade count, so a correction that would silently break
  /// the ledger is rejected instead of landing on an unbalanced report
  /// (design section 14, mirroring [validateBalancesForApproval]'s
  /// approval-time gate rather than a new, separate rule).
  Future<void> validateProductionOverrideForGrade({
    required BreederDailyReport report,
    required String gradeId,
    required int todaysProductionOverride,
  }) async {
    if (todaysProductionOverride < 0) {
      throw BreederEggInventoryValidationError(
        'todaysProductionOverride cannot be negative '
        '(was $todaysProductionOverride)',
      );
    }
    final previous = await previousBalance(
      flockId: report.flockId,
      gradeId: gradeId,
      reportDate: report.reportDate,
    );
    final available = availableBalance(
      previousBalance: previous,
      todaysProduction: todaysProductionOverride,
    );
    final movements = await movementRepository.getForReportAndGrade(
      report.id,
      gradeId,
    );
    final dispatched = _sumKind(
      movements,
      BreederEggInventoryMovementKind.hatcheryDispatch,
    );
    final sold = _sumKind(movements, BreederEggInventoryMovementKind.sale);
    final kitchen = _sumKind(movements, BreederEggInventoryMovementKind.kitchen);
    final gifts = _sumKind(movements, BreederEggInventoryMovementKind.gift);
    final netAdjustment = _netEffect(
      movements
          .where((m) => m.kind == BreederEggInventoryMovementKind.adjustment)
          .toList(),
    );
    // Throws BreederEggInventoryValidationError if this would go negative.
    closingBalance(
      availableBalance: available,
      dispatched: dispatched,
      sold: sold,
      kitchen: kitchen,
      gifts: gifts,
      netAdjustment: netAdjustment,
    );
  }

  /// Corrects an already-recorded plain movement (dispatch/sale/kitchen
  /// /gift) or adjustment to [newQuantity] by appending a documented
  /// reversal of the original row followed by a new row carrying the
  /// corrected quantity — never by mutating [movementId] in place (design
  /// section 8: "Correction or cancellation after approval uses a
  /// documented reversing movement rather than destructive deletion").
  /// This is the append-only-ledger counterpart of
  /// `BreederBirdLedgerService.correctHeader`/`correctMovement` for the
  /// other report tables (breeder-flock-performance ticket 12).
  ///
  /// The resulting balance is validated BEFORE either row is persisted —
  /// simulating the original row plus the new reversal plus the new
  /// corrected row together (the original's effect and the reversal's
  /// exactly cancel, leaving only [newQuantity] to count, precisely what
  /// the ledger will show once both rows are actually written) — and
  /// throws [BreederEggInventoryValidationError] without writing anything
  /// if that would drive the closing balance negative.
  Future<BreederEggInventoryMovement> correctMovement({
    required BreederDailyReport report,
    required String movementId,
    required int newQuantity,
    required String reason,
    required String actorUserId,
    DateTime? occurredAt,
  }) async {
    if (newQuantity < 0) {
      throw BreederEggInventoryValidationError(
        'newQuantity cannot be negative (was $newQuantity)',
      );
    }
    if (reason.trim().isEmpty) {
      throw BreederEggInventoryValidationError(
        'A correction requires a non-empty reason',
      );
    }
    if (actorUserId.trim().isEmpty) {
      throw BreederEggInventoryValidationError(
        'A correction requires an actor',
      );
    }
    final original = await movementRepository.getById(movementId);
    if (original == null) {
      throw BreederEggInventoryValidationError(
        'No egg inventory movement found with id $movementId',
      );
    }
    if (original.isReversal) {
      throw BreederEggInventoryValidationError(
        'Cannot correct a reversal row directly',
      );
    }

    final occurred = occurredAt ?? DateTime.now();
    final reversal = BreederEggInventoryMovement(
      id: _generateId(),
      reportId: original.reportId,
      gradeId: original.gradeId,
      kind: original.kind,
      quantity: original.quantity,
      adjustmentDirection: original.adjustmentDirection,
      reason: reason.trim(),
      actorUserId: actorUserId,
      occurredAt: occurred,
      reversedMovementId: original.id,
    );
    final corrected = BreederEggInventoryMovement(
      id: _generateId(),
      reportId: original.reportId,
      gradeId: original.gradeId,
      kind: original.kind,
      quantity: newQuantity,
      adjustmentDirection: original.adjustmentDirection,
      reason: reason.trim(),
      actorUserId: actorUserId,
      occurredAt: occurred,
    );

    // Validate the state as it will exist once BOTH new rows are written,
    // alongside every row already on record (including [original] itself
    // — unlike the entry-time upsert check in [_assertWouldNotGoNegative],
    // nothing here is "replaced", so [original] must stay in the simulated
    // set for the reversal's cancelling effect to net out correctly).
    final existingMovements = await movementRepository.getForReportAndGrade(
      report.id,
      original.gradeId,
    );
    final previous = await previousBalance(
      flockId: report.flockId,
      gradeId: original.gradeId,
      reportDate: report.reportDate,
    );
    final production = await todaysProduction(
      reportId: report.id,
      gradeId: original.gradeId,
    );
    final available = availableBalance(
      previousBalance: previous,
      todaysProduction: production,
    );
    final simulated = [...existingMovements, reversal, corrected];
    final dispatched = _sumKind(
      simulated,
      BreederEggInventoryMovementKind.hatcheryDispatch,
    );
    final sold = _sumKind(simulated, BreederEggInventoryMovementKind.sale);
    final kitchen = _sumKind(simulated, BreederEggInventoryMovementKind.kitchen);
    final gifts = _sumKind(simulated, BreederEggInventoryMovementKind.gift);
    final netAdjustment = _netEffect(
      simulated
          .where((m) => m.kind == BreederEggInventoryMovementKind.adjustment)
          .toList(),
    );
    // Throws BreederEggInventoryValidationError if this would go negative —
    // nothing has been written yet, so a rejected correction leaves the
    // ledger completely untouched.
    closingBalance(
      availableBalance: available,
      dispatched: dispatched,
      sold: sold,
      kitchen: kitchen,
      gifts: gifts,
      netAdjustment: netAdjustment,
    );

    await movementRepository.insertAppend(reversal);
    return movementRepository.insertAppend(corrected);
  }

  Future<void> validateBalancesForApproval(BreederDailyReport report) async {
    final balances = await balancesForReport(report);
    for (final balance in balances) {
      if (balance.closingBalance < 0) {
        throw BreederEggInventoryValidationError(
          'Egg inventory for grade ${balance.gradeId} does not balance: '
          'closing balance would be ${balance.closingBalance}',
        );
      }
    }
  }
}
