import '../../../data/models/farm_visit_models.dart';

class VisitBriefingBuilder {
  const VisitBriefingBuilder();

  VisitBriefingSnapshot build({
    required DateTime generatedAt,
    required List<VisitBriefingConcern> concerns,
    String? targetVersion,
    String? ruleVersion,
    List<String> previousInvestigationKeys = const [],
  }) {
    final investigations = <String>{...previousInvestigationKeys};
    final evidence = <String, Object?>{};

    for (final concern in concerns) {
      evidence[concern.concernId] = concern.toJson();
      investigations
        ..addAll(concern.investigationKeys)
        ..addAll(_investigationsFor(concern.metricKey));
    }

    return VisitBriefingSnapshot(
      generatedAtIso: generatedAt.toUtc().toIso8601String(),
      concernIds: concerns.map((concern) => concern.concernId).toList(),
      evidence: evidence,
      investigations: investigations.toList()..sort(),
      targetVersion: targetVersion,
      ruleVersion: ruleVersion,
    );
  }

  Iterable<String> _investigationsFor(String metricKey) {
    final normalized = metricKey.toLowerCase();
    final checks = <String>{};
    if (normalized.contains('weight')) {
      checks.addAll(const [
        'sample_weights_by_location',
        'check_feeder_distribution',
        'check_nipple_flow',
        'examine_enteric_health',
      ]);
    }
    if (normalized.contains('feed')) {
      checks.addAll(const [
        'check_feeder_distribution',
        'review_feed_delivery',
        'assess_feed_quality',
      ]);
    }
    if (normalized.contains('water')) {
      checks.addAll(const [
        'check_nipple_flow',
        'check_water_meter',
        'review_water_interruptions',
      ]);
    }
    if (normalized.contains('mortality')) {
      checks.addAll(const [
        'review_mortality_causes',
        'clinical_examination',
        'necropsy',
      ]);
    }
    if (normalized.contains('temperature') ||
        normalized.contains('humidity') ||
        normalized.contains('co2') ||
        normalized.contains('ammonia') ||
        normalized.contains('ventilation')) {
      checks.addAll(const [
        'measure_environment_by_location',
        'inspect_ventilation_equipment',
      ]);
    }
    if (normalized.contains('uniformity') || normalized.contains('cv')) {
      checks.addAll(const [
        'sample_weights_by_location',
        'check_feeder_distribution',
        'check_nipple_flow',
      ]);
    }
    return checks;
  }
}
