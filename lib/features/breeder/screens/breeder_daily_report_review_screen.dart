import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/breeder_bird_movement_model.dart';
import '../../../data/models/breeder_daily_report_model.dart';
import '../../../data/models/breeder_egg_grade_definition_model.dart';
import '../../../data/models/breeder_egg_production_entry_model.dart';
import '../../../data/models/breeder_feed_entry_model.dart';
import '../../../data/models/breeder_isolation_area_model.dart';
import '../../../data/models/flock_model.dart';
import '../../../data/models/poultry_hierarchy_models.dart';
import '../../../data/repositories/breeder_benchmark_repository.dart';
import '../../../data/repositories/breeder_bird_movement_repository.dart';
import '../../../data/repositories/breeder_daily_report_repository.dart';
import '../../../data/repositories/breeder_egg_grade_definition_repository.dart';
import '../../../data/models/breeder_egg_inventory_movement_model.dart';
import '../../../data/repositories/breeder_egg_inventory_movement_repository.dart';
import '../../../data/repositories/breeder_egg_production_entry_repository.dart';
import '../../../data/repositories/breeder_feed_entry_repository.dart';
import '../../../data/models/breeder_report_revision_model.dart';
import '../../../data/repositories/breeder_isolation_area_repository.dart';
import '../../../data/repositories/breeder_report_revision_repository.dart';
import '../../../data/repositories/poultry_hierarchy_repository.dart';
import '../../../services/breeder/breeder_bird_ledger_service.dart';
import '../../../services/breeder/breeder_egg_inventory_service.dart';
import '../../../services/breeder/breeder_egg_production_service.dart';
import '../../../services/breeder/breeder_flock_lifecycle_service.dart';
import '../../../services/breeder/breeder_report_revision_service.dart';
import '../../../widgets/section_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../services/breeder_report_composition.dart';
import '../services/breeder_report_pdf_export.dart';
import 'breeder_daily_report_entry_screen.dart';
import 'breeder_report_conflict_resolution_screen.dart';

/// The consolidated one-table review of a daily report (breeder-flock
/// -performance ticket 07, design doc section 5.3: "the final review
/// transforms the entries into one table matching the familiar paper
/// report"). All houses and isolation areas (ticket 08) are presented
/// together here regardless of how many screens the house-by-house entry
/// took.
///
/// From here a Draft report can be returned to entry for correction, a
/// Draft report can be submitted, and a Submitted report can be approved by
/// a production-manager role or higher (design doc section 5.3).
class BreederDailyReportReviewScreen extends StatefulWidget {
  final FlockModel flock;
  final BreederDailyReport report;
  final BreederBirdLedgerService? service;
  final PoultryHierarchyRepository? houseRepository;
  final BreederIsolationAreaRepository? isolationAreaRepository;
  final BreederBirdMovementRepository? movementRepository;
  final BreederDailyReportRepository? reportRepository;
  final BreederFeedEntryRepository? feedEntryRepository;
  final BreederFlockLifecycleService? lifecycleService;
  final BreederEggGradeDefinitionRepository? eggGradeRepository;
  final BreederEggProductionEntryRepository? eggProductionEntryRepository;
  final BreederEggProductionService? eggProductionService;
  final BreederEggInventoryMovementRepository? eggInventoryMovementRepository;
  final BreederEggInventoryService? eggInventoryService;
  final BreederReportRevisionRepository? revisionRepository;
  final BreederReportRevisionService? revisionService;
  final BreederBenchmarkRepository? benchmarkRepository;

  /// Renders the print/export PDF (breeder-flock-performance ticket 19).
  /// Overridable so widget tests can assert on the built
  /// `BreederReportComposition` without invoking the platform print sheet.
  final BreederReportPdfExport? pdfExport;

  /// Overrides the acting user's id/role instead of reading
  /// `AuthProvider.user`. Exists so widget tests can exercise the
  /// approval-role gate without wiring a full auth stack.
  final String? actorUserIdOverride;
  final String? actorRoleOverride;

  const BreederDailyReportReviewScreen({
    super.key,
    required this.flock,
    required this.report,
    this.service,
    this.houseRepository,
    this.isolationAreaRepository,
    this.movementRepository,
    this.reportRepository,
    this.feedEntryRepository,
    this.lifecycleService,
    this.eggGradeRepository,
    this.eggProductionEntryRepository,
    this.eggProductionService,
    this.eggInventoryMovementRepository,
    this.eggInventoryService,
    this.revisionRepository,
    this.revisionService,
    this.benchmarkRepository,
    this.pdfExport,
    this.actorUserIdOverride,
    this.actorRoleOverride,
  });

  @override
  State<BreederDailyReportReviewScreen> createState() =>
      _BreederDailyReportReviewScreenState();
}

