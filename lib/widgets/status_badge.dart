import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_sizes.dart';
import '../core/theme/app_text_styles.dart';

class StatusBadge extends StatelessWidget {
  final String status;
  final String? label;

  const StatusBadge({super.key, required this.status, this.label});

  @override
  Widget build(BuildContext context) {
    final displayLabel = label ?? _capitalize(status);
    final (bgColor, textColor) = _getColors(status);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.spaceMd,
        vertical: AppSizes.spaceXs,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
      ),
      child: Text(
        displayLabel,
        style: AppTextStyles.badgeLabel.copyWith(color: textColor),
      ),
    );
  }

  (Color, Color) _getColors(String status) {
    final normalizedStatus = status.toLowerCase();
    switch (normalizedStatus) {
      case 'completed':
      case 'synced':
        return (AppColors.statusGoodBg, AppColors.statusGood);
      case 'active':
      case 'syncing':
        return (AppColors.statusActiveBg, AppColors.statusActive);
      case 'syncfailed':
      case 'failed':
      case 'error':
        return (AppColors.statusErrorBg, AppColors.statusError);
      default:
        return (AppColors.statusNeutralBg, AppColors.statusNeutralText);
    }
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }
}
