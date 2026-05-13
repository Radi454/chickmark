import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/bmk_age_calculator.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/station_sample_model.dart';
import '../../../data/repositories/benchmark_lookup.dart';
import '../providers/audit_provider.dart';
import '../widgets/audit_autosave_status.dart';
import '../widgets/audit_keyboard_dismiss.dart';
import '../widgets/audit_numeric_keyboard.dart';
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
                    child: ListView(
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
            if (breakoutType == EggBreakoutType.residueHatchDay) ...[
              const SizedBox(height: AppSizes.spaceMd),
              _buildResidueBatchTabs(provider),
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
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final entry in drafts.asMap().entries)
                ChoiceChip(
                  key: ValueKey('residue-batch-tab-${entry.key}'),
                  label: Text(_residueBatchLabel(entry.value, entry.key)),
                  selected: entry.key == provider.activeHatchIndex,
                  onSelected: provider.isReadOnly
                      ? null
                      : (_) => provider.switchHatch(entry.key),
                  selectedColor: AppColors.primary.withValues(alpha: 0.14),
                  checkmarkColor: AppColors.primary,
                  labelStyle: AppTextStyles.body.copyWith(
                    color: entry.key == provider.activeHatchIndex
                        ? AppColors.primary
                        : AppColors.textBody,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: entry.key == provider.activeHatchIndex
                          ? AppColors.primary
                          : AppColors.borderDefault,
                    ),
                  ),
                ),
              _buildTrayActionButton(
                key: const ValueKey('residue-add-batch'),
                tooltip: 'Add hatch batch',
                icon: Icons.add,
                onPressed: provider.isReadOnly ? null : provider.addHatch,
              ),
              if (provider.hatchCount > 1)
                _buildTrayActionButton(
                  key: const ValueKey('residue-remove-batch'),
                  tooltip: 'Remove active hatch batch',
                  icon: Icons.remove,
                  onPressed: provider.isReadOnly
                      ? null
                      : provider.removeActiveHatch,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _residueBatchLabel(AuditModel audit, int index) {
    final fallback = '${index + 1}';
    final setter = _batchLabelPart(audit.setterId, fallback);
    final hatcher = _batchLabelPart(audit.hatcherId, fallback);
    return 'S${setter}H$hatcher';
  }

  String _batchLabelPart(String? raw, String fallback) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return fallback;
    return value;
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
        final headerTitle = Text(
          'Breakout Type',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.heading.copyWith(
            fontSize: useWideHeader ? 26 : 24,
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
              width: double.infinity,
              padding: EdgeInsets.all(useWideHeader ? 20 : 18),
              decoration: _gradientHeaderDecoration(),
              child: Wrap(
                spacing: AppSizes.spaceSm,
                runSpacing: AppSizes.spaceSm,
                children: [
                  _buildGradientInfoTile('Flock', widget.context.flockId),
                  _buildGradientInfoTile('Breed', widget.context.breed ?? '--'),
                  _buildGradientInfoTile(
                    'BMK Age',
                    _formatBmkWeeksValue(bmkAgeWeeks),
                    key: const ValueKey('breakout-bmk-age-display-card'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.spaceSm),
            Container(
              key: const ValueKey('hatch-analysis-required-entry-card'),
              width: double.infinity,
              padding: EdgeInsets.all(useWideHeader ? 16 : 14),
              decoration: _requiredEntryCardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Entry Fields',
                        style: AppTextStyles.body.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.spaceSm),
                  Wrap(
                    spacing: AppSizes.spaceSm,
                    runSpacing: AppSizes.spaceSm,
                    children: [
                      _buildGradientNumberTile(
                        cardKey: const ValueKey(
                          'breakout-storage-days-entry-card',
                        ),
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
          _sectionTitle('Batch Results'),
          const SizedBox(height: AppSizes.spaceMd),
          Wrap(
            spacing: AppSizes.spaceSm,
            runSpacing: AppSizes.spaceSm,
            children: [
              _residueTextNumberField(
                wrapperKey: const ValueKey('residue-setter-number'),
                fieldKey: ValueKey('residue-setter-number-$hatchIndex'),
                label: 'Setter',
                value: audit.setterId,
                enabled: !provider.isReadOnly,
                onChanged: (value) => provider.updateHatchField(
                  hatchIndex,
                  'setterId',
                  value.trim().isEmpty ? null : value.trim(),
                ),
              ),
              _residueTextNumberField(
                wrapperKey: const ValueKey('residue-hatcher-number'),
                fieldKey: ValueKey('residue-hatcher-number-$hatchIndex'),
                label: 'Hatcher',
                value: audit.hatcherId,
                enabled: !provider.isReadOnly,
                onChanged: (value) => provider.updateHatchField(
                  hatchIndex,
                  'hatcherId',
                  value.trim().isEmpty ? null : value.trim(),
                ),
              ),
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
          const SizedBox(height: AppSizes.spaceMd),
          FutureBuilder<Map<String, Object?>?>(
            future: breedBenchmarkFuture,
            builder: (context, snapshot) {
              final benchmark = snapshot.data;
              return Wrap(
                spacing: AppSizes.spaceSm,
                runSpacing: AppSizes.spaceSm,
                children: [
                  _resultMetricTile(
                    key: const ValueKey('residue-metric-hatchability'),
                    label: 'Hatchability',
                    actual: metrics.hatchabilityPct,
                    target: _doubleValue(benchmark?['hatchabilityPct']),
                    targetLabel: 'BMK',
                    lowerIsBad: true,
                  ),
                  _resultMetricTile(
                    key: const ValueKey('residue-metric-fertility'),
                    label: 'Fertility',
                    actual: metrics.fertilityPct,
                    target: _doubleValue(benchmark?['fertilityPct']),
                    targetLabel: 'BMK',
                    lowerIsBad: true,
                  ),
                  _resultMetricTile(
                    key: const ValueKey('residue-metric-hof'),
                    label: 'HOF',
                    actual: metrics.hofPct,
                    target: _doubleValue(benchmark?['hofPct']),
                    targetLabel: 'BMK',
                    lowerIsBad: true,
                  ),
                  _resultMetricTile(
                    key: const ValueKey('residue-metric-culled'),
                    label: 'Culled %',
                    actual: metrics.culledPct,
                    target: 1.0,
                    targetLabel: 'Limit',
                    lowerIsBad: false,
                  ),
                  _resultMetricTile(
                    key: const ValueKey('residue-metric-dead'),
                    label: 'Dead %',
                    actual: metrics.deadPct,
                    target: 0.2,
                    targetLabel: 'Limit',
                    lowerIsBad: false,
                  ),
                ],
              );
            },
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
    return SizedBox(
      key: wrapperKey,
      width: 132,
      child: AuditNumericFormField(
        key: fieldKey,
        initialValue: value ?? '',
        enabled: enabled,
        decoration: _inputDecoration(label),
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
    return SizedBox(
      key: wrapperKey,
      width: 160,
      child: AuditNumericFormField(
        key: fieldKey,
        initialValue: value?.toString() ?? '',
        enabled: enabled,
        decoration: _inputDecoration(label),
        onChanged: onChanged,
      ),
    );
  }

  Widget _resultMetricTile({
    required Key key,
    required String label,
    required double? actual,
    required double? target,
    required String targetLabel,
    required bool lowerIsBad,
  }) {
    final hasAlert =
        actual != null &&
        target != null &&
        (lowerIsBad ? actual < target : actual > target);
    final delta = actual != null && target != null ? actual - target : null;

    return Container(
      key: key,
      width: 184,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasAlert ? const Color(0xFFFFF1F2) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasAlert ? const Color(0xFFF43F5E) : AppColors.borderDefault,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _formatPercent(actual),
            style: AppTextStyles.heading.copyWith(
              fontSize: 22,
              color: hasAlert ? const Color(0xFFBE123C) : AppColors.textBody,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$targetLabel ${_formatPercent(target)}',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'Delta ${_formatDelta(delta)}',
            style: AppTextStyles.caption.copyWith(
              color: hasAlert
                  ? const Color(0xFFBE123C)
                  : AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
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

  BoxDecoration _requiredEntryCardDecoration() {
    return BoxDecoration(
      gradient: AppColors.brandGradient,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.34),
        width: 1.2,
      ),
      boxShadow: const [
        BoxShadow(
          color: AppColors.cardShadow,
          blurRadius: 14,
          offset: Offset(0, 7),
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 124, maxWidth: 180),
      child: Container(
        key: key,
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
              style: AppTextStyles.caption.copyWith(
                color: Colors.white.withValues(alpha: 0.78),
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
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
          color: Colors.white.withValues(alpha: prominent ? 0.22 : 0.14),
          borderRadius: BorderRadius.circular(prominent ? 10 : 8),
          border: Border.all(
            color: Colors.white.withValues(alpha: prominent ? 0.42 : 0.24),
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
                color: Colors.white.withValues(alpha: 0.78),
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
                    color: Colors.white.withValues(alpha: 0.78),
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
    final samples = _normalizeTraySamples(
      decodedSamples
          .where((sample) => sample.breakoutType == breakoutType)
          .toList(),
    );
    final totalSample = samples.fold<int>(
      0,
      (sum, sample) => sum + (sample.totalSample ?? 0),
    );
    final activeIndex = _activeBreakoutSampleIndex(hatchIndex, samples.length);
    final storageDays = audit.ebStorageDays ?? audit.haStorageDays;
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
            totalSample > 0
                ? '${samples.length} tray${samples.length == 1 ? '' : 's'} · $totalSample eggs sampled'
                : 'Add tray samples for diagnostic breakout entry',
            style: AppTextStyles.caption.copyWith(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          _buildTraySampleControls(
            provider: provider,
            hatchIndex: hatchIndex,
            samples: samples,
            breakoutType: breakoutType,
            activeIndex: activeIndex,
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
                active: entry.key == activeIndex,
                benchmarkFuture: benchmarkFuture,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTraySampleControls({
    required AuditProvider provider,
    required int hatchIndex,
    required List<EggBreakoutSampleEntry> samples,
    required EggBreakoutType breakoutType,
    required int activeIndex,
  }) {
    final chips = [
      for (final entry in samples.asMap().entries)
        ChoiceChip(
          key: ValueKey('breakout-sample-tab-${entry.key}'),
          label: Text(entry.value.label),
          selected: entry.key == activeIndex,
          onSelected: provider.isReadOnly
              ? null
              : (_) => _activateBreakoutSample(
                  hatchIndex,
                  entry.key,
                  entry.value.id,
                ),
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
    ];

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTrayActionButton(
          key: const ValueKey('breakout-add-sample'),
          tooltip: 'Add tray sample',
          icon: Icons.add,
          onPressed: provider.isReadOnly
              ? null
              : () {
                  final nextIndex = samples.length + 1;
                  final nextSample = EggBreakoutSampleEntry.tray(
                    id: 'sample-${DateTime.now().microsecondsSinceEpoch}',
                    label: 'Tray $nextIndex',
                    position: 'random',
                    traySize: _defaultTraySizeForBreakout(breakoutType),
                    breakoutType: breakoutType,
                  );
                  _activeBreakoutSampleIndexes[hatchIndex] = samples.length;
                  _persistBreakoutSamples(provider, hatchIndex, breakoutType, [
                    ...samples,
                    nextSample,
                  ]);
                  _scrollToBreakoutSample(nextSample.id);
                },
        ),
        if (samples.length > 1) ...[
          const SizedBox(width: 8),
          _buildTrayActionButton(
            key: const ValueKey('breakout-remove-sample'),
            tooltip: 'Remove active tray sample',
            icon: Icons.remove,
            onPressed: provider.isReadOnly
                ? null
                : () {
                    final next = [...samples]..removeAt(activeIndex);
                    final nextActiveIndex = activeIndex
                        .clamp(0, next.length - 1)
                        .toInt();
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
      tooltip: tooltip,
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
          Text(
            sample.label,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
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
              if (breakoutType != EggBreakoutType.freshEggBreakout)
                _breakoutPositionField(
                  provider: provider,
                  hatchIndex: hatchIndex,
                  samples: samples,
                  sampleIndex: sampleIndex,
                  sample: sample,
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
            ],
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
    final focusNode = _breakoutCountFocusNode(sample, field);

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
                child: _breakoutMetricTile(
                  key: ValueKey('breakout-percent-${field.key}'),
                  value: _formatPercent(percent),
                  alert: exceedsBmk,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _breakoutMetricTile(
                  key: ValueKey('breakout-bmk-${field.key}'),
                  value: 'BMK ${_formatPercent(bmkPercent)}',
                  emphasized: bmkPercent != null,
                  alert: exceedsBmk,
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

  Widget _breakoutMetricTile({
    required Key key,
    required String value,
    bool emphasized = false,
    bool alert = false,
  }) {
    return Container(
      key: key,
      height: 52,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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

  void _activateBreakoutSample(
    int hatchIndex,
    int sampleIndex,
    String sampleId,
  ) {
    setState(() {
      _activeBreakoutSampleIndexes[hatchIndex] = sampleIndex;
    });
    _scrollToBreakoutSample(sampleId);
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

  List<EggBreakoutSampleEntry> _normalizeTraySamples(
    List<EggBreakoutSampleEntry> samples,
  ) {
    return samples
        .asMap()
        .entries
        .map((entry) => _asTraySample(entry.value, entry.key))
        .toList();
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

  int _defaultTraySizeForBreakout(EggBreakoutType breakoutType) {
    return breakoutType == EggBreakoutType.freshEggBreakout ? 30 : 150;
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
    next[sampleIndex] = _asTraySample(
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
    final typedSamples = _normalizeTraySamples(samples)
        .asMap()
        .entries
        .map((entry) => entry.value.copyWith(breakoutType: breakoutType))
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

  int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
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
      color: Colors.white,
      fontWeight: FontWeight.w800,
    );

    return SizedBox(
      height: 24,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (_controller.text.isEmpty)
            Text(
              '--',
              style: textStyle.copyWith(
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          EditableText(
            controller: _controller,
            focusNode: _focusNode,
            readOnly: !widget.enabled,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: textStyle,
            cursorColor: Colors.white,
            backgroundCursorColor: Colors.white54,
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
