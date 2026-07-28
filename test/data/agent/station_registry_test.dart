import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}
