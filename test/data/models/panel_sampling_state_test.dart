import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/panel_sampling_state.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';

void main() {
  SamplingNode node({
    required String id,
    required SamplingScopeLevel level,
    String panelKey = 'candled_egg_breakout',
    String? parentId,
    String? identityKey,
    Map<String, String> identity = const {},
    String? sampleId,
    int? sampleNumber,
  }) => SamplingNode(
    id: id,
    sessionId: 'session',
    panelKey: panelKey,
    parentId: parentId,
    level: level,
    identityKey: identityKey,
    identity: identity,
    sampleId: sampleId,
    sampleNumber: sampleNumber,
  );

  test(
    'samples are terminal leaves and a single comparison stays comparison',
    () {
      final house = node(
        id: 'house-node',
        level: SamplingScopeLevel.house,
        identityKey: 'H1',
        identity: {'code': 'H1'},
      );
      final tray = node(
        id: 'tray-node',
        level: SamplingScopeLevel.tray,
        parentId: house.id,
        identityKey: '1',
        sampleId: 'stable-sample-id',
        sampleNumber: 1,
      );
      final state = PanelSamplingState(
        sessionId: 'session',
        panelKey: 'candled_egg_breakout',
        nodes: [house, tray],
        serialHighWatermark: 1,
        activeSampleId: 'stable-sample-id',
      );

      expect(state.samples, [tray]);
      expect(
        state.isComparisonAt(parentId: null, level: SamplingScopeLevel.house),
        isTrue,
      );
      expect(
        state.hasIdentityUnderParent(
          parentId: null,
          level: SamplingScopeLevel.house,
          identity: {'code': 'H1'},
        ),
        isTrue,
      );
      expect(
        state.hasIdentityUnderParent(
          parentId: null,
          level: SamplingScopeLevel.house,
          identity: {'code': '1'},
        ),
        isTrue,
      );
      expect(
        state.hasIdentityUnderParent(
          parentId: 'another-house',
          level: SamplingScopeLevel.tray,
          identity: {'code': '1'},
        ),
        isFalse,
      );
      final textualHouse = node(
        id: 'text-house',
        level: SamplingScopeLevel.house,
        identity: {'code': 'HNORTH'},
      );
      final textState = PanelSamplingState(
        sessionId: 'session',
        panelKey: 'candled_egg_breakout',
        nodes: [textualHouse],
        serialHighWatermark: 0,
        activeSampleId: '',
      );
      expect(
        textState.hasIdentityUnderParent(
          parentId: null,
          level: SamplingScopeLevel.house,
          identity: {'code': 'NORTH'},
        ),
        isFalse,
      );
      expect(
        textState.hasIdentityUnderParent(
          parentId: null,
          level: SamplingScopeLevel.house,
          identity: {'code': 'hnorth'},
        ),
        isTrue,
      );
      expect(state.pathFor('stable-sample-id').sampleId, 'stable-sample-id');
    },
  );

  test(
    'path reconstruction leaves skipped ancestors pooled and retains paired keys',
    () {
      final pair = node(
        id: 'pair',
        level: SamplingScopeLevel.setter,
        panelKey: 'residue_breakout',
        identityKey: 'S2/HT4',
        identity: {'setter': 'S2', 'hatcher': 'HT4'},
      );
      final terminal = node(
        id: 'terminal',
        level: SamplingScopeLevel.tray,
        panelKey: 'residue_breakout',
        parentId: 'pair',
        identityKey: 'T1',
        sampleId: 'sample-1',
        sampleNumber: 1,
      );
      final path = PanelSamplingState(
        sessionId: 'session',
        panelKey: 'residue_breakout',
        nodes: [pair, terminal],
        serialHighWatermark: 1,
        activeSampleId: 'missing',
      ).pathFor('sample-1');

      expect(path.house, isNull);
      expect(path.setter, 'S2');
      expect(path.hatcher, 'HT4');
      expect(path.trolley, isNull);
      expect(path.tray, 'T1');
      expect(path.pooledAt(SamplingScopeLevel.house), isTrue);
    },
  );

  test('row round trip keeps immutable identity and sample id', () {
    final original = node(
      id: 'sample-1',
      level: SamplingScopeLevel.sample,
      identityKey: 'original',
      identity: {'code': 'original'},
      sampleId: 'sample-1',
      sampleNumber: 4,
    );
    final edited = original.copyWith(identity: {'code': 'edited'});
    final restored = SamplingNode.fromMap(edited.toMap());

    expect(restored.sampleId, 'sample-1');
    expect(restored.identity, {'code': 'edited'});
    expect(original.identity, {'code': 'original'});
    expect(restored.copyWith(sampleNumber: 5).sampleId, 'sample-1');
  });

  test(
    'database root sentinels deserialize as a root and preserve fallback identity',
    () {
      final serializedRoot = node(
        id: 'root-sample',
        level: SamplingScopeLevel.sample,
        panelKey: 'egg_storage',
        sampleId: 'root-sample',
        sampleNumber: 1,
      ).toMap();
      expect(serializedRoot['parentId'], '');
      expect(serializedRoot['identityKey'], '');
      final persisted = SamplingNode.fromMap(serializedRoot);
      final state = PanelSamplingState(
        sessionId: 'session',
        panelKey: 'egg_storage',
        nodes: [persisted],
        serialHighWatermark: 1,
        activeSampleId: 'root-sample',
      );

      expect(persisted.parentId, isNull);
      expect(persisted.identityKey, isNull);
      expect(state.pathFor('root-sample').sampleId, 'root-sample');
      expect(state.pathFor('root-sample').house, isNull);

      final withCode = SamplingNode(
        id: 'house-1',
        sessionId: 'session',
        panelKey: 'egg_quality',
        level: SamplingScopeLevel.house,
        identity: {'code': 'H1'},
      );
      expect(withCode.toMap()['identityKey'], 'H1');
      expect(SamplingNode.fromMap(withCode.toMap()).identityKey, 'H1');
    },
  );

  test(
    'complete Pooled state has one default sample and selects it deterministically',
    () {
      final terminal = node(
        id: 'default',
        level: SamplingScopeLevel.sample,
        panelKey: 'egg_storage',
        sampleId: 'default',
        sampleNumber: 1,
      );
      final state = PanelSamplingState(
        sessionId: 'session',
        panelKey: 'egg_storage',
        nodes: [terminal],
        serialHighWatermark: 1,
        activeSampleId: 'deleted',
      );

      expect(state.samples, [terminal]);
      expect(state.resolvedActiveSampleId, 'default');
      expect(state.pathFor('default').unknownLevels, isEmpty);
      expect(state.pathFor('default').house, isNull);
      expect(state.pathFor('default').setter, isNull);
      expect(state.pathFor('default').hatcher, isNull);
      expect(state.pathFor('default').trolley, isNull);
      expect(state.pathFor('default').tray, isNull);
    },
  );

  test('invalid tree references and cycles fail promptly', () {
    final cycleA = node(
      id: 'a',
      level: SamplingScopeLevel.house,
      parentId: 'b',
    );
    final cycleB = node(
      id: 'b',
      level: SamplingScopeLevel.setter,
      parentId: 'a',
    );
    final state = PanelSamplingState(
      sessionId: 'session',
      panelKey: 'candled_egg_breakout',
      nodes: [
        cycleA,
        cycleB,
        node(
          id: 'leaf',
          level: SamplingScopeLevel.tray,
          parentId: 'a',
          sampleId: 'leaf',
          sampleNumber: 1,
        ),
      ],
      serialHighWatermark: 1,
      activeSampleId: 'leaf',
    );
    expect(() => state.pathFor('leaf'), throwsStateError);
  });
}
