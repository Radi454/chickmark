import 'package:flutter_test/flutter_test.dart';

class HatchBudget {
  final int totalEggsSet;
  final int healthyHatched;
  final int culled;
  final int deadAtHatch;
  final int pipped;
  final int infertileClear;
  final int earlyDead;
  final int midDead;
  final int midLateDead;
  final int lateDead;
  final int contaminatedExploders;

  const HatchBudget({
    required this.totalEggsSet,
    this.healthyHatched = 0,
    this.culled = 0,
    this.deadAtHatch = 0,
    this.pipped = 0,
    this.infertileClear = 0,
    this.earlyDead = 0,
    this.midDead = 0,
    this.midLateDead = 0,
    this.lateDead = 0,
    this.contaminatedExploders = 0,
  });

  int get sum => healthyHatched + culled + deadAtHatch + pipped +
      infertileClear + earlyDead + midDead + midLateDead + lateDead +
      contaminatedExploders;

  bool get isReconciled => sum == totalEggsSet;

  int get difference => totalEggsSet - sum;

  double percentageOf(int category) {
    if (totalEggsSet <= 0) return 0.0;
    return (category / totalEggsSet) * 100;
  }

  double get healthyHatchedPct => percentageOf(healthyHatched);
  double get culledPct => percentageOf(culled);
  double get deadAtHatchPct => percentageOf(deadAtHatch);
  double get pippedPct => percentageOf(pipped);
  double get infertileClearPct => percentageOf(infertileClear);
  double get earlyDeadPct => percentageOf(earlyDead);
  double get midDeadPct => percentageOf(midDead);
  double get midLateDeadPct => percentageOf(midLateDead);
  double get lateDeadPct => percentageOf(lateDead);
  double get contaminatedExplodersPct => percentageOf(contaminatedExploders);
}

String? validateHatchBudget(HatchBudget budget) {
  if (budget.healthyHatched < 0) return 'Healthy Hatched cannot be negative';
  if (budget.culled < 0) return 'Culled cannot be negative';
  if (budget.deadAtHatch < 0) return 'Dead At Hatch cannot be negative';
  if (budget.pipped < 0) return 'Pipped cannot be negative';
  if (budget.infertileClear < 0) return 'Infertile/Clear cannot be negative';
  if (budget.earlyDead < 0) return 'Early Dead cannot be negative';
  if (budget.midDead < 0) return 'Mid Dead cannot be negative';
  if (budget.midLateDead < 0) return 'Mid/Late Dead cannot be negative';
  if (budget.lateDead < 0) return 'Late Dead cannot be negative';
  if (budget.contaminatedExploders < 0) {
    return 'Contaminated/Exploders cannot be negative';
  }
  if (budget.totalEggsSet <= 0) return 'Total Eggs Set must be positive';

  final diff = budget.difference;
  if (diff > 0) {
    return 'Unallocated eggs: $diff eggs still need a category assignment';
  }
  if (diff < 0) {
    return 'Over budget: ${-diff} eggs exceed the total ${budget.totalEggsSet}. Reduce category counts.';
  }
  return null;
}

