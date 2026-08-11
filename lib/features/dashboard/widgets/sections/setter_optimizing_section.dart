import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_thresholds.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/dashboard/widgets/bmk_bar_chart.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/section_shared.dart';

class SetterOptimizingSection extends StatelessWidget {
  const SetterOptimizingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        final hasData = provider.setterComparisons.isNotEmpty;
        return Card(
          child: ExpansionTile(
            title: const Text('Setters'),
            initiallyExpanded: true,
            children: [
              if (provider.availableSetterIds.isEmpty)
                emptySection('setter optimizing')
              else ...[
                _buildCheckboxes(context, provider),
                if (hasData) ...[
                  _buildComparisonTable(context, provider),
                  _buildTurningAngleRow(context, provider),
                  const Divider(),
                  _buildEstChart(context, provider),
                  const Divider(),
                  _buildCo2Chart(context, provider),
                ] else
                  emptySection('setter optimizing'),
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
        children: provider.availableSetterIds.map((id) {
          final selected = provider.selectedSetterIds.contains(id);
          return FilterChip(
            label: Text('Setter $id'),
            selected: selected,
            onSelected: (_) => provider.toggleSetter(id),
            selectedColor: AppColors.primary.withAlpha(60),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTurningAngleRow(
    BuildContext context,
    DashboardProvider provider,
  ) {
    final comparisons = provider.setterComparisons;
    final hasTurning = comparisons.any((c) => c.turningAngle > 0);
    if (!hasTurning) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Text('Turning Angle', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          ...comparisons
              .where((c) => c.turningAngle > 0)
              .map(
                (c) => metricRow(
                  'Setter ${c.setterId}',
                  '${c.turningAngle.toStringAsFixed(1)}°',
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildComparisonTable(
    BuildContext context,
    DashboardProvider provider,
  ) {
    final comparisons = provider.setterComparisons;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DataTable(
        columnSpacing: 16,
        columns: [
          const DataColumn(label: Text('Setter')),
          const DataColumn(label: Text('Hatch%')),
          const DataColumn(label: Text('Fert%')),
          const DataColumn(label: Text('HOF%')),
          const DataColumn(label: Text('EST')),
          const DataColumn(label: Text('EST CV%')),
        ],
        rows: comparisons
            .map(
              (c) => DataRow(
                cells: [
                  DataCell(Text(c.setterId)),
                  DataCell(Text(c.hatchabilityPct.toStringAsFixed(1))),
                  DataCell(Text(c.fertilityPct.toStringAsFixed(1))),
                  DataCell(Text(c.hofPct.toStringAsFixed(1))),
                  DataCell(
                    Text('${c.estAvgF.toStringAsFixed(1)}${c.estUnit.suffix}'),
                  ),
                  DataCell(Text(c.estCvPct.toStringAsFixed(1))),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildEstChart(BuildContext context, DashboardProvider provider) {
    final comparisons = provider.setterComparisons;
    if (comparisons.isEmpty) return const SizedBox.shrink();

    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        'EST Comparison',
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );

    final groups = comparisons
        .asMap()
        .entries
        .map((e) => BmkBarChart.createGroup(e.key, e.value.estAvgF))
        .toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EST (°F)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Target: ${AppThresholds.estMin.toStringAsFixed(0)}-${AppThresholds.estMax.toStringAsFixed(0)}°F',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: BmkBarChart(
              barGroups: groups,
              bmkValue: (AppThresholds.estMin + AppThresholds.estMax) / 2,
              xLabel: '',
              xLabels: comparisons.map((c) => 'S${c.setterId}').toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCo2Chart(BuildContext context, DashboardProvider provider) {
    final comparisons = provider.setterComparisons;
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
                    'Setter ${e.value.setterId}',
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
