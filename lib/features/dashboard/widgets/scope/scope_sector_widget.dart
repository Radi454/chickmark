import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../widgets/app_card.dart';
import '../../providers/scope_comparison_provider.dart';
import '../../scope/scope_config.dart';
import 'column_pick_chips.dart';
import 'hatch_age_chart.dart';
import 'layer_toggle_bar.dart';
import 'scope_age_picker.dart';
import 'scope_chart_view.dart';
import 'scope_cumulative_view.dart';
import 'scope_matrix_table.dart';
import 'scope_tiles_grid.dart';
import '../dashboard_quality_strip.dart';

/// One audit sector with an independent BMK-age selector, data-aware hierarchy
/// controls, and a table/chart toggle over the same selected dataset.
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
    final selectedPeriod = provider.selectedPeriodFor(sectorId);
    final isAllAges = selectedPeriod == null;
    // Chart mode is an Act-vs-STD view, so only offer it when the sector has at
    // least one benchmarked numeric param to compare.
    final hasChartable = sector.params.any(
      (p) => p.format != ScopeValueFormat.text && p.bmkField != null,
    );
    // The bar/table chart toggle is an Incremental-only control.
    final showChartToggle = !isEmpty && hasChartable;
    final periods = provider.periodsFor(sectorId);
    final showPicker = !isDummy && periods.isNotEmpty;
    final eligibleLayers = provider.eligibleLayersFor(sectorId);

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
          const SizedBox(height: 6),
          DashboardQualityStrip(sectorId: sectorId),
          const SizedBox(height: 6),
          Text(
            isAllAges
                ? 'Overall: equal-age average · ${sector.params.map((p) => scopeAggregationPolicyLabel(p.aggregationPolicy)).toSet().join(' / ')}'
                : 'Calculation: ${sector.params.map((p) => scopeAggregationPolicyLabel(p.aggregationPolicy)).toSet().join(' / ')}',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
            ),
          ),
          if (showChartToggle || showPicker) ...[
            const SizedBox(height: AppSizes.spaceSm),
            Row(
              children: [
                if (showPicker) ScopeAgePicker(sectorId: sectorId),
                const Spacer(),
                if (showChartToggle)
                  _ChartToggle(
                    isChart: isChart,
                    onTap: () => context
                        .read<ScopeComparisonProvider>()
                        .toggleChartMode(sectorId),
                  ),
              ],
            ),
          ],
          // ── content ──
          if (isEmpty)
            const _EmptyState()
          else if (isAllAges && !isDummy) ...[
            if (eligibleLayers.isNotEmpty) ...[
              const SizedBox(height: AppSizes.spaceMd),
              const Text(
                'Compare performance across BMK ages',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 6),
              LayerToggleBar(sectorId: sectorId, layers: eligibleLayers),
            ],
            ScopeCumulativeView(sectorId: sectorId),
          ] else if (sector.isSingleScope)
            (isChart && hasChartable)
                ? (sectorId == 'hatch_results' && isDummy
                      ? const HatchAgeChart()
                      : ScopeChartView(sectorId: sectorId))
                : ScopeTilesGrid(sectorId: sectorId)
          else ...[
            if (eligibleLayers.isNotEmpty) ...[
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
              LayerToggleBar(sectorId: sectorId, layers: eligibleLayers),
            ],
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

class _ChartToggle extends StatelessWidget {
  final bool isChart;
  final VoidCallback onTap;

  const _ChartToggle({required this.isChart, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = context.tr(isChart ? 'Show table' : 'Show chart');
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(8),
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
