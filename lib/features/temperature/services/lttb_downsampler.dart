import 'dart:math' as math;

class LttbDownsampler {
  static const int defaultMinPoints = 50;
  static const int defaultMaxPoints = 500;
  static const double defaultRatio = 0.10;

  const LttbDownsampler._();

  static int targetCount(
    int readingCount, {
    double ratio = defaultRatio,
    int minPoints = defaultMinPoints,
    int maxPoints = defaultMaxPoints,
  }) {
    if (readingCount <= minPoints) return readingCount;
    return (readingCount * ratio).round().clamp(minPoints, maxPoints).toInt();
  }

  static List<T> downsample<T>(
    List<T> readings, {
    required DateTime Function(T reading) timestampFor,
    required double Function(T reading) yFor,
    double ratio = defaultRatio,
    int minPoints = defaultMinPoints,
    int maxPoints = defaultMaxPoints,
  }) {
    final target = targetCount(
      readings.length,
      ratio: ratio,
      minPoints: minPoints,
      maxPoints: maxPoints,
    );
    if (readings.length <= target) return readings;

    final sorted = [...readings]
      ..sort((a, b) => timestampFor(a).compareTo(timestampFor(b)));
    if (target < 3) return [sorted.first, sorted.last];

    final sampled = <T>[sorted.first];
    final every = (sorted.length - 2) / (target - 2);
    var anchorIndex = 0;

    for (var i = 0; i < target - 2; i += 1) {
      final averageStart = ((i + 1) * every).floor() + 1;
      final averageEnd = math.min(((i + 2) * every).floor() + 1, sorted.length);
      final averageRange = sorted.sublist(averageStart, averageEnd);
      final averageX = averageRange.isEmpty
          ? timestampFor(sorted.last).millisecondsSinceEpoch.toDouble()
          : averageRange
                    .map(
                      (reading) => timestampFor(
                        reading,
                      ).millisecondsSinceEpoch.toDouble(),
                    )
                    .reduce((a, b) => a + b) /
                averageRange.length;
      final averageY = averageRange.isEmpty
          ? yFor(sorted.last)
          : averageRange.map(yFor).reduce((a, b) => a + b) /
                averageRange.length;

      final rangeStart = (i * every).floor() + 1;
      final rangeEnd = math.min(
        math.max(rangeStart + 1, ((i + 1) * every).floor() + 1),
        sorted.length - 1,
      );
      final anchor = sorted[anchorIndex];
      final anchorX = timestampFor(anchor).millisecondsSinceEpoch.toDouble();
      final anchorY = yFor(anchor);

      var maxArea = -1.0;
      var nextIndex = rangeStart;
      for (
        var candidateIndex = rangeStart;
        candidateIndex < rangeEnd;
        candidateIndex += 1
      ) {
        final candidate = sorted[candidateIndex];
        final candidateX = timestampFor(
          candidate,
        ).millisecondsSinceEpoch.toDouble();
        final candidateY = yFor(candidate);
        final area =
            ((anchorX - averageX) * (candidateY - anchorY) -
                    (anchorX - candidateX) * (averageY - anchorY))
                .abs() /
            2;
        if (area > maxArea) {
          maxArea = area;
          nextIndex = candidateIndex;
        }
      }

      sampled.add(sorted[nextIndex]);
      anchorIndex = nextIndex;
    }

    sampled.add(sorted.last);
    return sampled;
  }
}
