import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/govee/govee_service.dart';

base class _FakeBluetoothPlatform extends FlutterBluePlusPlatform {
  final calls = <String>[];
  final writes = <List<int>>[];
  final _adapterStateController =
      StreamController<BmBluetoothAdapterState>.broadcast();
  final _scanController = StreamController<BmScanResponse>.broadcast();
  final _connectionController =
      StreamController<BmConnectionStateResponse>.broadcast();
  final _servicesController =
      StreamController<BmDiscoverServicesResult>.broadcast();
  final _characteristicReceivedController =
      StreamController<BmCharacteristicData>.broadcast();
  final _characteristicWrittenController =
      StreamController<BmCharacteristicData>.broadcast();
  final _descriptorWrittenController =
      StreamController<BmDescriptorData>.broadcast();

  final DeviceIdentifier remoteId = DeviceIdentifier(
    '798FC583-07B3-1978-1E50-2AD46A8F149A',
  );
  final Guid serviceUuid = Guid('494e5445-4c4c-495f-524f-434b535f2000');
  String platformName = 'Govee_H5075_ECC3';
  bool disconnectOnFirstHistoryWrite = false;
  bool epochMinuteUsesShortCompletion = false;
  bool includeHistoryCharacteristics = true;
  Completer<void>? connectGate;
  int historyWriteCount = 0;

  @override
  Stream<BmBluetoothAdapterState> get onAdapterStateChanged =>
      _adapterStateController.stream;

  @override
  Stream<BmScanResponse> get onScanResponse => _scanController.stream;

  @override
  Stream<BmConnectionStateResponse> get onConnectionStateChanged =>
      _connectionController.stream;

  @override
  Stream<BmDiscoverServicesResult> get onDiscoveredServices =>
      _servicesController.stream;

  @override
  Stream<BmCharacteristicData> get onCharacteristicReceived =>
      _characteristicReceivedController.stream;

  @override
  Stream<BmCharacteristicData> get onCharacteristicWritten =>
      _characteristicWrittenController.stream;

  @override
  Stream<BmDescriptorData> get onDescriptorWritten =>
      _descriptorWrittenController.stream;

  @override
  Future<BmBluetoothAdapterState> getAdapterState(
    BmBluetoothAdapterStateRequest request,
  ) async {
    calls.add('getAdapterState');
    return BmBluetoothAdapterState(adapterState: BmAdapterStateEnum.on);
  }

  @override
  Future<bool> isSupported(BmIsSupportedRequest request) async {
    calls.add('isSupported');
    return true;
  }

  @override
  Future<bool> startScan(BmScanSettings request) async {
    calls.add('startScan');
    scheduleMicrotask(() {
      _scanController.add(
        BmScanResponse(
          advertisements: [
            BmScanAdvertisement(
              remoteId: remoteId,
              platformName: platformName,
              advName: platformName,
              connectable: true,
              txPowerLevel: null,
              appearance: null,
              manufacturerData: const {},
              serviceData: const {},
              serviceUuids: const [],
              rssi: -48,
            ),
          ],
          success: true,
          errorCode: 0,
          errorString: '',
        ),
      );
    });
    return true;
  }

  @override
  Future<bool> stopScan(BmStopScanRequest request) async {
    calls.add('stopScan');
    return true;
  }

  @override
  Future<bool> connect(BmConnectRequest request) async {
    calls.add('connect');
    final gate = connectGate;
    if (gate != null) {
      await gate.future;
    }
    scheduleMicrotask(() => _emitConnection(BmConnectionStateEnum.connected));
    return true;
  }

  @override
  Future<bool> discoverServices(BmDiscoverServicesRequest request) async {
    calls.add('discoverServices');
    scheduleMicrotask(() {
      final characteristics = [
        _characteristic(
          GoveeService.deviceCommandCharacteristicUuidForTesting,
          write: true,
          notify: true,
        ),
        if (includeHistoryCharacteristics) ...[
          _characteristic(
            GoveeService.historyResponseCharacteristicUuidForTesting,
            write: true,
            notify: true,
          ),
          _characteristic(
            GoveeService.historyDataCharacteristicUuidForTesting,
            notify: true,
          ),
        ],
      ];
      _servicesController.add(
        BmDiscoverServicesResult(
          remoteId: remoteId,
          services: [
            BmBluetoothService(
              remoteId: remoteId,
              primaryServiceUuid: null,
              serviceUuid: serviceUuid,
              characteristics: characteristics,
            ),
          ],
          success: true,
          errorCode: 0,
          errorString: '',
        ),
      );
    });
    return true;
  }

  @override
  Future<bool> setNotifyValue(BmSetNotifyValueRequest request) async {
    calls.add('setNotifyValue:${request.characteristicUuid.str}');
    scheduleMicrotask(() {
      _descriptorWrittenController.add(
        BmDescriptorData(
          remoteId: remoteId,
          primaryServiceUuid: request.primaryServiceUuid,
          serviceUuid: request.serviceUuid,
          characteristicUuid: request.characteristicUuid,
          descriptorUuid: Guid('00002902-0000-1000-8000-00805f9b34fb'),
          instanceId: request.instanceId,
          value: request.enable ? const [0x01, 0x00] : const [0x00, 0x00],
          success: true,
          errorCode: 0,
          errorString: '',
        ),
      );
    });
    return true;
  }

  @override
  Future<bool> writeCharacteristic(BmWriteCharacteristicRequest request) async {
    calls.add('writeCharacteristic:${request.characteristicUuid.str}');
    writes.add(request.value);
    scheduleMicrotask(() {
      _characteristicWrittenController.add(
        _characteristicData(
          characteristicUuid: request.characteristicUuid,
          value: request.value,
        ),
      );
    });

    if (_isHistoryRequest(request.value)) {
      historyWriteCount += 1;
      if (disconnectOnFirstHistoryWrite && historyWriteCount == 1) {
        Future<void>.delayed(const Duration(milliseconds: 1), () {
          _emitConnection(BmConnectionStateEnum.disconnected);
        });
      } else {
        Future<void>.delayed(const Duration(milliseconds: 1), () {
          _emitHistoryNotifications();
        });
      }
    }
    return true;
  }

  BmBluetoothCharacteristic _characteristic(
    String uuid, {
    bool write = false,
    bool notify = false,
  }) {
    return BmBluetoothCharacteristic(
      remoteId: remoteId,
      primaryServiceUuid: null,
      serviceUuid: serviceUuid,
      characteristicUuid: Guid(uuid),
      instanceId: 0,
      descriptors: const [],
      properties: BmCharacteristicProperties(
        broadcast: false,
        read: false,
        writeWithoutResponse: false,
        write: write,
        notify: notify,
        indicate: false,
        authenticatedSignedWrites: false,
        extendedProperties: false,
        notifyEncryptionRequired: false,
        indicateEncryptionRequired: false,
      ),
    );
  }

  BmCharacteristicData _characteristicData({
    required Guid characteristicUuid,
    required List<int> value,
  }) {
    return BmCharacteristicData(
      remoteId: remoteId,
      primaryServiceUuid: null,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      instanceId: 0,
      value: value,
      success: true,
      errorCode: 0,
      errorString: '',
    );
  }

  void _emitConnection(BmConnectionStateEnum state) {
    _connectionController.add(
      BmConnectionStateResponse(
        remoteId: remoteId,
        connectionState: state,
        disconnectReasonCode: null,
        disconnectReasonString: null,
      ),
    );
  }

  void _emitHistoryNotifications() {
    if (writes.last.length == 10) {
      _emitEpochMinuteHistoryNotifications();
      return;
    }

    _characteristicReceivedController.add(
      _characteristicData(
        characteristicUuid: Guid(
          GoveeService.historyResponseCharacteristicUuidForTesting,
        ),
        value: GoveeService.buildGoveeHistoryRequestForTesting(
          startMinutesBack: 3,
          endMinutesBack: 1,
        ),
      ),
    );
    _characteristicReceivedController.add(
      _characteristicData(
        characteristicUuid: Guid(
          GoveeService.historyDataCharacteristicUuidForTesting,
        ),
        value: const [
          0x00,
          0x03,
          0x03,
          0x75,
          0xcf,
          0x03,
          0x75,
          0xcf,
          0x03,
          0x75,
          0xce,
        ],
      ),
    );
    _characteristicReceivedController.add(
      _characteristicData(
        characteristicUuid: Guid(
          GoveeService.historyResponseCharacteristicUuidForTesting,
        ),
        value: const [
          0xee,
          0x01,
          0x00,
          0x01,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0xee,
        ],
      ),
    );
  }

  void _emitEpochMinuteHistoryNotifications() {
    _characteristicReceivedController.add(
      _characteristicData(
        characteristicUuid: Guid(
          GoveeService.historyResponseCharacteristicUuidForTesting,
        ),
        value: writes.last,
      ),
    );
    final epochMinute = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    _characteristicReceivedController.add(
      _characteristicData(
        characteristicUuid: Guid(
          GoveeService.historyDataCharacteristicUuidForTesting,
        ),
        value: [
          epochMinute & 0xFF,
          (epochMinute >> 8) & 0xFF,
          (epochMinute >> 16) & 0xFF,
          (epochMinute >> 24) & 0xFF,
          0xC4,
          0x09,
          0x64,
          0x19,
          0xFF,
          0xFF,
          0xFF,
          0xFF,
          0xFF,
          0xFF,
          0xFF,
          0xFF,
          0xFF,
          0xFF,
          0xFF,
          0xFF,
        ],
      ),
    );
    _characteristicReceivedController.add(
      _characteristicData(
        characteristicUuid: Guid(
          GoveeService.historyResponseCharacteristicUuidForTesting,
        ),
        value: epochMinuteUsesShortCompletion
            ? const [0x02]
            : const [
                0xee,
                0x01,
                0x00,
                0x01,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0xee,
              ],
      ),
    );
  }

  bool _isHistoryRequest(List<int> value) {
    return value.length >= 2 &&
        ((value[0] == 0x33 && value[1] == 0x01) ||
            (value.length == 10 && value[0] == 0x00 && value[1] == 0x00));
  }

  void reset() {
    calls.clear();
    writes.clear();
    platformName = 'Govee_H5075_ECC3';
    disconnectOnFirstHistoryWrite = false;
    epochMinuteUsesShortCompletion = false;
    includeHistoryCharacteristics = true;
    connectGate = null;
    historyWriteCount = 0;
    _emitConnection(BmConnectionStateEnum.disconnected);
  }

  Future<void> close() async {
    await _adapterStateController.close();
    await _scanController.close();
    await _connectionController.close();
    await _servicesController.close();
    await _characteristicReceivedController.close();
    await _characteristicWrittenController.close();
    await _descriptorWrittenController.close();
  }
}