class _BreederDailyReportReviewScreenState
    extends State<BreederDailyReportReviewScreen> {
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
  late final BreederEggGradeDefinitionRepository _eggGradeRepository =
      widget.eggGradeRepository ?? BreederEggGradeDefinitionRepository();
  late final BreederEggProductionEntryRepository _eggProductionEntryRepository =
      widget.eggProductionEntryRepository ??
      BreederEggProductionEntryRepository();
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
  late final BreederReportRevisionRepository _revisionRepository =
      widget.revisionRepository ?? BreederReportRevisionRepository();
  late final BreederReportRevisionService _revisionService =
      widget.revisionService ??
      BreederReportRevisionService(
        revisionRepository: _revisionRepository,
        reportRepository: _reportRepository,
      );
  late final BreederBirdLedgerService _service =
      widget.service ??
      BreederBirdLedgerService(
        reportRepository: _reportRepository,
        movementRepository: _movementRepository,
        houseRepository: _houseRepository,
        isolationAreaRepository: _isolationAreaRepository,
        feedEntryRepository: _feedEntryRepository,
        eggInventoryService: _eggInventoryService,
        revisionService: _revisionService,
      );
  late final BreederFlockLifecycleService _lifecycleService =
      widget.lifecycleService ?? BreederFlockLifecycleService();
  late final BreederBenchmarkRepository _benchmarkRepository =
      widget.benchmarkRepository ?? BreederBenchmarkRepository();
  late final BreederReportPdfExport _pdfExport =
      widget.pdfExport ?? const BreederReportPdfExport();

  late BreederDailyReport _report;
  late Future<_ReviewData> _dataFuture;
  _ReviewData? _lastLoadedData;
  String? _error;

  @override
  void initState() {
    super.initState();
    _report = widget.report;
    _dataFuture = _load();
  }

  Future<_ReviewData> _load() async {
    final houses = await _houseRepository.listHouses(widget.flock.id);
    final isolationAreas = await _isolationAreaRepository.listAreas(
      widget.flock.id,
    );
    final movements = await _movementRepository.getForReport(_report.id);
    final feedEntries = await _feedEntryRepository.getForReport(_report.id);
    final productionWeek = await _lifecycleService.officialProductionWeek(
      widget.flock,
      now: _report.reportDate,
    );
    // The egg section only appears once the flock has entered the
    // benchmark profile's official production range (design doc section
    // 5.1) — delegated entirely to `BreederFlockLifecycleService`, never
    // re-derived here.
    final hasEggSection = !productionWeek.isPreProduction;
    final grades = hasEggSection
        ? await _eggGradeRepository.listActiveGrades()
        : const <BreederEggGradeDefinition>[];
    final eggEntries = hasEggSection
        ? await _eggProductionEntryRepository.getForReport(_report.id)
        : const <BreederEggProductionEntry>[];
    // Egg-inventory balances (breeder-flock-performance ticket 11) — one
    // per active grade, gated on the same "entered production" flag as egg
    // production, since the paper form's inventory section only exists
    // once a flock is laying.
    final inventoryBalances = hasEggSection
        ? await _eggInventoryService.balancesForReport(
            _report,
            flockId: widget.flock.id,
          )
        : const <BreederEggInventoryBalance>[];
    // Raw egg-inventory movement rows (breeder-flock-performance ticket
    // 12) — the correction dialog needs the actual correctable rows
    // (id/kind/quantity), not just the derived per-grade balance
    // [inventoryBalances] already carries.
    final inventoryMovements = hasEggSection
        ? await _eggInventoryMovementRepository.getForReport(_report.id)
        : const <BreederEggInventoryMovement>[];
    // Display precision for every derived value this report prints comes
    // from `breeder_metric_definitions.displayPrecision` (ticket 03), never
    // a hard-coded decimal count (breeder-flock-performance ticket 19).
    final metricDefinitions = await _benchmarkRepository.getMetricDefinitions();
    final data = _ReviewData(
      houses: houses,
      isolationAreas: isolationAreas,
      movements: movements,
      feedEntries: feedEntries,
      productionWeek: productionWeek,
      hasEggSection: hasEggSection,
      grades: grades,
      eggEntries: eggEntries,
      inventoryBalances: inventoryBalances,
      inventoryMovements: inventoryMovements,
      metrics: BreederReportMetricFormatter(metricDefinitions),
    );
    _lastLoadedData = data;
    return data;
  }

  /// The single composition consumed by both the on-screen tables below and
  /// [_printOrExport] (breeder-flock-performance ticket 19, design section
  /// 5.3: "the consolidated review table is the same view used for
  /// printing and export"). Rebuilt from the current [_report] every time
  /// it is needed, so an Approved report always composes from its latest
  /// approved revision (`_report.revision`), never a stale snapshot.
  BreederReportComposition _composeReport(_ReviewData data) {
    return buildBreederReportComposition(
      report: _report,
      flock: widget.flock,
      age: _lifecycleService.ageSummary(widget.flock, now: _report.reportDate),
      productionWeek: data.productionWeek,
      houses: data.houses,
      isolationAreas: data.isolationAreas,
      movements: data.movements,
      feedEntries: data.feedEntries,
      hasEggSection: data.hasEggSection,
      grades: data.grades,
      eggEntries: data.eggEntries,
      inventoryBalances: data.inventoryBalances,
      metrics: data.metrics,
      formatDate: HatchDateUtils.formatDisplayDate,
      weekdayName: HatchDateUtils.weekdayName,
    );
  }

  /// Opens the OS print/export sheet for the current report (ticket 19).
  /// Re-reads the report row first so a print immediately after an
  /// approval/correction always reflects the latest saved revision rather
  /// than a widget-state value that might predate it.
  Future<void> _printOrExport() async {
    final isArabic = context.l10n.isArabic;
    final translate = context.l10n.translate;
    final refreshed = await _reportRepository.getById(_report.id) ?? _report;
    final data = _lastLoadedData;
    if (data == null) return;
    if (!mounted) return;
    if (refreshed.revision != _report.revision) {
      setState(() => _report = refreshed);
    } else {
      _report = refreshed;
    }
    final composition = _composeReport(data);
    await _pdfExport.printOrShare(
      composition: composition,
      flockLabel: widget.flock.breed,
      reportDateLabel: HatchDateUtils.formatDisplayDate(_report.reportDate),
      rtl: isArabic,
      translate: translate,
    );
  }

  Future<void> _editEntries() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BreederDailyReportEntryScreen(
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
          eggInventoryMovementRepository: _eggInventoryMovementRepository,
          eggInventoryService: _eggInventoryService,
          lifecycleService: _lifecycleService,
        ),
      ),
    );
    if (mounted) {
      setState(() => _dataFuture = _load());
    }
  }

  String? get _actorUserId =>
      widget.actorUserIdOverride ?? context.read<AuthProvider>().user?.id;
  String? get _actorRole =>
      widget.actorRoleOverride ?? context.read<AuthProvider>().user?.role;

  Future<void> _submit() async {
    try {
      final updated = await _service.submit(
        _report,
        actorUserId: _actorUserId ?? 'unknown',
      );
      if (!mounted) return;
      setState(() {
        _report = updated;
        _error = null;
      });
    } on BreederLedgerValidationError catch (error) {
      setState(() => _error = error.message);
    } on BreederReportStateError catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _approve() async {
    try {
      // Egg-production approval snapshot (breeder-flock-performance ticket
      // 10, design doc section 7.1): retain the denominator actually used,
      // the benchmark profile version, and the comparison axis, so the
      // approved report stays auditable even if the benchmark profile or
      // milestones change later. Only meaningful once the flock has
      // entered egg production; otherwise all three stay null.
      int? denominatorFemales;
      String? profileVersion;
      String? axisDescription;
      final data = _lastLoadedData;
      if (data != null && data.hasEggSection) {
        denominatorFemales = BreederEggProductionService.closingFemalesHouseScope(
          data.movements,
        );
        final axisOffer = await _lifecycleService.comparisonAxes(
          widget.flock,
          now: _report.reportDate,
        );
        profileVersion = axisOffer.profile?.guideVersion;
        axisDescription = axisOffer.official.axis.toString();
      }
      final updated = await _service.approve(
        _report,
        actorUserId: _actorUserId ?? 'unknown',
        actorRole: _actorRole,
        eggProductionDenominatorFemales: denominatorFemales,
        benchmarkProfileVersionAtApproval: profileVersion,
        comparisonAxisAtApproval: axisDescription,
      );
      if (!mounted) return;
      setState(() {
        _report = updated;
        _error = null;
      });
    } on BreederReportStateError catch (error) {
      setState(() => _error = error.message);
    } on BreederEggInventoryValidationError catch (error) {
      // Design section 14: "Inventory equations must balance before
      // approval, and a report that does not balance cannot be approved" —
      // surfaced through the same approve() call, not a separate check.
      setState(() => _error = error.message);
    }
  }

  /// Opens the "Correct report" dialog for an Approved report
  /// (breeder-flock-performance ticket 12, design doc section 5.3: "Any
  /// correction after approval requires a reason"). The dialog first asks
  /// WHAT is being corrected — the header, or one already-recorded child
  /// row (a bird movement, a feed entry, an egg-production count, or an
  /// egg-inventory movement) — since a wrong mortality count, a transposed
  /// cull, or a miscounted egg grade is what actually gets corrected in
  /// practice, not the header. Whichever target is picked, the reason
  /// field is required before the dialog's Save button does anything.
  Future<void> _correctReport() async {
    final data = _lastLoadedData;
    if (data == null) return;
    final result = await showDialog<_CorrectionResult>(
      context: context,
      builder: (dialogContext) => _CorrectionDialog(
        report: _report,
        houses: data.houses,
        isolationAreas: data.isolationAreas,
        movements: data.movements,
        feedEntries: data.feedEntries,
        hasEggSection: data.hasEggSection,
        grades: data.grades,
        eggEntries: data.eggEntries,
        inventoryMovements: data.inventoryMovements,
      ),
    );
    if (result == null) return;

    final actorUserId = _actorUserId ?? 'unknown';
    try {
      BreederDailyReport updated;
      switch (result.kind) {
        case _CorrectionKind.header:
          updated = await _service.correctHeader(
            _report,
            reason: result.reason,
            actorUserId: actorUserId,
            insideTemperature: result.insideTemperature,
            clearInsideTemperature: result.insideTemperature == null,
            outsideTemperature: result.outsideTemperature,
            clearOutsideTemperature: result.outsideTemperature == null,
            lightHours: result.lightHours,
            clearLightHours: result.lightHours == null,
            notes: result.notes,
            clearNotes: result.notes == null || result.notes!.isEmpty,
          );
        case _CorrectionKind.movement:
          updated = await _service.correctMovement(
            _report,
            movementId: result.movementId!,
            reason: result.reason,
            actorUserId: actorUserId,
            mortality: result.mortality,
            culls: result.culls,
            sale: result.sale,
            kitchenRemoval: result.kitchenRemoval,
            euthanasia: result.euthanasia,
            transferIn: result.transferIn,
            transferOut: result.transferOut,
          );
        case _CorrectionKind.feed:
          updated = await _service.correctFeedEntry(
            _report,
            feedEntryId: result.feedEntryId!,
            feedKg: result.feedKg!,
            reason: result.reason,
            actorUserId: actorUserId,
          );
        case _CorrectionKind.eggProduction:
          updated = await _service.correctEggProductionEntry(
            _report,
            entryId: result.eggEntryId!,
            count: result.eggCount!,
            reason: result.reason,
            actorUserId: actorUserId,
          );
        case _CorrectionKind.eggInventory:
          updated = await _service.correctEggInventoryMovement(
            _report,
            movementId: result.inventoryMovementId!,
            quantity: result.inventoryQuantity!,
            reason: result.reason,
            actorUserId: actorUserId,
          );
      }
      if (!mounted) return;
      setState(() {
        _report = updated;
        _error = null;
        _dataFuture = _load();
      });
    } on BreederReportCorrectionError catch (error) {
      setState(() => _error = error.message);
    } on BreederLedgerValidationError catch (error) {
      setState(() => _error = error.message);
    } on BreederReportStateError catch (error) {
      setState(() => _error = error.message);
    } on BreederEggInventoryValidationError catch (error) {
      setState(() => _error = error.message);
    }
  }

  /// Shows the full revision history for this report (breeder-flock
  /// -performance ticket 12, design doc section 5.3: "creates permanent
  /// revision history") — who changed it, when, which field, from what to
  /// what, and the stated reason for every correction ever made.
  Future<void> _showRevisionHistory() async {
    final history = await _revisionService.historyFor(_report.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _RevisionHistoryDialog(revisions: history),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canApprove = BreederApprovalRole.canApprove(_actorRole);

    return Scaffold(
      appBar: GradientAppBar(title: 'Daily Report Review'),
      body: FutureBuilder<_ReviewData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final composition = _composeReport(data);
          // A plain Column, not ListView: this page is a fixed-length
          // static layout (header, two tables, actions), not a long list.
          // ListView's SliverList only builds children near the viewport,
          // which silently drops the actions row off-screen below the
          // tables.
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(data),
                const SizedBox(height: AppSizes.cardPadding),
                if (_report.isSyncConflict) ...[
                  _buildSyncConflictBanner(),
                  const SizedBox(height: AppSizes.cardPadding),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: AppSizes.cardPadding,
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                _buildMovementTable(data, composition.femaleMovements),
                const SizedBox(height: AppSizes.cardPadding),
                _buildMovementTable(data, composition.maleMovements),
                const SizedBox(height: AppSizes.cardPadding),
                if (composition.eggProduction != null &&
                    composition.eggInventory != null) ...[
                  _buildEggTable(data, composition.eggProduction!),
                  const SizedBox(height: AppSizes.cardPadding),
                  _buildInventoryTable(data, composition.eggInventory!),
                  const SizedBox(height: AppSizes.cardPadding),
                  _buildComparisonNote(),
                  const SizedBox(height: AppSizes.cardPadding),
                ],
                _buildActions(canApprove),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Banner shown when this report is in `Sync Conflict`
  /// (breeder-flock-performance ticket 15, design doc section 5.3): visible
  /// from any state, links to the resolution screen, and blocks nothing
  /// here itself — submit/approve are already refused by
  /// `BreederBirdLedgerService` while the report is in this state.
  Widget _buildSyncConflictBanner() {
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Row(
          children: [
            const Icon(Icons.sync_problem, color: Colors.amber),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'This report has a sync conflict. It cannot be submitted '
                'or approved until it is resolved.',
              ),
            ),
            ElevatedButton(
              onPressed: _openConflictResolution,
              child: Text(context.tr('Resolve')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openConflictResolution() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BreederReportConflictResolutionScreen(
          reportId: _report.id,
        ),
      ),
    );
    final refreshed = await _reportRepository.getById(_report.id);
    if (!mounted || refreshed == null) return;
    setState(() {
      _report = refreshed;
      _dataFuture = _load();
    });
  }

  /// Renders the header band and both tables from the single
  /// [BreederReportComposition] (breeder-flock-performance ticket 19,
  /// design section 5.3: "the consolidated review table is the same view
  /// used for printing and export") — the on-screen `DataTable`s below and
  /// the printed PDF (`BreederReportPdfExport`) both read from the exact
  /// same computed rows, so they can never drift apart.
  Widget _buildHeader(_ReviewData data) {
    final composition = _composeReport(data);
    return SectionCard(
      title: 'Report header',
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          for (final field in composition.headerFields)
            _headerField(field.label, field.value),
          _headerField('State', composition.stateLabel),
          if (composition.isApproved)
            _headerField('Revision', '${composition.revisionNumber}'),
        ],
      ),
    );
  }

  Widget _headerField(String label, String value) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(label),
            style: AppTextStyles.body.copyWith(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          Text(value, style: AppTextStyles.body),
        ],
      ),
    );
  }

  Widget _buildMovementTable(_ReviewData data, BreederReportTable table) {
    return SectionCard(
      title: table.title,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            for (final c in table.columns) DataColumn(label: Text(context.tr(c))),
          ],
          rows: [
            for (final row in table.rows)
              DataRow(cells: [for (final cell in row) DataCell(Text(cell))]),
          ],
        ),
      ),
    );
  }

  /// Egg production by location (breeder-flock-performance ticket 10,
  /// design doc section 5.2 and 7): one row per house/isolation area, one
  /// column per active grade (count and percentage), plus calculated total
  /// eggs, calculated production percent, and egg weight. Houses and
  /// isolation are both shown, but isolation's production percent uses its
  /// own denominator (design section 7.1) — never mixed with the house
  /// figure.
  Widget _buildEggTable(_ReviewData data, BreederReportTable table) {
    return SectionCard(
      title: table.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              context.tr(
                'Every egg is counted once, under the highest-priority '
                'grade it matches (e.g. a cracked double-yolk egg counts as '
                'cracked). Grade counts always sum to total eggs.',
              ),
              style: AppTextStyles.body.copyWith(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                for (final c in table.columns)
                  DataColumn(label: Text(context.tr(c))),
              ],
              rows: [
                for (final row in table.rows)
                  DataRow(
                    cells: [for (final cell in row) DataCell(Text(cell))],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Flock-level egg-inventory ledger, one row per active grade
  /// (breeder-flock-performance ticket 11, design doc section 5.2 and 7):
  /// previous balance, today's production, available balance, dispatched,
  /// sold, kitchen, gifts, and closing balance — all sourced from
  /// `BreederEggInventoryService.balancesForReport`, never recomputed here.
  Widget _buildInventoryTable(_ReviewData data, BreederReportTable table) {
    return SectionCard(
      title: table.title,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            for (final c in table.columns) DataColumn(label: Text(context.tr(c))),
          ],
          rows: [
            for (final row in table.rows)
              DataRow(cells: [for (final cell in row) DataCell(Text(cell))]),
          ],
        ),
      ),
    );
  }

  /// Design doc section 7.3: "official hen-week and hen-housed production
  /// are defined on different denominators" than this report's local
  /// production percent (which divides by closing live females in
  /// production houses, per the approved paper report). Per the Ross 308
  /// profile's own provenance notes, the profile's hen-week column assumes
  /// 8% cumulative in-lay mortality; there is no hen-day column in that
  /// profile, so this note deliberately never uses that term.
  Widget _buildComparisonNote() {
    return SectionCard(
      title: 'About this comparison',
      child: Text(
        context.tr(
          'This local production percent divides by closing live females '
          'in production houses, matching the operating paper report. '
          'Official hen-week and hen-housed production targets use a '
          'different denominator (hen-week assumes 8% cumulative in-lay '
          'mortality), so a comparison against those targets carries a '
          'small systematic bias, larger after heavy mortality or '
          'depletion. The denominator used here is retained on approval '
          'for auditability.',
        ),
        style: AppTextStyles.body.copyWith(
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildActions(bool canApprove) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Print/export (breeder-flock-performance ticket 19) is offered in
        // every state, not just Approved — a Draft or Submitted report is
        // still the same familiar paper-report table, and a farm may want
        // a printed copy before approval reaches it.
        OutlinedButton.icon(
          key: const Key('printOrExportButton'),
          onPressed: _printOrExport,
          icon: const Icon(Icons.print_outlined),
          label: Text(context.tr('Print / Export')),
        ),
        if (_report.isDraft) ...[
          OutlinedButton.icon(
            onPressed: _editEntries,
            icon: const Icon(Icons.edit_outlined),
            label: Text(context.tr('Back to edit')),
          ),
          ElevatedButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.send_outlined),
            label: Text(context.tr('Submit')),
          ),
        ],
        if (_report.isSubmitted && canApprove)
          ElevatedButton.icon(
            onPressed: _approve,
            icon: const Icon(Icons.check_circle_outline),
            label: Text(context.tr('Approve')),
          ),
        if (_report.isApproved) ...[
          OutlinedButton.icon(
            onPressed: _correctReport,
            icon: const Icon(Icons.edit_note_outlined),
            label: Text(context.tr('Correct report')),
          ),
          OutlinedButton.icon(
            onPressed: _showRevisionHistory,
            icon: const Icon(Icons.history),
            label: Text(context.tr('Revision history')),
          ),
        ],
      ],
    );
  }
}

