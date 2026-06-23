import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/govee_capture_model.dart';
import 'package:hatchaudit/data/models/hatchery_model.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:hatchaudit/features/govee/providers/govee_capture_provider.dart';
import 'package:hatchaudit/features/govee/widgets/govee_scope_picker.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/services/govee/govee_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockGoveeCaptureRepository extends Mock
    implements GoveeCaptureRepository {}

class _MockGoveeService extends Mock implements GoveeService {}

class _FakeCustomersProvider extends CustomersProvider {
  _FakeCustomersProvider({
    required List<CustomerModel> customers,
    List<FlockModel> flocks = const [],
    required List<HatcheryModel> hatcheries,
  }) : _customers = customers,
       _flocks = flocks,
       _hatcheries = hatcheries;

  final List<CustomerModel> _customers;
  final List<FlockModel> _flocks;
  final List<HatcheryModel> _hatcheries;

  @override
  List<CustomerModel> get allCustomers => _customers;

  @override
  List<FlockModel> get flocks => _flocks;

  @override
  List<FlockModel> get availableFlocks =>
      _flocks.where((flock) => flock.isAvailableForAudit).toList();

  @override
  List<HatcheryModel> get hatcheries => _hatcheries;

  @override
  CustomerModel? customerById(String id) =>
      _customers.where((customer) => customer.id == id).firstOrNull;

  @override
  FlockModel? flockById(String? id) =>
      id == null ? null : _flocks.where((flock) => flock.id == id).firstOrNull;

  @override
  HatcheryModel? hatcheryById(String? id) => id == null
      ? null
      : _hatcheries.where((hatchery) => hatchery.id == id).firstOrNull;

  @override
  Future<void> selectCustomer(CustomerModel customer) async {}
}

