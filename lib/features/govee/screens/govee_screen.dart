import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/utils/calculation_utils.dart';
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
          final selectedSavedSummary = provider.selectedSavedSummary;
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
              if (selectedSavedSummary != null) ...[
                const SizedBox(height: 12),
                GoveeCaptureChart(summary: selectedSavedSummary),
              ],
              if (provider.phase == GoveeCapturePhase.saved) ...[
                const SizedBox(height: 12),
                _SavedNotice(nextLabel: provider.suggestedNextPlace?.label),
              ],
            ],
          );
        },
      ),
      bottomNavigationBar: Consumer<GoveeCaptureProvider>(
        builder: (context, provider, _) {
          if (provider.savedSummaries.isEmpty) return const SizedBox.shrink();
          return _SavedStationStrip(provider: provider);
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
    final tempValues = points
        .map((point) => point.temperatureFahrenheit)
        .toList(growable: false);
    final rhValues = points
        .map((point) => point.humidity)
        .toList(growable: false);

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
          GoveeMetricChart(
            chartKey: const ValueKey('govee-temperature-preview-chart'),
            title: 'Temperature preview',
            points: points,
            valueFor: (point) => point.temperatureFahrenheit,
            unit: 'F',
            color: AppColors.chart1,
            average: _average(tempValues),
            minimum: _min(tempValues),
            maximum: _max(tempValues),
            tooltipTextFor: _tooltipText,
          ),
          const SizedBox(height: 16),
          GoveeMetricChart(
            chartKey: const ValueKey('govee-rh-preview-chart'),
            title: 'Relative Humidity preview',
            points: points,
            valueFor: (point) => point.humidity,
            unit: '%',
            color: AppColors.chart2,
            average: _average(rhValues),
            minimum: _min(rhValues),
            maximum: _max(rhValues),
            tooltipTextFor: _tooltipText,
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

  List<GoveeChartPoint> _previewPoints() {
    final points = <GoveeChartPoint>[];
    for (var i = 0; i < readings.length; i += 1) {
      final reading = readings[i];
      if (reading.temperatureFahrenheit == null || reading.humidity == null) {
        continue;
      }
      points.add(
        GoveeChartPoint(
          x: reading.timestamp.millisecondsSinceEpoch.toDouble(),
          temperatureFahrenheit: reading.temperatureFahrenheit!,
          humidity: reading.humidity!,
          recordedAt: reading.timestamp,
        ),
      );
    }
    return points;
  }

  String _tooltipText(GoveeChartPoint point) {
    return [
      _exactTimestamp(point.recordedAt),
      'Temp ${point.temperatureFahrenheit.toStringAsFixed(1)} F',
      'RH ${point.humidity.toStringAsFixed(1)}%',
      ?machineId,
    ].join('\n');
  }

  double _average(List<double> values) {
    return CalculationUtils.average(values);
  }

  double _min(List<double> values) => CalculationUtils.minValue(values)!;

  double _max(List<double> values) => CalculationUtils.maxValue(values)!;

  String _exactTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
    return '$date $time';
  }
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

class _SavedStationStrip extends StatelessWidget {
  final GoveeCaptureProvider provider;

  const _SavedStationStrip({required this.provider});

  @override
  Widget build(BuildContext context) {
    final selectedId = provider.selectedSavedSummary?.capture.id;
    return SafeArea(
      top: false,
      child: Container(
        key: const ValueKey('govee-saved-station-strip'),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.borderDefault)),
          boxShadow: [
            BoxShadow(
              color: AppColors.cardShadow,
              blurRadius: 18,
              offset: Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: AppColors.statusGood,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Saved stations',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${provider.savedSummaries.length}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 68,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: provider.savedSummaries.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final summary = provider.savedSummaries[index];
                  final capture = summary.capture;
                  final selected = capture.id == selectedId;
                  return _SavedStationChip(
                    captureId: capture.id,
                    title: capture.place.label,
                    subtitle: '${capture.readingCount} readings',
                    selected: selected,
                    onTap: () => context
                        .read<GoveeCaptureProvider>()
                        .selectSavedCapture(capture.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedStationChip extends StatelessWidget {
  final String captureId;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _SavedStationChip({
    required this.captureId,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.statusActiveBg : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: ValueKey('govee-saved-station-$captureId'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 168,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.borderDefault,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.circle_outlined,
                color: selected ? AppColors.primary : AppColors.textTertiary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
