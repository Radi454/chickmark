import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../data/models/audit_model.dart';
import '../../models/culled_chicks_analysis.dart';
import '../audit_numeric_keyboard.dart';

class CulledChicksAnalysisTab extends StatefulWidget {
  final AuditModel audit;
  final bool isReadOnly;
  final Function(String key, dynamic value) onFieldChanged;
  final bool embedded;

  const CulledChicksAnalysisTab({
    super.key,
    required this.audit,
    required this.isReadOnly,
    required this.onFieldChanged,
    this.embedded = false,
  });

  @override
  State<CulledChicksAnalysisTab> createState() =>
      _CulledChicksAnalysisTabState();
}

class _CulledChicksAnalysisTabState extends State<CulledChicksAnalysisTab> {
  late final TextEditingController _totalEggSetController;
  final Map<String, TextEditingController> _countControllers = {};

  @override
  void initState() {
    super.initState();
    final totalEggSet = (widget.audit.culledChicksTotalEggSet ?? 0) > 0
        ? widget.audit.culledChicksTotalEggSet!
        : kDefaultCulledChicksTotalEggSet;
    _totalEggSetController = TextEditingController(
      text: totalEggSet.toString(),
    );
    final counts = CulledChicksAnalysisCodec.countsFromPercentages(
      widget.audit.culledChicksAnalysisJson,
      totalEggSet: totalEggSet,
    );
    for (final defect in kCulledChickDefects) {
      final count = counts[defect.id] ?? 0;
      _countControllers[defect.id] = TextEditingController(
        text: count > 0 ? count.toString() : '',
      );
    }
  }

  @override
  void dispose() {
    _totalEggSetController.dispose();
    for (final controller in _countControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _currentSummary();
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTotalEggSetField(),
        const SizedBox(height: 12),
        _buildSummaryStrip(summary),
        const SizedBox(height: 16),
        for (final category in _categories) ...[
          _CategoryHeader(category: category),
          const SizedBox(height: 8),
          for (final defect in _defectsFor(category))
            _DefectCountRow(
              defect: defect,
              controller: _countControllers[defect.id]!,
              percent: summary.defectPct(defect.id),
              enabled: !widget.isReadOnly,
              onChanged: _syncAnalysis,
            ),
          const SizedBox(height: 12),
        ],
      ],
    );

    if (widget.embedded) return AuditNumericKeyboardScope(child: content);

    return AuditNumericKeyboardScope(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: content,
      ),
    );
  }

  Widget _buildTotalEggSetField() {
    return AuditNumericField(
      key: const ValueKey('culled-chicks-total-egg-set'),
      controller: _totalEggSetController,
      enabled: !widget.isReadOnly,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        labelText: 'Total Egg Set',
      ),
      onChanged: (value) {
        widget.onFieldChanged(
          'culledChicksTotalEggSet',
          int.tryParse(value) ?? kDefaultCulledChicksTotalEggSet,
        );
        _syncAnalysis();
      },
    );
  }

  Widget _buildSummaryStrip(CulledChicksAnalysisSummary summary) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SummaryChip(
          label: 'Total %',
          value: '${summary.affectedPct.toStringAsFixed(3)}%',
        ),
        _SummaryChip(label: 'Top', value: summary.topSubtype ?? '--'),
      ],
    );
  }

  CulledChicksAnalysisSummary _currentSummary() {
    return CulledChicksAnalysisSummary.fromCounts(
      _countsById(),
      totalEggSet: _totalEggSet,
    );
  }

  void _syncAnalysis() {
    final totalEggSet = _totalEggSet;
    final summary = CulledChicksAnalysisSummary.fromCounts(
      _countsById(),
      totalEggSet: totalEggSet,
    );
    final json = summary.encodedJson;
    widget.onFieldChanged('culledChicksTotalEggSet', totalEggSet);
    widget.onFieldChanged('culledChicksAnalysisJson', json);
    widget.onFieldChanged('culledChicksAffectedPct', summary.affectedPct);
    widget.onFieldChanged('culledChicksTopCategory', summary.topCategory);
    widget.onFieldChanged('culledChicksTopSubtype', summary.topSubtype);
    if (mounted) setState(() {});
  }

  Map<String, int> _countsById() {
    return {
      for (final entry in _countControllers.entries)
        if ((int.tryParse(entry.value.text) ?? 0) > 0)
          entry.key: int.tryParse(entry.value.text) ?? 0,
    };
  }

  int get _totalEggSet {
    final parsed = int.tryParse(_totalEggSetController.text);
    if (parsed == null || parsed <= 0) return kDefaultCulledChicksTotalEggSet;
    return parsed;
  }

  List<String> get _categories {
    final categories = <String>[];
    for (final defect in kCulledChickDefects) {
      if (!categories.contains(defect.category)) {
        categories.add(defect.category);
      }
    }
    return categories;
  }

  List<CulledChickDefect> _defectsFor(String category) {
    return kCulledChickDefects
        .where((defect) => defect.category == category)
        .toList();
  }
}

class _CategoryHeader extends StatelessWidget {
  final String category;

  const _CategoryHeader({required this.category});

  @override
  Widget build(BuildContext context) {
    return Text(
      category,
      style: AppTextStyles.body.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _DefectCountRow extends StatelessWidget {
  final CulledChickDefect defect;
  final TextEditingController controller;
  final double percent;
  final bool enabled;
  final VoidCallback onChanged;

  const _DefectCountRow({
    required this.defect,
    required this.controller,
    required this.percent,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderDefault),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          defect.subtype,
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (percent > 0) ...[
                          const SizedBox(height: 3),
                          Text(
                            '${percent.toStringAsFixed(3)}% of egg set',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _CountStepper(
                  defectId: defect.id,
                  controller: controller,
                  enabled: enabled,
                  onChanged: onChanged,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CountStepper extends StatelessWidget {
  final String defectId;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  const _CountStepper({
    required this.defectId,
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  int get _count => int.tryParse(controller.text) ?? 0;

  void _setCount(int count) {
    final safeCount = count < 0 ? 0 : count;
    final text = safeCount == 0 ? '' : safeCount.toString();
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    return SizedBox(
      width: 154,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            buttonKey: ValueKey('culled-chicks-decrement-$defectId'),
            icon: Icons.remove,
            tooltip: 'Decrease count',
            onPressed: enabled && count > 0 ? () => _setCount(count - 1) : null,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: AuditNumericField(
              key: ValueKey('culled-chicks-count-$defectId'),
              controller: controller,
              enabled: enabled,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Count',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(width: 6),
          _StepButton(
            buttonKey: ValueKey('culled-chicks-increment-$defectId'),
            icon: Icons.add,
            tooltip: 'Increase count',
            onPressed: enabled ? () => _setCount(count + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final Key buttonKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _StepButton({
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final activeBorder = AppColors.primary.withValues(alpha: 0.24);
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 36,
        child: OutlinedButton(
          key: buttonKey,
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: AppColors.primary,
            disabledForegroundColor: AppColors.textTertiary,
            backgroundColor: AppColors.primary.withValues(alpha: 0.06),
            disabledBackgroundColor: AppColors.surfaceVariant,
            side: BorderSide(
              color: onPressed == null ? AppColors.borderDefault : activeBorder,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTextStyles.badgeLabel.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
