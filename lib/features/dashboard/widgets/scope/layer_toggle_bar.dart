import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../data/models/panel_sample_schema.dart';
import '../../providers/scope_comparison_provider.dart';
import '../../scope/scope_config.dart';

/// Multi-select "Break down by" filter. Each layer is a pill: off = outline +
/// `+`, on = filled blue + `✓`. Toggling narrows/broadens the matrix columns.
class LayerToggleBar extends StatelessWidget {
  final String sectorId;
  final List<SamplingLayer> layers;

  const LayerToggleBar({
    super.key,
    required this.sectorId,
    required this.layers,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScopeComparisonProvider>();
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final layer in layers)
          _LayerToggleChip(
            label: scopeLayerLabel(layer),
            active: provider.isLayerOn(sectorId, layer),
            onTap: () => context
                .read<ScopeComparisonProvider>()
                .toggleLayer(sectorId, layer),
          ),
      ],
    );
  }
}

class _LayerToggleChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _LayerToggleChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.statusActive : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            border: Border.all(
              color: active ? AppColors.statusActive : AppColors.borderDefault,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? Icons.check : Icons.add,
                size: 14,
                color: active
                    ? Colors.white
                    : AppColors.textSecondary.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
