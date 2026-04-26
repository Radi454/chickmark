import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';

class BmkLineChart extends StatelessWidget {
  final List<FlSpot> dataPoints;
  final double bmkValue;
  final String yLabel;

  const BmkLineChart({
    super.key,
    required this.dataPoints,
    required this.bmkValue,
    required this.yLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (dataPoints.isEmpty) {
      return const Center(child: Text('No data'));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _calculateInterval(),
          getDrawingHorizontalLine: (line) =>
              const FlLine(color: AppColors.chartGridH, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}',
                style: AppTextStyles.caption,
              ),
            ),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: dataPoints,
            isCurved: true,
            color: AppColors.primary,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primary.withAlpha(50),
            ),
          ),
        ],
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: bmkValue,
              color: AppColors.statusNeutralText,
              strokeWidth: 2,
              dashArray: [5, 5],
            ),
          ],
        ),
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  double _calculateInterval() {
    if (dataPoints.isEmpty) return 10;
    final max = dataPoints.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final min = dataPoints.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final range = max - min;
    if (range <= 0) return 10;
    if (range < 20) return 5;
    if (range < 50) return 10;
    return 20;
  }
}
