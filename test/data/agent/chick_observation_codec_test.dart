import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/agent/chick_observation_codec.dart';
import 'package:hatchaudit/data/agent/station_registry.dart';
import 'package:hatchaudit/data/models/chick_quality_observation.dart';

void main() {
  const sampleId = '018f0f00-0000-7000-8000-000000000001';
  final observedAt = DateTime.utc(2026, 8, 24, 5);

  test('registry declares every approved Chick raw observation domain', () {
    final descriptors = {
      for (final schema in AgentStationRegistry.schemas.where(
        (schema) => schema.schemaKey.startsWith('chicks.'),
      ))
        schema.schemaKey: {
          for (final field in schema.fields)
            if (field.observation != null) field.fieldKey: field.observation,
        },
    };

    expect(
      descriptors.keys,
      containsAll(const {
        'chicks.weights',
        'chicks.yfbm',
        'chicks.cvt',
        'chicks.pasgar',
        'chicks.postmortem',
        'chicks.culled_analysis',
      }),
    );
    expect(descriptors.values.every((fields) => fields.isNotEmpty), isTrue);
  });

  test('number-list observations round-trip with stable ordered ids', () {
    final schema = AgentStationRegistry.require('chicks.weights', 1);
    final observations = ChickObservationCodec.extract(
      schema: schema,
      sampleId: sampleId,
      customerId: 'customer-a',
      sessionId: 'session-a',
      values: const {
        'weightsJson': [41.0, 0.0, 43.5],
      },
      observedAt: observedAt,
    );

    expect(
      observations.map(
        (item) => [
          item.kind,
          item.observationKey,
          item.ordinal,
          item.numericValue,
          item.textValue,
          item.unit,
        ],
      ),
      [
        ['series', 'weightsJson', 0, 41.0, null, 'grams'],
        ['series', 'weightsJson', 1, 0.0, null, 'grams'],
        ['series', 'weightsJson', 2, 43.5, null, 'grams'],
      ],
    );
    expect(observations.map((item) => item.id).toSet(), hasLength(3));
    expect(
      ChickObservationCodec.extract(
        schema: schema,
        sampleId: sampleId,
        customerId: 'customer-a',
        sessionId: 'session-a',
        values: const {
          'weightsJson': [41.0, 0.0, 43.5],
        },
        observedAt: observedAt,
      ).map((item) => item.id),
      observations.map((item) => item.id),
    );
    expect(ChickObservationCodec.reconstruct(schema, observations), {
      'weightsJson': [41.0, 0.0, 43.5],
    });
  });

  test('object lists and scalar tallies/ordinals round-trip exactly', () {
    final yfbm = AgentStationRegistry.require('chicks.yfbm', 1);
    final yfbmObservations = ChickObservationCodec.extract(
      schema: yfbm,
      sampleId: sampleId,
      customerId: 'customer-a',
      sessionId: 'session-a',
      values: const {
        'yfbmEntriesJson': [
          {'chickWeight': 42.0, 'yolkWeight': 4.5},
          {'chickWeight': 44.0, 'yolkWeight': 0.0},
        ],
      },
      observedAt: observedAt,
    );
    expect(yfbmObservations, hasLength(4));
    expect(ChickObservationCodec.reconstruct(yfbm, yfbmObservations), {
      'yfbmEntriesJson': [
        {'chickWeight': 42.0, 'yolkWeight': 4.5},
        {'chickWeight': 44.0, 'yolkWeight': 0.0},
      ],
    });

    final postmortem = AgentStationRegistry.require('chicks.postmortem', 1);
    final pmObservations = ChickObservationCodec.extract(
      schema: postmortem,
      sampleId: sampleId,
      customerId: 'customer-a',
      sessionId: 'session-a',
      values: const {
        'pmSampleSize': 10,
        'pmCollectionPoint': 'farm',
        'pmOmphalitisCount': 0,
        'pmOmphalitisSeverity': 'mild',
      },
      observedAt: observedAt,
    );
    expect(ChickObservationCodec.reconstruct(postmortem, pmObservations), {
      'pmSampleSize': 10,
      'pmCollectionPoint': 'farm',
      'pmOmphalitisCount': 0,
      'pmOmphalitisSeverity': 'mild',
    });
  });

  test('keyed culled tallies preserve Unicode keys and explicit zero', () {
    final schema = AgentStationRegistry.require('chicks.culled_analysis', 1);
    final observations = ChickObservationCodec.extract(
      schema: schema,
      sampleId: sampleId,
      customerId: 'customer-a',
      sessionId: 'session-a',
      values: const {
        'culledChicksTotalEggSet': 100,
        'culledChicksAnalysisJson': [
          {'id': 'sticky/جاف', 'count': 0},
          {'id': 'weak', 'count': 3},
        ],
      },
      observedAt: observedAt,
    );

    expect(
      observations
          .where(
            (item) =>
                item.observationKey.startsWith('culled:') &&
                item.observationKey != 'culled:__present',
          )
          .map((item) => [item.observationKey, item.numericValue]),
      [
        ['culled:sticky/جاف', 0.0],
        ['culled:weak', 3.0],
      ],
    );
    expect(ChickObservationCodec.reconstruct(schema, observations), {
      'culledChicksTotalEggSet': 100,
      'culledChicksAnalysisJson': [
        {'id': 'sticky/جاف', 'count': 0},
        {'id': 'weak', 'count': 3},
      ],
    });
  });

  test('an explicit empty culled list remains present, not missing', () {
    final schema = AgentStationRegistry.require('chicks.culled_analysis', 1);
    final values = const {
      'culledChicksTotalEggSet': 100,
      'culledChicksAnalysisJson': <Object?>[],
    };
    final observations = ChickObservationCodec.extract(
      schema: schema,
      sampleId: sampleId,
      customerId: 'customer-a',
      sessionId: 'session-a',
      values: values,
      observedAt: observedAt,
    );
    expect(ChickObservationCodec.reconstruct(schema, observations), values);
    expect(ChickObservationCodec.canRoundTrip(schema, values), isTrue);
  });

  test(
    'object property order and registry-ignored cache fields are lossless',
    () {
      final yfbm = AgentStationRegistry.require('chicks.yfbm', 1);
      expect(
        ChickObservationCodec.canRoundTrip(yfbm, const {
          'yfbmEntriesJson': [
            {'yolkWeight': 4.5, 'chickWeight': 42.0},
          ],
        }),
        isTrue,
      );

      final culled = AgentStationRegistry.require('chicks.culled_analysis', 1);
      expect(
        ChickObservationCodec.canRoundTrip(culled, const {
          'culledChicksAnalysisJson': [
            {
              'pct': 0.5,
              'sourceRefs': <Object?>[],
              'commonCauses': <Object?>[],
              'description': 'derived label',
              'subtype': 'derived subtype',
              'category': 'derived category',
              'count': 5,
              'id': 'weak',
            },
          ],
        }),
        isTrue,
      );
    },
  );

  test('sparse or incomplete series are omitted instead of compressed', () {
    final weights = AgentStationRegistry.require('chicks.weights', 1);
    final weightObservations = ChickObservationCodec.extract(
      schema: weights,
      sampleId: sampleId,
      customerId: 'customer-a',
      sessionId: 'session-a',
      values: const {
        'weightsJson': [40.0, 41.0, 42.0],
      },
      observedAt: observedAt,
    ).where((item) => item.ordinal != 1);
    expect(
      ChickObservationCodec.reconstruct(weights, weightObservations),
      isNot(contains('weightsJson')),
    );

    final yfbm = AgentStationRegistry.require('chicks.yfbm', 1);
    final yfbmObservations = ChickObservationCodec.extract(
      schema: yfbm,
      sampleId: sampleId,
      customerId: 'customer-a',
      sessionId: 'session-a',
      values: const {
        'yfbmEntriesJson': [
          {'chickWeight': 42.0, 'yolkWeight': 4.5},
        ],
      },
      observedAt: observedAt,
    ).where((item) => item.observationKey != 'yfbm:yolkWeight');
    expect(
      ChickObservationCodec.reconstruct(yfbm, yfbmObservations),
      isNot(contains('yfbmEntriesJson')),
    );

    final culled = AgentStationRegistry.require('chicks.culled_analysis', 1);
    final culledObservations = ChickObservationCodec.extract(
      schema: culled,
      sampleId: sampleId,
      customerId: 'customer-a',
      sessionId: 'session-a',
      values: const {
        'culledChicksAnalysisJson': [
          {'id': 'weak', 'count': 1},
          {'id': 'small', 'count': 2},
        ],
      },
      observedAt: observedAt,
    ).where((item) => item.ordinal != 0);
    expect(
      ChickObservationCodec.reconstruct(culled, culledObservations),
      isNot(contains('culledChicksAnalysisJson')),
    );
  });

  test('wrong-unit and wrong-value-shape observations are omitted', () {
    final schema = AgentStationRegistry.require('chicks.pasgar', 1);
    final valid = ChickObservationCodec.extract(
      schema: schema,
      sampleId: sampleId,
      customerId: 'customer-a',
      sessionId: 'session-a',
      values: const {'pasgarSampleSize': 10},
      observedAt: observedAt,
    ).single;
    final wrongUnit = ChickQualityObservation.fromMap({
      ...valid.toMap(),
      'unit': 'grams',
    });
    final wrongShape = ChickQualityObservation.fromMap({
      ...valid.toMap(),
      'numericValue': null,
      'textValue': 'bad',
    });

    expect(ChickObservationCodec.reconstruct(schema, [wrongUnit]), isEmpty);
    expect(ChickObservationCodec.reconstruct(schema, [wrongShape]), isEmpty);
    expect(ChickObservationCodec.isValid(schema, valid), isTrue);
    expect(ChickObservationCodec.isValid(schema, wrongUnit), isFalse);
    expect(ChickObservationCodec.isValid(schema, wrongShape), isFalse);
  });
}