void main() {
  setUpAll(() {
    registerFallbackValue(TemperaturePlace.eggStorageRoom);
  });

  testWidgets(
    'setter and hatcher station scopes keep customer and hatchery controls',
    (tester) async {
      final repository = _MockGoveeCaptureRepository();
      final service = _MockGoveeService();
      when(
        () => repository.getCaptureForScope(
          customerId: any(named: 'customerId'),
          hatcheryId: any(named: 'hatcheryId'),
          stationKey: any(named: 'stationKey'),
          place: any(named: 'place'),
          machineId: any(named: 'machineId'),
          captureDate: any(named: 'captureDate'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => repository.getCapturesForDashboard(
          customerId: any(named: 'customerId'),
          hatcheryId: any(named: 'hatcheryId'),
          captureDate: any(named: 'captureDate'),
        ),
      ).thenAnswer((_) async => const <GoveeDailyCaptureModel>[]);
      when(
        () => repository.getReadingsForCapture(any()),
      ).thenAnswer((_) async => const <GoveePlaceReadingModel>[]);
      when(() => service.readings).thenAnswer((_) => const Stream.empty());
      when(() => service.isAvailable).thenReturn(false);
      when(() => service.isConnected).thenReturn(false);
      when(() => service.isGattConnected).thenReturn(false);
      when(() => service.isGattConnecting).thenReturn(false);
      when(() => service.isScanning).thenReturn(false);
      when(() => service.deviceName).thenReturn(null);
      when(() => service.deviceId).thenReturn(null);
      when(() => service.signalStrength).thenReturn(null);
      when(() => service.latestReading).thenReturn(null);
      when(() => service.lastSeenAt).thenReturn(null);
      when(() => service.diagnostics).thenReturn(const []);

      final govee = GoveeCaptureProvider(
        repository: repository,
        goveeService: service,
        enablePhaseTimer: false,
      );
      await govee.configure(
        customerId: 'customer-1',
        hatcheryId: 'hatchery-1',
        place: TemperaturePlace.setterRoom,
        captureDate: '2026-05-02',
        stationKey: 'setters',
        machineId: 'S1',
      );

      final customers = _FakeCustomersProvider(
        customers: [
          CustomerModel(
            id: 'customer-1',
            name: 'Blue Farm',
            createdAt: DateTime(2026, 5, 2),
            createdBy: 'tester',
          ),
        ],
        flocks: [
          FlockModel(
            id: 'flock-1',
            customerId: 'customer-1',
            flockId: 'Flock A',
            breed: 'Ross 308',
            entryDate: DateTime(2026, 4, 1),
          ),
        ],
        hatcheries: [
          HatcheryModel(
            id: 'hatchery-1',
            customerId: 'customer-1',
            name: 'Main Hatchery',
            createdAt: DateTime(2026, 5, 2),
            createdBy: 'tester',
          ),
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GoveeCaptureProvider>.value(value: govee),
            ChangeNotifierProvider<CustomersProvider>.value(value: customers),
          ],
          child: const MaterialApp(home: Scaffold(body: GoveeScopePicker())),
        ),
      );
      await tester.pump();

      expect(find.text('Customer'), findsOneWidget);
      expect(find.text('Flock'), findsOneWidget);
      expect(find.text('Hatchery'), findsOneWidget);
      expect(find.text('Record environment'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('govee-scope-room-choice')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('govee-scope-machine-choice')),
        findsOneWidget,
      );
    },
  );

  testWidgets('room scope hides the capture date field', (tester) async {
    final repository = _MockGoveeCaptureRepository();
    final service = _MockGoveeService();
    when(
      () => repository.getCaptureForScope(
        customerId: any(named: 'customerId'),
        hatcheryId: any(named: 'hatcheryId'),
        stationKey: any(named: 'stationKey'),
        place: any(named: 'place'),
        machineId: any(named: 'machineId'),
        captureDate: any(named: 'captureDate'),
      ),
    ).thenAnswer((_) async => null);
    when(
      () => repository.getCapturesForDashboard(
        customerId: any(named: 'customerId'),
        hatcheryId: any(named: 'hatcheryId'),
        captureDate: any(named: 'captureDate'),
      ),
    ).thenAnswer((_) async => const <GoveeDailyCaptureModel>[]);
    when(
      () => repository.getReadingsForCapture(any()),
    ).thenAnswer((_) async => const <GoveePlaceReadingModel>[]);
    when(() => service.readings).thenAnswer((_) => const Stream.empty());
    when(() => service.isAvailable).thenReturn(false);
    when(() => service.isConnected).thenReturn(false);
    when(() => service.isGattConnected).thenReturn(false);
    when(() => service.isGattConnecting).thenReturn(false);
    when(() => service.isScanning).thenReturn(false);
    when(() => service.deviceName).thenReturn(null);
    when(() => service.deviceId).thenReturn(null);
    when(() => service.signalStrength).thenReturn(null);
    when(() => service.latestReading).thenReturn(null);
    when(() => service.lastSeenAt).thenReturn(null);
    when(() => service.diagnostics).thenReturn(const []);

    final govee = GoveeCaptureProvider(
      repository: repository,
      goveeService: service,
      enablePhaseTimer: false,
    );
    await govee.configure(
      customerId: 'customer-1',
      hatcheryId: 'hatchery-1',
      place: TemperaturePlace.eggStorageRoom,
      captureDate: '2026-05-02',
    );

    final customers = _FakeCustomersProvider(
      customers: [
        CustomerModel(
          id: 'customer-1',
          name: 'Blue Farm',
          createdAt: DateTime(2026, 5, 2),
          createdBy: 'tester',
        ),
      ],
      flocks: [
        FlockModel(
          id: 'flock-1',
          customerId: 'customer-1',
          flockId: 'Flock A',
          breed: 'Ross 308',
          entryDate: DateTime(2026, 4, 1),
        ),
      ],
      hatcheries: [
        HatcheryModel(
          id: 'hatchery-1',
          customerId: 'customer-1',
          name: 'Main Hatchery',
          createdAt: DateTime(2026, 5, 2),
          createdBy: 'tester',
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GoveeCaptureProvider>.value(value: govee),
          ChangeNotifierProvider<CustomersProvider>.value(value: customers),
        ],
        child: const MaterialApp(home: Scaffold(body: GoveeScopePicker())),
      ),
    );
    await tester.pump();

    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('Flock'), findsOneWidget);
    expect(find.text('Flock A'), findsOneWidget);
    expect(find.text('Hatchery'), findsOneWidget);
    expect(find.text('Place'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_today_outlined), findsNothing);
    expect(find.text('02-05-2026'), findsNothing);
  });
}
