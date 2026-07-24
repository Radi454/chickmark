import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/audit_session_model.dart';
import '../../../widgets/app_card.dart';

class IncompleteVisitCard extends StatelessWidget {
  const IncompleteVisitCard({
    super.key,
    required this.session,
    required this.customerName,
    required this.flockLabel,
    required this.missingStationLabels,
    required this.onTap,
    this.breed,
  });

  final AuditSessionModel session;
  final String customerName;
  final String flockLabel;
  final String? breed;
  final List<String> missingStationLabels;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final breedPart = breed == null || breed!.trim().isEmpty
        ? ''
        : ' · ${breed!.trim()}';
    final completed = session.stationsCompleted
        .where(session.selectedStationKeys.contains)
        .length;
    final total = session.selectedStationKeys.length;
    final stationWord = total == 1 ? 'station' : 'stations';
    final missing = missingStationLabels.isEmpty
        ? 'Still needed: Review visit'
        : 'Still needed: ${missingStationLabels.join(', ')}';

    return AppCard(
      key: ValueKey('home-incomplete-visit-${session.id}'),
      margin: EdgeInsets.zero,
      color: AppColors.statusWarningBg,
      border: Border.all(
        color: AppColors.statusWarning.withValues(alpha: 0.35),
      ),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.pending_actions_outlined,
                color: AppColors.statusWarning,
                size: AppSizes.iconSm,
              ),
              const SizedBox(width: AppSizes.spaceSm),
              Expanded(
                child: Text('Incomplete visit', style: AppTextStyles.title),
              ),
              Text(
                '$completed/$total $stationWord complete',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.statusWarning,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Text(
            '$customerName · $flockLabel$breedPart · '
            '${HatchDateUtils.formatDisplayDate(session.date)}',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Text(missing, style: AppTextStyles.caption),
          const SizedBox(height: AppSizes.spaceXs),
          Text(
            'Please complete this visit soon.',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.statusWarning,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSizes.spaceMd),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              key: ValueKey('home-complete-now-${session.id}'),
              onPressed: onTap,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Complete now'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.statusWarning,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
