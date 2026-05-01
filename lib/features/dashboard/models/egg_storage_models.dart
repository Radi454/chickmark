import 'dart:convert';

import '../../audits/models/est_grid_data.dart';

class EggStorageEstEvidencePoint {
  final String key;
  final String positionLabel;
  final String levelLabel;
  final double? readingC;
  final String? photoPath;

  const EggStorageEstEvidencePoint({
    required this.key,
    required this.positionLabel,
    required this.levelLabel,
    this.readingC,
    this.photoPath,
  });

  bool get hasPhoto => photoPath != null && photoPath!.trim().isNotEmpty;
  bool get isComplete => readingC != null && hasPhoto;
}

class EggStorageEstEvidence {
  final List<EggStorageEstEvidencePoint> points;

  const EggStorageEstEvidence({required this.points});

  factory EggStorageEstEvidence.fromJsonStrings({
    String? readingsJson,
    String? photosJson,
  }) {
    final readings = EstGridData.normalizeReadings(
      _decodeMap(readingsJson) ?? const {},
    );
    final photos = _normalizePhotos(_decodeMap(photosJson) ?? const {});

    return EggStorageEstEvidence(
      points: [
        for (final key in EstGridData.scanKeys)
          EggStorageEstEvidencePoint(
            key: key,
            positionLabel: EstGridData.label(key.split('_').first),
            levelLabel: EstGridData.label(key.split('_').last),
            readingC: readings[key],
            photoPath: photos[key],
          ),
      ],
    );
  }

  bool get isComplete => points.every((point) => point.isComplete);

  static Map<dynamic, dynamic>? _decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded;
    } catch (_) {
      return null;
    }
    return null;
  }

  static Map<String, String> _normalizePhotos(Map<dynamic, dynamic> photos) {
    final normalized = <String, String>{};
    final canonicalKeys = EstGridData.scanKeys.toSet();
    for (final entry in photos.entries) {
      final rawKey = entry.key?.toString();
      final rawPath = entry.value?.toString().trim();
      if (rawKey == null || rawPath == null || rawPath.isEmpty) continue;
      final key = rawKey.startsWith('door_')
          ? rawKey.replaceFirst('door_', 'front_')
          : rawKey;
      if (canonicalKeys.contains(key)) {
        normalized[key] = rawPath;
      }
    }
    return normalized;
  }
}

class EggStorageTrend {
  final String date;
  final double avgWeightG;
  final double uniformityPct;
  final double cvPct;
  final double shellTempC;
  final double uvAffectedPct;
  final double co2;
  final double estAvgF;
  final double estCvPct;

  EggStorageTrend({
    required this.date,
    this.avgWeightG = 0.0,
    this.uniformityPct = 0.0,
    this.cvPct = 0.0,
    this.shellTempC = 0.0,
    this.uvAffectedPct = 0.0,
    this.co2 = 0.0,
    this.estAvgF = 0.0,
    this.estCvPct = 0.0,
  });

  factory EggStorageTrend.fromMap(Map<String, dynamic> map) {
    return EggStorageTrend(
      date: map['date'] ?? '',
      avgWeightG: map['avgWeightG']?.toDouble() ?? 0.0,
      uniformityPct: map['uniformityPct']?.toDouble() ?? 0.0,
      cvPct: map['cvPct']?.toDouble() ?? 0.0,
      shellTempC: map['shellTempC']?.toDouble() ?? 0.0,
      uvAffectedPct: map['uvAffectedPct']?.toDouble() ?? 0.0,
      co2: map['co2']?.toDouble() ?? 0.0,
      estAvgF: map['estAvgF']?.toDouble() ?? 0.0,
      estCvPct: map['estCvPct']?.toDouble() ?? 0.0,
    );
  }
}

class SetterComparison {
  final String setterId;
  final double hatchabilityPct;
  final double fertilityPct;
  final double hofPct;
  final double culledPct;
  final double deadPct;
  final double infertilePct;
  final double early24hPct;
  final double early48hPct;
  final double bloodRingPct;
  final double estAvgF;
  final double estCvPct;
  final double turningAngle;
  final Map<String, double> co2Trend;

