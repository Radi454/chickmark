import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';

class GoveeSensorReading {
  final double? temperatureFahrenheit;
  final double? humidity;
  final DateTime timestamp;

  GoveeSensorReading({
    this.temperatureFahrenheit,
    this.humidity,
    required this.timestamp,
  });
}

class GoveeService {
  bool _isAvailable = false;
  bool _isConnected = false;
  String? _deviceName;
  int? _signalStrength;
  final StreamController<GoveeSensorReading> _readingsController =
      StreamController<GoveeSensorReading>.broadcast();

  bool get isAvailable => _isAvailable;
  bool get isConnected => _isConnected;
  String? get deviceName => _deviceName;
  int? get signalStrength => _signalStrength;

  Stream<GoveeSensorReading> get readings => _readingsController.stream;

  GoveeService() {
    _checkBluetoothAvailability();
  }

  Future<void> _checkBluetoothAvailability() async {
    try {
      _isAvailable =
          await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;
    } catch (e) {
      _isAvailable = false;
    }
  }

  Future<void> startScan() async {
    if (!isAvailable) return;
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.platformName.startsWith('Govee')) {
            _parseGoveeAdvertisement(r);
            _isConnected = true;
            _deviceName = r.device.platformName;
            _signalStrength = r.rssi;
            notifyListeners();
            break; // Use first found Govee device
          }
        }
      });
    } catch (e) {
      // Silent error logging - degrade gracefully
      _isConnected = false;
    }
  }

  void _parseGoveeAdvertisement(ScanResult result) {
    try {
      final manufacturerData = result.advertisementData.manufacturerData;
      if (manufacturerData.isEmpty) return;

      // Govee H5075/H5179 format: temp and humidity in manufacturer data
      // Parse temperature and humidity from bytes
      for (var data in manufacturerData.values) {
        if (data.length >= 6) {
          // Temperature in °F (Govee sends in °C, convert to °F)
          final tempC = (data[4] & 0xFF) + (data[3] & 0x0F) / 10.0;
          final tempF = (tempC * 9 / 5) + 32;

          // Humidity percentage
          final humidity = (data[5] & 0xFF).toDouble();

          _readingsController.add(
            GoveeSensorReading(
              temperatureFahrenheit: tempF,
              humidity: humidity,
              timestamp: DateTime.now(),
            ),
          );
          break;
        }
      }
    } catch (e) {
      // Silent error - degrade gracefully
    }
  }

  Future<void> stopScan() async {
    if (!isAvailable) return;
    try {
      await FlutterBluePlus.stopScan();
      _isConnected = false;
      _deviceName = null;
      _signalStrength = null;
    } catch (e) {
      // Silent error logging
    }
  }

  void dispose() {
    _readingsController.close();
  }

  void notifyListeners() {
    // For use with ChangeNotifier
  }
}
