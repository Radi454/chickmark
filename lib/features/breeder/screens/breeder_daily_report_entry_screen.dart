import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../data/models/breeder_bird_movement_model.dart';
import '../../../data/models/breeder_daily_report_model.dart';
import '../../../data/models/breeder_egg_grade_definition_model.dart';
import '../../../data/models/breeder_egg_inventory_movement_model.dart';
import '../../../data/models/breeder_egg_production_entry_model.dart';
import '../../../data/models/breeder_feed_entry_model.dart';
import '../../../data/models/flock_model.dart';
import '../../../data/repositories/breeder_bird_movement_repository.dart';
import '../../../data/repositories/breeder_daily_report_repository.dart';
import '../../../data/repositories/breeder_egg_grade_definition_repository.dart';
import '../../../data/repositories/breeder_egg_inventory_movement_repository.dart';
import '../../../data/repositories/breeder_egg_production_entry_repository.dart';
import '../../../data/repositories/breeder_feed_entry_repository.dart';
import '../../../data/repositories/breeder_isolation_area_repository.dart';
import '../../../data/repositories/poultry_hierarchy_repository.dart';
import '../../../services/breeder/breeder_bird_ledger_service.dart';
import '../../../services/breeder/breeder_egg_inventory_service.dart';
import '../../../services/breeder/breeder_egg_production_service.dart';
import '../../../services/breeder/breeder_flock_lifecycle_service.dart';
import '../../../widgets/section_card.dart';
import '../../auth/providers/auth_provider.dart';
import 'breeder_daily_report_review_screen.dart';

/// One location a daily report can record bird movements against: either a
/// production house or a named isolation area (breeder-flock-performance
/// ticket 08, design doc section 6: "isolation areas [are] separate
/// locations"). This screen treats both uniformly for entry purposes —
/// [isIsolation] is only consulted where the ledger service itself
/// distinguishes houses from isolation areas (opening-balance derivation
/// and which repository field a movement is recorded against).
class _EntryLocation {
  final String id;
  final String name;
  final bool isIsolation;

  const _EntryLocation({
    required this.id,
    required this.name,
    required this.isIsolation,
  });
}

/// House-by-house (and isolation-area-by-isolation-area) bird-movement entry
/// for one Draft daily report (breeder-flock-performance ticket 07, design
/// doc section 5.3: "entry is house-by-house, with isolation areas as
/// separate locations"; isolation areas added by ticket 08).
///
/// Every displayed opening/closing balance and every persisted movement row
/// goes through `BreederBirdLedgerService`; this screen never computes a
/// closing balance itself.
class BreederDailyReportEntryScreen extends StatefulWidget {
  final FlockModel flock;
  final BreederDailyReport report;
  final BreederBirdLedgerService? service;
  final PoultryHierarchyRepository? houseRepository;
  final BreederIsolationAreaRepository? isolationAreaRepository;
  final BreederBirdMovementRepository? movementRepository;
  final BreederDailyReportRepository? reportRepository;
  final BreederFeedEntryRepository? feedEntryRepository;
  final BreederEggGradeDefinitionRepository? eggGradeRepository;
  final BreederEggProductionEntryRepository? eggProductionEntryRepository;
  final BreederEggProductionService? eggProductionService;
  final BreederEggInventoryMovementRepository? eggInventoryMovementRepository;
  final BreederEggInventoryService? eggInventoryService;
  final BreederFlockLifecycleService? lifecycleService;

  /// Overrides the acting user's id instead of reading
  /// `AuthProvider.user` — mirrors
  /// `BreederDailyReportReviewScreen.actorUserIdOverride`, so widget tests
  /// can exercise adjustment recording without wiring a full auth stack.
  final String? actorUserIdOverride;

  const BreederDailyReportEntryScreen({
    super.key,
    required this.flock,
    required this.report,
    this.service,
    this.houseRepository,
    this.isolationAreaRepository,
    this.movementRepository,
    this.reportRepository,
    this.feedEntryRepository,
    this.eggGradeRepository,
    this.eggProductionEntryRepository,
    this.eggProductionService,
    this.eggInventoryMovementRepository,
    this.eggInventoryService,
    this.lifecycleService,
    this.actorUserIdOverride,
  });

  @override
  State<BreederDailyReportEntryScreen> createState() =>
      _BreederDailyReportEntryScreenState();
}

class _MovementFieldControllers {
  final TextEditingController mortality;
  final TextEditingController culls;
  final TextEditingController sale;
  final TextEditingController sexSpecificRemoval;
  final TextEditingController transferIn;
  final TextEditingController transferOut;

  _MovementFieldControllers(BreederBirdMovement movement)
    : mortality = TextEditingController(text: '${movement.mortality}'),
      culls = TextEditingController(text: '${movement.culls}'),
      sale = TextEditingController(text: '${movement.sale}'),
      sexSpecificRemoval = TextEditingController(
        text: '${movement.sexSpecificRemoval}',
      ),
      transferIn = TextEditingController(text: '${movement.transferIn}'),
      transferOut = TextEditingController(text: '${movement.transferOut}');

  void dispose() {
    mortality.dispose();
    culls.dispose();
    sale.dispose();
    sexSpecificRemoval.dispose();
    transferIn.dispose();
    transferOut.dispose();
  }
}

