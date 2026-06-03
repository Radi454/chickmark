import '../../../core/utils/calculation_utils.dart';

class HatchAnalysisAvg {
  final double hatchabilityPct;
  final double fertilityPct;
  final double hofPct;
  final double culledPct;
  final double deadPct;

  HatchAnalysisAvg({
    this.hatchabilityPct = 0.0,
    this.fertilityPct = 0.0,
    this.hofPct = 0.0,
    this.culledPct = 0.0,
    this.deadPct = 0.0,
  });

  factory HatchAnalysisAvg.fromMap(Map<String, dynamic> map) {
    return HatchAnalysisAvg(
      hatchabilityPct: map['hatchabilityPct']?.toDouble() ?? 0.0,
      fertilityPct: map['fertilityPct']?.toDouble() ?? 0.0,
      hofPct: map['hofPct']?.toDouble() ?? 0.0,
      culledPct: map['culledPct']?.toDouble() ?? 0.0,
      deadPct: map['deadPct']?.toDouble() ?? 0.0,
    );
  }
}

class HatchAnalysisTrend {
  final String date;
  final double hatchabilityPct;
  final double fertilityPct;
  final double hofPct;
  final double culledPct;
  final double deadPct;

  HatchAnalysisTrend({
    required this.date,
    this.hatchabilityPct = 0.0,
    this.fertilityPct = 0.0,
    this.hofPct = 0.0,
    this.culledPct = 0.0,
    this.deadPct = 0.0,
  });

  factory HatchAnalysisTrend.fromMap(Map<String, dynamic> map) {
    return HatchAnalysisTrend(
      date: map['date'] ?? '',
      hatchabilityPct: map['hatchabilityPct']?.toDouble() ?? 0.0,
      fertilityPct: map['fertilityPct']?.toDouble() ?? 0.0,
      hofPct: map['hofPct']?.toDouble() ?? 0.0,
      culledPct: map['culledPct']?.toDouble() ?? 0.0,
      deadPct: map['deadPct']?.toDouble() ?? 0.0,
    );
  }
}

class HatchBudgetSummary {
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

  HatchBudgetSummary({
    this.totalEggsSet = 0,
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

  double get healthyHatchedPct => _pct(healthyHatched, totalEggsSet);
  double get culledPct => _pct(culled, totalEggsSet);
  double get deadAtHatchPct => _pct(deadAtHatch, totalEggsSet);
  double get pippedPct => _pct(pipped, totalEggsSet);
  double get infertileClearPct => _pct(infertileClear, totalEggsSet);
  double get earlyDeadPct => _pct(earlyDead, totalEggsSet);
  double get midDeadPct => _pct(midDead, totalEggsSet);
  double get midLateDeadPct => _pct(midLateDead, totalEggsSet);
  double get lateDeadPct => _pct(lateDead, totalEggsSet);
  double get contaminatedExplodersPct =>
      _pct(contaminatedExploders, totalEggsSet);

  factory HatchBudgetSummary.fromMap(Map<String, dynamic> map) {
    return HatchBudgetSummary(
      totalEggsSet: map['haTotalEggsSet'] ?? map['totalEggsSet'] ?? 0,
      healthyHatched: map['haHatched'] ?? map['healthyHatched'] ?? 0,
      culled: map['haCulled'] ?? map['culled'] ?? 0,
      deadAtHatch: map['haDead'] ?? map['deadAtHatch'] ?? 0,
      pipped: map['haPipped'] ?? map['pipped'] ?? 0,
      infertileClear: map['haInfertileClear'] ?? map['infertileClear'] ?? 0,
      earlyDead: map['haEarlyDead'] ?? map['earlyDead'] ?? 0,
      midDead: map['haMidDead'] ?? map['midDead'] ?? 0,
      midLateDead: map['haMidLateDead'] ?? map['midLateDead'] ?? 0,
      lateDead: map['haLateDead'] ?? map['lateDead'] ?? 0,
      contaminatedExploders:
          map['haContaminatedExploders'] ?? map['contaminatedExploders'] ?? 0,
    );
  }

  Map<String, double> get percentages => {
    'healthyHatched': healthyHatchedPct,
    'culled': culledPct,
    'deadAtHatch': deadAtHatchPct,
    'pipped': pippedPct,
    'infertileClear': infertileClearPct,
    'earlyDead': earlyDeadPct,
    'midDead': midDeadPct,
    'midLateDead': midLateDeadPct,
    'lateDead': lateDeadPct,
    'contaminatedExploders': contaminatedExplodersPct,
  };
}

double _pct(num count, num total) {
  return CalculationUtils.percentOf(count, total) ?? 0.0;
}

class HatchBenchmarkStatus {
  final String category;
  final double actualPct;
  final double bmkPct;
  final String status;

  HatchBenchmarkStatus({
    required this.category,
    required this.actualPct,
    required this.bmkPct,
    required this.status,
  });

  static String computeStatus(double actualPct, double bmkPct) {
    if (actualPct <= bmkPct) return 'OK';
    if (actualPct <= bmkPct + 3.0) return 'Medium';
    return 'High';
  }
}
