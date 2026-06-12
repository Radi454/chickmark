import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/temp_converter.dart';
import '../../../providers/app_provider.dart';
import '../providers/govee_capture_provider.dart';

part 'govee_settings_sheet.dart';

class GoveeLiveReadingCard extends StatelessWidget {
  const GoveeLiveReadingCard({super.key});

  static const Color _gradientForeground = Colors.white;
  static const Color _gradientMutedForeground = Color(0xD9FFFFFF);
  static const Color _gradientControlFill = Color(0x26FFFFFF);
  static const Color _gradientBorder = Color(0x3DFFFFFF);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GoveeCaptureProvider>();
    final hasLiveData = provider.hasFreshLiveData;
    final status = _goveeConnectionStatus(provider);
    final updatedText = provider.liveUpdatedAt;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: _gradientBorder),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _circleIcon(
                hasLiveData
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
                      _goveeDeviceName(provider.deviceName),
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.title.copyWith(
                        color: _gradientForeground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Status: ${status.label}',
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: _gradientMutedForeground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _settingsButton(context),
              const SizedBox(width: 6),
              _readAction(context, provider),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
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
                  children: [
                    tempTile,
                    const SizedBox(height: AppSizes.spaceSm),
                    rhTile,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: tempTile),
                  const SizedBox(width: AppSizes.spaceSm),
                  Expanded(child: rhTile),
                ],
              );
            },
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Wrap(
            spacing: AppSizes.spaceSm,
            runSpacing: AppSizes.spaceXs,
            crossAxisAlignment: WrapCrossAlignment.center,
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
              _unitToggle(context),
            ],
          ),
          if (provider.error != null) ...[
            const SizedBox(height: 10),
            Text(
              provider.error!,
              style: AppTextStyles.caption.copyWith(
                color: _gradientForeground,
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
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: _gradientControlFill,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: _gradientForeground, size: 18),
    );
  }

  Widget _settingsButton(BuildContext context) {
    return IconButton(
      key: const ValueKey('govee-settings-button'),
      tooltip: 'Govee device settings',
      onPressed: () => _showSettings(context),
      icon: const Icon(Icons.settings_outlined),
      color: _gradientForeground,
      style: IconButton.styleFrom(
        backgroundColor: _gradientControlFill,
        foregroundColor: _gradientForeground,
        disabledForegroundColor: _gradientMutedForeground,
        minimumSize: const Size.square(36),
        fixedSize: const Size.square(36),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.iconRadius),
        ),
      ),
    );
  }

  Widget _readAction(BuildContext context, GoveeCaptureProvider provider) {
    final hasLiveData = provider.hasFreshLiveData;
    final busy =
        provider.isGattConnecting || (provider.isScanning && !hasLiveData);
    final label = busy
        ? provider.isGattConnecting
              ? 'Connecting'
              : 'Scanning'
        : hasLiveData
        ? 'Read'
        : 'Scan';

    return TextButton.icon(
      // The settings sheet intentionally exposes "Restart scan". The compact
      // card only says "Scan", so disable it while a scan is already active.
      onPressed: busy
          ? null
          : () => unawaited(
              hasLiveData
                  ? context.read<GoveeCaptureProvider>().requestSensorReading()
                  : context.read<GoveeCaptureProvider>().connectSensor(),
            ),
      icon: busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(_gradientForeground),
              ),
            )
          : Icon(
              hasLiveData ? Icons.sensors : Icons.bluetooth_searching,
              size: 18,
            ),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: _gradientForeground,
        disabledForegroundColor: _gradientMutedForeground,
        backgroundColor: _gradientControlFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        ),
        minimumSize: const Size(70, 36),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.spaceMd,
          vertical: AppSizes.spaceSm,
        ),
      ),
    );
  }

  Widget _metricTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.spaceSm),
      decoration: BoxDecoration(
        color: _gradientControlFill,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: _gradientBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _gradientForeground, size: 17),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: _gradientMutedForeground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceXs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: AppTextStyles.heading.copyWith(
                color: _gradientForeground,
                fontSize: 20,
                height: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _unitToggle(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final selectedUnit = appProvider.tempUnit;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: _gradientControlFill,
        borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
        border: Border.all(color: _gradientBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _unitChip(
            context,
            label: '°F',
            selected: selectedUnit == TempUnit.fahrenheit,
            unit: TempUnit.fahrenheit,
          ),
          _unitChip(
            context,
            label: '°C',
            selected: selectedUnit == TempUnit.celsius,
            unit: TempUnit.celsius,
          ),
        ],
      ),
    );
  }

  Widget _unitChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required TempUnit unit,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: selected
          ? null
          : () => unawaited(context.read<AppProvider>().setTempUnit(unit)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
        ),
        child: Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: selected ? AppColors.primary : _gradientMutedForeground,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _gradientMutedForeground, size: 15),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: _gradientMutedForeground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  String _temperature(BuildContext context, GoveeCaptureProvider provider) {
    final tempF = provider.liveTemperatureFahrenheit;
    if (tempF == null) return '--';
    final appProvider = context.watch<AppProvider>();
    return TempConverter.display(
      tempF,
      showCelsius: appProvider.tempUnit == TempUnit.celsius,
    );
  }

  String _humidity(GoveeCaptureProvider provider) {
    final humidity = provider.liveHumidity;
    if (humidity == null) return '--';
    return '${humidity.toStringAsFixed(1)}%';
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _showSettings(BuildContext context) {
    final provider = context.read<GoveeCaptureProvider>();
    final appProvider = context.read<AppProvider>();
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider.value(value: appProvider),
        ],
        child: const _GoveeSettingsSheet(),
      ),
    );
  }
}

enum _GoveeConnectionStatus {
  bluetoothUnavailable('Bluetooth unavailable'),
  connecting('Connecting'),
  scanning('Scanning'),
  connected('Connected'),
  recentReading('Recent reading'),
  disconnected('Disconnected');

  final String label;

  const _GoveeConnectionStatus(this.label);
}

_GoveeConnectionStatus _goveeConnectionStatus(GoveeCaptureProvider provider) {
  if (!provider.isBleAvailable) {
    return _GoveeConnectionStatus.bluetoothUnavailable;
  }
  if (provider.isGattConnecting) return _GoveeConnectionStatus.connecting;
  if (provider.isScanning && !provider.hasLiveConnection) {
    return _GoveeConnectionStatus.scanning;
  }
  if (provider.hasLiveConnection) return _GoveeConnectionStatus.connected;
  if (provider.hasFreshLiveData) return _GoveeConnectionStatus.recentReading;
  return _GoveeConnectionStatus.disconnected;
}

String _goveeDeviceName(String? name) {
  final raw = name == null || name.trim().isEmpty ? 'Govee H5051' : name;
  return raw.trim().replaceAll(RegExp(r'[_\s]+'), ' ');
}