/// What kind of already-recorded data a "Correct report" pass is
/// targeting (breeder-flock-performance ticket 12) — the header, or one
/// specific child row. In practice a wrong mortality count, a transposed
/// cull, or a miscounted egg grade is what gets corrected; the header
/// (temperatures/light hours/notes) is included for completeness but is
/// rarely the reason a report gets reopened.
enum _CorrectionKind { header, movement, feed, eggProduction, eggInventory }

/// The reason and target-specific field values entered in
/// [_CorrectionDialog]. For the header target, a `null` field means "clear
/// this value", matching `BreederDailyReport.copyWith`'s `clear*` flags.
class _CorrectionResult {
  final _CorrectionKind kind;
  final String reason;

  // Header target.
  final double? insideTemperature;
  final double? outsideTemperature;
  final double? lightHours;
  final String? notes;

  // Bird-movement target.
  final String? movementId;
  final int? mortality;
  final int? culls;
  final int? sale;
  final int? kitchenRemoval;
  final int? euthanasia;
  final int? transferIn;
  final int? transferOut;

  // Feed-entry target.
  final String? feedEntryId;
  final double? feedKg;

  // Egg-production target.
  final String? eggEntryId;
  final int? eggCount;

  // Egg-inventory target.
  final String? inventoryMovementId;
  final int? inventoryQuantity;

