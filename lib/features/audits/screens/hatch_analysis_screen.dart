import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/calculation_utils.dart';
import '../../../core/utils/date_utils.dart' as hatch_dates;
import '../../../data/models/audit_model.dart';
import '../providers/audit_provider.dart';
import '../widgets/audit_keyboard_dismiss.dart';
import '../widgets/audit_numeric_keyboard.dart';
import '../widgets/sample_mode_controls.dart';
import '../widgets/unsaved_changes_guard.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/egg_breakout_sample.dart';
import 'audit_context_screen.dart';

class HatchAnalysisScreen extends StatefulWidget {
  final AuditContextData context;
  final AuditModel? initialAudit;
  final int initialSectionIndex;

  const HatchAnalysisScreen({
    super.key,
    required this.context,
    this.initialAudit,
    this.initialSectionIndex = 0,
  });

  @override
  State<HatchAnalysisScreen> createState() => _HatchAnalysisScreenState();
}

class _HatchAnalysisScreenState extends State<HatchAnalysisScreen> {
  final ScrollController _scrollController = ScrollController();
  late final List<GlobalKey> _sectionKeys = List.generate(
    2,
    (_) => GlobalKey(),
  );

  @override
  void initState() {
    super.initState();
    final auditProvider = Provider.of<AuditProvider>(context, listen: false);
    final auditContext = AuditContext(
      auditType: widget.context.auditType,
      customerId: widget.context.customerId,
      flockId: widget.context.flockId,
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
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auditProvider = context.watch<AuditProvider>();
    final drafts = auditProvider.drafts;

    return UnsavedChangesGuard(
      enabled: widget.context.sessionId == null,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6F8),
        appBar: widget.context.sessionId != null
            ? null
            : GradientAppBar(
                title: 'Hatch Analysis',
                actions: [
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
                  _buildTopBar(auditProvider),
                  Expanded(
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      children: [
                        if (_shouldShowAverageCard(drafts)) ...[
                          _buildAverageCard(drafts),
                          const SizedBox(height: 10),
                        ],
                        ...drafts.asMap().entries.map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildHatchSector(
                              provider: auditProvider,
                              hatchIndex: entry.key,
                              audit: entry.value,
                            ),
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

  Widget _buildTopBar(AuditProvider provider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.isCompareMode
                      ? '${provider.hatchCount} batch / hatch groups'
                      : 'Batch / hatch group',
                  style: AppTextStyles.heading.copyWith(fontSize: 20),
                ),
                const SizedBox(height: 2),
                Text(
                  provider.isCompareMode
                      ? 'Enter each hatch group with its own breakout samples'
                      : 'Enter hatchability accounting and breakout samples',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          Flexible(
            child: StationSampleModeControls(
              provider: provider,
              padding: EdgeInsets.zero,
              afterAddSample: () =>
                  _persistBmkAges(provider, provider.activeHatchIndex),
            ),
          ),
        ],
      ),
    );
  }

  bool _shouldShowAverageCard(List<AuditModel> drafts) {
    return drafts.length > 1 &&
        drafts.every(
          (draft) => EggBreakoutType.fromStorageValue(
            draft.ebBreakoutType,
          ).showsHatchability,
        );
  }

  Widget _buildAverageCard(List<AuditModel> audits) {
    final hatchabilities = audits.map(_hatchability).toList();
    final culledPcts = audits.map(_culledPct).toList();
    final deadPcts = audits.map(_deadPct).toList();
    final fertilities = audits.map(_fertilityFromBudget).toList();
    final hofs = audits.map(_hofFromBudget).toList();

    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Average Across Hatches',
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metricPill(
                'Hatchability',
                CalculationUtils.average(hatchabilities),
              ),
              _metricPill('Culled', CalculationUtils.average(culledPcts)),
              _metricPill('Dead', CalculationUtils.average(deadPcts)),
              _metricPill('Fertility', CalculationUtils.average(fertilities)),
              _metricPill('HOF', CalculationUtils.average(hofs)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHatchSector({
    required AuditProvider provider,
    required int hatchIndex,
    required AuditModel audit,
  }) {
    final breakoutType = EggBreakoutType.fromStorageValue(audit.ebBreakoutType);
    final showHatchability = breakoutType.showsHatchability;
    final storageDays = audit.haStorageDays ?? audit.ebStorageDays;
    final bmkAgeDays = _calculateBmkAgeDays(
      provider,
      audit,
      breakoutType,
      storageDays: storageDays,
    );
    final reconciled = showHatchability
        ? provider.isHatchBudgetReconciled(hatchIndex)
        : false;
    final budgetSum = showHatchability
        ? provider.hatchBudgetSum(hatchIndex)
        : 0;
    final totalEggsSet = audit.haTotalEggsSet ?? 0;
    final diff = totalEggsSet - budgetSum;

    return _surface(
      containerKey: hatchIndex == provider.activeHatchIndex
          ? _sectionKeys[0]
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Batch / Hatch Group ${hatchIndex + 1}',
                  style: AppTextStyles.heading.copyWith(fontSize: 20),
                ),
              ),
              _smallBadge(audit.setterId, 'Setter'),
              const SizedBox(width: 8),
              _smallBadge(audit.hatcherId, 'Hatcher'),
            ],
          ),
          const SizedBox(height: 10),
          _sectionTitle('Breakout Type'),
          const SizedBox(height: 8),
          _buildBreakoutTypeSelector(provider, hatchIndex, audit, breakoutType),
          const SizedBox(height: 14),
          _sectionTitle('Batch Info'),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 680;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _sizedField(
                        wide,
                        maxWidth: constraints.maxWidth,
                        child: _textField(
                          audit: audit,
                          hatchIndex: hatchIndex,
                          provider: provider,
                          field: 'setterId',
                          label: 'Setter ID',
                          value: audit.setterId,
                        ),
                      ),
                      SizedBox(
                        width: wide
                            ? 220.0
                            : _compactFieldWidth(constraints.maxWidth),
                        child: _bmkAgeChip(bmkAgeDays),
                      ),
                      _sizedField(
                        wide,
                        maxWidth: constraints.maxWidth,
                        child: _textField(
                          audit: audit,
                          hatchIndex: hatchIndex,
                          provider: provider,
                          field: 'hatcherId',
                          label: 'Hatcher ID',
                          value: audit.hatcherId,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _sizedField(
                        wide,
                        maxWidth: constraints.maxWidth,
                        child: _numberField(
                          audit: audit,
                          hatchIndex: hatchIndex,
                          provider: provider,
                          field: 'haStorageDays',
                          label: 'Storage Days',
                          value: storageDays,
                          afterChanged: () =>
                              _syncStorageDays(provider, hatchIndex),
                        ),
                      ),
                      _sizedField(
                        wide,
                        maxWidth: constraints.maxWidth,
                        child: _numberField(
                          audit: audit,
                          hatchIndex: hatchIndex,
                          provider: provider,
                          field: 'haTotalEggsSet',
                          label: 'Total Eggs Set',
                          value: audit.haTotalEggsSet,
                          afterChanged: () => _persistHatchCalculations(
                            provider,
                            hatchIndex,
                            audit,
                          ),
                        ),
                      ),
                      if (breakoutType == EggBreakoutType.candledEggBreakout)
                        _sizedField(
                          wide,
                          maxWidth: constraints.maxWidth,
                          child: _numberField(
                            audit: audit,
                            hatchIndex: hatchIndex,
                            provider: provider,
                            field: 'ebBreakoutAgeDays',
                            label: 'Candling Day',
                            value: audit.ebBreakoutAgeDays ?? 10,
                            afterChanged: () =>
                                _persistBmkAges(provider, hatchIndex),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
          if (showHatchability) ...[
            const SizedBox(height: 14),
            _sectionTitle('Hatchability Results'),
            const SizedBox(height: 8),
            _buildReconciliationBar(totalEggsSet, budgetSum, diff, reconciled),
            const SizedBox(height: 14),
            _sectionTitle('100% Budget Categories'),
            const SizedBox(height: 8),
            _buildBudgetCategoryGrid(provider, hatchIndex, audit),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metricPill(
                  'Hatchability',
                  _hatchability(audit),
                  highlight: true,
                ),
                _metricPill('Fertility', _fertilityFromBudget(audit)),
                _metricPill('HOF', _hofFromBudget(audit)),
                _metricPill('Dead', _deadPct(audit)),
                _metricPill('Culled', _culledPct(audit)),
              ],
            ),
            const SizedBox(height: 12),
            if (reconciled && totalEggsSet > 0) ...[
              const SizedBox(height: 4),
              _buildPercentageSummary(audit, totalEggsSet),
            ],
          ],
          const SizedBox(height: 14),
          _sectionTitle('Breakout Samples'),
          const SizedBox(height: 8),
          _buildBreakoutSampleSection(
            provider,
            hatchIndex,
            audit,
            breakoutType,
          ),
        ],
      ),
    );
  }

  Widget _buildBreakoutTypeSelector(
    AuditProvider provider,
    int hatchIndex,
    AuditModel audit,
    EggBreakoutType selectedType,
  ) {
    return SegmentedButton<EggBreakoutType>(
      segments: const [
        ButtonSegment(
          value: EggBreakoutType.freshEggBreakout,
          label: Text('Fresh Egg'),
        ),
        ButtonSegment(
          value: EggBreakoutType.candledEggBreakout,
          label: Text('Candled Egg'),
        ),
        ButtonSegment(
          value: EggBreakoutType.residueHatchDay,
          label: Text('Residue / Hatch Day'),
        ),
      ],
      selected: {selectedType},
      onSelectionChanged: provider.isReadOnly || provider.isLoading
          ? null
          : (selection) {
              final nextType = selection.first;
              final existingSamples = EggBreakoutSampleEntry.decodeList(
                audit.ebTrayBreakoutJson,
                fallbackBreakoutType: nextType,
              );
              if (existingSamples.isEmpty) {
                provider.updateHatchField(
                  hatchIndex,
                  'ebBreakoutType',
                  nextType.storageValue,
                );
              } else {
                _persistBreakoutSamples(
                  provider,
                  hatchIndex,
                  nextType,
                  existingSamples,
                );
              }
              if (nextType == EggBreakoutType.candledEggBreakout &&
                  audit.ebBreakoutAgeDays == null) {
                provider.updateHatchField(hatchIndex, 'ebBreakoutAgeDays', 10);
              }
              _persistBmkAges(provider, hatchIndex);
            },
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.primary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppColors.primary
              : Colors.white;
        }),
      ),
    );
  }

  Widget _buildBreakoutSampleSection(
    AuditProvider provider,
    int hatchIndex,
    AuditModel audit,
    EggBreakoutType breakoutType,
  ) {
    final samples = EggBreakoutSampleEntry.decodeList(
      audit.ebTrayBreakoutJson,
      fallbackBreakoutType: breakoutType,
    );
    final totalSample = samples.fold<int>(
      0,
      (sum, sample) => sum + (sample.totalSample ?? 0),
    );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  totalSample > 0
                      ? '${samples.length} sample${samples.length == 1 ? '' : 's'} · $totalSample eggs sampled'
                      : 'Add tray or pooled samples for diagnostic breakout entry',
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
              if (!provider.isReadOnly)
                TextButton.icon(
                  onPressed: () {
                    final nextIndex = samples.length + 1;
                    final next = [
                      ...samples,
                      EggBreakoutSampleEntry.tray(
                        id: 'sample-${DateTime.now().microsecondsSinceEpoch}',
                        label: 'Tray $nextIndex',
                        position: 'random',
                        traySize: 150,
                        breakoutType: breakoutType,
                      ),
                    ];
                    _persistBreakoutSamples(
                      provider,
                      hatchIndex,
                      breakoutType,
                      next,
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add Sample'),
                ),
            ],
          ),
          if (samples.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No breakout samples yet.',
                style: AppTextStyles.caption,
              ),
            )
          else
            ...samples.asMap().entries.map(
              (entry) => _buildBreakoutSampleCard(
                provider,
                hatchIndex,
                entry.key,
                entry.value,
                samples,
                breakoutType,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBreakoutSampleCard(
    AuditProvider provider,
    int hatchIndex,
    int sampleIndex,
    EggBreakoutSampleEntry sample,
    List<EggBreakoutSampleEntry> samples,
    EggBreakoutType breakoutType,
  ) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  sample.label,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!provider.isReadOnly)
                IconButton(
                  tooltip: 'Delete sample',
                  onPressed: () {
                    final next = [...samples]..removeAt(sampleIndex);
                    _persistBreakoutSamples(
                      provider,
                      hatchIndex,
                      breakoutType,
                      next,
                    );
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SegmentedButton<EggBreakoutSampleMode>(
            segments: const [
              ButtonSegment(
                value: EggBreakoutSampleMode.tray,
                label: Text('Tray sample'),
              ),
              ButtonSegment(
                value: EggBreakoutSampleMode.pool,
                label: Text('Pool sample'),
              ),
            ],
            selected: {sample.sampleMode},
            onSelectionChanged: provider.isReadOnly || provider.isLoading
                ? null
                : (selection) {
                    final nextMode = selection.first;
                    final nextSample = sample.copyWith(
                      sampleMode: nextMode,
                      label: _defaultSampleLabel(
                        nextMode,
                        sampleIndex + 1,
                        sample.label,
                      ),
                      numberOfTrays: sample.numberOfTrays ?? 1,
                      traySize: sample.traySize ?? 150,
                    );
                    _replaceBreakoutSample(
                      provider,
                      hatchIndex,
                      breakoutType,
                      samples,
                      sampleIndex,
                      nextSample,
                    );
                  },
            showSelectedIcon: false,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _breakoutTextField(
                provider: provider,
                hatchIndex: hatchIndex,
                samples: samples,
                sampleIndex: sampleIndex,
                label: 'Label',
                value: sample.label,
                breakoutType: breakoutType,
              ),
              if (sample.sampleMode == EggBreakoutSampleMode.tray)
                _breakoutPositionField(
                  provider: provider,
                  hatchIndex: hatchIndex,
                  samples: samples,
                  sampleIndex: sampleIndex,
                  sample: sample,
                  breakoutType: breakoutType,
                ),
              if (sample.sampleMode == EggBreakoutSampleMode.pool)
                _breakoutNumberField(
                  provider: provider,
                  hatchIndex: hatchIndex,
                  samples: samples,
                  sampleIndex: sampleIndex,
                  label: 'Number of trays',
                  value: sample.numberOfTrays,
                  sampleField: _BreakoutSampleField.numberOfTrays,
                  breakoutType: breakoutType,
                ),
              _breakoutNumberField(
                provider: provider,
                hatchIndex: hatchIndex,
                samples: samples,
                sampleIndex: sampleIndex,
                label: 'Tray size',
                value: sample.traySize,
                sampleField: _BreakoutSampleField.traySize,
                breakoutType: breakoutType,
              ),
              _totalSampleTile(sample),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: breakoutType.countFields.map((field) {
              return _breakoutNumberField(
                provider: provider,
                hatchIndex: hatchIndex,
                samples: samples,
                sampleIndex: sampleIndex,
                label: field.label,
                value: sample.counts[field.key],
                countKey: field.key,
                suffixText: _formatPercent(sample.percentageFor(field.key)),
                breakoutType: breakoutType,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _breakoutTextField({
    required AuditProvider provider,
    required int hatchIndex,
    required List<EggBreakoutSampleEntry> samples,
    required int sampleIndex,
    required String label,
    required String value,
    required EggBreakoutType breakoutType,
  }) {
    return SizedBox(
      width: 150,
      child: TextFormField(
        key: ValueKey('${samples[sampleIndex].id}-label'),
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
            samples[sampleIndex].copyWith(label: text),
          );
        },
      ),
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
    return SizedBox(
      width: 170,
      child: DropdownButtonFormField<String>(
        key: ValueKey('${sample.id}-position'),
        initialValue: value,
        isExpanded: true,
        decoration: _inputDecoration('Position'),
        items: const [
          DropdownMenuItem(value: 'top', child: Text('Top')),
          DropdownMenuItem(value: 'mid', child: Text('Mid')),
          DropdownMenuItem(value: 'bottom', child: Text('Bottom')),
          DropdownMenuItem(value: 'random', child: Text('Random')),
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
      ),
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
    return SizedBox(
      width: 140,
      child: AuditNumericFormField(
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
      ),
    );
  }

  Widget _totalSampleTile(EggBreakoutSampleEntry sample) {
    return Container(
      width: 140,
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Total sample', style: AppTextStyles.caption),
          Text(
            sample.totalSample?.toString() ?? '--',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildReconciliationBar(
    int total,
    int sum,
    int diff,
    bool reconciled,
  ) {
    final isOver = diff < 0;
    final label = reconciled
        ? 'Budget reconciles: $total = $total'
        : isOver
        ? 'Over by ${-diff} eggs'
        : 'Under by $diff eggs';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: reconciled ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: reconciled ? const Color(0xFF6EE7B7) : const Color(0xFFFECACA),
        ),
      ),
      child: Row(
        children: [
          Icon(
            reconciled ? Icons.check_circle : Icons.warning_amber_rounded,
            color: reconciled ? Colors.green : Colors.red,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: reconciled
                        ? Colors.green.shade800
                        : Colors.red.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: total > 0 ? (sum / total).clamp(0.0, 2.0) : 0.0,
                  backgroundColor: Colors.grey.shade200,
                  color: reconciled ? Colors.green : Colors.red,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 4),
                Text(
                  '$sum / $total eggs allocated',
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetCategoryGrid(
    AuditProvider provider,
    int hatchIndex,
    AuditModel audit,
  ) {
    final categories = _budgetCategories;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: categories.map((cat) {
            return SizedBox(
              width: _compactFieldWidth(constraints.maxWidth),
              child: _numberField(
                audit: audit,
                hatchIndex: hatchIndex,
                provider: provider,
                field: cat.field,
                label: cat.label,
                value: _getHatchField(audit, cat.field),
                afterChanged: () =>
                    _persistHatchCalculations(provider, hatchIndex, audit),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  int? _getHatchField(AuditModel audit, String field) {
    switch (field) {
      case 'haHatched':
        return audit.haHatched;
      case 'haCulled':
        return audit.haCulled;
      case 'haDead':
        return audit.haDead;
      case 'haPipped':
        return audit.haPipped;
      case 'haInfertileClear':
        return audit.haInfertileClear;
      case 'haEarlyDead':
        return audit.haEarlyDead;
      case 'haMidDead':
        return audit.haMidDead;
      case 'haMidLateDead':
        return audit.haMidLateDead;
      case 'haLateDead':
        return audit.haLateDead;
      case 'haContaminatedExploders':
        return audit.haContaminatedExploders;
      default:
        return null;
    }
  }

  Widget _buildPercentageSummary(AuditModel audit, int totalEggsSet) {
    final categories = _budgetCategories;
    final percentages = <String, double>{};
    for (final cat in categories) {
      final count = _getHatchField(audit, cat.field) ?? 0;
      percentages[cat.label] = totalEggsSet > 0
          ? (count / totalEggsSet) * 100
          : 0.0;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Category Percentages',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: percentages.entries.map((entry) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.key,
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${entry.value.toStringAsFixed(1)}%',
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _textField({
    required AuditModel audit,
    required int hatchIndex,
    required AuditProvider provider,
    required String field,
    required String label,
    required String? value,
  }) {
    return AuditNumericFormField(
      key: ValueKey('${audit.id}-$field'),
      initialValue: value ?? '',
      enabled: !provider.isReadOnly,
      decoration: _inputDecoration(label),
      onChanged: (text) {
        provider.updateHatchField(hatchIndex, field, text);
        if (field == 'setterId') {
          provider.updateHatchField(hatchIndex, 'soSetterId', text);
        }
        if (field == 'hatcherId') {
          provider.updateHatchField(hatchIndex, 'hoHatcherId', text);
        }
      },
    );
  }

  Widget _numberField({
    required AuditModel audit,
    required int hatchIndex,
    required AuditProvider provider,
    required String field,
    required String label,
    required int? value,
    VoidCallback? afterChanged,
  }) {
    return AuditNumericFormField(
      key: ValueKey('${audit.id}-$field'),
      initialValue: value?.toString() ?? '',
      enabled: !provider.isReadOnly,
      decoration: _inputDecoration(label),
      onChanged: (text) {
        provider.updateHatchField(hatchIndex, field, int.tryParse(text));
        afterChanged?.call();
      },
    );
  }

  Widget _bmkAgeChip(int? ageDays) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_graph, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'BMK Age ${_formatBmkAge(ageDays)}',
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 8),
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

  Widget _smallBadge(String? value, String fallback) {
    final label = (value == null || value.trim().isEmpty) ? fallback : value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _metricPill(String label, double value, {bool highlight = false}) {
    return _metricTile(
      label,
      '${value.toStringAsFixed(1)}%',
      highlight: highlight,
    );
  }

  Widget _metricTile(String label, String value, {bool highlight = false}) {
    return Container(
      width: _metricTileWidth(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlight ? AppColors.infoBg : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlight ? AppColors.primary : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTextStyles.heading.copyWith(
              fontSize: 20,
              color: highlight ? AppColors.primary : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sizedField(bool wide, {required Widget child, double? maxWidth}) {
    final available = maxWidth ?? MediaQuery.sizeOf(context).width - 56;
    final width = wide ? 220.0 : _compactFieldWidth(available);
    return SizedBox(width: width, child: child);
  }

  double _compactFieldWidth(double availableWidth) {
    if (availableWidth < 320) return availableWidth;
    final twoColumnWidth = (availableWidth - 10) / 2;
    return twoColumnWidth.clamp(140.0, 220.0).toDouble();
  }

  double _metricTileWidth() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final available = screenWidth - 56;
    if (available < 320) return available;
    return ((available - 8) / 2).clamp(136.0, 150.0).toDouble();
  }

  void _persistHatchCalculations(
    AuditProvider provider,
    int hatchIndex,
    AuditModel audit,
  ) {
    provider.recalculateHatchMetrics(hatchIndex);
    _persistBmkAges(provider, hatchIndex);
  }

  void _syncStorageDays(AuditProvider provider, int hatchIndex) {
    final storageDays = provider.drafts[hatchIndex].haStorageDays;
    provider.updateHatchField(hatchIndex, 'ebStorageDays', storageDays);
    _persistBmkAges(provider, hatchIndex);
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
    final storageDays = audit.haStorageDays ?? audit.ebStorageDays;
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
    final flockAgeWeeks = provider.context?.flockAgeWeeks;
    if (flockAgeWeeks != null) return (flockAgeWeeks * 7).round();
    final entryDate = provider.context?.flockEntryDate;
    if (entryDate == null) return null;
    return hatch_dates.HatchDateUtils.flockAgeDays(entryDate, now: audit.date);
  }

  int? _legacyBmkWeeks(int? ageDays) {
    if (ageDays == null) return null;
    return (ageDays / 7.0).ceil();
  }

  String _formatBmkAge(int? ageDays) {
    if (ageDays == null) return '--';
    return '$ageDays days';
  }

  double _hatchability(AuditModel audit) {
    final hatched = audit.haHatched ?? 0;
    final total = audit.haTotalEggsSet ?? 19200;
    return CalculationUtils.hatchability(hatched, total);
  }

  double _deadPct(AuditModel audit) {
    final total = audit.haTotalEggsSet ?? 19200;
    if (total <= 0) return 0.0;
    return ((audit.haDead ?? 0) / total) * 100;
  }

  double _culledPct(AuditModel audit) {
    final total = audit.haTotalEggsSet ?? 19200;
    if (total <= 0) return 0.0;
    return ((audit.haCulled ?? 0) / total) * 100;
  }

  double _fertilityFromBudget(AuditModel audit) {
    final total = audit.haTotalEggsSet ?? 0;
    if (total <= 0) return 0.0;
    final infertile = audit.haInfertileClear ?? 0;
    return CalculationUtils.fertility(total - infertile, infertile);
  }

  double _hofFromBudget(AuditModel audit) {
    return CalculationUtils.hof(
      _hatchability(audit),
      _fertilityFromBudget(audit),
    );
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
    next[sampleIndex] = sample.copyWith(breakoutType: breakoutType);
    _persistBreakoutSamples(provider, hatchIndex, breakoutType, next);
  }

  void _persistBreakoutSamples(
    AuditProvider provider,
    int hatchIndex,
    EggBreakoutType breakoutType,
    List<EggBreakoutSampleEntry> samples,
  ) {
    final typedSamples = samples
        .map((sample) => sample.copyWith(breakoutType: breakoutType))
        .toList();
    provider.updateHatchField(
      hatchIndex,
      'ebTrayBreakoutJson',
      EggBreakoutSampleEntry.encodeList(typedSamples),
    );
    provider.updateHatchField(
      hatchIndex,
      'ebBreakoutType',
      breakoutType.storageValue,
    );
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

  int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

const List<_BudgetCategory> _budgetCategories = [
  _BudgetCategory('Healthy Hatched', 'haHatched'),
  _BudgetCategory('Culled', 'haCulled'),
  _BudgetCategory('Dead at Hatch', 'haDead'),
  _BudgetCategory('Pipped', 'haPipped'),
  _BudgetCategory('Infertile/Clear', 'haInfertileClear'),
  _BudgetCategory('Early Dead', 'haEarlyDead'),
  _BudgetCategory('Mid Dead', 'haMidDead'),
  _BudgetCategory('Mid/Late Dead', 'haMidLateDead'),
  _BudgetCategory('Late Dead', 'haLateDead'),
  _BudgetCategory('Contaminated/Exploders', 'haContaminatedExploders'),
];

class _BudgetCategory {
  final String label;
  final String field;
  const _BudgetCategory(this.label, this.field);
}

enum _BreakoutSampleField { traySize, numberOfTrays }
