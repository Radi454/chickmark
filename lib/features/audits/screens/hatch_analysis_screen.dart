import 'dart:convert';

import 'package:hatchaudit/localized_material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/bmk_age_calculator.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/sample_mode.dart';
import '../../../data/models/station_sample_model.dart';
import '../../../data/repositories/benchmark_lookup.dart';
import '../providers/audit_provider.dart';
import '../widgets/audit_autosave_status.dart';
import '../widgets/audit_keyboard_dismiss.dart';
import '../widgets/audit_numeric_keyboard.dart';
import '../widgets/audit_station_scroll_view.dart';
import '../widgets/photo_button.dart';
import '../widgets/unsaved_changes_guard.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/egg_breakout_sample.dart';
import '../models/residue_batch_metrics.dart';
import 'audit_context_screen.dart';

class HatchAnalysisScreen extends StatefulWidget {
  final AuditContextData context;
  final AuditModel? initialAudit;
  final List<AuditModel> initialAudits;
  final List<StationSampleModel> initialStationSamples;
  final int initialSectionIndex;
  final BenchmarkLookup? benchmarkLookup;

  const HatchAnalysisScreen({
    super.key,
    required this.context,
    this.initialAudit,
    this.initialAudits = const [],
    this.initialStationSamples = const [],
    this.initialSectionIndex = 0,
    this.benchmarkLookup,
  });

  @override
  State<HatchAnalysisScreen> createState() => _HatchAnalysisScreenState();
}

class _HatchAnalysisScreenState extends State<HatchAnalysisScreen> {
  final ScrollController _scrollController = ScrollController();
  late final BenchmarkLookup _benchmarkLookup;
  final Map<int, Future<Map<String, Object?>?>> _breakoutBenchmarkFutures = {};
  final Map<String, Future<Map<String, Object?>?>> _breedBenchmarkFutures = {};
  final Map<int, int> _activeBreakoutSampleIndexes = {};
  final Map<String, GlobalKey> _sampleCardKeys = {};
  final Map<String, FocusNode> _breakoutCountFocusNodes = {};
  late final List<GlobalKey> _sectionKeys = List.generate(
    2,
    (_) => GlobalKey(),
  );

