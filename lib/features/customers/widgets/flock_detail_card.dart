import 'package:flutter/material.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/flock_model.dart';

class FlockDetailCard extends StatelessWidget {
  final FlockModel flock;
  final VoidCallback? onTap;

  const FlockDetailCard({super.key, required this.flock, this.onTap});

  @override
  Widget build(BuildContext context) {
    final ageWeeks = flock.currentAgeWeeks.toInt();
    final displayAge = ageWeeks < 0 ? 0 : ageWeeks;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Flock ID', flock.flockId),
              const SizedBox(height: 12),
              _buildDetailRow('Breed', flock.breed),
              const SizedBox(height: 12),
              _buildDetailRow(
                flock.isAgeEstimated ? 'Estimated Entry Date' : 'Entry Date',
                '${flock.entryDate.day}/${flock.entryDate.month}/${flock.entryDate.year}',
                isEstimated: flock.isAgeEstimated,
              ),
              const SizedBox(height: 12),
              _buildDetailRow(
                'Current Age',
                '$displayAge weeks',
                isAutoCalculated: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    bool isAutoCalculated = false,
    bool isEstimated = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.body.copyWith(
            color: AppColors.statusNeutralText,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (isAutoCalculated || isEstimated)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.ageBadgeBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isEstimated
                      ? Icons.warning_amber_outlined
                      : Icons.auto_awesome,
                  size: 14,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  value,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          )
        else
          Text(
            value,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}
