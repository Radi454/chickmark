import 'package:hatchaudit/data/models/govee_capture_model.dart';

import 'dashboard_intelligence_models.dart';

class GoveeCaptureSummary {
  final GoveeDailyCaptureModel capture;
  final List<GoveePlaceReadingModel> readings;

  const GoveeCaptureSummary({required this.capture, required this.readings});

  List<GoveeChartPoint> get combinedPoints {
    final sortedReadings = [...readings]
      ..sort((a, b) {
        final timeCompare = a.recordedAt.compareTo(b.recordedAt);
        if (timeCompare != 0) return timeCompare;
        return a.readingIndex.compareTo(b.readingIndex);
      });
    return sortedReadings
        .map(
          (reading) => GoveeChartPoint(
            x: reading.recordedAt.millisecondsSinceEpoch.toDouble(),
            temperatureFahrenheit: reading.temperatureFahrenheit,
            humidity: reading.humidity,
            recordedAt: reading.recordedAt,
          ),
        )
        .toList(growable: false);
  }

  List<GoveeChartPoint> get combinedTempPoints => combinedPoints;

  DateTime? get recordingStartedAt {
    if (capture.startedAt != null) return capture.startedAt;
    final points = combinedPoints;
    if (points.isNotEmpty) return points.first.recordedAt;
    return null;
  }

  DateTime? get recordingEndedAt {
    if (capture.endedAt != null) return capture.endedAt;
    final points = combinedPoints;
    if (points.isNotEmpty) return points.last.recordedAt;
    return null;
  }

  DateTime get effectiveRecordedAt =>
      recordingEndedAt ?? recordingStartedAt ?? capture.updatedAt;

  DashboardFreshness freshnessAt(DateTime now) {
    final at = effectiveRecordedAt;
    if (at.isAfter(now.add(const Duration(minutes: 5)))) {
      return DashboardFreshness.invalid;
    }
    final age = now.difference(at);
    if (age <= const Duration(hours: 48)) return DashboardFreshness.current;
    if (age <= const Duration(days: 7)) return DashboardFreshness.aging;
    return DashboardFreshness.stale;
  }
}

class GoveeChartPoint {
  final double x;
  final double temperatureFahrenheit;
  final double humidity;
  final DateTime recordedAt;

  const GoveeChartPoint({
    required this.x,
    required this.temperatureFahrenheit,
    required this.humidity,
    required this.recordedAt,
  });
}
