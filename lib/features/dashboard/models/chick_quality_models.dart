import '../../audits/models/culled_chicks_analysis.dart';

class ChickWeightTrend {
  final String date;
  final double avgWeightG;
  final double uniformityPct;
  final double cvPct;

  ChickWeightTrend({
    required this.date,
    this.avgWeightG = 0.0,
    this.uniformityPct = 0.0,
    this.cvPct = 0.0,
  });

  factory ChickWeightTrend.fromMap(Map<String, dynamic> map) {
    return ChickWeightTrend(
      date: map['date'] ?? '',
      avgWeightG: map['avgWeightG']?.toDouble() ?? 0.0,
      uniformityPct: map['uniformityPct']?.toDouble() ?? 0.0,
      cvPct: map['cvPct']?.toDouble() ?? 0.0,
    );
  }
}

class CulledChicksAnalysisAvg {
  final int totalEggSet;
  final double affectedPct;
  final String? topCategory;
  final CulledChickDefect? topDefect;
  final Map<String, double> categoryPcts;
  final List<CulledChicksAnalysisEntry> entries;

  CulledChicksAnalysisAvg({
    required this.totalEggSet,
    required this.affectedPct,
    required this.topCategory,
    required this.topDefect,
    required this.categoryPcts,
    required this.entries,
  });

  factory CulledChicksAnalysisAvg.fromSummary(
    CulledChicksAnalysisSummary summary,
  ) {
    return CulledChicksAnalysisAvg(
      totalEggSet: summary.totalEggSet,
      affectedPct: summary.affectedPct,
      topCategory: summary.topCategory,
      topDefect: summary.topDefect,
      categoryPcts: summary.categoryPcts,
      entries: summary.entries,
    );
  }

  String? get topSubtype => topDefect?.subtype;

  bool get needsReview => affectedPct > 0;

  bool get hasDominantCategory {
    final category = topCategory;
    if (category == null || affectedPct <= 0) return false;
    return ((categoryPcts[category] ?? 0) / affectedPct) >= 0.5;
  }
}

class PasgarAvg {
  final double score;
  final double reflexesPct;
  final double beakPct;
  final double navelPct;
  final double bellyPct;
  final double legPct;
  final double featherDevPct;

  PasgarAvg({
    this.score = 0.0,
    this.reflexesPct = 0.0,
    this.beakPct = 0.0,
    this.navelPct = 0.0,
    this.bellyPct = 0.0,
    this.legPct = 0.0,
    this.featherDevPct = 0.0,
  });

  factory PasgarAvg.fromMap(Map<String, dynamic> map) {
    return PasgarAvg(
      score: map['score']?.toDouble() ?? 0.0,
      reflexesPct: map['reflexesPct']?.toDouble() ?? 0.0,
      beakPct: map['beakPct']?.toDouble() ?? 0.0,
      navelPct: map['navelPct']?.toDouble() ?? 0.0,
      bellyPct: map['bellyPct']?.toDouble() ?? 0.0,
      legPct: map['legPct']?.toDouble() ?? 0.0,
      featherDevPct: map['featherDevPct']?.toDouble() ?? 0.0,
    );
  }
}

class CvtAvg {
  final double avgTempF;
  final double cvPct;

  CvtAvg({this.avgTempF = 0.0, this.cvPct = 0.0});

  factory CvtAvg.fromMap(Map<String, dynamic> map) {
    return CvtAvg(
      avgTempF: map['avgTempF']?.toDouble() ?? 0.0,
      cvPct: map['cvPct']?.toDouble() ?? 0.0,
    );
  }
}

class YfbmTrend {
  final String date;
  final double avgPct;
  final double cvPct;

  YfbmTrend({required this.date, this.avgPct = 0.0, this.cvPct = 0.0});

  factory YfbmTrend.fromMap(Map<String, dynamic> map) {
    return YfbmTrend(
      date: map['date'] ?? '',
      avgPct: map['avgPct']?.toDouble() ?? 0.0,
      cvPct: map['cvPct']?.toDouble() ?? 0.0,
    );
  }
}

class ChaEnvironmentalTrend {
  final String date;
  final double co2;
  final double pm10;
  final double pm25;
  final double airVelocity;
  final double noiseLevel;

  ChaEnvironmentalTrend({
    required this.date,
    this.co2 = 0.0,
    this.pm10 = 0.0,
    this.pm25 = 0.0,
    this.airVelocity = 0.0,
    this.noiseLevel = 0.0,
  });

  factory ChaEnvironmentalTrend.fromMap(Map<String, dynamic> map) {
    return ChaEnvironmentalTrend(
      date: map['date'] ?? '',
      co2: map['co2']?.toDouble() ?? 0.0,
      pm10: map['pm10']?.toDouble() ?? 0.0,
      pm25: map['pm25']?.toDouble() ?? 0.0,
      airVelocity: map['airVelocity']?.toDouble() ?? 0.0,
      noiseLevel: map['noiseLevel']?.toDouble() ?? 0.0,
    );
  }
}
