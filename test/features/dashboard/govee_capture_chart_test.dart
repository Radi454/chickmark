import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/govee_capture_model.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/features/dashboard/models/govee_capture_summary.dart';
import 'package:hatchaudit/features/dashboard/widgets/govee_capture_chart.dart';

void main() {
  test('GoveeCaptureSummary combines place readings in timestamp order', () {
    final summary = _makeSummary();
    final firstTimestamp = DateTime(2026, 5, 2, 12);
    final lastTimestamp = DateTime(2026, 5, 2, 12, 1, 39);

    expect(summary.combinedPoints, hasLength(100));
    expect(
      summary.combinedPoints.first.x,
      firstTimestamp.millisecondsSinceEpoch.toDouble(),
    );
    expect(
      summary.combinedPoints.last.x,
      lastTimestamp.millisecondsSinceEpoch.toDouble(),
    );
    expect(summary.combinedTempPoints, hasLength(100));
  });

  testWidgets('GoveeCaptureChart renders place metadata and both charts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GoveeCaptureChart(summary: _makeSummary())),
      ),
    );

    expect(find.text('Egg storage room'), findsOneWidget);
    expect(find.text('Setter 7'), findsOneWidget);
    expect(find.text('2026-05-02'), findsOneWidget);
    expect(find.text('12:00 PM - 12:04 PM'), findsOneWidget);
    expect(
      find.text('Temp avg 72.4F / min 70.9F / max 73.8F / SD 1.2 / CV 1.7%'),
      findsOneWidget,
    );
    expect(
      find.text('RH avg 57.2% / min 55.1% / max 60.2% / SD 2.1 / CV 3.7%'),
      findsOneWidget,
    );
    expect(find.text('100 readings'), findsOneWidget);
    expect(find.textContaining('spots'), findsNothing);
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('Relative Humidity'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('govee-temperature-chart-capture-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('govee-rh-chart-capture-1')),
      findsOneWidget,
    );
  });

  testWidgets(
    'GoveeCaptureChart tooltip includes timestamp and place details',
    (tester) async {
      final summary = _makeSummary();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GoveeCaptureChart(summary: summary)),
        ),
      );

      final chart = tester.widget<LineChart>(
        find.byKey(const ValueKey('govee-temperature-chart-capture-1')),
      );
      final bar = chart.data.lineBarsData.single;
      final tooltipItems = chart.data.lineTouchData.touchTooltipData
          .getTooltipItems([LineBarSpot(bar, 0, bar.spots.first)]);

      expect(tooltipItems, hasLength(1));
      expect(tooltipItems.single!.text, contains('2026-05-02 12:00:00'));
      expect(tooltipItems.single!.text, contains('Temp 71.0F'));
      expect(tooltipItems.single!.text, contains('RH 56.0%'));
      expect(tooltipItems.single!.text, isNot(contains('Spot')));
      expect(tooltipItems.single!.text, contains('Egg storage room'));
      expect(tooltipItems.single!.text, contains('Setter 7'));
    },
  );
}

GoveeCaptureSummary _makeSummary() {
  final now = DateTime(2026, 5, 2, 12);
  final capture = GoveeDailyCaptureModel(
    id: 'capture-1',
    customerId: 'customer-1',
    hatcheryId: 'hatchery-1',
    place: TemperaturePlace.eggStorageRoom,
    machineId: 'Setter 7',
    captureDate: '2026-05-02',
    startedAt: now,
    endedAt: now.add(const Duration(minutes: 4)),
    status: 'completed',
    tempAvg: 72.4,
    tempMin: 70.9,
    tempMax: 73.8,
    tempSd: 1.2,
    tempCvPct: 1.7,
    rhAvg: 57.2,
    rhMin: 55.1,
    rhMax: 60.2,
    rhSd: 2.1,
    rhCvPct: 3.7,
    readingCount: 100,
    createdAt: now,
    updatedAt: now,
  );

  return GoveeCaptureSummary(
    capture: capture,
    readings: [
      for (var i = 0; i < 100; i++)
        GoveePlaceReadingModel(
          id: 'reading-$i',
          captureId: capture.id,
          readingIndex: i,
          recordedAt: now.add(Duration(seconds: i)),
          temperatureFahrenheit: 71 + (i / 100),
          humidity: 56 + (i / 100),
          createdAt: now,
        ),
    ],
  );
}