void main() {
  group('HatchBudget 100%-budget validation', () {
    test('exact reconciliation passes validation', () {
      final budget = HatchBudget(
        totalEggsSet: 20000,
        healthyHatched: 16800,
        culled: 200,
        deadAtHatch: 200,
        pipped: 400,
        infertileClear: 800,
        earlyDead: 400,
        midDead: 300,
        midLateDead: 200,
        lateDead: 400,
        contaminatedExploders: 300,
      );
      expect(validateHatchBudget(budget), isNull);
    });

    test('under-budget fails with missing count', () {
      final budget = HatchBudget(
        totalEggsSet: 20000,
        healthyHatched: 10000,
        culled: 100,
        deadAtHatch: 100,
      );
      final error = validateHatchBudget(budget);
      expect(error, isNotNull);
      expect(error, contains('Unallocated eggs'));
      expect(error, contains('9800'));
    });

    test('over-budget fails with excess count', () {
      final budget = HatchBudget(
        totalEggsSet: 1000,
        healthyHatched: 800,
        culled: 300,
      );
      final error = validateHatchBudget(budget);
      expect(error, isNotNull);
      expect(error, contains('Over budget'));
    });

    test('negative count fails validation', () {
      final budget = HatchBudget(
        totalEggsSet: 20000,
        healthyHatched: -1,
        culled: 200,
        deadAtHatch: 200,
        pipped: 400,
        infertileClear: 800,
        earlyDead: 400,
        midDead: 300,
        midLateDead: 200,
        lateDead: 400,
        contaminatedExploders: 200,
      );
      final error = validateHatchBudget(budget);
      expect(error, isNotNull);
      expect(error, contains('negative'));
    });

    test('zero total eggs set fails validation', () {
      final budget = HatchBudget(
        totalEggsSet: 0,
        healthyHatched: 100,
        culled: 50,
      );
      final error = validateHatchBudget(budget);
      expect(error, isNotNull);
      expect(error, contains('must be positive'));
    });

    test('all zeroes validates when totalEggsSet is zero (rejected by positive check)', () {
      final budget = HatchBudget(totalEggsSet: 5000);
      final error = validateHatchBudget(budget);
      expect(error, isNotNull);
      expect(error, contains('Unallocated eggs'));
      expect(error, contains('5000'));
    });

    test('reconciled at exactly zero totals for all categories', () {
      final budget = HatchBudget(
        totalEggsSet: 20000,
        healthyHatched: 20000,
      );
      expect(validateHatchBudget(budget), isNull);
    });
  });

  group('HatchBudget percentage calculations', () {
    test('percentages sum to 100% when reconciled', () {
      final budget = HatchBudget(
        totalEggsSet: 20000,
        healthyHatched: 16800,
        culled: 200,
        deadAtHatch: 200,
        pipped: 400,
        infertileClear: 800,
        earlyDead: 400,
        midDead: 300,
        midLateDead: 200,
        lateDead: 400,
        contaminatedExploders: 300,
      );

      final totalPct = budget.healthyHatchedPct +
          budget.culledPct +
          budget.deadAtHatchPct +
          budget.pippedPct +
          budget.infertileClearPct +
          budget.earlyDeadPct +
          budget.midDeadPct +
          budget.midLateDeadPct +
          budget.lateDeadPct +
          budget.contaminatedExplodersPct;

      expect(totalPct, closeTo(100.0, 0.01));
    });

    test('healthy hatched percentage is correct', () {
      final budget = HatchBudget(
        totalEggsSet: 10000,
        healthyHatched: 8500,
      );
      expect(budget.healthyHatchedPct, closeTo(85.0, 0.01));
    });

    test('culled percentage is correct', () {
      final budget = HatchBudget(
        totalEggsSet: 10000,
        culled: 100,
      );
      expect(budget.culledPct, closeTo(1.0, 0.01));
    });

    test('dead percentage is correct', () {
      final budget = HatchBudget(
        totalEggsSet: 10000,
        deadAtHatch: 50,
      );
      expect(budget.deadAtHatchPct, closeTo(0.5, 0.01));
    });

    test('percentages are zero when totalEggsSet is zero', () {
      final budget = HatchBudget(totalEggsSet: 0);
      expect(budget.healthyHatchedPct, 0.0);
      expect(budget.culledPct, 0.0);
      expect(budget.lateDeadPct, 0.0);
    });

    test('sum equals totalEggsSet when fully allocated', () {
      final budget = HatchBudget(
        totalEggsSet: 50000,
        healthyHatched: 42000,
        culled: 500,
        deadAtHatch: 300,
        pipped: 1000,
        infertileClear: 2000,
        earlyDead: 1200,
        midDead: 800,
        midLateDead: 600,
        lateDead: 1000,
        contaminatedExploders: 600,
      );
      expect(budget.sum, 50000);
      expect(budget.isReconciled, isTrue);
    });

    test('difference returns positive for under-budget', () {
      final budget = HatchBudget(
        totalEggsSet: 10000,
        healthyHatched: 8000,
      );
      expect(budget.difference, 2000);
    });

    test('difference returns negative for over-budget', () {
      final budget = HatchBudget(
        totalEggsSet: 10000,
        healthyHatched: 8000,
        culled: 3000,
      );
      expect(budget.difference, -1000);
    });
  });
}
