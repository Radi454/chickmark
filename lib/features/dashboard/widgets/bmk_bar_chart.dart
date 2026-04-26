import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';

class BmkBarChart extends StatelessWidget {
  final List<BarChartGroupData> barGroups;
  final double bmkValue;
  final String xLabel;
  final List<String> xLabels;

  const BmkBarChart({
    super.key,
    required this.barGroups,
    required this.bmkValue,
    required this.xLabel,
    this.xLabels = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (barGroups.isEmpty) {
      return const Center(child: Text('No data'));
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 10,
          getDrawingHorizontalLine: (line) =>
              const FlLine(
                color: AppColors.chartGridH,
                strokeWidth: 1,
              ),
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
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx >= 0 && idx < xLabels.length) {
                  return Text(
                    xLabels[idx],
                    style: AppTextStyles.caption,
                  );
                }
                return const Text('');
              },
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: barGroups,
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

  static BarChartGroupData createGroup(int x, double value, {String? label}) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: value,
          color: AppColors.primary,
          width: 20,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(4),
          ),
        ),
      ],
    );
  }
}
