import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

/// A simulated BLE sensor widget that displays temperature and humidity readings.
/// In a real implementation this would connect to a Govee BLE device.
/// The [onReading] callback is invoked when values are captured.
class BleSensorWidget extends StatefulWidget {
  final double? temperature;
  final double? humidity;
  final void Function(double temperature, double humidity)? onReading;

  const BleSensorWidget({
    super.key,
    this.temperature,
    this.humidity,
    this.onReading,
  });

  @override
  State<BleSensorWidget> createState() => _BleSensorWidgetState();
}

class _BleSensorWidgetState extends State<BleSensorWidget> {
  bool _isConnecting = false;
  bool _isConnected = false;
  double? _temperature;
  double? _humidity;

  @override
  void initState() {
    super.initState();
    _temperature = widget.temperature;
    _humidity = widget.humidity;
    if (_temperature != null && _humidity != null) {
      _isConnected = true;
    }
  }

  Future<void> _scanAndConnect() async {
    setState(() => _isConnecting = true);
    // Simulate BLE scan delay
    await Future.delayed(const Duration(seconds: 2));
    // Simulated readings
    final temp = 37.2 + (DateTime.now().millisecondsSinceEpoch % 20) / 10.0;
    final hum = 60.0 + (DateTime.now().millisecondsSinceEpoch % 15);
    setState(() {
      _isConnecting = false;
      _isConnected = true;
      _temperature = temp;
      _humidity = hum;
    });
    widget.onReading?.call(_temperature!, _humidity!);
  }

  Color _tempColor(double temp) {
    if (temp < 35) return AppTheme.secondary;
    if (temp <= 38.5) return AppTheme.green;
    return AppTheme.red;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.primary.withValues(alpha: 0.05),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _isConnected ? AppTheme.green : AppTheme.textSecondary,
          width: 1.5,
        ),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bluetooth,
                  color: _isConnected ? AppTheme.green : AppTheme.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _isConnected
                      ? 'BLE Sensor Connected'
                      : 'BLE Sensor (Govee)',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: _isConnected
                        ? AppTheme.green
                        : AppTheme.textSecondary,
                  ),
                ),
                const Spacer(),
                if (_isConnecting)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  TextButton.icon(
                    onPressed: _scanAndConnect,
                    icon: Icon(
                      _isConnected ? Icons.refresh : Icons.search,
                      size: 16,
                    ),
                    label: Text(_isConnected ? 'Refresh' : 'Scan'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                    ),
                  ),
              ],
            ),
            if (_isConnected && _temperature != null && _humidity != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _SensorValueChip(
                      icon: Icons.thermostat,
                      label: 'Temperature',
                      value: '${_temperature!.toStringAsFixed(1)} °C',
                      color: _tempColor(_temperature!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SensorValueChip(
                      icon: Icons.water_drop,
                      label: 'Humidity',
                      value: '${_humidity!.toStringAsFixed(1)} %',
                      color: AppTheme.secondary,
                    ),
                  ),
                ],
              ),
            ] else if (!_isConnecting) ...[
              const SizedBox(height: 8),
              Text(
                'Tap "Scan" to connect to the nearest Govee sensor.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SensorValueChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SensorValueChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
