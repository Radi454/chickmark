import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_sizes.dart';
import '../core/theme/app_elevation.dart';
import '../core/theme/app_text_styles.dart';

class SectionCard extends StatelessWidget {
  final Widget child;
  final String? title;
  final EdgeInsets? padding;
  final bool isSaved;
  final VoidCallback? onEdit;

  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.padding,
    this.isSaved = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final cardPadding = padding ?? const EdgeInsets.all(AppSizes.cardPadding);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        boxShadow: AppElevation.level1,
        border: isSaved
            ? const Border(
                top: BorderSide(color: AppColors.statusGood, width: 3),
              )
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null || (isSaved && onEdit != null))
              Padding(
                padding: const EdgeInsets.all(AppSizes.spaceLg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (title != null)
                      Text(title!, style: AppTextStyles.sectionTitle),
                    if (isSaved && onEdit != null)
                      TextButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Edit'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.statusGood,
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: cardPadding,
              child: IgnorePointer(
                ignoring: isSaved,
                child: Opacity(opacity: isSaved ? 0.4 : 1.0, child: child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}