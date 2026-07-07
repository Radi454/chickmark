import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../providers/scope_comparison_provider.dart';
import 'scope_severity_style.dart';

/// Pick-chips that show/hide each comparison column. Leading `⌀ Avg` chip
/// appears when there is more than one group. All on by default.
class ColumnPickChips extends StatelessWidget {
  final String sectorId;
  final String avgLabel;

  const ColumnPickChips({
    super.key,
    required this.sectorId,
    this.avgLabel = '⌀ Avg',
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScopeComparisonProvider>();
    final groups = provider.groupsFor(sectorId);
    if (groups.length < 2) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.spaceSm),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          _PickChip(
            label: avgLabel,
            isAvg: true,
            active: provider.isAvgVisible(sectorId),
            onTap: () => context.read<ScopeComparisonProvider>().toggleColumn(
              sectorId,
              ScopeComparisonProvider.avgColumnId,
            ),
          ),
          for (var i = 0; i < groups.length; i++)
            _PickChip(
              label: groups[i].label,
              dot: ScopeSeverityStyle.dotColor(groups[i].severity),
              active: provider.isColumnVisible(sectorId, i),
              onTap: () => context.read<ScopeComparisonProvider>().toggleColumn(
                sectorId,
                i,
              ),
            ),
        ],
      ),
    );
  }
}

class _PickChip extends StatelessWidget {
  final String label;
  final bool active;
  final bool isAvg;
  final Color? dot;
  final VoidCallback onTap;

  const _PickChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.isAvg = false,
    this.dot,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color border;
    if (isAvg && active) {
      bg = AppColors.statusActive;
      fg = Colors.white;
      border = AppColors.statusActive;
    } else if (active) {
      bg = AppColors.statusActiveBg;
      fg = AppColors.statusActive;
      border = AppColors.statusActive.withValues(alpha: 0.30);
    } else {
      bg = AppColors.surface;
      fg = AppColors.textSecondary;
      border = AppColors.borderDefault;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                StatusDot(active ? dot! : dot!.withValues(alpha: 0.45)),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
