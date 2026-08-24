import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/agent/station_adapter.dart';
import 'package:hatchaudit/data/agent/station_registry.dart';

void main() {
  final pasgar = AgentStationRegistry.require('chicks.pasgar', 1);

  test('classification distinguishes BLOCK WARN FLAG and preserves zero', () {
    final validValues = <String, Object?>{
      'pasgarSampleSize': 40,
      'pasgarReflexesCount': 0,
      'pasgarBeakCount': 0,
      'pasgarNavelCount': 0,
      'pasgarBellyCount': 0,
      'pasgarLegCount': 0,
      'pasgarFeatherDevCount': 0,
    };

    final ok = AgentStationAdapter.classifyQuality(
      pasgar,
      validValues,
      context: const AgentStationQualityContext(
        domain: 'chicks.pasgar',
        schemaVersion: 1,
        scopeType: 'pool',
        scopeKey: '{}',
        sampleKey: 'stable-key',
      ),
    );
    expect(ok.status, 'OK');
    expect(ok.flags, isEmpty);

    final flag = AgentStationAdapter.classifyQuality(
      pasgar,
      const {'pasgarSampleSize': 40},
      context: const AgentStationQualityContext(
        domain: 'chicks.pasgar',
        schemaVersion: 1,
        scopeType: 'pool',
        scopeKey: '{}',
        sampleKey: 'stable-key',
      ),
    );
    expect(flag.status, 'FLAG');
    expect(
      flag.flags,
      contains(
        predicate<AgentStationQualityFlag>(
          (item) =>
              item.tier == AgentStationQualityTier.flag &&
              item.code == 'missing_required',
        ),
      ),
    );

    final warn = AgentStationAdapter.classifyQuality(
      pasgar,
      {...validValues, 'pasgarBeakCount': 41},
      context: const AgentStationQualityContext(
        domain: 'chicks.pasgar',
        schemaVersion: 1,
        scopeType: 'pool',
        scopeKey: '{}',
        sampleKey: 'stable-key',
      ),
    );
    expect(warn.status, 'WARN');
    expect(warn.flags.single.code, 'above_dynamic_maximum');

    final block = AgentStationAdapter.classifyQuality(
      pasgar,
      validValues,
      context: const AgentStationQualityContext(
        domain: 'chicks.pasgar',
        schemaVersion: 1,
        scopeType: 'house',
        scopeKey: '{"houseId":"H1"}',
        sampleKey: 'stable-key',
      ),
    );
    expect(block.status, 'BLOCK');
    expect(block.flags.single.code, 'scope_not_allowed');
  });

  test('classification flags missing raw evidence and derived mismatch', () {
    final weights = AgentStationRegistry.require('chicks.weights', 1);
    final result = AgentStationAdapter.classifyQuality(
      weights,
      const {'sampleSize': 2, 'avgWeight': 999.0},
      context: const AgentStationQualityContext(
        domain: 'chicks.weights',
        schemaVersion: 1,
        scopeType: 'house',
        scopeKey: '{"houseId":"H1"}',
        sampleKey: 'stable-key',
      ),
    );

    expect(result.status, 'FLAG');
    expect(
      result.flags.map((flag) => flag.code),
      containsAll(['missing_raw_evidence', 'derived_cache_mismatch']),
    );
    expect(result.canonicalJson, result.canonicalJson);
  });

  test('classification tolerates a partially completed derived schema', () {
    final result = AgentStationAdapter.classifyQuality(
      pasgar,
      const {
        'pasgarSampleSize': 20,
        'pasgarReflexesCount': 1,
        'pasgarReflexesPct': 5.0,
      },
      context: const AgentStationQualityContext(
        domain: 'chicks.pasgar',
        schemaVersion: 1,
        scopeType: 'pool',
        scopeKey: '{}',
        sampleKey: 'stable-key',
      ),
    );

    expect(result.status, 'FLAG');
    expect(
      result.flags.map((flag) => flag.code),
      everyElement('missing_required'),
    );
  });

  test('classification blocks malformed derived inputs without throwing', () {
    final result = AgentStationAdapter.classifyQuality(
      pasgar,
      const {
        'pasgarSampleSize': 20,
        'pasgarReflexesCount': 'not-a-number',
        'pasgarReflexesPct': 5.0,
      },
      context: const AgentStationQualityContext(
        domain: 'chicks.pasgar',
        schemaVersion: 1,
        scopeType: 'pool',
        scopeKey: '{}',
        sampleKey: 'stable-key',
      ),
    );

    expect(result.status, 'BLOCK');
    expect(result.flags.map((flag) => flag.code), contains('invalid_type'));
    expect(
      result.flags.map((flag) => flag.code),
      contains('derived_cache_mismatch'),
    );
  });

  test('classification tolerates a derived object missing a required item', () {
    final culled = AgentStationRegistry.require('chicks.culled_analysis', 1);
    final result = AgentStationAdapter.classifyQuality(
      culled,
      const {
        'culledChicksTotalEggSet': 100,
        'culledChicksAnalysisJson': [
          {'id': 'sticky_dehydrated_burned_chick'},
        ],
        'culledChicksAffectedPct': 1.0,
      },
      context: const AgentStationQualityContext(
        domain: 'chicks.culled_analysis',
        schemaVersion: 1,
        scopeType: 'pool',
        scopeKey: '{}',
        sampleKey: 'stable-key',
      ),
    );

    expect(result.status, 'WARN');
    expect(result.flags.map((flag) => flag.code), contains('item_required'));
    expect(
      result.flags.map((flag) => flag.code),
      contains('derived_cache_mismatch'),
    );
  });

  test('registry parity vectors pin canonical classification output', () {
    final vectors =
        AgentStationRegistry.qualityClassification['parityVectors']!
            as List<Object?>;
    for (final rawVector in vectors) {
      final vector = Map<String, Object?>.from(rawVector! as Map);
      final context = Map<String, Object?>.from(vector['context']! as Map);
      final result = AgentStationAdapter.classifyQuality(
        AgentStationRegistry.require(
          vector['schemaKey']! as String,
          vector['schemaVersion']! as int,
        ),
        Map<String, Object?>.from(vector['values']! as Map),
        context: AgentStationQualityContext(
          domain: context['domain']! as String,
          schemaVersion: context['schemaVersion']! as int,
          scopeType: context['scopeType']! as String,
          scopeKey: context['scopeKey']! as String,
          sampleKey: context['sampleKey']! as String,
        ),
      );
      expect(result.status, vector['expectedStatus']);
      expect(result.canonicalJson, jsonEncode(vector['expectedFlags']));
    }
  });
}
