import 'package:hatchaudit/localized_material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/hatchery_agent_models.dart';
import '../../../widgets/app_card.dart';

class AgentSubmissionCard extends StatelessWidget {
  const AgentSubmissionCard({
    super.key,
    required this.summary,
    required this.isSelected,
    required this.onTap,
  });

  final HatcheryDraftBatchSummary summary;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = agentSubmissionStatusPresentation(summary.status);
    final sourceTitle =
        summary.sourceSummary ??
        summary.sourceFileName ??
        summary.sourceText ??
        'Telegram submission';
    final submitter = summary.telegramUserId == null
        ? 'Unknown staff'
        : 'Telegram user ${summary.telegramUserId}';

    return AppCard(
      key: ValueKey('agent-batch-${summary.id}'),
      onTap: onTap,
      margin: const EdgeInsets.only(bottom: AppSizes.spaceSm),
      color: isSelected ? AppColors.statusActiveBg : AppColors.surface,
      border: Border.all(
        color: isSelected ? AppColors.primary : AppColors.borderDefault,
        width: isSelected ? 1.5 : 1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: AppSizes.iconContainerSm,
                height: AppSizes.iconContainerSm,
                decoration: BoxDecoration(
                  color: status.background,
                  borderRadius: BorderRadius.circular(AppSizes.iconRadius),
                ),
                child: Icon(
                  _sourceIcon(summary.sourceKind),
                  color: status.foreground,
                  size: AppSizes.iconSm,
                ),
              ),
              const SizedBox(width: AppSizes.spaceSm),
              Expanded(
                child: Text(
                  sourceTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
          AgentStatusChip(presentation: status),
          const SizedBox(height: AppSizes.spaceSm),
          Text(
            submitter,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSizes.spaceXs),
          Text(
            _formatTimestamp(summary.submittedAt),
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Wrap(
            spacing: AppSizes.spaceSm,
            runSpacing: AppSizes.spaceXs,
            children: [
              _CountLabel(label: 'Rows', value: summary.rowCount),
              if (summary.needsReviewCount > 0)
                _CountLabel(
                  label: 'Review',
                  value: summary.needsReviewCount,
                  color: AppColors.statusWarning,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class AgentStatusChip extends StatelessWidget {
  const AgentStatusChip({super.key, required this.presentation});

  final AgentStatusPresentation presentation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceSm,
        vertical: AppSizes.spaceXs,
      ),
      decoration: BoxDecoration(
        color: presentation.background,
        borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
      ),
      child: Text(
        presentation.label,
        style: AppTextStyles.badgeLabel.copyWith(
          color: presentation.foreground,
        ),
      ),
    );
  }
}

class AgentStatusPresentation {
  const AgentStatusPresentation({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;
}

AgentStatusPresentation agentSubmissionStatusPresentation(
  AgentSubmissionStatus status,
) {
  return switch (status) {
    AgentSubmissionStatus.received => const AgentStatusPresentation(
      label: 'Received',
      foreground: AppColors.statusActive,
      background: AppColors.statusActiveBg,
    ),
    AgentSubmissionStatus.processing => const AgentStatusPresentation(
      label: 'Processing',
      foreground: AppColors.statusActive,
      background: AppColors.statusActiveBg,
    ),
    AgentSubmissionStatus.waitingForStaffAnswer =>
      const AgentStatusPresentation(
        label: 'Waiting for staff answer',
        foreground: AppColors.statusWarning,
        background: AppColors.statusWarningBg,
      ),
    AgentSubmissionStatus.draftReady => const AgentStatusPresentation(
      label: 'Draft ready',
      foreground: AppColors.statusGood,
      background: AppColors.statusGoodBg,
    ),
    AgentSubmissionStatus.needsAdminReview => const AgentStatusPresentation(
      label: 'Needs admin review',
      foreground: AppColors.statusWarning,
      background: AppColors.statusWarningBg,
    ),
    AgentSubmissionStatus.partiallyApproved => const AgentStatusPresentation(
      label: 'Partially approved',
      foreground: AppColors.statusActive,
      background: AppColors.statusActiveBg,
    ),
    AgentSubmissionStatus.approved => const AgentStatusPresentation(
      label: 'Approved',
      foreground: AppColors.statusGood,
      background: AppColors.statusGoodBg,
    ),
    AgentSubmissionStatus.rejected => const AgentStatusPresentation(
      label: 'Rejected',
      foreground: AppColors.statusError,
      background: AppColors.statusErrorBg,
    ),
    AgentSubmissionStatus.failed => const AgentStatusPresentation(
      label: 'Failed',
      foreground: AppColors.statusError,
      background: AppColors.statusErrorBg,
    ),
  };
}

class _CountLabel extends StatelessWidget {
  const _CountLabel({
    required this.label,
    required this.value,
    this.color = AppColors.statusNeutralText,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: $value',
      style: AppTextStyles.caption.copyWith(color: color),
    );
  }
}

IconData _sourceIcon(AgentSourceKind kind) {
  return switch (kind) {
    AgentSourceKind.text => Icons.chat_bubble_outline,
    AgentSourceKind.image => Icons.image_outlined,
    AgentSourceKind.pdf => Icons.picture_as_pdf_outlined,
    AgentSourceKind.spreadsheet => Icons.table_chart_outlined,
    AgentSourceKind.file => Icons.attach_file,
  };
}

String _formatTimestamp(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
