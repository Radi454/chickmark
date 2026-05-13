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
    await tester.pumpWidget(_chartHarness(_makeSummary()));

    expect(find.text('Egg storage room'), findsOneWidget);
    expect(find.text('Setter 7'), findsOneWidget);
    expect(find.text('2026-05-02'), findsOneWidget);
    expect(find.text('12:00 PM - 12:04 PM'), findsOneWidget);
    expect(find.text('Temp'), findsOneWidget);
    expect(find.text('RH'), findsOneWidget);
    expect(find.text('72.4F avg'), findsOneWidget);
    expect(find.text('57.2% avg'), findsOneWidget);
    expect(find.text('100 readings'), findsOneWidget);
    expect(find.textContaining('spots'), findsNothing);
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('Relative Humidity'), findsOneWidget);
    expect(find.text('Max'), findsNWidgets(2));
    expect(find.text('Avg'), findsNWidgets(2));
    expect(find.text('Min'), findsNWidgets(2));
    expect(find.text('73.8F'), findsOneWidget);
    expect(find.text('72.4F'), findsOneWidget);
    expect(find.text('70.9F'), findsOneWidget);
    expect(find.text('60.2%'), findsOneWidget);
    expect(find.text('57.2%'), findsOneWidget);
    expect(find.text('55.1%'), findsOneWidget);
    expect(find.byTooltip('Zoom in Temperature'), findsOneWidget);
    expect(find.byTooltip('Zoom out Temperature'), findsOneWidget);
    expect(find.byTooltip('Fit Temperature'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('govee-temperature-chart-capture-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('govee-rh-chart-capture-1')),
      findsOneWidget,
    );

    final chart = tester.widget<LineChart>(
      find.byKey(const ValueKey('govee-temperature-chart-capture-1')),
    );
    expect(chart.transformationConfig.scaleAxis, FlScaleAxis.horizontal);
    expect(chart.transformationConfig.maxScale, greaterThan(1));
    expect(chart.data.extraLinesData.horizontalLines.single.y, 72.4);
    expect(chart.data.extraLinesData.horizontalLines.single.dashArray, [6, 4]);
  });

  testWidgets(
    'GoveeCaptureChart tooltip includes timestamp and place details',
    (tester) async {
      final summary = _makeSummary();
      await tester.pumpWidget(_chartHarness(summary));

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

  testWidgets('GoveeCaptureChart handles empty saved readings', (tester) async {
    final summary = _makeSummary(readingCount: 0, readings: const []);

    await tester.pumpWidget(_chartHarness(summary));

    expect(find.text('No readings saved'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
  });

  testWidgets('GoveeCaptureChart renders a single saved reading', (
    tester,
  ) async {
    final now = DateTime(2026, 5, 2, 12);
    final summary = _makeSummary(
      readingCount: 1,
      readings: [
        GoveePlaceReadingModel(
          id: 'reading-single',
          captureId: 'capture-1',
          readingIndex: 0,
          recordedAt: now,
          temperatureFahrenheit: 71,
          humidity: 56,
          createdAt: now,
        ),
      ],
    );

    await tester.pumpWidget(_chartHarness(summary));

    final chart = tester.widget<LineChart>(
      find.byKey(const ValueKey('govee-temperature-chart-capture-1')),
    );
    expect(chart.data.lineBarsData.single.spots, hasLength(1));
    expect(chart.data.minX, lessThan(chart.data.maxX));
    expect(chart.data.minY, lessThan(chart.data.maxY));
  });
}

Widget _chartHarness(GoveeCaptureSummary summary) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: GoveeCaptureChart(summary: summary)),
    ),
  );
}

GoveeCaptureSummary _makeSummary({
  int readingCount = 100,
  List<GoveePlaceReadingModel>? readings,
}) {
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
    readingCount: readingCount,
    createdAt: now,
    updatedAt: now,
  );

  return GoveeCaptureSummary(
    capture: capture,
    readings:
        readings ??
        [
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
