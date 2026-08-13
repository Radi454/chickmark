import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_thresholds.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/dashboard/widgets/bmk_bar_chart.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/section_shared.dart';

class HatcherOptimizingSection extends StatelessWidget {
  const HatcherOptimizingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        final hasData = provider.hatcherComparisons.isNotEmpty;
        return Card(
          child: ExpansionTile(
            title: const Text('Hatchers'),
            initiallyExpanded: true,
            children: [
              if (provider.availableHatcherIds.isEmpty)
                emptySection('hatcher optimizing')
              else ...[
                _buildCheckboxes(context, provider),
                if (hasData) ...[
                  _buildComparisonTable(context, provider),
                  const Divider(),
                  _buildCvtChart(context, provider),
                  const Divider(),
                  _buildCo2Chart(context, provider),
                  const Divider(),
                  _buildPantingChart(context, provider),
                ] else
                  emptySection('hatcher optimizing'),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCheckboxes(BuildContext context, DashboardProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: provider.availableHatcherIds.map((id) {
          final selected = provider.selectedHatcherIds.contains(id);
          return FilterChip(
            label: Text('Hatcher $id'),
            selected: selected,
            onSelected: (_) => provider.toggleHatcher(id),
            selectedColor: AppColors.primary.withAlpha(60),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildComparisonTable(
    BuildContext context,
    DashboardProvider provider,
  ) {
    final comparisons = provider.hatcherComparisons;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DataTable(
        columnSpacing: 16,
        columns: const [
          DataColumn(label: Text('Hatcher')),
          DataColumn(label: Text('Hatch%')),
          DataColumn(label: Text('HOF%')),
          DataColumn(label: Text('Culled%')),
          DataColumn(label: Text('CVT')),
          DataColumn(label: Text('CVT CV%')),
          DataColumn(label: Text('Meconium')),
          DataColumn(label: Text('Trans. Day')),
        ],
        rows: comparisons
            .map(
              (c) => DataRow(
                cells: [
                  DataCell(Text(c.hatcherId)),
                  DataCell(Text(c.hatchabilityPct.toStringAsFixed(1))),
                  DataCell(Text(c.hofPct.toStringAsFixed(1))),
                  DataCell(Text(c.culledPct.toStringAsFixed(1))),
                  DataCell(
                    Text('${c.cvtAvgF.toStringAsFixed(1)}${c.cvtUnit.suffix}'),
                  ),
                  DataCell(Text(c.cvtCvPct.toStringAsFixed(1))),
                  DataCell(Text(c.meconium ?? '--')),
                  DataCell(Text(c.transferDay?.toString() ?? '--')),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildCvtChart(BuildContext context, DashboardProvider provider) {
    final comparisons = provider.hatcherComparisons;
    final colors = [
      AppColors.primary,
      AppColors.statusError,
      AppColors.statusGood,
      AppColors.primaryLight,
    ];

    final groups = comparisons
        .asMap()
        .entries
        .map((e) => BmkBarChart.createGroup(e.key, e.value.cvtAvgF))
        .toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CVT Avg (°F)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Target: ${AppThresholds.cvtMin.toStringAsFixed(0)}-${AppThresholds.cvtMax.toStringAsFixed(0)}°F',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: BmkBarChart(
              barGroups: groups,
              bmkValue: (AppThresholds.cvtMin + AppThresholds.cvtMax) / 2,
              xLabel: '',
              xLabels: comparisons.map((c) => 'H${c.hatcherId}').toList(),
            ),
          ),
          _buildLegend(
            comparisons
                .asMap()
                .entries
                .map(
                  (e) => MapEntry(
                    'Hatcher ${e.value.hatcherId}',
                    colors[e.key % colors.length],
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCo2Chart(BuildContext context, DashboardProvider provider) {
    final comparisons = provider.hatcherComparisons;
    final colors = [
      AppColors.primary,
      AppColors.statusError,
      AppColors.statusGood,
      AppColors.primaryLight,
    ];

    final lineBars = comparisons.asMap().entries.map((entry) {
      final c = entry.value;
      final color = colors[entry.key % colors.length];
      final spots = c.co2Trend.entries
          .toList()
          .asMap()
          .entries
          .map((e) => FlSpot(e.key.toDouble(), e.value.value))
          .toList();
      return LineChartBarData(
        spots: spots.isEmpty ? [const FlSpot(0, 0)] : spots,
        color: color,
        barWidth: 2,
        isCurved: true,
        dotData: const FlDotData(show: false),
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CO₂ Trend (ppm)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: lineBars.isEmpty
                ? const Center(child: Text('No CO₂ data'))
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (v) => const FlLine(
                          color: AppColors.chartGridH,
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: const FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: lineBars,
                    ),
                  ),
          ),
          _buildLegend(
            comparisons
                .asMap()
                .entries
                .map(
                  (e) => MapEntry(
                    'Hatcher ${e.value.hatcherId}',
                    colors[e.key % colors.length],
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPantingChart(BuildContext context, DashboardProvider provider) {
    final comparisons = provider.hatcherComparisons;
    final colors = [
      AppColors.primary,
      AppColors.statusError,
      AppColors.statusGood,
      AppColors.primaryLight,
    ];

    final lineBars = comparisons.asMap().entries.map((entry) {
      final c = entry.value;
      final color = colors[entry.key % colors.length];
      final spots = c.pantingTrend.entries
          .toList()
          .asMap()
          .entries
          .map((e) => FlSpot(e.key.toDouble(), e.value.value))
          .toList();
      return LineChartBarData(
        spots: spots.isEmpty ? [const FlSpot(0, 0)] : spots,
        color: color,
        barWidth: 2,
        isCurved: true,
        dotData: const FlDotData(show: false),
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chick Panting Trend',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: lineBars.isEmpty
                ? const Center(child: Text('No panting data'))
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (v) => const FlLine(
                          color: AppColors.chartGridH,
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: const FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: lineBars,
                      extraLinesData: ExtraLinesData(
                        horizontalLines: [
                          HorizontalLine(
                            y: 20,
                            color: Colors.orange,
                            strokeWidth: 1,
                            dashArray: [5, 5],
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          _buildLegend(
            comparisons
                .asMap()
                .entries
                .map(
                  (e) => MapEntry(
                    'Hatcher ${e.value.hatcherId}',
                    colors[e.key % colors.length],
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(List<MapEntry<String, Color>> items) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 12,
        children: items
            .map(
              (e) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 12, height: 3, color: e.value),
                  const SizedBox(width: 4),
                  Text(e.key, style: const TextStyle(fontSize: 12)),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}
