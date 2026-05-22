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
  final int eggSampleSize;
  final double eggBmkWeight;
  final double shellTempC;
  final double uvAffectedPct;
  final int uvTrayEggCount;
  final double uvCuticleDamagePct;
  final double uvWashedPct;
  final double uvDirtyPct;
  final double co2;
  final double estAvgF;
  final double estCvPct;
  final int? storageDays;
  final int? turningTimes;
  final String? traySpacing;
  final String? coolerProximity;
  final bool? condensationPresent;
  final int upsideDownCount;
  final double upsideDownPct;

  EggStorageTrend({
    required this.date,
    this.avgWeightG = 0.0,
    this.uniformityPct = 0.0,
    this.cvPct = 0.0,
    this.eggSampleSize = 0,
    this.eggBmkWeight = 0.0,
    this.shellTempC = 0.0,
    this.uvAffectedPct = 0.0,
    this.uvTrayEggCount = 0,
    this.uvCuticleDamagePct = 0.0,
    this.uvWashedPct = 0.0,
    this.uvDirtyPct = 0.0,
    this.co2 = 0.0,
    this.estAvgF = 0.0,
    this.estCvPct = 0.0,
    this.storageDays,
    this.turningTimes,
    this.traySpacing,
    this.coolerProximity,
    this.condensationPresent,
    this.upsideDownCount = 0,
    this.upsideDownPct = 0.0,
  });

  factory EggStorageTrend.fromMap(Map<String, dynamic> map) {
    return EggStorageTrend(
      date: map['date'] ?? '',
      avgWeightG: _asDouble(map['avgWeightG']),
      uniformityPct: _asDouble(map['uniformityPct']),
      cvPct: _asDouble(map['cvPct']),
      eggSampleSize: _asInt(map['eggSampleSize']) ?? 0,
      eggBmkWeight: _asDouble(map['eggBmkWeight']),
      shellTempC: _asDouble(map['shellTempC']),
      uvAffectedPct: _asDouble(map['uvAffectedPct']),
      uvTrayEggCount: _asInt(map['uvTrayEggCount']) ?? 0,
      uvCuticleDamagePct: _asDouble(map['uvCuticleDamagePct']),
      uvWashedPct: _asDouble(map['uvWashedPct']),
      uvDirtyPct: _asDouble(map['uvDirtyPct']),
      co2: _asDouble(map['co2']),
      estAvgF: _asDouble(map['estAvgF']),
      estCvPct: _asDouble(map['estCvPct']),
      storageDays: _asInt(map['storageDays']),
      turningTimes: _asInt(map['turningTimes']),
      traySpacing: _asString(map['traySpacing']),
      coolerProximity: _asString(map['coolerProximity']),
      condensationPresent: _asBool(map['condensationPresent']),
      upsideDownCount: _asInt(map['upsideDownCount']) ?? 0,
      upsideDownPct: _asDouble(map['upsideDownPct']),
    );
  }

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool? _asBool(Object? value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == 'yes' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == 'no' || normalized == '0') {
      return false;
    }
    return null;
  }

  static String? _asString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
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
