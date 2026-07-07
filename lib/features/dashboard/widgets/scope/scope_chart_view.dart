import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../providers/scope_comparison_provider.dart';
import '../../scope/scope_config.dart';
import '../../scope/scope_severity.dart';
import 'scope_severity_style.dart';

/// Chart view for a sector: pick a scope (column) → one Act-vs-STD bar pair per
/// breakout item (parameter). Act bars are colored by severity; STD bars are a
/// soft slate benchmark. Each Act bar carries an always-on value label, so the
/// numbers read without tapping. Bars scroll horizontally to stay mobile-friendly.
class ScopeChartView extends StatelessWidget {
  final String sectorId;

  const ScopeChartView({super.key, required this.sectorId});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScopeComparisonProvider>();
    final sector = ScopeConfigRegistry.byId(sectorId);
    final groups = provider.groupsFor(sectorId);
    final visibleIdx = provider.visibleColumnIndexes(sectorId);

    // Breakout items: numeric params that have a benchmark, so every bar is a
    // true Act-vs-STD pair (counts/denominators without a STD are excluded so
    // they can't dominate the shared axis). Fertility is a "good" metric, not a
    // breakout defect, so it's left off the breakout charts.
    final chartParams = <int>[
      for (var i = 0; i < sector.params.length; i++)
        if (sector.params[i].format != ScopeValueFormat.text &&
            sector.params[i].bmkField != null &&
            sector.params[i].bmkField != 'fertilityPct')
          i,
    ];
    if (chartParams.isEmpty || visibleIdx.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSizes.spaceMd),
        child: Text(
          'Nothing to chart for this selection.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textTertiary,
          ),
        ),
      );
    }

    // Selected scope (group) — clamp to a currently-visible column.
    var scopeIdx = provider.chartScopeIndex(sectorId);
    if (!visibleIdx.contains(scopeIdx)) scopeIdx = visibleIdx.first;
    final group = groups[scopeIdx];
    final bmk = provider.bmkFor(sectorId);

    // Act (selected scope) vs STD (benchmark) per breakout item.
    final acts = [
      for (final p in chartParams) (group.cells[p].value ?? 0).toDouble()
    ];
    final stds = [
      for (final p in chartParams)
        bmkLookup(bmk, sector.params[p].bmkField)?.toDouble()
    ];
    final maxAct = acts.isEmpty ? 0.0 : acts.reduce(math.max);
    final maxStd = stds.whereType<double>().fold<double>(0, math.max);
    // 1.18 headroom leaves room for the value labels that float above each bar.
    final maxY = math.max(maxAct, maxStd) * 1.18 + 0.01;
    final step = _niceStep(maxY);

    String fmt(double v, int paramIdx) =>
        '${v.toStringAsFixed(1)}'
        '${sector.params[paramIdx].format == ScopeValueFormat.percent ? '%' : ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSizes.spaceMd),
        // Scope selector (the filter buttons are now scopes/columns).
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: visibleIdx.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final gi = visibleIdx[i];
              final active = gi == scopeIdx;
              return GestureDetector(
                onTap: () => context
                    .read<ScopeComparisonProvider>()
                    .setChartScope(sectorId, gi),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.statusActive
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                    border: Border.all(
                      color: active
                          ? AppColors.statusActive
                          : AppColors.borderDefault,
                    ),
                  ),
                  child: Text(
                    groups[gi].label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSizes.spaceMd),
        // Legend — the Act bars are severity-colored, so the key doubles as the
        // severity scale; the slate swatch is the STD benchmark.
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _LegendItem(color: AppColors.statusGood, label: 'On target'),
              _LegendItem(color: AppColors.statusWarning, label: 'Watch'),
              _LegendItem(color: AppColors.statusError, label: 'Over'),
              _LegendItem(
                color: AppColors.chartBenchmark,
                label: 'STD',
                bar: true,
              ),
            ],
          ),
        ),
        // Chart (horizontally scrollable when many breakout items).
        LayoutBuilder(
          builder: (context, constraints) {
            const perGroup = 60.0;
            final chartW =
                math.max(constraints.maxWidth, chartParams.length * perGroup);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: chartW,
                height: 232,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: maxY,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        // Transparent box turns the tooltip into a floating
                        // value label rather than a heavy popup.
                        getTooltipColor: (_) => Colors.transparent,
                        tooltipPadding: EdgeInsets.zero,
                        tooltipMargin: 4,
                        fitInsideVertically: true,
                        fitInsideHorizontally: true,
                        getTooltipItem: (g, _, rod, rodIndex) {
                          if (rod.toY == 0) return null;
                          final pIdx = chartParams[g.x];
                          final isAct = rodIndex == 0;
                          final color = isAct
                              ? ScopeSeverityStyle.dotColor(
                                  group.cells[pIdx].severity)
                              : AppColors.textTertiary;
                          return BarTooltipItem(
                            fmt(rod.toY, pIdx),
                            TextStyle(
                              color: color,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                            ),
                          );
                        },
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: step,
                      getDrawingHorizontalLine: (_) => const FlLine(
                        color: AppColors.chartGridH,
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: step,
                          reservedSize: 30,
                          getTitlesWidget: (v, meta) {
                            if (v > maxY - step * 0.5) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              step >= 1
                                  ? v.toStringAsFixed(0)
                                  : v.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textTertiary,
                              ),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 1,
                          reservedSize: 46,
                          getTitlesWidget: (v, meta) {
                            final i = v.toInt();
                            if (i < 0 || i >= chartParams.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Transform.rotate(
                                angle: -0.45,
                                child: Text(
                                  sector.params[chartParams[i]].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: [
                      for (var i = 0; i < chartParams.length; i++)
                        BarChartGroupData(
                          x: i,
                          barsSpace: 4,
                          // Always-on label over the Act bar (rod 0).
                          showingTooltipIndicators: const [0],
                          barRods: [
                            BarChartRodData(
                              toY: acts[i],
                              width: 15,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                              color: ScopeSeverityStyle.dotColor(
                                group.cells[chartParams[i]].severity,
                              ),
                            ),
                            if (stds[i] != null)
                              BarChartRodData(
                                toY: stds[i]!,
                                width: 15,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                                color: AppColors.chartBenchmark,
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// A "nice" axis step (1/2/5 × 10ⁿ) giving ~4 gridlines up to [max].
double _niceStep(double max) {
  if (max <= 0) return 1;
  final raw = max / 4;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final norm = raw / mag;
  final step = norm < 1.5
      ? 1.0
      : norm < 3
          ? 2.0
          : norm < 7
              ? 5.0
              : 10.0;
  return step * mag;
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  /// Render a rounded bar swatch (STD) instead of a severity dot.
  final bool bar;

  const _LegendItem({
    required this.color,
    required this.label,
    this.bar = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: bar ? 14 : 10,
          height: bar ? 9 : 10,
          decoration: BoxDecoration(
            color: color,
            shape: bar ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: bar ? BorderRadius.circular(2) : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
