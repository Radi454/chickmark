import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/temp_converter.dart';
import '../../../providers/app_provider.dart';
import '../providers/temperature_rh_provider.dart';

class TemperatureRhPanel extends StatefulWidget {
  final bool compact;

  const TemperatureRhPanel({super.key, this.compact = false});

  @override
  State<TemperatureRhPanel> createState() => _TemperatureRhPanelState();
}

class _TemperatureRhPanelState extends State<TemperatureRhPanel> {
  static const List<int> _recordingIntervalOptions = [5, 10, 15, 30, 60];

  @override
  Widget build(BuildContext context) {
    final temperatureProvider = context.watch<TemperatureRhProvider>();

    return ListView(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      children: [
        _buildHeader(temperatureProvider),
        const SizedBox(height: 12),
        _buildDeviceStatusCard(temperatureProvider),
      ],
    );
  }

  Widget _buildHeader(TemperatureRhProvider provider) {
    final status = provider.isActive
        ? provider.isSensorConnected
              ? 'Capturing'
              : 'Scanning'
        : 'Ready';
    return Row(
      children: [
        const Icon(Icons.device_thermostat, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Temperature & R.H.',
            style: AppTextStyles.heading.copyWith(fontSize: 20),
          ),
        ),
        Chip(
          label: Text(status),
          backgroundColor: provider.isActive
              ? AppColors.completedBg
              : AppColors.ageBadgeBg,
          labelStyle: AppTextStyles.caption.copyWith(
            color: provider.isActive
                ? AppColors.completedText
                : AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceStatusCard(TemperatureRhProvider provider) {
    final connected = provider.isSensorConnected;
    final gattConnected = provider.isGattConnected;
    final gattConnecting = provider.isGattConnecting;
    final lastSeen = provider.lastSensorSeenAt;
    final subtitle = provider.isBleAvailable
        ? gattConnecting
              ? 'Status: Connecting'
              : provider.isScanning && !connected
              ? 'Status: Scanning'
              : connected || gattConnected
              ? 'Status: Connected'
              : 'Status: Disconnected'
        : 'Bluetooth unavailable';
    final updatedText = provider.liveUpdatedAt ?? lastSeen;

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
        children: [
          Row(
            children: [
              _circleIcon(
                connected
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
                      _displayDeviceName(provider.deviceName),
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.sectionTitle.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          connected
                              ? Icons.bluetooth_connected
                              : provider.isScanning
                              ? Icons.bluetooth_searching
                              : Icons.bluetooth_searching,
                          color: Colors.white.withValues(alpha: 0.85),
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            subtitle,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _circleIconButton(
                Icons.settings_outlined,
                () => _showDeviceSettings(context, provider),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _deviceMetrics(provider),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _deviceMeta(
                icon: Icons.schedule,
                label: updatedText == null
                    ? 'No update yet'
                    : 'Updated ${_formatTime(updatedText)}',
              ),
              _deviceMeta(
                icon: Icons.signal_cellular_alt,
                label: 'RSSI ${provider.signalStrength?.toString() ?? '--'}',
              ),
              _deviceMeta(
                icon: Icons.battery_5_bar,
                label:
                    'Battery ${provider.batteryPercent == null ? '--' : '${provider.batteryPercent}%'}',
              ),
            ],
          ),
          if (provider.isBleAvailable &&
              (!connected ||
                  provider.liveTemperatureFahrenheit == null ||
                  provider.liveHumidity == null)) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: _deviceActionButton(provider),
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

  Widget _circleIconButton(IconData icon, VoidCallback onPressed) {
    return Material(
      color: Colors.white.withValues(alpha: 0.15),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _deviceMetrics(TemperatureRhProvider provider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 340;
        final tiles = [
          _deviceMetric(
            value: _deviceTemp(provider),
            label: 'Temperature',
            icon: Icons.thermostat,
          ),
          _deviceMetric(
            value: _deviceHumidity(provider),
            label: 'Humidity',
            icon: Icons.water_drop_outlined,
          ),
        ];

        if (stack) {
          return Column(
            children: [tiles[0], const SizedBox(height: 8), tiles[1]],
          );
        }

        return Row(
          children: [
            Expanded(child: tiles[0]),
            const SizedBox(width: 10),
            Expanded(child: tiles[1]),
          ],
        );
      },
    );
  }

  Widget _deviceMetric({
    required String value,
    required String label,
    required IconData icon,
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
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceMeta({required IconData icon, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.72), size: 15),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: Colors.white.withValues(alpha: 0.76),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _deviceActionButton(TemperatureRhProvider provider) {
    final isBusy = provider.isGattConnecting;
    final label = isBusy
        ? 'Connecting...'
        : provider.isSensorConnected
        ? 'Read device'
        : provider.isScanning
        ? 'Restart scan'
        : 'Scan again';
    final icon = provider.isSensorConnected
        ? Icons.sensors
        : provider.isScanning
        ? Icons.refresh
        : Icons.bluetooth_searching;

    return TextButton.icon(
      onPressed: isBusy
          ? null
          : () => unawaited(
              provider.isSensorConnected
                  ? provider.requestSensorReading()
                  : provider.connectSensor(),
            ),
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.55),
        backgroundColor: Colors.white.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  String _displayDeviceName(String? name) {
    final raw = (name == null || name.trim().isEmpty)
        ? 'Govee H5051'
        : name.trim();
    return raw.replaceAll(RegExp(r'[_\s]+'), ' ');
  }

  String _deviceTemp(TemperatureRhProvider provider) {
    final tempF = provider.liveTemperatureFahrenheit;
    if (tempF == null) return '--';
    final appProvider = context.watch<AppProvider>();
    return TempConverter.display(
      tempF,
      showCelsius: appProvider.tempUnit == TempUnit.celsius,
    );
  }

  String _deviceHumidity(TemperatureRhProvider provider) {
    final humidity = provider.liveHumidity;
    if (humidity == null) return '--';
    return '${humidity.toStringAsFixed(1)}%';
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatInterval(int seconds) => '${seconds}s';

  void _showDeviceSettings(
    BuildContext context,
    TemperatureRhProvider provider,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              child: Consumer2<TemperatureRhProvider, AppProvider>(
                builder: (context, tempProvider, appProvider, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.tune_rounded,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Device settings',
                                  style: AppTextStyles.heading.copyWith(
                                    fontSize: 20,
                                  ),
                                ),
                                Text(
                                  _displayDeviceName(tempProvider.deviceName),
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.caption,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _settingsSection(
                        icon: Icons.schedule_outlined,
                        title: 'Local sync interval',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _recordingIntervalOptions.map((seconds) {
                            final selected =
                                tempProvider.sampleIntervalSeconds == seconds;
                            return ChoiceChip(
                              label: Text(_formatInterval(seconds)),
                              selected: selected,
                              selectedColor: AppColors.primary,
                              backgroundColor: Colors.white,
                              labelStyle: AppTextStyles.caption.copyWith(
                                color: selected ? Colors.white : AppColors.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                              side: BorderSide(
                                color: selected
                                    ? AppColors.primary
                                    : const Color(0xFFDDE6F1),
                              ),
                              onSelected: (_) => tempProvider
                                  .setSampleIntervalSeconds(seconds),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _settingsSection(
                        icon: Icons.thermostat_outlined,
                        title: 'Temperature unit',
                        child: Wrap(
                          spacing: 8,
                          children: [
                            _unitChip(
                              label: '°F',
                              unit: TempUnit.fahrenheit,
                              selectedUnit: appProvider.tempUnit,
                              onSelected: appProvider.setTempUnit,
                            ),
                            _unitChip(
                              label: '°C',
                              unit: TempUnit.celsius,
                              selectedUnit: appProvider.tempUnit,
                              onSelected: appProvider.setTempUnit,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _settingsSection(
                        icon: Icons.bluetooth_searching,
                        title: 'BLE diagnostics',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _diagnosticSummary(tempProvider),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: tempProvider.isGattConnecting
                                      ? null
                                      : () => unawaited(
                                          tempProvider.requestSensorReading(),
                                        ),
                                  icon: const Icon(Icons.sensors, size: 18),
                                  label: const Text('Read now'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: tempProvider.isGattConnecting
                                      ? null
                                      : () => unawaited(
                                          tempProvider.connectSensor(),
                                        ),
                                  icon: const Icon(
                                    Icons.bluetooth_connected,
                                    size: 18,
                                  ),
                                  label: const Text('Reconnect'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _diagnosticLog(tempProvider),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _settingsSection({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E7EF)),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _unitChip({
    required String label,
    required TempUnit unit,
    required TempUnit selectedUnit,
    required ValueChanged<TempUnit> onSelected,
  }) {
    final selected = unit == selectedUnit;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.primary,
      backgroundColor: Colors.white,
      avatar: selected
          ? const Icon(Icons.check, color: Colors.white, size: 16)
          : null,
      labelStyle: AppTextStyles.caption.copyWith(
        color: selected ? Colors.white : AppColors.textPrimary,
        fontWeight: FontWeight.w800,
      ),
      side: BorderSide(
        color: selected ? AppColors.primary : const Color(0xFFDDE6F1),
      ),
      onSelected: (_) => onSelected(unit),
    );
  }

  Widget _diagnosticSummary(TemperatureRhProvider provider) {
    final updatedAt = provider.liveUpdatedAt;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _diagnosticChip(
          provider.isScanning ? 'Scanning on' : 'Scanning off',
          provider.isScanning ? Icons.radar : Icons.radar_outlined,
        ),
        _diagnosticChip(
          provider.isGattConnected ? 'GATT on' : 'GATT off',
          provider.isGattConnected
              ? Icons.bluetooth_connected
              : Icons.bluetooth_disabled,
        ),
        _diagnosticChip(
          updatedAt == null
              ? 'No reading yet'
              : 'Last ${_formatTime(updatedAt)}',
          Icons.schedule,
        ),
      ],
    );
  }

  Widget _diagnosticChip(String label, IconData icon) {
    return Chip(
      avatar: Icon(icon, size: 16, color: AppColors.primary),
      label: Text(label),
      labelStyle: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
      backgroundColor: AppColors.ageBadgeBg,
      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.16)),
    );
  }

  Widget _diagnosticLog(TemperatureRhProvider provider) {
    final entries = provider.bleDiagnostics.reversed.take(18).toList();
    if (entries.isEmpty) {
      return Text(
        'No BLE events yet.',
        style: AppTextStyles.caption.copyWith(color: Colors.black54),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E7EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: entries
            .map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  entry,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.25,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
