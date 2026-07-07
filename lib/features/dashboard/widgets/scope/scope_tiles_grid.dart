import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../providers/scope_comparison_provider.dart';
import '../../scope/scope_config.dart';
import '../../scope/scope_models.dart';
import '../../scope/scope_severity.dart';
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
    final bmk = provider.bmkFor(sectorId);

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
                    param: sector.params[j],
                    cell: cells[j],
                    bmk: bmkLookup(bmk, sector.params[j].bmkField),
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
  final ScopeParam param;
  final ScopeCell cell;
  final num? bmk;

  const _ScopeTile({required this.param, required this.cell, this.bmk});

  @override
  Widget build(BuildContext context) {
    final style = ScopeSeverityStyle.of(cell.severity);
    final bmkValue = bmk;
    final actual = cell.value;
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
            param.label,
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
          if (param.bmkField != null && bmkValue != null) ...[
            const SizedBox(height: 3),
            Text(
              'BMK ${param.formatValue(bmkValue)}'
              '${actual == null ? '' : '  ${param.formatGap(actual - bmkValue)}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.statusNeutralText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