  const _CorrectionResult({
    required this.kind,
    required this.reason,
    this.insideTemperature,
    this.outsideTemperature,
    this.lightHours,
    this.notes,
    this.movementId,
    this.mortality,
    this.culls,
    this.sale,
    this.kitchenRemoval,
    this.euthanasia,
    this.transferIn,
    this.transferOut,
    this.feedEntryId,
    this.feedKg,
    this.eggEntryId,
    this.eggCount,
    this.inventoryMovementId,
    this.inventoryQuantity,
  });
}

/// A house or isolation-area display label for a movement/feed/egg
/// location id, matching the naming the review tables already use.
String _locationLabelFor(
  List<HouseModel> houses,
  List<BreederIsolationArea> isolationAreas,
  String? houseId,
  String? isolationAreaId,
) {
  if (houseId != null) {
    for (final house in houses) {
      if (house.id == houseId) return house.name;
    }
    return houseId;
  }
  for (final area in isolationAreas) {
    if (area.id == isolationAreaId) return '${area.name} (Isolation)';
  }
  return isolationAreaId ?? '';
}

/// A reason-first correction dialog for an Approved report
/// (breeder-flock-performance ticket 12). The first field picks WHAT is
/// being corrected — the header, or one already-recorded bird movement,
/// feed entry, egg-production count, or egg-inventory movement — and the
/// form below it changes to match. The Save button stays disabled until a
/// non-blank reason is entered and (for every non-header target) a
/// specific row has been picked — the UI-level half of "require a reason
/// before an approved report can be corrected"; the schema/service layer
/// enforces the same rule regardless of what any UI does.
class _CorrectionDialog extends StatefulWidget {
  final BreederDailyReport report;
  final List<HouseModel> houses;
  final List<BreederIsolationArea> isolationAreas;
  final List<BreederBirdMovement> movements;
  final List<BreederFeedEntry> feedEntries;
  final bool hasEggSection;
  final List<BreederEggGradeDefinition> grades;
  final List<BreederEggProductionEntry> eggEntries;
  final List<BreederEggInventoryMovement> inventoryMovements;

