import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/features/dashboard/models/govee_capture_summary.dart';

class GoveeCaptureChart extends StatelessWidget {
  final GoveeCaptureSummary summary;

  const GoveeCaptureChart({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final points = summary.combinedTempPoints;
    final spots = summary.sortedSpots;

    return Container(
      padding: const EdgeInsets.all(AppSizes.spaceMd),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.capture.place.label,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSizes.spaceXs),
                    Text(
                      summary.capture.captureDate,
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              _metricPill('${summary.capture.spotCount} spots'),
              const SizedBox(width: AppSizes.spaceXs),
              _metricPill('${summary.capture.readingCount} readings'),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Wrap(
            spacing: AppSizes.spaceSm,
            runSpacing: AppSizes.spaceXs,
            children: [
              if (summary.capture.tempAvg != null)
                _metricPill(
                  '${summary.capture.tempAvg!.toStringAsFixed(1)} F avg',
                ),
              if (summary.capture.rhAvg != null)
                _metricPill('${summary.capture.rhAvg!.toStringAsFixed(1)}% RH'),
              for (final spot in spots) _metricPill(spot.spotLabel),
            ],
          ),
          const SizedBox(height: AppSizes.spaceMd),
          if (points.isEmpty)
            const SizedBox(
              height: 180,
              child: Center(child: Text('No readings saved')),
            )
          else
            SizedBox(
              height: 190,
              child: Column(
                children: [
                  Expanded(child: _lineChart(points)),
                  const SizedBox(height: AppSizes.spaceXs),
                  Row(
                    children: spots
                        .map(
                          (spot) => Expanded(
                            child: Text(
                              spot.spotLabel,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.caption,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _lineChart(List<GoveeChartPoint> points) {
    final chartPoints = points
        .map((point) => FlSpot(point.x.toDouble(), point.temperatureFahrenheit))
        .toList();
    final yValues = chartPoints.map((spot) => spot.y).toList();
    final minY = yValues.reduce((a, b) => a < b ? a : b) - 1;
    final maxY = yValues.reduce((a, b) => a > b ? a : b) + 1;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: chartPoints.last.x,
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.chartGridH, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) =>
                  Text(value.toStringAsFixed(0), style: AppTextStyles.caption),
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
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: chartPoints,
            isCurved: true,
            color: AppColors.chart1,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.chart1.withValues(alpha: 0.12),
            ),
          ),
        ],
        extraLinesData: ExtraLinesData(
          verticalLines: summary.spotBoundaryIndexes
              .map(
                (boundary) => VerticalLine(
                  x: boundary.toDouble(),
                  color: AppColors.statusNeutralText.withValues(alpha: 0.42),
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
              )
              .toList(),
        ),
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _metricPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceSm,
        vertical: AppSizes.spaceXs,
      ),
      decoration: BoxDecoration(
        color: AppColors.statusNeutralBg,
        borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