  @override
  void initState() {
    super.initState();
    _benchmarkLookup = widget.benchmarkLookup ?? BenchmarkLookup();
    final auditProvider = Provider.of<AuditProvider>(context, listen: false);
    final auditContext = AuditContext(
      auditType: widget.context.auditType,
      customerId: widget.context.customerId,
      flockId: widget.context.flockId,
      hatcheryId: widget.context.hatcheryId,
      breed: widget.context.breed,
      setterId: widget.context.setterId,
      hatcherId: widget.context.hatcherId,
      flockEntryDate: widget.context.flockEntryDate,
      flockAgeWeeks: widget.context.flockAgeWeeks,
      date: widget.context.date,
    );
    auditProvider.initialize(
      auditContext,
      existingAudit: widget.initialAudit,
      existingAudits: widget.initialAudits,
      existingStationSamples: widget.initialStationSamples,
      readOnly: widget.context.sessionId == null ? null : false,
      notify: false,
      currentUser: context.read<AuthProvider>().user,
      sessionId: widget.context.sessionId,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _persistAllBmkAges(auditProvider);
      _scrollToInitialSection();
    });
  }

  @override
  void dispose() {
    for (final node in _breakoutCountFocusNodes.values) {
      node.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auditProvider = context.watch<AuditProvider>();
    final drafts = auditProvider.drafts;
    final activeIndex = drafts.isEmpty
        ? 0
        : auditProvider.activeHatchIndex.clamp(0, drafts.length - 1).toInt();
    final activeDraft = drafts.isEmpty ? null : drafts[activeIndex];

    return UnsavedChangesGuard(
      enabled: widget.context.sessionId == null,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6F8),
        appBar: widget.context.sessionId != null
            ? null
            : GradientAppBar(
                title: 'Hatch Analysis & Egg Breakouts',
                actions: [
                  const AuditAutosaveStatus(onDark: true),
                  if (auditProvider.isReadOnly)
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => auditProvider.setEditMode(true),
                    ),
                ],
              ),
        body: AuditNumericKeyboardScope(
          child: AuditKeyboardDismiss(
            child: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: AuditStationListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      children: [
                        if (activeDraft != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _buildHatchSector(
                              provider: auditProvider,
                              hatchIndex: activeIndex,
                              audit: activeDraft,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHatchSector({
    required AuditProvider provider,
    required int hatchIndex,
    required AuditModel audit,
  }) {
    final breakoutType = EggBreakoutType.fromStorageValue(audit.ebBreakoutType);

    return Center(
      key: const ValueKey('hatch-analysis-workbench-shell'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: Column(
          key: hatchIndex == provider.activeHatchIndex ? _sectionKeys[0] : null,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBreakoutTypeCard(provider, hatchIndex, audit, breakoutType),
            if (breakoutType != EggBreakoutType.freshEggBreakout) ...[
              const SizedBox(height: AppSizes.spaceMd),
              _buildResidueBatchTabs(provider),
            ],
            if (breakoutType == EggBreakoutType.residueHatchDay) ...[
              const SizedBox(height: AppSizes.spaceLg),
              _buildResidueBatchResultsCard(provider, hatchIndex, audit),
            ],
            const SizedBox(height: AppSizes.spaceLg),
            _surface(
              containerKey: const ValueKey('hatch-analysis-samples-panel'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Breakout Samples'),
                  const SizedBox(height: AppSizes.spaceSm),
                  _buildBreakoutSampleSection(
                    provider,
                    hatchIndex,
                    audit,
                    breakoutType,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResidueBatchTabs(AuditProvider provider) {
    final drafts = provider.drafts;
    final activeIndex = drafts.isEmpty
        ? 0
        : provider.activeHatchIndex.clamp(0, drafts.length - 1).toInt();
    final activeAudit = drafts.isEmpty ? null : drafts[activeIndex];
    final scopeActive = provider.isCompareMode || drafts.length > 1;
    final activeHouseKey = scopeActive && activeAudit != null
        ? _residueHouseKey(activeAudit, activeIndex)
        : null;
    final selectedHouseScopeActive =
        activeHouseKey != null && activeHouseKey != 'pool';
    final houses = scopeActive
        ? _residueHouseTabs(drafts)
        : const <_ResidueHouseTab>[];
    final machineEntries = scopeActive && activeHouseKey != null
        ? drafts
              .asMap()
              .entries
              .where(
                (entry) =>
                    _residueHouseKey(entry.value, entry.key) ==
                        activeHouseKey &&
                    _isResidueMachineDraft(entry.value),
              )
              .toList()
        : const <MapEntry<int, AuditModel>>[];
    final hasSelectedMachineEntry = machineEntries.any(
      (entry) => entry.key == provider.activeHatchIndex,
    );
    final activeBreakoutType = activeAudit == null
        ? EggBreakoutType.residueHatchDay
        : EggBreakoutType.fromStorageValue(activeAudit.ebBreakoutType);
    final activeScopeSamples = activeAudit == null
        ? const <EggBreakoutSampleEntry>[]
        : _resolveBreakoutWorkingSamples(activeAudit, activeBreakoutType);
    final activeScopeIndex = activeScopeSamples.isEmpty
        ? 0
        : _activeBreakoutSampleIndex(activeIndex, activeScopeSamples.length);
    final activeTrolleyKey = activeScopeSamples.isEmpty
        ? null
        : _trimmedOrNull(activeScopeSamples[activeScopeIndex].trolley);
    final trolleyTabs = _residueTrolleyTabs(activeScopeSamples);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: Container(
          key: const ValueKey('residue-batch-tabs'),
          width: double.infinity,
          padding: const EdgeInsets.all(AppSizes.spaceMd),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            border: Border.all(color: AppColors.borderDefault),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSampleControlCard(
                title: 'House scope',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _residueHierarchyTabRow(
                      rowKey: const ValueKey('residue-house-tabs'),
                      entries: scopeActive && houses.isNotEmpty
                          ? [
                              for (final house in houses)
                                _buildResidueScopeChip(
                                  key: ValueKey(
                                    'residue-house-tab-${house.firstDraftIndex}',
                                  ),
                                  label: house.label,
                                  selected: house.key == activeHouseKey,
                                  enabled: !provider.isReadOnly,
                                  onSelected: () => provider.switchHatch(
                                    house.firstDraftIndex,
                                  ),
                                ),
                            ]
                          : [
                              _buildResidueScopeChip(
                                label: 'Pool',
                                selected: true,
                                enabled: false,
                                onSelected: null,
                              ),
                            ],
                      actions: [
                        _buildTrayActionButton(
                          key: const ValueKey('residue-add-house'),
                          tooltip: context.tr('Add house'),
                          icon: Icons.add,
                          onPressed: provider.isReadOnly
                              ? null
                              : () => _addResidueHouse(provider),
                        ),
                        if (selectedHouseScopeActive)
                          _buildTrayActionButton(
                            key: const ValueKey('residue-remove-house'),
                            tooltip: context.tr('Remove active house'),
                            icon: Icons.remove,
                            onPressed: provider.isReadOnly
                                ? null
                                : () => _removeActiveResidueHouse(provider),
                          ),
                      ],
                    ),
                    if (selectedHouseScopeActive && activeAudit != null) ...[
                      const SizedBox(height: AppSizes.spaceMd),
                      _responsiveTileGrid(
                        minTileWidth: 150,
                        children: [
                          _residueTextNumberField(
                            wrapperKey: const ValueKey('residue-house-number'),
                            fieldKey: ValueKey(
                              'residue-house-number-$activeIndex',
                            ),
                            label: 'House',
                            value: _residueHouseFieldValue(activeAudit.houseId),
                            enabled: !provider.isReadOnly,
                            onChanged: (value) => _updateResidueHouseField(
                              provider,
                              activeIndex,
                              value,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildSampleControlCard(
                title: 'Machine scope',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _residueHierarchyTabRow(
                      rowKey: const ValueKey('residue-machine-tabs'),
                      entries: scopeActive && machineEntries.isNotEmpty
                          ? [
                              for (final entry in machineEntries)
                                _buildResidueScopeChip(
                                  key: ValueKey(
                                    'residue-batch-tab-${entry.key}',
                                  ),
                                  label: _residueBatchLabel(
                                    entry.value,
                                    entry.key,
                                  ),
                                  selected:
                                      entry.key == provider.activeHatchIndex,
                                  enabled: !provider.isReadOnly,
                                  onSelected: () =>
                                      provider.switchHatch(entry.key),
                                ),
                            ]
                          : [
                              _buildResidueScopeChip(
                                label: 'Pool',
                                selected: true,
                                enabled: false,
                                onSelected: null,
                              ),
                            ],
                      actions: [
                        _buildTrayActionButton(
                          key: const ValueKey('residue-add-batch'),
                          tooltip: context.tr('Add machine'),
                          icon: Icons.add,
                          onPressed: provider.isReadOnly
                              ? null
                              : () => _addResidueMachine(provider),
                        ),
                        if (hasSelectedMachineEntry)
                          _buildTrayActionButton(
                            key: const ValueKey('residue-remove-batch'),
                            tooltip: context.tr('Remove active machine'),
                            icon: Icons.remove,
                            onPressed: provider.isReadOnly
                                ? null
                                : () => _removeActiveResidueMachine(provider),
                          ),
                      ],
                    ),
                    if (scopeActive &&
                        activeAudit != null &&
                        hasSelectedMachineEntry) ...[
                      const SizedBox(height: AppSizes.spaceMd),
                      _responsiveTileGrid(
                        minTileWidth: 150,
                        children: [
                          _residueTextNumberField(
                            wrapperKey: const ValueKey('residue-setter-number'),
                            fieldKey: ValueKey(
                              'residue-setter-number-$activeIndex',
                            ),
                            label: 'Setter',
                            value: _residueMachineFieldValue(
                              activeAudit.setterId,
                              'S',
                            ),
                            enabled: !provider.isReadOnly,
                            onChanged: (value) => _updateResidueMachineField(
                              provider,
                              activeIndex,
                              'setterId',
                              value,
                            ),
                          ),
                          _residueTextNumberField(
                            wrapperKey: const ValueKey(
                              'residue-hatcher-number',
                            ),
                            fieldKey: ValueKey(
                              'residue-hatcher-number-$activeIndex',
                            ),
                            label: 'Hatcher',
                            value: _residueMachineFieldValue(
                              activeAudit.hatcherId,
                              'H',
                            ),
                            enabled: !provider.isReadOnly,
                            onChanged: (value) => _updateResidueMachineField(
                              provider,
                              activeIndex,
                              'hatcherId',
                              value,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildSampleControlCard(
                title: 'Trolley scope',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _residueHierarchyTabRow(
                      rowKey: const ValueKey('residue-trolley-tabs'),
                      entries: trolleyTabs.isNotEmpty
                          ? [
                              for (final trolley in trolleyTabs)
                                _buildResidueScopeChip(
                                  key: ValueKey(
                                    'residue-trolley-tab-${trolley.firstSampleIndex}',
                                  ),
                                  label: trolley.label,
                                  selected: trolley.key == activeTrolleyKey,
                                  enabled: !provider.isReadOnly,
                                  onSelected: () => _activateBreakoutSample(
                                    activeIndex,
                                    trolley.firstSampleIndex,
                                  ),
                                ),
                            ]
                          : [
                              _buildResidueScopeChip(
                                label: 'Pool',
                                selected: true,
                                enabled: false,
                                onSelected: null,
                              ),
                            ],
                      actions: [
                        _buildTrayActionButton(
                          key: const ValueKey('residue-add-trolley'),
                          tooltip: context.tr('Add trolley'),
                          icon: Icons.add,
                          onPressed: provider.isReadOnly || activeAudit == null
                              ? null
                              : () => _addResidueTrolley(
                                  provider,
                                  activeIndex,
                                  activeAudit,
                                  activeBreakoutType,
                                  activeScopeSamples,
                                ),
                        ),
                        if (activeTrolleyKey != null)
                          _buildTrayActionButton(
                            key: const ValueKey('residue-remove-trolley'),
                            tooltip: context.tr('Remove active trolley'),
                            icon: Icons.remove,
                            onPressed:
                                provider.isReadOnly || activeAudit == null
                                ? null
                                : () => _removeActiveResidueTrolley(
                                    provider,
                                    activeIndex,
                                    activeBreakoutType,
                                    activeScopeSamples,
                                    activeTrolleyKey,
                                  ),
                          ),
                      ],
                    ),
                    if (activeTrolleyKey != null && activeAudit != null) ...[
                      const SizedBox(height: AppSizes.spaceMd),
                      _responsiveTileGrid(
                        minTileWidth: 150,
                        children: [
                          _residueTextNumberField(
                            wrapperKey: const ValueKey(
                              'residue-trolley-number',
                            ),
                            fieldKey: ValueKey(
                              'residue-trolley-number-$activeIndex',
                            ),
                            label: 'Trolley',
                            value: _residueTrolleyFieldValue(activeTrolleyKey),
                            enabled: !provider.isReadOnly,
                            onChanged: (value) => _updateResidueTrolleyField(
                              provider,
                              activeIndex,
                              activeBreakoutType,
                              activeScopeSamples,
                              activeTrolleyKey,
                              value,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _residueHierarchyTabRow({
    required Key rowKey,
    required List<Widget> entries,
    required List<Widget> actions,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final actionRow = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < actions.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              actions[index],
            ],
          ],
        );
        if (constraints.maxWidth < 520) {
          return Wrap(
            key: rowKey,
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [...entries, actionRow],
          );
        }

        return Row(
          key: rowKey,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: entries,
              ),
            ),
            const SizedBox(width: 8),
            actionRow,
          ],
        );
      },
    );
  }

  Widget _buildResidueScopeChip({
    Key? key,
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback? onSelected,
  }) {
    return ChoiceChip(
      key: key,
      label: Text(label),
      selected: selected,
      onSelected: enabled && onSelected != null ? (_) => onSelected() : null,
      selectedColor: AppColors.primary.withValues(alpha: 0.14),
      checkmarkColor: AppColors.primary,
      labelStyle: AppTextStyles.body.copyWith(
        color: selected ? AppColors.primary : AppColors.textBody,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.borderDefault,
        ),
      ),
    );
  }

  Widget _buildSampleControlCard({
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  String _residueBatchLabel(AuditModel audit, int index) {
    final fallback = '${index + 1}';
    final setter = _machineLabelPart(audit.setterId, 'S', fallback);
    final hatcher = _machineLabelPart(audit.hatcherId, 'H', fallback);
    return 'S${setter}H$hatcher';
  }

  String _residueResultScopeLabel(
    AuditProvider provider,
    AuditModel audit,
    int index,
  ) {
    if (!provider.isCompareMode && provider.hatchCount == 1) return 'Pool';
    if (_isResidueMachineDraft(audit)) return _residueBatchLabel(audit, index);
    return _residueHouseLabel(_residueHouseKey(audit, index));
  }

  bool _isResidueMachineDraft(AuditModel audit) {
    return SampleMode.isCompare(audit.sampleMode) &&
        (_trimmedOrNull(audit.setterId) != null ||
            _trimmedOrNull(audit.hatcherId) != null);
  }

  List<_ResidueHouseTab> _residueHouseTabs(List<AuditModel> drafts) {
    final seen = <String>{};
    final houses = <_ResidueHouseTab>[];
    for (final entry in drafts.asMap().entries) {
      final key = _residueHouseKey(entry.value, entry.key);
      if (!seen.add(key)) continue;
      houses.add(
        _ResidueHouseTab(
          key: key,
          label: _residueHouseLabel(key),
          firstDraftIndex: entry.key,
        ),
      );
    }
    return houses;
  }

  /// The breakout samples the scope cards operate on for [audit]. Tray samples
  /// take over once tray comparison is active; otherwise the pool sample(s)
  /// (which may carry a trolley) are returned so the Trolley scope can attach
  /// to a pooled sample without forcing the Tray scope into comparison.
  List<EggBreakoutSampleEntry> _resolveBreakoutWorkingSamples(
    AuditModel audit,
    EggBreakoutType breakoutType,
  ) {
    final breakoutSamples = _normalizeBreakoutSamples(
      EggBreakoutSampleEntry.decodeList(
        audit.ebTrayBreakoutJson,
        fallbackBreakoutType:
            _legacyBreakoutJsonNeedsTypeFallback(audit.ebTrayBreakoutJson)
            ? breakoutType
            : null,
      ).where((sample) => sample.breakoutType == breakoutType).toList(),
    );
    return _resolveWorkingSamplesFrom(breakoutSamples, breakoutType);
  }

  List<EggBreakoutSampleEntry> _resolveWorkingSamplesFrom(
    List<EggBreakoutSampleEntry> breakoutSamples,
    EggBreakoutType breakoutType,
  ) {
    final traySamples = breakoutSamples
        .where((sample) => sample.sampleMode == EggBreakoutSampleMode.tray)
        .toList();
    if (traySamples.isNotEmpty) return traySamples;
    if (breakoutSamples.isNotEmpty) return breakoutSamples;
    return [_defaultPoolBreakoutSample(breakoutType)];
  }

  List<_ResidueTrolleyTab> _residueTrolleyTabs(
    List<EggBreakoutSampleEntry> samples,
  ) {
    final seen = <String>{};
    final trolleys = <_ResidueTrolleyTab>[];
    for (final entry in samples.asMap().entries) {
      final key = _trimmedOrNull(entry.value.trolley);
      if (key == null || !seen.add(key)) continue;
      trolleys.add(
        _ResidueTrolleyTab(
          key: key,
          label: _residueTrolleyLabel(key),
          firstSampleIndex: entry.key,
        ),
      );
    }
    return trolleys;
  }

  String _residueHouseKey(AuditModel audit, int index) {
    return _residueHouseKeyOrNull(audit) ?? 'pool';
  }

  String? _residueHouseKeyOrNull(AuditModel audit) {
    return _trimmedOrNull(audit.houseId);
  }

  String _residueHouseLabel(String raw) {
    if (raw.trim().toLowerCase() == 'pool') return 'Pool';
    final value = _batchLabelPart(raw, '1');
    if (value.toLowerCase().startsWith('h')) return value;
    return 'H$value';
  }

  String _residueTrolleyLabel(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return 'Pool';
    if (value.toLowerCase().startsWith('t')) return value;
    return 'T$value';
  }

  void _addResidueHouse(AuditProvider provider) {
    final existingHouseKeys = provider.isCompareMode
        ? _residueHouseTabs(provider.drafts).map((house) => house.key).toSet()
        : <String>{};
    final nextHouse = existingHouseKeys.isEmpty
        ? 'H'
        : _nextHierarchyNumber(existingHouseKeys);
    if (!provider.isCompareMode && provider.hatchCount == 1) {
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
    } else {
      provider.addHatch();
    }
    final nextIndex = provider.activeHatchIndex;
    provider.updateHatchField(nextIndex, 'houseId', nextHouse);
    provider.updateHatchField(nextIndex, 'setterId', null);
    provider.updateHatchField(nextIndex, 'hatcherId', null);
    _syncAllMachineBreakoutSamplesWithActiveHierarchy(provider, nextIndex);
  }

  void _addResidueMachine(AuditProvider provider) {
    if (provider.drafts.isEmpty) return;
    final wasCompareMode = provider.isCompareMode;
    final initialActiveIndex = provider.activeHatchIndex
        .clamp(0, provider.drafts.length - 1)
        .toInt();
    final activeHouseOrNull = wasCompareMode
        ? _residueHouseKeyOrNull(provider.drafts[initialActiveIndex])
        : null;
    final activeHouseKey = wasCompareMode
        ? _residueHouseKey(
            provider.drafts[initialActiveIndex],
            initialActiveIndex,
          )
        : 'pool';
    final existingMachineEntries = wasCompareMode
        ? provider.drafts
              .asMap()
              .entries
              .where(
                (entry) =>
                    _residueHouseKey(entry.value, entry.key) ==
                        activeHouseKey &&
                    _isResidueMachineDraft(entry.value),
              )
              .toList()
        : const <MapEntry<int, AuditModel>>[];
    final activeDraftHasData = _residueDraftHasEnteredData(
      provider.drafts[initialActiveIndex],
    );
    final shouldConvertActiveDraft =
        !_isResidueMachineDraft(provider.drafts[initialActiveIndex]) &&
        (wasCompareMode || !activeDraftHasData);
    if (!provider.isCompareMode && provider.hatchCount == 1) {
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.updateHatchField(initialActiveIndex, 'houseId', null);
      provider.updateHatchField(initialActiveIndex, 'setterId', null);
      provider.updateHatchField(initialActiveIndex, 'hatcherId', null);
    }
    if (!shouldConvertActiveDraft) {
      provider.addHatch();
    }
    final nextIndex = shouldConvertActiveDraft
        ? initialActiveIndex
        : provider.activeHatchIndex;
    final nextMachineNumber = existingMachineEntries.isEmpty
        ? null
        : _nextResidueMachineNumber(existingMachineEntries);
    provider.updateHatchField(nextIndex, 'houseId', activeHouseOrNull);
    provider.updateHatchField(nextIndex, 'setterId', nextMachineNumber ?? 'S');
    provider.updateHatchField(nextIndex, 'hatcherId', nextMachineNumber ?? 'H');
    _syncAllMachineBreakoutSamplesWithActiveHierarchy(provider, nextIndex);
  }

  void _addResidueTrolley(
    AuditProvider provider,
    int hatchIndex,
    AuditModel audit,
    EggBreakoutType breakoutType,
    List<EggBreakoutSampleEntry> samples,
  ) {
    if (hatchIndex < 0 || hatchIndex >= provider.drafts.length) return;
    final existingTrolleys = _residueTrolleyTabs(
      samples,
    ).map((trolley) => trolley.key).toSet();
    final nextTrolley = existingTrolleys.isEmpty
        ? 'T'
        : _nextPrefixedScopeNumber(existingTrolleys, 'T');
    final trayScopeActive = samples.any(
      (sample) => sample.sampleMode == EggBreakoutSampleMode.tray,
    );

    // Adding a trolley keeps the breakout pooled: the trolley attaches to a
    // pool sample so the Tray scope stays on `Pool` until the user adds a tray.
    // The first trolley reuses the lone blank pool sample in place; only when
    // tray comparison is already active does a new trolley spawn a tray.
    if (!trayScopeActive &&
        existingTrolleys.isEmpty &&
        samples.length == 1 &&
        _trimmedOrNull(samples.first.trolley) == null) {
      _activeBreakoutSampleIndexes[hatchIndex] = 0;
      _persistBreakoutSamples(provider, hatchIndex, breakoutType, [
        samples.first.copyWith(trolley: nextTrolley),
      ]);
      return;
    }

    final nextSampleIndex = samples.length + 1;
    final nextSample = trayScopeActive
        ? EggBreakoutSampleEntry.tray(
            id: 'sample-${DateTime.now().microsecondsSinceEpoch}',
            label: 'Tray $nextSampleIndex',
            trolley: nextTrolley,
            position: 'random',
            traySize: _defaultTraySizeForBreakout(breakoutType),
            breakoutType: breakoutType,
          )
        : EggBreakoutSampleEntry.pool(
            id: 'sample-${DateTime.now().microsecondsSinceEpoch}',
            label: 'Pool $nextSampleIndex',
            trolley: nextTrolley,
            numberOfTrays: 1,
            traySize: _defaultTraySizeForBreakout(breakoutType),
            breakoutType: breakoutType,
          );
    final nextSampleWithHierarchy = _sampleWithActiveBatchHierarchy(
      audit,
      nextSample,
      breakoutType,
    );
    final nextSamples = [...samples, nextSampleWithHierarchy];
    _activeBreakoutSampleIndexes[hatchIndex] = nextSamples.length - 1;
    _persistBreakoutSamples(provider, hatchIndex, breakoutType, nextSamples);
  }

  void _removeActiveResidueTrolley(
    AuditProvider provider,
    int hatchIndex,
    EggBreakoutType breakoutType,
    List<EggBreakoutSampleEntry> samples,
    String trolleyKey,
  ) {
    if (samples.isEmpty) return;
    final trayScopeActive = samples.any(
      (sample) => sample.sampleMode == EggBreakoutSampleMode.tray,
    );
    final remaining = samples
        .where((sample) => _trimmedOrNull(sample.trolley) != trolleyKey)
        .toList();
    final remainingHasTrolley = remaining.any(
      (sample) => _trimmedOrNull(sample.trolley) != null,
    );
    // In tray comparison, or when this is the only trolley, keep the samples
    // and just drop the trolley label (preserving entered counts). For pooled
    // multi-trolley scopes, removing a trolley removes its pool sample so no
    // orphaned no-trolley pool sample is left behind.
    var nextSamples = trayScopeActive || !remainingHasTrolley
        ? [
            for (final sample in samples)
              _trimmedOrNull(sample.trolley) == trolleyKey
                  ? sample.copyWith(trolley: '')
                  : sample,
          ]
        : remaining;
    if (nextSamples.isEmpty) {
      nextSamples = [_defaultPoolBreakoutSample(breakoutType)];
    }
    final nextActiveIndex = nextSamples.indexWhere(
      (sample) => _trimmedOrNull(sample.trolley) == null,
    );
    _activeBreakoutSampleIndexes[hatchIndex] = nextActiveIndex == -1
        ? 0
        : nextActiveIndex;
    _persistBreakoutSamples(provider, hatchIndex, breakoutType, nextSamples);
  }

  void _updateResidueTrolleyField(
    AuditProvider provider,
    int hatchIndex,
    EggBreakoutType breakoutType,
    List<EggBreakoutSampleEntry> samples,
    String trolleyKey,
    String value,
  ) {
    final nextTrolley = _trimmedOrNull(value) ?? 'T';
    final nextSamples = [
      for (final sample in samples)
        _trimmedOrNull(sample.trolley) == trolleyKey
            ? sample.copyWith(trolley: nextTrolley)
            : sample,
    ];
    final nextActiveIndex = nextSamples.indexWhere(
      (sample) => _trimmedOrNull(sample.trolley) == nextTrolley,
    );
    if (nextActiveIndex != -1) {
      _activeBreakoutSampleIndexes[hatchIndex] = nextActiveIndex;
    }
    _persistBreakoutSamples(provider, hatchIndex, breakoutType, nextSamples);
  }

  bool _residueDraftHasEnteredData(AuditModel audit) {
    return audit.haHatched != null ||
        audit.haCulled != null ||
        audit.haDead != null ||
        audit.ebInfertileCount != null ||
        audit.ebEarlyDeadCount != null ||
        audit.ebMidDeadCount != null ||
        audit.ebLateDeadCount != null ||
        audit.ebInternalPipCount != null ||
        audit.ebExternalPipCount != null ||
        audit.ebCrackedCount != null ||
        audit.ebContaminatedCount != null ||
        audit.ebMalpositionCount != null ||
        audit.ebExposedBrainCount != null ||
        audit.ebCrossedBeakCount != null ||
        audit.ebCulledDeadCount != null ||
        _trimmedOrNull(audit.ebTrayBreakoutJson) != null;
  }

  void _removeActiveResidueHouse(AuditProvider provider) {
    if (provider.drafts.isEmpty) return;
    final activeIndex = provider.activeHatchIndex
        .clamp(0, provider.drafts.length - 1)
        .toInt();
    final activeHouse = _residueHouseKey(
      provider.drafts[activeIndex],
      activeIndex,
    );
    final indexes =
        provider.drafts
            .asMap()
            .entries
            .where(
              (entry) =>
                  _residueHouseKey(entry.value, entry.key) == activeHouse,
            )
            .map((entry) => entry.key)
            .toList()
          ..sort((a, b) => b.compareTo(a));
    if (indexes.length >= provider.drafts.length) {
      provider.updateHatchField(0, 'houseId', null);
      provider.updateHatchField(0, 'setterId', null);
      provider.updateHatchField(0, 'hatcherId', null);
      provider.setStationSampleMode(StationSampleModel.sampleModePooled);
      _syncAllMachineBreakoutSamplesWithActiveHierarchy(provider, 0);
      return;
    }
    for (final index in indexes) {
      provider.switchHatch(index);
      provider.removeActiveHatch();
    }
  }

  void _removeActiveResidueMachine(AuditProvider provider) {
    if (provider.drafts.isEmpty) return;
    final activeIndex = provider.activeHatchIndex
        .clamp(0, provider.drafts.length - 1)
        .toInt();
    final activeHouse = _residueHouseKey(
      provider.drafts[activeIndex],
      activeIndex,
    );
    final machineIndexes = provider.drafts
        .asMap()
        .entries
        .where(
          (entry) =>
              _residueHouseKey(entry.value, entry.key) == activeHouse &&
              _isResidueMachineDraft(entry.value),
        )
        .map((entry) => entry.key)
        .toList();
    if (machineIndexes.length <= 1) {
      provider.updateHatchField(activeIndex, 'setterId', null);
      provider.updateHatchField(activeIndex, 'hatcherId', null);
      _syncAllMachineBreakoutSamplesWithActiveHierarchy(provider, activeIndex);
      return;
    }
    provider.removeActiveHatch();
    if (!provider.isCompareMode && provider.drafts.isNotEmpty) {
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
    }
  }

  void _updateResidueHouseField(
    AuditProvider provider,
    int hatchIndex,
    String value,
  ) {
    if (hatchIndex < 0 || hatchIndex >= provider.drafts.length) return;
    final oldHouse = _residueHouseKey(provider.drafts[hatchIndex], hatchIndex);
    final nextHouse = _trimmedOrNull(value) ?? 'H';
    final affectedIndexes = provider.drafts
        .asMap()
        .entries
        .where((entry) => _residueHouseKey(entry.value, entry.key) == oldHouse)
        .map((entry) => entry.key)
        .toList();
    for (final index in affectedIndexes) {
      provider.updateHatchField(index, 'houseId', nextHouse);
      _syncAllMachineBreakoutSamplesWithActiveHierarchy(provider, index);
    }
  }

  void _updateResidueMachineField(
    AuditProvider provider,
    int hatchIndex,
    String field,
    String value,
  ) {
    final fallback = field == 'setterId' ? 'S' : 'H';
    provider.updateHatchField(
      hatchIndex,
      field,
      _trimmedOrNull(value) ?? fallback,
    );
    _syncAllMachineBreakoutSamplesWithActiveHierarchy(provider, hatchIndex);
  }

  void _syncAllMachineBreakoutSamplesWithActiveHierarchy(
    AuditProvider provider,
    int hatchIndex,
  ) {
    _syncBreakoutSamplesWithActiveHierarchy(
      provider,
      hatchIndex,
      EggBreakoutType.candledEggBreakout,
    );
    _syncBreakoutSamplesWithActiveHierarchy(
      provider,
      hatchIndex,
      EggBreakoutType.residueHatchDay,
    );
  }

  void _syncBreakoutSamplesWithActiveHierarchy(
    AuditProvider provider,
    int hatchIndex,
    EggBreakoutType breakoutType,
  ) {
    if (hatchIndex < 0 || hatchIndex >= provider.drafts.length) return;
    final audit = provider.drafts[hatchIndex];
    final samples = EggBreakoutSampleEntry.decodeList(
      audit.ebTrayBreakoutJson,
      fallbackBreakoutType: breakoutType,
    ).where((sample) => sample.breakoutType == breakoutType).toList();
    if (samples.isEmpty) return;
    _persistBreakoutSamples(provider, hatchIndex, breakoutType, samples);
  }

  String _nextHierarchyNumber(Set<String> existing) {
    var maxNumber = 0;
    for (final value in existing) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null && parsed > maxNumber) maxNumber = parsed;
    }
    var next = maxNumber + 1;
    while (existing.contains('$next')) {
      next++;
    }
    return '$next';
  }

  String _nextPrefixedScopeNumber(Set<String> existing, String prefix) {
    var maxNumber = 0;
    for (final value in existing) {
      final parsed = int.tryParse(_machineLabelPart(value, prefix, ''));
      if (parsed != null && parsed > maxNumber) maxNumber = parsed;
    }
    var next = maxNumber + 1;
    while (existing.any(
      (value) => _machineLabelPart(value, prefix, '') == '$next',
    )) {
      next++;
    }
    return '$next';
  }

  String _nextResidueMachineNumber(
    List<MapEntry<int, AuditModel>> existingMachines,
  ) {
    final existingNumbers = <String>{};
    var maxNumber = 0;
    for (final entry in existingMachines) {
      final audit = entry.value;
      for (final part in [
        _machineLabelPart(audit.setterId, 'S', ''),
        _machineLabelPart(audit.hatcherId, 'H', ''),
      ]) {
        if (part.isEmpty) continue;
        existingNumbers.add(part);
        final parsed = int.tryParse(part);
        if (parsed != null && parsed > maxNumber) maxNumber = parsed;
      }
    }
    var next = maxNumber + 1;
    while (existingNumbers.contains('$next')) {
      next++;
    }
    return '$next';
  }

  String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _batchLabelPart(String? raw, String fallback) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return fallback;
    return value;
  }

  String _machineLabelPart(String? raw, String prefix, String fallback) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return fallback;
    if (value.toLowerCase() == prefix.toLowerCase()) return '';
    if (value.toLowerCase().startsWith(prefix.toLowerCase())) {
      return value.substring(prefix.length);
    }
    return value;
  }

  String? _residueHouseFieldValue(String? value) {
    return _isPrefixOnly(value, 'H') ? null : value;
  }

  String? _residueMachineFieldValue(String? value, String prefix) {
    return _isPrefixOnly(value, prefix) ? null : value;
  }

  String? _residueTrolleyFieldValue(String? value) {
    if (_isPrefixOnly(value, 'T')) return null;
    final fieldValue = _machineLabelPart(value, 'T', '');
    return fieldValue.isEmpty ? null : fieldValue;
  }

  bool _isPrefixOnly(String? value, String prefix) {
    return value?.trim().toLowerCase() == prefix.toLowerCase();
  }

  Widget _buildBreakoutTypeCard(
    AuditProvider provider,
    int hatchIndex,
    AuditModel audit,
    EggBreakoutType breakoutType,
  ) {
    final storageDays = audit.ebStorageDays ?? audit.haStorageDays ?? 0;
    final bmkAgeDays = _calculateBmkAgeDays(
      provider,
      audit,
      breakoutType,
      storageDays: storageDays,
    );
    final bmkAgeWeeks = _displayBmkWeeks(bmkAgeDays, audit, breakoutType);

    return LayoutBuilder(
      builder: (context, constraints) {
        final useWideHeader = constraints.maxWidth >= 560;
        final topCardHeight = useWideHeader ? 112.0 : 132.0;
        final headerTitle = Text(
          'Breakout Type',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.heading.copyWith(
            fontSize: 22,
            height: 1.08,
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        );
        final selector = Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
              width: 1.2,
            ),
          ),
          child: _buildBreakoutTypeSelector(
            provider,
            hatchIndex,
            audit,
            breakoutType,
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: const ValueKey('hatch-analysis-breakout-header'),
              constraints: BoxConstraints(minHeight: topCardHeight),
              width: double.infinity,
              padding: EdgeInsets.all(useWideHeader ? 20 : 18),
              decoration: _gradientHeaderDecoration(),
              child: useWideHeader
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(width: 170, child: headerTitle),
                        const SizedBox(width: AppSizes.spaceLg),
                        Expanded(child: selector),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        headerTitle,
                        const SizedBox(height: AppSizes.spaceMd),
                        selector,
                      ],
                    ),
            ),
            const SizedBox(height: AppSizes.spaceMd),
            Container(
              key: const ValueKey('hatch-analysis-context-card'),
              constraints: BoxConstraints(minHeight: topCardHeight),
              width: double.infinity,
              padding: EdgeInsets.all(useWideHeader ? 20 : 18),
              decoration: _gradientHeaderDecoration(),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildGradientInfoTile(
                        'Flock',
                        widget.context.flockId,
                      ),
                    ),
                    const SizedBox(width: AppSizes.spaceSm),
                    Expanded(
                      child: _buildGradientInfoTile(
                        'Breed',
                        widget.context.breed ?? '--',
                      ),
                    ),
                    const SizedBox(width: AppSizes.spaceSm),
                    Expanded(
                      child: _buildGradientInfoTile(
                        'BMK Age',
                        _formatBmkWeeksValue(bmkAgeWeeks),
                        key: const ValueKey('breakout-bmk-age-display-card'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSizes.spaceSm),
            Container(
              key: const ValueKey('hatch-analysis-required-entry-card'),
              width: double.infinity,
              padding: EdgeInsets.all(useWideHeader ? 12 : 10),
              decoration: _storageEntryCardDecoration(),
              child: Wrap(
                spacing: AppSizes.spaceSm,
                runSpacing: AppSizes.spaceSm,
                children: [
                  _buildGradientNumberTile(
                    cardKey: const ValueKey('breakout-storage-days-entry-card'),
                    key: const ValueKey('breakout-storage-days'),
                    label: 'Storage days',
                    value: storageDays,
                    enabled: !provider.isReadOnly,
                    prominent: true,
                    clearZeroOnFocus: true,
                    onChanged: (value) {
                      final parsed = int.tryParse(value);
                      provider.updateHatchField(
                        hatchIndex,
                        'haStorageDays',
                        parsed,
                      );
                      provider.updateHatchField(
                        hatchIndex,
                        'ebStorageDays',
                        parsed,
                      );
                      _persistBmkAges(provider, hatchIndex);
                    },
                  ),
                  if (breakoutType == EggBreakoutType.candledEggBreakout)
                    _buildGradientNumberTile(
                      key: const ValueKey('breakout-candled-age'),
                      label: 'Candled age',
                      value: audit.ebBreakoutAgeDays ?? 10,
                      enabled: !provider.isReadOnly,
                      onChanged: (value) {
                        provider.updateHatchField(
                          hatchIndex,
                          'ebBreakoutAgeDays',
                          int.tryParse(value),
                        );
                        _persistBmkAges(provider, hatchIndex);
                      },
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResidueBatchResultsCard(
    AuditProvider provider,
    int hatchIndex,
    AuditModel audit,
  ) {
    final storageDays = audit.ebStorageDays ?? audit.haStorageDays ?? 0;
    final bmkAgeDays = _calculateBmkAgeDays(
      provider,
      audit,
      EggBreakoutType.residueHatchDay,
      storageDays: storageDays,
    );
    final breed = widget.context.breed ?? audit.soBreed ?? audit.hoBreed;
    final breedBenchmarkFuture = bmkAgeDays == null || breed == null
        ? null
        : _breedBenchmarkFuture(calculatedBmkAgeDays: bmkAgeDays, breed: breed);
    final metrics = ResidueBatchMetrics.fromAudit(audit);

    return _surface(
      containerKey: const ValueKey('residue-batch-results-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultsHeader(
            title: 'Hatch Results',
            subtitle:
                'Hatch ${_residueResultScopeLabel(provider, audit, hatchIndex)}',
          ),
          const SizedBox(height: AppSizes.spaceLg),
          _resultsGroup(
            title: 'Hatch totals',
            child: _responsiveTileGrid(
              minTileWidth: 150,
              children: [
                _residueCountField(
                  wrapperKey: const ValueKey('residue-total-eggs-set'),
                  fieldKey: ValueKey('residue-total-eggs-set-$hatchIndex'),
                  label: 'Total eggs set',
                  value: audit.haTotalEggsSet,
                  enabled: !provider.isReadOnly,
                  onChanged: (value) => provider.updateHatchField(
                    hatchIndex,
                    'haTotalEggsSet',
                    int.tryParse(value),
                  ),
                ),
                _residueCountField(
                  wrapperKey: const ValueKey('residue-hatched-chicks'),
                  fieldKey: ValueKey('residue-hatched-chicks-$hatchIndex'),
                  label: 'Hatched chicks',
                  value: audit.haHatched,
                  enabled: !provider.isReadOnly,
                  onChanged: (value) => provider.updateHatchField(
                    hatchIndex,
                    'haHatched',
                    int.tryParse(value),
                  ),
                ),
                _residueCountField(
                  wrapperKey: const ValueKey('residue-culled-chicks'),
                  fieldKey: ValueKey('residue-culled-chicks-$hatchIndex'),
                  label: 'Culled',
                  value: audit.haCulled,
                  enabled: !provider.isReadOnly,
                  onChanged: (value) => provider.updateHatchField(
                    hatchIndex,
                    'haCulled',
                    int.tryParse(value),
                  ),
                ),
                _residueCountField(
                  wrapperKey: const ValueKey('residue-dead-chicks'),
                  fieldKey: ValueKey('residue-dead-chicks-$hatchIndex'),
                  label: 'Dead',
                  value: audit.haDead,
                  enabled: !provider.isReadOnly,
                  onChanged: (value) => provider.updateHatchField(
                    hatchIndex,
                    'haDead',
                    int.tryParse(value),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.spaceLg),
          FutureBuilder<Map<String, Object?>?>(
            future: breedBenchmarkFuture,
            builder: (context, snapshot) {
              final benchmark = snapshot.data;
              return _resultsGroup(
                title: 'Performance',
                child: _performanceSummaryCard(
                  metrics: [
                    _PerformanceMetric(
                      label: 'Hatchability',
                      actual: metrics.hatchabilityPct,
                      target: _doubleValue(benchmark?['hatchabilityPct']),
                      targetLabel: 'BMK',
                      lowerIsBad: true,
                    ),
                    _PerformanceMetric(
                      label: 'Fertility',
                      actual: metrics.fertilityPct,
                      target: _doubleValue(benchmark?['fertilityPct']),
                      targetLabel: 'BMK',
                      lowerIsBad: true,
                    ),
                    _PerformanceMetric(
                      label: 'HOF',
                      actual: metrics.hofPct,
                      target: _doubleValue(benchmark?['hofPct']),
                      targetLabel: 'BMK',
                      lowerIsBad: true,
                    ),
                    _PerformanceMetric(
                      label: 'Culled %',
                      actual: metrics.culledPct,
                      target: 1.0,
                      targetLabel: 'Limit',
                      lowerIsBad: false,
                    ),
                    _PerformanceMetric(
                      label: 'Dead %',
                      actual: metrics.deadPct,
                      target: 0.2,
                      targetLabel: 'Limit',
                      lowerIsBad: false,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _performanceSummaryCard({required List<_PerformanceMetric> metrics}) {
    return Container(
      key: const ValueKey('hatch-performance-summary-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8E2EC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEAF4FF), Color(0xFFF8FBFF)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xFFD5E7FF)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Actual',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.infoText,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  'Benchmark / limit',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < metrics.length; index++)
            _performanceMetricRow(
              metrics[index],
              isLast: index == metrics.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _performanceMetricRow(
    _PerformanceMetric metric, {
    required bool isLast,
  }) {
    final hasAlert =
        metric.actual != null &&
        metric.target != null &&
        (metric.lowerIsBad
            ? metric.actual! < metric.target!
            : metric.actual! > metric.target!);
    final delta = metric.actual != null && metric.target != null
        ? metric.actual! - metric.target!
        : null;
    final tone = hasAlert ? AppColors.statusError : AppColors.primary;
    final actualText = _formatPercent(metric.actual);
    final targetText = '${metric.targetLabel} ${_formatPercent(metric.target)}';
    final gapText = 'Gap ${_formatDelta(delta)}';

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: hasAlert ? const Color(0xFFFFF7F8) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasAlert ? const Color(0xFFFECACA) : const Color(0xFFE6EEF7),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 340;
            final labelAndValue = Row(
              children: [
                Container(
                  width: 4,
                  height: 46,
                  decoration: BoxDecoration(
                    color: tone,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metric.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        actualText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.sectionTitle.copyWith(
                          color: hasAlert
                              ? const Color(0xFFBE123C)
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  labelAndValue,
                  const SizedBox(height: 8),
                  _performanceTargetBlock(
                    targetText: targetText,
                    gapText: gapText,
                    hasAlert: hasAlert,
                    stretch: true,
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: labelAndValue),
                const SizedBox(width: 10),
                _performanceTargetBlock(
                  targetText: targetText,
                  gapText: gapText,
                  hasAlert: hasAlert,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _performanceTargetBlock({
    required String targetText,
    required String gapText,
    required bool hasAlert,
    bool stretch = false,
  }) {
    return Container(
      width: stretch ? double.infinity : 126,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: hasAlert ? AppColors.statusErrorBg : AppColors.infoBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            targetText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              color: hasAlert ? const Color(0xFFBE123C) : AppColors.infoText,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            gapText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              color: hasAlert
                  ? const Color(0xFFBE123C)
                  : AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _residueTextNumberField({
    required Key wrapperKey,
    required Key fieldKey,
    required String label,
    required String? value,
    required bool enabled,
    required ValueChanged<String> onChanged,
  }) {
    return _residueEntryTile(
      key: wrapperKey,
      label: label,
      child: AuditNumericFormField(
        key: fieldKey,
        initialValue: value ?? '',
        enabled: enabled,
        decoration: _embeddedInputDecoration(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _residueCountField({
    required Key wrapperKey,
    required Key fieldKey,
    required String label,
    required int? value,
    required bool enabled,
    required ValueChanged<String> onChanged,
  }) {
    return _residueEntryTile(
      key: wrapperKey,
      label: label,
      child: AuditNumericFormField(
        key: fieldKey,
        initialValue: value?.toString() ?? '',
        enabled: enabled,
        decoration: _embeddedInputDecoration(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _resultsHeader({required String title, required String subtitle}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.sectionTitle.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _resultsGroup({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.spaceMd),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSizes.spaceSm),
          child,
        ],
      ),
    );
  }

  Widget _responsiveTileGrid({
    required double minTileWidth,
    required List<Widget> children,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSizes.spaceSm;
        final availableWidth = constraints.maxWidth;
        final columnCount = (availableWidth / minTileWidth)
            .floor()
            .clamp(1, 3)
            .toInt();
        final tileWidth =
            (availableWidth - (gap * (columnCount - 1))) / columnCount;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(width: tileWidth, child: child),
          ],
        );
      },
    );
  }

  Widget _residueEntryTile({
    required Key key,
    required String label,
    required Widget child,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8E2EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  BoxDecoration _gradientHeaderDecoration() {
    return BoxDecoration(
      gradient: AppColors.brandGradient,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: AppColors.cardShadow,
          blurRadius: 16,
          offset: Offset(0, 8),
        ),
      ],
    );
  }

  BoxDecoration _storageEntryCardDecoration() {
    return BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.borderDefault, width: 1.2),
      boxShadow: const [
        BoxShadow(
          color: AppColors.cardShadow,
          blurRadius: 12,
          offset: Offset(0, 6),
        ),
      ],
    );
  }

  Widget _buildBreakoutTypeSelector(
    AuditProvider provider,
    int hatchIndex,
    AuditModel audit,
    EggBreakoutType selectedType,
  ) {
    final enabled = !provider.isReadOnly && !provider.isLoading;
    final options = EggBreakoutType.values;

    return LayoutBuilder(
      builder: (context, constraints) {
        final pills = options.map((type) {
          return _buildBreakoutTypePill(
            type: type,
            selected: type == selectedType,
            enabled: enabled,
            onTap: () => _setBreakoutType(provider, hatchIndex, audit, type),
          );
        }).toList();

        if (constraints.maxWidth < 320) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final pill in pills) ...[
                pill,
                if (pill != pills.last) const SizedBox(height: 8),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (final pill in pills) ...[
              Expanded(child: pill),
              if (pill != pills.last) const SizedBox(width: 8),
            ],
          ],
        );
      },
    );
  }

  Widget _buildGradientInfoTile(String label, String value, {Key? key}) {
    return Container(
      key: key,
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
            style: AppTextStyles.body.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientNumberTile({
    Key? cardKey,
    required Key key,
    required String label,
    required int? value,
    required bool enabled,
    required ValueChanged<String> onChanged,
    bool prominent = false,
    bool clearZeroOnFocus = false,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: prominent ? 196 : 124,
        maxWidth: prominent ? 280 : 180,
      ),
      child: Container(
        key: cardKey,
        padding: EdgeInsets.all(prominent ? 12 : 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(prominent ? 10 : 8),
          border: Border.all(
            color: prominent
                ? AppColors.borderFocused.withValues(alpha: 0.18)
                : AppColors.borderDefault,
            width: prominent ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: KeyedSubtree(
                    key: key,
                    child: _GradientNumberInput(
                      value: value,
                      enabled: enabled,
                      onChanged: onChanged,
                      clearZeroOnFocus: clearZeroOnFocus,
                    ),
                  ),
                ),
                if (prominent) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.edit_rounded,
                    size: 18,
                    color: AppColors.primary.withValues(alpha: 0.82),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakoutTypePill({
    required EggBreakoutType type,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final foreground = selected ? AppColors.primary : Colors.white;
    final background = selected
        ? Colors.white
        : Colors.white.withValues(alpha: 0.12);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.28),
            ),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                type.displayLabel,
                maxLines: 1,
                style: AppTextStyles.caption.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setBreakoutType(
    AuditProvider provider,
    int hatchIndex,
    AuditModel audit,
    EggBreakoutType nextType,
  ) {
    provider.updateHatchField(
      hatchIndex,
      'ebBreakoutType',
      nextType.storageValue,
    );
    if (nextType == EggBreakoutType.candledEggBreakout &&
        audit.ebBreakoutAgeDays == null) {
      provider.updateHatchField(hatchIndex, 'ebBreakoutAgeDays', 10);
    }
    _persistBmkAges(provider, hatchIndex);
  }

  Widget _buildBreakoutSampleSection(
    AuditProvider provider,
    int hatchIndex,
    AuditModel audit,
    EggBreakoutType breakoutType,
  ) {
    final decodedSamples = EggBreakoutSampleEntry.decodeList(
      audit.ebTrayBreakoutJson,
      fallbackBreakoutType:
          _legacyBreakoutJsonNeedsTypeFallback(audit.ebTrayBreakoutJson)
          ? breakoutType
          : null,
    );
    final breakoutSamples = _normalizeBreakoutSamples(
      decodedSamples
          .where((sample) => sample.breakoutType == breakoutType)
          .toList(),
    );
    final traySamples = breakoutSamples
        .where((sample) => sample.sampleMode == EggBreakoutSampleMode.tray)
        .toList();
    final samples = _resolveWorkingSamplesFrom(breakoutSamples, breakoutType);
    final totalSample = samples.fold<int>(
      0,
      (sum, sample) => sum + (sample.totalSample ?? 0),
    );
    final activeIndex = _activeBreakoutSampleIndex(hatchIndex, samples.length);
    final storageDays = audit.ebStorageDays ?? audit.haStorageDays ?? 0;
    final bmkAgeDays = _calculateBmkAgeDays(
      provider,
      audit,
      breakoutType,
      storageDays: storageDays,
    );
    final benchmarkFuture = bmkAgeDays == null
        ? null
        : _breakoutBenchmarkFuture(bmkAgeDays);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDefault),
      ),
      padding: const EdgeInsets.all(AppSizes.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            traySamples.isNotEmpty
                ? '${traySamples.length} tray${traySamples.length == 1 ? '' : 's'} · $totalSample eggs sampled'
                : totalSample > 0
                ? 'Pool sample · $totalSample eggs sampled'
                : 'Pool sample · no tray comparison',
            style: AppTextStyles.caption.copyWith(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          _buildSampleControlCard(
            title: 'Tray scope',
            child: _buildTraySampleControls(
              provider: provider,
              hatchIndex: hatchIndex,
              audit: audit,
              samples: samples,
              breakoutType: breakoutType,
              activeIndex: activeIndex,
            ),
          ),
          _buildBreakoutSampleCard(
            provider,
            hatchIndex,
            activeIndex,
            samples[activeIndex],
            samples,
            breakoutType,
            active: true,
            benchmarkFuture: benchmarkFuture,
          ),
        ],
      ),
    );
  }

  Widget _buildTraySampleControls({
    required AuditProvider provider,
    required int hatchIndex,
    required AuditModel audit,
    required List<EggBreakoutSampleEntry> samples,
    required EggBreakoutType breakoutType,
    required int activeIndex,
  }) {
    final trayScopeActive = samples.any(
      (sample) => sample.sampleMode == EggBreakoutSampleMode.tray,
    );
    final chips = trayScopeActive
        ? [
            for (final entry in samples.asMap().entries)
              ChoiceChip(
                key: ValueKey('breakout-sample-tab-${entry.key}'),
                label: Text(entry.value.label),
                selected: entry.key == activeIndex,
                onSelected: provider.isReadOnly
                    ? null
                    : (_) => _activateBreakoutSample(hatchIndex, entry.key),
                selectedColor: AppColors.primary.withValues(alpha: 0.14),
                checkmarkColor: AppColors.primary,
                labelStyle: AppTextStyles.body.copyWith(
                  color: entry.key == activeIndex
                      ? AppColors.primary
                      : AppColors.textBody,
                  fontWeight: FontWeight.w800,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: entry.key == activeIndex
                        ? AppColors.primary
                        : AppColors.borderDefault,
                  ),
                ),
              ),
          ]
        : [
            ChoiceChip(
              key: const ValueKey('breakout-pool-sample-tab'),
              label: const Text('Pool'),
              selected: true,
              onSelected: null,
              selectedColor: AppColors.primary.withValues(alpha: 0.14),
              checkmarkColor: AppColors.primary,
              labelStyle: AppTextStyles.body.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ];

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTrayActionButton(
          key: const ValueKey('breakout-add-sample'),
          tooltip: context.tr('Add tray sample'),
          icon: Icons.add,
          onPressed: provider.isReadOnly
              ? null
              : () {
                  final nextIndex = trayScopeActive ? samples.length + 1 : 1;
                  final activeTrolley = _trimmedOrNull(
                    samples[activeIndex].trolley,
                  );
                  final nextSample = EggBreakoutSampleEntry.tray(
                    id: 'sample-${DateTime.now().microsecondsSinceEpoch}',
                    label: 'Tray $nextIndex',
                    trolley: activeTrolley,
                    position: 'random',
                    traySize: _defaultTraySizeForBreakout(breakoutType),
                    breakoutType: breakoutType,
                  );
                  final nextSampleWithHierarchy =
                      _sampleWithActiveBatchHierarchy(
                        audit,
                        nextSample,
                        breakoutType,
                      );
                  final nextSamples = trayScopeActive
                      ? [...samples, nextSampleWithHierarchy]
                      : [nextSampleWithHierarchy];
                  _activeBreakoutSampleIndexes[hatchIndex] =
                      nextSamples.length - 1;
                  _persistBreakoutSamples(provider, hatchIndex, breakoutType, [
                    ...nextSamples,
                  ]);
                },
        ),
        if (trayScopeActive) ...[
          const SizedBox(width: 8),
          _buildTrayActionButton(
            key: const ValueKey('breakout-remove-sample'),
            tooltip: context.tr('Remove active tray sample'),
            icon: Icons.remove,
            onPressed: provider.isReadOnly
                ? null
                : () {
                    final next = [...samples]..removeAt(activeIndex);
                    final nextActiveIndex = next.isEmpty
                        ? 0
                        : activeIndex.clamp(0, next.length - 1).toInt();
                    _activeBreakoutSampleIndexes[hatchIndex] = nextActiveIndex;
                    _persistBreakoutSamples(
                      provider,
                      hatchIndex,
                      breakoutType,
                      next,
                    );
                    if (next.isNotEmpty) {
                      _scrollToBreakoutSample(next[nextActiveIndex].id);
                    }
                  },
          ),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [...chips, actions],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: chips,
              ),
            ),
            const SizedBox(width: 8),
            actions,
          ],
        );
      },
    );
  }

  Widget _buildTrayActionButton({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton.filledTonal(
      key: key,
      tooltip: context.tr(tooltip),
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        fixedSize: const Size(44, 44),
        shape: const CircleBorder(),
      ),
    );
  }

  Widget _buildBreakoutSampleCard(
    AuditProvider provider,
    int hatchIndex,
    int sampleIndex,
    EggBreakoutSampleEntry sample,
    List<EggBreakoutSampleEntry> samples,
    EggBreakoutType breakoutType, {
    required bool active,
    required Future<Map<String, Object?>?>? benchmarkFuture,
  }) {
    final cardKey = _sampleCardKeys.putIfAbsent(sample.id, () => GlobalKey());

    return Container(
      key: cardKey,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? AppColors.primary : const Color(0xFFE5E7EB),
          width: active ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _breakoutSampleHeaderRow(
            provider: provider,
            hatchIndex: hatchIndex,
            sampleIndex: sampleIndex,
            sample: sample,
            samples: samples,
            breakoutType: breakoutType,
          ),
          const SizedBox(height: 14),
          FutureBuilder<Map<String, Object?>?>(
            future: benchmarkFuture,
            builder: (context, snapshot) {
              final benchmark = snapshot.data;
              return Column(
                children: [
                  for (final field in breakoutType.countFields) ...[
                    _buildBreakoutCountRow(
                      provider: provider,
                      hatchIndex: hatchIndex,
                      samples: samples,
                      sampleIndex: sampleIndex,
                      field: field,
                      sample: sample,
                      breakoutType: breakoutType,
                      bmkPercent: _bmkPercentForField(benchmark, field.key),
                    ),
                    if (field != breakoutType.countFields.last)
                      const SizedBox(height: 8),
                  ],
                ],
              );
            },
          ),
          if (_legacyBreakoutPhotoEntries(sample).isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildLegacyBreakoutPhotoControl(
              provider: provider,
              hatchIndex: hatchIndex,
              sample: sample,
              breakoutType: breakoutType,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegacyBreakoutPhotoControl({
    required AuditProvider provider,
    required int hatchIndex,
    required EggBreakoutSampleEntry sample,
    required EggBreakoutType breakoutType,
  }) {
    final entries = _legacyBreakoutPhotoEntries(sample);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Photos',
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        MultiPhotoButton(
          photoPaths: [for (final entry in entries) entry.value],
          enabled: false,
          panelName: _breakoutPanelNameForType(breakoutType),
          panelRowId: _breakoutPhotoRowId(
            provider,
            hatchIndex,
            sample.id,
            breakoutType,
          ),
          fieldKey: 'breakout_photo',
          onPhotoCaptured: (_, _) {},
        ),
      ],
    );
  }

  Widget _breakoutSampleHeaderRow({
    required AuditProvider provider,
    required int hatchIndex,
    required int sampleIndex,
    required EggBreakoutSampleEntry sample,
    required List<EggBreakoutSampleEntry> samples,
    required EggBreakoutType breakoutType,
  }) {
    if (sample.sampleMode == EggBreakoutSampleMode.pool) {
      return _responsiveTileGrid(
        minTileWidth: 130,
        children: [
          _breakoutNumberField(
            provider: provider,
            hatchIndex: hatchIndex,
            samples: samples,
            sampleIndex: sampleIndex,
            label: 'Sample size',
            value: sample.totalSample ?? sample.traySize,
            sampleField: _BreakoutSampleField.traySize,
            breakoutType: breakoutType,
          ),
        ],
      );
    }

    final showsPosition = breakoutType != EggBreakoutType.freshEggBreakout;
    final hierarchyFields = <Widget>[
      if (!showsPosition)
        _breakoutTextField(
          provider: provider,
          hatchIndex: hatchIndex,
          samples: samples,
          sampleIndex: sampleIndex,
          fieldKey: 'house',
          label: 'House',
          value: sample.house ?? '',
          breakoutType: breakoutType,
          onTextChanged: (text) => sample.copyWith(house: text.trim()),
        ),
      _breakoutTextField(
        provider: provider,
        hatchIndex: hatchIndex,
        samples: samples,
        sampleIndex: sampleIndex,
        fieldKey: 'tray',
        label: 'Tray',
        value: sample.tray ?? sample.label,
        breakoutType: breakoutType,
        onTextChanged: (text) {
          final trimmed = text.trim();
          return sample.copyWith(
            tray: trimmed,
            label: trimmed.isEmpty ? sample.label : trimmed,
          );
        },
      ),
    ];
    final traySizeField = _breakoutNumberField(
      provider: provider,
      hatchIndex: hatchIndex,
      samples: samples,
      sampleIndex: sampleIndex,
      label: 'Tray size',
      value: sample.traySize,
      sampleField: _BreakoutSampleField.traySize,
      breakoutType: breakoutType,
    );

    return _responsiveTileGrid(
      minTileWidth: 130,
      children: [
        ...hierarchyFields,
        if (showsPosition)
          _breakoutPositionField(
            provider: provider,
            hatchIndex: hatchIndex,
            samples: samples,
            sampleIndex: sampleIndex,
            sample: sample,
            breakoutType: breakoutType,
          ),
        traySizeField,
      ],
    );
  }

  Widget _breakoutTextField({
    required AuditProvider provider,
    required int hatchIndex,
    required List<EggBreakoutSampleEntry> samples,
    required int sampleIndex,
    required String fieldKey,
    required String label,
    required String value,
    required EggBreakoutType breakoutType,
    required EggBreakoutSampleEntry Function(String text) onTextChanged,
  }) {
    return TextFormField(
      key: ValueKey('${samples[sampleIndex].id}-$fieldKey'),
      initialValue: value,
      enabled: !provider.isReadOnly,
      decoration: _inputDecoration(label),
      onChanged: (text) {
        _replaceBreakoutSample(
          provider,
          hatchIndex,
          breakoutType,
          samples,
          sampleIndex,
          onTextChanged(text),
        );
      },
    );
  }

  Widget _breakoutPositionField({
    required AuditProvider provider,
    required int hatchIndex,
    required List<EggBreakoutSampleEntry> samples,
    required int sampleIndex,
    required EggBreakoutSampleEntry sample,
    required EggBreakoutType breakoutType,
  }) {
    const positions = ['top', 'mid', 'bottom', 'random'];
    final value = positions.contains(sample.position) ? sample.position : null;
    final positionTextStyle = AppTextStyles.body.copyWith(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    );
    return DropdownButtonFormField<String>(
      key: ValueKey('${sample.id}-position'),
      initialValue: value,
      isExpanded: true,
      decoration: _inputDecoration('Position'),
      style: positionTextStyle,
      items: [
        DropdownMenuItem(
          value: 'top',
          child: Text('Top', style: positionTextStyle),
        ),
        DropdownMenuItem(
          value: 'mid',
          child: Text('Mid', style: positionTextStyle),
        ),
        DropdownMenuItem(
          value: 'bottom',
          child: Text('Bottom', style: positionTextStyle),
        ),
        DropdownMenuItem(
          value: 'random',
          child: Text('Random', style: positionTextStyle),
        ),
      ],
      onChanged: provider.isReadOnly
          ? null
          : (nextPosition) {
              _replaceBreakoutSample(
                provider,
                hatchIndex,
                breakoutType,
                samples,
                sampleIndex,
                sample.copyWith(position: nextPosition),
              );
            },
    );
  }

  Widget _breakoutNumberField({
    required AuditProvider provider,
    required int hatchIndex,
    required List<EggBreakoutSampleEntry> samples,
    required int sampleIndex,
    required String label,
    required Object? value,
    required EggBreakoutType breakoutType,
    _BreakoutSampleField? sampleField,
    String? countKey,
    String? suffixText,
  }) {
    return AuditNumericFormField(
      key: ValueKey('${samples[sampleIndex].id}-$label'),
      initialValue: _intValue(value)?.toString() ?? '',
      enabled: !provider.isReadOnly,
      decoration: _inputDecoration(label).copyWith(suffixText: suffixText),
      onChanged: (text) {
        final sample = samples[sampleIndex];
        final parsed = int.tryParse(text) ?? 0;
        var nextSample = sample;
        if (sampleField == _BreakoutSampleField.traySize) {
          nextSample = nextSample.copyWith(traySize: parsed);
        } else if (sampleField == _BreakoutSampleField.numberOfTrays) {
          nextSample = nextSample.copyWith(numberOfTrays: parsed);
        } else if (countKey != null) {
          final counts = Map<String, int>.from(sample.counts);
          counts[countKey] = parsed;
          nextSample = nextSample.copyWith(counts: counts);
        }
        _replaceBreakoutSample(
          provider,
          hatchIndex,
          breakoutType,
          samples,
          sampleIndex,
          nextSample,
        );
      },
    );
  }

  Widget _buildBreakoutCountRow({
    required AuditProvider provider,
    required int hatchIndex,
    required List<EggBreakoutSampleEntry> samples,
    required int sampleIndex,
    required EggBreakoutCountField field,
    required EggBreakoutSampleEntry sample,
    required EggBreakoutType breakoutType,
    required double? bmkPercent,
  }) {
    final percent = sample.percentageFor(field.key);
    final enteredCount = sample.counts[field.key];
    final hasEnteredCount = enteredCount != null && enteredCount > 0;
    final initialCountText = hasEnteredCount ? enteredCount.toString() : '';
    final exceedsBmk =
        hasEnteredCount &&
        percent != null &&
        bmkPercent != null &&
        percent > bmkPercent;
    final diffPercent = percent != null && bmkPercent != null
        ? percent - bmkPercent
        : null;
    final focusNode = _breakoutCountFocusNode(sample, field);
    final metricSummary =
        '${_formatPercent(percent)} | BMK ${_formatPercent(bmkPercent)} | Gap ${_formatGap(diffPercent)}';

    return Container(
      key: ValueKey('breakout-row-${field.key}'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: exceedsBmk ? const Color(0xFFFFF1F2) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: exceedsBmk ? const Color(0xFFF43F5E) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Stack(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: KeyedSubtree(
                  key: ValueKey('breakout-count-${field.key}'),
                  child: TextFormField(
                    key: ValueKey('breakout-count-${sample.id}-${field.key}'),
                    initialValue: initialCountText,
                    enabled: !provider.isReadOnly,
                    focusNode: focusNode,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _inputDecoration(field.label),
                    onChanged: (text) {
                      final counts = Map<String, int>.from(sample.counts);
                      final parsed = int.tryParse(text);
                      if (parsed == null || parsed <= 0) {
                        counts.remove(field.key);
                      } else {
                        counts[field.key] = parsed;
                      }
                      _replaceBreakoutSample(
                        provider,
                        hatchIndex,
                        breakoutType,
                        samples,
                        sampleIndex,
                        sample.copyWith(counts: counts),
                      );
                    },
                    onEditingComplete: () => _focusNextBreakoutCount(
                      samples: samples,
                      sampleIndex: sampleIndex,
                      breakoutType: breakoutType,
                      field: field,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: _breakoutMetricSummaryTile(
                  key: ValueKey('breakout-summary-${field.key}'),
                  value: metricSummary,
                  emphasized: bmkPercent != null || diffPercent != null,
                  alert: exceedsBmk,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                key: ValueKey('breakout-photo-${sample.id}-${field.key}'),
                width: 64,
                height: 56,
                child: _buildBreakoutMetricPhotoControl(
                  provider: provider,
                  hatchIndex: hatchIndex,
                  samples: samples,
                  sampleIndex: sampleIndex,
                  sample: sample,
                  breakoutType: breakoutType,
                  field: field,
                ),
              ),
            ],
          ),
          if (exceedsBmk)
            SizedBox.shrink(key: ValueKey('breakout-alert-${field.key}')),
        ],
      ),
    );
  }

  Widget _buildBreakoutMetricPhotoControl({
    required AuditProvider provider,
    required int hatchIndex,
    required List<EggBreakoutSampleEntry> samples,
    required int sampleIndex,
    required EggBreakoutSampleEntry sample,
    required EggBreakoutType breakoutType,
    required EggBreakoutCountField field,
  }) {
    final entries = _breakoutPhotoEntriesForField(sample, field.key);
    return MultiPhotoButton(
      singleRow: true,
      photoPaths: [for (final entry in entries) entry.value],
      enabled: !provider.isReadOnly,
      panelName: _breakoutPanelNameForType(breakoutType),
      panelRowId: _breakoutPhotoRowId(
        provider,
        hatchIndex,
        sample.id,
        breakoutType,
        field.key,
      ),
      fieldKey: _breakoutPhotoFieldKey(field.key),
      onPhotoCaptured: (index, path) {
        final photos = Map<String, String>.from(sample.photos);
        if (index >= 0 && index < entries.length) {
          photos[entries[index].key] = path;
        } else {
          photos['${_breakoutPhotoStoragePrefix(field.key)}photo_${DateTime.now().microsecondsSinceEpoch}'] =
              path;
        }
        _replaceBreakoutSample(
          provider,
          hatchIndex,
          breakoutType,
          samples,
          sampleIndex,
          sample.copyWith(photos: photos),
        );
      },
      onPhotoRemoved: (index) {
        if (index < 0 || index >= entries.length) return;
        final photos = Map<String, String>.from(sample.photos)
          ..remove(entries[index].key);
        _replaceBreakoutSample(
          provider,
          hatchIndex,
          breakoutType,
          samples,
          sampleIndex,
          sample.copyWith(photos: photos),
        );
      },
    );
  }

  List<MapEntry<String, String>> _breakoutPhotoEntriesForField(
    EggBreakoutSampleEntry sample,
    String fieldKey,
  ) {
    final prefix = _breakoutPhotoStoragePrefix(fieldKey);
    return sample.photos.entries
        .where((entry) => entry.key.startsWith(prefix))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
  }

  List<MapEntry<String, String>> _legacyBreakoutPhotoEntries(
    EggBreakoutSampleEntry sample,
  ) {
    final prefixes = <String>{
      for (final type in EggBreakoutType.values)
        for (final field in type.countFields)
          _breakoutPhotoStoragePrefix(field.key),
    };
    return sample.photos.entries
        .where(
          (entry) => !prefixes.any((prefix) => entry.key.startsWith(prefix)),
        )
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
  }

  String _breakoutPhotoStoragePrefix(String fieldKey) => '$fieldKey:';

  String _breakoutPhotoFieldKey(String fieldKey) =>
      'breakout_${fieldKey}_photo';

  String _breakoutCountFocusKey(
    EggBreakoutSampleEntry sample,
    EggBreakoutCountField field,
  ) {
    return '${sample.id}:${field.key}';
  }

  FocusNode _breakoutCountFocusNode(
    EggBreakoutSampleEntry sample,
    EggBreakoutCountField field,
  ) {
    return _breakoutCountFocusNodes.putIfAbsent(
      _breakoutCountFocusKey(sample, field),
      () => FocusNode(debugLabel: 'breakout-count-${field.key}'),
    );
  }

  void _focusNextBreakoutCount({
    required List<EggBreakoutSampleEntry> samples,
    required int sampleIndex,
    required EggBreakoutType breakoutType,
    required EggBreakoutCountField field,
  }) {
    final fields = breakoutType.countFields;
    final fieldIndex = fields.indexWhere((candidate) {
      return candidate.key == field.key;
    });
    if (fieldIndex == -1) {
      FocusScope.of(context).unfocus();
      return;
    }

    var nextSampleIndex = sampleIndex;
    var nextFieldIndex = fieldIndex + 1;
    if (nextFieldIndex >= fields.length) {
      nextSampleIndex += 1;
      nextFieldIndex = 0;
    }

    if (nextSampleIndex >= samples.length) {
      FocusScope.of(context).unfocus();
      return;
    }

    final nextSample = samples[nextSampleIndex];
    final nextField = fields[nextFieldIndex];
    final nextNode =
        _breakoutCountFocusNodes[_breakoutCountFocusKey(nextSample, nextField)];
    if (nextNode == null) {
      FocusScope.of(context).nextFocus();
      return;
    }
    nextNode.requestFocus();
  }

  Widget _breakoutMetricSummaryTile({
    required Key key,
    required String value,
    bool emphasized = false,
    bool alert = false,
  }) {
    return Container(
      key: key,
      constraints: const BoxConstraints(minHeight: 52),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: emphasized
            ? AppColors.primary.withValues(alpha: 0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: alert
              ? const Color(0xFFF43F5E)
              : emphasized
              ? AppColors.primary
              : const Color(0xFFD1D5DB),
        ),
      ),
      child: Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.visible,
        textAlign: TextAlign.center,
        style: AppTextStyles.caption.copyWith(
          color: alert
              ? const Color(0xFFBE123C)
              : emphasized
              ? AppColors.primary
              : AppColors.textBody,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }

  InputDecoration _embeddedInputDecoration() {
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: AppColors.surfaceVariant,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFD8E2EC)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFD8E2EC)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }

  void _scrollToInitialSection() {
    final index = widget.initialSectionIndex
        .clamp(0, _sectionKeys.length - 1)
        .toInt();
    final targetContext = _sectionKeys[index].currentContext;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  Widget _surface({required Widget child, Key? containerKey}) {
    return Container(
      key: containerKey,
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.spaceLg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
    );
  }

  void _persistAllBmkAges(AuditProvider provider) {
    for (var i = 0; i < provider.drafts.length; i++) {
      _persistBmkAges(provider, i);
    }
  }

  void _persistBmkAges(AuditProvider provider, int hatchIndex) {
    if (hatchIndex < 0 || hatchIndex >= provider.drafts.length) return;
    final audit = provider.drafts[hatchIndex];
    final breakoutType = EggBreakoutType.fromStorageValue(audit.ebBreakoutType);
    if (breakoutType == EggBreakoutType.candledEggBreakout &&
        audit.ebBreakoutAgeDays == null) {
      provider.updateHatchField(hatchIndex, 'ebBreakoutAgeDays', 10);
    }
    final storageDays = audit.haStorageDays ?? audit.ebStorageDays ?? 0;
    final bmkAgeDays = _calculateBmkAgeDays(
      provider,
      audit,
      breakoutType,
      storageDays: storageDays,
    );
    final bmkAgeWeeks = _legacyBmkWeeks(bmkAgeDays);

    if (audit.ebBmkAge != bmkAgeWeeks) {
      provider.updateHatchField(hatchIndex, 'ebBmkAge', bmkAgeWeeks);
    }
    if (breakoutType.showsHatchability && audit.haBmkAge != bmkAgeWeeks) {
      provider.updateHatchField(hatchIndex, 'haBmkAge', bmkAgeWeeks);
    }
  }

  int? _calculateBmkAgeDays(
    AuditProvider provider,
    AuditModel audit,
    EggBreakoutType breakoutType, {
    required int? storageDays,
  }) {
    return breakoutType.calculateBmkAgeDays(
      currentFlockAgeDays: _currentFlockAgeDays(provider, audit),
      storageDays: storageDays,
      candlingDay: audit.ebBreakoutAgeDays ?? 10,
    );
  }

  int? _currentFlockAgeDays(AuditProvider provider, AuditModel audit) {
    return BmkAgeCalculator.currentFlockAgeDays(
      flockAgeWeeks: provider.context?.flockAgeWeeks,
      flockEntryDate: provider.context?.flockEntryDate,
      auditDate: audit.date,
    );
  }

  int? _legacyBmkWeeks(int? ageDays) {
    return BmkAgeCalculator.displayWeekForDays(ageDays);
  }

  int? _displayBmkWeeks(
    int? calculatedAgeDays,
    AuditModel audit,
    EggBreakoutType breakoutType,
  ) {
    final calculatedWeeks = _legacyBmkWeeks(calculatedAgeDays);
    if (calculatedWeeks != null) return calculatedWeeks;
    return breakoutType.showsHatchability
        ? (audit.haBmkAge ?? audit.ebBmkAge)
        : (audit.ebBmkAge ?? audit.haBmkAge);
  }

  String _formatBmkWeeksValue(int? weeks) {
    if (weeks == null) return '--';
    return '$weeks wks';
  }

  Future<Map<String, Object?>?> _breakoutBenchmarkFuture(int ageDays) {
    return _breakoutBenchmarkFutures.putIfAbsent(
      ageDays,
      () => _benchmarkLookup.nearestBreakoutBenchmark(
        calculatedBmkAgeDays: ageDays,
      ),
    );
  }

  Future<Map<String, Object?>?> _breedBenchmarkFuture({
    required int calculatedBmkAgeDays,
    required String breed,
  }) {
    final key = '$breed:$calculatedBmkAgeDays';
    return _breedBenchmarkFutures.putIfAbsent(
      key,
      () => _benchmarkLookup.nearestBreedBenchmark(
        calculatedBmkAgeDays: calculatedBmkAgeDays,
        breed: breed,
      ),
    );
  }

  double? _bmkPercentForField(Map<String, Object?>? benchmark, String key) {
    if (benchmark == null) return null;
    final column = _breakoutBmkColumnForField(key);
    if (column == null) return null;
    return _doubleValue(benchmark[column]);
  }

  String? _breakoutBmkColumnForField(String key) {
    return switch (key) {
      'early72hBloodRing' => 'bloodRingPct',
      'externalPip' => 'externalPipPct',
      'contaminated' => 'contamPct',
      'infertile' ||
      'early24h' ||
      'early48h' ||
      'blackEye' ||
      'earlyDead' ||
      'midDead' ||
      'lateDead' ||
      'cracked' => '${key}Pct',
      _ => null,
    };
  }

  double? _doubleValue(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  int _activeBreakoutSampleIndex(int hatchIndex, int sampleCount) {
    if (sampleCount <= 0) return 0;
    final current = _activeBreakoutSampleIndexes[hatchIndex] ?? 0;
    final clamped = current.clamp(0, sampleCount - 1).toInt();
    _activeBreakoutSampleIndexes[hatchIndex] = clamped;
    return clamped;
  }

  void _activateBreakoutSample(int hatchIndex, int sampleIndex) {
    setState(() {
      _activeBreakoutSampleIndexes[hatchIndex] = sampleIndex;
    });
  }

  void _scrollToBreakoutSample(String sampleId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = _sampleCardKeys[sampleId]?.currentContext;
      if (targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: 0.12,
      );
    });
  }

  List<EggBreakoutSampleEntry> _normalizeBreakoutSamples(
    List<EggBreakoutSampleEntry> samples,
  ) {
    final usedIds = <String>{};
    return samples.asMap().entries.map((entry) {
      final sample = _normalizeBreakoutSample(entry.value, entry.key);
      final uniqueId = _uniqueBreakoutSampleId(sample.id, entry.key, usedIds);
      usedIds.add(uniqueId);
      return uniqueId == sample.id ? sample : sample.copyWith(id: uniqueId);
    }).toList();
  }

  EggBreakoutSampleEntry _defaultPoolBreakoutSample(
    EggBreakoutType breakoutType,
  ) {
    return EggBreakoutSampleEntry.pool(
      id: 'pool-${breakoutType.storageValue}',
      label: 'Pool',
      traySize: _defaultTraySizeForBreakout(breakoutType),
      numberOfTrays: 1,
      breakoutType: breakoutType,
    );
  }

  String _uniqueBreakoutSampleId(
    String rawId,
    int sampleIndex,
    Set<String> usedIds,
  ) {
    final base = rawId.trim().isEmpty ? 'sample-${sampleIndex + 1}' : rawId;
    if (!usedIds.contains(base)) return base;

    var candidate = '$base-${sampleIndex + 1}';
    var suffix = 2;
    while (usedIds.contains(candidate)) {
      candidate = '$base-${sampleIndex + 1}-$suffix';
      suffix++;
    }
    return candidate;
  }

  EggBreakoutSampleEntry _asTraySample(
    EggBreakoutSampleEntry sample,
    int sampleIndex,
  ) {
    if (sample.sampleMode == EggBreakoutSampleMode.tray) return sample;
    return sample.copyWith(
      sampleMode: EggBreakoutSampleMode.tray,
      label: _defaultSampleLabel(
        EggBreakoutSampleMode.tray,
        sampleIndex + 1,
        sample.label,
      ),
      position: sample.position ?? 'random',
      traySize:
          sample.totalSample ??
          sample.traySize ??
          _defaultTraySizeForBreakout(sample.breakoutType),
    );
  }

  EggBreakoutSampleEntry _normalizeBreakoutSample(
    EggBreakoutSampleEntry sample,
    int sampleIndex,
  ) {
    if (sample.sampleMode == EggBreakoutSampleMode.tray) {
      return _asTraySample(sample, sampleIndex);
    }
    return sample.copyWith(
      label: _defaultSampleLabel(
        EggBreakoutSampleMode.pool,
        sampleIndex + 1,
        sample.label,
      ),
      traySize:
          sample.traySize ?? _defaultTraySizeForBreakout(sample.breakoutType),
      numberOfTrays: sample.numberOfTrays ?? 1,
    );
  }

  int _defaultTraySizeForBreakout(EggBreakoutType breakoutType) {
    return breakoutType == EggBreakoutType.freshEggBreakout ? 30 : 150;
  }

  String _breakoutPanelNameForType(EggBreakoutType breakoutType) {
    return switch (breakoutType) {
      EggBreakoutType.freshEggBreakout => 'fresh_egg_breakout',
      EggBreakoutType.candledEggBreakout => 'candled_egg_breakout',
      EggBreakoutType.residueHatchDay => 'residue_breakout',
    };
  }

  String _breakoutPhotoRowId(
    AuditProvider provider,
    int hatchIndex,
    String sampleId,
    EggBreakoutType breakoutType, [
    String? fieldKey,
  ]) {
    final sessionId = hatchIndex >= 0 && hatchIndex < provider.drafts.length
        ? provider.drafts[hatchIndex].sessionId
        : null;
    final prefix = sessionId == null || sessionId.isEmpty ? 'draft' : sessionId;
    final rowId =
        '$prefix:${_breakoutPanelNameForType(breakoutType)}:$sampleId';
    return fieldKey == null ? rowId : '$rowId:$fieldKey';
  }

  void _replaceBreakoutSample(
    AuditProvider provider,
    int hatchIndex,
    EggBreakoutType breakoutType,
    List<EggBreakoutSampleEntry> samples,
    int sampleIndex,
    EggBreakoutSampleEntry sample,
  ) {
    final next = [...samples];
    next[sampleIndex] = _normalizeBreakoutSample(
      sample.copyWith(breakoutType: breakoutType),
      sampleIndex,
    );
    _persistBreakoutSamples(provider, hatchIndex, breakoutType, next);
  }

  void _persistBreakoutSamples(
    AuditProvider provider,
    int hatchIndex,
    EggBreakoutType breakoutType,
    List<EggBreakoutSampleEntry> samples,
  ) {
    if (hatchIndex < 0 || hatchIndex >= provider.drafts.length) return;
    final currentAudit = provider.drafts[hatchIndex];
    final existingSamples = EggBreakoutSampleEntry.decodeList(
      currentAudit.ebTrayBreakoutJson,
      fallbackBreakoutType:
          _legacyBreakoutJsonNeedsTypeFallback(currentAudit.ebTrayBreakoutJson)
          ? breakoutType
          : null,
    );
    final otherTypeSamples = existingSamples
        .where((sample) => sample.breakoutType != breakoutType)
        .toList();
    final typedSamples = _normalizeBreakoutSamples(samples)
        .asMap()
        .entries
        .map(
          (entry) => _sampleWithActiveBatchHierarchy(
            currentAudit,
            entry.value.copyWith(breakoutType: breakoutType),
            breakoutType,
          ),
        )
        .toList();
    provider.updateHatchField(
      hatchIndex,
      'ebTrayBreakoutJson',
      EggBreakoutSampleEntry.encodeList([...otherTypeSamples, ...typedSamples]),
    );
    provider.updateHatchField(
      hatchIndex,
      'ebBreakoutType',
      breakoutType.storageValue,
    );
  }

  EggBreakoutSampleEntry _sampleWithActiveBatchHierarchy(
    AuditModel audit,
    EggBreakoutSampleEntry sample,
    EggBreakoutType breakoutType,
  ) {
    if (breakoutType == EggBreakoutType.freshEggBreakout) return sample;
    final hasMachineScope = _isResidueMachineDraft(audit);
    final hasHouseScope = SampleMode.isCompare(audit.sampleMode);
    return EggBreakoutSampleEntry(
      id: sample.id,
      sampleMode: sample.sampleMode,
      label: sample.label,
      house: hasHouseScope ? _residueHouseKeyOrNull(audit) : null,
      setter: hasMachineScope ? _trimmedOrNull(audit.setterId) : null,
      hatcher: hasMachineScope ? _trimmedOrNull(audit.hatcherId) : null,
      trolley: sample.trolley,
      tray: sample.tray,
      position: sample.position,
      traySize: sample.traySize,
      numberOfTrays: sample.numberOfTrays,
      breakoutType: sample.breakoutType,
      counts: sample.counts,
      photos: sample.photos,
    );
  }

  bool _legacyBreakoutJsonNeedsTypeFallback(String? source) {
    if (source == null || source.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List || decoded.isEmpty) return false;
      final sampleMaps = decoded.whereType<Map>().toList();
      if (sampleMaps.isEmpty) return false;
      return sampleMaps.every((sample) => !sample.containsKey('breakoutType'));
    } catch (_) {
      return false;
    }
  }

  String _defaultSampleLabel(
    EggBreakoutSampleMode mode,
    int index,
    String currentLabel,
  ) {
    final trayPattern = RegExp(r'^Tray \d+$');
    final poolPattern = RegExp(r'^Pool \d+$');
    if (!trayPattern.hasMatch(currentLabel) &&
        !poolPattern.hasMatch(currentLabel)) {
      return currentLabel;
    }
    return mode == EggBreakoutSampleMode.tray ? 'Tray $index' : 'Pool $index';
  }

  String _formatPercent(double? value) {
    if (value == null) return '--';
    return '${value.toStringAsFixed(1)}%';
  }

  String _formatDelta(double? value) {
    if (value == null) return '--';
    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(1)}';
  }

  String _formatGap(double? value) => _formatDelta(value);

  int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class _PerformanceMetric {
  final String label;
  final double? actual;
  final double? target;
  final String targetLabel;
  final bool lowerIsBad;

  const _PerformanceMetric({
    required this.label,
    required this.actual,
    required this.target,
    required this.targetLabel,
    required this.lowerIsBad,
  });
}

class _ResidueHouseTab {
  final String key;
  final String label;
  final int firstDraftIndex;

  const _ResidueHouseTab({
    required this.key,
    required this.label,
    required this.firstDraftIndex,
  });
}

class _ResidueTrolleyTab {
  final String key;
  final String label;
  final int firstSampleIndex;

  const _ResidueTrolleyTab({
    required this.key,
    required this.label,
    required this.firstSampleIndex,
  });
}

enum _BreakoutSampleField { traySize, numberOfTrays }

class _GradientNumberInput extends StatefulWidget {
  final int? value;
  final bool enabled;
  final bool clearZeroOnFocus;
  final ValueChanged<String> onChanged;

  const _GradientNumberInput({
    required this.value,
    required this.enabled,
    this.clearZeroOnFocus = false,
    required this.onChanged,
  });

  @override
  State<_GradientNumberInput> createState() => _GradientNumberInputState();
}

class _GradientNumberInputState extends State<_GradientNumberInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value?.toString() ?? '');
    _focusNode = FocusNode();
    _controller.addListener(_handleControllerChanged);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _GradientNumberInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextText = widget.value?.toString() ?? '';
    if (_focusNode.hasFocus &&
        widget.clearZeroOnFocus &&
        widget.value == 0 &&
        _controller.text.isEmpty) {
      return;
    }
    if (oldWidget.value != widget.value && nextText != _controller.text) {
      _controller.text = nextText;
    }
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  void _handleFocusChanged() {
    if (!widget.clearZeroOnFocus) return;
    if (_focusNode.hasFocus && widget.enabled && _controller.text == '0') {
      _controller.clear();
      return;
    }
    if (!_focusNode.hasFocus && _controller.text.isEmpty && widget.value == 0) {
      _controller.text = '0';
    }
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = AppTextStyles.body.copyWith(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w800,
    );

    return SizedBox(
      height: 24,
      child: Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          if (_controller.text.isEmpty)
            Text(
              '--',
              style: textStyle.copyWith(color: AppColors.textTertiary),
            ),
          EditableText(
            controller: _controller,
            focusNode: _focusNode,
            readOnly: !widget.enabled,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: textStyle,
            cursorColor: AppColors.primary,
            backgroundCursorColor: AppColors.borderDefault,
            onChanged: widget.onChanged,
            onSubmitted: widget.onChanged,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _focusNode.removeListener(_handleFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}