  SetterComparison({
    required this.setterId,
    this.hatchabilityPct = 0.0,
    this.fertilityPct = 0.0,
    this.hofPct = 0.0,
    this.culledPct = 0.0,
    this.deadPct = 0.0,
    this.infertilePct = 0.0,
    this.early24hPct = 0.0,
    this.early48hPct = 0.0,
    this.bloodRingPct = 0.0,
    this.estAvgF = 0.0,
    this.estCvPct = 0.0,
    this.turningAngle = 0.0,
    Map<String, double>? co2Trend,
  }) : co2Trend = co2Trend ?? {};

  factory SetterComparison.fromMap(Map<String, dynamic> map) {
    return SetterComparison(
      setterId: map['setterId'] ?? '',
      hatchabilityPct: map['hatchabilityPct']?.toDouble() ?? 0.0,
      fertilityPct: map['fertilityPct']?.toDouble() ?? 0.0,
      hofPct: map['hofPct']?.toDouble() ?? 0.0,
      culledPct: map['culledPct']?.toDouble() ?? 0.0,
      deadPct: map['deadPct']?.toDouble() ?? 0.0,
      infertilePct: map['infertilePct']?.toDouble() ?? 0.0,
      early24hPct: map['early24hPct']?.toDouble() ?? 0.0,
      early48hPct: map['early48hPct']?.toDouble() ?? 0.0,
      bloodRingPct: map['bloodRingPct']?.toDouble() ?? 0.0,
      estAvgF: map['estAvgF']?.toDouble() ?? 0.0,
      estCvPct: map['estCvPct']?.toDouble() ?? 0.0,
      turningAngle: map['turningAngle']?.toDouble() ?? 0.0,
    );
  }
}

class HatcherComparison {
  final String hatcherId;
  final double hatchabilityPct;
  final double fertilityPct;
  final double hofPct;
  final double culledPct;
  final double deadPct;
  final double lateDeadPct;
  final double externalPipPct;
  final double exposedBrainPct;
  final double crossedBeakPct;
  final double contamPct;
  final double crackedPct;
  final double cvtAvgF;
  final double cvtCvPct;
  final String? meconium;
  final int? transferDay;
  final Map<String, double> co2Trend;
  final Map<String, double> pantingTrend;

  HatcherComparison({
    required this.hatcherId,
    this.hatchabilityPct = 0.0,
    this.fertilityPct = 0.0,
    this.hofPct = 0.0,
    this.culledPct = 0.0,
    this.deadPct = 0.0,
    this.lateDeadPct = 0.0,
    this.externalPipPct = 0.0,
    this.exposedBrainPct = 0.0,
    this.crossedBeakPct = 0.0,
    this.contamPct = 0.0,
    this.crackedPct = 0.0,
    this.cvtAvgF = 0.0,
    this.cvtCvPct = 0.0,
    this.meconium,
    this.transferDay,
    Map<String, double>? co2Trend,
    Map<String, double>? pantingTrend,
  }) : co2Trend = co2Trend ?? {},
       pantingTrend = pantingTrend ?? {};

  factory HatcherComparison.fromMap(Map<String, dynamic> map) {
    return HatcherComparison(
      hatcherId: map['hatcherId'] ?? '',
      hatchabilityPct: map['hatchabilityPct']?.toDouble() ?? 0.0,
      fertilityPct: map['fertilityPct']?.toDouble() ?? 0.0,
      hofPct: map['hofPct']?.toDouble() ?? 0.0,
      culledPct: map['culledPct']?.toDouble() ?? 0.0,
      deadPct: map['deadPct']?.toDouble() ?? 0.0,
      lateDeadPct: map['lateDeadPct']?.toDouble() ?? 0.0,
      externalPipPct: map['externalPipPct']?.toDouble() ?? 0.0,
      exposedBrainPct: map['exposedBrainPct']?.toDouble() ?? 0.0,
      crossedBeakPct: map['crossedBeakPct']?.toDouble() ?? 0.0,
      contamPct: map['contamPct']?.toDouble() ?? 0.0,
      crackedPct: map['crackedPct']?.toDouble() ?? 0.0,
      cvtAvgF: map['cvtAvgF']?.toDouble() ?? 0.0,
      cvtCvPct: map['cvtCvPct']?.toDouble() ?? 0.0,
      meconium: map['meconium'] as String?,
      transferDay: map['transferDay'] as int?,
    );
  }
}

