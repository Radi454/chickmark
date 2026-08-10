import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/features/audits/logic/audit_meaningful_data.dart';

/// Minimal `AuditModel` builder for these tests: only the fields required by
/// the constructor plus whichever optional fields a given test cares about.
AuditModel _audit(
  String auditType, {
  String? notes,
  // Egg storage
  int? esEggStorageDays,
  String? esEstReadingsJson,
  String? esEstPhotosJson,
  double? esEstAvg,
  double? esEstCv,
  int? esTurningTimes,
  String? esUvTrays,
  String? esTraySpacing,
  String? esCoolerProximity,
  bool? esCondensation,
  // Egg quality
  int? esEggQualityStorageDays,
  String? esEggWeights,
  int? esEggSampleSize,
  double? esEggAvgWeight,
  int? esEggBmkAge,
  double? esEggBmkWeight,
  // Chicks: pasgar
  int? pasgarSampleSize,
  double? pasgarFinalScore,
  // Chicks: weights
  String? chickWeights,
  int? chickSampleSize,
  double? chickAvgWeight,
  double? chickUniformityPct,
  double? chickCvPct,
  // Hatch analysis / egg breakout
  int? haTotalEggsSet,
  int? haHatched,
  String? ebTrayBreakoutJson,
  String? ebBreakoutType,
  int? ebTraySize,
  // Setters
  String? soSetterId,
  int? soIncubationAge,
  int? soIncubationHours,
  double? soCo2,
  // Hatchers
  String? hoHatcherId,
  int? hoIncubationAge,
  int? hoIncubationHours,
  double? hoCo2,
}) {
  return AuditModel(
    id: 'audit-1',
    auditType: auditType,
    customerId: 'customer-1',
    flockId: 'flock-1',
    date: DateTime(2026, 1, 1),
    status: 'active',
    createdBy: 'tester',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    notes: notes,
    esEggStorageDays: esEggStorageDays,
    esEstReadingsJson: esEstReadingsJson,
    esEstPhotosJson: esEstPhotosJson,
    esEstAvg: esEstAvg,
    esEstCv: esEstCv,
    esTurningTimes: esTurningTimes,
    esUvTrays: esUvTrays,
    esTraySpacing: esTraySpacing,
    esCoolerProximity: esCoolerProximity,
    esCondensation: esCondensation,
    esEggQualityStorageDays: esEggQualityStorageDays,
    esEggWeights: esEggWeights,
    esEggSampleSize: esEggSampleSize,
    esEggAvgWeight: esEggAvgWeight,
    esEggBmkAge: esEggBmkAge,
    esEggBmkWeight: esEggBmkWeight,
    pasgarSampleSize: pasgarSampleSize,
    pasgarFinalScore: pasgarFinalScore,
    chickWeights: chickWeights,
    chickSampleSize: chickSampleSize,
    chickAvgWeight: chickAvgWeight,
    chickUniformityPct: chickUniformityPct,
    chickCvPct: chickCvPct,
    haTotalEggsSet: haTotalEggsSet,
    haHatched: haHatched,
    ebTrayBreakoutJson: ebTrayBreakoutJson,
    ebBreakoutType: ebBreakoutType,
    ebTraySize: ebTraySize,
    soSetterId: soSetterId,
    soIncubationAge: soIncubationAge,
    soIncubationHours: soIncubationHours,
    soCo2: soCo2,
    hoHatcherId: hoHatcherId,
    hoIncubationAge: hoIncubationAge,
    hoIncubationHours: hoIncubationHours,
    hoCo2: hoCo2,
  );
}

