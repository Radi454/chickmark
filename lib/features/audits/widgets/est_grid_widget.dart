
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import 'photo_button.dart';

class EstGridWidget extends StatelessWidget {
  final Map<String, TextEditingController> controllers;
  final Map<String, String?> photos;
  final bool enabled;
  final Function(String key, String value) onValueChanged;
  final Function(String key, String path) onPhotoCaptured;

  const EstGridWidget({
    super.key,
    required this.controllers,
    required this.photos,
    required this.enabled,
    required this.onValueChanged,
    required this.onPhotoCaptured,
  });

  @override
  Widget build(BuildContext context) {
    final rows = ['Door', 'Middle', 'Back'];
    final cols = ['Top', 'Middle', 'Bottom'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          children: [
            const SizedBox(width: 60), // Spacer for row labels
            ...cols.map((col) => Expanded(
                  child: Center(
                    child: Text(
                      col,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )),
          ],
        ),
        const SizedBox(height: 8),
        // Grid rows
        ...rows.map((row) => _buildGridRow(row, cols)),
      ],
    );
  }

  Widget _buildGridRow(String row, List<String> cols) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row label
          SizedBox(
            width: 60,
            child: Text(
              row,
              style: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Grid cells
          ...cols.map((col) {
            final key = '${row.toLowerCase()}_${col.toLowerCase()}';
            return Expanded(
              child: _buildGridCell(key),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildGridCell(String key) {
    final controller = controllers[key];
    final photo = photos[key];
    final hasValue = controller?.text.isNotEmpty ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        decoration: BoxDecoration(
          color: hasValue ? AppColors.completedBg : Colors.white,
          borderRadius: BorderRadius.circular(AppSizes.cardRadius),
          border: Border.all(
            color: hasValue ? AppColors.completedText : Colors.grey[300]!,
            width: hasValue ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            // Status indicator
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: hasValue ? AppColors.completedText : Colors.transparent,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppSizes.cardRadius - 1),
                  topRight: Radius.circular(AppSizes.cardRadius - 1),
                ),
              ),
              child: Icon(
                hasValue ? Icons.check_circle : Icons.circle_outlined,
                color: hasValue ? Colors.white : Colors.grey,
                size: 16,
              ),
            ),
            // Temperature input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: TextField(
                controller: controller,
                enabled: enabled,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
                ],
                onChanged: (value) => onValueChanged(key, value),
              ),
            ),
            // Photo button
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PhotoButton(
                photoPath: photo,
                enabled: enabled,
                onPhotoCaptured: (path) => onPhotoCaptured(key, path),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
