import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../models/hatch_analysis_models.dart';
import '../../providers/scope_comparison_provider.dart';
import '../../scope/scope_severity.dart';
import 'scope_severity_style.dart';

/// Hatch Result chart mode: one Act-vs-BMK bar chart per metric (Hatchability,
/// Fertility, HOF). X = benchmark age (weeks), Y = value %; each age carries two
/// bars — the flock's actual (severity-colored) and the benchmark (slate).
class HatchAgeChart extends StatelessWidget {
  const HatchAgeChart({super.key});

  @override
  Widget build(BuildContext context) {
    final series = context.watch<ScopeComparisonProvider>().hatchAgeSeries;
    if (series.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSizes.spaceMd),
        child: Text(
          'No age data to chart yet.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textTertiary,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSizes.spaceMd),
        const _Legend(),
        _MetricChart(
          title: 'Hatchability %',
          series: series,
          actOf: (p) => p.hatchAct,
          bmkOf: (p) => p.hatchBmk,
        ),
        _MetricChart(
          title: 'Fertility %',
          series: series,
          actOf: (p) => p.fertAct,
          bmkOf: (p) => p.fertBmk,
        ),
        _MetricChart(
          title: 'HOF %',
          series: series,
          actOf: (p) => p.hofAct,
          bmkOf: (p) => p.hofBmk,
        ),
      ],
    );
  }
}

class _MetricChart extends StatelessWidget {
  final String title;
  final List<HatchAgePoint> series;
  final double? Function(HatchAgePoint) actOf;
  final double? Function(HatchAgePoint) bmkOf;

  const _MetricChart({
    required this.title,
    required this.series,
    required this.actOf,
    required this.bmkOf,
  });

  @override
  Widget build(BuildContext context) {
    final acts = [for (final p in series) actOf(p) ?? 0.0];
    final bmks = [for (final p in series) bmkOf(p)];
    final maxV = [...acts, ...bmks.whereType<double>()].fold<double>(0, math.max);
    final maxY = maxV <= 0 ? 1.0 : maxV * 1.18 + 0.01;
    final step = _niceStep(maxY);

    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              const perGroup = 64.0;
              final chartW = math.max(
                constraints.maxWidth,
                series.length * perGroup,
              );
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: chartW,
                  height: 190,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxY,
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => Colors.transparent,
                          tooltipPadding: EdgeInsets.zero,
                          tooltipMargin: 4,
                          fitInsideVertically: true,
                          fitInsideHorizontally: true,
                          getTooltipItem: (group, _, rod, rodIndex) {
                            if (rod.toY == 0) return null;
                            final isAct = rodIndex == 0;
                            return BarTooltipItem(
                              '${rod.toY.toStringAsFixed(1)}%',
                              TextStyle(
                                color: isAct
                                    ? (rod.color ?? AppColors.textPrimary)
                                    : AppColors.textTertiary,
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
                            reservedSize: 32,
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
                            reservedSize: 28,
                            getTitlesWidget: (v, meta) {
                              final i = v.toInt();
                              if (i < 0 || i >= series.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '${series[i].age}w',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < series.length; i++)
                          BarChartGroupData(
                            x: i,
                            barsSpace: 4,
                            showingTooltipIndicators: const [0],
                            barRods: [
                              BarChartRodData(
                                toY: acts[i],
                                width: 14,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                                color: _actColor(acts[i], bmks[i]),
                              ),
                              if (bmks[i] != null)
                                BarChartRodData(
                                  toY: bmks[i]!,
                                  width: 14,
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
      ),
    );
  }

  /// Higher-is-better severity: green when Act ≥ BMK, warn/err as it falls below.
  Color _actColor(double act, double? bmk) {
    final severity = severityFor(
      value: act,
      bmk: bmk,
      higherIsBetter: true,
      thresholds: const SeverityThresholds(),
    );
    return ScopeSeverityStyle.dotColor(severity);
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

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        children: [
          _LegendItem(color: AppColors.statusGood, label: 'On target'),
          _LegendItem(color: AppColors.statusWarning, label: 'Watch'),
          _LegendItem(color: AppColors.statusError, label: 'Below'),
          _LegendItem(color: AppColors.chartBenchmark, label: 'BMK', bar: true),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool bar;

  const _LegendItem({required this.color, required this.label, this.bar = false});

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
