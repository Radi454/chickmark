import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/models/est_grid_data.dart';

void main() {
  group('EstGridData.normalizeReadings', () {
    test('maps legacy door location keys to front location keys', () {
      final normalized = EstGridData.normalizeReadings({
        'door_top': 19.5,
        'door_middle': 20.1,
        'door_bottom': 20.3,
        'middle_top': 19.8,
      });

      expect(normalized['front_top'], 19.5);
      expect(normalized['front_middle'], 20.1);
      expect(normalized['front_bottom'], 20.3);
      expect(normalized['middle_top'], 19.8);
      expect(normalized.containsKey('door_top'), isFalse);
    });
  });

  group('EstGridData scan contract', () {
    test('uses front-first scan order within each position', () {
      expect(EstGridData.scanKeys, [
        'front_top',
        'front_middle',
        'front_bottom',
        'middle_top',
        'middle_middle',
        'middle_bottom',
        'back_top',
        'back_middle',
        'back_bottom',
      ]);
    });

    test('returns structured data with position level and value', () {
      final structured = EstGridData.toStructuredReadings({
        'front_top': 20.1,
        'back_bottom': 19.8,
      });

      expect(structured, [
        {'position': 'Front', 'level': 'Top', 'value': 20.1},
        {'position': 'Back', 'level': 'Bottom', 'value': 19.8},
      ]);
    });
  });
}
