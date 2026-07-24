import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/farm_visit_models.dart';
import 'package:hatchaudit/features/performance/services/visit_briefing_builder.dart';

void main() {
  const builder = VisitBriefingBuilder();

  test('weight feed water and mortality evidence maps to visit checks', () {
    final snapshot = builder.build(
      generatedAt: DateTime.utc(2026, 7, 24),
      targetVersion: 'ross-308-2022-as-hatched',
      ruleVersion: 'defaults-v1',
      concerns: const [
        VisitBriefingConcern(
          concernId: 'weight',
          metricKey: 'weight_deviation_pct',
          actualValue: -6.2,
          targetValue: 0,
          evidenceSummary: 'Feed below target since day 17',
        ),
        VisitBriefingConcern(
          concernId: 'water',
          metricKey: 'water_change_without_event',
          actualValue: -13.2,
          baselineValue: 1.74,
          evidenceSummary: 'Water:feed declined to 1.51',
        ),
        VisitBriefingConcern(
          concernId: 'mortality',
          metricKey: 'daily_mortality_pct',
          actualValue: 0.34,
          targetValue: 0.15,
          evidenceSummary: 'Mortality increased for 48 hours',
        ),
      ],
      previousInvestigationKeys: const ['sample_weights_by_location'],
    );

    expect(snapshot.concernIds, containsAll(['weight', 'water', 'mortality']));
    expect(snapshot.investigations, contains('check_nipple_flow'));
    expect(snapshot.investigations, contains('check_feeder_distribution'));
    expect(snapshot.investigations, contains('necropsy'));
    expect(
      VisitBriefingSnapshot.fromJson(snapshot.toJson()).toJson(),
      snapshot.toJson(),
    );
  });
}
