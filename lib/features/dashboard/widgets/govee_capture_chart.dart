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
    final points = summary.combinedPoints;
    final machineLabel = summary.capture.machineId;
    final startedAt = summary.recordingStartedAt;
    final endedAt = summary.recordingEndedAt;

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
                    if (machineLabel != null) ...[
                      const SizedBox(height: AppSizes.spaceXs),
                      Text(machineLabel, style: AppTextStyles.caption),
                    ],
                    const SizedBox(height: AppSizes.spaceXs),
                    Text(
                      summary.capture.captureDate,
                      style: AppTextStyles.caption,
                    ),
                    if (startedAt != null && endedAt != null) ...[
                      const SizedBox(height: AppSizes.spaceXs),
                      Text(
                        '${_formatClock(startedAt)} - ${_formatClock(endedAt)}',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ],
                ),
              ),
              _metricPill('${summary.capture.readingCount} readings'),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Wrap(
            spacing: AppSizes.spaceSm,
            runSpacing: AppSizes.spaceXs,
            children: [
              _metricPill(
                _rangeMetric(
                  label: 'Temp',
                  unit: 'F',
                  avg: summary.capture.tempAvg,
                  min: summary.capture.tempMin,
                  max: summary.capture.tempMax,
                  sd: summary.capture.tempSd,
                  cvPct: summary.capture.tempCvPct,
                ),
              ),
              _metricPill(
                _rangeMetric(
                  label: 'RH',
                  unit: '%',
                  avg: summary.capture.rhAvg,
                  min: summary.capture.rhMin,
                  max: summary.capture.rhMax,
                  sd: summary.capture.rhSd,
                  cvPct: summary.capture.rhCvPct,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceMd),
          if (points.isEmpty)
            const SizedBox(
              height: 180,
              child: Center(child: Text('No readings saved')),
            )
          else ...[
            _MetricLineChart(
              chartKey: ValueKey(
                'govee-temperature-chart-${summary.capture.id}',
              ),
              title: 'Temperature',
              unit: 'F',
              color: AppColors.chart1,
              summary: summary,
              valueFor: (point) => point.temperatureFahrenheit,
            ),
            const SizedBox(height: AppSizes.spaceMd),
            _MetricLineChart(
              chartKey: ValueKey('govee-rh-chart-${summary.capture.id}'),
              title: 'Relative Humidity',
              unit: '%',
              color: AppColors.chart2,
              summary: summary,
              valueFor: (point) => point.humidity,
            ),
          ],
        ],
      ),
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

class _MetricLineChart extends StatelessWidget {
  final Key chartKey;
  final String title;
  final String unit;
  final Color color;
  final GoveeCaptureSummary summary;
  final double Function(GoveeChartPoint point) valueFor;

  const _MetricLineChart({
    required this.chartKey,
    required this.title,
    required this.unit,
    required this.color,
    required this.summary,
    required this.valueFor,
  });

  @override
  Widget build(BuildContext context) {
    final points = summary.combinedPoints;
    final chartPoints = points
        .map((point) => FlSpot(point.x, valueFor(point)))
        .toList(growable: false);
    final yValues = chartPoints.map((spot) => spot.y).toList();
    var minY = yValues.reduce((a, b) => a < b ? a : b) - 1;
    var maxY = yValues.reduce((a, b) => a > b ? a : b) + 1;
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }
    final minX = chartPoints.first.x;
    final maxX = chartPoints.last.x == minX ? minX + 1 : chartPoints.last.x;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.subtitle),
        const SizedBox(height: AppSizes.spaceXs),
        SizedBox(
          height: 165,
          child: LineChart(
            key: chartKey,
            LineChartData(
              minX: minX,
              maxX: maxX,
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
                    reservedSize: 38,
                    getTitlesWidget: (value, meta) => Text(
                      value.toStringAsFixed(0),
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
              lineTouchData: LineTouchData(
                enabled: true,
                handleBuiltInTouches: true,
                touchTooltipData: LineTouchTooltipData(
                  maxContentWidth: 260,
                  getTooltipItems: (touchedSpots) => touchedSpots
                      .map((spot) => _tooltipForPoint(spot))
                      .toList(growable: false),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: chartPoints,
                  isCurved: true,
                  color: color,
                  barWidth: 3,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: color.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          ),
        ),
      ],
    );
  }

  LineTooltipItem _tooltipForPoint(LineBarSpot spot) {
    final point = _nearestPoint(spot.x);
    final machineLabel = summary.capture.machineId;
    final lines = [
      _formatTimestamp(point.recordedAt),
      'Temp ${point.temperatureFahrenheit.toStringAsFixed(1)}F',
      'RH ${point.humidity.toStringAsFixed(1)}%',
      summary.capture.place.label,
      ?machineLabel,
    ];

    return LineTooltipItem(
      lines.join('\n'),
      const TextStyle(
        color: AppColors.textOnPrimary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
    );
  }

  GoveeChartPoint _nearestPoint(double x) {
    final points = summary.combinedPoints;
    var closest = points.first;
    var closestDistance = (closest.x - x).abs();
    for (final point in points.skip(1)) {
      final distance = (point.x - x).abs();
      if (distance < closestDistance) {
        closest = point;
        closestDistance = distance;
      }
    }
    return closest;
  }
}

String _rangeMetric({
  required String label,
  required String unit,
  required double? avg,
  required double? min,
  required double? max,
  required double? sd,
  required double? cvPct,
}) {
  return '$label avg ${_formatMetric(avg)}$unit / min ${_formatMetric(min)}$unit / max ${_formatMetric(max)}$unit / SD ${_formatMetric(sd)} / CV ${_formatMetric(cvPct)}%';
}

String _formatMetric(double? value) {
  if (value == null) return '--';
  return value.toStringAsFixed(1);
}

String _formatClock(DateTime dateTime) {
  final hour = dateTime.hour;
  final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final suffix = hour >= 12 ? 'PM' : 'AM';
  return '$displayHour:$minute $suffix';
}

String _formatTimestamp(DateTime dateTime) {
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final second = dateTime.second.toString().padLeft(2, '0');
  return '${dateTime.year}-$month-$day $hour:$minute:$second';
}
