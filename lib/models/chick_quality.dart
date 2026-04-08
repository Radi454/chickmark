import 'dart:convert';
import 'dart:math';

class ChickQuality {
  final String id;
  final String auditSessionId;
  final String customerId;
  final String flockId;

  // ── Top section ──────────────────────────────────────────────────────────
  int? eggStorageDays;

  // ── Section A: Environmental ──────────────────────────────────────────────
  double? temperature;
  double? humidity;
  double? co2Level;
  double? pm10;
  double? pm25;
  double? airVelocityDoor;
  double? airVelocityCenter;
  double? airVelocityCorner;
  double? noiseLevel;

  // ── Section B: Weight Uniformity ──────────────────────────────────────────
  int sampleSize; // default 100
  List<double> weights;

  double get avgWeight {
    if (weights.isEmpty) return 0.0;
    return weights.reduce((a, b) => a + b) / weights.length;
  }

  double get stdDev {
    if (weights.length < 2) return 0.0;
    final avg = avgWeight;
    final variance =
        weights.map((w) => pow(w - avg, 2)).reduce((a, b) => a + b) /
            (weights.length - 1);
    return sqrt(variance);
  }

  /// Coefficient of variation as a percentage.
  double get cvPercent {
    if (avgWeight == 0) return 0.0;
    return (stdDev / avgWeight) * 100;
  }

  /// Percentage of chicks whose weight falls within ±10 % of the average.
  double get uniformityPercent {
    if (weights.isEmpty) return 0.0;
    final avg = avgWeight;
    final lowerBound = avg * 0.90;
    final upperBound = avg * 1.10;
    final withinRange =
        weights.where((w) => w >= lowerBound && w <= upperBound).length;
    return (withinRange / weights.length) * 100;
  }

  // ── Section C: YFBM (Yolk-Free Body Mass) ────────────────────────────────
  /// Stored as JSON: List of {"total_weight": double, "yolk_weight": double}
  String yfbmDataJson;

  /// New per-hatch YFBM format:
  /// [{hatcherIdx: 0, samples: [{total_weight, yolk_weight}]}, ...]
  String? yfbmHatchDataJson;

  /// Per-hatch weights format: [[w1, w2, ...], [w1, w2, ...], ...]
  String? weightsHatchJson;

  List<Map<String, double>> get yfbmPairs {
    if (yfbmDataJson.isEmpty) return [];
    final decoded = jsonDecode(yfbmDataJson) as List;
    return decoded
        .map((e) => {
              'total_weight': (e['total_weight'] as num).toDouble(),
              'yolk_weight': (e['yolk_weight'] as num).toDouble(),
            })
        .toList();
  }

  /// Average yolk percentage: (yolk_weight / total_weight) * 100 per pair.
  double get avgYolkPercent {
    final pairs = yfbmPairs;
    if (pairs.isEmpty) return 0.0;
    final percentages = pairs.map((p) {
      final total = p['total_weight']!;
      final yolk = p['yolk_weight']!;
      return total > 0 ? (yolk / total) * 100 : 0.0;
    }).toList();
    return percentages.reduce((a, b) => a + b) / percentages.length;
  }

  double get cvYolkPercent {
    final pairs = yfbmPairs;
    if (pairs.length < 2) return 0.0;
    final percentages = pairs.map((p) {
      final total = p['total_weight']!;
      final yolk = p['yolk_weight']!;
      return total > 0 ? (yolk / total) * 100 : 0.0;
    }).toList();
    final avg = percentages.reduce((a, b) => a + b) / percentages.length;
    if (avg == 0) return 0.0;
    final variance =
        percentages.map((v) => pow(v - avg, 2)).reduce((a, b) => a + b) /
            (percentages.length - 1);
    return (sqrt(variance) / avg) * 100;
  }

  // ── Section D: Pasgar Score ───────────────────────────────────────────────
  /// New per-hatch PASGAR format:
  /// [{hatcherIdx: 0, sampleSize: 100, reflexes: 0, beak: 0, navel: 0, belly: 0, legs: 0, featheredCount: null}, ...]
  String? pasgarHatchDataJson;

  int pasgarSampleSize;
  int reflexesDefects;
  int beakDefects;
  int navelDefects;
  int bellyDefects;
  int legsDefects;

  int get totalDefects =>
      reflexesDefects + beakDefects + navelDefects + bellyDefects + legsDefects;

  /// Pasgar score out of 10.
  /// Formula: ((sampleSize * 10 - totalDefects) / (sampleSize * 10)) * 10
  double get pasgarScore {
    if (pasgarSampleSize == 0) return 0.0;
    return ((pasgarSampleSize * 10 - totalDefects) /
            (pasgarSampleSize * 10)) *
        10;
  }

  /// 'green' >= 9, 'amber' >= 7, 'red' < 7
  String get pasgarColor {
    final score = pasgarScore;
    if (score >= 9) return 'green';
    if (score >= 7) return 'amber';
    return 'red';
  }

  // ── Section E: Wing Feather ───────────────────────────────────────────────
  int? featheredCount;

  /// Wing feathering percentage relative to sampleSize.
  double? get wingPercent {
    if (featheredCount == null || sampleSize == 0) return null;
    return (featheredCount! / sampleSize) * 100;
  }

