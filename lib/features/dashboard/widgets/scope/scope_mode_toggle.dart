import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../providers/scope_comparison_provider.dart';
import '../../scope/scope_config.dart';

/// Segmented Incremental ⇄ Cumulative switch bound to a sector's view mode.
/// Cumulative tints to the sector's axis color (age = blue, visit = orange).
/// Shared by [ScopeSectorWidget] and the bespoke Egg-Storage station body.
class ScopeModeToggle extends StatelessWidget {
  final String sectorId;
  final CumulativeAxis axis;

  const ScopeModeToggle({
    super.key,
    required this.sectorId,
    required this.axis,
  });

  @override
  Widget build(BuildContext context) {
    final isCumulative =
        context.watch<ScopeComparisonProvider>().isCumulative(sectorId);
    final cumColor =
        axis == CumulativeAxis.visit ? AppColors.accent : AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg(
            context,
            label: 'Incremental',
            on: !isCumulative,
            onColor: AppColors.primary,
            onTap: () => context
                .read<ScopeComparisonProvider>()
                .setCumulative(sectorId, false),
          ),
          _seg(
            context,
            label: 'Cumulative',
            icon: Icons.show_chart,
            on: isCumulative,
            onColor: cumColor,
            onTap: () => context
                .read<ScopeComparisonProvider>()
                .setCumulative(sectorId, true),
          ),
        ],
      ),
    );
  }

  Widget _seg(
    BuildContext context, {
    required String label,
    required bool on,
    required Color onColor,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: on ? onColor : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 13, color: on ? Colors.white : AppColors.textSecondary),
                const SizedBox(width: 3),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: on ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
