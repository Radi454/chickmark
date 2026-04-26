import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/app_provider.dart';
import '../../../core/utils/temp_converter.dart';
import 'package:provider/provider.dart';

class GoveeSector extends StatefulWidget {
  final bool isAvailable;
  final bool isConnected;
  final String? deviceName;
  final int? signalStrength;
  final double? temperature;
  final double? humidity;
  final VoidCallback onScanTap;

  const GoveeSector({
    super.key,
    required this.isAvailable,
    required this.isConnected,
    this.deviceName,
    this.signalStrength,
    this.temperature,
    this.humidity,
    required this.onScanTap,
  });

  @override
  State<GoveeSector> createState() => _GoveeSectorState();
}

class _GoveeSectorState extends State<GoveeSector> {
  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final showCelsius = appProvider.tempUnit == TempUnit.celsius;

    if (!widget.isAvailable) {
      return _buildDisabledCard();
    }

    if (!widget.isConnected) {
      return _buildScanCard();
    }

    return _buildConnectedCard(showCelsius);
  }

  Widget _buildDisabledCard() {
    return Container(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bluetooth_disabled,
                color: Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'BLE unavailable',
                style: AppTextStyles.caption.copyWith(color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Bluetooth is not available on this device',
            style: AppTextStyles.body.copyWith(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Scan & Connect'),
          ),
        ],
      ),
    );
  }

  Widget _buildScanCard() {
    return Container(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: AppSizes.cardShadowBlur,
            offset: Offset(0, AppSizes.cardShadowOffsetY),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bluetooth_searching,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Govee Sensor',
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: widget.onScanTap,
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Scan & Connect'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedCard(bool showCelsius) {
    final tempDisplay = widget.temperature != null
        ? TempConverter.display(widget.temperature!, showCelsius: showCelsius)
        : '--';

    final humidityDisplay = widget.humidity?.toStringAsFixed(1) ?? '--';

    // Calculate signal strength bars
    final signalBars = _getSignalBars(widget.signalStrength);

    return Container(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: AppSizes.cardShadowBlur,
            offset: Offset(0, AppSizes.cardShadowOffsetY),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.bluetooth_connected,
                    color: AppColors.greenTab,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.deviceName ?? 'Govee Sensor',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Row(
                children: List.generate(4, (index) {
                  return Container(
                    margin: const EdgeInsets.only(left: 2),
                    width: 4,
                    height: 8 + (index * 4),
                    decoration: BoxDecoration(
                      color: index < signalBars
                          ? AppColors.greenTab
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildReadingCard(
                icon: Icons.thermostat,
                label: 'Temperature',
                value: tempDisplay,
                color: AppColors.primary,
              ),
              _buildReadingCard(
                icon: Icons.water_drop,
                label: 'Humidity',
                value: '$humidityDisplay%',
                color: Colors.blue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReadingCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.heading.copyWith(fontSize: 20, color: color),
        ),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }

  int _getSignalBars(int? rssi) {
    if (rssi == null) return 0;
    if (rssi >= -50) return 4;
    if (rssi >= -60) return 3;
    if (rssi >= -70) return 2;
    if (rssi >= -80) return 1;
    return 0;
  }
}
