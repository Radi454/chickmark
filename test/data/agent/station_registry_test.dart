import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/utils/calculation_utils.dart';
import 'package:hatchaudit/data/agent/station_adapter.dart';
import 'package:hatchaudit/data/agent/station_registry.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';

void main() {
  test(
    'station registry generator reports committed contracts as current',
    () async {
      final result = await Process.run('dart', const [
        'tool/agent_schema/generate_station_registry.dart',
        '--check',
      ], workingDirectory: Directory.current.path);

      expect(
        result.exitCode,
        0,
        reason: [
          result.stdout.toString().trim(),
          result.stderr.toString().trim(),
        ].where((line) => line.isNotEmpty).join('\n'),
      );
    },
  );

  test('every active hatchery panel has a versioned agent schema', () {
    final mappedTables = AgentStationRegistry.schemas
        .expand((schema) => schema.persistence)
        .map((mapping) => mapping.localTable)
        .toSet();

    expect(
      mappedTables,
      containsAll(PanelSampleSchema.panels.map((panel) => panel.tableName)),
    );
  });

  test('station schema identities are unique', () {
    expect(
      AgentStationRegistry.schemas.map((schema) => schema.identity).toSet(),
      hasLength(AgentStationRegistry.schemas.length),
    );
  });

  test('generated persistence columns are bidirectional and unambiguous', () {
    for (final schema in AgentStationRegistry.schemas) {
      final bindings = [
        ...schema.fields.map(
          (field) => (
            fieldKey: field.fieldKey,
            local: field.persistence['localColumn'],
            remote: field.persistence['remoteColumn'],
          ),
        ),
        ...schema.calculations.map(
          (calculation) => (
            fieldKey: calculation.fieldKey,
            local: calculation.persistence['localColumn'],
            remote: calculation.persistence['remoteColumn'],
          ),
        ),
      ];
      expect(
        bindings.map((binding) => binding.local).toSet(),
        hasLength(bindings.length),
        reason: '${schema.identity} repeats a local column',
      );
      expect(
        bindings.map((binding) => binding.remote).toSet(),
        hasLength(bindings.length),
        reason: '${schema.identity} repeats a remote column',
      );
    }

    final schema = AgentStationRegistry.require('chicks.weights', 1);
    final fieldValues = AgentStationAdapter.fieldValuesFromLocalRow(schema, {
      'weightsJson': '[41.0,43.0]',
      'sampleSize': 2,
      'avgWeight': 42.0,
    });

    expect(fieldValues, {
      'weightsJson': [41.0, 43.0],
      'sampleSize': 2,
      'avgWeight': 42.0,
    });
    expect(
      AgentStationAdapter.localPersistenceValues(schema, {
        'weightsJson': fieldValues['weightsJson'],
      }),
      {
        'weightsJson': '[41.0,43.0]',
        'sampleSize': 2,
        'avgWeight': 42.0,
        'uniformityPct': 100.0,
        'cvPct': 3.4,
      },
    );
  });

  test('Pasgar requires the sample and six explicit observations', () {
    final schema = AgentStationRegistry.require('chicks.pasgar', 1);
    const expectedRequired = {
      'pasgarSampleSize',
      'pasgarReflexesCount',
      'pasgarBeakCount',
      'pasgarNavelCount',
      'pasgarBellyCount',
      'pasgarLegCount',
      'pasgarFeatherDevCount',
    };

    expect(schema.requiredFieldKeys.toSet(), expectedRequired);
    expect(
      schema.fields
          .where((field) => field.fieldKey != 'pasgarSampleSize')
          .every(
            (field) =>
                field.explicitZero &&
                field.validation['maxFieldKey'] == 'pasgarSampleSize',
          ),
      isTrue,
    );
    expect(schema.persistence.single.localTable, 'chick_quality');
  });

  test(
    'non-Pasgar schemas expose calculations and editable field metadata',
    () {
      final schema = AgentStationRegistry.require('chicks.weights', 1);

      expect(schema.allowedLayers, contains('house'));
      expect(schema.fields.single.type, 'number_list');
      expect(schema.fields.single.validation['itemMax'], 200);
      expect(schema.calculations.map((calculation) => calculation.fieldKey), [
        'sampleSize',
        'avgWeight',
        'uniformityPct',
        'cvPct',
      ]);
      expect(schema.calculations.last.persistence['remoteColumn'], 'cv_pct');
    },
  );

  test('canonical calculation parity vectors match Flutter formulas', () {
    final vectors = AgentStationRegistry.calculationParityVectors;
    final percent = (vectors['percentOf']! as List).single as Map;
    expect(
      CalculationUtils.percentOf(percent['count'], percent['total']),
      percent['expected'],
    );
    final cv = (vectors['cvPercent']! as List).single as Map;
    expect(
      CalculationUtils.cvPercent(
        (cv['values']! as List)
            .cast<num>()
            .map((value) => value.toDouble())
            .toList(growable: false),
        sample: cv['sample']! as bool,
      ),
      cv['expected'],
    );
    final uniformity = (vectors['uniformityPercent']! as List).single as Map;
    expect(
      CalculationUtils.uniformityPercent(
        (uniformity['values']! as List)
            .cast<num>()
            .map((value) => value.toDouble())
            .toList(growable: false),
        (uniformity['minimum']! as num).toDouble(),
        (uniformity['maximum']! as num).toDouble(),
      ),
      uniformity['expected'],
    );
    final pasgar = (vectors['pasgarScore']! as List).single as Map;
    expect(
      CalculationUtils.pasgarScore(
        pasgar['sampleSize']! as int,
        (pasgar['defectCounts']! as List).cast<int>(),
      ),
      pasgar['expected'],
    );
    final fertility = (vectors['fertility']! as List).single as Map;
    expect(
      CalculationUtils.fertility(
        fertility['fertile']! as int,
        fertility['clear']! as int,
      ),
      fertility['expected'],
    );
    final hatchability = (vectors['hatchability']! as List).single as Map;
    expect(
      CalculationUtils.hatchability(
        hatchability['hatched']! as int,
        hatchability['total']! as int,
      ),
      hatchability['expected'],
    );
    final hof = (vectors['hof']! as List).single as Map;
    expect(
      CalculationUtils.hof(
        (hof['hatchability']! as num).toDouble(),
        (hof['fertility']! as num).toDouble(),
      ),
      hof['expected'],
    );
  });
}
