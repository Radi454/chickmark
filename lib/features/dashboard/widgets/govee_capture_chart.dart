import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/data/models/govee_capture_model.dart';
import 'package:hatchaudit/features/dashboard/models/govee_capture_summary.dart';

class GoveeCaptureChart extends StatelessWidget {
  final GoveeCaptureSummary summary;

  const GoveeCaptureChart({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final points = summary.combinedPoints;
    final capture = summary.capture;
    final machineLabel = capture.machineId;
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      capture.place.label,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (machineLabel != null) ...[
                      const SizedBox(height: AppSizes.spaceXs),
                      Text(machineLabel, style: AppTextStyles.caption),
                    ],
                    const SizedBox(height: AppSizes.spaceXs),
                    Text(capture.captureDate, style: AppTextStyles.caption),
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
              _Badge('${capture.readingCount} readings'),
            ],
          ),
          const SizedBox(height: AppSizes.spaceMd),
          Row(
            children: [
              Expanded(
                child: _MetricSummaryTile(
                  label: 'Temp',
                  average: '${_formatMetric(capture.tempAvg)}F avg',
                  range:
                      '${_formatMetric(capture.tempMin)} - ${_formatMetric(capture.tempMax)}F',
                  variability:
                      'SD ${_formatMetric(capture.tempSd)} / CV ${_formatMetric(capture.tempCvPct)}%',
                ),
              ),
              const SizedBox(width: AppSizes.spaceSm),
              Expanded(
                child: _MetricSummaryTile(
                  label: 'RH',
                  average: '${_formatMetric(capture.rhAvg)}% avg',
                  range:
                      '${_formatMetric(capture.rhMin)} - ${_formatMetric(capture.rhMax)}%',
                  variability:
                      'SD ${_formatMetric(capture.rhSd)} / CV ${_formatMetric(capture.rhCvPct)}%',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceLg),
          if (points.isEmpty)
            const SizedBox(
              height: 180,
              child: Center(child: Text('No readings saved')),
            )
          else ...[
            GoveeMetricChart(
              chartKey: ValueKey('govee-temperature-chart-${capture.id}'),
              title: 'Temperature',
              unit: 'F',
              color: AppColors.chart1,
              points: points,
              average: capture.tempAvg,
              minimum: capture.tempMin,
              maximum: capture.tempMax,
              valueFor: (point) => point.temperatureFahrenheit,
              tooltipTextFor: (point) => _tooltipText(point, capture),
            ),
            const SizedBox(height: AppSizes.spaceLg),
            GoveeMetricChart(
              chartKey: ValueKey('govee-rh-chart-${capture.id}'),
              title: 'Relative Humidity',
              unit: '%',
              color: AppColors.chart2,
              points: points,
              average: capture.rhAvg,
              minimum: capture.rhMin,
              maximum: capture.rhMax,
              valueFor: (point) => point.humidity,
              tooltipTextFor: (point) => _tooltipText(point, capture),
            ),
          ],
        ],
      ),
    );
  }
}

class GoveeMetricChart extends StatefulWidget {
  final Key chartKey;
  final String title;
  final String unit;
  final Color color;
  final List<GoveeChartPoint> points;
  final double? average;
  final double? minimum;
  final double? maximum;
  final double Function(GoveeChartPoint point) valueFor;
  final String Function(GoveeChartPoint point) tooltipTextFor;

  const GoveeMetricChart({
    super.key,
    required this.chartKey,
    required this.title,
    required this.unit,
    required this.color,
    required this.points,
    required this.average,
    required this.minimum,
    required this.maximum,
    required this.valueFor,
    required this.tooltipTextFor,
  });

  @override
  State<GoveeMetricChart> createState() => _GoveeMetricChartState();
}

