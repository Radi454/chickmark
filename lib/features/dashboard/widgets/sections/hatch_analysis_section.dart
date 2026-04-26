import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/widgets/chart_toggle.dart';
import 'package:hatchaudit/widgets/app_card.dart';
import 'package:hatchaudit/features/dashboard/widgets/bmk_bar_chart.dart';
import 'package:hatchaudit/features/dashboard/widgets/bmk_donut_chart.dart';
import 'package:hatchaudit/features/dashboard/widgets/bmk_line_chart.dart';

class HatchAnalysisSection extends StatefulWidget {
  const HatchAnalysisSection({super.key});

  @override
  State<HatchAnalysisSection> createState() => _HatchAnalysisSectionState();
}

class _HatchAnalysisSectionState extends State<HatchAnalysisSection> {
  ChartType _chartType = ChartType.bar;

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, child) {
        final avg = provider.hatchAnalysisAvg;
        final bmk = provider.bmkReference;

        return AppCard(
          margin: EdgeInsets.zero,
          padding: EdgeInsets.zero,
          child: ExpansionTile(
            title: const Text(
              'Hatch Analysis',
              style: AppTextStyles.sectionTitle,
            ),
            initiallyExpanded: true,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: AppSizes.spaceLg,
              vertical: AppSizes.spaceSm,
            ),
            children: [
              if (provider.isLoading)
                const Padding(
                  padding: EdgeInsets.all(AppSizes.spaceLg),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (avg == null)
                const Padding(
                  padding: EdgeInsets.all(AppSizes.spaceLg),
                  child: Text('No data', style: AppTextStyles.caption),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.all(AppSizes.spaceSm),
                  child: ChartToggle(
                    selected: _chartType,
                    onChanged: (t) => setState(() => _chartType = t),
                  ),
                ),
                _buildMetrics(avg, bmk),
                const SizedBox(height: AppSizes.spaceLg),
                SizedBox(
                  height: 200,
                  child: _buildChart(avg, bmk, provider.hatchAnalysisTrend),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetrics(dynamic avg, dynamic bmk) {
    return Column(
      children: [
        _metricRow(
          'Hatchability',
          avg.hatchabilityPct,
          bmk?.hatchabilityPct ?? 0,
        ),
        _metricRow('Fertility', avg.fertilityPct, bmk?.fertilityPct ?? 0),
        _metricRow('HOF', avg.hofPct, bmk?.hofPct ?? 0),
        _metricRow('Culled', avg.culledPct, bmk?.cullPct ?? 0),
        _metricRow('Dead', avg.deadPct, 0),
      ],
    );
  }

  Widget _metricRow(String label, double value, double bmk) {
    final isGood = value >= bmk;
    final color = bmk > 0
        ? (isGood ? AppColors.statusGood : AppColors.statusError)
        : AppColors.statusNeutralText;
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSizes.spaceXs,
        horizontal: AppSizes.spaceLg,
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTextStyles.body)),
          Text(
            '${value.toStringAsFixed(1)}%',
            style: AppTextStyles.badgeLabel,
          ),
          const SizedBox(width: AppSizes.spaceSm),
          Container(
            width: AppSizes.spaceMd,
            height: AppSizes.spaceMd,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(dynamic avg, dynamic bmk, dynamic trend) {
    if (_chartType == ChartType.bar) {
      return BmkBarChart(
        barGroups: [
          BmkBarChart.createGroup(0, avg.hatchabilityPct),
          BmkBarChart.createGroup(1, avg.fertilityPct),
          BmkBarChart.createGroup(2, avg.hofPct),
        ],
        bmkValue: bmk?.hatchabilityPct ?? 0,
        xLabel: '',
        xLabels: const ['Hatch', 'Fert', 'HOF'],
      );
    }
    if (_chartType == ChartType.donut) {
      return Center(
        child: BmkDonutChart(
          actualPct: avg.hatchabilityPct,
          bmkPct: bmk?.hatchabilityPct ?? 0,
        ),
      );
    }
    final points = trend
        .asMap()
        .entries
        .map(
          (entry) => FlSpot(entry.key.toDouble(), entry.value.hatchabilityPct),
        )
        .toList();
    return BmkLineChart(
      dataPoints: points.isEmpty ? [FlSpot(0, avg.hatchabilityPct)] : points,
      bmkValue: bmk?.hatchabilityPct ?? 0,
      yLabel: '%',
    );
  }
}
