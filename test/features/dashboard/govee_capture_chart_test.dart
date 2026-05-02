import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/govee_capture_model.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/features/dashboard/models/govee_capture_summary.dart';
import 'package:hatchaudit/features/dashboard/widgets/govee_capture_chart.dart';

void main() {
  test('GoveeCaptureSummary combines readings and exposes spot boundaries', () {
    final summary = _makeSummary();

    expect(summary.combinedTempPoints, hasLength(180));
    expect(summary.combinedTempPoints.first.x, 0);
    expect(summary.combinedTempPoints.last.x, 179);
    expect(summary.spotBoundaryIndexes, [60, 120]);
  });

  testWidgets('GoveeCaptureChart renders place, spot labels, and totals', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GoveeCaptureChart(summary: _makeSummary())),
      ),
    );

    expect(find.text('Egg storage room'), findsOneWidget);
    expect(find.text('2026-05-02'), findsOneWidget);
    expect(find.text('Spot 1'), findsWidgets);
    expect(find.text('Spot 2'), findsWidgets);
    expect(find.text('Spot 3'), findsWidgets);
    expect(find.text('3 spots'), findsOneWidget);
    expect(find.text('180 readings'), findsOneWidget);
  });
}

GoveeCaptureSummary _makeSummary() {
  final now = DateTime(2026, 5, 2, 12);
  final capture = GoveeDailyCaptureModel(
    id: 'capture-1',
    customerId: 'customer-1',
    hatcheryId: 'hatchery-1',
    place: TemperaturePlace.eggStorageRoom,
    captureDate: '2026-05-02',
    status: 'completed',
    tempAvg: 72.4,
    tempMin: 70.9,
    tempMax: 73.8,
    rhAvg: 57.2,
    rhMin: 55.1,
    rhMax: 60.2,
    spotCount: 3,
    readingCount: 180,
    createdAt: now,
    updatedAt: now,
  );
  final spots = [_makeSpot(1), _makeSpot(2), _makeSpot(3)];

  return GoveeCaptureSummary(
    capture: capture,
    spots: spots,
    readings: [
      for (final spot in spots)
        for (var i = 0; i < 60; i++)
          GoveeSpotReadingModel(
            id: '${spot.id}-$i',
            captureId: capture.id,
            spotId: spot.id,
            readingIndex: i,
            recordedAt: now.add(Duration(seconds: i)),
            temperatureFahrenheit: 70 + spot.spotIndex + (i / 100),
            humidity: 55 + spot.spotIndex + (i / 100),
            createdAt: now,
          ),
    ],
  );
}

GoveeSpotCaptureModel _makeSpot(int spotIndex) {
  final now = DateTime(2026, 5, 2, 12).add(Duration(minutes: spotIndex));
  return GoveeSpotCaptureModel(
    id: 'spot-$spotIndex',
    captureId: 'capture-1',
    spotIndex: spotIndex,
    spotLabel: 'Spot $spotIndex',
    warmupStartedAt: now,
    validStartedAt: now.add(const Duration(seconds: 60)),
    validEndedAt: now.add(const Duration(seconds: 120)),
    validDurationSeconds: 60,
    tempAvg: (71 + spotIndex).toDouble(),
    tempMin: (70 + spotIndex).toDouble(),
    tempMax: (72 + spotIndex).toDouble(),
    rhAvg: (55 + spotIndex).toDouble(),
    rhMin: (54 + spotIndex).toDouble(),
    rhMax: (56 + spotIndex).toDouble(),
    readingCount: 60,
    createdAt: now,
    updatedAt: now,
  );
}
