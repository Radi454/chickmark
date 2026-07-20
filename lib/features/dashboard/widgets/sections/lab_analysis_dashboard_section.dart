import 'package:hatchaudit/localized_material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../data/models/lab_analysis_models.dart';
import '../../../../widgets/app_card.dart';
import '../../models/lab_analysis_trend_models.dart';
import '../lab_analysis_trend_panel.dart';

class LabAnalysisDashboardSection extends StatelessWidget {
  const LabAnalysisDashboardSection({
    super.key,
    required this.summaries,
    required this.isLoading,
  });

  final List<LabAnalysisDashboardSummary> summaries;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final alertCount = summaries.fold<int>(0, (sum, item) {
      return sum + item.alertCount;
    });
    final watchCount = summaries.fold<int>(0, (sum, item) {
      return sum + item.watchCount;
    });
    final reportCount = summaries.map((item) => item.report.id).toSet().length;
    final types = summaries.map((item) => item.group.testType).toSet().length;
    final elisaTrends = LabAnalysisTrendBuilder.buildElisa(summaries);

    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.biotech_outlined, color: AppColors.primary),
              const SizedBox(width: AppSizes.spaceSm),
              Expanded(
                child: Text('Lab Analysis', style: AppTextStyles.sectionTitle),
              ),
              if (isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Text(
            'Breeder farm lab signals from ELISA, PCR, HI, bacterial culture, and sensitivity records.',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSizes.spaceMd),
          Wrap(
            spacing: AppSizes.spaceSm,
            runSpacing: AppSizes.spaceSm,
            children: [
              _Metric(label: 'Reports', value: '$reportCount'),
              _Metric(label: 'Test types', value: '$types'),
              _Metric(label: 'Alerts', value: '$alertCount'),
              _Metric(label: 'Watch', value: '$watchCount'),
            ],
          ),
          const SizedBox(height: AppSizes.spaceMd),
          if (!isLoading && summaries.isEmpty)
            const _EmptyLabState()
          else ...[
            if (elisaTrends.isNotEmpty) ...[
              LabAnalysisTrendPanel(series: elisaTrends.first),
              const SizedBox(height: AppSizes.spaceLg),
            ],
            Text('Recent findings', style: AppTextStyles.subtitle),
            const SizedBox(height: AppSizes.spaceSm),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth < 720 ? 1 : 2;
                final gap = columns == 1 ? 0.0 : AppSizes.spaceMd;
                final width = (constraints.maxWidth - gap) / columns;
                return Wrap(
                  spacing: AppSizes.spaceMd,
                  runSpacing: AppSizes.spaceMd,
                  children: [
                    for (final summary in summaries.take(8))
                      SizedBox(
                        width: width,
                        child: _LabFindingCard(summary: summary),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _LabFindingCard extends StatelessWidget {
  const _LabFindingCard({required this.summary});

  final LabAnalysisDashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final group = summary.group;
    final color = _severityColor(group.severity);
    final bg = _severityBg(group.severity);
    return Container(
      padding: const EdgeInsets.all(AppSizes.spaceMd),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Pill(label: group.testType.label, color: color),
              const SizedBox(width: AppSizes.spaceXs),
              Expanded(
                child: Text(
                  _title(group),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceXs),
          Text(
            HatchDateUtils.formatDisplayDate(summary.report.reportDate),
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Text(
            group.interpretation,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body,
          ),
          const SizedBox(height: AppSizes.spaceSm),
          _SummaryLine(group: group, rows: summary.rows),
        ],
      ),
    );
  }

  String _title(LabAnalysisGroupModel group) {
    final scope = group.groupLabel.isEmpty
        ? group.sampleScope
        : group.groupLabel;
    final target = group.testType == LabTestType.hi
        ? group.antigen
        : group.analyte;
    if (scope.isEmpty) return target.isEmpty ? group.testType.label : target;
    if (target.isEmpty) return scope;
    return '$scope · $target';
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.group, required this.rows});

  final LabAnalysisGroupModel group;
  final List<LabAnalysisRowModel> rows;

  @override
  Widget build(BuildContext context) {
    final parts = switch (group.testType) {
      LabTestType.elisa => [
        if (group.gmtTiter != null) 'GMT ${group.gmtTiter!.toStringAsFixed(0)}',
        if (group.cvPct != null) 'CV ${group.cvPct!.toStringAsFixed(0)}%',
        if (group.positivePct != null)
          '+ ${group.positivePct!.toStringAsFixed(0)}%',
      ],
      LabTestType.pcr => [
        '${group.positiveCount ?? 0}/${group.sampleCount ?? rows.length} positive',
        if (_minCt(rows) != null) 'min Ct ${_minCt(rows)!.toStringAsFixed(1)}',
      ],
      LabTestType.hi => [
        if (group.gmLog2 != null) 'GM ${group.gmLog2!.toStringAsFixed(1)}',
        if (group.protectivePct != null)
          'protected ${group.protectivePct!.toStringAsFixed(0)}%',
      ],
      LabTestType.culture => [
        '${group.positiveCount ?? 0}/${group.sampleCount ?? rows.length} positive',
        if ((group.method).trim().isNotEmpty) group.method,
      ],
      LabTestType.sensitivity => [
        '${_categoryCount(rows, 'S')} S',
        '${_categoryCount(rows, 'I')} I',
        '${_categoryCount(rows, 'R')} R',
      ],
    };
    return Text(
      parts.isEmpty ? '${rows.length} rows' : parts.join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary),
    );
  }

  double? _minCt(List<LabAnalysisRowModel> rows) {
    double? min;
    for (final row in rows) {
      final ct = row.ctValue;
      if (ct == null) continue;
      min = min == null || ct < min ? ct : min;
    }
    return min;
  }

  int _categoryCount(List<LabAnalysisRowModel> rows, String category) {
    return rows.where((row) {
      return row.sensitivityCategory.toUpperCase().startsWith(category);
    }).length;
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      padding: const EdgeInsets.all(AppSizes.spaceSm),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 2),
          Text(value, style: AppTextStyles.title),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyLabState extends StatelessWidget {
  const _EmptyLabState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.spaceMd),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        children: [
          const Icon(Icons.science_outlined, color: AppColors.textTertiary),
          const SizedBox(width: AppSizes.spaceSm),
          Expanded(
            child: Text(
              'No lab analysis records for this filter yet.',
              style: AppTextStyles.caption,
            ),
          ),
        ],
      ),
    );
  }
}

Color _severityColor(LabSeverity severity) {
  return switch (severity) {
    LabSeverity.normal => AppColors.statusGood,
    LabSeverity.watch => AppColors.statusWarning,
    LabSeverity.alert => AppColors.statusError,
  };
}

Color _severityBg(LabSeverity severity) {
  return switch (severity) {
    LabSeverity.normal => AppColors.statusGoodBg,
    LabSeverity.watch => AppColors.statusWarningBg,
    LabSeverity.alert => AppColors.statusErrorBg,
  };
}
