import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

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
    final color = isGood ? const Color(0xFF3a9a5c) : const Color(0xFFE24B4A);
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
            titleStyle: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (remaining > 0)
            PieChartSectionData(
              value: remaining,
              color: Colors.grey.shade200,
              radius: 25,
              title: '',
            ),
        ],
      ),
    );
  }
}
