import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/govee_capture_model.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/features/dashboard/models/govee_capture_summary.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_models.dart';
import 'package:hatchaudit/features/dashboard/widgets/scope/govee_triage_builder.dart';

/// A capture for [place] whose readings all sit at [tempF] / [rh].
GoveeCaptureSummary _cap(
  TemperaturePlace place, {
  required double tempF,
  required double rh,
}) {
  final now = DateTime(2026, 6, 6);
  final capture = GoveeDailyCaptureModel(
    id: place.name,
    customerId: 'c',
    hatcheryId: 'h',
    place: place,
    captureDate: '2026-06-06',
    status: 'completed',
    readingCount: 2,
    createdAt: now,
    updatedAt: now,
  );
  final readings = [
    for (var i = 0; i < 2; i++)
      GoveePlaceReadingModel(
        id: '${place.name}-$i',
        captureId: place.name,
        readingIndex: i,
        recordedAt: now,
        temperatureFahrenheit: tempF,
        humidity: rh,
        createdAt: now,
      ),
  ];
  return GoveeCaptureSummary(capture: capture, readings: readings);
}

void main() {
  test('converts °F→°C and grades temp band + RH ceiling', () {
    final items = goveeTriageItems([
      // 99.32°F = 37.4°C → 0.2 over the 36.7–37.2 band → Watch.
      _cap(TemperaturePlace.insideHatcher, tempF: 99.32, rh: 50),
      // 75.2°F = 24.0°C → inside 23–25 (good); RH 67 vs ≤65 → Watch.
      _cap(TemperaturePlace.hatcherRoom, tempF: 75.2, rh: 67),
    ]);

    final hatcherTemp = items.firstWhere(
      (i) => i.primaryTag == 'Inside hatcher' && i.metric == 'Temperature',
    );
    expect(hatcherTemp.severity, ScopeSeverity.warn);
    expect(hatcherTemp.value, '37.4 °C');
    expect(hatcherTemp.context, contains('36.7'));

    final roomTemp = items.firstWhere(
      (i) => i.primaryTag == 'Hatcher room' && i.metric == 'Temperature',
    );
    expect(roomTemp.severity, ScopeSeverity.good);

    final roomRh = items.firstWhere(
      (i) => i.primaryTag == 'Hatcher room' && i.metric == 'Relative Humidity',
    );
    expect(roomRh.severity, ScopeSeverity.warn);
    expect(roomRh.value, '67%');
  });

  test('outside hatchery has no targets → no items', () {
    final items = goveeTriageItems([
      _cap(TemperaturePlace.outsideHatchery, tempF: 50, rh: 90),
    ]);
    expect(items, isEmpty);
  });
}
