import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class GoveeSensorReading {
  final double? temperatureFahrenheit;
  final double? humidity;
  final int? batteryPercent;
  final DateTime timestamp;

  GoveeSensorReading({
    this.temperatureFahrenheit,
    this.humidity,
    this.batteryPercent,
    required this.timestamp,
  });
}

class DiscoveredGoveeDevice {
  final String remoteId;
  final String name;
  final int? rssi;
  final DateTime lastSeen;
  final BluetoothDevice device;

  const DiscoveredGoveeDevice({
    required this.remoteId,
    required this.name,
    this.rssi,
    required this.lastSeen,
    required this.device,
  });
}

class GoveeService extends ChangeNotifier {
  static const Duration _scanTimeout = Duration(minutes: 30);
  static const Duration _discoveryTimeout = Duration(seconds: 8);
  static const Duration _gattPollInterval = Duration(seconds: 5);
  static const Duration _reconnectScanDelay = Duration(seconds: 2);
  static const int _maxDiagnosticEntries = 120;
  static const int _goveeManufacturerId = 0xEC88;
  static const int _appleManufacturerId = 0x004C;
  static const int _microsoftManufacturerId = 0x0006;
  static const String _goveeDeviceCharacteristicUuid =
      '494e5445-4c4c-495f-524f-434b535f2011';
  static const String _goveeCommandCharacteristicUuid =
      '494e5445-4c4c-495f-524f-434b535f2012';
  static const String _goveeDataCharacteristicUuid =
      '494e5445-4c4c-495f-524f-434b535f2013';
  static const String _sigTemperatureMeasurementUuid = '2a1c';
  static const String _sigTemperatureUuid = '2a6e';
  static const String _sigHumidityUuid = '2a6f';

  bool _isAvailable = false;
  bool _isConnected = false;
  bool _isGattConnected = false;
  bool _isGattConnecting = false;
  bool _isScanning = false;
  bool? _isBluetoothSupported;
  String? _deviceName;
  String? _deviceId;
  int? _signalStrength;
  DateTime? _lastSeenAt;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _goveeDeviceCharacteristic;
  GoveeSensorReading? _latestReading;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<bool>? _scanStateSubscription;
  final List<StreamSubscription<List<int>>> _gattNotificationSubscriptions =
      <StreamSubscription<List<int>>>[];
  Timer? _discoveryTimeoutTimer;
  Timer? _gattPollTimer;
  Timer? _reconnectScanTimer;
  int _gattPollCount = 0;
  bool _manualDisconnectRequested = false;
  bool _autoReconnectEnabled = false;
  String? _preferredDeviceId;
  final Map<String, DiscoveredGoveeDevice> _discoveredGoveeDevices = {};
  Future<bool>? _supportCheck;
  final Set<String> _debugLoggedScanIds = <String>{};
  final List<String> _diagnostics = <String>[];
  final StreamController<GoveeSensorReading> _readingsController =
      StreamController<GoveeSensorReading>.broadcast();

  bool get isAvailable => _isAvailable;
  bool get isConnected => _isConnected;
  bool get isGattConnected => _isGattConnected;
  bool get isGattConnecting => _isGattConnecting;
  bool get isScanning => _isScanning;
  String? get deviceName => _deviceName;
  String? get deviceId => _deviceId;
  int? get signalStrength => _signalStrength;
  DateTime? get lastSeenAt => _lastSeenAt;
  GoveeSensorReading? get latestReading => _latestReading;
  List<String> get diagnostics => List.unmodifiable(_diagnostics);

  List<DiscoveredGoveeDevice> get discoveredGoveeDevices =>
      List.unmodifiable(_discoveredGoveeDevices.values);

  Stream<GoveeSensorReading> get readings => _readingsController.stream;

  bool _bleInitialized = false;

  GoveeService();