  const _CorrectionDialog({
    required this.report,
    required this.houses,
    required this.isolationAreas,
    required this.movements,
    required this.feedEntries,
    required this.hasEggSection,
    required this.grades,
    required this.eggEntries,
    required this.inventoryMovements,
  });

  @override
  State<_CorrectionDialog> createState() => _CorrectionDialogState();
}

class _CorrectionDialogState extends State<_CorrectionDialog> {
  _CorrectionKind _kind = _CorrectionKind.header;

  final TextEditingController _reasonController = TextEditingController();

  // Header controllers.
  late final TextEditingController _insideController = TextEditingController(
    text: widget.report.insideTemperature?.toString() ?? '',
  );
  late final TextEditingController _outsideController = TextEditingController(
    text: widget.report.outsideTemperature?.toString() ?? '',
  );
  late final TextEditingController _lightHoursController =
      TextEditingController(text: widget.report.lightHours?.toString() ?? '');
  late final TextEditingController _notesController = TextEditingController(
    text: widget.report.notes ?? '',
  );

  // Movement target.
  String? _movementId;
  final TextEditingController _mortalityController = TextEditingController();
  final TextEditingController _cullsController = TextEditingController();
  final TextEditingController _saleController = TextEditingController();
  final TextEditingController _sexRemovalController = TextEditingController();
  final TextEditingController _transferInController = TextEditingController();
  final TextEditingController _transferOutController = TextEditingController();