class BmkReference {
  final double hatchabilityPct;
  final double fertilityPct;
  final double hofPct;
  final double eggWeightG;
  final double chickWeightG;
  final double infertilePct;
  final double early24hPct;
  final double early48hPct;
  final double bloodRingPct;
  final double blackEyePct;
  final double midDeadPct;
  final double lateDeadPct;
  final double pippedExternalPct;
  final double explodedPct;
  final double mushyPct;
  final double contamPct;
  final double cullPct;
  final double earlyDeadPct;
  final double midBlackEyePct;
  final double internalPipPct;
  final double externalPipPct;
  final double crackedPct;
  final double turnedPct;
  final double exposedBrainPct;
  final double crossedBeakPct;

  BmkReference({
    this.hatchabilityPct = 0.0,
    this.fertilityPct = 0.0,
    this.hofPct = 0.0,
    this.eggWeightG = 0.0,
    this.chickWeightG = 0.0,
    this.infertilePct = 0.0,
    this.early24hPct = 0.0,
    this.early48hPct = 0.0,
    this.bloodRingPct = 0.0,
    this.blackEyePct = 0.0,
    this.midDeadPct = 0.0,
    this.lateDeadPct = 0.0,
    this.pippedExternalPct = 0.0,
    this.explodedPct = 0.0,
    this.mushyPct = 0.0,
    this.contamPct = 0.0,
    this.cullPct = 0.0,
    this.earlyDeadPct = 0.0,
    this.midBlackEyePct = 0.0,
    this.internalPipPct = 0.0,
    this.externalPipPct = 0.0,
    this.crackedPct = 0.0,
    this.turnedPct = 0.0,
    this.exposedBrainPct = 0.0,
    this.crossedBeakPct = 0.0,
  });

  factory BmkReference.fromMaps(
    Map<String, dynamic>? breed,
    Map<String, dynamic>? breakout,
  ) {
    return BmkReference(
      hatchabilityPct: breed?['hatchabilityPct']?.toDouble() ?? 0.0,
      fertilityPct: breed?['fertilityPct']?.toDouble() ?? 0.0,
      hofPct: breed?['hofPct']?.toDouble() ?? 0.0,
      eggWeightG: breed?['eggWeightG']?.toDouble() ?? 0.0,
      chickWeightG: breed?['chickWeightG']?.toDouble() ?? 0.0,
      infertilePct: breakout?['infertilePct']?.toDouble() ?? 0.0,
      early24hPct: breakout?['early24hPct']?.toDouble() ?? 0.0,
      early48hPct: breakout?['early48hPct']?.toDouble() ?? 0.0,
      bloodRingPct: breakout?['bloodRingPct']?.toDouble() ?? 0.0,
      blackEyePct: breakout?['blackEyePct']?.toDouble() ?? 0.0,
      midDeadPct: breakout?['midDeadPct']?.toDouble() ?? 0.0,
      lateDeadPct: breakout?['lateDeadPct']?.toDouble() ?? 0.0,
      pippedExternalPct: breakout?['pippedExternalPct']?.toDouble() ?? 0.0,
      explodedPct: breakout?['explodedPct']?.toDouble() ?? 0.0,
      mushyPct: breakout?['mushyPct']?.toDouble() ?? 0.0,
      contamPct: breakout?['contamPct']?.toDouble() ?? 0.0,
      cullPct: breakout?['cullPct']?.toDouble() ?? 0.0,
      earlyDeadPct:
          breakout?['earlyDeadPct']?.toDouble() ??
          breakout?['midDeadPct']?.toDouble() ??
          0.0,
      midBlackEyePct:
          breakout?['midBlackEyePct']?.toDouble() ??
          breakout?['blackEyePct']?.toDouble() ??
          0.0,
      internalPipPct:
          breakout?['internalPipPct']?.toDouble() ??
          breakout?['pippedInternalPct']?.toDouble() ??
          0.0,
      externalPipPct:
          breakout?['externalPipPct']?.toDouble() ??
          breakout?['pippedExternalPct']?.toDouble() ??
          0.0,
      crackedPct: breakout?['crackedPct']?.toDouble() ?? 0.0,
      turnedPct: breakout?['turnedPct']?.toDouble() ?? 0.0,
      exposedBrainPct: breakout?['exposedBrainPct']?.toDouble() ?? 0.0,
      crossedBeakPct: breakout?['crossedBeakPct']?.toDouble() ?? 0.0,
    );
  }
}
