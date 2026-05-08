import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../dashboard/models/govee_capture_summary.dart';
import '../../dashboard/widgets/govee_capture_chart.dart';
import '../providers/govee_capture_provider.dart';
import '../widgets/govee_chart_preview.dart';
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
