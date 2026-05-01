import 'package:flutter/material.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/audit_type_labels.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/flock_model.dart';
import '../../../widgets/status_badge.dart';

class AuditHistoryCard extends StatelessWidget {
  final AuditModel audit;
  final FlockModel? flock;
  final VoidCallback? onTap;

  const AuditHistoryCard({
    super.key,
    required this.audit,
    this.flock,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ageWeeks = flock != null
        ? HatchDateUtils.flockAgeWeeks(flock!.entryDate)
        : 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildAgeBadge(ageWeeks),
                  StatusBadge(status: audit.status),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                AuditTypeLabels.forAuditType(audit.auditType),
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Flock: ${flock?.flockId ?? audit.flockId ?? "Unknown"}',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: 8),
              Text(_formatDate(audit.date), style: AppTextStyles.caption),
              if (audit.setterId != null) ...[
                const SizedBox(height: 8),
                Text('Setter: ${audit.setterId}', style: AppTextStyles.caption),
              ],
              if (audit.hatcherId != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Hatcher: ${audit.hatcherId}',
                  style: AppTextStyles.caption,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgeBadge(int ageWeeks) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.ageBadgeBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$ageWeeks wks',
        style: AppTextStyles.caption.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')} '
        '${_monthAbbreviation(date.month)} '
        '${date.year}';
  }

  String _monthAbbreviation(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}
