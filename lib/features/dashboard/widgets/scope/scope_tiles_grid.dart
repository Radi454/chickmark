import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../providers/scope_comparison_provider.dart';
import '../../scope/scope_config.dart';
import '../../scope/scope_models.dart';
import 'scope_severity_style.dart';

/// Read-only tile grid for single-scope (pooled) sectors — label + value + dot.
class ScopeTilesGrid extends StatelessWidget {
  final String sectorId;

  const ScopeTilesGrid({super.key, required this.sectorId});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScopeComparisonProvider>();
    final sector = ScopeConfigRegistry.byId(sectorId);
    final groups = provider.groupsFor(sectorId);
    if (groups.isEmpty) return const SizedBox.shrink();
    final cells = groups.first.cells;

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSizes.spaceSm;
        const minTile = 132.0;
        final cols = (constraints.maxWidth / (minTile + gap))
            .floor()
            .clamp(1, 5);
        final tileW =
            (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Padding(
          padding: const EdgeInsets.only(top: AppSizes.spaceMd),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var j = 0; j < sector.params.length && j < cells.length; j++)
                SizedBox(
                  width: tileW,
                  child: _ScopeTile(
                    label: sector.params[j].label,
                    cell: cells[j],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ScopeTile extends StatelessWidget {
  final String label;
  final ScopeCell cell;

  const _ScopeTile({required this.label, required this.cell});

  @override
  Widget build(BuildContext context) {
    final style = ScopeSeverityStyle.of(cell.severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border.all(color: AppColors.borderDefault),
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  cell.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: cell.severity == ScopeSeverity.good ||
                            cell.severity == ScopeSeverity.pool
                        ? AppColors.textPrimary
                        : style.cellText,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              StatusDot(ScopeSeverityStyle.dotColor(cell.severity)),
            ],
          ),
        ],
      ),
    );
  }
}
