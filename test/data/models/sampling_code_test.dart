import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/sampling_code.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';

void main() {
  test('normalizes exactly three ASCII letters', () {
    expect(normalizeThreeLetterCode(' org '), 'ORG');
    expect(normalizeThreeLetterCode('aZq'), 'AZQ');
    expect(normalizeThreeLetterCode('AB'), isNull);
    expect(normalizeThreeLetterCode('AB12'), isNull);
    expect(normalizeThreeLetterCode('A-BC'), isNull);
    expect(normalizeThreeLetterCode('ÉBC'), isNull);
  });

  test('builds scope segments in physical order and omits pooled levels', () {
    final path = SamplingScopePath(
      house: 'H1',
      setter: null,
      hatcher: 'HT3',
      trolley: 'TR2',
      tray: 'T1',
      sampleId: 'stable-id',
      sampleNumber: 7,
    );

    expect(
      SamplingCode.build(
        customerCode: 'org',
        hatcheryCode: 'hat',
        flockCode: 'frm',
        breedAbbreviation: 'RS',
        path: path,
      ),
      'ORG-HAT-FRM-RS-H1-HT3-TR2-T1-SA7',
    );
  });

  test('missing references or unknown legacy scopes have no trusted code', () {
    final path = SamplingScopePath(
      sampleId: 'stable-id',
      sampleNumber: 1,
      unknownLevels: {SamplingScopeLevel.house},
    );
    expect(
      SamplingCode.build(
        customerCode: 'ORG',
        hatcheryCode: 'HAT',
        flockCode: 'FRM',
        breedAbbreviation: 'RS',
        path: path,
      ),
      isNull,
    );
    expect(
      SamplingCode.build(
        customerCode: null,
        hatcheryCode: 'HAT',
        flockCode: 'FRM',
        breedAbbreviation: 'RS',
        path: SamplingScopePath(sampleId: 'id', sampleNumber: 1),
      ),
      isNull,
    );
  });

  test(
    'identity equality is normalized and paired setter hatcher identity aware',
    () {
      final a = SamplingNode(
        id: 'a',
        sessionId: 'session',
        panelKey: 'chick_quality',
        level: SamplingScopeLevel.setter,
        parentId: null,
        identity: {'setter': 'S2', 'hatcher': 'HT4'},
      );
      final same = SamplingNode(
        id: 'same',
        sessionId: 'session',
        panelKey: 'chick_quality',
        level: SamplingScopeLevel.setter,
        parentId: null,
        identity: {'hatcher': ' 4 ', 'setter': '2'},
      );
      final differentPair = SamplingNode(
        id: 'different',
        sessionId: 'session',
        panelKey: 'chick_quality',
        level: SamplingScopeLevel.setter,
        parentId: null,
        identity: {'setter': 'S2', 'hatcher': 'HT5'},
      );
      final sameUnderAnotherParent = SamplingNode(
        id: 'other-parent',
        sessionId: 'session',
        panelKey: 'chick_quality',
        parentId: 'house-2',
        level: SamplingScopeLevel.setter,
        identity: {'setter': 'S2', 'hatcher': 'HT4'},
      );
      final houseNorth = SamplingNode(
        id: 'north-1',
        sessionId: 'session',
        panelKey: 'egg_quality',
        level: SamplingScopeLevel.house,
        identity: {'code': 'HNORTH'},
      );
      final houseNorthWithoutPrefix = SamplingNode(
        id: 'north-2',
        sessionId: 'session',
        panelKey: 'egg_quality',
        level: SamplingScopeLevel.house,
        identity: {'code': 'NORTH'},
      );

      expect(sameScopeIdentity(a, same), isTrue);
      expect(sameScopeIdentity(a, differentPair), isFalse);
      expect(sameScopeIdentity(a, sameUnderAnotherParent), isFalse);
      expect(sameScopeIdentity(houseNorth, houseNorthWithoutPrefix), isFalse);
      expect(
        sameScopeIdentity(
          houseNorth.copyWith(identity: {'code': 'H2'}),
          houseNorth.copyWith(identity: {'code': '2'}),
        ),
        isTrue,
      );
    },
  );

  test('scope codes normalize only numeric display prefixes', () {
    final textualPath = SamplingScopePath(
      house: 'HNORTH',
      sampleId: 'sample',
      sampleNumber: 1,
    );
    expect(
      SamplingCode.build(
        customerCode: 'ORG',
        hatcheryCode: 'HAT',
        flockCode: 'FRM',
        breedAbbreviation: 'RS',
        path: textualPath,
      ),
      'ORG-HAT-FRM-RS-HHNORTH-SA1',
    );
  });

  test('scope path rejects blank ids and nonpositive serials', () {
    expect(
      () => SamplingScopePath(sampleId: ' ', sampleNumber: 1),
      throwsArgumentError,
    );
    expect(
      () => SamplingScopePath(sampleId: 'sample', sampleNumber: 0),
      throwsArgumentError,
    );
  });
}