class _GoveeMetricChartState extends State<GoveeMetricChart> {
  static const double _maxScale = 8;
  late final TransformationController _transformationController;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chartPoints = widget.points
        .map((point) => FlSpot(point.x, widget.valueFor(point)))
        .where((spot) => spot.y.isFinite)
        .toList(growable: false);
    if (chartPoints.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text('No readings saved')),
      );
    }

    final yValues = chartPoints.map((spot) => spot.y).toList(growable: false);
    final computedMin = yValues.reduce((a, b) => a < b ? a : b);
    final computedMax = yValues.reduce((a, b) => a > b ? a : b);
    final displayMin = widget.minimum ?? computedMin;
    final displayMax = widget.maximum ?? computedMax;
    final displayAvg =
        widget.average ?? yValues.reduce((a, b) => a + b) / yValues.length;
    final yPadding = _axisPadding(displayMin, displayMax);
    final minY = displayMin - yPadding;
    final maxY = displayMax + yPadding;
    final minX = chartPoints.first.x;
    final maxX = chartPoints.last.x == minX
        ? minX + const Duration(minutes: 1).inMilliseconds
        : chartPoints.last.x;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.title,
          textAlign: TextAlign.center,
          style: AppTextStyles.title.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: AppSizes.spaceSm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              height: 230,
              child: _ChartValueRail(
                unit: widget.unit,
                max: displayMax,
                avg: displayAvg,
                min: displayMin,
              ),
            ),
            const SizedBox(width: AppSizes.spaceSm),
            Expanded(
              child: SizedBox(
                height: 230,
                child: LineChart(
                  key: widget.chartKey,
                  transformationConfig: FlTransformationConfig(
                    scaleAxis: FlScaleAxis.horizontal,
                    minScale: 1,
                    maxScale: _maxScale,
                    panEnabled: true,
                    scaleEnabled: true,
                    trackpadScrollCausesScale: true,
                    transformationController: _transformationController,
                  ),
                  LineChartData(
                    minX: minX,
                    maxX: maxX,
                    minY: minY,
                    maxY: maxY,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: true,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: AppColors.borderDefault,
                        strokeWidth: 1,
                        dashArray: const [6, 4],
                      ),
                      getDrawingVerticalLine: (_) => FlLine(
                        color: AppColors.borderDefault,
                        strokeWidth: 1,
                        dashArray: const [6, 4],
                      ),
                    ),
                    titlesData: const FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
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
                    borderData: FlBorderData(
                      show: true,
                      border: const Border(
                        top: BorderSide(color: AppColors.borderDefault),
                        bottom: BorderSide(color: AppColors.borderDefault),
                      ),
                    ),
                    extraLinesData: ExtraLinesData(
                      horizontalLines: [
                        HorizontalLine(
                          y: displayAvg,
                          color: widget.color,
                          strokeWidth: 2,
                          dashArray: const [6, 4],
                        ),
                      ],
                    ),
                    lineTouchData: LineTouchData(
                      enabled: true,
                      handleBuiltInTouches: true,
                      touchTooltipData: LineTouchTooltipData(
                        maxContentWidth: 260,
                        getTooltipColor: (_) => AppColors.textPrimary,
                        getTooltipItems: (touchedSpots) => touchedSpots
                            .map((spot) => _tooltipForPoint(spot))
                            .toList(growable: false),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: chartPoints,
                        isCurved: chartPoints.length > 1,
                        color: widget.color,
                        barWidth: 3,
                        dotData: FlDotData(show: chartPoints.length == 1),
                        belowBarData: BarAreaData(
                          show: true,
                          color: widget.color.withValues(alpha: 0.12),
                        ),
                      ),
                    ],
                  ),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.spaceSm),
        Padding(
          padding: const EdgeInsets.only(left: 84),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(_endpointLabel(widget.points.first.recordedAt)),
              ),
              const SizedBox(width: AppSizes.spaceSm),
              Flexible(
                child: Text(
                  _endpointLabel(widget.points.last.recordedAt),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.spaceSm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ZoomButton(
              tooltip: 'Zoom out ${widget.title}',
              icon: Icons.remove,
              onPressed: () => _zoomBy(0.75),
            ),
            const SizedBox(width: AppSizes.spaceXs),
            _ZoomButton(
              tooltip: 'Fit ${widget.title}',
              icon: Icons.fit_screen,
              label: 'Fit',
              onPressed: _fit,
            ),
            const SizedBox(width: AppSizes.spaceXs),
            _ZoomButton(
              tooltip: 'Zoom in ${widget.title}',
              icon: Icons.add,
              onPressed: () => _zoomBy(1.35),
            ),
          ],
        ),
      ],
    );
  }

  LineTooltipItem _tooltipForPoint(LineBarSpot spot) {
    final point = _nearestPoint(spot.x);
    return LineTooltipItem(
      widget.tooltipTextFor(point),
      const TextStyle(
        color: AppColors.textOnPrimary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
    );
  }

  GoveeChartPoint _nearestPoint(double x) {
    var closest = widget.points.first;
    var closestDistance = (closest.x - x).abs();
    for (final point in widget.points.skip(1)) {
      final distance = (point.x - x).abs();
      if (distance < closestDistance) {
        closest = point;
        closestDistance = distance;
      }
    }
    return closest;
  }

  double _axisPadding(double min, double max) {
    final span = (max - min).abs();
    if (span == 0) return widget.unit == '%' ? 2 : 1;
    return span * 0.12;
  }

  void _zoomBy(double factor) {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final nextScale = (currentScale * factor).clamp(1.0, _maxScale);
    setState(() {
      _transformationController.value = Matrix4.diagonal3Values(
        nextScale,
        1.0,
        1.0,
      );
    });
  }

  void _fit() {
    setState(() {
      _transformationController.value = Matrix4.identity();
    });
  }
}