void main() {
  group('treatBlankDraftAsSavedIncomplete', () {
    test('is true only for Hatchers', () {
      expect(treatBlankDraftAsSavedIncomplete(_audit('Hatchers')), isTrue);
      expect(treatBlankDraftAsSavedIncomplete(_audit('Setters')), isFalse);
      expect(treatBlankDraftAsSavedIncomplete(_audit('Egg')), isFalse);
    });
  });

  group('isMeaningfulPooledEggStorageValue', () {
    test('rejects null, empty/bracket strings; esEggStorageDays==0', () {
      expect(isMeaningfulPooledEggStorageValue('esEggStorageDays', null), isFalse);
      expect(isMeaningfulPooledEggStorageValue('esEggStorageDays', 0), isFalse);
      expect(isMeaningfulPooledEggStorageValue('esEggStorageDays', 5), isTrue);
      expect(isMeaningfulPooledEggStorageValue('esUvTrays', ''), isFalse);
      expect(isMeaningfulPooledEggStorageValue('esUvTrays', '[]'), isFalse);
      expect(isMeaningfulPooledEggStorageValue('esUvTrays', '{}'), isFalse);
      expect(isMeaningfulPooledEggStorageValue('esUvTrays', '[1]'), isTrue);
      expect(isMeaningfulPooledEggStorageValue('notes', 'hello'), isTrue);
    });
  });

  group('hasMeaningfulJsonObject / hasMeaningfulJsonData / isMeaningfulJsonValue', () {
    test('json object meaningfulness rejects empty and blank-valued maps', () {
      expect(hasMeaningfulJsonObject(null), isFalse);
      expect(hasMeaningfulJsonObject('{}'), isFalse);
      expect(hasMeaningfulJsonObject('{"k":""}'), isFalse);
      expect(hasMeaningfulJsonObject('{"k":"v"}'), isTrue);
    });

    test('json data meaningfulness rejects blank/invalid source', () {
      expect(hasMeaningfulJsonData(null), isFalse);
      expect(hasMeaningfulJsonData(''), isFalse);
      expect(hasMeaningfulJsonData('not json'), isFalse);
      expect(hasMeaningfulJsonData('[]'), isFalse);
      expect(hasMeaningfulJsonData('[1]'), isTrue);
      expect(hasMeaningfulJsonData('{"a":1}'), isTrue);
    });

    test('isMeaningfulJsonValue recurses into iterables and maps', () {
      expect(isMeaningfulJsonValue(null), isFalse);
      expect(isMeaningfulJsonValue(''), isFalse);
      expect(isMeaningfulJsonValue('  '), isFalse);
      expect(isMeaningfulJsonValue('x'), isTrue);
      expect(isMeaningfulJsonValue(<Object?>[]), isFalse);
      expect(isMeaningfulJsonValue(<Object?>['']), isFalse);
      expect(isMeaningfulJsonValue(<Object?>['x']), isTrue);
      expect(isMeaningfulJsonValue(<String, Object?>{'a': ''}), isFalse);
      expect(isMeaningfulJsonValue(<String, Object?>{'a': 'x'}), isTrue);
      expect(isMeaningfulJsonValue(3), isTrue);
    });
  });

  group('hasMeaningfulMachineId', () {
    test('rejects blank, default, and context-matching ids', () {
      expect(
        hasMeaningfulMachineId(null, defaultValue: 'S'),
        isFalse,
      );
      expect(
        hasMeaningfulMachineId('  ', defaultValue: 'S'),
        isFalse,
      );
      expect(
        hasMeaningfulMachineId('S', defaultValue: 'S'),
        isFalse,
      );
      expect(
        hasMeaningfulMachineId(
          'setter-1',
          defaultValue: 'S',
          contextValue: 'setter-1',
        ),
        isFalse,
      );
      expect(
        hasMeaningfulMachineId(
          'setter-1',
          defaultValue: 'S',
          contextValue: 'setter-2',
        ),
        isTrue,
      );
    });
  });

  group('hasMeaningfulWeightList', () {
    test('true only when at least one positive weight is present', () {
      expect(hasMeaningfulWeightList(null), isFalse);
      expect(hasMeaningfulWeightList(''), isFalse);
      expect(hasMeaningfulWeightList('not json'), isFalse);
      expect(hasMeaningfulWeightList('[]'), isFalse);
      expect(hasMeaningfulWeightList('[0, 0]'), isFalse);
      expect(hasMeaningfulWeightList('[0, 42.5]'), isTrue);
    });
  });

  group('hasMeaningfulChickWeightSample', () {
    test('true when any resolved value is meaningful', () {
      expect(hasMeaningfulChickWeightSample(const {}), isFalse);
      expect(
        hasMeaningfulChickWeightSample({'weightsJson': '[0]'}),
        isFalse,
      );
      expect(
        hasMeaningfulChickWeightSample({'weightsJson': '[42.5]'}),
        isTrue,
      );
      expect(
        hasMeaningfulChickWeightSample({'sampleSize': 5}),
        isTrue,
      );
      expect(
        hasMeaningfulChickWeightSample({'avgWeight': 10.0}),
        isTrue,
      );
    });
  });

  group('hasMeaningfulPasgarData', () {
    test('true only when a pasgar field is populated', () {
      expect(hasMeaningfulPasgarData(_audit('Chicks')), isFalse);
      expect(
        hasMeaningfulPasgarData(_audit('Chicks', pasgarSampleSize: 40)),
        isTrue,
      );
      expect(
        hasMeaningfulPasgarData(_audit('Chicks', pasgarFinalScore: 9.5)),
        isTrue,
      );
    });
  });

  group('hasSavableEggStorageData / hasMeaningfulEggStorageData', () {
    test('blank egg draft has no savable or meaningful storage data', () {
      final blank = _audit('Egg');
      expect(hasSavableEggStorageData(blank), isFalse);
      expect(hasMeaningfulEggStorageData(blank), isFalse);
    });

    test('a populated field makes storage data meaningful', () {
      final populated = _audit('Egg', esTurningTimes: 4);
      expect(hasMeaningfulEggStorageData(populated), isTrue);
      // esTurningTimes alone is not part of the *savable* subset.
      expect(hasSavableEggStorageData(populated), isFalse);
    });
  });

  group('hasMeaningfulEggQualityData', () {
    test('blank egg-quality draft is not meaningful', () {
      expect(hasMeaningfulEggQualityData(_audit('Egg')), isFalse);
    });

    test('a positive sample size makes it meaningful', () {
      expect(
        hasMeaningfulEggQualityData(_audit('Egg', esEggSampleSize: 30)),
        isTrue,
      );
    });
  });

  group('hasMeaningfulHatchCoreData / hasHatchScopeResults', () {
    test('blank hatch draft has no core or scope data', () {
      final blank = _audit('Hatch Analysis & Egg Breakouts');
      expect(hasMeaningfulHatchCoreData(blank), isFalse);
      expect(hasHatchScopeResults(blank), isFalse);
    });

    test('haHatched makes both core data and scope results meaningful', () {
      final withHatched = _audit(
        'Hatch Analysis & Egg Breakouts',
        haHatched: 8900,
      );
      expect(hasMeaningfulHatchCoreData(withHatched), isTrue);
      expect(hasHatchScopeResults(withHatched), isTrue);
    });
  });

  group('hasMeaningfulSetterCoreData / hasMeaningfulSetterData (parameterized)', () {
    test('a setter id equal to the context id is not meaningful', () {
      final draft = _audit('Setters', soSetterId: 'setter-1');
      expect(
        hasMeaningfulSetterCoreData(draft, contextSetterId: 'setter-1'),
        isFalse,
      );
      expect(
        hasMeaningfulSetterData(draft, contextSetterId: 'setter-1'),
        isFalse,
      );
    });

    test('the same setter id is meaningful once the context id differs', () {
      final draft = _audit('Setters', soSetterId: 'setter-1');
      expect(
        hasMeaningfulSetterCoreData(draft, contextSetterId: 'setter-2'),
        isTrue,
      );
      expect(
        hasMeaningfulSetterData(draft, contextSetterId: 'setter-2'),
        isTrue,
      );
      // Omitting contextSetterId entirely also makes it meaningful.
      expect(hasMeaningfulSetterCoreData(draft), isTrue);
    });
  });

  group('hasMeaningfulHatcherCoreData / hasMeaningfulHatcherData (parameterized)', () {
    test('a hatcher id equal to the context id is not meaningful', () {
      final draft = _audit('Hatchers', hoHatcherId: 'hatcher-1');
      expect(
        hasMeaningfulHatcherCoreData(draft, contextHatcherId: 'hatcher-1'),
        isFalse,
      );
      expect(
        hasMeaningfulHatcherData(draft, contextHatcherId: 'hatcher-1'),
        isFalse,
      );
    });

    test('the same hatcher id is meaningful once the context id differs', () {
      final draft = _audit('Hatchers', hoHatcherId: 'hatcher-1');
      expect(
        hasMeaningfulHatcherCoreData(draft, contextHatcherId: 'hatcher-2'),
        isTrue,
      );
      expect(
        hasMeaningfulHatcherData(draft, contextHatcherId: 'hatcher-2'),
        isTrue,
      );
    });
  });

  group(
    'hasMeaningfulChickWeightData / hasMeaningfulChickCoreData / hasMeaningfulChickData (parameterized)',
    () {
      test('an otherwise-blank chick draft is not meaningful', () {
        final blank = _audit('Chicks');
        expect(
          hasMeaningfulChickWeightData(
            blank,
            hasAnyMeaningfulChickWeightSample: false,
          ),
          isFalse,
        );
        expect(
          hasMeaningfulChickCoreData(
            blank,
            hasAnyMeaningfulChickWeightSample: false,
          ),
          isFalse,
        );
        expect(
          hasMeaningfulChickData(
            blank,
            hasAnyMeaningfulChickWeightSample: false,
          ),
          isFalse,
        );
      });

      test(
        'hasAnyMeaningfulChickWeightSample=true alone flips all three to true',
        () {
          final blank = _audit('Chicks');
          expect(
            hasMeaningfulChickWeightData(
              blank,
              hasAnyMeaningfulChickWeightSample: true,
            ),
            isTrue,
          );
          expect(
            hasMeaningfulChickCoreData(
              blank,
              hasAnyMeaningfulChickWeightSample: true,
            ),
            isTrue,
          );
          expect(
            hasMeaningfulChickData(
              blank,
              hasAnyMeaningfulChickWeightSample: true,
            ),
            isTrue,
          );
        },
      );
    },
  );

  group('hasAnyMeaningfulStationData / hasCoreStationData', () {
    test('a blank draft has no meaningful or core station data, for every audit type', () {
      for (final auditType in [
        'Egg',
        'Chicks',
        'Hatch Analysis & Egg Breakouts',
        'Setters',
        'Hatchers',
      ]) {
        final blank = _audit(auditType);
        expect(
          hasAnyMeaningfulStationData(
            blank,
            hasAnyMeaningfulChickWeightSample: false,
          ),
          isFalse,
          reason: '$auditType should have no meaningful station data',
        );
        expect(
          hasCoreStationData(
            blank,
            hasAnyMeaningfulChickWeightSample: false,
          ),
          isFalse,
          reason: '$auditType should have no core station data',
        );
      }
    });

    test('an unknown audit type always resolves to false', () {
      final draft = _audit('Something Else', notes: 'has notes');
      expect(
        hasAnyMeaningfulStationData(
          draft,
          hasAnyMeaningfulChickWeightSample: false,
        ),
        isFalse,
      );
    });

    test('a populated Egg draft is meaningful but not necessarily core', () {
      final draft = _audit('Egg', esTurningTimes: 4);
      expect(
        hasAnyMeaningfulStationData(
          draft,
          hasAnyMeaningfulChickWeightSample: false,
        ),
        isTrue,
      );
      expect(
        hasCoreStationData(draft, hasAnyMeaningfulChickWeightSample: false),
        isFalse,
      );
    });
  });
}
