import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../dashboard/models/govee_capture_summary.dart';
import '../../dashboard/widgets/govee_capture_chart.dart';
import '../../../services/govee/govee_service.dart';
import '../providers/govee_capture_provider.dart';
import '../widgets/govee_scope_picker.dart';
import '../widgets/govee_place_recorder.dart';

class GoveeScreen extends StatefulWidget {
  const GoveeScreen({super.key});

  @override
  State<GoveeScreen> createState() => _GoveeScreenState();
}

class _GoveeScreenState extends State<GoveeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!kIsWeb) return;
      unawaited(context.read<GoveeCaptureProvider>().ensureBleReady());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientAppBar(title: 'Govee'),
      body: Consumer<GoveeCaptureProvider>(
        builder: (context, provider, _) {
          return ListView(
            padding: const EdgeInsets.all(AppSizes.cardPadding),
            children: [
              _GoveeLiveHeader(provider: provider),
              const SizedBox(height: 12),
              const GoveeScopePicker(),
              if (provider.hasExistingCapture) ...[
                const SizedBox(height: 12),
                _ExistingCaptureNotice(
                  date: provider.captureDate ?? '',
                  placeLabel: provider.place?.label ?? 'Selected place',
                ),
              ],
              const SizedBox(height: 12),
              const GoveePlaceRecorder(),
              if (provider.liveRecordingReadings.isNotEmpty) ...[
                const SizedBox(height: 12),
                GoveeChartPreview(
                  readings: provider.liveRecordingReadings,
                  machineId: provider.machineId,
                ),
              ],
              if (provider.finishedCapture != null) ...[
                const SizedBox(height: 12),
                GoveeCaptureChart(
                  summary: GoveeCaptureSummary(
                    capture: provider.finishedCapture!,
                    readings: provider.finishedReadings,
                  ),
                ),
              ],
              if (provider.phase == GoveeCapturePhase.saved) ...[
                const SizedBox(height: 12),
                _SavedNotice(nextLabel: provider.suggestedNextPlace?.label),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _GoveeLiveHeader extends StatelessWidget {
  final GoveeCaptureProvider provider;

  const _GoveeLiveHeader({required this.provider});

  @override
  Widget build(BuildContext context) {
    final connected = provider.isSensorConnected || provider.isGattConnected;
    final busy = provider.isGattConnecting;
    final status = busy
        ? 'Connecting'
        : provider.isScanning && !connected
        ? 'Scanning'
        : connected
        ? 'Connected'
        : provider.isBleAvailable
        ? 'Disconnected'
        : 'Bluetooth unavailable';
    final actionLabel = busy
        ? 'Connecting...'
        : connected
        ? 'Read'
        : provider.deviceName == null
        ? 'Scan'
        : 'Reconnect';

    return Container(
      key: const ValueKey('govee-live-header'),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadowElevated,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _deviceName(provider.deviceName),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textOnPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            status,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _HeaderMetric(
                  label: 'Temperature',
                  value: _temperature(provider.liveTemperatureFahrenheit),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HeaderMetric(
                  label: 'Relative Humidity',
                  value: _humidity(provider.liveHumidity),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  _updatedAt(provider.liveUpdatedAt),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => unawaited(
                        connected
                            ? context
                                  .read<GoveeCaptureProvider>()
                                  .requestSensorReading()
                            : context
                                  .read<GoveeCaptureProvider>()
                                  .connectSensor(),
                      ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                ),
                icon: Icon(
                  connected ? Icons.sensors : Icons.bluetooth_searching,
                  size: 18,
                ),
                label: Text(actionLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _deviceName(String? name) {
    if (name == null || name.trim().isEmpty) return 'Govee H5051';
    return name.replaceAll(RegExp(r'[_\s]+'), ' ');
  }

  String _temperature(double? tempF) {
    if (tempF == null) return '-- F';
    return '${tempF.toStringAsFixed(1)} F';
  }

  String _humidity(double? humidity) {
    if (humidity == null) return '--%';
    return '${humidity.toStringAsFixed(1)}%';
  }

  String _updatedAt(DateTime? timestamp) {
    if (timestamp == null) return 'Updated at --';
    final local = timestamp.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return 'Updated at $hour:$minute';
  }
}

class _HeaderMetric extends StatelessWidget {
  final String label;
  final String value;

  const _HeaderMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textOnPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

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

class _ExistingCaptureNotice extends StatelessWidget {
  final String date;
  final String placeLabel;

  const _ExistingCaptureNotice({required this.date, required this.placeLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.statusWarningBg,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.statusWarning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$placeLabel already has a Govee capture for $date. You will be asked before older records are replaced.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedNotice extends StatelessWidget {
  final String? nextLabel;

  const _SavedNotice({required this.nextLabel});

  @override
  Widget build(BuildContext context) {
    final text = nextLabel == null
        ? 'Capture saved. Choose the next place when ready.'
        : 'Capture saved. Next place: $nextLabel.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.statusGoodBg,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: AppColors.statusGood),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
