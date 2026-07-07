import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../models/scope_cumulative.dart';
import '../../providers/scope_comparison_provider.dart';

/// Independent BMK-age selector for one dashboard sector.
class ScopeAgePicker extends StatelessWidget {
  final String sectorId;

  const ScopeAgePicker({super.key, required this.sectorId});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScopeComparisonProvider>();
    final periods = provider.periodsFor(sectorId);
    if (periods.isEmpty) return const SizedBox.shrink();

    final selected = provider.selectedPeriodFor(sectorId);
    final label = selected?.label ?? 'All BMK Ages';
    final active = selected != null;

    return PopupMenuButton<ScopePeriod?>(
      tooltip: context.tr('Pick BMK age'),
      position: PopupMenuPosition.under,
      onSelected: (period) =>
          context.read<ScopeComparisonProvider>().setPeriod(sectorId, period),
      itemBuilder: (context) => [
        PopupMenuItem<ScopePeriod?>(
          value: null,
          child: _menuRow('All BMK Ages', selected == null),
        ),
        for (final period in periods)
          PopupMenuItem<ScopePeriod?>(
            value: period,
            child: _menuRow(period.label, selected?.sameAs(period) ?? false),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.statusActiveBg : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          border: Border.all(
            color: active
                ? AppColors.statusActive.withValues(alpha: 0.3)
                : AppColors.borderDefault,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_note,
              size: 14,
              color: active ? AppColors.statusActive : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: active
                    ? AppColors.statusActive
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: active ? AppColors.statusActive : AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuRow(String text, bool selected) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              color: selected ? AppColors.statusActive : AppColors.textPrimary,
            ),
          ),
        ),
        if (selected)
          const Icon(Icons.check, size: 15, color: AppColors.statusActive),
      ],
    );
  }
}
