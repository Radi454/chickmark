import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/agent/station_adapter.dart';
import 'package:hatchaudit/data/agent/station_registry.dart';

void main() {
  test('validates and derives a non-Pasgar list station', () {
    final schema = AgentStationRegistry.require('chicks.weights', 1);
    final values = <String, Object?>{
      'weightsJson': [39.5, 40, 41.25],
    };

    final validation = AgentStationAdapter.validate(schema, values);
    final calculations = AgentStationAdapter.calculate(schema, values);
    final persistence = AgentStationAdapter.persistenceValues(schema, values);

    expect(validation.isValid, isTrue);
    expect(calculations['sampleSize'], 3);
    expect(calculations['avgWeight'], 40.3);
    expect(calculations['uniformityPct'], 100);
    expect(persistence['weights_json'], '[39.5,40,41.25]');
    expect(persistence['sample_size'], 3);
  });

  test('reports dynamic bounds, unknown fields, and nested item errors', () {
    final pasgar = AgentStationRegistry.require('chicks.pasgar', 1);
    final invalidPasgar = AgentStationAdapter.validate(pasgar, {
      'pasgarSampleSize': 40,
      'pasgarNavelCount': 41,
      'invented': 1,
    });
    expect(invalidPasgar.missing, hasLength(5));
    expect(
      invalidPasgar.issues.map((issue) => issue.code),
      containsAll(['above_dynamic_maximum', 'unknown_field']),
    );

    final culled = AgentStationRegistry.require('chicks.culled_analysis', 1);
    final invalidCulled = AgentStationAdapter.validate(culled, {
      'culledChicksTotalEggSet': 10,
      'culledChicksAnalysisJson': [
        {'id': 'navel_open_unhealed', 'count': 11},
      ],
    });
    expect(
      invalidCulled.issues.map((issue) => issue.code),
      contains('item_above_maximum'),
    );
  });

  test('applies conditional required fields for PM lesion severity', () {
    final schema = AgentStationRegistry.require('chicks.postmortem', 1);
    final values = <String, Object?>{
      'pmSampleSize': 10,
      'pmCollectionPoint': 'hatcher',
      'pmOmphalitisCount': 1,
      'pmGaseousCecaCount': 0,
      'pmGizzardErosionsCount': 0,
      'pmAirSacCaseationsCount': 0,
      'pmUrolithiasisCount': 0,
      'pmNephritisCount': 0,
      'pmGeneralSepticemiaCount': 0,
    };

    final validation = AgentStationAdapter.validate(schema, values);

    expect(validation.missing, contains('pmOmphalitisSeverity'));
  });
}