void main() {
  group('GoveeService history sync helpers', () {
    late _FakeBluetoothPlatform platform;

    setUpAll(() {
      platform = _FakeBluetoothPlatform();
      FlutterBluePlusPlatform.instance = platform;
    });

    setUp(() {
      platform.reset();
    });

    tearDownAll(() async {
      await platform.close();
    });

    test('uses 2012 for history requests and 2013 for history data', () {
      expect(
        GoveeService.historyWriteCharacteristicUuidForTesting,
        GoveeService.historyResponseCharacteristicUuidForTesting,
      );
      expect(
        GoveeService.historyWriteCharacteristicUuidForTesting.endsWith('2011'),
        isFalse,
      );
      expect(
        GoveeService.historyWriteCharacteristicUuidForTesting.endsWith('2012'),
        isTrue,
      );
      expect(
        GoveeService.historyResponseCharacteristicUuidForTesting.endsWith(
          '2012',
        ),
        isTrue,
      );
      expect(
        GoveeService.historyDataCharacteristicUuidForTesting.endsWith('2013'),
        isTrue,
      );
    });

    test('suppresses live GATT polling while history sync is active', () {
      expect(
        GoveeService.shouldPollGattForTesting(
          hasCharacteristic: true,
          isGattConnected: true,
          canWrite: true,
          historySyncActive: false,
        ),
        isTrue,
      );
      expect(
        GoveeService.shouldPollGattForTesting(
          hasCharacteristic: true,
          isGattConnected: true,
          canWrite: true,
          historySyncActive: true,
        ),
        isFalse,
      );
    });

    test(
      'keeps history sync alive across an auto-reconnectable GATT drop',
      () async {
        platform.disconnectOnFirstHistoryWrite = true;

        final service = GoveeService();
        addTearDown(service.dispose);
        service.setAutoReconnectEnabled(true);
        await service.initializeBle();
        await service.startScan(
          timeout: const Duration(seconds: 5),
          discoveryTimeout: const Duration(seconds: 5),
        );

        for (var i = 0; i < 20 && !service.isGattConnected; i += 1) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(service.isGattConnected, isTrue);

        final readings = await service.syncHistory(
          startedAt: DateTime.now().subtract(const Duration(minutes: 3)),
          endedAt: DateTime.now(),
        );

        expect(readings, isNotEmpty);
        expect(platform.historyWriteCount, greaterThanOrEqualTo(2));
        expect(
          platform.calls.where(
            (call) =>
                call ==
                'writeCharacteristic:${GoveeService.historyWriteCharacteristicUuidForTesting}',
          ),
          isNotEmpty,
        );
        expect(platform.writes.last[5], 0x01);
        expect(
          service.diagnostics,
          contains(contains('GATT disconnected during history sync; retrying')),
        );
      },
    );

    test(
      'history sync waits for an in-progress reconnect before checking characteristics',
      () async {
        platform.platformName = 'Govee_H5051_ECC3';

        final service = GoveeService();
        addTearDown(service.dispose);
        service.setAutoReconnectEnabled(true);
        await service.initializeBle();
        await service.startScan(
          timeout: const Duration(seconds: 5),
          discoveryTimeout: const Duration(seconds: 5),
        );

        for (var i = 0; i < 20 && !service.isGattConnected; i += 1) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(service.isGattConnected, isTrue);

        platform._emitConnection(BmConnectionStateEnum.disconnected);
        await Future<void>.delayed(Duration.zero);
        expect(service.isGattConnected, isFalse);

        final connectGate = Completer<void>();
        platform.connectGate = connectGate;
        final reconnect = service.connectDevice();
        await Future<void>.delayed(Duration.zero);
        expect(service.isGattConnecting, isTrue);

        final sync = service.syncHistory(
          startedAt: DateTime.now().subtract(const Duration(minutes: 3)),
          endedAt: DateTime.now(),
        );

        connectGate.complete();
        await reconnect;

        final readings = await sync.timeout(const Duration(seconds: 1));

        expect(readings, isNotEmpty);
        expect(
          service.diagnostics,
          contains(contains('History sync requested epoch-minute window')),
        );
      },
    );

    test('uses epoch-minute history requests for H5051 devices', () async {
      platform.platformName = 'Govee_H5051_ECC3';

      final service = GoveeService();
      addTearDown(service.dispose);
      await service.initializeBle();
      await service.startScan(
        timeout: const Duration(seconds: 5),
        discoveryTimeout: const Duration(seconds: 5),
      );

      for (var i = 0; i < 20 && !service.isGattConnected; i += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(service.isGattConnected, isTrue);

      final readings = await service.syncHistory(
        startedAt: DateTime.now().subtract(const Duration(minutes: 3)),
        endedAt: DateTime.now(),
      );

      final historyWrite = platform.writes.lastWhere(
        (write) => write.isNotEmpty && write.first == 0x00,
      );
      expect(historyWrite, hasLength(10));
      expect(historyWrite.take(2), [0x00, 0x00]);
      expect(readings, isNotEmpty);
      expect(readings.first.temperatureFahrenheit, closeTo(77.0, 0.1));
      expect(readings.first.humidity, closeTo(65.0, 0.1));
    });

    test('completes H5051 epoch-minute sync on 0x02 status', () async {
      platform
        ..platformName = 'Govee_H5051_ECC3'
        ..epochMinuteUsesShortCompletion = true;

      final service = GoveeService();
      addTearDown(service.dispose);
      await service.initializeBle();
      await service.startScan(
        timeout: const Duration(seconds: 5),
        discoveryTimeout: const Duration(seconds: 5),
      );

      for (var i = 0; i < 20 && !service.isGattConnected; i += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(service.isGattConnected, isTrue);

      final readings = await service
          .syncHistory(
            startedAt: DateTime.now().subtract(const Duration(minutes: 3)),
            endedAt: DateTime.now(),
          )
          .timeout(const Duration(seconds: 1));

      expect(readings, isNotEmpty);
      expect(
        service.diagnostics,
        contains(contains('History sync complete: 1 packets')),
      );
    });

    test(
      'missing history characteristics fail sync instead of returning empty',
      () async {
        platform
          ..platformName = 'Govee_H5051_ECC3'
          ..includeHistoryCharacteristics = false;

        final service = GoveeService();
        addTearDown(service.dispose);
        await service.initializeBle();
        await service.startScan(
          timeout: const Duration(seconds: 5),
          discoveryTimeout: const Duration(seconds: 5),
        );

        for (var i = 0; i < 20 && !service.isGattConnected; i += 1) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(service.isGattConnected, isTrue);

        await expectLater(
          service.syncHistory(
            startedAt: DateTime.now().subtract(const Duration(minutes: 3)),
            endedAt: DateTime.now(),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('history/control/data characteristics'),
            ),
          ),
        );
        expect(
          service.diagnostics,
          contains(
            contains(
              'History sync needs connected H5051 history/control/data characteristics',
            ),
          ),
        );
      },
    );

    test('macOS scan uses a single adapter-state readiness check', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });

      final service = GoveeService();
      addTearDown(service.dispose);
      await service.startScan(
        timeout: const Duration(milliseconds: 10),
        discoveryTimeout: const Duration(milliseconds: 10),
      );

      expect(platform.calls, contains('startScan'));
      expect(platform.calls, isNot(contains('isSupported')));
      expect(
        platform.calls.where((call) => call == 'getAdapterState').length,
        lessThanOrEqualTo(1),
      );
    });

    test('builds 0x3301 history request payloads with checksum', () {
      expect(
        GoveeService.buildGoveeHistoryRequestForTesting(
          startMinutesBack: 21,
          endMinutesBack: 2,
        ),
        const [
          0x33,
          0x01,
          0x00,
          0x15,
          0x00,
          0x02,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x25,
        ],
      );

      expect(
        GoveeService.buildGoveeHistoryRequestForTesting(
          startMinutesBack: 28800,
          endMinutesBack: 1,
        ),
        const [
          0x33,
          0x01,
          0x70,
          0x80,
          0x00,
          0x01,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0xc3,
        ],
      );
    });

    test('parses history data packets into minute timestamps', () {
      final baseMinute = DateTime.parse('2026-05-02T10:30:00');
      final readings =
          GoveeService.parseGoveeHistoryDataPacketForTesting(const [
            0x00,
            0x15,
            0x03,
            0x71,
            0xe7,
            0x03,
            0x75,
            0xcf,
            0x03,
            0x71,
            0xe7,
            0x03,
            0x75,
            0xcf,
            0x03,
            0x71,
            0xe6,
            0x03,
            0x75,
            0xce,
          ], syncBaseMinute: baseMinute);

      expect(readings, hasLength(6));
      expect(readings.first.timestamp, DateTime.parse('2026-05-02T10:09:00'));
      expect(readings.last.timestamp, DateTime.parse('2026-05-02T10:14:00'));
      expect(readings.first.temperatureFahrenheit, closeTo(72.5, 0.1));
      expect(readings.first.humidity, closeTo(76.7, 0.1));
    });

    test('skips padded history records', () {
      final readings =
          GoveeService.parseGoveeHistoryDataPacketForTesting(const [
            0x00,
            0x03,
            0x03,
            0x75,
            0xcf,
            0x03,
            0x75,
            0xcf,
            0x03,
            0x75,
            0xce,
            0xff,
            0xff,
            0xff,
            0xff,
            0xff,
            0xff,
            0xff,
            0xff,
            0xff,
            0xff,
          ], syncBaseMinute: DateTime.parse('2026-05-02T10:30:00'));

      expect(readings, hasLength(3));
    });

    test('parses history completion message count', () {
      expect(
        GoveeService.parseGoveeHistoryCompletionCountForTesting(const [
          0xee,
          0x01,
          0x00,
          0x04,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0xeb,
        ]),
        4,
      );
    });
  });

  group('GoveeService command response parser', () {
    test('ignores empty 0x0A command echoes', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
        0xaa,
        0x0a,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0xa0,
      ]);

      expect(reading, isNull);
    });

    test('parses temperature and humidity from 0x0A response', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
        0xaa,
        0x0a,
        0xfd,
        0x09,
        0x08,
        0x17,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x4b,
      ]);

      expect(reading, isNotNull);
      expect(reading!.temperatureFahrenheit, closeTo(78.026, 0.001));
      expect(reading.humidity, closeTo(58.96, 0.001));
    });

    test('parses live H5051 0x0A response from diagnostic log', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
        0xaa,
        0x0a,
        0xa3,
        0x09,
        0xd3,
        0x17,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0xce,
      ]);

      expect(reading, isNotNull);
      expect(reading!.temperatureFahrenheit, closeTo(76.406, 0.001));
      expect(reading.humidity, closeTo(60.99, 0.001));
    });

    test(
      'parses battery-only 0x08 responses without changing temp or humidity',
      () {
        final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
          0xaa,
          0x08,
          0x63,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0xc1,
        ]);

        expect(reading, isNotNull);
        expect(reading!.batteryPercent, 99);
        expect(reading.temperatureFahrenheit, isNull);
        expect(reading.humidity, isNull);
      },
    );

    test('rejects invalid checksum for command responses', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
        0xaa,
        0x0a,
        0xfd,
        0x09,
        0x08,
        0x17,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0xff,
      ]);

      expect(reading, isNull);
    });

    test('rejects command responses shorter than 3 bytes', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
        0xaa,
        0x0a,
      ]);

      expect(reading, isNull);
    });

    test('rejects battery responses with value over 100', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
        0xaa,
        0x08,
        0x80,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x22,
      ]);

      expect(reading, isNull);
    });

    test('rejects responses with non-AA prefix', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
        0xbb,
        0x0a,
        0xfd,
        0x09,
        0x08,
        0x17,
      ]);

      expect(reading, isNull);
    });

    test('rejects command responses with all-zero payload', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
        0xaa,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);

      expect(reading, isNull);
    });

    test('rejects invalid temperature range from command responses', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
        0xaa,
        0x0a,
        0x00,
        0x80,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x2a,
      ]);

      expect(reading, isNull);
    });

    test('handles empty byte list gracefully', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(
        const [],
      );

      expect(reading, isNull);
    });
  });

  group('H5051 advertisement parser (via testing wrapper)', () {
    test('parses valid H5051 9-byte advertisement', () {
      final reading = GoveeService.parseH5051ForTesting(const [
        0x00,
        0xa3,
        0x09,
        0xd3,
        0x17,
        0x63,
        0x00,
        0x00,
        0x00,
      ]);

      expect(reading, isNotNull);
      expect(reading!.temperatureFahrenheit, isNotNull);
      expect(reading.humidity, isNotNull);
      expect(reading.batteryPercent, 99);
    });

    test('rejects H5051 advertisement with wrong length', () {
      final reading = GoveeService.parseH5051ForTesting(const [
        0x00,
        0xa3,
        0x09,
        0xd3,
        0x17,
        0x63,
        0x00,
        0x00,
      ]);

      expect(reading, isNull);
    });

    test('rejects H5051 with invalid temperature', () {
      final reading = GoveeService.parseH5051ForTesting(const [
        0x00,
        0x00,
        0xff,
        0xff,
        0x7f,
        0x63,
        0x00,
        0x00,
        0x00,
      ]);

      expect(reading, isNull);
    });

    test('rejects H5051 with invalid humidity', () {
      final reading = GoveeService.parseH5051ForTesting(const [
        0x00,
        0xa3,
        0x09,
        0x00,
        0xff,
        0x63,
        0x00,
        0x00,
        0x00,
      ]);

      expect(reading, isNull);
    });
  });

  group('H5051 short advertisement parser (via testing wrapper)', () {
    test('parses valid H5051 7-byte short advertisement', () {
      final reading = GoveeService.parseH5051ShortAdvertForTesting(const [
        0x10,
        0x05,
        0x86,
        0x1c,
        0x00,
        0x00,
        0x00,
      ]);

      expect(reading, isNotNull);
      expect(reading!.temperatureFahrenheit, isNotNull);
      expect(reading.humidity, isNull);
    });

    test('rejects short advert with wrong prefix', () {
      final reading = GoveeService.parseH5051ShortAdvertForTesting(const [
        0x00,
        0x05,
        0x86,
        0x1c,
        0x00,
        0x00,
        0x00,
      ]);

      expect(reading, isNull);
    });

    test('rejects short advert with wrong length', () {
      final reading = GoveeService.parseH5051ShortAdvertForTesting(const [
        0x10,
        0x05,
        0x86,
        0x1c,
        0x00,
        0x00,
      ]);

      expect(reading, isNull);
    });

    test('rejects short advert with out-of-range temp', () {
      final reading = GoveeService.parseH5051ShortAdvertForTesting(const [
        0x10,
        0x05,
        0x00,
        0x80,
        0x00,
        0x00,
        0x00,
      ]);

      expect(reading, isNull);
    });
  });

  group('Govee combined advertisement parser (via testing wrapper)', () {
    test('parses valid Govee combined 6-byte advert', () {
      final reading = GoveeService.parseGoveeCombinedAdvertForTesting(const [
        0x00,
        0x03,
        0x84,
        0x66,
        0x63,
        0x00,
      ], manufacturerId: 0xEC88);

      expect(reading, isNotNull);
      expect(reading!.temperatureFahrenheit, isNotNull);
      expect(reading.humidity, isNotNull);
      expect(reading.batteryPercent, 99);
    });

    test('rejects combined advert with invalid length', () {
      final reading = GoveeService.parseGoveeCombinedAdvertForTesting(const [
        0x00,
        0x4c,
        0xc8,
        0xaf,
        0x63,
      ], manufacturerId: 0xEC88);

      expect(reading, isNull);
    });

    test('rejects combined advert with non-Govee manufacturer id', () {
      final reading = GoveeService.parseGoveeCombinedAdvertForTesting(const [
        0x00,
        0x4c,
        0xc8,
        0xaf,
        0x63,
        0x00,
      ], manufacturerId: 0x0001);

      expect(reading, isNull);
    });
  });
}
