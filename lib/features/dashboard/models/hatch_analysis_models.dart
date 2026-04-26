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

  double get healthyHatchedPct =>
      totalEggsSet > 0 ? (healthyHatched / totalEggsSet) * 100 : 0.0;
  double get culledPct =>
      totalEggsSet > 0 ? (culled / totalEggsSet) * 100 : 0.0;
  double get deadAtHatchPct =>
      totalEggsSet > 0 ? (deadAtHatch / totalEggsSet) * 100 : 0.0;
  double get pippedPct =>
      totalEggsSet > 0 ? (pipped / totalEggsSet) * 100 : 0.0;
  double get infertileClearPct =>
      totalEggsSet > 0 ? (infertileClear / totalEggsSet) * 100 : 0.0;
  double get earlyDeadPct =>
      totalEggsSet > 0 ? (earlyDead / totalEggsSet) * 100 : 0.0;
  double get midDeadPct =>
      totalEggsSet > 0 ? (midDead / totalEggsSet) * 100 : 0.0;
  double get midLateDeadPct =>
      totalEggsSet > 0 ? (midLateDead / totalEggsSet) * 100 : 0.0;
  double get lateDeadPct =>
      totalEggsSet > 0 ? (lateDead / totalEggsSet) * 100 : 0.0;
  double get contaminatedExplodersPct =>
      totalEggsSet > 0 ? (contaminatedExploders / totalEggsSet) * 100 : 0.0;

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
