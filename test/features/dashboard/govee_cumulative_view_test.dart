import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/govee_capture_model.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/features/dashboard/models/govee_capture_summary.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/govee_cumulative_view.dart';

/// GoveeCumulativeView groups captures by date and charts the selected metric
/// across visits. Self-contained (no provider/DB) → plain widget pumps.
GoveeCaptureSummary _summary({
  required String id,
  required String date,
  required double temp,
  required double rh,
}) {
  final now = DateTime(2026, 5, 2, 12);
  return GoveeCaptureSummary(
    capture: GoveeDailyCaptureModel(
      id: id,
      customerId: 'c',
      hatcheryId: 'h',
      place: TemperaturePlace.eggStorageRoom,
      captureDate: date,
      status: 'completed',
      tempAvg: temp,
      rhAvg: rh,
      tempCvPct: 2.0,
      rhCvPct: 3.0,
      readingCount: 1,
      createdAt: now,
      updatedAt: now,
    ),
    readings: const [],
  );
}

void main() {
  Future<void> pump(WidgetTester tester, List<GoveeCaptureSummary> caps) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GoveeCumulativeView(captures: caps),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));
  }

  testWidgets('renders chips, metric table and a trend chart across dates', (
    tester,
  ) async {
    await pump(tester, [
      _summary(id: 'a', date: '2026-03-01', temp: 70.0, rh: 55),
      _summary(id: 'b', date: '2026-05-02', temp: 73.0, rh: 60),
    ]);

    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('Temp °F'), findsWidgets); // metric row
    expect(find.text('RH %'), findsWidgets);
    expect(find.text('1 Mar'), findsWidgets); // date column + x-axis label
    expect(find.text('2 May'), findsWidgets);
  });

  testWidgets('tapping a metric row keeps a chart shown', (tester) async {
    await pump(tester, [
      _summary(id: 'a', date: '2026-03-01', temp: 70.0, rh: 55),
      _summary(id: 'b', date: '2026-05-02', temp: 73.0, rh: 60),
    ]);
    await tester.tap(find.text('RH %').first);
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('empty captures show a note, no chart', (tester) async {
    await pump(tester, const []);
    expect(find.byType(LineChart), findsNothing);
    expect(find.textContaining('No Govee captures'), findsOneWidget);
  });
}
