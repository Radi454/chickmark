import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../data/models/panel_sample_schema.dart';
import '../../../../widgets/app_card.dart';
import '../../providers/scope_comparison_provider.dart';
import '../../scope/scope_config.dart';
import 'column_pick_chips.dart';
import 'layer_toggle_bar.dart';
import 'scope_matrix_table.dart';
import 'scope_tiles_grid.dart';

/// One audit sector: header (title + note + optional "Example data" badge), then
/// either a read-only tiles grid (single-scope) or the layer filter + pick-chips
/// + comparison matrix (multi-scope).
class ScopeSectorWidget extends StatelessWidget {
  final String sectorId;

  const ScopeSectorWidget({super.key, required this.sectorId});

  @override
  Widget build(BuildContext context) {
    final sector = ScopeConfigRegistry.byId(sectorId);
    final isDummy =
        context.select<ScopeComparisonProvider, bool>((p) => p.isDummyFor(sectorId));
    final nonPool =
        sector.allowedLayers.where((l) => l != SamplingLayer.pool).toList();

    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSizes.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  sector.title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (isDummy) const _ExampleBadge(),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            sector.note,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
            ),
          ),
          if (sector.isSingleScope)
            ScopeTilesGrid(sectorId: sectorId)
          else ...[
            const SizedBox(height: AppSizes.spaceMd),
            Text(
              'Break down by — add layers to narrow, remove to broaden',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 6),
            LayerToggleBar(sectorId: sectorId, layers: nonPool),
            ColumnPickChips(sectorId: sectorId),
            ScopeMatrixTable(sectorId: sectorId),
          ],
        ],
      ),
    );
  }
}

class _ExampleBadge extends StatelessWidget {
  const _ExampleBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.statusWarningBg,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: const Text(
        'Example data',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
          color: AppColors.scopeWarnText,
        ),
      ),
    );
  }
}
