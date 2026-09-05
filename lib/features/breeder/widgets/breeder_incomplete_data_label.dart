import 'package:hatchaudit/localized_material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../services/breeder/breeder_report_period_service.dart';

/// The prominent `Incomplete Data` marker weekly and cumulative views must
/// carry (breeder-flock-performance ticket 12, design doc section 12/14:
/// "Weekly and cumulative output identifies missing dates and is labelled
/// incomplete, with recorded and missing day counts" — and the ticket's UI
/// note: "Weekly/cumulative views must carry the incomplete-data label and
/// counts prominently, not as a footnote").
///
/// Renders nothing (an empty [SizedBox]) for a fully-recorded
/// [completeness] — an unwarranted "incomplete" banner on complete data
/// would be as misleading as a missing one on incomplete data.
class BreederIncompleteDataLabel extends StatelessWidget {
  final BreederPeriodCompleteness completeness;

  const BreederIncompleteDataLabel({super.key, required this.completeness});

  @override
  Widget build(BuildContext context) {
    if (completeness.isComplete) return const SizedBox.shrink();

    return Container(
      key: const Key('breederIncompleteDataLabel'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.cardPadding,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.statusWarningBg,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.statusWarning),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.statusWarning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Incomplete Data'),
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.statusWarning,
                  ),
                ),
                Text(
                  '${context.tr("Recorded")}: '
                  '${completeness.recordedDayCount} / '
                  '${completeness.totalDayCount}   '
                  '${context.tr("Missing")}: '
                  '${completeness.missingDayCount}',
                  style: AppTextStyles.body.copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The visible partial-data warning a benchmark comparison must carry
/// whenever the period behind it is incomplete (design doc section 14:
/// "Partial results may be compared with the official benchmark only with
/// a visible partial-data warning"). Renders nothing for a complete period.
class BreederPartialDataWarning extends StatelessWidget {
  final BreederBenchmarkPeriodComparison comparison;

  const BreederPartialDataWarning({super.key, required this.comparison});

  @override
  Widget build(BuildContext context) {
    final warning = comparison.partialDataWarning;
    if (warning == null) return const SizedBox.shrink();

    return Container(
      key: const Key('breederPartialDataWarning'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.cardPadding,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.statusWarningBg,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.statusWarning),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            color: AppColors.statusWarning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr(warning),
              style: AppTextStyles.body.copyWith(
                color: AppColors.statusWarning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