/// Feed-kilogram input for one location/sex (breeder-flock-performance
/// ticket 09). Grams-per-bird has no controller of its own anywhere in this
/// screen — it is always displayed as a read-only, computed value, never a
/// text field a user can type into.
class _FeedFieldControllers {
  final TextEditingController feedKg;

  _FeedFieldControllers(BreederFeedEntry? entry)
    : feedKg = TextEditingController(text: _formatKg(entry?.feedKg ?? 0));

  static String _formatKg(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

  void dispose() {
    feedKg.dispose();
  }
}

/// Egg-grade-count input for one location (breeder-flock-performance
/// ticket 10): one text field per active grade, keyed by gradeId, plus one
/// egg-weight field shared across the whole location. Total eggs, grade
/// percentages, and production percent are never text fields — always
/// recomputed for display from these counts via
/// `BreederEggProductionService`.
class _EggFieldControllers {
  final Map<String, TextEditingController> countByGradeId;
  final TextEditingController eggWeightGrams;

  _EggFieldControllers({
    required Map<String, int> countsByGradeId,
    double? eggWeightGrams,
  }) : countByGradeId = {
         for (final entry in countsByGradeId.entries)
           entry.key: TextEditingController(text: '${entry.value}'),
       },
       eggWeightGrams = TextEditingController(
         text: eggWeightGrams == null
             ? ''
             : (eggWeightGrams == eggWeightGrams.roundToDouble()
                   ? eggWeightGrams.toStringAsFixed(0)
                   : '$eggWeightGrams'),
       );

  void dispose() {
    for (final c in countByGradeId.values) {
      c.dispose();
    }
    eggWeightGrams.dispose();
  }
}

/// Editable-field input for one grade's egg-inventory row on a Draft report
/// (breeder-flock-performance ticket 11): dispatched/sold/kitchen/gifts.
/// Previous balance, today's production, available balance, and closing
/// balance have no controllers here at all — they are always displayed as
/// read-only computed text, never a field a user can type into (design
/// section 7.2 and the ticket's "Derived cells read-only" acceptance
/// criterion).
class _InventoryFieldControllers {
  final TextEditingController dispatched;
  final TextEditingController sold;
  final TextEditingController kitchen;
  final TextEditingController gifts;

  _InventoryFieldControllers(BreederEggInventoryBalance? balance)
    : dispatched = TextEditingController(text: '${balance?.dispatched ?? 0}'),
      sold = TextEditingController(text: '${balance?.sold ?? 0}'),
      kitchen = TextEditingController(text: '${balance?.kitchen ?? 0}'),
      gifts = TextEditingController(text: '${balance?.gifts ?? 0}');