  // Feed target.
  String? _feedEntryId;
  final TextEditingController _feedKgController = TextEditingController();

  // Egg-production target.
  String? _eggEntryId;
  final TextEditingController _eggCountController = TextEditingController();

  // Egg-inventory target.
  String? _inventoryMovementId;
  final TextEditingController _inventoryQuantityController =
      TextEditingController();

  bool get _hasReason => _reasonController.text.trim().isNotEmpty;

  bool get _canSave {
    if (!_hasReason) return false;
    switch (_kind) {
      case _CorrectionKind.header:
        return true;
      case _CorrectionKind.movement:
        return _movementId != null;
      case _CorrectionKind.feed:
        return _feedEntryId != null;
      case _CorrectionKind.eggProduction:
        return _eggEntryId != null;
      case _CorrectionKind.eggInventory:
        return _inventoryMovementId != null;
    }
  }

  BreederBirdMovement? get _selectedMovement {
    for (final m in widget.movements) {
      if (m.id == _movementId) return m;
    }
    return null;
  }

  /// Only plain (non-adjustment, non-reversal) rows are offered — a
  /// reversal is itself the documented record of an earlier correction and
  /// is never corrected again, and an adjustment already has its own
  /// dedicated entry flow.
  List<BreederEggInventoryMovement> get _correctableInventoryMovements {
    return widget.inventoryMovements
        .where(
          (m) =>
              m.kind != BreederEggInventoryMovementKind.adjustment &&
              !m.isReversal,
        )
        .toList();
  }

  String _gradeName(String gradeId) {
    for (final grade in widget.grades) {
      if (grade.id == gradeId) return grade.name;
    }
    return gradeId;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _insideController.dispose();
    _outsideController.dispose();
    _lightHoursController.dispose();
    _notesController.dispose();
    _mortalityController.dispose();
    _cullsController.dispose();
    _saleController.dispose();
    _sexRemovalController.dispose();
    _transferInController.dispose();
    _transferOutController.dispose();
    _feedKgController.dispose();
    _eggCountController.dispose();
    _inventoryQuantityController.dispose();
    super.dispose();
  }

  void _selectMovement(String? id) {
    setState(() {
      _movementId = id;
      final movement = _selectedMovement;
      _mortalityController.text = movement?.mortality.toString() ?? '';
      _cullsController.text = movement?.culls.toString() ?? '';
      _saleController.text = movement?.sale.toString() ?? '';
      _sexRemovalController.text = movement == null
          ? ''
          : movement.sexSpecificRemoval.toString();
      _transferInController.text = movement?.transferIn.toString() ?? '';
      _transferOutController.text = movement?.transferOut.toString() ?? '';
    });
  }

  void _selectFeedEntry(String? id) {
    setState(() {
      _feedEntryId = id;
      for (final entry in widget.feedEntries) {
        if (entry.id == id) {
          _feedKgController.text = entry.feedKg.toString();
          return;
        }
      }
      _feedKgController.text = '';
    });
  }

  void _selectEggEntry(String? id) {
    setState(() {
      _eggEntryId = id;
      for (final entry in widget.eggEntries) {
        if (entry.id == id) {
          _eggCountController.text = entry.count.toString();
          return;
        }
      }
      _eggCountController.text = '';
    });
  }

  void _selectInventoryMovement(String? id) {
    setState(() {
      _inventoryMovementId = id;
      for (final movement in _correctableInventoryMovements) {
        if (movement.id == id) {
          _inventoryQuantityController.text = movement.quantity.toString();
          return;
        }
      }
      _inventoryQuantityController.text = '';
    });
  }

