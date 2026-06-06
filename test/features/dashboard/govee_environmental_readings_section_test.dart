import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/govee_capture_model.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/features/dashboard/models/govee_capture_summary.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/govee_environmental_readings_section.dart';
import 'package:hatchaudit/providers/app_provider.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Govee sector appears when captures exist', (tester) async {
    await _pumpSection(
      tester,
      captures: [
        _makeSummary(id: 'egg', place: TemperaturePlace.eggStorageRoom),
      ],
    );

    expect(find.text('Govee Environmental Readings'), findsOneWidget);
    expect(find.text('Egg storage room'), findsWidgets);
  });

  testWidgets('multiple places render as tabs, only selected group shown', (
    tester,
  ) async {
    await _pumpSection(
      tester,
      captures: [
        _makeSummary(id: 'egg', place: TemperaturePlace.eggStorageRoom),
        _makeSummary(
          id: 'setter-1',
          place: TemperaturePlace.insideSetter,
          machineId: 'Setter 1',
        ),
      ],
    );

    // A tab exists for every place.
    expect(
      find.byKey(const ValueKey('govee-place-tab-eggStorageRoom')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('govee-place-tab-insideSetter')),
      findsOneWidget,
    );

    // The first place (lowest enum index) is selected by default, so only
    // its group and capture card are mounted.
    expect(
      find.byKey(const ValueKey('govee-place-group-eggStorageRoom')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('govee-place-group-insideSetter')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('govee-capture-card-egg')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('govee-capture-card-setter-1')),
      findsNothing,
    );
  });

  testWidgets('tapping a place tab switches the visible group', (
    tester,
  ) async {
    await _pumpSection(
      tester,
      captures: [
        _makeSummary(id: 'egg', place: TemperaturePlace.eggStorageRoom),
        _makeSummary(id: 'chicks', place: TemperaturePlace.chickHoldingArea),
      ],
    );

    // Egg storage room is selected first.
    expect(
      find.byKey(const ValueKey('govee-capture-card-egg')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('govee-capture-card-chicks')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('govee-place-tab-chickHoldingArea')),
    );
    await tester.pumpAndSettle();

    // Now only the chick holding area group is mounted.
    expect(
      find.byKey(const ValueKey('govee-capture-card-chicks')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('govee-capture-card-egg')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('govee-place-group-eggStorageRoom')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('govee-place-group-chickHoldingArea')),
      findsOneWidget,
    );
  });

  testWidgets('inside machine place groups keep machine captures separated', (
    tester,
  ) async {
    await _pumpSection(
      tester,
      captures: [
        _makeSummary(
          id: 'setter-1',
          place: TemperaturePlace.insideSetter,
          machineId: 'Setter 1',
        ),
        _makeSummary(
          id: 'setter-2',
          place: TemperaturePlace.insideSetter,
          machineId: 'Setter 2',
        ),
      ],
    );

    final setterGroup = find.byKey(
      const ValueKey('govee-place-group-insideSetter'),
    );

    expect(setterGroup, findsOneWidget);
    expect(find.text('Setter 1'), findsWidgets);
    expect(find.text('Setter 2'), findsWidgets);
    expect(
      find.descendant(
        of: setterGroup,
        matching: find.byKey(const ValueKey('govee-capture-card-setter-1')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: setterGroup,
        matching: find.byKey(const ValueKey('govee-capture-card-setter-2')),
      ),
      findsOneWidget,
    );
  });
}

Future<void> _pumpSection(
  WidgetTester tester, {
  required List<GoveeCaptureSummary> captures,
  Widget? outsideChild,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => AppProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ?outsideChild,
              GoveeEnvironmentalReadingsSection(
                captures: captures,
                isLoading: false,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

GoveeCaptureSummary _makeSummary({
  required String id,
  required TemperaturePlace place,
  String? machineId,
}) {
  final now = DateTime(2026, 5, 2, 12);
  final capture = GoveeDailyCaptureModel(
    id: id,
    customerId: 'customer-1',
    hatcheryId: 'hatchery-1',
    place: place,
    machineId: machineId,
    captureDate: '2026-05-02',
    status: 'completed',
    tempAvg: 72.4,
    tempMin: 70.9,
    tempMax: 73.8,
    rhAvg: 57.2,
    rhMin: 55.1,
    rhMax: 60.2,
    readingCount: 2,
    createdAt: now,
    updatedAt: now,
  );
  return GoveeCaptureSummary(
    capture: capture,
    readings: [
      GoveePlaceReadingModel(
        id: '$id-reading-1',
        captureId: id,
        readingIndex: 0,
        recordedAt: now,
        temperatureFahrenheit: 71,
        humidity: 56,
        createdAt: now,
      ),
      GoveePlaceReadingModel(
        id: '$id-reading-2',
        captureId: id,
        readingIndex: 1,
        recordedAt: now.add(const Duration(minutes: 1)),
        temperatureFahrenheit: 72,
        humidity: 57,
        createdAt: now,
      ),
    ],
  );
}
