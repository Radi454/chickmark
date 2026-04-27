import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/calculation_utils.dart';
import '../../../core/utils/date_utils.dart' as hatch_dates;
import '../../../data/models/audit_model.dart';
import '../../../data/models/sample_mode.dart';
import '../providers/audit_provider.dart';
import '../widgets/audit_keyboard_dismiss.dart';
import '../widgets/unsaved_changes_guard.dart';
import '../../auth/providers/auth_provider.dart';
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
        body: AuditKeyboardDismiss(
          child: SafeArea(
            child: Column(
              children: [
                _buildTopBar(auditProvider),
                Expanded(
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    children: [
                      if (drafts.length > 1) ...[
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
                      ? '${provider.hatchCount} hatch${provider.hatchCount == 1 ? '' : 'es'}'
                      : 'Pooled sample',
                  style: AppTextStyles.heading.copyWith(fontSize: 20),
                ),
                const SizedBox(height: 2),
                Text(
                  provider.isCompareMode
                      ? 'Compare hatch results and tray breakouts side by side'
                      : 'One pooled hatchery sample for this visit',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: provider.isReadOnly || !provider.isCompareMode
                ? null
                : () {
                    provider.addHatch();
                    _persistBmkAges(provider, provider.activeHatchIndex);
                  },
            icon: const Icon(Icons.add),
            label: const Text('Hatch'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildSampleModeControl(provider),
        ],
      ),
    );
  }

  Widget _buildSampleModeControl(AuditProvider provider) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: SampleMode.pool,
          icon: Icon(Icons.all_inclusive),
          label: Text('Pool'),
        ),
        ButtonSegment(
          value: SampleMode.compare,
          icon: Icon(Icons.compare_arrows),
          label: Text('Compare'),
        ),
      ],
      selected: {provider.sampleMode},
      onSelectionChanged: provider.isReadOnly
          ? null
          : (selection) => provider.setSampleMode(selection.first),
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
    final reconciled = provider.isHatchBudgetReconciled(hatchIndex);
    final budgetSum = provider.hatchBudgetSum(hatchIndex);
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
                  'Hatch ${hatchIndex + 1}',
                  style: AppTextStyles.heading.copyWith(fontSize: 20),
                ),
              ),
              _smallBadge(audit.setterId, 'Setter'),
              const SizedBox(width: 8),
              _smallBadge(audit.hatcherId, 'Hatcher'),
            ],
          ),
          const SizedBox(height: 10),
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
                        child: _bmkAgeChip(
                          audit.haBmkAge ??
                              _calculateBmkAgeWeeks(
                                provider,
                                storageDays:
                                    audit.haStorageDays ?? audit.ebStorageDays,
                              ),
                        ),
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
                          value: audit.haStorageDays ?? audit.ebStorageDays,
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
                          value: audit.haTotalEggsSet ?? 19200,
                          afterChanged: () => _persistHatchCalculations(
                            provider,
                            hatchIndex,
                            audit,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          // Budget reconciliation bar
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
          // Category percentage summary
          if (reconciled && totalEggsSet > 0) ...[
            const SizedBox(height: 4),
            _buildPercentageSummary(audit, totalEggsSet),
          ],
          const SizedBox(height: 14),
          _sectionTitle('Egg Breakout Trays'),
          const SizedBox(height: 8),
          _buildBreakoutTraySection(provider, hatchIndex, audit),
        ],
      ),
    );
  }

  Widget _buildBreakoutTraySection(
    AuditProvider provider,
    int hatchIndex,
    AuditModel audit,
  ) {
    final trays = _decodeBreakoutTrays(audit.ebTrayBreakoutJson);
    final totalTraySize = audit.ebTraySize ?? 0;

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
                  totalTraySize > 0
                      ? '${trays.length} tray${trays.length == 1 ? '' : 's'} · $totalTraySize eggs'
                      : 'Add trays to compare positions inside the hatch',
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
              if (!provider.isReadOnly)
                TextButton.icon(
                  onPressed: () {
                    final next = [...trays, _newBreakoutTray(trays.length + 1)];
                    _persistBreakoutTrays(provider, hatchIndex, next);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Tray'),
                ),
            ],
          ),
          if (trays.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No tray-level breakout data yet.',
                style: AppTextStyles.caption,
              ),
            )
          else
            ...trays.asMap().entries.map(
              (entry) => _buildBreakoutTrayCard(
                provider,
                hatchIndex,
                entry.key,
                entry.value,
                trays,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBreakoutTrayCard(
    AuditProvider provider,
    int hatchIndex,
    int trayIndex,
    Map<String, dynamic> tray,
    List<Map<String, dynamic>> trays,
  ) {
    final label = (tray['label'] as String?) ?? 'Tray ${trayIndex + 1}';
    final counts = Map<String, dynamic>.from(tray['counts'] as Map? ?? {});

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
                  label,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!provider.isReadOnly)
                IconButton(
                  tooltip: 'Delete tray',
                  onPressed: () {
                    final next = [...trays]..removeAt(trayIndex);
                    _persistBreakoutTrays(provider, hatchIndex, next);
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _breakoutTextField(
                provider: provider,
                hatchIndex: hatchIndex,
                trays: trays,
                trayIndex: trayIndex,
                keyName: 'label',
                label: 'Label',
                value: label,
              ),
              _breakoutTextField(
                provider: provider,
                hatchIndex: hatchIndex,
                trays: trays,
                trayIndex: trayIndex,
                keyName: 'position',
                label: 'Position',
                value: (tray['position'] as String?) ?? '',
              ),
              _breakoutNumberField(
                provider: provider,
                hatchIndex: hatchIndex,
                trays: trays,
                trayIndex: trayIndex,
                label: 'Tray size',
                value: tray['traySize'],
                rootKey: 'traySize',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _breakoutCountFields.map((field) {
              return _breakoutNumberField(
                provider: provider,
                hatchIndex: hatchIndex,
                trays: trays,
                trayIndex: trayIndex,
                label: field.label,
                value: counts[field.key],
                countKey: field.key,
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
    required List<Map<String, dynamic>> trays,
    required int trayIndex,
    required String keyName,
    required String label,
    required String value,
  }) {
    return SizedBox(
      width: 150,
      child: TextFormField(
        key: ValueKey('${trays[trayIndex]['id']}-$keyName'),
        initialValue: value,
        enabled: !provider.isReadOnly,
        decoration: _inputDecoration(label),
        onChanged: (text) {
          final next = _copyBreakoutTrays(trays);
          next[trayIndex][keyName] = text;
          _persistBreakoutTrays(provider, hatchIndex, next);
        },
      ),
    );
  }

  Widget _breakoutNumberField({
    required AuditProvider provider,
    required int hatchIndex,
    required List<Map<String, dynamic>> trays,
    required int trayIndex,
    required String label,
    required Object? value,
    String? rootKey,
    String? countKey,
  }) {
    return SizedBox(
      width: 140,
      child: TextFormField(
        key: ValueKey('${trays[trayIndex]['id']}-$label'),
        initialValue: _intValue(value)?.toString() ?? '',
        enabled: !provider.isReadOnly,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: _inputDecoration(label),
        onChanged: (text) {
          final next = _copyBreakoutTrays(trays);
          final parsed = int.tryParse(text) ?? 0;
          if (rootKey != null) {
            next[trayIndex][rootKey] = parsed;
          }
          if (countKey != null) {
            final counts = Map<String, dynamic>.from(
              next[trayIndex]['counts'] as Map? ?? {},
            );
            counts[countKey] = parsed;
            next[trayIndex]['counts'] = counts;
          }
          _persistBreakoutTrays(provider, hatchIndex, next);
        },
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
    return TextFormField(
      key: ValueKey('${audit.id}-$field'),
      initialValue: value ?? '',
      enabled: !provider.isReadOnly,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      decoration: _inputDecoration(label),
      onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
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
    return TextFormField(
      key: ValueKey('${audit.id}-$field'),
      initialValue: value?.toString() ?? '',
      enabled: !provider.isReadOnly,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: _inputDecoration(label),
      onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
      onChanged: (text) {
        provider.updateHatchField(hatchIndex, field, int.tryParse(text));
        afterChanged?.call();
      },
    );
  }

  Widget _bmkAgeChip(int? ageWeeks) {
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
              'BMK Age ${_formatBmkAge(ageWeeks)}',
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
    final storageDays = audit.haStorageDays ?? audit.ebStorageDays ?? 0;
    final bmkAge = _calculateBmkAgeWeeks(provider, storageDays: storageDays);

    if (bmkAge != null && audit.haBmkAge != bmkAge) {
      provider.updateHatchField(hatchIndex, 'haBmkAge', bmkAge);
    }
    if (bmkAge != null && audit.ebBmkAge != bmkAge) {
      provider.updateHatchField(hatchIndex, 'ebBmkAge', bmkAge);
    }
  }

  int? _calculateBmkAgeWeeks(AuditProvider provider, {int? storageDays}) {
    final entryDate = provider.context?.flockEntryDate;
    if (entryDate == null) return null;
    final bmkAgeDays =
        hatch_dates.HatchDateUtils.flockAgeDays(entryDate) -
        21 -
        (storageDays ?? 0);
    if (bmkAgeDays <= 0) return 0;
    return (bmkAgeDays / 7).ceil();
  }

  String _formatBmkAge(int? ageWeeks) {
    if (ageWeeks == null) return '--';
    return '$ageWeeks wks';
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

  List<Map<String, dynamic>> _decodeBreakoutTrays(String? source) {
    if (source == null || source.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> _newBreakoutTray(int index) {
    return {
      'id': 'tray-${DateTime.now().microsecondsSinceEpoch}',
      'label': 'Tray $index',
      'position': '',
      'traySize': 150,
      'breakoutType': 'Hatch Residue',
      'counts': <String, int>{},
    };
  }

  List<Map<String, dynamic>> _copyBreakoutTrays(
    List<Map<String, dynamic>> trays,
  ) {
    return trays
        .map(
          (tray) => {
            ...tray,
            'counts': Map<String, dynamic>.from(tray['counts'] as Map? ?? {}),
          },
        )
        .toList();
  }

  void _persistBreakoutTrays(
    AuditProvider provider,
    int hatchIndex,
    List<Map<String, dynamic>> trays,
  ) {
    provider.updateHatchField(
      hatchIndex,
      'ebTrayBreakoutJson',
      jsonEncode(trays),
    );
    final breakoutType = trays.isEmpty
        ? null
        : (trays.first['breakoutType'] as String? ?? 'Hatch Residue');
    if (breakoutType != null) {
      provider.updateHatchField(hatchIndex, 'ebBreakoutType', breakoutType);
    }
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

const List<_BreakoutCountField> _breakoutCountFields = [
  _BreakoutCountField('Infertile', 'infertile'),
  _BreakoutCountField('Early Dead', 'earlyDead'),
  _BreakoutCountField('Mid Dead', 'midDead'),
  _BreakoutCountField('Late Dead', 'lateDead'),
  _BreakoutCountField('Internal Pip', 'internalPip'),
  _BreakoutCountField('External Pip', 'externalPip'),
  _BreakoutCountField('Cracked', 'cracked'),
  _BreakoutCountField('Contaminated', 'contaminated'),
  _BreakoutCountField('Malposition', 'malposition'),
  _BreakoutCountField('Exposed Brain', 'exposedBrain'),
  _BreakoutCountField('Crossed Beak', 'crossedBeak'),
  _BreakoutCountField('Culled/Dead', 'culledDead'),
];

class _BreakoutCountField {
  final String label;
  final String key;
  const _BreakoutCountField(this.label, this.key);
}
