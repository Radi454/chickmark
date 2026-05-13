import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/yfbm_entry_model.dart';

void main() {
  group('YfbmEntry', () {
    test('calculates yolk-free body mass percentage', () {
      final entry = YfbmEntry(chickWeight: 40, yolkWeight: 4);

      expect(entry.yolkPct, 10.0);
    });

    test('returns null for impossible percentages', () {
      expect(YfbmEntry(chickWeight: 40, yolkWeight: 41).yolkPct, isNull);
      expect(YfbmEntry(chickWeight: -40, yolkWeight: 4).yolkPct, isNull);
      expect(YfbmEntry(chickWeight: 40, yolkWeight: -1).yolkPct, isNull);
    });
  });
}
