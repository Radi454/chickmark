import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/models/egg_grading.dart';

void main() {
  test('catalogue codes are unique and non-empty', () {
    final codes = kEggDefectTypes.map((d) => d.code).toList();
    expect(codes.toSet(), hasLength(codes.length));
    expect(codes.any((c) => c.trim().isEmpty), isFalse);
    expect(codes, contains('dirty'));
    expect(codes, contains('hairline_crack'));
    expect(codes, contains('other'));
  });

  test('summary derives acceptable counts and percentages', () {
    final summary = EggGradingSummary.fromCounts(
      sampleSize: 100,
      rejectedCount: 12,
      counts: {'dirty': 4, 'cracked': 3, 'wrinkled': 2, 'thin_shell': 3},
    );

    expect(summary.acceptableCount, 88);
    expect(summary.rejectedPct, closeTo(12.0, 0.001));
    expect(summary.acceptablePct, closeTo(88.0, 0.001));
    expect(summary.topDefectCode, 'dirty');
    expect(summary.topDefectPct, closeTo(4.0, 0.001));
  });

  test('a defect sum above the sample size is allowed', () {
    final errors = EggGradingValidation.validate(
      sampleSize: 100,
      rejectedCount: 40,
      counts: {'dirty': 60, 'cracked': 55},
    );
    expect(errors, isEmpty);
  });

  test('retained counts cannot exceed zero inspected eggs', () {
    final errors = EggGradingValidation.validate(
      sampleSize: 0,
      rejectedCount: 12,
      counts: {'dirty': 4},
    );

    expect(errors, contains('Eggs rejected cannot exceed eggs inspected.'));
    expect(errors, contains('Dirty count cannot exceed eggs inspected.'));
  });

  test('negative counts, oversized defects and oversized rejects are rejected',
      () {
    expect(
      EggGradingValidation.validate(
          sampleSize: 100, rejectedCount: 0, counts: {'dirty': -1}),
      isNotEmpty,
    );
    expect(
      EggGradingValidation.validate(
          sampleSize: 100, rejectedCount: 0, counts: {'dirty': 101}),
      isNotEmpty,
    );
    expect(
      EggGradingValidation.validate(
          sampleSize: 100, rejectedCount: 101, counts: const {}),
      isNotEmpty,
    );
  });

  test('summary round-trips through JSON', () {
    final summary = EggGradingSummary.fromCounts(
      sampleSize: 50,
      rejectedCount: 5,
      counts: {'dirty': 2, 'ridged': 1},
    );
    final restored = EggGradingSummary.fromJson(
      summary.encodedJson,
      sampleSize: 50,
      rejectedCount: 5,
    );
    expect(restored.counts, {'dirty': 2, 'ridged': 1});
    expect(restored.topDefectCode, 'dirty');
  });
}