  /// 'green' >= 90 %, 'amber' >= 70 %, 'red' < 70 %
  String? get wingColor {
    final pct = wingPercent;
    if (pct == null) return null;
    if (pct >= 90) return 'green';
    if (pct >= 70) return 'amber';
    return 'red';
  }

  // ── Meta ──────────────────────────────────────────────────────────────────
  bool isCompleted;
  DateTime createdAt;

  ChickQuality({
    required this.id,
    required this.auditSessionId,
    required this.customerId,
    required this.flockId,
    // Top
    this.eggStorageDays,
    // Section A
    this.temperature,
    this.humidity,
    this.co2Level,
    this.pm10,
    this.pm25,
    this.airVelocityDoor,
    this.airVelocityCenter,
    this.airVelocityCorner,
    this.noiseLevel,
    // Section B
    this.sampleSize = 100,
    List<double>? weights,
    // Section C
    String? yfbmDataJson,
    this.yfbmHatchDataJson,
    this.weightsHatchJson,
    // Section D
    this.pasgarHatchDataJson,
    this.pasgarSampleSize = 0,
    this.reflexesDefects = 0,
    this.beakDefects = 0,
    this.navelDefects = 0,
    this.bellyDefects = 0,
    this.legsDefects = 0,
    // Section E
    this.featheredCount,
    // Meta
    this.isCompleted = false,
    required this.createdAt,
  })  : weights = weights ?? [],
        yfbmDataJson = yfbmDataJson ?? '[]';

  Map<String, dynamic> toMap() => {
        'id': id,
        'audit_session_id': auditSessionId,
        'customer_id': customerId,
        'flock_id': flockId,
        'egg_storage_days': eggStorageDays,
        // Section A
        'temperature': temperature,
        'humidity': humidity,
        'co2_level': co2Level,
        'pm10': pm10,
        'pm25': pm25,
        'air_velocity_door': airVelocityDoor,
        'air_velocity_center': airVelocityCenter,
        'air_velocity_corner': airVelocityCorner,
        'noise_level': noiseLevel,
        // Section B
        'sample_size': sampleSize,
        'weights': jsonEncode(weights),
        // Section C
        'yfbm_data': yfbmDataJson,
        'yfbm_hatch_data': yfbmHatchDataJson,
        'weights_hatch_json': weightsHatchJson,
        // Section D
        'pasgar_hatch_data': pasgarHatchDataJson,
        'pasgar_sample_size': pasgarSampleSize,
        'reflexes_defects': reflexesDefects,
        'beak_defects': beakDefects,
        'navel_defects': navelDefects,
        'belly_defects': bellyDefects,
        'legs_defects': legsDefects,
        // Section E
        'feathered_count': featheredCount,
        // Meta
        'is_completed': isCompleted ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  factory ChickQuality.fromMap(Map<String, dynamic> m) {
    List<double> weights = [];
    if (m['weights'] != null) {
      final decoded = jsonDecode(m['weights'] as String) as List;
      weights = decoded.map((e) => (e as num).toDouble()).toList();
    }
    return ChickQuality(
      id: m['id'] as String,
      auditSessionId: m['audit_session_id'] as String,
      customerId: m['customer_id'] as String,
      flockId: m['flock_id'] as String,
      eggStorageDays: (m['egg_storage_days'] as num?)?.toInt(),
      // Section A
      temperature: (m['temperature'] as num?)?.toDouble(),
      humidity: (m['humidity'] as num?)?.toDouble(),
      co2Level: (m['co2_level'] as num?)?.toDouble(),
      pm10: (m['pm10'] as num?)?.toDouble(),
      pm25: (m['pm25'] as num?)?.toDouble(),
      airVelocityDoor: (m['air_velocity_door'] as num?)?.toDouble(),
      airVelocityCenter: (m['air_velocity_center'] as num?)?.toDouble(),
      airVelocityCorner: (m['air_velocity_corner'] as num?)?.toDouble(),
      noiseLevel: (m['noise_level'] as num?)?.toDouble(),
      // Section B
      sampleSize: (m['sample_size'] as int?) ?? 100,
      weights: weights,
      // Section C
      yfbmDataJson: (m['yfbm_data'] as String?) ?? '[]',
      yfbmHatchDataJson: m['yfbm_hatch_data'] as String?,
      weightsHatchJson: m['weights_hatch_json'] as String?,
      // Section D
      pasgarHatchDataJson: m['pasgar_hatch_data'] as String?,
      pasgarSampleSize: (m['pasgar_sample_size'] as int?) ?? 0,
      reflexesDefects: (m['reflexes_defects'] as int?) ?? 0,
      beakDefects: (m['beak_defects'] as int?) ?? 0,
      navelDefects: (m['navel_defects'] as int?) ?? 0,
      bellyDefects: (m['belly_defects'] as int?) ?? 0,
      legsDefects: (m['legs_defects'] as int?) ?? 0,
      // Section E
      featheredCount: m['feathered_count'] as int?,
      // Meta
      isCompleted: (m['is_completed'] == 1 || m['is_completed'] == true),
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }
}
