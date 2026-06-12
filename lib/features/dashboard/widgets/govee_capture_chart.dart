import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/core/utils/date_utils.dart';
import 'package:hatchaudit/core/utils/temp_converter.dart';
import 'package:hatchaudit/data/models/govee_capture_model.dart';
import 'package:hatchaudit/features/dashboard/models/govee_capture_summary.dart';
import 'package:hatchaudit/providers/app_provider.dart';
import 'package:provider/provider.dart';

const _goveeChartCardColor = Colors.white;
const _goveeChartLineColor = Color(0xFF12B7F5);
const _goveeChartGridColor = Color(0xFFE3E8EF);
const _goveeChartRailLabelColor = Color(0xFF9CA3AF);
const _goveeChartRailValueColor = Color(0xFF111827);
const _goveeChartTooltipColor = Color(0xFF111827);
const _goveeChartPlotHeight = 220.0;
const _goveeChartBottomTitleHeight = 28.0;
const _goveeChartRailWidth = 58.0;
const _goveeChartRailGap = 8.0;
const _goveeChartRailOffset = _goveeChartRailWidth + _goveeChartRailGap;
const _goveeEndpointTextStyle = TextStyle(
  color: AppColors.textPrimary,
  fontSize: 12,
  fontWeight: FontWeight.w600,
);

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
    final showCelsius =
        context.watch<AppProvider>().tempUnit == TempUnit.celsius;
    final tempUnit = _temperatureUnit(showCelsius);

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
                    Text(
                      HatchDateUtils.formatDisplayDateKey(capture.captureDate),
                      textDirection: TextDirection.ltr,
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
              _Badge('${capture.readingCount} readings'),
            ],
          ),
          const SizedBox(height: AppSizes.spaceMd),
          Row(
            children: [
              Expanded(
                child: _MetricSummaryTile(
                  label: 'Temp',
                  average:
                      '${_formatMetric(_temperatureValue(capture.tempAvg, showCelsius))}$tempUnit avg',
                  range:
                      '${_formatMetric(_temperatureValue(capture.tempMin, showCelsius))} - ${_formatMetric(_temperatureValue(capture.tempMax, showCelsius))}$tempUnit',
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
              unit: tempUnit,
              color: AppColors.chart1,
              points: points,
              average: _temperatureValue(capture.tempAvg, showCelsius),
              minimum: _temperatureValue(capture.tempMin, showCelsius),
              maximum: _temperatureValue(capture.tempMax, showCelsius),
              valueFor: (point) =>
                  _temperatureValue(point.temperatureFahrenheit, showCelsius)!,
              tooltipTextFor: (point) =>
                  _tooltipText(point, capture, showCelsius: showCelsius),
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
              tooltipTextFor: (point) =>
                  _tooltipText(point, capture, showCelsius: showCelsius),
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
  final bool interactionEnabled;
  final double plotHeight;
  final bool compact;

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
    this.interactionEnabled = true,
    this.plotHeight = _goveeChartPlotHeight,
    this.compact = false,
  });

  @override
  State<GoveeMetricChart> createState() => _GoveeMetricChartState();
}

class _GoveeMetricChartState extends State<GoveeMetricChart> {
  static const double _maxScale = 50;
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
      return SizedBox(
        height: widget.plotHeight,
        child: const Center(child: Text('No readings saved')),
      );
    }

    final yValues = chartPoints.map((spot) => spot.y).toList(growable: false);
    final computedMin = yValues.reduce((a, b) => a < b ? a : b);
    final computedMax = yValues.reduce((a, b) => a > b ? a : b);
    final displayMin = widget.minimum ?? computedMin;
    final displayMax = widget.maximum ?? computedMax;
    final displayAvg =
        widget.average ?? yValues.reduce((a, b) => a + b) / yValues.length;
    final yBounds = _axisBounds(displayMin, displayMax);
    final minY = yBounds.min;
    final maxY = yBounds.max;
    final minX = chartPoints.first.x;
    final maxX = chartPoints.last.x == minX
        ? minX + const Duration(minutes: 1).inMilliseconds
        : chartPoints.last.x;

    final compact = widget.compact;
    final plotHeight = widget.plotHeight;
    return Container(
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 10, 12, 8)
          : const EdgeInsets.fromLTRB(14, 16, 14, 16),
      decoration: BoxDecoration(
        color: _goveeChartCardColor,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        boxShadow: [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: compact ? 10 : 18,
            offset: Offset(0, compact ? 4 : 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: AppTextStyles.title.copyWith(
              color: AppColors.textPrimary,
              fontSize: compact ? 13 : 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: compact ? AppSizes.spaceXs : AppSizes.spaceMd),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _goveeChartRailWidth,
                height: plotHeight,
                child: _ChartValueRail(
                  unit: widget.unit,
                  max: displayMax,
                  avg: displayAvg,
                  min: displayMin,
                  compact: compact,
                ),
              ),
              const SizedBox(width: _goveeChartRailGap),
              Expanded(
                child: SizedBox(
                  height: plotHeight + _goveeChartBottomTitleHeight,
                  child: LineChart(
                    key: widget.chartKey,
                    transformationConfig: FlTransformationConfig(
                      scaleAxis: FlScaleAxis.horizontal,
                      minScale: 1,
                      maxScale: widget.interactionEnabled ? _maxScale : 1,
                      panEnabled: widget.interactionEnabled,
                      scaleEnabled: widget.interactionEnabled,
                      trackpadScrollCausesScale: widget.interactionEnabled,
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
                        horizontalInterval: _gridInterval(minY, maxY, lines: 3),
                        verticalInterval: _gridInterval(minX, maxX, lines: 8),
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: _goveeChartGridColor,
                          strokeWidth: 1,
                          dashArray: const [3, 6],
                        ),
                        getDrawingVerticalLine: (_) => FlLine(
                          color: _goveeChartGridColor,
                          strokeWidth: 1,
                          dashArray: const [3, 6],
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: _goveeChartBottomTitleHeight,
                            interval: _bottomTickInterval(minX, maxX),
                            getTitlesWidget: (value, meta) =>
                                _bottomTitle(value, minX, maxX),
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      extraLinesData: ExtraLinesData(
                        horizontalLines: [
                          HorizontalLine(
                            y: displayAvg,
                            color: _goveeChartLineColor,
                            strokeWidth: 2,
                            dashArray: const [3, 6],
                          ),
                        ],
                      ),
                      lineTouchData: LineTouchData(
                        enabled: true,
                        handleBuiltInTouches: true,
                        touchTooltipData: LineTouchTooltipData(
                          maxContentWidth: 260,
                          getTooltipColor: (_) => _goveeChartTooltipColor,
                          getTooltipItems: (touchedSpots) => touchedSpots
                              .map((spot) => _tooltipForPoint(spot))
                              .toList(growable: false),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: chartPoints,
                          isCurved: false,
                          color: _goveeChartLineColor,
                          barWidth: 2.0,
                          dotData: FlDotData(show: chartPoints.length == 1),
                          belowBarData: BarAreaData(
                            show: true,
                            color: _goveeChartLineColor.withValues(alpha: 0.12),
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
          SizedBox(height: compact ? AppSizes.spaceXs : AppSizes.spaceSm),
          Padding(
            padding: const EdgeInsets.only(left: _goveeChartRailOffset),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _endpointLabel(widget.points.first.recordedAt),
                        style: _goveeEndpointTextStyle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSizes.spaceSm),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _endpointLabel(widget.points.last.recordedAt),
                        textAlign: TextAlign.end,
                        style: _goveeEndpointTextStyle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

  ({double min, double max}) _axisBounds(double min, double max) {
    final low = min < max ? min : max;
    final high = max > min ? max : min;
    final span = (high - low).abs();
    final targetSpan = span == 0
        ? _minimumVisualYSpan
        : (span * 1.24).clamp(_minimumVisualYSpan, double.infinity);
    final midpoint = (low + high) / 2;
    var visualMin = midpoint - (targetSpan / 2);
    var visualMax = midpoint + (targetSpan / 2);

    if (widget.unit == '%') {
      if (visualMin < 0) {
        visualMax = (visualMax - visualMin).clamp(0, 100);
        visualMin = 0;
      }
      if (visualMax > 100) {
        visualMin = (visualMin - (visualMax - 100)).clamp(0, 100);
        visualMax = 100;
      }
    }

    return (min: visualMin, max: visualMax);
  }

  double get _minimumVisualYSpan {
    return widget.unit == '%' ? 5.0 : 2.0;
  }

  double _gridInterval(double min, double max, {required int lines}) {
    final span = (max - min).abs();
    if (!span.isFinite || span <= 0) return 1;
    return span / lines;
  }

  double _bottomTickInterval(double minX, double maxX) {
    final spanMs = (maxX - minX).abs();
    final minuteMs = const Duration(minutes: 1).inMilliseconds.toDouble();
    if (spanMs <= minuteMs * 10) return minuteMs * 2;
    if (spanMs <= minuteMs * 30) return minuteMs * 5;
    if (spanMs <= minuteMs * 90) return minuteMs * 15;
    if (spanMs <= minuteMs * 180) return minuteMs * 30;
    if (spanMs <= minuteMs * 720) return minuteMs * 60;
    return spanMs / 4;
  }

  Widget _bottomTitle(double value, double minX, double maxX) {
    if (value < minX || value > maxX) return const SizedBox.shrink();
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      value.round(),
    ).toLocal();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        _clockLabel(timestamp),
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ChartValueRail extends StatelessWidget {
  final String unit;
  final double max;
  final double avg;
  final double min;
  final bool compact;

  const _ChartValueRail({
    required this.unit,
    required this.max,
    required this.avg,
    required this.min,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _RailSlot(
          child: _RailValue(
            label: 'Max',
            value: max,
            unit: unit,
            compact: compact,
          ),
        ),
        _RailSlot(
          child: _RailValue(
            label: 'Avg',
            value: avg,
            unit: unit,
            compact: compact,
          ),
        ),
        _RailSlot(
          child: _RailValue(
            label: 'Min',
            value: min,
            unit: unit,
            compact: compact,
          ),
        ),
      ],
    );
  }
}

class _RailSlot extends StatelessWidget {
  final Widget child;

  const _RailSlot({required this.child});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Align(
        alignment: Alignment.centerRight,
        child: FittedBox(fit: BoxFit.scaleDown, child: child),
      ),
    );
  }
}

class _RailValue extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final bool compact;

  const _RailValue({
    required this.label,
    required this.value,
    required this.unit,
    this.compact = false,
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
            color: _goveeChartRailLabelColor,
            fontSize: compact ? 10 : 13,
            height: compact ? 1.0 : null,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: compact ? 1 : 2),
        Text(
          '${_formatMetric(value)}$unit',
          style: AppTextStyles.body.copyWith(
            color: _goveeChartRailValueColor,
            fontSize: compact ? 12 : 14,
            height: compact ? 1.05 : null,
            fontWeight: FontWeight.w700,
          ),
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

String _tooltipText(
  GoveeChartPoint point,
  GoveeDailyCaptureModel capture, {
  required bool showCelsius,
}) {
  final tempUnit = _temperatureUnit(showCelsius);
  final lines = [
    _formatTimestamp(point.recordedAt),
    'Temp ${_formatMetric(_temperatureValue(point.temperatureFahrenheit, showCelsius))}$tempUnit',
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

double? _temperatureValue(double? fahrenheit, bool showCelsius) {
  if (fahrenheit == null) return null;
  return showCelsius ? TempConverter.toCelsius(fahrenheit) : fahrenheit;
}

String _temperatureUnit(bool showCelsius) => showCelsius ? '°C' : 'F';

String _formatClock(DateTime dateTime) {
  final hour = dateTime.hour;
  final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final suffix = hour >= 12 ? 'PM' : 'AM';
  return '$displayHour:$minute $suffix';
}

String _clockLabel(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatTimestamp(DateTime dateTime) {
  return HatchDateUtils.formatDisplayTimestamp(dateTime);
}

String _endpointLabel(DateTime timestamp) {
  final hour = timestamp.hour.toString().padLeft(2, '0');
  final minute = timestamp.minute.toString().padLeft(2, '0');
  return '${HatchDateUtils.formatDisplayDate(timestamp)} $hour:$minute';
}
