import 'package:hatchaudit/localized_material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';

class BmkDonutChart extends StatelessWidget {
  final double actualPct;
  final double bmkPct;

  const BmkDonutChart({
    super.key,
    required this.actualPct,
    required this.bmkPct,
  });

  @override
  Widget build(BuildContext context) {
    final isGood = actualPct >= bmkPct;
    final color = isGood ? AppColors.statusGood : AppColors.statusError;
    final remaining = (100 - actualPct).clamp(0.0, 100.0);

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: [
          PieChartSectionData(
            value: actualPct,
            color: color,
            radius: 30,
            title: '${actualPct.toStringAsFixed(1)}%',
            titleStyle: AppTextStyles.badge,
          ),
          if (remaining > 0)
            PieChartSectionData(
              value: remaining,
              color: AppColors.chartEmptyBorder,
              radius: 25,
              title: '',
            ),
        ],
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }
}
