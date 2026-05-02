import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/temp_converter.dart';
import '../../../features/temperature/providers/temperature_rh_provider.dart';
import '../../../providers/app_provider.dart';

class GoveeLiveReadingCard extends StatelessWidget {
  const GoveeLiveReadingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TemperatureRhProvider>();
    final connected = provider.isSensorConnected;
    final gattConnected = provider.isGattConnected;
    final gattConnecting = provider.isGattConnecting;
    final subtitle = provider.isBleAvailable
        ? gattConnecting
              ? 'Connecting'
              : provider.isScanning && !connected
              ? 'Scanning'
              : connected || gattConnected
              ? 'Connected'
              : 'Disconnected'
        : 'Bluetooth unavailable';
    final updatedText = provider.liveUpdatedAt ?? provider.lastSensorSeenAt;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: AppSizes.cardShadowBlur,
            offset: Offset(0, AppSizes.cardShadowOffsetY),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _circleIcon(
                connected || gattConnected
                    ? Icons.bluetooth_connected
                    : provider.isScanning
                    ? Icons.bluetooth_searching
                    : Icons.bluetooth,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _deviceName(provider.deviceName),
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.sectionTitle.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Status: $subtitle',
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _readAction(context, provider),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 340;
              final tempTile = _metricTile(
                icon: Icons.thermostat,
                label: 'Temperature',
                value: _temperature(context, provider),
              );
              final rhTile = _metricTile(
                icon: Icons.water_drop_outlined,
                label: 'Humidity',
                value: _humidity(provider),
              );

              if (stack) {
                return Column(
                  children: [tempTile, const SizedBox(height: 8), rhTile],
                );
              }
              return Row(
                children: [
                  Expanded(child: tempTile),
                  const SizedBox(width: 10),
                  Expanded(child: rhTile),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _meta(
                Icons.schedule,
                updatedText == null
                    ? 'No update yet'
                    : 'Updated ${_formatTime(updatedText)}',
              ),
              _meta(
                Icons.signal_cellular_alt,
                'RSSI ${provider.signalStrength?.toString() ?? '--'}',
              ),
              _meta(
                Icons.battery_5_bar,
                'Battery ${provider.batteryPercent == null ? '--' : '${provider.batteryPercent}%'}',
              ),
            ],
          ),
          if (provider.error != null) ...[
            const SizedBox(height: 10),
            Text(
              provider.error!,
              style: AppTextStyles.caption.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _circleIcon(IconData icon) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }

  Widget _readAction(BuildContext context, TemperatureRhProvider provider) {
    final busy = provider.isGattConnecting;
    final label = busy
        ? 'Connecting'
        : provider.isSensorConnected || provider.isGattConnected
        ? 'Read'
        : provider.isScanning
        ? 'Restart'
        : 'Scan';

    return TextButton.icon(
      onPressed: busy
          ? null
          : () => unawaited(
              provider.isSensorConnected || provider.isGattConnected
                  ? context.read<TemperatureRhProvider>().requestSensorReading()
                  : context.read<TemperatureRhProvider>().connectSensor(),
            ),
      icon: Icon(
        provider.isSensorConnected || provider.isGattConnected
            ? Icons.sensors
            : Icons.bluetooth_searching,
        size: 18,
      ),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.55),
        backgroundColor: Colors.white.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  Widget _metricTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.82), size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: AppTextStyles.heading.copyWith(
                color: Colors.white,
                fontSize: 34,
                height: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.72), size: 15),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: Colors.white.withValues(alpha: 0.76),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  String _deviceName(String? name) {
    final raw = name == null || name.trim().isEmpty ? 'Govee H5051' : name;
    return raw.trim().replaceAll(RegExp(r'[_\s]+'), ' ');
  }

  String _temperature(BuildContext context, TemperatureRhProvider provider) {
    final tempF = provider.liveTemperatureFahrenheit;
    if (tempF == null) return '--';
    final appProvider = context.watch<AppProvider>();
    return TempConverter.display(
      tempF,
      showCelsius: appProvider.tempUnit == TempUnit.celsius,
    );
  }

  String _humidity(TemperatureRhProvider provider) {
    final humidity = provider.liveHumidity;
    if (humidity == null) return '--';
    return '${humidity.toStringAsFixed(1)}%';
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
