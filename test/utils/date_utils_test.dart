import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/utils/date_utils.dart';

void main() {
  group('HatchDateUtils', () {
    test('flockAgeWeeks returns correct weeks for known entry date', () {
      // Example: entryDate = 2026-04-04, today = 2026-04-18
      final entryDate = DateTime(2026, 4, 4);
      final today = DateTime(2026, 4, 18);
      expect(HatchDateUtils.flockAgeWeeks(entryDate, now: today), 2);
    });
    test('flockAgeDays returns correct days for known entry date', () {
      final entryDate = DateTime(2026, 4, 4);
      final today = DateTime(2026, 4, 18);
      expect(HatchDateUtils.flockAgeDays(entryDate, now: today), 14);
    });
    test('bmkAgeWeeks formula = (flockAgeDays - 21) / 7', () {
      final entryDate = DateTime(2026, 3, 24);
      final today = DateTime(2026, 4, 21);
      // flockAgeDays = 28, bmkAgeWeeks = 1
      expect(HatchDateUtils.bmkAgeWeeks(entryDate, 0, now: today), 1);
    });
    test('bmkAgeWeeks with storageDays=5 reduces correctly', () {
      final entryDate = DateTime(2026, 3, 24);
      final today = DateTime(2026, 4, 28);
      // flockAgeDays = 35, bmkAgeWeeks = (35-21-5)/7 = 1.2857
      expect(
        HatchDateUtils.bmkAgeWeeks(entryDate, 5, now: today),
        closeTo(1.29, 0.01),
      );
    });
    test('zero-day flock', () {
      final entryDate = DateTime(2026, 4, 18);
      final today = DateTime(2026, 4, 18);
      expect(HatchDateUtils.flockAgeDays(entryDate, now: today), 0);
      expect(HatchDateUtils.flockAgeWeeks(entryDate, now: today), 0);
    });
    test('formatDisplayDate returns dd-MM-yyyy with leading zeroes', () {
      expect(
        HatchDateUtils.formatDisplayDate(DateTime(2026, 4, 7)),
        '07-04-2026',
      );
    });
    test('formatDisplayDateKey displays ISO date keys as dd-MM-yyyy', () {
      expect(HatchDateUtils.formatDisplayDateKey('2026-05-02'), '02-05-2026');
    });
    test('formatDisplayDateTime returns dd-MM-yyyy before the time', () {
      expect(
        HatchDateUtils.formatDisplayDateTime(DateTime(2026, 4, 7, 8, 5)),
        '07-04-2026 08:05',
      );
    });
  });
}
