import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:hatchaudit/localized_material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../data/models/audit_model.dart';
import '../../models/egg_grading.dart';

class EggGradingSection extends StatefulWidget {
  final AuditModel audit;
  final Map<String, int> gradingCounts;
  final bool isReadOnly;
  final ValueChanged<dynamic> onSampleSizeChanged;
  final ValueChanged<dynamic> onRejectedCountChanged;
  final ValueChanged<Map<String, int>> onCountsChanged;

  const EggGradingSection({
    super.key,
    required this.audit,
    required this.gradingCounts,
    required this.isReadOnly,
    required this.onSampleSizeChanged,
    required this.onRejectedCountChanged,
    required this.onCountsChanged,
  });

  @override
  State<EggGradingSection> createState() => _EggGradingSectionState();
}

class _EggGradingSectionState extends State<EggGradingSection> {
  late final TextEditingController _sampleSizeController;
  late final TextEditingController _rejectedCountController;
  final Map<String, TextEditingController> _countControllers = {};

  @override
  void initState() {
    super.initState();
    _sampleSizeController = TextEditingController();
    _rejectedCountController = TextEditingController();
    for (final defect in kEggDefectTypes) {
      _countControllers[defect.code] = TextEditingController();
    }
    _loadDraft();
  }

  @override
  void didUpdateWidget(covariant EggGradingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audit.id != widget.audit.id) _loadDraft();
  }

  @override
  void dispose() {
    _sampleSizeController.dispose();
    _rejectedCountController.dispose();
    for (final controller in _countControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final errors = EggGradingValidation.validate(
      sampleSize: _sampleSize,
      rejectedCount: _rejectedCount,
      counts: _counts,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInputs(),
        const SizedBox(height: 12),
        _buildSummaryStrip(summary),
        if (errors.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final error in errors)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                error,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.statusError,
                ),
              ),
            ),
        ],
        const SizedBox(height: 16),
        for (final category in _categories) ...[
          Text(
            category,
            style: AppTextStyles.body.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final defect in _defectsFor(category))
            _EggDefectCountRow(
              defect: defect,
              controller: _countControllers[defect.code]!,
              percent: summary.pctFor(defect.code),
              enabled: !widget.isReadOnly,
              onChanged: _syncCounts,
            ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildInputs() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('egg-grading-sample-size'),
            controller: _sampleSizeController,
            enabled: !widget.isReadOnly,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Eggs inspected',
            ),
            onChanged: (_) => _syncSampleSize(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            key: const Key('egg-grading-rejected'),
            controller: _rejectedCountController,
            enabled: !widget.isReadOnly,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Eggs rejected',
            ),
            onChanged: (_) => _syncRejectedCount(),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryStrip(EggGradingSummary summary) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _EggGradingSummaryChip(
          label: 'Acceptable',
          count: summary.acceptableCount,
          percent: summary.acceptablePct,
        ),
        _EggGradingSummaryChip(
          label: 'Rejected',
          count: summary.rejectedCount,
          percent: summary.rejectedPct,
        ),
        if (summary.topDefectCode case final code?)
          _EggGradingTopDefectChip(
            defectName: eggDefectTypeForCode(code)?.name ?? code,
            percent: summary.topDefectPct ?? 0,
          ),
      ],
    );
  }

  EggGradingSummary get _summary => EggGradingSummary.fromCounts(
    sampleSize: _sampleSize,
    rejectedCount: _rejectedCount,
    counts: _counts,
  );

  int get _sampleSize => _parseCount(_sampleSizeController.text);

  int get _rejectedCount => _parseCount(_rejectedCountController.text);

  Map<String, int> get _counts => {
    for (final entry in widget.gradingCounts.entries)
      if (eggDefectTypeForCode(entry.key) == null && entry.value > 0)
        entry.key: entry.value,
    for (final entry in _countControllers.entries)
      if (_parseCount(entry.value.text) > 0)
        entry.key: _parseCount(entry.value.text),
  };

  void _loadDraft() {
    _sampleSizeController.text = _textFor(widget.audit.esGradingSampleSize);
    _rejectedCountController.text = _textFor(
      widget.audit.esGradingRejectedCount,
    );
    for (final defect in kEggDefectTypes) {
      _countControllers[defect.code]!.text = _textFor(
        widget.gradingCounts[defect.code],
      );
    }
  }

  void _syncSampleSize() {
    widget.onSampleSizeChanged(_nullableCount(_sampleSizeController.text));
    widget.onCountsChanged(_counts);
    if (mounted) setState(() {});
  }

  void _syncRejectedCount() {
    widget.onRejectedCountChanged(
      _nullableCount(_rejectedCountController.text),
    );
    widget.onCountsChanged(_counts);
    if (mounted) setState(() {});
  }

  void _syncCounts() {
    widget.onCountsChanged(_counts);
    if (mounted) setState(() {});
  }

  int _parseCount(String value) => int.tryParse(value) ?? 0;

  int? _nullableCount(String value) {
    final parsed = int.tryParse(value);
    return parsed == null || parsed == 0 ? null : parsed;
  }

  String _textFor(int? value) => value == null || value == 0 ? '' : '$value';

  List<String> get _categories {
    final categories = <String>{
      for (final defect in kEggDefectTypes) defect.category,
    }.toList();
    categories.sort((a, b) => _firstSortOrder(a).compareTo(_firstSortOrder(b)));
    return categories;
  }

  int _firstSortOrder(String category) => kEggDefectTypes
      .where((defect) => defect.category == category)
      .map((defect) => defect.sortOrder)
      .reduce((first, next) => first < next ? first : next);

  List<EggDefectType> _defectsFor(String category) {
    final defects = kEggDefectTypes
        .where((defect) => defect.category == category)
        .toList();
    defects.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return defects;
  }
}

class _EggGradingSummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final double percent;

  const _EggGradingSummaryChip({
    required this.label,
    required this.count,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Text('$label $count (${percent.toStringAsFixed(1)}%)'),
    );
  }
}

class _EggGradingTopDefectChip extends StatelessWidget {
  final String defectName;
  final double percent;

  const _EggGradingTopDefectChip({
    required this.defectName,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Text('Top defect: $defectName ${percent.toStringAsFixed(1)}%'),
    );
  }
}

class _EggDefectCountRow extends StatelessWidget {
  final EggDefectType defect;
  final TextEditingController controller;
  final double percent;
  final bool enabled;
  final VoidCallback onChanged;

  const _EggDefectCountRow({
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
        child: Row(
          children: [
            defect.imageAsset == null
                ? const SizedBox(width: 40, height: 40)
                : Image.asset(defect.imageAsset!, width: 40, height: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    defect.name,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    percent > 0
                        ? '${percent.toStringAsFixed(1)}% of eggs inspected'
                        : '-',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 76,
              child: TextField(
                key: Key('egg-grading-count-${defect.code}'),
                controller: controller,
                enabled: enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => onChanged(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
