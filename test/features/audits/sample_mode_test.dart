import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/sample_mode.dart';

void main() {
  group('SampleMode', () {
    test('normalizes null, empty, and unknown values to pool', () {
      expect(SampleMode.normalize(null), SampleMode.pool);
      expect(SampleMode.normalize(''), SampleMode.pool);
      expect(SampleMode.normalize('unknown'), SampleMode.pool);
    });

    test('accepts only pool and compare', () {
      expect(SampleMode.normalize('pool'), SampleMode.pool);
      expect(SampleMode.normalize('compare'), SampleMode.compare);
      expect(SampleMode.isCompare('compare'), isTrue);
      expect(SampleMode.isCompare('pool'), isFalse);
      expect(SampleMode.isCompare('invalid'), isFalse);
    });
  });
}
