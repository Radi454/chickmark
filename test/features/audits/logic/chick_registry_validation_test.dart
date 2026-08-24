import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/logic/chick_registry_validation.dart';

void main() {
  test('chick domain values are warned by their registry rules only', () {
    final warnings = validateChickRegistryDomains(
      chickQualityValues: {
        'cvtReadingsJson': jsonEncode({
          'unit': '°F',
          'readings': {'front_top': 79.0},
        }),
        'pmSampleSize': 10,
        'pmCollectionPoint': 'hatcher',
        'pmOmphalitisCount': 1,
        'pmGaseousCecaCount': 0,
        'pmGizzardErosionsCount': 0,
        'pmAirSacCaseationsCount': 0,
        'pmUrolithiasisCount': 0,
        'pmNephritisCount': 0,
        'pmGeneralSepticemiaCount': 0,
      },
      chickWeightValues: {'weightsJson': '[0,201]'},
    );

    expect(
      warnings.map((warning) => '${warning.schemaKey}:${warning.code}'),
      containsAll([
        'chicks.cvt:item_out_of_range',
        'chicks.weights:item_out_of_range',
        'chicks.postmortem:required',
      ]),
    );
    expect(
      warnings.where((warning) => warning.code == 'unknown_field'),
      isEmpty,
    );
  });
}
