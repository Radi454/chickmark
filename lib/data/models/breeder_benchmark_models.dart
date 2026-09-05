/// Official breeder benchmark foundation models (breeder-flock-performance
/// ticket 03). These mirror `breeder_metric_definitions`,
/// `breeder_benchmark_profiles`, and `breeder_benchmark_values` — versioned
/// reference data loaded from checked-in asset files. Nothing in the app
/// writes or edits these; see
/// lib/data/database/seeds/breeder_benchmark_seeds.dart for the importer and
/// lib/data/repositories/breeder_benchmark_repository.dart for the read-only
/// repository.
library;

class BreederMetricDefinition {
  final String id;
  final String code;
  final String label;
  final String unit;
  final String sexScope; // 'female' | 'male' | 'both'
  final String periodType; // 'daily' | 'weekly' | 'cumulative'
  final String aggregationMethod; // 'average' | 'sum' | 'cumulative'
  final int displayPrecision;

  const BreederMetricDefinition({
    required this.id,
    required this.code,
    required this.label,
    required this.unit,
    required this.sexScope,
    required this.periodType,
    required this.aggregationMethod,
    required this.displayPrecision,
  });

  factory BreederMetricDefinition.fromMap(Map<String, dynamic> map) {
    return BreederMetricDefinition(
      id: map['id'] as String,
      code: map['code'] as String,
      label: map['label'] as String,
      unit: map['unit'] as String,
      sexScope: map['sexScope'] as String,
      periodType: map['periodType'] as String,
      aggregationMethod: map['aggregationMethod'] as String,
      displayPrecision: (map['displayPrecision'] as num?)?.toInt() ?? 0,
    );
  }

  String format(num? value) {
    if (value == null) return '—';
    return value.toStringAsFixed(displayPrecision);
  }
}

class BreederBenchmarkProfile {
  final String id;
  final String profileKey;
  final String company;
  final String breed;
  final String product;
  final String guideVersion;
  final DateTime? publicationDate;
  final String sourceUrl;
  final int effectiveAgeStartDays;
  final int? effectiveAgeEndDays;
  final String lifecycleCoverage;
  final String state; // 'draft' | 'active' | 'archived'

  const BreederBenchmarkProfile({
    required this.id,
    required this.profileKey,
    required this.company,
    required this.breed,
    required this.product,
    required this.guideVersion,
    required this.publicationDate,
    required this.sourceUrl,
    required this.effectiveAgeStartDays,
    required this.effectiveAgeEndDays,
    required this.lifecycleCoverage,
    required this.state,
  });

  factory BreederBenchmarkProfile.fromMap(Map<String, dynamic> map) {
    return BreederBenchmarkProfile(
      id: map['id'] as String,
      profileKey: map['profileKey'] as String,
      company: map['company'] as String,
      breed: map['breed'] as String,
      product: map['product'] as String,
      guideVersion: map['guideVersion'] as String,
      publicationDate: DateTime.tryParse(
        map['publicationDate']?.toString() ?? '',
      ),
      sourceUrl: map['sourceUrl'] as String,
      effectiveAgeStartDays: (map['effectiveAgeStartDays'] as num?)?.toInt() ?? 0,
      effectiveAgeEndDays: (map['effectiveAgeEndDays'] as num?)?.toInt(),
      lifecycleCoverage: map['lifecycleCoverage'] as String? ?? '',
      state: map['state'] as String? ?? 'draft',
    );
  }

  String get displayName => '$company $breed — $product';
}

class BreederBenchmarkValue {
  final String id;
  final String profileId;
  final String metricId;
  final String sex; // 'female' | 'male' | 'both'
  final int ageDays;
  final int ageWeek;
  final int? productionWeek;
  final String periodType; // 'daily' | 'weekly' | 'cumulative'
  final double? targetValue;
  final double? lowerBound;
  final double? upperBound;

  const BreederBenchmarkValue({
    required this.id,
    required this.profileId,
    required this.metricId,
    required this.sex,
    required this.ageDays,
    required this.ageWeek,
    required this.productionWeek,
    required this.periodType,
    required this.targetValue,
    required this.lowerBound,
    required this.upperBound,
  });

  factory BreederBenchmarkValue.fromMap(Map<String, dynamic> map) {
    return BreederBenchmarkValue(
      id: map['id'] as String,
      profileId: map['profileId'] as String,
      metricId: map['metricId'] as String,
      sex: map['sex'] as String,
      ageDays: (map['ageDays'] as num).toInt(),
      ageWeek: (map['ageWeek'] as num).toInt(),
      productionWeek: (map['productionWeek'] as num?)?.toInt(),
      periodType: map['periodType'] as String,
      targetValue: (map['targetValue'] as num?)?.toDouble(),
      lowerBound: (map['lowerBound'] as num?)?.toDouble(),
      upperBound: (map['upperBound'] as num?)?.toDouble(),
    );
  }
}
