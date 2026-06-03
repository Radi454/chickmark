import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class GoveeSensorReading {
  final double? temperatureFahrenheit;
  final double? humidity;
  final int? batteryPercent;
  final DateTime timestamp;
  final DateTime? bucketStartedAt;
  final DateTime? bucketEndedAt;
  final int rawReadingCount;
  final String source;

  GoveeSensorReading({
    this.temperatureFahrenheit,
    this.humidity,
    this.batteryPercent,
    required this.timestamp,
    this.bucketStartedAt,
    this.bucketEndedAt,
    this.rawReadingCount = 1,
    this.source = 'history_sync',
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

enum _GoveeHistoryProtocol { minuteBack, epochMinute }

class _GoveeHistorySyncRequest {
  final _GoveeHistoryProtocol protocol;
  final List<int> payload;
  final DateTime? baseMinute;
  final int? startMinutesBack;
  final int? endMinutesBack;
  final int? startEpochMinute;
  final int? endEpochMinute;

  const _GoveeHistorySyncRequest({
    required this.protocol,
    required this.payload,
    this.baseMinute,
    this.startMinutesBack,
    this.endMinutesBack,
    this.startEpochMinute,
    this.endEpochMinute,
  });

  String get commandLabel {
    return switch (protocol) {
      _GoveeHistoryProtocol.minuteBack => '0x3301',
      _GoveeHistoryProtocol.epochMinute => 'epoch-minute 0x0000',
    };
  }

  String diagnostic({required bool retry}) {
    final prefix = retry
        ? 'Retried history sync after reconnect'
        : 'History sync requested';
    return switch (protocol) {
      _GoveeHistoryProtocol.minuteBack =>
        '$prefix ${startMinutesBack}m to ${endMinutesBack}m back',
      _GoveeHistoryProtocol.epochMinute =>
        '$prefix epoch-minute window $startEpochMinute to $endEpochMinute',
    };
  }
}

class GoveeService extends ChangeNotifier {
  static const Duration _scanTimeout = Duration(minutes: 30);
  static const Duration _discoveryTimeout = Duration(seconds: 8);
  static const Duration _gattPollInterval = Duration(seconds: 5);
  static const Duration _reconnectScanDelay = Duration(seconds: 2);
  static const Duration _historySyncTimeout = Duration(seconds: 45);
  static const Duration _adapterStateReadyTimeout = Duration(seconds: 2);
  static const int _maxDiagnosticEntries = 120;
  static const int _goveeManufacturerId = 0xEC88;
  static const int _appleManufacturerId = 0x004C;
  static const int _microsoftManufacturerId = 0x0006;
  static const String _goveeServiceUuid =
      '494e5445-4c4c-495f-524f-434b535f2000';
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
  BluetoothCharacteristic? _goveeHistoryControlCharacteristic;
  BluetoothCharacteristic? _goveeHistoryDataCharacteristic;
  GoveeSensorReading? _latestReading;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<bool>? _scanStateSubscription;
  final List<StreamSubscription<List<int>>> _gattNotificationSubscriptions =
      <StreamSubscription<List<int>>>[];
  Timer? _discoveryTimeoutTimer;
  Duration _activeDiscoveryTimeout = _discoveryTimeout;
  Timer? _gattPollTimer;
  Timer? _reconnectScanTimer;
  int _gattPollCount = 0;
  bool _manualDisconnectRequested = false;
  bool _autoReconnectEnabled = false;
  String? _preferredDeviceId;
  final Map<String, DiscoveredGoveeDevice> _discoveredGoveeDevices = {};
  Future<bool>? _supportCheck;
  Future<void>? _availabilityRefresh;
  final Set<String> _debugLoggedScanIds = <String>{};
  final List<String> _diagnostics = <String>[];
  Future<void>? _gattConnectOperation;
  Future<void>? _gattDiscoveryOperation;
  Completer<List<GoveeSensorReading>>? _historySyncCompleter;
  List<GoveeSensorReading> _historySyncReadings = <GoveeSensorReading>[];
  DateTime? _historySyncBaseMinute;
  DateTime? _historySyncStartedAt;
  DateTime? _historySyncEndedAt;
  int _historySyncPacketCount = 0;
  _GoveeHistoryProtocol _historySyncProtocol = _GoveeHistoryProtocol.minuteBack;
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

  @visibleForTesting
  static String get deviceCommandCharacteristicUuidForTesting =>
      _goveeDeviceCharacteristicUuid;

  @visibleForTesting
  static String get historyWriteCharacteristicUuidForTesting =>
      _goveeCommandCharacteristicUuid;

  @visibleForTesting
  static String get historyResponseCharacteristicUuidForTesting =>
      _goveeCommandCharacteristicUuid;

  @visibleForTesting
  static String get historyDataCharacteristicUuidForTesting =>
      _goveeDataCharacteristicUuid;

  @visibleForTesting
  static bool shouldPollGattForTesting({
    required bool hasCharacteristic,
    required bool isGattConnected,
    required bool canWrite,
    required bool historySyncActive,
  }) {
    return _shouldPollGatt(
      hasCharacteristic: hasCharacteristic,
      isGattConnected: isGattConnected,
      canWrite: canWrite,
      historySyncActive: historySyncActive,
    );
  }

  bool _bleInitialized = false;

  GoveeService();

  void _ensureBleInitialized() {
    if (_bleInitialized) return;
    _bleInitialized = true;
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
        _clearGattCharacteristics();
        _failHistorySync(StateError('Bluetooth adapter turned off'));
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

  Future<void> _ensureNativeBleInitialized() async {
    await _refreshAvailability(waitForKnown: true);
    if (_bleInitialized) return;
    _ensureBleInitialized();
  }

  Future<void> _refreshAvailability({bool waitForKnown = false}) async {
    final pending = _availabilityRefresh;
    if (pending != null) return pending;

    final refresh = () async {
      try {
        final state = waitForKnown
            ? await FlutterBluePlus.adapterState
                  .where((state) => state != BluetoothAdapterState.unknown)
                  .first
                  .timeout(
                    _adapterStateReadyTimeout,
                    onTimeout: () => FlutterBluePlus.adapterStateNow,
                  )
            : await FlutterBluePlus.adapterState.first;
        _isAvailable = state == BluetoothAdapterState.on;
      } catch (_) {
        _isAvailable = false;
      } finally {
        _availabilityRefresh = null;
      }
      notifyListeners();
    }();
    _availabilityRefresh = refresh;
    return refresh;
  }

  Future<void> startScan({
    Duration timeout = _scanTimeout,
    Duration discoveryTimeout = _discoveryTimeout,
  }) async {
    if (kIsWeb) {
      _ensureBleInitialized();
      await _startWebUserGestureScan(
        timeout: timeout,
        discoveryTimeout: discoveryTimeout,
      );
      return;
    }

    await _ensureNativeBleInitialized();
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

  Future<void> _startWebUserGestureScan({
    required Duration timeout,
    required Duration discoveryTimeout,
  }) async {
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
      // Web Bluetooth requires requestDevice() to run during the same browser
      // gesture that triggered the scan. Avoid awaited preflight work here.
      unawaited(_scanSubscription?.cancel());
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
      _isBluetoothSupported = true;
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

    if (!_shouldUseBluetoothSupportPreflight(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    )) {
      _isBluetoothSupported = true;
      return true;
    }

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

  static bool _shouldUseBluetoothSupportPreflight({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    if (isWeb) return true;
    return platform != TargetPlatform.iOS && platform != TargetPlatform.macOS;
  }

  Future<void> restartScan({
    Duration timeout = _scanTimeout,
    Duration discoveryTimeout = _discoveryTimeout,
  }) async {
    _ensureBleInitialized();
    if (kIsWeb) {
      unawaited(stopScan());
      await startScan(timeout: timeout, discoveryTimeout: discoveryTimeout);
      return;
    }

    await stopScan();
    await startScan(timeout: timeout, discoveryTimeout: discoveryTimeout);
  }

  void _startDiscoveryTimeout(Duration discoveryTimeout) {
    _discoveryTimeoutTimer?.cancel();
    _activeDiscoveryTimeout = discoveryTimeout;
    _discoveryTimeoutTimer = Timer(discoveryTimeout, () {
      unawaited(_handleDiscoveryTimeout());
    });
  }

  Future<void> _handleDiscoveryTimeout() async {
    if (!_isScanning || _isConnected || _device != null) return;
    final timeout = _activeDiscoveryTimeout;
    if (kDebugMode) {
      debugPrint('Govee discovery timed out after $timeout');
    }
    _addDiagnostic(
      'Discovery timed out after ${_formatDurationBrief(timeout)}',
    );
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

  Future<void> connectDevice() {
    _ensureBleInitialized();
    final pendingConnect = _gattConnectOperation;
    if (pendingConnect != null) return pendingConnect;

    final device = _device;
    if (device == null) return Future<void>.value();
    if (_isGattConnected) {
      return _gattDiscoveryOperation ?? Future<void>.value();
    }

    final operation = _connectDevice(device);
    _gattConnectOperation = operation;
    return operation.whenComplete(() {
      if (identical(_gattConnectOperation, operation)) {
        _gattConnectOperation = null;
      }
    });
  }

  Future<void> _connectDevice(BluetoothDevice device) async {
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
          _clearGattCharacteristics();
          if (_historySyncActive &&
              _shouldRetryHistorySyncAfterGattDisconnect()) {
            _historySyncReadings = <GoveeSensorReading>[];
            _historySyncBaseMinute = null;
            _historySyncPacketCount = 0;
            _addDiagnostic(
              'GATT disconnected during history sync; retrying on reconnect',
              notify: false,
            );
          } else {
            _failHistorySync(
              StateError('Govee disconnected during history sync'),
            );
          }
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
    if (kIsWeb) {
      _ensureBleInitialized();
      await _refreshAvailability();
      return;
    }
    await _ensureNativeBleInitialized();
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
      _clearGattCharacteristics();

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

  Future<void> _discoverAndRead(BluetoothDevice device) {
    final pendingDiscovery = _gattDiscoveryOperation;
    if (pendingDiscovery != null) return pendingDiscovery;

    final operation = _discoverAndReadInternal(device);
    _gattDiscoveryOperation = operation;
    return operation.whenComplete(() {
      if (identical(_gattDiscoveryOperation, operation)) {
        _gattDiscoveryOperation = null;
      }
    });
  }

  Future<void> _discoverAndReadInternal(BluetoothDevice device) async {
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
            } else if (uuid == _goveeCommandCharacteristicUuid) {
              _goveeHistoryControlCharacteristic = characteristic;
            } else if (uuid == _goveeDataCharacteristicUuid) {
              _goveeHistoryDataCharacteristic = characteristic;
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
                  'Govee read ${characteristic.uuid.str}: ${value.length} bytes',
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
                    'Govee notify ${characteristic.uuid.str}: ${value.length} bytes',
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
      if (_historySyncActive) {
        try {
          await _requestActiveHistorySync(retry: true);
        } catch (e) {
          _failHistorySync(e);
          rethrow;
        }
        return;
      }
      await _requestGoveeGattReadings(goveeCharacteristics);
      _startGattPolling();
    } catch (e) {
      if (kDebugMode) debugPrint('Govee discover services failed: $e');
      _addDiagnostic('Service discovery failed: $e');
    }
  }

  void _parseCharacteristicValue(String uuid, List<int> value) {
    if (_handleHistorySyncNotification(uuid, value)) {
      return;
    }

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
    ].where((name) => name.isNotEmpty);

    if (names.any(_isGoveeName)) {
      return true;
    }

    if (_hasGoveeBleIdentity(result)) {
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

  _GoveeHistoryProtocol _historyProtocolForDeviceName(String? name) {
    final lowerName = (name ?? '').toLowerCase();
    if (lowerName.contains('h5051') || lowerName.contains('h5179')) {
      return _GoveeHistoryProtocol.epochMinute;
    }
    return _GoveeHistoryProtocol.minuteBack;
  }

  bool _hasGoveeAdvertisement(ScanResult result) {
    final localName = _advertisedLocalName(result);

    for (final entry in result.advertisementData.manufacturerData.entries) {
      final manufacturerId = entry.key;
      if (manufacturerId == _appleManufacturerId ||
          manufacturerId == _microsoftManufacturerId) {
        continue;
      }

      final data = entry.value;
      final hasGoveeIdentity = _hasGoveeIdentity(
        manufacturerId: manufacturerId,
        localName: localName,
      );
      if ((hasGoveeIdentity &&
              (_parseH5051(data) != null ||
                  _parseH5051ShortAdvert(data) != null)) ||
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
      final hasGoveeIdentity = _hasGoveeIdentity(
        manufacturerId: manufacturerId,
        localName: localName,
      );
      if ((hasGoveeIdentity &&
              (_parseH5051(data) != null ||
                  _parseH5051ShortAdvert(data) != null)) ||
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

  bool _hasGoveeBleIdentity(ScanResult result) {
    if (result.advertisementData.manufacturerData.keys.any(
      (manufacturerId) => manufacturerId == _goveeManufacturerId,
    )) {
      return true;
    }

    if (result.advertisementData.serviceData.keys.any(
      (uuid) => _isGoveeAdvertisedUuid(uuid.str),
    )) {
      return true;
    }

    return result.advertisementData.serviceUuids.any(
      (uuid) => _isGoveeAdvertisedUuid(uuid.str),
    );
  }

  GoveeSensorReading? _parseGoveeAdvertisement(ScanResult result) {
    try {
      _logAdvertisement(result);

      final localName = _advertisedLocalName(result);
      for (final entry in result.advertisementData.manufacturerData.entries) {
        final manufacturerId = entry.key;
        final data = entry.value;
        if (manufacturerId == _appleManufacturerId ||
            manufacturerId == _microsoftManufacturerId) {
          continue;
        }

        final hasGoveeIdentity = _hasGoveeIdentity(
          manufacturerId: manufacturerId,
          localName: localName,
        );
        if (hasGoveeIdentity) {
          final h5051 = _parseH5051(data);
          if (h5051 != null) return h5051;
        }
        final combined = _parseGoveeCombinedAdvert(
          data,
          manufacturerId: manufacturerId,
          localName: localName,
        );
        if (combined != null) return combined;
        if (hasGoveeIdentity) {
          final shortAdvert = _parseH5051ShortAdvert(data);
          if (shortAdvert != null) return shortAdvert;
        }
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

        final hasGoveeIdentity = _hasGoveeIdentity(
          manufacturerId: manufacturerId,
          localName: localName,
        );
        if (hasGoveeIdentity) {
          final h5051 = _parseH5051(data);
          if (h5051 != null) return h5051;
        }
        final combined = _parseGoveeCombinedAdvert(
          data,
          manufacturerId: manufacturerId,
          localName: localName,
        );
        if (combined != null) return combined;
        if (hasGoveeIdentity) {
          final shortAdvert = _parseH5051ShortAdvert(data);
          if (shortAdvert != null) return shortAdvert;
        }
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

  bool _isGoveeName(String name) {
    final lower = name.toLowerCase();
    return lower.startsWith('govee') ||
        lower.startsWith('h5051') ||
        lower.startsWith('gvh') ||
        lower.contains('govee') ||
        lower.contains('h50');
  }

  String _advertisedLocalName(ScanResult result) {
    return [
      result.device.platformName,
      result.advertisementData.advName,
    ].where((name) => name.isNotEmpty).join(' ');
  }

  bool _hasGoveeIdentity({
    required int manufacturerId,
    required String localName,
  }) {
    return manufacturerId == _goveeManufacturerId || _isGoveeName(localName);
  }

  bool _isGoveeAdvertisedUuid(String uuid) {
    final lower = uuid.toLowerCase();
    return lower.contains('ec88') || lower == _goveeServiceUuid;
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

  @visibleForTesting
  static List<int> buildGoveeHistoryRequestForTesting({
    required int startMinutesBack,
    required int endMinutesBack,
  }) {
    return _buildGoveeHistoryRequest(
      startMinutesBack: startMinutesBack,
      endMinutesBack: endMinutesBack,
    );
  }

  @visibleForTesting
  static List<int> buildGoveeEpochMinuteHistoryRequestForTesting({
    required DateTime startedAt,
    required DateTime endedAt,
    required DateTime now,
  }) {
    return _buildHistorySyncRequest(
      protocol: _GoveeHistoryProtocol.epochMinute,
      startedAt: startedAt,
      endedAt: endedAt,
      now: now,
    ).payload;
  }

  @visibleForTesting
  static List<GoveeSensorReading> parseGoveeHistoryDataPacketForTesting(
    List<int> data, {
    required DateTime syncBaseMinute,
  }) {
    return _parseGoveeHistoryDataPacket(data, syncBaseMinute: syncBaseMinute);
  }

  @visibleForTesting
  static List<GoveeSensorReading>
  parseGoveeEpochMinuteHistoryDataPacketForTesting(List<int> data) {
    return _parseGoveeEpochMinuteHistoryDataPacket(data);
  }

  @visibleForTesting
  static int? parseGoveeHistoryCompletionCountForTesting(List<int> data) {
    return _parseGoveeHistoryCompletionCount(data);
  }

  static List<int> _buildGoveeHistoryRequest({
    required int startMinutesBack,
    required int endMinutesBack,
  }) {
    if (startMinutesBack < 0 || startMinutesBack > 0xFFFF) {
      throw RangeError.range(startMinutesBack, 0, 0xFFFF, 'startMinutesBack');
    }
    if (endMinutesBack < 0 || endMinutesBack > startMinutesBack) {
      throw RangeError.range(
        endMinutesBack,
        0,
        startMinutesBack,
        'endMinutesBack',
      );
    }

    final payload = <int>[
      0x33,
      0x01,
      (startMinutesBack >> 8) & 0xFF,
      startMinutesBack & 0xFF,
      (endMinutesBack >> 8) & 0xFF,
      endMinutesBack & 0xFF,
    ];
    while (payload.length < 19) {
      payload.add(0);
    }
    payload.add(_xorChecksum(payload));
    return payload;
  }

  static _GoveeHistorySyncRequest _buildHistorySyncRequest({
    required _GoveeHistoryProtocol protocol,
    required DateTime startedAt,
    required DateTime endedAt,
    required DateTime now,
  }) {
    return switch (protocol) {
      _GoveeHistoryProtocol.minuteBack => _buildMinuteBackHistorySyncRequest(
        startedAt: startedAt,
        endedAt: endedAt,
        now: now,
      ),
      _GoveeHistoryProtocol.epochMinute => _buildEpochMinuteHistorySyncRequest(
        startedAt: startedAt,
        endedAt: endedAt,
        now: now,
      ),
    };
  }

  static _GoveeHistorySyncRequest _buildMinuteBackHistorySyncRequest({
    required DateTime startedAt,
    required DateTime endedAt,
    required DateTime now,
  }) {
    final baseMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    final startMinutesBack = math.min(
      0xFFFF,
      _ceilMinutes(now.difference(startedAt)) + 1,
    );
    final requestedEndMinutesBack = math.max(
      1,
      _floorMinutes(now.difference(endedAt)) - 1,
    );
    final endMinutesBack = math.min(startMinutesBack, requestedEndMinutesBack);
    return _GoveeHistorySyncRequest(
      protocol: _GoveeHistoryProtocol.minuteBack,
      payload: _buildGoveeHistoryRequest(
        startMinutesBack: startMinutesBack,
        endMinutesBack: endMinutesBack,
      ),
      baseMinute: baseMinute,
      startMinutesBack: startMinutesBack,
      endMinutesBack: endMinutesBack,
    );
  }

  static _GoveeHistorySyncRequest _buildEpochMinuteHistorySyncRequest({
    required DateTime startedAt,
    required DateTime endedAt,
    required DateTime now,
  }) {
    final latestCompletedMinute =
        now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/
        60000;
    final requestedStartMinute = startedAt.millisecondsSinceEpoch ~/ 60000;
    final requestedEndMinute = endedAt.millisecondsSinceEpoch ~/ 60000;
    var startEpochMinute = math.min(requestedStartMinute, requestedEndMinute);
    var endEpochMinute = math.min(
      math.max(requestedStartMinute, requestedEndMinute),
      latestCompletedMinute,
    );
    if (endEpochMinute < startEpochMinute) {
      startEpochMinute = endEpochMinute;
    }
    return _GoveeHistorySyncRequest(
      protocol: _GoveeHistoryProtocol.epochMinute,
      payload: _buildGoveeEpochMinuteHistoryRequest(
        startEpochMinute: startEpochMinute,
        endEpochMinute: endEpochMinute,
      ),
      startEpochMinute: startEpochMinute,
      endEpochMinute: endEpochMinute,
    );
  }

  static List<int> _buildGoveeEpochMinuteHistoryRequest({
    required int startEpochMinute,
    required int endEpochMinute,
  }) {
    if (startEpochMinute < 0 || startEpochMinute > 0xFFFFFFFF) {
      throw RangeError.range(
        startEpochMinute,
        0,
        0xFFFFFFFF,
        'startEpochMinute',
      );
    }
    if (endEpochMinute < startEpochMinute || endEpochMinute > 0xFFFFFFFF) {
      throw RangeError.range(
        endEpochMinute,
        startEpochMinute,
        0xFFFFFFFF,
        'endEpochMinute',
      );
    }
    return [
      0x00,
      0x00,
      startEpochMinute & 0xFF,
      (startEpochMinute >> 8) & 0xFF,
      (startEpochMinute >> 16) & 0xFF,
      (startEpochMinute >> 24) & 0xFF,
      endEpochMinute & 0xFF,
      (endEpochMinute >> 8) & 0xFF,
      (endEpochMinute >> 16) & 0xFF,
      (endEpochMinute >> 24) & 0xFF,
    ];
  }

  static List<GoveeSensorReading> _parseGoveeHistoryDataPacket(
    List<int> data, {
    required DateTime syncBaseMinute,
  }) {
    if (data.length < 5) return const [];
    final firstMinutesBack = _unsignedInt16BigEndian(data[0], data[1]);
    final readings = <GoveeSensorReading>[];
    var recordIndex = 0;
    for (var offset = 2; offset + 2 < data.length; offset += 3) {
      final high = data[offset] & 0xFF;
      final mid = data[offset + 1] & 0xFF;
      final low = data[offset + 2] & 0xFF;
      if (high == 0xFF && mid == 0xFF && low == 0xFF) {
        recordIndex += 1;
        continue;
      }

      final decoded = _decodePackedTempHumidityStatic(high, mid, low);
      if (decoded != null) {
        final minutesBack = firstMinutesBack - recordIndex;
        if (minutesBack < 0) {
          recordIndex += 1;
          continue;
        }
        final tempF = _celsiusToFahrenheit(decoded.temperatureCelsius);
        final humidity = decoded.humidity;
        if (_isValidReading(tempF, humidity)) {
          final bucketStartedAt = syncBaseMinute.subtract(
            Duration(minutes: minutesBack),
          );
          readings.add(
            GoveeSensorReading(
              temperatureFahrenheit: tempF,
              humidity: humidity,
              timestamp: bucketStartedAt,
              bucketStartedAt: bucketStartedAt,
              bucketEndedAt: bucketStartedAt.add(const Duration(minutes: 1)),
            ),
          );
        }
      }
      recordIndex += 1;
    }
    return readings;
  }

  static List<GoveeSensorReading> _parseGoveeEpochMinuteHistoryDataPacket(
    List<int> data,
  ) {
    if (data.length < 8) return const [];
    final firstEpochMinute = _unsignedInt32LittleEndian(
      data[0],
      data[1],
      data[2],
      data[3],
    );
    final readings = <GoveeSensorReading>[];
    var recordIndex = 0;
    for (var offset = 4; offset + 3 < data.length; offset += 4) {
      final tempLow = data[offset] & 0xFF;
      final tempHigh = data[offset + 1] & 0xFF;
      final humidityLow = data[offset + 2] & 0xFF;
      final humidityHigh = data[offset + 3] & 0xFF;
      if (tempLow == 0xFF &&
          tempHigh == 0xFF &&
          humidityLow == 0xFF &&
          humidityHigh == 0xFF) {
        recordIndex += 1;
        continue;
      }

      final epochMinute = firstEpochMinute - recordIndex;
      if (epochMinute < 0) {
        recordIndex += 1;
        continue;
      }
      final tempRaw = _signedInt16(tempLow, tempHigh);
      final humidityRaw = humidityLow | (humidityHigh << 8);
      final tempF = _celsiusToFahrenheit(tempRaw / 100.0);
      final humidity = humidityRaw / 100.0;
      if (_isValidReading(tempF, humidity)) {
        final bucketStartedAt = DateTime.fromMillisecondsSinceEpoch(
          epochMinute * 60000,
        );
        readings.add(
          GoveeSensorReading(
            temperatureFahrenheit: tempF,
            humidity: humidity,
            timestamp: bucketStartedAt,
            bucketStartedAt: bucketStartedAt,
            bucketEndedAt: bucketStartedAt.add(const Duration(minutes: 1)),
          ),
        );
      }
      recordIndex += 1;
    }
    return readings;
  }

  static bool _isGoveeHistoryAck(
    List<int> data,
    _GoveeHistoryProtocol protocol,
  ) {
    return switch (protocol) {
      _GoveeHistoryProtocol.minuteBack =>
        data.length >= 2 &&
            data[0] == 0x33 &&
            data[1] == 0x01 &&
            _hasValidGoveeChecksum(data),
      _GoveeHistoryProtocol.epochMinute =>
        (data.length == 1 && data[0] == 0x00) ||
            (data.length >= 2 && data[0] == 0x00 && data[1] == 0x00),
    };
  }

  static bool _isGoveeHistoryComplete(
    List<int> data,
    _GoveeHistoryProtocol protocol,
  ) {
    return switch (protocol) {
      _GoveeHistoryProtocol.minuteBack => false,
      _GoveeHistoryProtocol.epochMinute => data.length == 1 && data[0] == 0x02,
    };
  }

  static bool _isGoveeHistoryProgress(
    List<int> data,
    _GoveeHistoryProtocol protocol,
  ) {
    return switch (protocol) {
      _GoveeHistoryProtocol.minuteBack => false,
      _GoveeHistoryProtocol.epochMinute => data.length == 1 && data[0] == 0x03,
    };
  }

  static int? _parseGoveeHistoryCompletionCount(List<int> data) {
    if (data.length < 4 ||
        data[0] != 0xEE ||
        data[1] != 0x01 ||
        !_hasValidGoveeChecksum(data)) {
      return null;
    }
    return _unsignedInt16BigEndian(data[2], data[3]);
  }

  static int _signedInt16(int lowByte, int highByte) {
    final unsigned = (lowByte & 0xFF) | ((highByte & 0xFF) << 8);
    return unsigned >= 0x8000 ? unsigned - 0x10000 : unsigned;
  }

  static int _unsignedInt16BigEndian(int highByte, int lowByte) {
    return ((highByte & 0xFF) << 8) | (lowByte & 0xFF);
  }

  static int _unsignedInt32LittleEndian(
    int firstByte,
    int secondByte,
    int thirdByte,
    int fourthByte,
  ) {
    return (firstByte & 0xFF) |
        ((secondByte & 0xFF) << 8) |
        ((thirdByte & 0xFF) << 16) |
        ((fourthByte & 0xFF) << 24);
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
    final checksum = _xorChecksum(data.take(data.length - 1));
    return checksum == (data.last & 0xFF);
  }

  static int _xorChecksum(Iterable<int> bytes) {
    var checksum = 0;
    for (final byte in bytes) {
      checksum ^= byte & 0xFF;
    }
    return checksum;
  }

  static int _ceilMinutes(Duration duration) {
    if (duration.isNegative) return 0;
    return (duration.inSeconds + 59) ~/ 60;
  }

  static int _floorMinutes(Duration duration) {
    if (duration.isNegative) return 0;
    return duration.inSeconds ~/ 60;
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
    _ensureBleInitialized();
    if (!endedAt.isAfter(startedAt)) return const [];

    if (_historySyncCompleter != null && !_historySyncCompleter!.isCompleted) {
      throw StateError('Govee history sync is already in progress');
    }

    final historyCharacteristicsReady =
        await _ensureHistoryCharacteristicsReady();
    final writeCharacteristic = _goveeHistoryControlCharacteristic;
    final responseCharacteristic = _goveeHistoryControlCharacteristic;
    final dataCharacteristic = _goveeHistoryDataCharacteristic;
    if (!historyCharacteristicsReady ||
        !_isGattConnected ||
        writeCharacteristic == null ||
        responseCharacteristic == null ||
        dataCharacteristic == null ||
        !_canWrite(writeCharacteristic)) {
      const message =
          'History sync needs connected H5051 history/control/data characteristics. Keep the device near the app and reconnect Govee.';
      _addDiagnostic(message);
      throw StateError(message);
    }

    final now = DateTime.now();
    final protocol = _historyProtocolForDeviceName(_deviceName);
    final syncRequest = _buildHistorySyncRequest(
      protocol: protocol,
      startedAt: startedAt,
      endedAt: endedAt,
      now: now,
    );

    _historySyncCompleter = Completer<List<GoveeSensorReading>>();
    _historySyncReadings = <GoveeSensorReading>[];
    _historySyncBaseMinute = syncRequest.baseMinute;
    _historySyncStartedAt = startedAt;
    _historySyncEndedAt = endedAt;
    _historySyncPacketCount = 0;
    _historySyncProtocol = protocol;
    final wasPolling = _gattPollTimer != null;
    if (wasPolling) {
      _stopGattPolling();
      _addDiagnostic(
        'Paused live GATT polling for history sync',
        notify: false,
      );
    }

    try {
      await _requestActiveHistorySync(
        retry: false,
        syncRequest: syncRequest,
        writeCharacteristic: writeCharacteristic,
        responseCharacteristic: responseCharacteristic,
        dataCharacteristic: dataCharacteristic,
      );
      return await _historySyncCompleter!.future.timeout(_historySyncTimeout);
    } on TimeoutException {
      _addDiagnostic(
        'History sync timed out. Keep the H5051 powered on and near the app, then retry sync.',
      );
      rethrow;
    } finally {
      _historySyncCompleter = null;
      _historySyncReadings = <GoveeSensorReading>[];
      _historySyncBaseMinute = null;
      _historySyncStartedAt = null;
      _historySyncEndedAt = null;
      _historySyncPacketCount = 0;
      _historySyncProtocol = _GoveeHistoryProtocol.minuteBack;
      if (wasPolling && _isGattConnected) {
        _startGattPolling();
      }
    }
  }

  Future<void> _requestActiveHistorySync({
    required bool retry,
    _GoveeHistorySyncRequest? syncRequest,
    BluetoothCharacteristic? writeCharacteristic,
    BluetoothCharacteristic? responseCharacteristic,
    BluetoothCharacteristic? dataCharacteristic,
  }) async {
    final startedAt = _historySyncStartedAt;
    final endedAt = _historySyncEndedAt;
    if (!_historySyncActive || startedAt == null || endedAt == null) {
      throw StateError('No active Govee history sync to request');
    }

    final resolvedWrite =
        writeCharacteristic ?? _goveeHistoryControlCharacteristic;
    final resolvedResponse =
        responseCharacteristic ?? _goveeHistoryControlCharacteristic;
    final resolvedData = dataCharacteristic ?? _goveeHistoryDataCharacteristic;
    if (!_isGattConnected ||
        resolvedWrite == null ||
        resolvedResponse == null ||
        resolvedData == null ||
        !_canWrite(resolvedWrite)) {
      throw StateError('Govee history sync could not reconnect GATT');
    }

    final resolvedSyncRequest =
        syncRequest ??
        _buildHistorySyncRequest(
          protocol: _historySyncProtocol,
          startedAt: startedAt,
          endedAt: endedAt,
          now: DateTime.now(),
        );

    _historySyncReadings = <GoveeSensorReading>[];
    _historySyncBaseMinute = resolvedSyncRequest.baseMinute;
    _historySyncPacketCount = 0;
    try {
      await _ensureHistoryNotifications(resolvedResponse, resolvedData);
      await _writeGoveeHistoryRequest(resolvedWrite, resolvedSyncRequest);
      _addDiagnostic(resolvedSyncRequest.diagnostic(retry: retry));
    } catch (e) {
      if (_canRetryActiveHistorySyncAfterGattFailure(e)) {
        _prepareHistorySyncRetryAfterGattFailure(e);
        return;
      }
      rethrow;
    }
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
        debugPrint(
          'Govee write ${characteristic.uuid.str}: ${payload.length} bytes',
        );
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

  Future<void> _writeGoveeHistoryRequest(
    BluetoothCharacteristic characteristic,
    _GoveeHistorySyncRequest request,
  ) async {
    final payload = request.payload;
    try {
      await characteristic.write(
        payload,
        withoutResponse:
            !characteristic.properties.write &&
            characteristic.properties.writeWithoutResponse,
      );
      if (kDebugMode) {
        debugPrint(
          'Govee history write ${characteristic.uuid.str}: ${payload.length} bytes',
        );
      }
      _addDiagnostic(
        'Write history request ${request.commandLabel} to ${characteristic.uuid.str} (${payload.length} bytes)',
        notify: false,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Govee history write failed ${characteristic.uuid.str}: $e');
      }
      _addDiagnostic(
        'History sync write failed ${characteristic.uuid.str} (${payload.length} bytes): $e',
      );
      rethrow;
    }
  }

  Future<void> _ensureHistoryNotifications(
    BluetoothCharacteristic controlCharacteristic,
    BluetoothCharacteristic dataCharacteristic,
  ) async {
    for (final characteristic in [controlCharacteristic, dataCharacteristic]) {
      if (!characteristic.properties.notify) continue;
      try {
        await characteristic.setNotifyValue(true);
      } catch (e) {
        _addDiagnostic(
          'History notification setup failed ${characteristic.uuid.str}: $e',
        );
        rethrow;
      }
    }
  }

  bool _canRetryActiveHistorySyncAfterGattFailure(Object error) {
    if (!_historySyncActive || !_shouldRetryHistorySyncAfterGattDisconnect()) {
      return false;
    }
    final message = error.toString().toLowerCase();
    return message.contains('disconnect') || message.contains('not connected');
  }

  void _prepareHistorySyncRetryAfterGattFailure(Object error) {
    _historySyncReadings = <GoveeSensorReading>[];
    _historySyncBaseMinute = null;
    _historySyncPacketCount = 0;
    _isGattConnected = false;
    _stopGattPolling();
    unawaited(_cancelGattNotificationSubscriptions());
    _clearGattCharacteristics();
    _addDiagnostic(
      'History sync waiting for reconnect after GATT failure: $error',
      notify: false,
    );
    _scheduleReconnectScan();
    notifyListeners();
  }

  Future<bool> _ensureHistoryCharacteristicsReady() async {
    if (_hasHistoryGattCharacteristics) return true;

    final pendingConnect = _gattConnectOperation;
    if (pendingConnect != null) {
      await pendingConnect;
      if (_hasHistoryGattCharacteristics) return true;
    }

    final pendingDiscovery = _gattDiscoveryOperation;
    if (pendingDiscovery != null) {
      await pendingDiscovery;
      if (_hasHistoryGattCharacteristics) return true;
    }

    final device = _device;
    if (device == null) return false;

    if (!_isGattConnected) {
      await connectDevice();
      if (_hasHistoryGattCharacteristics) return true;
    }

    if (_isGattConnected) {
      _addDiagnostic(
        'History characteristics missing; rediscovering GATT services',
        notify: false,
      );
      await _discoverAndRead(device);
    }
    return _hasHistoryGattCharacteristics;
  }

  bool get _hasHistoryGattCharacteristics =>
      _isGattConnected &&
      _goveeDeviceCharacteristic != null &&
      _goveeHistoryControlCharacteristic != null &&
      _goveeHistoryDataCharacteristic != null;

  List<int> _buildGoveeCommand(int prefix, int command) {
    final payload = <int>[prefix & 0xFF, command & 0xFF];
    while (payload.length < 19) {
      payload.add(0);
    }
    payload.add(_xorChecksum(payload));
    return payload;
  }

  bool _handleHistorySyncNotification(String uuid, List<int> value) {
    final completer = _historySyncCompleter;
    if (completer == null || completer.isCompleted) return false;

    if (uuid == _goveeCommandCharacteristicUuid) {
      if (_isGoveeHistoryAck(value, _historySyncProtocol)) {
        _addDiagnostic(
          'History sync accepted by ${_historyProtocolLabel(_historySyncProtocol)}',
          notify: false,
        );
        return true;
      }

      if (_isGoveeHistoryProgress(value, _historySyncProtocol)) {
        _addDiagnostic('History sync progress status received', notify: false);
        return true;
      }

      if (_isGoveeHistoryComplete(value, _historySyncProtocol)) {
        _completeHistorySync(_historySyncPacketCount);
        return true;
      }

      final completionCount = _parseGoveeHistoryCompletionCount(value);
      if (completionCount != null) {
        _completeHistorySync(completionCount);
        return true;
      }
      return false;
    }

    if (uuid != _goveeDataCharacteristicUuid) return false;
    if (value.isEmpty) return true;
    final readings = _parseActiveHistoryDataPacket(value);
    _historySyncPacketCount += 1;
    _historySyncReadings.addAll(readings);
    _addDiagnostic(
      'History packet $_historySyncPacketCount: ${readings.length} readings',
      notify: false,
    );
    return true;
  }

  void _completeHistorySync(int completionCount) {
    final completer = _historySyncCompleter;
    if (completer == null || completer.isCompleted) return;
    final readings = List<GoveeSensorReading>.from(_historySyncReadings)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _addDiagnostic(
      'History sync complete: $completionCount packets, ${readings.length} readings',
    );
    completer.complete(readings);
  }

  List<GoveeSensorReading> _parseActiveHistoryDataPacket(List<int> value) {
    if (_historySyncProtocol == _GoveeHistoryProtocol.epochMinute) {
      return _parseGoveeEpochMinuteHistoryDataPacket(value);
    }

    final baseMinute = _historySyncBaseMinute;
    if (baseMinute == null) return const <GoveeSensorReading>[];
    return _parseGoveeHistoryDataPacket(value, syncBaseMinute: baseMinute);
  }

  String _historyProtocolLabel(_GoveeHistoryProtocol protocol) {
    return switch (protocol) {
      _GoveeHistoryProtocol.minuteBack => 'minute-back command',
      _GoveeHistoryProtocol.epochMinute => 'epoch-minute command',
    };
  }

  void _clearGattCharacteristics() {
    _goveeDeviceCharacteristic = null;
    _goveeHistoryControlCharacteristic = null;
    _goveeHistoryDataCharacteristic = null;
  }

  void _failHistorySync(Object error) {
    final completer = _historySyncCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.completeError(error);
  }

  bool get _historySyncActive =>
      _historySyncCompleter != null && !_historySyncCompleter!.isCompleted;

  bool _shouldRetryHistorySyncAfterGattDisconnect() {
    return !_manualDisconnectRequested &&
        _autoReconnectEnabled &&
        _isAvailable &&
        _isConnected;
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
    final canWrite = characteristic != null && _canWrite(characteristic);
    if (!_shouldPollGatt(
      hasCharacteristic: characteristic != null,
      isGattConnected: _isGattConnected,
      canWrite: canWrite,
      historySyncActive:
          _historySyncCompleter != null && !_historySyncCompleter!.isCompleted,
    )) {
      return;
    }
    _gattPollCount += 1;
    await _writeGoveeCommand(characteristic!, 0x0A);
    if (includeBattery || _gattPollCount % 12 == 0) {
      await _writeGoveeCommand(characteristic, 0x08);
    }
  }

  static bool _shouldPollGatt({
    required bool hasCharacteristic,
    required bool isGattConnected,
    required bool canWrite,
    required bool historySyncActive,
  }) {
    return hasCharacteristic &&
        isGattConnected &&
        canWrite &&
        !historySyncActive;
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
      'rssi=${result.rssi}',
    );
  }

  void _logScanCandidate(ScanResult result) {
    if (!kDebugMode) return;
    if (_debugLoggedScanIds.length >= 25) return;

    final id = result.device.remoteId.str;
    if (!_debugLoggedScanIds.add(id)) return;
    final advertisedName = _advertisedLocalName(result).trim();
    final name = advertisedName.isEmpty ? '(unnamed)' : advertisedName;
    debugPrint(
      'BLE scan candidate ignored name=$name rssi=${result.rssi}'
      '${_advertisementIdentitySummary(result)}',
    );
  }

  String _advertisementIdentitySummary(ScanResult result) {
    final manufacturerIds = result.advertisementData.manufacturerData.keys
        .map((id) => '0x${id.toRadixString(16).padLeft(4, '0')}')
        .join(',');
    final serviceIds = [
      ...result.advertisementData.serviceData.keys.map((uuid) => uuid.str),
      ...result.advertisementData.serviceUuids.map((uuid) => uuid.str),
    ].take(3).join(',');
    if (manufacturerIds.isEmpty && serviceIds.isEmpty) return '';
    return ' manufacturers=[$manufacturerIds] services=[$serviceIds]';
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
      _clearGattCharacteristics();
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

  String _formatDurationBrief(Duration duration) {
    if (duration.inSeconds >= 1 &&
        duration.inMilliseconds % Duration.millisecondsPerSecond == 0) {
      return '${duration.inSeconds}s';
    }
    if (duration.inMilliseconds >= 1) {
      return '${duration.inMilliseconds}ms';
    }
    return duration.toString();
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
