import 'package:hatchaudit/localized_material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_text_styles.dart';
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
          else if (elisaTrends.isNotEmpty)
            LabAnalysisTrendPanel(series: elisaTrends.first),
        ],
      ),
    );
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
