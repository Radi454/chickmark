import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../services/govee/govee_service.dart';

class GoveeChartPreview extends StatelessWidget {
  final List<GoveeSensorReading> readings;
  final String? machineId;

  const GoveeChartPreview({super.key, required this.readings, this.machineId});

  @override
  Widget build(BuildContext context) {
    final points = _previewPoints();
    if (points.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Preview charts',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          _PreviewChart(
            key: const ValueKey('govee-temperature-preview-chart'),
            title: 'Temperature preview',
            points: points,
            valueFor: (point) => point.reading.temperatureFahrenheit,
            valueSuffix: ' F',
            color: AppColors.chart1,
          ),
          const SizedBox(height: 16),
          _PreviewChart(
            key: const ValueKey('govee-rh-preview-chart'),
            title: 'Relative Humidity preview',
            points: points,
            valueFor: (point) => point.reading.humidity,
            valueSuffix: '%',
            color: AppColors.chart2,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PreviewPill(label: '${readings.length} live readings'),
              if (machineId != null) _PreviewPill(label: machineId!),
            ],
          ),
        ],
      ),
    );
  }

  List<_PreviewPoint> _previewPoints() {
    final points = <_PreviewPoint>[];
    for (var i = 0; i < readings.length; i += 1) {
      final reading = readings[i];
      if (reading.temperatureFahrenheit == null || reading.humidity == null) {
        continue;
      }
      points.add(_PreviewPoint(x: i, reading: reading, machineId: machineId));
    }
    return points;
  }
}

class _PreviewChart extends StatelessWidget {
  final String title;
  final List<_PreviewPoint> points;
  final double? Function(_PreviewPoint point) valueFor;
  final String valueSuffix;
  final Color color;

  const _PreviewChart({
    super.key,
    required this.title,
    required this.points,
    required this.valueFor,
    required this.valueSuffix,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chartPoints = points
        .where((point) => valueFor(point) != null)
        .map((point) => FlSpot(point.x.toDouble(), valueFor(point)!))
        .toList();
    final yValues = chartPoints.map((spot) => spot.y).toList();
    final minY = yValues.reduce((a, b) => a < b ? a : b) - 1;
    final maxY = yValues.reduce((a, b) => a > b ? a : b) + 1;
    final bottomInterval = (chartPoints.length / 3)
        .ceil()
        .clamp(1, 999)
        .toInt();
    final maxX = chartPoints.last.x == 0 ? 1.0 : chartPoints.last.x;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minX: 0,
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
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if (index < 0 || index >= points.length) {
                        return const SizedBox.shrink();
                      }
                      if (index != 0 &&
                          index != points.length - 1 &&
                          index % bottomInterval != 0) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        _timeLabel(points[index].reading.timestamp),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      );
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
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => AppColors.textPrimary,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final index = spot.x
                          .round()
                          .clamp(0, points.length - 1)
                          .toInt();
                      final point = points[index];
                      final reading = point.reading;
                      final temp = reading.temperatureFahrenheit!
                          .toStringAsFixed(1);
                      final rh = reading.humidity!.toStringAsFixed(1);
                      final details = [
                        _exactTimestamp(reading.timestamp),
                        'Temp $temp F',
                        'RH $rh%',
                        if (point.machineId != null) point.machineId!,
                      ].join('\n');
                      return LineTooltipItem(
                        details,
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    }).toList();
                  },
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

  String _timeLabel(DateTime timestamp) {
    final local = timestamp.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _exactTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
    return '$date $time';
  }
}

class _PreviewPoint {
  final int x;
  final GoveeSensorReading reading;
  final String? machineId;

  const _PreviewPoint({required this.x, required this.reading, this.machineId});
}

class _PreviewPill extends StatelessWidget {
  final String label;

  const _PreviewPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.statusNeutralBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