  void _save() {
    final reason = _reasonController.text.trim();
    switch (_kind) {
      case _CorrectionKind.header:
        Navigator.of(context).pop(
          _CorrectionResult(
            kind: _kind,
            reason: reason,
            insideTemperature: double.tryParse(_insideController.text.trim()),
            outsideTemperature: double.tryParse(
              _outsideController.text.trim(),
            ),
            lightHours: double.tryParse(_lightHoursController.text.trim()),
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          ),
        );
      case _CorrectionKind.movement:
        final movement = _selectedMovement;
        final isFemale =
            movement?.sex == BreederBirdMovementSex.female;
        final sexRemoval = int.tryParse(_sexRemovalController.text.trim());
        Navigator.of(context).pop(
          _CorrectionResult(
            kind: _kind,
            reason: reason,
            movementId: _movementId,
            mortality: int.tryParse(_mortalityController.text.trim()),
            culls: int.tryParse(_cullsController.text.trim()),
            sale: int.tryParse(_saleController.text.trim()),
            kitchenRemoval: isFemale ? sexRemoval : null,
            euthanasia: isFemale ? null : sexRemoval,
            transferIn: int.tryParse(_transferInController.text.trim()),
            transferOut: int.tryParse(_transferOutController.text.trim()),
          ),
        );
      case _CorrectionKind.feed:
        Navigator.of(context).pop(
          _CorrectionResult(
            kind: _kind,
            reason: reason,
            feedEntryId: _feedEntryId,
            feedKg: double.tryParse(_feedKgController.text.trim()) ?? 0,
          ),
        );
      case _CorrectionKind.eggProduction:
        Navigator.of(context).pop(
          _CorrectionResult(
            kind: _kind,
            reason: reason,
            eggEntryId: _eggEntryId,
            eggCount: int.tryParse(_eggCountController.text.trim()) ?? 0,
          ),
        );
      case _CorrectionKind.eggInventory:
        Navigator.of(context).pop(
          _CorrectionResult(
            kind: _kind,
            reason: reason,
            inventoryMovementId: _inventoryMovementId,
            inventoryQuantity:
                int.tryParse(_inventoryQuantityController.text.trim()) ?? 0,
          ),
        );
    }
  }

  Widget _targetPicker() {
    final items = <DropdownMenuItem<_CorrectionKind>>[
      DropdownMenuItem(
        value: _CorrectionKind.header,
        child: Text(context.tr('Header fields')),
      ),
      DropdownMenuItem(
        value: _CorrectionKind.movement,
        child: Text(context.tr('Bird movement')),
      ),
      DropdownMenuItem(
        value: _CorrectionKind.feed,
        child: Text(context.tr('Feed entry')),
      ),
      if (widget.hasEggSection) ...[
        DropdownMenuItem(
          value: _CorrectionKind.eggProduction,
          child: Text(context.tr('Egg production count')),
        ),
        DropdownMenuItem(
          value: _CorrectionKind.eggInventory,
          child: Text(context.tr('Egg inventory movement')),
        ),
      ],
    ];
    return DropdownButtonFormField<_CorrectionKind>(
      key: const Key('correctionTargetPicker'),
      initialValue: _kind,
      decoration: InputDecoration(
        labelText: context.tr('What are you correcting?'),
      ),
      items: items,
      onChanged: (value) {
        if (value == null) return;
        setState(() => _kind = value);
      },
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label,
    Key key,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        key: key,
        controller: controller,
        decoration: InputDecoration(labelText: context.tr(label)),
        keyboardType: const TextInputType.numberWithOptions(signed: true),
      ),
    );
  }

  Widget _targetForm() {
    switch (_kind) {
      case _CorrectionKind.header:
        return Column(
          children: [
            _numberField(
              _insideController,
              'Inside temperature (°C)',
              const Key('correctionInsideTemperatureField'),
            ),
            _numberField(
              _outsideController,
              'Outside temperature (°C)',
              const Key('correctionOutsideTemperatureField'),
            ),
            _numberField(
              _lightHoursController,
              'Light hours',
              const Key('correctionLightHoursField'),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                key: const Key('correctionNotesField'),
                controller: _notesController,
                decoration: InputDecoration(labelText: context.tr('Notes')),
              ),
            ),
          ],
        );
      case _CorrectionKind.movement:
        final movement = _selectedMovement;
        final isFemale = movement?.sex == BreederBirdMovementSex.female;
        return Column(
          children: [
            DropdownButtonFormField<String>(
              key: const Key('correctionMovementPicker'),
              initialValue: _movementId,
              decoration: InputDecoration(
                labelText: context.tr('Movement row'),
              ),
              items: [
                for (final m in widget.movements)
                  DropdownMenuItem(
                    value: m.id,
                    child: Text(
                      '${_locationLabelFor(widget.houses, widget.isolationAreas, m.houseId, m.isolationAreaId)} — '
                      '${m.sex == BreederBirdMovementSex.female ? context.tr("Female") : context.tr("Male")}',
                    ),
                  ),
              ],
              onChanged: _selectMovement,
            ),
            if (movement != null) ...[
              _numberField(
                _mortalityController,
                'Mortality',
                const Key('correctionMortalityField'),
              ),
              _numberField(
                _cullsController,
                'Culls/Sorts',
                const Key('correctionCullsField'),
              ),
              _numberField(
                _saleController,
                'Sale',
                const Key('correctionSaleField'),
              ),
              _numberField(
                _sexRemovalController,
                isFemale ? 'Kitchen' : 'Euthanasia',
                const Key('correctionSexRemovalField'),
              ),
              _numberField(
                _transferInController,
                'Transfer in',
                const Key('correctionTransferInField'),
              ),
              _numberField(
                _transferOutController,
                'Transfer out',
                const Key('correctionTransferOutField'),
              ),
            ],
          ],
        );
      case _CorrectionKind.feed:
        return Column(
          children: [
            DropdownButtonFormField<String>(
              key: const Key('correctionFeedEntryPicker'),
              initialValue: _feedEntryId,
              decoration: InputDecoration(
                labelText: context.tr('Feed entry'),
              ),
              items: [
                for (final f in widget.feedEntries)
                  DropdownMenuItem(
                    value: f.id,
                    child: Text(
                      '${_locationLabelFor(widget.houses, widget.isolationAreas, f.houseId, f.isolationAreaId)} — '
                      '${f.sex == BreederBirdMovementSex.female ? context.tr("Female") : context.tr("Male")}',
                    ),
                  ),
              ],
              onChanged: _selectFeedEntry,
            ),
            if (_feedEntryId != null)
              _numberField(
                _feedKgController,
                'Feed (kg)',
                const Key('correctionFeedKgField'),
              ),
          ],
        );
      case _CorrectionKind.eggProduction:
        return Column(
          children: [
            DropdownButtonFormField<String>(
              key: const Key('correctionEggEntryPicker'),
              initialValue: _eggEntryId,
              decoration: InputDecoration(
                labelText: context.tr('Egg production entry'),
              ),
              items: [
                for (final e in widget.eggEntries)
                  DropdownMenuItem(
                    value: e.id,
                    child: Text(
                      '${_locationLabelFor(widget.houses, widget.isolationAreas, e.houseId, e.isolationAreaId)} — '
                      '${_gradeName(e.gradeId)}',
                    ),
                  ),
              ],
              onChanged: _selectEggEntry,
            ),
            if (_eggEntryId != null)
              _numberField(
                _eggCountController,
                'Count',
                const Key('correctionEggCountField'),
              ),
          ],
        );
      case _CorrectionKind.eggInventory:
        return Column(
          children: [
            DropdownButtonFormField<String>(
              key: const Key('correctionInventoryMovementPicker'),
              initialValue: _inventoryMovementId,
              decoration: InputDecoration(
                labelText: context.tr('Egg inventory movement'),
              ),
              items: [
                for (final m in _correctableInventoryMovements)
                  DropdownMenuItem(
                    value: m.id,
                    child: Text('${_gradeName(m.gradeId)} — ${m.kind}'),
                  ),
              ],
              onChanged: _selectInventoryMovement,
            ),
            if (_inventoryMovementId != null)
              _numberField(
                _inventoryQuantityController,
                'Quantity',
                const Key('correctionInventoryQuantityField'),
              ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('Correct report')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _reasonController,
              decoration: InputDecoration(
                labelText: context.tr('Reason (required)'),
              ),
              onChanged: (_) => setState(() {}),
              key: const Key('correctionReasonField'),
            ),
            const SizedBox(height: 12),
            _targetPicker(),
            const SizedBox(height: 8),
            _targetForm(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Cancel')),
        ),
        ElevatedButton(
          onPressed: _canSave ? _save : null,
          child: Text(context.tr('Save correction')),
        ),
      ],
    );
  }
}

