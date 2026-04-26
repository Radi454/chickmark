import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_sizes.dart';
import '../core/theme/app_text_styles.dart';

class TempToggle extends StatelessWidget {
  const TempToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final isFahrenheit = appProvider.tempUnit == TempUnit.fahrenheit;

    return Container(
      width: 108,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: isFahrenheit
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.all(AppSizes.spaceXs),
              child: Container(
                width: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _buildSegment(
                  label: '°F',
                  isSelected: isFahrenheit,
                  onTap: () {
                    if (!isFahrenheit) {
                      HapticFeedback.selectionClick();
                      appProvider.setTempUnit(TempUnit.fahrenheit);
                    }
                  },
                ),
              ),
              Expanded(
                child: _buildSegment(
                  label: '°C',
                  isSelected: !isFahrenheit,
                  onTap: () {
                    if (isFahrenheit) {
                      HapticFeedback.selectionClick();
                      appProvider.setTempUnit(TempUnit.celsius);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegment(
    {
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTextStyles.subtitle.copyWith(
            color: isSelected
                ? AppColors.textOnPrimary
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
