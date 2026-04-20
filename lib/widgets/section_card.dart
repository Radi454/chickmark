import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_sizes.dart';

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
    final cardPadding = padding ?? EdgeInsets.all(AppSizes.cardPadding);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        boxShadow: [
          BoxShadow(
            color: const Color(0x0F000000),
            blurRadius: AppSizes.cardShadowBlur,
            offset: Offset(0, AppSizes.cardShadowOffsetY),
          ),
        ],
        border: isSaved
            ? const Border(
                top: BorderSide(
                  color: AppColors.completedText,
                  width: 3,
                ),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null || (isSaved && onEdit != null))
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (title != null)
                    Text(
                      title!,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  if (isSaved && onEdit != null)
                    TextButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Edit'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.completedText,
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: cardPadding,
            child: IgnorePointer(
              ignoring: isSaved,
              child: Opacity(
                opacity: isSaved ? 0.6 : 1.0,
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
