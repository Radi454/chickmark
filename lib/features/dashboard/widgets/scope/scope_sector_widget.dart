import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../data/models/panel_sample_schema.dart';
import '../../../../widgets/app_card.dart';
import '../../models/scope_cumulative.dart';
import '../../providers/scope_comparison_provider.dart';
import '../../scope/scope_config.dart';
import 'column_pick_chips.dart';
import 'hatch_age_chart.dart';
import 'layer_toggle_bar.dart';
import 'scope_chart_view.dart';
import 'scope_cumulative_view.dart';
import 'scope_matrix_table.dart';
import 'scope_mode_toggle.dart';
import 'scope_tiles_grid.dart';

/// One audit sector: header (title + note + optional "Example data" badge), an
/// Incremental ⇄ Cumulative mode toggle + period picker, then either the
/// read-only tiles grid / comparison matrix (Incremental) or the per-axis trend
/// (Cumulative). Incremental keeps the exact prior behavior.
class ScopeSectorWidget extends StatelessWidget {
  final String sectorId;

  /// When false, the tick + bold title line is hidden (note and controls stay).
  /// Used when an outer tab bar already names the sector.
  final bool showTitle;

  const ScopeSectorWidget({
    super.key,
    required this.sectorId,
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    final sector = ScopeConfigRegistry.byId(sectorId);
    final provider = context.watch<ScopeComparisonProvider>();
    final isDummy = provider.isDummyFor(sectorId);
    final isEmpty = provider.isEmptyFor(sectorId);
    final isChart = provider.isChartMode(sectorId);
    final isCumulative = provider.isCumulative(sectorId);
    // Chart mode is an Act-vs-STD view, so only offer it when the sector has at
    // least one benchmarked numeric param to compare.
    final hasChartable = sector.params.any(
      (p) => p.format != ScopeValueFormat.text && p.bmkField != null,
    );
    // The bar/table chart toggle is an Incremental-only control.
    final showChartToggle = !isEmpty && hasChartable && !isCumulative;
    // Incremental ⇄ Cumulative is offered wherever real data exists (example /
    // dummy-only sectors keep their original single view).
    final showModeToggle = !isDummy;
    final periods = provider.periodsFor(sectorId);
    final showPicker = !isDummy && !isCumulative && periods.isNotEmpty;
    final nonPool =
        sector.allowedLayers.where((l) => l != SamplingLayer.pool).toList();

    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSizes.spaceMd),
      padding: const EdgeInsets.all(AppSizes.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTitle || isDummy)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showTitle)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 3.5,
                          height: 15,
                          margin: const EdgeInsets.only(top: 1, right: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            sector.title,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const Spacer(),
                if (isDummy) const _ExampleBadge(),
              ],
            ),
          if (showTitle) const SizedBox(height: 4),
          Text(
            sector.note,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
            ),
          ),
          if (showModeToggle || showChartToggle || showPicker) ...[
            const SizedBox(height: AppSizes.spaceSm),
            Row(
              children: [
                if (showModeToggle)
                  ScopeModeToggle(
                    sectorId: sectorId,
                    axis: sector.cumulativeAxis,
                  ),
                const Spacer(),
                if (showChartToggle)
                  _ChartToggle(
                    isChart: isChart,
                    onTap: () => context
                        .read<ScopeComparisonProvider>()
                        .toggleChartMode(sectorId),
                  ),
                if (showPicker)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _PeriodPicker(
                      sectorId: sectorId,
                      axis: sector.cumulativeAxis,
                    ),
                  ),
              ],
            ),
          ],
          // ── content ──
          if (isCumulative && !isDummy)
            ScopeCumulativeView(sectorId: sectorId)
          else if (isEmpty)
            const _EmptyState()
          else if (sector.isSingleScope)
            (isChart && hasChartable)
                ? (sectorId == 'hatch_results'
                      ? const HatchAgeChart()
                      : ScopeChartView(sectorId: sectorId))
                : ScopeTilesGrid(sectorId: sectorId)
          else ...[
            const SizedBox(height: AppSizes.spaceMd),
            const Text(
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
            // Column-pick chips are a table control; in chart mode the scope
            // selector inside ScopeChartView is the filter instead.
            if (!isChart) ColumnPickChips(sectorId: sectorId),
            if (isChart)
              ScopeChartView(sectorId: sectorId)
            else
              ScopeMatrixTable(sectorId: sectorId),
          ],
        ],
      ),
    );
  }
}

/// Period picker — a calendar pill that opens a menu of All + each age/visit.
/// Narrows the Incremental view to the picked period.
class _PeriodPicker extends StatelessWidget {
  final String sectorId;
  final CumulativeAxis axis;

  const _PeriodPicker({required this.sectorId, required this.axis});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScopeComparisonProvider>();
    final periods = provider.periodsFor(sectorId);
    final selected = provider.selectedPeriodFor(sectorId);
    final label = selected?.label ?? 'All';
    final active = selected != null;

    return PopupMenuButton<ScopePeriod?>(
      tooltip: axis == CumulativeAxis.age ? 'Pick age' : 'Pick visit',
      position: PopupMenuPosition.under,
      onSelected: (p) =>
          context.read<ScopeComparisonProvider>().setPeriod(sectorId, p),
      itemBuilder: (context) => [
        PopupMenuItem<ScopePeriod?>(
          value: null,
          child: _menuRow('All', selected == null),
        ),
        for (final p in periods)
          PopupMenuItem<ScopePeriod?>(
            value: p,
            child: _menuRow(p.label, selected?.sameAs(p) ?? false),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.statusActiveBg : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          border: Border.all(
            color:
                active ? AppColors.statusActive.withValues(alpha: 0.3) : AppColors.borderDefault,
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
                color: active ? AppColors.statusActive : AppColors.textSecondary,
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

class _ChartToggle extends StatelessWidget {
  final bool isChart;
  final VoidCallback onTap;

  const _ChartToggle({required this.isChart, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.statusActiveBg,
            borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          ),
          child: Icon(
            isChart ? Icons.table_chart_outlined : Icons.bar_chart,
            size: 18,
            color: AppColors.statusActive,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSizes.spaceMd),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderDefault),
        borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
      ),
      child: const Text(
        'No data for this customer / flock / age yet.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textTertiary,
        ),
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