class _ChartValueRail extends StatelessWidget {
  final String unit;
  final double max;
  final double avg;
  final double min;

  const _ChartValueRail({
    required this.unit,
    required this.max,
    required this.avg,
    required this.min,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _RailValue(label: 'Max', value: max, unit: unit),
        _RailValue(label: 'Avg', value: avg, unit: unit),
        _RailValue(label: 'Min', value: min, unit: unit),
      ],
    );
  }
}

class _RailValue extends StatelessWidget {
  final String label;
  final double value;
  final String unit;

  const _RailValue({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textTertiary,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${_formatMetric(value)}$unit',
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _MetricSummaryTile extends StatelessWidget {
  final String label;
  final String average;
  final String range;
  final String variability;

  const _MetricSummaryTile({
    required this.label,
    required this.average,
    required this.range,
    required this.variability,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.spaceSm),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSizes.spaceXs),
          Text(
            average,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(range, style: AppTextStyles.caption),
          Text(variability, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;

  const _Badge(this.label);

  @override
  Widget build(BuildContext context) {
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
        style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final String? label;
  final VoidCallback onPressed;

  const _ZoomButton({
    required this.tooltip,
    required this.icon,
    this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final child = label == null
        ? Icon(icon, size: 18)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 4),
              Text(label!),
            ],
          );
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(42, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
        ),
        child: child,
      ),
    );
  }
}

String _tooltipText(GoveeChartPoint point, GoveeDailyCaptureModel capture) {
  final lines = [
    _formatTimestamp(point.recordedAt),
    'Temp ${point.temperatureFahrenheit.toStringAsFixed(1)}F',
    'RH ${point.humidity.toStringAsFixed(1)}%',
    capture.place.label,
    if (capture.machineId != null) capture.machineId!,
  ];
  return lines.join('\n');
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

String _endpointLabel(DateTime timestamp) {
  final hour = timestamp.hour.toString().padLeft(2, '0');
  final minute = timestamp.minute.toString().padLeft(2, '0');
  final month = _monthName(timestamp.month);
  return '$hour:$minute, $month ${timestamp.day}';
}

String _monthName(int month) {
  return const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][month - 1];
}