  void dispose() {
    dispatched.dispose();
    sold.dispose();
    kitchen.dispose();
    gifts.dispose();
  }
}

class _BreederDailyReportEntryScreenState
    extends State<BreederDailyReportEntryScreen> {
  late final PoultryHierarchyRepository _houseRepository =
      widget.houseRepository ?? PoultryHierarchyRepository();
  late final BreederIsolationAreaRepository _isolationAreaRepository =
      widget.isolationAreaRepository ?? BreederIsolationAreaRepository();
  late final BreederBirdMovementRepository _movementRepository =
      widget.movementRepository ?? BreederBirdMovementRepository();
  late final BreederDailyReportRepository _reportRepository =
      widget.reportRepository ?? BreederDailyReportRepository();
  late final BreederFeedEntryRepository _feedEntryRepository =
      widget.feedEntryRepository ?? BreederFeedEntryRepository();
  late final BreederBirdLedgerService _service =
      widget.service ??
      BreederBirdLedgerService(
        reportRepository: _reportRepository,
        movementRepository: _movementRepository,
        houseRepository: _houseRepository,
        isolationAreaRepository: _isolationAreaRepository,
        feedEntryRepository: _feedEntryRepository,
      );
  late final BreederEggGradeDefinitionRepository _eggGradeRepository =
      widget.eggGradeRepository ?? BreederEggGradeDefinitionRepository();
  late final BreederEggProductionEntryRepository _eggProductionEntryRepository =
      widget.eggProductionEntryRepository ??
      BreederEggProductionEntryRepository();
  late final BreederEggProductionService _eggProductionService =
      widget.eggProductionService ??
      BreederEggProductionService(
        gradeRepository: _eggGradeRepository,
        entryRepository: _eggProductionEntryRepository,
      );
  late final BreederEggInventoryMovementRepository
  _eggInventoryMovementRepository =
      widget.eggInventoryMovementRepository ??
      BreederEggInventoryMovementRepository();
  late final BreederEggInventoryService _eggInventoryService =
      widget.eggInventoryService ??
      BreederEggInventoryService(
        movementRepository: _eggInventoryMovementRepository,
        gradeRepository: _eggGradeRepository,
        productionEntryRepository: _eggProductionEntryRepository,
      );
  late final BreederFlockLifecycleService _lifecycleService =
      widget.lifecycleService ?? BreederFlockLifecycleService();

  late Future<void> _loadFuture;
  late BreederDailyReport _report = widget.report;
  List<_EntryLocation> _locations = const [];
  final Map<String, BreederBirdMovement> _movements = {};
  final Map<String, _MovementFieldControllers> _controllers = {};
  final Map<String, BreederFeedEntry?> _feedEntries = {};
  final Map<String, _FeedFieldControllers> _feedControllers = {};

  /// True once the flock has entered the benchmark profile's official
  /// production range (design doc section 5.1) — gates the whole egg
  /// section. Delegated to `BreederFlockLifecycleService`, never
  /// re-derived here.
  bool _hasEggSection = false;
  List<BreederEggGradeDefinition> _grades = const [];
  final Map<String, List<BreederEggProductionEntry>> _eggEntriesByLocation = {};
  final Map<String, _EggFieldControllers> _eggControllers = {};

  /// Flock-level egg-inventory balances, one per active grade
  /// (breeder-flock-performance ticket 11) — keyed by gradeId, unlike the
  /// per-location egg-production maps above, since inventory has no house
  /// /isolation split (design section 5.2).
  final Map<String, BreederEggInventoryBalance> _inventoryBalances = {};
  final Map<String, _InventoryFieldControllers> _inventoryControllers = {};

  /// Guards [_applyInventoryChange] against the double-invocation
  /// `TextField.onSubmitted`/`onEditingComplete` can both fire for a single
  /// "done" action (harmless for the other entry fields in this screen,
  /// which always update an already-initialized row, but would otherwise
  /// insert two ledger rows here on a grade/kind's very first edit, since
  /// the egg-inventory ledger deliberately has no eager zero-row
  /// initialization — see `BreederEggInventoryService`'s doc comment on why
  /// "production in" is never persisted as a row at all).
  final Set<String> _pendingInventoryChanges = {};

  String? _error;

  // Report-header field controllers (breeder-flock-performance ticket 09):
  // inside/outside temperature already existed as data from ticket 07 but
  // had no entry UI; light hours and notes are shown here alongside them.
  late final TextEditingController _insideTempController =
      TextEditingController(text: _formatNullableNumber(_report.insideTemperature));
  late final TextEditingController _outsideTempController =
      TextEditingController(text: _formatNullableNumber(_report.outsideTemperature));
  late final TextEditingController _lightHoursController =
      TextEditingController(text: _formatNullableNumber(_report.lightHours));
  late final TextEditingController _notesController = TextEditingController(
    text: _report.notes ?? '',
  );

  static String _formatNullableNumber(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : '$value';
  }

  String _key(String locationId, String sex) => '$locationId|$sex';

  String? get _actorUserId =>
      widget.actorUserIdOverride ?? context.read<AuthProvider>().user?.id;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  @override
  void dispose() {
    for (final controllers in _controllers.values) {
      controllers.dispose();
    }
    for (final controllers in _feedControllers.values) {
      controllers.dispose();
    }
    for (final controllers in _eggControllers.values) {
      controllers.dispose();
    }
    for (final controllers in _inventoryControllers.values) {
      controllers.dispose();
    }
    _insideTempController.dispose();
    _outsideTempController.dispose();
    _lightHoursController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final houses = await _houseRepository.listHouses(widget.flock.id);
    final isolationAreas = await _isolationAreaRepository.listAreas(
      widget.flock.id,
    );
    _locations = [
      for (final house in houses)
        _EntryLocation(id: house.id, name: house.name, isIsolation: false),
      for (final area in isolationAreas)
        _EntryLocation(id: area.id, name: area.name, isIsolation: true),
    ];
    for (final location in _locations) {
      for (final sex in BreederBirdMovementSex.all) {
        final existing = location.isIsolation
            ? await _movementRepository.getByReportIsolationAreaSex(
                widget.report.id,
                location.id,
                sex,
              )
            : await _movementRepository.getByReportHouseSex(
                widget.report.id,
                location.id,
                sex,
              );
        final movement =
            existing ?? await _initializeMovement(location: location, sex: sex);
        _movements[_key(location.id, sex)] = movement;
        _controllers[_key(location.id, sex)] = _MovementFieldControllers(
          movement,
        );
        final feedEntry = location.isIsolation
            ? await _feedEntryRepository.getByReportIsolationAreaSex(
                widget.report.id,
                location.id,
                sex,
              )
            : await _feedEntryRepository.getByReportHouseSex(
                widget.report.id,
                location.id,
                sex,
              );
        _feedEntries[_key(location.id, sex)] = feedEntry;
        _feedControllers[_key(location.id, sex)] = _FeedFieldControllers(
          feedEntry,
        );
      }
    }

    _hasEggSection = await _lifecycleService.hasEnteredProductionRange(
      widget.flock,
      now: _report.reportDate,
    );
    if (_hasEggSection) {
      _grades = await _eggGradeRepository.listActiveGrades();
      for (final location in _locations) {
        final entries = await _eggProductionService.initializeEntriesForLocation(
          reportId: _report.id,
          houseId: location.isIsolation ? null : location.id,
          isolationAreaId: location.isIsolation ? location.id : null,
        );
        _eggEntriesByLocation[location.id] = entries;
        _eggControllers[location.id] = _EggFieldControllers(
          countsByGradeId: {for (final e in entries) e.gradeId: e.count},
          eggWeightGrams: entries.isEmpty ? null : entries.first.eggWeightGrams,
        );
      }
      await _loadInventoryBalances();
    }
  }

  /// Loads every active grade's egg-inventory balance and creates its field
  /// controllers, once, at screen load (breeder-flock-performance ticket
  /// 11). Later changes call [_refreshInventoryBalance] instead, which
  /// recomputes the balance without recreating (and so without disrupting)
  /// the already-live controllers.
  Future<void> _loadInventoryBalances() async {
    for (final grade in _grades) {
      final balance = await _fetchInventoryBalance(grade.id);
      _inventoryBalances[grade.id] = balance;
      _inventoryControllers[grade.id] = _InventoryFieldControllers(balance);
    }
  }

  Future<BreederEggInventoryBalance> _fetchInventoryBalance(
    String gradeId,
  ) {
    return _eggInventoryService.balanceFor(
      flockId: widget.flock.id,
      reportId: _report.id,
      reportDate: _report.reportDate,
      gradeId: gradeId,
    );
  }

  /// Recomputes and stores [gradeId]'s balance after a movement change
  /// (breeder-flock-performance ticket 11). Previous balance, today's
  /// production, available balance, and closing balance are always
  /// freshly derived — never read from a cached field a user could have
  /// edited (design section 7.2).
  Future<void> _refreshInventoryBalance(String gradeId) async {
    _inventoryBalances[gradeId] = await _fetchInventoryBalance(gradeId);
  }

  Future<BreederBirdMovement> _initializeMovement({
    required _EntryLocation location,
    required String sex,
  }) async {
    final opening = location.isIsolation
        ? await _service.isolationOpeningBalanceFor(
            flockId: widget.flock.id,
            isolationAreaId: location.id,
            sex: sex,
            reportDate: _report.reportDate,
          )
        : await _service.openingBalanceFor(
            flockId: widget.flock.id,
            houseId: location.id,
            sex: sex,
            reportDate: _report.reportDate,
          );
    return _service.recordMovement(
      reportId: _report.id,
      houseId: location.isIsolation ? null : location.id,
      isolationAreaId: location.isIsolation ? location.id : null,
      sex: sex,
      opening: opening,
    );
  }

  Future<void> _applyChange(
    _EntryLocation location,
    String sex, {
    int? mortality,
    int? culls,
    int? sale,
    int? sexSpecificRemoval,
    int? transferIn,
    int? transferOut,
  }) async {
    final key = _key(location.id, sex);
    final current = _movements[key];
    if (current == null) return;
    final isFemale = sex == BreederBirdMovementSex.female;
    try {
      final updated = await _service.recordMovement(
        reportId: _report.id,
        houseId: location.isIsolation ? null : location.id,
        isolationAreaId: location.isIsolation ? location.id : null,
        sex: sex,
        opening: current.opening,
        mortality: mortality ?? current.mortality,
        culls: culls ?? current.culls,
        sale: sale ?? current.sale,
        kitchenRemoval: isFemale
            ? (sexSpecificRemoval ?? current.kitchenRemoval)
            : 0,
        euthanasia: !isFemale
            ? (sexSpecificRemoval ?? current.euthanasia)
            : 0,
        transferIn: transferIn ?? current.transferIn,
        transferOut: transferOut ?? current.transferOut,
      );
      setState(() {
        _movements[key] = updated;
        _error = null;
      });
    } on BreederLedgerValidationError catch (error) {
      setState(() => _error = error.message);
      // Revert the field's displayed text to the last-known-good value.
      final controllers = _controllers[key]!;
      controllers.mortality.text = '${current.mortality}';
      controllers.culls.text = '${current.culls}';
      controllers.sale.text = '${current.sale}';
      controllers.sexSpecificRemoval.text = '${current.sexSpecificRemoval}';
      controllers.transferIn.text = '${current.transferIn}';
      controllers.transferOut.text = '${current.transferOut}';
    }
  }

  int _parse(String text) => int.tryParse(text.trim()) ?? 0;
  double _parseDouble(String text) => double.tryParse(text.trim()) ?? 0;
  double? _parseOptionalDouble(String text) =>
      text.trim().isEmpty ? null : double.tryParse(text.trim());

  /// Records a feed-kilogram entry (breeder-flock-performance ticket 09).
  /// Grams per bird is never entered here — it is always recomputed for
  /// display from the location's already-recorded closing bird count via
  /// `BreederBirdLedgerService.feedGramsPerBird`.
  Future<void> _applyFeedChange(_EntryLocation location, String sex) async {
    final key = _key(location.id, sex);
    final controllers = _feedControllers[key];
    if (controllers == null) return;
    final feedKg = _parseDouble(controllers.feedKg.text);
    try {
      final updated = await _service.recordFeedEntry(
        reportId: _report.id,
        houseId: location.isIsolation ? null : location.id,
        isolationAreaId: location.isIsolation ? location.id : null,
        sex: sex,
        feedKg: feedKg,
      );
      setState(() {
        _feedEntries[key] = updated;
        _error = null;
      });
    } on BreederLedgerValidationError catch (error) {
      setState(() => _error = error.message);
      final current = _feedEntries[key];
      controllers.feedKg.text = _FeedFieldControllers._formatKg(
        current?.feedKg ?? 0,
      );
    }
  }

  /// Records one grade's egg count for [location] (breeder-flock
  /// -performance ticket 10). Total eggs, grade percentages, and
  /// production percent are never entered here — always recomputed for
  /// display from every grade's count via `BreederEggProductionService`.
  Future<void> _applyGradeCountChange(
    _EntryLocation location,
    String gradeId,
  ) async {
    final controllers = _eggControllers[location.id];
    final countController = controllers?.countByGradeId[gradeId];
    if (controllers == null || countController == null) return;
    final count = _parse(countController.text);
    try {
      final updated = await _eggProductionService.recordGradeCount(
        reportId: _report.id,
        houseId: location.isIsolation ? null : location.id,
        isolationAreaId: location.isIsolation ? location.id : null,
        gradeId: gradeId,
        count: count,
      );
      // Today's production feeds the egg-inventory available/closing
      // balance for this grade (breeder-flock-performance ticket 11) —
      // refresh it whenever a grade count changes, not just when an
      // inventory field itself changes.
      await _refreshInventoryBalance(gradeId);
      setState(() {
        final entries = _eggEntriesByLocation[location.id] ?? [];
        final index = entries.indexWhere((e) => e.gradeId == gradeId);
        if (index >= 0) {
          entries[index] = updated;
        } else {
          entries.add(updated);
        }
        _eggEntriesByLocation[location.id] = entries;
        _error = null;
      });
    } on BreederEggProductionValidationError catch (error) {
      setState(() => _error = error.message);
      final entries = _eggEntriesByLocation[location.id] ?? [];
      BreederEggProductionEntry? existing;
      for (final e in entries) {
        if (e.gradeId == gradeId) {
          existing = e;
          break;
        }
      }
      countController.text = '${existing?.count ?? 0}';
    }
  }

  /// Records the location-level egg weight (breeder-flock-performance
  /// ticket 10, design doc section 5.2.1: "Egg weight is in grams").
  Future<void> _applyEggWeightChange(_EntryLocation location) async {
    final controllers = _eggControllers[location.id];
    if (controllers == null) return;
    final text = controllers.eggWeightGrams.text.trim();
    if (text.isEmpty) return;
    final weight = double.tryParse(text);
    if (weight == null) return;
    try {
      await _eggProductionService.recordEggWeight(
        reportId: _report.id,
        houseId: location.isIsolation ? null : location.id,
        isolationAreaId: location.isIsolation ? location.id : null,
        eggWeightGrams: weight,
      );
      setState(() {
        final entries = _eggEntriesByLocation[location.id] ?? [];
        _eggEntriesByLocation[location.id] = [
          for (final e in entries) e.copyWith(eggWeightGrams: weight),
        ];
        _error = null;
      });
    } on BreederEggProductionValidationError catch (error) {
      setState(() => _error = error.message);
    }
  }

  /// Records one of the four plain egg-inventory movement kinds
  /// (dispatched/sold/kitchen/gifts) for [gradeId] (breeder-flock
  /// -performance ticket 11). Previous balance, today's production,
  /// available balance, and closing balance are never entered here — always
  /// recomputed via `BreederEggInventoryService.balanceFor`.
  Future<void> _applyInventoryChange(
    String gradeId,
    String kind,
    TextEditingController controller,
  ) async {
    final pendingKey = '$gradeId|$kind';
    if (!_pendingInventoryChanges.add(pendingKey)) return;
    try {
      final quantity = _parse(controller.text);
      await _eggInventoryService.recordMovement(
        report: _report,
        gradeId: gradeId,
        kind: kind,
        quantity: quantity,
      );
      await _refreshInventoryBalance(gradeId);
      setState(() => _error = null);
    } on BreederEggInventoryValidationError catch (error) {
      setState(() => _error = error.message);
      _revertInventoryField(gradeId, kind, controller);
    } on BreederEggInventoryStateError catch (error) {
      setState(() => _error = error.message);
      _revertInventoryField(gradeId, kind, controller);
    } finally {
      _pendingInventoryChanges.remove(pendingKey);
    }
  }

  void _revertInventoryField(
    String gradeId,
    String kind,
    TextEditingController controller,
  ) {
    final balance = _inventoryBalances[gradeId];
    if (balance == null) return;
    final previousValue = switch (kind) {
      BreederEggInventoryMovementKind.hatcheryDispatch => balance.dispatched,
      BreederEggInventoryMovementKind.sale => balance.sold,
      BreederEggInventoryMovementKind.kitchen => balance.kitchen,
      BreederEggInventoryMovementKind.gift => balance.gifts,
      _ => 0,
    };
    controller.text = '$previousValue';
  }

  /// Prompts for and records an approved adjustment (breeder-flock
  /// -performance ticket 11, design doc section 14: "Adjustments require a
  /// reason, an actor, and a time"). The time is always `DateTime.now()` at
  /// the moment of recording — never a free-typed field — and the actor is
  /// always the signed-in user, matching how [BreederDailyReportReviewScreen
  /// ._approve] resolves the acting user.
  Future<void> _promptAdjustment(String gradeId) async {
    final result = await showDialog<_AdjustmentInput>(
      context: context,
      builder: (dialogContext) => _AdjustmentDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await _eggInventoryService.recordAdjustment(
        report: _report,
        gradeId: gradeId,
        direction: result.direction,
        quantity: result.quantity,
        reason: result.reason,
        actorUserId: _actorUserId ?? 'unknown',
        occurredAt: DateTime.now(),
      );
      await _refreshInventoryBalance(gradeId);
      setState(() => _error = null);
    } on BreederEggInventoryValidationError catch (error) {
      setState(() => _error = error.message);
    }
  }

  /// Persists an edit to the report header (inside/outside temperature,
  /// light hours, notes — breeder-flock-performance ticket 09).
  Future<void> _applyHeaderChange() async {
    try {
      final updated = await _service.updateHeader(
        _report,
        insideTemperature: _parseOptionalDouble(_insideTempController.text),
        clearInsideTemperature: _insideTempController.text.trim().isEmpty,
        outsideTemperature: _parseOptionalDouble(_outsideTempController.text),
        clearOutsideTemperature: _outsideTempController.text.trim().isEmpty,
        lightHours: _parseOptionalDouble(_lightHoursController.text),
        clearLightHours: _lightHoursController.text.trim().isEmpty,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        clearNotes: _notesController.text.trim().isEmpty,
      );
      setState(() {
        _report = updated;
        _error = null;
      });
    } on BreederLedgerValidationError catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _goToReview() async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BreederDailyReportReviewScreen(
          flock: widget.flock,
          report: _report,
          service: _service,
          houseRepository: _houseRepository,
          isolationAreaRepository: _isolationAreaRepository,
          movementRepository: _movementRepository,
          reportRepository: _reportRepository,
          feedEntryRepository: _feedEntryRepository,
          eggGradeRepository: _eggGradeRepository,
          eggProductionEntryRepository: _eggProductionEntryRepository,
          eggProductionService: _eggProductionService,
          lifecycleService: _lifecycleService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: 'Daily Report Entry',
        actions: [
          TextButton(
            onPressed: _goToReview,
            child: Text(
              context.tr('Review'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_locations.isEmpty) {
            return Center(
              child: Text(
                context.tr('This flock has no houses yet.'),
                style: AppTextStyles.body,
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(AppSizes.cardPadding),
            children: [
              _buildHeaderCard(),
              const SizedBox(height: AppSizes.cardPadding),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.cardPadding),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              for (final location in _locations) _buildLocationCard(location),
              if (_hasEggSection) ...[
                const SizedBox(height: AppSizes.cardPadding),
                _buildInventorySection(),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Report-header edit section (breeder-flock-performance ticket 09,
  /// design doc section 5.1/5.2): inside/outside temperature (labelled with
  /// their own unit per the existing per-sector temperature convention —
  /// never a single global unit setting), light hours, and notes.
  Widget _buildHeaderCard() {
    return SectionCard(
      title: 'Report header',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: 140,
            child: TextField(
              key: const Key('header-insideTemperature'),
              controller: _insideTempController,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: context.tr('Inside temperature'),
                suffixText: '°C',
              ),
              onSubmitted: (_) => _applyHeaderChange(),
              onEditingComplete: _applyHeaderChange,
            ),
          ),
          SizedBox(
            width: 140,
            child: TextField(
              key: const Key('header-outsideTemperature'),
              controller: _outsideTempController,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: context.tr('Outside temperature'),
                suffixText: '°C',
              ),
              onSubmitted: (_) => _applyHeaderChange(),
              onEditingComplete: _applyHeaderChange,
            ),
          ),
          SizedBox(
            width: 120,
            child: TextField(
              key: const Key('header-lightHours'),
              controller: _lightHoursController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: context.tr('Light hours'),
                suffixText: context.tr('hrs'),
              ),
              onSubmitted: (_) => _applyHeaderChange(),
              onEditingComplete: _applyHeaderChange,
            ),
          ),
          SizedBox(
            width: 260,
            child: TextField(
              key: const Key('header-notes'),
              controller: _notesController,
              decoration: InputDecoration(labelText: context.tr('Notes')),
              onSubmitted: (_) => _applyHeaderChange(),
              onEditingComplete: _applyHeaderChange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard(_EntryLocation location) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.cardPadding),
      child: SectionCard(
        child: Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
            key: PageStorageKey('location-${location.id}'),
            initiallyExpanded: true,
            tilePadding: EdgeInsets.zero,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  location.name,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (location.isIsolation) ...[
                  const SizedBox(width: 8),
                  Chip(
                    key: Key('isolation-badge-${location.id}'),
                    label: Text(context.tr('Isolation')),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ],
            ),
            children: [
              _buildSexSection(
                location,
                BreederBirdMovementSex.female,
                'Females',
              ),
              const SizedBox(height: 12),
              _buildSexSection(location, BreederBirdMovementSex.male, 'Males'),
              if (_hasEggSection) ...[
                const SizedBox(height: 12),
                _buildEggSection(location),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSexSection(_EntryLocation location, String sex, String label) {
    final key = _key(location.id, sex);
    final movement = _movements[key];
    final controllers = _controllers[key];
    final feedControllers = _feedControllers[key];
    if (movement == null || controllers == null) return const SizedBox.shrink();
    final isFemale = sex == BreederBirdMovementSex.female;
    final feedKg = feedControllers != null
        ? _parseDouble(feedControllers.feedKg.text)
        : (_feedEntries[key]?.feedKg ?? 0);
    final gramsPerBird = BreederBirdLedgerService.feedGramsPerBird(
      feedKg: feedKg,
      closingLiveBirds: movement.closing,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _readOnlyField('Opening', movement.opening),
            _numberField(
              key: '$key-mortality',
              label: 'Mortality',
              controller: controllers.mortality,
              onChanged: (v) =>
                  _applyChange(location, sex, mortality: _parse(v)),
            ),
            _numberField(
              key: '$key-culls',
              label: 'Culls/Sorts',
              controller: controllers.culls,
              onChanged: (v) => _applyChange(location, sex, culls: _parse(v)),
            ),
            _numberField(
              key: '$key-sale',
              label: 'Sale',
              controller: controllers.sale,
              onChanged: (v) => _applyChange(location, sex, sale: _parse(v)),
            ),
            _numberField(
              key: '$key-sexSpecific',
              label: isFemale ? 'Kitchen removal' : 'Euthanasia',
              controller: controllers.sexSpecificRemoval,
              onChanged: (v) =>
                  _applyChange(location, sex, sexSpecificRemoval: _parse(v)),
            ),
            _numberField(
              key: '$key-transferIn',
              label: 'Transfer in',
              controller: controllers.transferIn,
              onChanged: (v) =>
                  _applyChange(location, sex, transferIn: _parse(v)),
            ),
            _numberField(
              key: '$key-transferOut',
              label: 'Transfer out',
              controller: controllers.transferOut,
              onChanged: (v) =>
                  _applyChange(location, sex, transferOut: _parse(v)),
            ),
            _readOnlyField('Closing', movement.closing),
            if (feedControllers != null)
              SizedBox(
                width: 110,
                child: TextField(
                  key: Key('$key-feedKg'),
                  controller: feedControllers.feedKg,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: context.tr('Feed (kg)'),
                  ),
                  onSubmitted: (_) => _applyFeedChange(location, sex),
                  onEditingComplete: () => _applyFeedChange(location, sex),
                ),
              ),
            // Grams-per-bird is always computed, never a text field a user
            // can type into (design doc section 7: "feed grams per bird ...
            // never typed").
            _readOnlyTextField(
              'Feed (g/bird)',
              gramsPerBird == null ? '—' : '$gramsPerBird',
              key: '$key-feedGramsPerBird',
            ),
          ],
        ),
      ],
    );
  }

  /// Egg-grade entry for one location (breeder-flock-performance ticket
  /// 10, design doc section 5.2 and 5.2.1): one count field per active
  /// grade, one shared egg-weight field, plus read-only calculated total
  /// eggs, grade percentages, and production percent. States the grade
  /// -partition rule so the "grades must sum to total" review validation
  /// (design section 14) is never a surprise.
  Widget _buildEggSection(_EntryLocation location) {
    final controllers = _eggControllers[location.id];
    if (controllers == null) return const SizedBox.shrink();
    final movementFemale = _movements[_key(location.id, BreederBirdMovementSex.female)];
    final countsByGrade = <String, int>{
      for (final grade in _grades)
        grade.id: _parse(controllers.countByGradeId[grade.id]?.text ?? '0'),
    };
    final total = BreederEggProductionService.totalEggs(countsByGrade.values);
    final productionPercent = location.isIsolation
        ? BreederEggProductionService.isolationProductionPercent(
            totalEggsIsolationScope: total,
            closingLiveFemalesIsolationScope: movementFemale?.closing,
          )
        : BreederEggProductionService.dailyProductionPercent(
            totalEggsHouseScope: total,
            closingLiveFemalesHouseScope: movementFemale?.closing,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('Egg production'),
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            context.tr(
              'Every egg counts once, under the highest-priority grade it '
              'matches (e.g. a cracked double-yolk egg counts as cracked). '
              'Grade counts always sum to total eggs.',
            ),
            style: AppTextStyles.body.copyWith(fontSize: 11),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final grade in _grades)
              _numberField(
                key: 'egg-${location.id}-${grade.code}',
                label: grade.name,
                controller: controllers.countByGradeId[grade.id]!,
                onChanged: (_) => _applyGradeCountChange(location, grade.id),
              ),
            _readOnlyField(
              'Total eggs',
              total,
              key: 'egg-${location.id}-totalEggs',
            ),
            _readOnlyTextField(
              'Production %',
              productionPercent == null ? '—' : '$productionPercent',
              key: 'egg-${location.id}-productionPercent',
            ),
            SizedBox(
              width: 120,
              child: TextField(
                key: Key('egg-${location.id}-eggWeight'),
                controller: controllers.eggWeightGrams,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: context.tr('Egg weight'),
                  suffixText: context.tr('g'),
                ),
                onSubmitted: (_) => _applyEggWeightChange(location),
                onEditingComplete: () => _applyEggWeightChange(location),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Flock-level egg-inventory ledger, one row per active grade
  /// (breeder-flock-performance ticket 11, design doc section 5.2): previous
  /// balance, today's production, available balance, dispatched, sold,
  /// kitchen, gifts, and closing balance. Previous balance, today's
  /// production, available balance, and closing balance are always
  /// read-only computed cells — this section never gives them a text field.
  Widget _buildInventorySection() {
    return SectionCard(
      title: 'Egg inventory',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final grade in _grades) _buildInventoryRow(grade),
        ],
      ),
    );
  }

  Widget _buildInventoryRow(BreederEggGradeDefinition grade) {
    final balance = _inventoryBalances[grade.id];
    final controllers = _inventoryControllers[grade.id];
    if (balance == null || controllers == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                grade.name,
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton.icon(
                key: Key('inventory-${grade.code}-adjust'),
                onPressed: () => _promptAdjustment(grade.id),
                icon: const Icon(Icons.tune, size: 16),
                label: Text(context.tr('Adjustment')),
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _readOnlyField(
                'Previous balance',
                balance.previousBalance,
                key: 'inventory-${grade.code}-previous',
              ),
              _readOnlyField(
                'Today\'s production',
                balance.todaysProduction,
                key: 'inventory-${grade.code}-production',
              ),
              _readOnlyField(
                'Available balance',
                balance.availableBalance,
                key: 'inventory-${grade.code}-available',
              ),
              _numberField(
                key: 'inventory-${grade.code}-dispatched',
                label: 'Dispatched to hatchery',
                controller: controllers.dispatched,
                onChanged: (_) => _applyInventoryChange(
                  grade.id,
                  BreederEggInventoryMovementKind.hatcheryDispatch,
                  controllers.dispatched,
                ),
              ),
              _numberField(
                key: 'inventory-${grade.code}-sold',
                label: 'Sold',
                controller: controllers.sold,
                onChanged: (_) => _applyInventoryChange(
                  grade.id,
                  BreederEggInventoryMovementKind.sale,
                  controllers.sold,
                ),
              ),
              _numberField(
                key: 'inventory-${grade.code}-kitchen',
                label: 'Kitchen',
                controller: controllers.kitchen,
                onChanged: (_) => _applyInventoryChange(
                  grade.id,
                  BreederEggInventoryMovementKind.kitchen,
                  controllers.kitchen,
                ),
              ),
              _numberField(
                key: 'inventory-${grade.code}-gifts',
                label: 'Gifts',
                controller: controllers.gifts,
                onChanged: (_) => _applyInventoryChange(
                  grade.id,
                  BreederEggInventoryMovementKind.gift,
                  controllers.gifts,
                ),
              ),
              _readOnlyField(
                'Closing balance',
                balance.closingBalance,
                key: 'inventory-${grade.code}-closing',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numberField({
    required String key,
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) {
    return SizedBox(
      width: 110,
      child: TextField(
        key: Key(key),
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: context.tr(label)),
        onSubmitted: onChanged,
        onEditingComplete: () => onChanged(controller.text),
      ),
    );
  }

  Widget _readOnlyField(String label, int value, {String? key}) {
    return SizedBox(
      width: 90,
      child: InputDecorator(
        key: key == null ? null : Key(key),
        decoration: InputDecoration(labelText: context.tr(label)),
        child: Text('$value', style: AppTextStyles.body),
      ),
    );
  }

  /// Like [_readOnlyField], but for an already-formatted string value (used
  /// for the derived feed-grams-per-bird display, which can be blank rather
  /// than a number — design doc section 7.2).
  Widget _readOnlyTextField(String label, String value, {required String key}) {
    return SizedBox(
      width: 110,
      child: InputDecorator(
        key: Key(key),
        decoration: InputDecoration(labelText: context.tr(label)),
        child: Text(value, style: AppTextStyles.body),
      ),
    );
  }
}

/// The result of [_AdjustmentDialog] — quantity, direction, and reason for
/// one approved egg-inventory adjustment (breeder-flock-performance ticket
/// 11, design doc section 14: "Adjustments require a reason, an actor, and
/// a time"). Actor and time are resolved by the caller, never by this
/// dialog.
class _AdjustmentInput {
  final String direction;
  final int quantity;
  final String reason;

  const _AdjustmentInput({
    required this.direction,
    required this.quantity,
    required this.reason,
  });
}

/// Prompts for an approved egg-inventory adjustment's direction, quantity,
/// and reason (breeder-flock-performance ticket 11). The reason field is
/// deliberately required to submit — an adjustment without one is invalid
/// (design section 14) — enforced here as well as by
/// `BreederEggInventoryService.recordAdjustment` and the database CHECK
/// constraint, so a user gets immediate feedback rather than a thrown error.
class _AdjustmentDialog extends StatefulWidget {
  @override
  State<_AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends State<_AdjustmentDialog> {
  String _direction = BreederEggInventoryAdjustmentDirection.increase;
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _submit() {
    final quantity = int.tryParse(_quantityController.text.trim());
    final reason = _reasonController.text.trim();
    if (quantity == null || quantity < 0) {
      setState(() => _validationError = 'Enter a non-negative quantity');
      return;
    }
    if (reason.isEmpty) {
      setState(() => _validationError = 'A reason is required');
      return;
    }
    Navigator.of(context).pop(
      _AdjustmentInput(direction: _direction, quantity: quantity, reason: reason),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('Approved adjustment')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: const Key('adjustment-direction'),
            initialValue: _direction,
            decoration: InputDecoration(labelText: context.tr('Direction')),
            items: [
              DropdownMenuItem(
                value: BreederEggInventoryAdjustmentDirection.increase,
                child: Text(context.tr('Increase')),
              ),
              DropdownMenuItem(
                value: BreederEggInventoryAdjustmentDirection.decrease,
                child: Text(context.tr('Decrease')),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _direction = value);
            },
          ),
          TextField(
            key: const Key('adjustment-quantity'),
            controller: _quantityController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: context.tr('Quantity')),
          ),
          TextField(
            key: const Key('adjustment-reason'),
            controller: _reasonController,
            decoration: InputDecoration(labelText: context.tr('Reason')),
          ),
          if (_validationError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _validationError!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Cancel')),
        ),
        ElevatedButton(
          key: const Key('adjustment-submit'),
          onPressed: _submit,
          child: Text(context.tr('Save')),
        ),
      ],
    );
  }
}
