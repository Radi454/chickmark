import 'package:hatchaudit/data/models/govee_capture_model.dart';

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