  void _ensureBleInitialized() {
    if (_bleInitialized) return;
    _bleInitialized = true;
    _refreshAvailability();
    _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
      final available = state == BluetoothAdapterState.on;
      if (_isAvailable == available) return;
      _isAvailable = available;
      _addDiagnostic('Adapter state: ${state.name}', notify: false);
      if (!available) {
        _isConnected = false;
        _isGattConnected = false;
        _isGattConnecting = false;
        _isScanning = false;
        _stopGattPolling();
        _reconnectScanTimer?.cancel();
      }
      notifyListeners();
    });
    _scanStateSubscription = FlutterBluePlus.isScanning.listen((isScanning) {
      if (_isScanning == isScanning) return;
      _isScanning = isScanning;
      if (!isScanning) {
        _discoveryTimeoutTimer?.cancel();
      }
      _addDiagnostic(
        isScanning ? 'Scan started' : 'Scan stopped',
        notify: false,
      );
      notifyListeners();
    });
  }

  Future<void> _refreshAvailability() async {
    try {
      _isAvailable =
          await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;
    } catch (_) {
      _isAvailable = false;
    }
    notifyListeners();
  }

  Future<void> startScan({
    Duration timeout = _scanTimeout,
    Duration discoveryTimeout = _discoveryTimeout,
  }) async {
    _ensureBleInitialized();
    if (!await _ensureBluetoothSupported()) {
      return;
    }
    if (!_isAvailable) {
      _addDiagnostic('Bluetooth adapter is not ready');
      return;
    }
    if (_isScanning) {
      if (!_isConnected) {
        _startDiscoveryTimeout(discoveryTimeout);
      }
      return;
    }
    try {
      await _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.onScanResults.listen(_handleResults);
      _isScanning = true;
      _reconnectScanTimer?.cancel();
      _manualDisconnectRequested = false;
      _addDiagnostic('Scanning for Govee advertisements');
      notifyListeners();
      _startDiscoveryTimeout(discoveryTimeout);
      await FlutterBluePlus.startScan(
        timeout: timeout,
        continuousUpdates: true,
        oneByOne: true,
        androidLegacy: true,
        androidUsesFineLocation: true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Govee scan failed: $e');
      _addDiagnostic('Scan failed: $e');
      _isConnected = false;
      _isScanning = false;
      _discoveryTimeoutTimer?.cancel();
      notifyListeners();
    }
  }

  Future<bool> _ensureBluetoothSupported() async {
    final known = _isBluetoothSupported;
    if (known != null) return known;

    final pending = _supportCheck;
    if (pending != null) return pending;

    final check = () async {
      try {
        final supported = await FlutterBluePlus.isSupported;
        _isBluetoothSupported = supported;
        if (!supported) {
          _isAvailable = false;
          _addDiagnostic('Bluetooth is not supported on this device');
        }
        return supported;
      } catch (e) {
        if (kDebugMode) debugPrint('Govee support check failed: $e');
        _isAvailable = false;
        _addDiagnostic('Bluetooth support check failed: $e');
        return false;
      } finally {
        _supportCheck = null;
      }
    }();
    _supportCheck = check;
    return check;
  }

  Future<void> restartScan() async {
    _ensureBleInitialized();
    await stopScan();
    await startScan();
  }

  void _startDiscoveryTimeout(Duration discoveryTimeout) {
    _discoveryTimeoutTimer?.cancel();
    _discoveryTimeoutTimer = Timer(discoveryTimeout, () {
      unawaited(_handleDiscoveryTimeout());
    });
  }

  Future<void> _handleDiscoveryTimeout() async {
    if (!_isScanning || _isConnected || _device != null) return;
    if (kDebugMode) {
      debugPrint('Govee discovery timed out after $_discoveryTimeout');
    }
    _addDiagnostic('Discovery timed out after ${_discoveryTimeout.inSeconds}s');
    await stopScan();
  }

  void _handleResults(List<ScanResult> results) {
    BluetoothDevice? deviceCandidate;
    String? deviceNameCandidate;
    String? deviceIdCandidate;
    int? signalCandidate;
    GoveeSensorReading? readingCandidate;

    for (final result in results) {
      if (!_isGoveeDevice(result)) {
        _logScanCandidate(result);
        continue;
      }

      final remoteId = result.device.remoteId.str;
      final name = _displayName(result);
      _discoveredGoveeDevices[remoteId] = DiscoveredGoveeDevice(
        remoteId: remoteId,
        name: name,
        rssi: result.rssi,
        lastSeen: DateTime.now(),
        device: result.device,
      );

      if (_device != null) continue;

      if (_preferredDeviceId != null && remoteId != _preferredDeviceId) {
        continue;
      }

      deviceCandidate ??= result.device;
      deviceNameCandidate ??= name;
      deviceIdCandidate ??= remoteId;
      signalCandidate ??= result.rssi;
      readingCandidate ??= _parseGoveeAdvertisement(result);
    }

    if (deviceCandidate == null) {
      notifyListeners();
      return;
    }

    _isConnected = true;
    _deviceName = deviceNameCandidate;
    _deviceId = deviceIdCandidate;
    _device = deviceCandidate;
    _signalStrength = signalCandidate;
    _lastSeenAt = DateTime.now();
    _discoveryTimeoutTimer?.cancel();
    final reading = readingCandidate;
    _addDiagnostic(
      'Found $_deviceName RSSI $_signalStrength; '
      '${reading == null ? 'advertisement had no reading' : _readingSummary(reading)}',
    );
    if (reading != null) {
      _publishReading(reading);
    }
    if (reading?.temperatureFahrenheit == null || reading?.humidity == null) {
      unawaited(connectDevice());
    }
    notifyListeners();
  }

  Future<void> connectDevice() async {
    _ensureBleInitialized();
    final device = _device;
    if (device == null || _isGattConnected || _isGattConnecting) return;
    _isGattConnecting = true;
    _manualDisconnectRequested = false;
    _addDiagnostic('Connecting GATT to ${_deviceName ?? 'Govee sensor'}');
    notifyListeners();
    try {
      await FlutterBluePlus.stopScan();
      _isScanning = false;
      await _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        final connected = state == BluetoothConnectionState.connected;
        _isGattConnected = connected;
        _addDiagnostic('GATT state: ${state.name}', notify: false);
        if (!connected) {
          _stopGattPolling();
          unawaited(_cancelGattNotificationSubscriptions());
          _goveeDeviceCharacteristic = null;
          _scheduleReconnectScan();
        }
        notifyListeners();
      });
      await device.connect(timeout: const Duration(seconds: 8));
      _isGattConnected = true;
      _addDiagnostic('GATT connected');
      notifyListeners();
      await _discoverAndRead(device);
    } catch (e) {
      if (kDebugMode) debugPrint('Govee connect failed: $e');
      _addDiagnostic('GATT connect failed: $e');
      _isGattConnected = false;
    } finally {
      _isGattConnecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnectDevice() async {
    _ensureBleInitialized();
    final device = _device;
    if (device == null) return;
    try {
      _manualDisconnectRequested = true;
      _reconnectScanTimer?.cancel();
      _stopGattPolling();
      await _cancelGattNotificationSubscriptions();
      _addDiagnostic('Manual GATT disconnect requested');
      await device.disconnect();
    } catch (e) {
      if (kDebugMode) debugPrint('Govee disconnect failed: $e');
      _addDiagnostic('GATT disconnect failed: $e');
    } finally {
      _isGattConnected = false;
      notifyListeners();
    }
  }

  void setAutoReconnectEnabled(bool enabled) {
    _autoReconnectEnabled = enabled;
  }

  void setPreferredDeviceId(String? deviceId) {
    _preferredDeviceId = deviceId;
  }

  Future<void> initializeBle() async {
    _ensureBleInitialized();
    await _refreshAvailability();
  }

  Future<void> selectDevice(String remoteId) async {
    _ensureBleInitialized();
    final discovered = _discoveredGoveeDevices[remoteId];
    if (discovered == null) return;

    try {
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      _discoveryTimeoutTimer?.cancel();
      _reconnectScanTimer?.cancel();
      _stopGattPolling();
      await _cancelGattNotificationSubscriptions();
      _isScanning = false;
      _isConnected = false;
      _isGattConnected = false;
      _goveeDeviceCharacteristic = null;

      _device = discovered.device;
      _deviceName = discovered.name;
      _deviceId = remoteId;
      _preferredDeviceId = remoteId;
      _signalStrength = discovered.rssi;
      _lastSeenAt = discovered.lastSeen;
      _isConnected = true;
      _manualDisconnectRequested = false;

      notifyListeners();
      await connectDevice();
    } catch (e) {
      _addDiagnostic('Device selection failed: $e');
      notifyListeners();
    }
  }

  void _scheduleReconnectScan() {
    if (_manualDisconnectRequested ||
        !_isAvailable ||
        !_isConnected ||
        _isScanning ||
        !_autoReconnectEnabled) {
      return;
    }
    _reconnectScanTimer?.cancel();
    _addDiagnostic(
      'GATT disconnected; reconnecting in ${_reconnectScanDelay.inSeconds}s',
      notify: false,
    );
    _reconnectScanTimer = Timer(_reconnectScanDelay, () {
      _reconnectScanTimer = null;
      if (_manualDisconnectRequested ||
          !_isAvailable ||
          !_isConnected ||
          _isGattConnected ||
          _isGattConnecting) {
        return;
      }
      // Device already known from BLE advertisement — connect directly.
      // Only fall back to scan if device reference was cleared.
      if (_device != null) {
        unawaited(connectDevice());
      } else if (!_isScanning) {
        unawaited(startScan());
      }
    });
  }

  Future<void> _discoverAndRead(BluetoothDevice device) async {
    try {
      await _cancelGattNotificationSubscriptions();
      final services = await device.discoverServices();
      final goveeCharacteristics = <String, BluetoothCharacteristic>{};
      _addDiagnostic('Discovered ${services.length} BLE services');
      for (final service in services) {
        if (kDebugMode) {
          debugPrint('Govee service ${service.uuid.str}');
        }
        for (final characteristic in service.characteristics) {
          final uuid = characteristic.uuid.str.toLowerCase();
          if (_isGoveeCharacteristic(uuid)) {
            goveeCharacteristics[uuid] = characteristic;
            if (uuid == _goveeDeviceCharacteristicUuid) {
              _goveeDeviceCharacteristic = characteristic;
            }
          }
          if (kDebugMode) {
            debugPrint(
              'Govee characteristic ${characteristic.uuid.str} '
              'props read=${characteristic.properties.read} '
              'notify=${characteristic.properties.notify} '
              'write=${characteristic.properties.write} '
              'writeWithoutResponse=${characteristic.properties.writeWithoutResponse}',
            );
          }
          if (!_isSupportedGattCharacteristic(uuid)) {
            continue;
          }
          if (characteristic.properties.read) {
            try {
              final value = await characteristic.read();
              if (kDebugMode) {
                debugPrint(
                  'Govee read ${characteristic.uuid.str}: ${_hex(value)}',
                );
              }
              _parseCharacteristicValue(uuid, value);
            } catch (e) {
              if (kDebugMode) {
                debugPrint('Govee read failed ${characteristic.uuid.str}: $e');
              }
              _addDiagnostic('Read failed ${characteristic.uuid.str}: $e');
            }
          }
          if (characteristic.properties.notify) {
            try {
              await characteristic.setNotifyValue(true);
              _addDiagnostic(
                'Notifications enabled ${characteristic.uuid.str}',
              );
              final subscription = characteristic.onValueReceived.listen((
                value,
              ) {
                if (kDebugMode) {
                  debugPrint(
                    'Govee notify ${characteristic.uuid.str}: ${_hex(value)}',
                  );
                }
                _parseCharacteristicValue(uuid, value);
              });
              _gattNotificationSubscriptions.add(subscription);
            } catch (e) {
              if (kDebugMode) {
                debugPrint(
                  'Govee notify failed ${characteristic.uuid.str}: $e',
                );
              }
              _addDiagnostic('Notify failed ${characteristic.uuid.str}: $e');
            }
          }
        }
      }
      await _requestGoveeGattReadings(goveeCharacteristics);
      _startGattPolling();
    } catch (e) {
      if (kDebugMode) debugPrint('Govee discover services failed: $e');
      _addDiagnostic('Service discovery failed: $e');
    }
  }

  void _parseCharacteristicValue(String uuid, List<int> value) {
    final standardReading = _parseStandardGattValue(uuid, value);
    if (standardReading != null) {
      _publishReading(standardReading);
      return;
    }

    final commandResponse = _parseGoveeCommandResponse(value);
    if (commandResponse != null) {
      _addDiagnostic(
        'Parsed GATT response: ${_readingSummary(commandResponse)}',
        notify: false,
      );
      _publishReading(commandResponse);
      return;
    }
    final h5051 = _parseH5051(value);
    if (h5051 == null) return;
    _addDiagnostic(
      'Parsed H5051 value: ${_readingSummary(h5051)}',
      notify: false,
    );
    _publishReading(h5051);
  }

  GoveeSensorReading? _parseStandardGattValue(String uuid, List<int> data) {
    if (uuid == _sigTemperatureUuid && data.length >= 2) {
      final tempC = _signedInt16(data[0], data[1]) / 100.0;
      return GoveeSensorReading(
        temperatureFahrenheit: _celsiusToFahrenheit(tempC),
        timestamp: DateTime.now(),
      );
    }

    if (uuid == _sigHumidityUuid && data.length >= 2) {
      final humidityRaw = (data[0] & 0xFF) | ((data[1] & 0xFF) << 8);
      return GoveeSensorReading(
        humidity: humidityRaw / 100.0,
        timestamp: DateTime.now(),
      );
    }

    if (uuid == _sigTemperatureMeasurementUuid && data.length >= 5) {
      final flags = data[0] & 0xFF;
      final temperature = _decodeBluetoothFloat(data, offset: 1);
      if (temperature == null) return null;
      final isFahrenheit = (flags & 0x01) != 0;
      return GoveeSensorReading(
        temperatureFahrenheit: isFahrenheit
            ? temperature
            : _celsiusToFahrenheit(temperature),
        timestamp: DateTime.now(),
      );
    }

    return null;
  }

  bool _isGoveeDevice(ScanResult result) {
    final names = <String>[
      result.device.platformName,
      result.advertisementData.advName,
    ].where((name) => name.isNotEmpty).map((name) => name.toLowerCase());

    if (names.any(
      (name) =>
          name.startsWith('govee') ||
          name.startsWith('h5051') ||
          name.startsWith('gvh') ||
          name.contains('govee') ||
          name.contains('h50'),
    )) {
      return true;
    }

    return _hasGoveeAdvertisement(result);
  }

  String _displayName(ScanResult result) {
    if (result.device.platformName.isNotEmpty) {
      return result.device.platformName;
    }
    if (result.advertisementData.advName.isNotEmpty) {
      return result.advertisementData.advName;
    }
    return 'Govee sensor';
  }

  bool _hasGoveeAdvertisement(ScanResult result) {
    final localName = [
      result.device.platformName,
      result.advertisementData.advName,
    ].where((name) => name.isNotEmpty).join(' ');

    for (final entry in result.advertisementData.manufacturerData.entries) {
      final manufacturerId = entry.key;
      if (manufacturerId == _appleManufacturerId ||
          manufacturerId == _microsoftManufacturerId) {
        continue;
      }

      final data = entry.value;
      if (_parseH5051(data) != null ||
          _parseH5051ShortAdvert(data) != null ||
          _parseLegacyGoveeAdvertisement(
                data,
                manufacturerId: manufacturerId,
                localName: localName,
              ) !=
              null ||
          _parseGoveeCombinedAdvert(
                data,
                manufacturerId: manufacturerId,
                localName: localName,
              ) !=
              null) {
        return true;
      }
    }

    for (final entry in result.advertisementData.serviceData.entries) {
      final data = entry.value;
      final serviceId = entry.key.str.toLowerCase();
      final manufacturerId = serviceId.contains('ec88')
          ? _goveeManufacturerId
          : 0;
      if (_parseH5051(data) != null ||
          _parseH5051ShortAdvert(data) != null ||
          _parseGoveeCombinedAdvert(
                data,
                manufacturerId: manufacturerId,
                localName: localName,
              ) !=
              null ||
          _parseLegacyGoveeAdvertisement(
                data,
                manufacturerId: manufacturerId,
                localName: localName,
              ) !=
              null) {
        return true;
      }
    }
    return false;
  }

  GoveeSensorReading? _parseGoveeAdvertisement(ScanResult result) {
    try {
      _logAdvertisement(result);

      final localName = _displayName(result);
      for (final entry in result.advertisementData.manufacturerData.entries) {
        final manufacturerId = entry.key;
        final data = entry.value;
        if (manufacturerId == _appleManufacturerId ||
            manufacturerId == _microsoftManufacturerId) {
          continue;
        }

        final h5051 = _parseH5051(data);
        if (h5051 != null) return h5051;
        final combined = _parseGoveeCombinedAdvert(
          data,
          manufacturerId: manufacturerId,
          localName: localName,
        );
        if (combined != null) return combined;
        final shortAdvert = _parseH5051ShortAdvert(data);
        if (shortAdvert != null) return shortAdvert;
        final legacy = _parseLegacyGoveeAdvertisement(
          data,
          manufacturerId: manufacturerId,
          localName: localName,
        );
        if (legacy != null) return legacy;
      }

      for (final entry in result.advertisementData.serviceData.entries) {
        final serviceId = entry.key.str.toLowerCase();
        final manufacturerId = serviceId.contains('ec88')
            ? _goveeManufacturerId
            : 0;
        final data = entry.value;

        final h5051 = _parseH5051(data);
        if (h5051 != null) return h5051;
        final combined = _parseGoveeCombinedAdvert(
          data,
          manufacturerId: manufacturerId,
          localName: localName,
        );
        if (combined != null) return combined;
        final shortAdvert = _parseH5051ShortAdvert(data);
        if (shortAdvert != null) return shortAdvert;
        final legacy = _parseLegacyGoveeAdvertisement(
          data,
          manufacturerId: manufacturerId,
          localName: localName,
        );
        if (legacy != null) return legacy;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Govee advertisement parse failed: $e');
    }
    return null;
  }

  GoveeSensorReading? _parseH5051ShortAdvert(List<int> data) {
    if (data.length != 7 || data[0] != 0x10 || data[1] != 0x05) return null;
    final tempRaw = _signedInt16(data[2], data[3]);
    final tempF = tempRaw / 100.0;
    if (tempF < -40 || tempF > 160) return null;
    return GoveeSensorReading(
      temperatureFahrenheit: tempF,
      timestamp: DateTime.now(),
    );
  }

  GoveeSensorReading? _parseH5051(List<int> data) {
    if (data.length != 9) return null;
    final tempRaw = _signedInt16(data[1], data[2]);
    final humidityRaw = (data[3] & 0xFF) | ((data[4] & 0xFF) << 8);
    final tempF = (tempRaw / 100.0 * 9.0 / 5.0) + 32.0;
    final humidity = humidityRaw / 100.0;
    final battery = data[5] & 0xFF;
    if (!_isValidReading(tempF, humidity)) return null;
    return GoveeSensorReading(
      temperatureFahrenheit: tempF,
      humidity: humidity,
      batteryPercent: battery.clamp(0, 100).toInt(),
      timestamp: DateTime.now(),
    );
  }

  GoveeSensorReading? _parseGoveeCombinedAdvert(
    List<int> data, {
    required int manufacturerId,
    required String localName,
  }) {
    if (data.length != 6) return null;
    if (manufacturerId != _goveeManufacturerId &&
        !localName.toLowerCase().contains('govee') &&
        !localName.toLowerCase().contains('h50')) {
      return null;
    }

    final decoded = _decodePackedTempHumidity(data[1], data[2], data[3]);
    if (decoded == null) return null;
    final tempF = _celsiusToFahrenheit(decoded.temperatureCelsius);
    final humidity = decoded.humidity;
    final battery = data[4] & 0x7F;
    if (!_isValidReading(tempF, humidity)) return null;
    return GoveeSensorReading(
      temperatureFahrenheit: tempF,
      humidity: humidity,
      batteryPercent: battery.clamp(0, 100).toInt(),
      timestamp: DateTime.now(),
    );
  }

  GoveeSensorReading? _parseLegacyGoveeAdvertisement(
    List<int> data, {
    required int manufacturerId,
    required String localName,
  }) {
    final lowerName = localName.toLowerCase();
    final looksLikeGovee =
        manufacturerId == _goveeManufacturerId ||
        lowerName.contains('govee') ||
        lowerName.contains('h50');
    if (!looksLikeGovee || data.length < 6) return null;

    final tempC = (data[4] & 0xFF) + ((data[3] & 0x0F) / 10.0);
    final tempF = _celsiusToFahrenheit(tempC);
    final humidity = (data[5] & 0xFF).toDouble();
    if (!_isValidReading(tempF, humidity)) return null;
    return GoveeSensorReading(
      temperatureFahrenheit: tempF,
      humidity: humidity,
      timestamp: DateTime.now(),
    );
  }

  GoveeSensorReading? _parseGoveeCommandResponse(List<int> data) {
    return GoveeService.parseGoveeCommandResponseForTesting(data);
  }

  @visibleForTesting
  static GoveeSensorReading? parseGoveeCommandResponseForTesting(
    List<int> data,
  ) {
    if (data.length < 3 || data[0] != 0xAA) return null;
    if (!_hasValidGoveeChecksum(data)) return null;

    final command = data[1] & 0xFF;
    if ((command == 0x01 || command == 0x0A) && data.length >= 6) {
      if (_hasEmptyGoveePayload(data)) return null;
      final tempRaw = _signedInt16(data[2], data[3]);
      final humidityRaw = (data[4] & 0xFF) | ((data[5] & 0xFF) << 8);
      final tempF = _celsiusToFahrenheit(tempRaw / 100.0);
      final humidity = humidityRaw / 100.0;
      final battery = command == 0x01 && data.length >= 7
          ? data[6] & 0xFF
          : null;
      if (!_isValidReading(tempF, humidity)) return null;
      return GoveeSensorReading(
        temperatureFahrenheit: tempF,
        humidity: humidity,
        batteryPercent: battery?.clamp(0, 100).toInt(),
        timestamp: DateTime.now(),
      );
    }

    if (command == 0x08 && data.length >= 3) {
      final battery = data[2] & 0xFF;
      if (battery > 100) return null;
      return GoveeSensorReading(
        batteryPercent: battery,
        timestamp: DateTime.now(),
      );
    }

    return null;
  }

  @visibleForTesting
  static GoveeSensorReading? parseH5051ForTesting(List<int> data) {
    if (data.length != 9) return null;
    final tempRaw = _signedInt16(data[1], data[2]);
    final humidityRaw = (data[3] & 0xFF) | ((data[4] & 0xFF) << 8);
    final tempF = (tempRaw / 100.0 * 9.0 / 5.0) + 32.0;
    final humidity = humidityRaw / 100.0;
    final battery = data[5] & 0xFF;
    if (!_isValidReading(tempF, humidity)) return null;
    return GoveeSensorReading(
      temperatureFahrenheit: tempF,
      humidity: humidity,
      batteryPercent: battery.clamp(0, 100).toInt(),
      timestamp: DateTime.now(),
    );
  }

  @visibleForTesting
  static GoveeSensorReading? parseH5051ShortAdvertForTesting(List<int> data) {
    if (data.length != 7 || data[0] != 0x10 || data[1] != 0x05) return null;
    final tempRaw = _signedInt16(data[2], data[3]);
    final tempF = tempRaw / 100.0;
    if (tempF < -40 || tempF > 160) return null;
    return GoveeSensorReading(
      temperatureFahrenheit: tempF,
      timestamp: DateTime.now(),
    );
  }

  @visibleForTesting
  static GoveeSensorReading? parseGoveeCombinedAdvertForTesting(
    List<int> data, {
    required int manufacturerId,
  }) {
    if (data.length != 6) return null;
    if (manufacturerId != _goveeManufacturerId) return null;

    final decoded = _decodePackedTempHumidityStatic(data[1], data[2], data[3]);
    if (decoded == null) return null;
    final tempF = _celsiusToFahrenheit(decoded.temperatureCelsius);
    final humidity = decoded.humidity;
    final battery = data[4] & 0x7F;
    if (!_isValidReading(tempF, humidity)) return null;
    return GoveeSensorReading(
      temperatureFahrenheit: tempF,
      humidity: humidity,
      batteryPercent: battery.clamp(0, 100).toInt(),
      timestamp: DateTime.now(),
    );
  }

  static int _signedInt16(int lowByte, int highByte) {
    final unsigned = (lowByte & 0xFF) | ((highByte & 0xFF) << 8);
    return unsigned >= 0x8000 ? unsigned - 0x10000 : unsigned;
  }

  _PackedTempHumidity? _decodePackedTempHumidity(
    int highByte,
    int midByte,
    int lowByte,
  ) {
    var raw =
        ((highByte & 0xFF) << 16) | ((midByte & 0xFF) << 8) | (lowByte & 0xFF);
    final isNegative = (raw & 0x800000) != 0;
    raw &= 0x7FFFFF;
    var temperatureC = (raw ~/ 1000) / 10.0;
    if (isNegative) temperatureC = -temperatureC;
    final humidity = (raw % 1000) / 10.0;
    return _PackedTempHumidity(temperatureC, humidity);
  }

  static _PackedTempHumidity? _decodePackedTempHumidityStatic(
    int highByte,
    int midByte,
    int lowByte,
  ) {
    var raw =
        ((highByte & 0xFF) << 16) | ((midByte & 0xFF) << 8) | (lowByte & 0xFF);
    final isNegative = (raw & 0x800000) != 0;
    raw &= 0x7FFFFF;
    var temperatureC = (raw ~/ 1000) / 10.0;
    if (isNegative) temperatureC = -temperatureC;
    final humidity = (raw % 1000) / 10.0;
    return _PackedTempHumidity(temperatureC, humidity);
  }

  static double _celsiusToFahrenheit(double temperatureCelsius) {
    return (temperatureCelsius * 9.0 / 5.0) + 32.0;
  }

  double? _decodeBluetoothFloat(List<int> data, {required int offset}) {
    if (data.length < offset + 4) return null;
    var mantissa =
        (data[offset] & 0xFF) |
        ((data[offset + 1] & 0xFF) << 8) |
        ((data[offset + 2] & 0xFF) << 16);
    if ((mantissa & 0x800000) != 0) {
      mantissa -= 0x1000000;
    }

    var exponent = data[offset + 3] & 0xFF;
    if ((exponent & 0x80) != 0) {
      exponent -= 0x100;
    }

    return mantissa * math.pow(10, exponent).toDouble();
  }

  static bool _hasValidGoveeChecksum(List<int> data) {
    if (data.length < 2) return false;
    var checksum = 0;
    for (var i = 0; i < data.length - 1; i += 1) {
      checksum ^= data[i] & 0xFF;
    }
    return checksum == (data.last & 0xFF);
  }

  static bool _hasEmptyGoveePayload(List<int> data) {
    if (data.length <= 3) return true;
    for (var i = 2; i < data.length - 1; i += 1) {
      if ((data[i] & 0xFF) != 0) return false;
    }
    return true;
  }

  bool _isGoveeCharacteristic(String uuid) {
    return uuid == _goveeDeviceCharacteristicUuid ||
        uuid == _goveeCommandCharacteristicUuid ||
        uuid == _goveeDataCharacteristicUuid;
  }

  bool _isSupportedGattCharacteristic(String uuid) {
    return _isGoveeCharacteristic(uuid) ||
        uuid == _sigTemperatureMeasurementUuid ||
        uuid == _sigTemperatureUuid ||
        uuid == _sigHumidityUuid;
  }

  Future<void> _requestGoveeGattReadings(
    Map<String, BluetoothCharacteristic> characteristics,
  ) async {
    final deviceCharacteristic =
        characteristics[_goveeDeviceCharacteristicUuid];

    if (deviceCharacteristic != null && _canWrite(deviceCharacteristic)) {
      await _writeGoveeCommand(deviceCharacteristic, 0x0A);
      await _writeGoveeCommand(deviceCharacteristic, 0x08);
    } else {
      _addDiagnostic('No writable Govee device characteristic found');
    }
  }

  Future<void> requestLiveReading() async {
    _ensureBleInitialized();
    final characteristic = _goveeDeviceCharacteristic;
    if (characteristic != null &&
        _isGattConnected &&
        _canWrite(characteristic)) {
      await _pollGattReading(includeBattery: true);
      return;
    }

    if (_device != null) {
      await connectDevice();
      return;
    }

    await startScan();
  }

  Future<List<GoveeSensorReading>> syncHistory({
    required DateTime startedAt,
    required DateTime endedAt,
  }) async {
    _addDiagnostic(
      'Device history sync is not available in this Govee integration yet',
    );
    return const [];
  }

  Future<void> _writeGoveeCommand(
    BluetoothCharacteristic characteristic,
    int command,
  ) async {
    final payload = _buildGoveeCommand(0xAA, command);
    try {
      await characteristic.write(
        payload,
        withoutResponse:
            !characteristic.properties.write &&
            characteristic.properties.writeWithoutResponse,
      );
      if (kDebugMode) {
        debugPrint('Govee write ${characteristic.uuid.str}: ${_hex(payload)}');
      }
      _addDiagnostic(
        'Write command 0x${command.toRadixString(16).padLeft(2, '0')}',
        notify: false,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Govee write failed ${characteristic.uuid.str}: $e');
      }
      _addDiagnostic(
        'Write failed 0x${command.toRadixString(16).padLeft(2, '0')}: $e',
      );
    }
  }

  List<int> _buildGoveeCommand(int prefix, int command) {
    final payload = <int>[prefix & 0xFF, command & 0xFF];
    while (payload.length < 19) {
      payload.add(0);
    }
    var checksum = 0;
    for (final byte in payload) {
      checksum ^= byte & 0xFF;
    }
    payload.add(checksum);
    return payload;
  }

  bool _canWrite(BluetoothCharacteristic characteristic) {
    return characteristic.properties.write ||
        characteristic.properties.writeWithoutResponse;
  }

  void _publishReading(GoveeSensorReading reading) {
    final previous = _latestReading;
    final merged = GoveeSensorReading(
      temperatureFahrenheit:
          reading.temperatureFahrenheit ?? previous?.temperatureFahrenheit,
      humidity: reading.humidity ?? previous?.humidity,
      batteryPercent: reading.batteryPercent ?? previous?.batteryPercent,
      timestamp: reading.timestamp,
    );
    _latestReading = merged;
    _addDiagnostic(
      'Published reading: ${_readingSummary(merged)}',
      notify: false,
    );
    if (merged.temperatureFahrenheit != null && merged.humidity != null) {
      _readingsController.add(merged);
    }
    notifyListeners();
  }

  void _startGattPolling() {
    final characteristic = _goveeDeviceCharacteristic;
    if (characteristic == null || !_canWrite(characteristic)) return;
    _gattPollTimer?.cancel();
    _gattPollCount = 0;
    _addDiagnostic(
      'Started GATT polling every ${_gattPollInterval.inSeconds}s',
    );
    _gattPollTimer = Timer.periodic(_gattPollInterval, (_) {
      unawaited(_pollGattReading());
    });
  }

  Future<void> _pollGattReading({bool includeBattery = false}) async {
    final characteristic = _goveeDeviceCharacteristic;
    if (characteristic == null ||
        !_isGattConnected ||
        !_canWrite(characteristic)) {
      return;
    }
    _gattPollCount += 1;
    await _writeGoveeCommand(characteristic, 0x0A);
    if (includeBattery || _gattPollCount % 12 == 0) {
      await _writeGoveeCommand(characteristic, 0x08);
    }
  }

  void _stopGattPolling() {
    _gattPollTimer?.cancel();
    _gattPollTimer = null;
    _gattPollCount = 0;
  }

  Future<void> _cancelGattNotificationSubscriptions() async {
    if (_gattNotificationSubscriptions.isEmpty) return;
    final subscriptions = List<StreamSubscription<List<int>>>.from(
      _gattNotificationSubscriptions,
    );
    _gattNotificationSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  void _logAdvertisement(ScanResult result) {
    if (!kDebugMode) return;
    debugPrint(
      'Govee BLE advertisement name=${_displayName(result)} '
      'id=${result.device.remoteId.str} rssi=${result.rssi} '
      '${_advertisementSummary(result)}',
    );
  }

  void _logScanCandidate(ScanResult result) {
    if (!kDebugMode) return;
    if (_debugLoggedScanIds.length >= 25) return;

    final id = result.device.remoteId.str;
    if (!_debugLoggedScanIds.add(id)) return;
    final name = _displayName(result);
    debugPrint(
      'BLE scan candidate ignored name=$name id=$id rssi=${result.rssi} '
      '${_advertisementSummary(result)}',
    );
  }

  String _advertisementSummary(ScanResult result) {
    final serviceData = result.advertisementData.serviceData.map(
      (key, value) => MapEntry(key.str, _hex(value)),
    );
    final manufacturerData = result.advertisementData.manufacturerData.map(
      (key, value) => MapEntry(key.toString(), _hex(value)),
    );
    return 'serviceData=$serviceData manufacturerData=$manufacturerData';
  }

  String _hex(List<int> bytes) {
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
  }

  static bool _isValidReading(double tempF, double humidity) {
    return tempF >= -40 && tempF <= 160 && humidity >= 0 && humidity <= 100;
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      _discoveryTimeoutTimer?.cancel();
      _reconnectScanTimer?.cancel();
      _stopGattPolling();
      await _cancelGattNotificationSubscriptions();
      _isConnected = false;
      _isGattConnected = false;
      _isScanning = false;
      _deviceName = null;
      _deviceId = null;
      _device = null;
      _goveeDeviceCharacteristic = null;
      _signalStrength = null;
      _lastSeenAt = null;
      _discoveredGoveeDevices.clear();
      _addDiagnostic('Stopped and cleared Govee device state');
    } catch (e) {
      if (kDebugMode) debugPrint('Govee stop scan failed: $e');
      _addDiagnostic('Stop scan failed: $e');
    } finally {
      notifyListeners();
    }
  }

  void _addDiagnostic(String message, {bool notify = true}) {
    final now = DateTime.now();
    final timestamp =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    _diagnostics.add('$timestamp  $message');
    if (_diagnostics.length > _maxDiagnosticEntries) {
      _diagnostics.removeRange(0, _diagnostics.length - _maxDiagnosticEntries);
    }
    if (kDebugMode) debugPrint('Govee diagnostic: $message');
    if (notify) notifyListeners();
  }

  String _readingSummary(GoveeSensorReading reading) {
    final parts = <String>[];
    final temp = reading.temperatureFahrenheit;
    final humidity = reading.humidity;
    final battery = reading.batteryPercent;
    if (temp != null) parts.add('${temp.toStringAsFixed(1)}F');
    if (humidity != null) parts.add('${humidity.toStringAsFixed(1)}% RH');
    if (battery != null) parts.add('$battery% battery');
    if (parts.isEmpty) return 'no temp/RH payload';
    return parts.join(', ');
  }

  @override
  void dispose() {
    _adapterSubscription?.cancel();
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _scanStateSubscription?.cancel();
    _discoveryTimeoutTimer?.cancel();
    _reconnectScanTimer?.cancel();
    _stopGattPolling();
    unawaited(_cancelGattNotificationSubscriptions());
    _readingsController.close();
    super.dispose();
  }
}

class _PackedTempHumidity {
  final double temperatureCelsius;
  final double humidity;

  const _PackedTempHumidity(this.temperatureCelsius, this.humidity);
}
