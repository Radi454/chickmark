import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/temperature/services/lttb_downsampler.dart';

class _SampleReading {
  final DateTime timestamp;
  final double temperatureFahrenheit;
  final double humidity;

  const _SampleReading({
    required this.timestamp,
    required this.temperatureFahrenheit,
    required this.humidity,
  });
}

void main() {
  _SampleReading reading(int index, {double? temp, double? humidity}) {
    return _SampleReading(
      timestamp: DateTime(2026, 5, 2, 10).add(Duration(seconds: index)),
      temperatureFahrenheit: temp ?? 70 + index / 100,
      humidity: humidity ?? 55 + index / 200,
    );
  }

  List<_SampleReading> readings(int count) =>
      List.generate(count, (index) => reading(index));

  List<_SampleReading> downsample(List<_SampleReading> input) {
    return LttbDownsampler.downsample<_SampleReading>(
      input,
      timestampFor: (sample) => sample.timestamp,
      yFor: (sample) => sample.temperatureFahrenheit + sample.humidity,
    );
  }

  test('empty list returns empty', () {
    expect(downsample(const []), isEmpty);
  });

  test('fewer than 50 returns all', () {
    final input = readings(49);

    expect(downsample(input), same(input));
  });

  test('exactly 50 returns all', () {
    final input = readings(50);

    expect(downsample(input), same(input));
  });

  test('target count follows ten percent with min and max bounds', () {
    expect(downsample(readings(500)), hasLength(50));
    expect(downsample(readings(1000)), hasLength(100));
    expect(downsample(readings(10000)), hasLength(500));
  });

  test('first and last readings are preserved in timestamp order', () {
    final input = readings(1000);

    final output = downsample(input);

    expect(output.first, same(input.first));
    expect(output.last, same(input.last));
    for (var i = 1; i < output.length; i += 1) {
      expect(output[i].timestamp.isBefore(output[i - 1].timestamp), isFalse);
    }
  });

  test('clear temperature spike is preserved', () {
    final input = readings(1000);
    final spike = reading(500, temp: 125, humidity: 56);
    input[500] = spike;

    expect(downsample(input), contains(same(spike)));
  });

  test('clear humidity spike is preserved', () {
    final input = readings(1000);
    final spike = reading(500, temp: 73, humidity: 95);
    input[500] = spike;

    expect(downsample(input), contains(same(spike)));
  });
}
