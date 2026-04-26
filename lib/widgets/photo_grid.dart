import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';

class PhotoGrid extends StatelessWidget {
  final List<String> filePaths;
  final Function(String)? onTap;

  const PhotoGrid({super.key, required this.filePaths, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (filePaths.isEmpty) {
      return _buildEmptyState();
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: AppSizes.spaceXs,
        crossAxisSpacing: AppSizes.spaceXs,
      ),
      itemCount: filePaths.length,
      itemBuilder: (context, index) => _buildTile(filePaths[index]),
    );
  }

  Widget _buildTile(String path) {
    return GestureDetector(
      onTap: onTap != null ? () => onTap!(path) : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.spaceXs),
        child: File(path).existsSync()
            ? Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildPlaceholder(),
              )
            : _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.background,
      child: const Icon(Icons.image, color: AppColors.textTertiary),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.photo_library_outlined,
            size: AppSizes.iconLg,
            color: AppColors.textDisabled,
          ),
          const SizedBox(height: AppSizes.spaceSm),
          const Text('No photos', style: AppTextStyles.caption),
        ],
      ),
    );
  }
}
