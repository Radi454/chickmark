import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/temp_converter.dart';
import '../../../providers/app_provider.dart';
import '../providers/govee_capture_provider.dart';

class GoveeLiveReadingCard extends StatelessWidget {
  const GoveeLiveReadingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GoveeCaptureProvider>();
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
    final updatedText = provider.liveUpdatedAt;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
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
              const SizedBox(width: 6),
              _settingsButton(context),
              const SizedBox(width: 6),
              _readAction(context, provider),
            ],
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
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
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }

  Widget _settingsButton(BuildContext context) {
    return IconButton(
      key: const ValueKey('govee-settings-button'),
      tooltip: 'Govee device settings',
      onPressed: () => _showSettings(context),
      icon: const Icon(Icons.settings_outlined),
      color: Colors.white,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.12),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.55),
        minimumSize: const Size.square(38),
        fixedSize: const Size.square(38),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  Widget _readAction(BuildContext context, GoveeCaptureProvider provider) {
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
                  ? context.read<GoveeCaptureProvider>().requestSensorReading()
                  : context.read<GoveeCaptureProvider>().connectSensor(),
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
        minimumSize: const Size(72, 38),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  Widget _metricTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
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
                fontSize: 26,
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
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
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
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: selected ? AppColors.primary : Colors.white,
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

class _GoveeSettingsSheet extends StatelessWidget {
  const _GoveeSettingsSheet();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GoveeCaptureProvider>();
    final devices = provider.availableDevices;
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Govee settings', style: AppTextStyles.sectionTitle),
            const SizedBox(height: 14),
            _SettingsSection(
              title: 'Connection details',
              children: [
                _DetailRow(label: 'Status', value: _status(provider)),
                _DetailRow(
                  label: 'Device name',
                  value: _deviceName(provider.deviceName),
                ),
                _DetailRow(
                  label: 'Device ID',
                  value: provider.deviceId ?? '--',
                ),
                _DetailRow(
                  label: 'RSSI',
                  value: provider.signalStrength?.toString() ?? '--',
                ),
                _DetailRow(
                  label: 'Battery',
                  value: provider.batteryPercent == null
                      ? '--'
                      : '${provider.batteryPercent}%',
                ),
                _DetailRow(
                  label: 'Last update',
                  value: provider.liveUpdatedAt == null
                      ? '--'
                      : _formatDateTime(provider.liveUpdatedAt!),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: provider.isGattConnecting
                      ? null
                      : () => unawaited(provider.connectSensor()),
                  icon: Icon(
                    provider.isScanning
                        ? Icons.refresh
                        : Icons.bluetooth_searching,
                    size: 18,
                  ),
                  label: Text(provider.isScanning ? 'Restart scan' : 'Scan'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      provider.isSensorConnected || provider.isGattConnected
                      ? () => unawaited(provider.disconnectSensor())
                      : null,
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('Disconnect'),
                ),
                TextButton.icon(
                  onPressed:
                      provider.isSensorConnected || provider.isGattConnected
                      ? () => unawaited(provider.requestSensorReading())
                      : null,
                  icon: const Icon(Icons.sensors, size: 18),
                  label: const Text('Read now'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Available devices', style: AppTextStyles.sectionTitle),
            const SizedBox(height: 8),
            if (devices.isEmpty)
              _EmptyDevicesNotice(isScanning: provider.isScanning)
            else
              ...devices.map((device) => _AvailableDeviceTile(device: device)),
            if (provider.bleDiagnostics.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Diagnostics', style: AppTextStyles.sectionTitle),
              const SizedBox(height: 8),
              ...provider.bleDiagnostics
                  .take(6)
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(entry, style: AppTextStyles.caption),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  static String _status(GoveeCaptureProvider provider) {
    if (!provider.isBleAvailable) return 'Bluetooth unavailable';
    if (provider.isGattConnecting) return 'Connecting';
    if (provider.isScanning &&
        !provider.isSensorConnected &&
        !provider.isGattConnected) {
      return 'Scanning';
    }
    if (provider.isSensorConnected || provider.isGattConnected) {
      return 'Connected';
    }
    return 'Disconnected';
  }

  static String _deviceName(String? name) {
    final raw = name == null || name.trim().isEmpty ? 'Govee H5051' : name;
    return raw.trim().replaceAll(RegExp(r'[_\s]+'), ' ');
  }

  static String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDevicesNotice extends StatelessWidget {
  final bool isScanning;

  const _EmptyDevicesNotice({required this.isScanning});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isScanning
            ? 'Scanning for nearby Govee sensors...'
            : 'No available devices yet. Start a scan to discover sensors nearby.',
        style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _AvailableDeviceTile extends StatelessWidget {
  final GoveeAvailableDevice device;

  const _AvailableDeviceTile({required this.device});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: device.selected ? AppColors.statusActiveBg : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: device.selected ? AppColors.primary : AppColors.borderDefault,
        ),
      ),
      child: ListTile(
        dense: true,
        title: Text(
          device.name,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          '${device.remoteId} | RSSI ${device.rssi?.toString() ?? '--'}',
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.caption,
        ),
        trailing: device.selected
            ? const Icon(Icons.check_circle, color: AppColors.primary)
            : TextButton(
                onPressed: () => unawaited(
                  context.read<GoveeCaptureProvider>().selectSensorDevice(
                    device.remoteId,
                  ),
                ),
                child: const Text('Use'),
              ),
      ),
    );
  }
}