/// Read-only listing of every revision entry for a report (breeder-flock
/// -performance ticket 12): who changed it, when, which field, from what
/// to what, and the stated reason.
class _RevisionHistoryDialog extends StatelessWidget {
  final List<BreederReportRevision> revisions;

  const _RevisionHistoryDialog({required this.revisions});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('Revision history')),
      content: SizedBox(
        width: double.maxFinite,
        child: revisions.isEmpty
            ? Text(
                context.tr('No corrections have been made to this report.'),
                key: const Key('revisionHistoryEmpty'),
              )
            : ListView.separated(
                key: const Key('revisionHistoryList'),
                shrinkWrap: true,
                itemCount: revisions.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, index) {
                  final revision = revisions[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${revision.fieldName}: '
                        '${revision.oldValue ?? "—"} → '
                        '${revision.newValue ?? "—"}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${context.tr("By")}: ${revision.actorUserId}  '
                        '${context.tr("At")}: ${revision.changedAt}',
                      ),
                      Text('${context.tr("Reason")}: ${revision.reason}'),
                    ],
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Close')),
        ),
      ],
    );
  }
}

class _ReviewData {
  final List<HouseModel> houses;
  final List<BreederIsolationArea> isolationAreas;
  final List<BreederBirdMovement> movements;
  final List<BreederFeedEntry> feedEntries;
  final ProductionWeekResult productionWeek;

  /// Whether the flock has entered the benchmark profile's official
  /// production range (design doc section 5.1) — gates the whole egg
  /// section.
  final bool hasEggSection;
  final List<BreederEggGradeDefinition> grades;
  final List<BreederEggProductionEntry> eggEntries;

  /// One egg-inventory balance per active grade (breeder-flock-performance
  /// ticket 11), gated by the same [hasEggSection] flag.
  final List<BreederEggInventoryBalance> inventoryBalances;

  /// The raw egg-inventory movement rows behind [inventoryBalances]
  /// (breeder-flock-performance ticket 12) — what the correction dialog
  /// offers to correct, since a balance is derived and has no id of its
  /// own.
  final List<BreederEggInventoryMovement> inventoryMovements;

  /// Display-precision lookup for this report's derived values
  /// (breeder-flock-performance ticket 19), sourced from
  /// `breeder_metric_definitions.displayPrecision`.
  final BreederReportMetricFormatter metrics;

  _ReviewData({
    required this.houses,
    required this.isolationAreas,
    required this.movements,
    required this.feedEntries,
    required this.productionWeek,
    this.hasEggSection = false,
    this.grades = const [],
    this.eggEntries = const [],
    this.inventoryBalances = const [],
    this.inventoryMovements = const [],
    BreederReportMetricFormatter? metrics,
  }) : metrics = metrics ?? BreederReportMetricFormatter(const []);
}
