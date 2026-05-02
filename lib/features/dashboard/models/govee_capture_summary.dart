import 'package:hatchaudit/data/models/govee_capture_model.dart';

class GoveeCaptureSummary {
  final GoveeDailyCaptureModel capture;
  final List<GoveeSpotCaptureModel> spots;
  final List<GoveeSpotReadingModel> readings;

  const GoveeCaptureSummary({
    required this.capture,
    required this.spots,
    required this.readings,
  });

  List<GoveeChartPoint> get combinedTempPoints {
    var x = 0;
    final points = <GoveeChartPoint>[];
    for (final spot in _sortedSpots) {
      for (final reading in _readingsForSpot(spot.id)) {
        points.add(
          GoveeChartPoint(
            x: x,
            temperatureFahrenheit: reading.temperatureFahrenheit,
            humidity: reading.humidity,
            recordedAt: reading.recordedAt,
            spotIndex: spot.spotIndex,
            spotLabel: spot.spotLabel,
          ),
        );
        x++;
      }
    }
    if (points.isNotEmpty || spots.isNotEmpty) return points;

    final sortedReadings = [...readings]
      ..sort((a, b) {
        final spotCompare = a.spotId.compareTo(b.spotId);
        if (spotCompare != 0) return spotCompare;
        return a.readingIndex.compareTo(b.readingIndex);
      });
    for (final reading in sortedReadings) {
      points.add(
        GoveeChartPoint(
          x: x,
          temperatureFahrenheit: reading.temperatureFahrenheit,
          humidity: reading.humidity,
          recordedAt: reading.recordedAt,
        ),
      );
      x++;
    }
    return points;
  }

  List<int> get spotBoundaryIndexes {
    var count = 0;
    final boundaries = <int>[];
    final sorted = _sortedSpots;
    for (var i = 0; i < sorted.length - 1; i++) {
      count += _readingsForSpot(sorted[i].id).length;
      if (count > 0) boundaries.add(count);
    }
    return boundaries;
  }

  List<GoveeSpotCaptureModel> get sortedSpots => _sortedSpots;

  List<GoveeSpotCaptureModel> get _sortedSpots {
    return [...spots]..sort((a, b) => a.spotIndex.compareTo(b.spotIndex));
  }

  List<GoveeSpotReadingModel> _readingsForSpot(String spotId) {
    return readings.where((reading) => reading.spotId == spotId).toList()
      ..sort((a, b) {
        final indexCompare = a.readingIndex.compareTo(b.readingIndex);
        if (indexCompare != 0) return indexCompare;
        return a.recordedAt.compareTo(b.recordedAt);
      });
  }
}

class GoveeChartPoint {
  final int x;
  final double temperatureFahrenheit;
  final double humidity;
  final DateTime recordedAt;
  final int? spotIndex;
  final String? spotLabel;

  const GoveeChartPoint({
    required this.x,
    required this.temperatureFahrenheit,
    required this.humidity,
    required this.recordedAt,
    this.spotIndex,
    this.spotLabel,
  });
}
