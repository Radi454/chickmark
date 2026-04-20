class EggBreakoutAvg {
  final String breakoutType;
  final double traySize;
  final double infertileCount;
  final double earlyDeadCount;
  final double midDeadCount;
  final double lateDeadCount;
  final double internalPipCount;
  final double externalPipCount;
  final double crackedCount;
  final double contaminatedCount;
  final double malpositionCount;
  final double exposedBrainCount;
  final double crossedBeakCount;
  final double culledDeadCount;
  final double infertilePct;
  final double earlyDeadPct;
  final double midDeadPct;
  final double lateDeadPct;
  final double internalPipPct;
  final double externalPipPct;
  final double crackedPct;
  final double contamPct;
  final double malpositionPct;
  final double exposedBrainPct;
  final double crossedBeakPct;
  final double cullPct;

  EggBreakoutAvg({
    this.breakoutType = '',
    this.traySize = 0.0,
    this.infertileCount = 0.0,
    this.earlyDeadCount = 0.0,
    this.midDeadCount = 0.0,
    this.lateDeadCount = 0.0,
    this.internalPipCount = 0.0,
    this.externalPipCount = 0.0,
    this.crackedCount = 0.0,
    this.contaminatedCount = 0.0,
    this.malpositionCount = 0.0,
    this.exposedBrainCount = 0.0,
    this.crossedBeakCount = 0.0,
    this.culledDeadCount = 0.0,
    this.infertilePct = 0.0,
    this.earlyDeadPct = 0.0,
    this.midDeadPct = 0.0,
    this.lateDeadPct = 0.0,
    this.internalPipPct = 0.0,
    this.externalPipPct = 0.0,
    this.crackedPct = 0.0,
    this.contamPct = 0.0,
    this.malpositionPct = 0.0,
    this.exposedBrainPct = 0.0,
    this.crossedBeakPct = 0.0,
    this.cullPct = 0.0,
  });

  factory EggBreakoutAvg.fromMap(Map<String, dynamic> map, String type) {
    return EggBreakoutAvg(
      breakoutType: type,
      traySize: map['traySize']?.toDouble() ?? 0.0,
      infertileCount: map['infertileCount']?.toDouble() ?? 0.0,
      earlyDeadCount: map['earlyDeadCount']?.toDouble() ?? 0.0,
      midDeadCount: map['midDeadCount']?.toDouble() ?? 0.0,
      lateDeadCount: map['lateDeadCount']?.toDouble() ?? 0.0,
      internalPipCount: map['internalPipCount']?.toDouble() ?? 0.0,
      externalPipCount: map['externalPipCount']?.toDouble() ?? 0.0,
      crackedCount: map['crackedCount']?.toDouble() ?? 0.0,
      contaminatedCount: map['contaminatedCount']?.toDouble() ?? 0.0,
      malpositionCount: map['malpositionCount']?.toDouble() ?? 0.0,
      exposedBrainCount: map['exposedBrainCount']?.toDouble() ?? 0.0,
      crossedBeakCount: map['crossedBeakCount']?.toDouble() ?? 0.0,
      culledDeadCount: map['culledDeadCount']?.toDouble() ?? 0.0,
      infertilePct: map['infertilePct']?.toDouble() ?? 0.0,
      earlyDeadPct: map['earlyDeadPct']?.toDouble() ?? 0.0,
      midDeadPct: map['midDeadPct']?.toDouble() ?? 0.0,
      lateDeadPct: map['lateDeadPct']?.toDouble() ?? 0.0,
      internalPipPct: map['internalPipPct']?.toDouble() ?? 0.0,
      externalPipPct: map['externalPipPct']?.toDouble() ?? 0.0,
      crackedPct: map['crackedPct']?.toDouble() ?? 0.0,
      contamPct: map['contamPct']?.toDouble() ?? 0.0,
      malpositionPct: map['malpositionPct']?.toDouble() ?? 0.0,
      exposedBrainPct: map['exposedBrainPct']?.toDouble() ?? 0.0,
      crossedBeakPct: map['crossedBeakPct']?.toDouble() ?? 0.0,
      cullPct: map['cullPct']?.toDouble() ?? 0.0,
    );
  }
}

class EggBreakoutTrend {
  final String date;
  final String breakoutType;
  final Map<String, double> percentages;

  EggBreakoutTrend({
    required this.date,
    required this.breakoutType,
    required this.percentages,
  });

  factory EggBreakoutTrend.fromMap(Map<String, dynamic> map, String type) {
    return EggBreakoutTrend(
      date: map['date'] ?? '',
      breakoutType: type,
      percentages: {
        'infertile': map['infertilePct']?.toDouble() ?? 0.0,
        'early_dead': map['earlyDeadPct']?.toDouble() ?? 0.0,
        'mid_dead': map['midDeadPct']?.toDouble() ?? 0.0,
        'late_dead': map['lateDeadPct']?.toDouble() ?? 0.0,
        'internal_pip': map['internalPipPct']?.toDouble() ?? 0.0,
        'external_pip': map['externalPipPct']?.toDouble() ?? 0.0,
        'cracked': map['crackedPct']?.toDouble() ?? 0.0,
        'contam': map['contamPct']?.toDouble() ?? 0.0,
        'malposition': map['malpositionPct']?.toDouble() ?? 0.0,
        'exposed_brain': map['exposedBrainPct']?.toDouble() ?? 0.0,
        'crossed_beak': map['crossedBeakPct']?.toDouble() ?? 0.0,
        'cull': map['cullPct']?.toDouble() ?? 0.0,
      },
    );
  }
}
