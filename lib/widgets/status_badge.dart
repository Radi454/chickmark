import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

class StatusBadge extends StatelessWidget {
  final String status;
  final String? label;

  const StatusBadge({
    super.key,
    required this.status,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final displayLabel = label ?? _capitalize(status);
    final (bgColor, textColor) = _getColors(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        displayLabel,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  (Color, Color) _getColors(String status) {
    final normalizedStatus = status.toLowerCase();
    switch (normalizedStatus) {
      case 'completed':
        return (AppColors.completedBg, AppColors.completedText);
      case 'active':
        return (AppColors.activeBg, AppColors.activeText);
      default:
        return (Colors.grey[300]!, Colors.grey[700]!);
    }
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }
}
