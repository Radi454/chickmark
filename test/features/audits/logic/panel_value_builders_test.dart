import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/features/audits/logic/breakout_value_builders.dart';
import 'package:hatchaudit/features/audits/logic/panel_value_builders.dart';

/// Minimal `AuditModel` builder for these tests: only the fields required by
/// the constructor plus whichever optional fields a given test cares about.
/// Mirrors the pattern used in `audit_meaningful_data_test.dart`.
AuditModel _audit(
  String auditType, {
  // Egg storage
  int? esEggStorageDays,
  String? esEstReadingsJson,
  double? esEstAvg,
  double? esEstCv,
  int? esTurningTimes,
  String? esUvTrays,
  String? esTraySpacing,
  String? esCoolerProximity,
  bool? esCondensation,
  // Egg quality
  int? esEggQualityStorageDays,
  int? esUvSampleSize,
  String? esEggWeights,
  int? esEggSampleSize,
  double? esEggAvgWeight,
  double? esEggUniformityPct,
  double? esEggCvPct,
  int? esEggBmkAge,
  double? esEggBmkWeight,
  // Chicks: pasgar
  int? pasgarSampleSize,
  int? pasgarReflexes,
  int? pasgarBeak,
  int? pasgarNavel,
  int? pasgarBelly,
  int? pasgarLeg,
  int? pasgarFeatherDev,
  double? pasgarFinalScore,
  // Chicks: yfbm / cvt
  String? yfbmPhoto,
  String? yfbmEntries,
  double? yfbmAvgPct,
  double? yfbmCvPct,
  String? cvtReadingsJson,
  int? cvtSampleSize,
  double? cvtAvg,
  double? cvtCvPct,
  // Chicks: post-mortem
  int? pmSampleSize,
  String? pmCollectionPoint,
  int? pmOmphalitisCount,
  String? pmOmphalitisSeverity,
  // Chicks: culled chicks
  int? culledChicksTotalEggSet,
  String? culledChicksAnalysisJson,
  // Chick weights
  String? chickWeights,
  int? chickSampleSize,
  double? chickAvgWeight,
  double? chickUniformityPct,
  double? chickCvPct,
  int? chickBmkAge,
  double? chickBmkWeight,
  // Hatch analysis / egg breakout
  String? ebBreakoutType,
  // Setters / Hatchers
  String? soSetterId,
  String? hoHatcherId,
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
    esEggStorageDays: esEggStorageDays,
    esEstReadingsJson: esEstReadingsJson,
    esEstAvg: esEstAvg,
    esEstCv: esEstCv,
    esTurningTimes: esTurningTimes,
    esUvTrays: esUvTrays,
    esTraySpacing: esTraySpacing,
    esCoolerProximity: esCoolerProximity,
    esCondensation: esCondensation,
    esEggQualityStorageDays: esEggQualityStorageDays,
    esUvSampleSize: esUvSampleSize,
    esEggWeights: esEggWeights,
    esEggSampleSize: esEggSampleSize,
    esEggAvgWeight: esEggAvgWeight,
    esEggUniformityPct: esEggUniformityPct,
    esEggCvPct: esEggCvPct,
    esEggBmkAge: esEggBmkAge,
    esEggBmkWeight: esEggBmkWeight,
    pasgarSampleSize: pasgarSampleSize,
    pasgarReflexes: pasgarReflexes,
    pasgarBeak: pasgarBeak,
    pasgarNavel: pasgarNavel,
    pasgarBelly: pasgarBelly,
    pasgarLeg: pasgarLeg,
    pasgarFeatherDev: pasgarFeatherDev,
    pasgarFinalScore: pasgarFinalScore,
    yfbmPhoto: yfbmPhoto,
    yfbmEntries: yfbmEntries,
    yfbmAvgPct: yfbmAvgPct,
    yfbmCvPct: yfbmCvPct,
    cvtReadingsJson: cvtReadingsJson,
    cvtSampleSize: cvtSampleSize,
    cvtAvg: cvtAvg,
    cvtCvPct: cvtCvPct,
    pmSampleSize: pmSampleSize,
    pmCollectionPoint: pmCollectionPoint,
    pmOmphalitisCount: pmOmphalitisCount,
    pmOmphalitisSeverity: pmOmphalitisSeverity,
    culledChicksTotalEggSet: culledChicksTotalEggSet,
    culledChicksAnalysisJson: culledChicksAnalysisJson,
    chickWeights: chickWeights,
    chickSampleSize: chickSampleSize,
    chickAvgWeight: chickAvgWeight,
    chickUniformityPct: chickUniformityPct,
    chickCvPct: chickCvPct,
    chickBmkAge: chickBmkAge,
    chickBmkWeight: chickBmkWeight,
    ebBreakoutType: ebBreakoutType,
    soSetterId: soSetterId,
    hoHatcherId: hoHatcherId,
  );
}

/// Column names declared for [tableName] in the real panel schema
/// (`database/panel_sample_schema.dart`), stripped of their SQL type suffix.
List<String> _schemaColumns(String tableName) {
  return PanelSampleSchema.byTable(tableName).measurementColumns
      .map((definition) => definition.trim().split(RegExp(r'\s+')).first)
      .toList();
}

StationSampleModel _sample({
  required String resultSummaryJson,
  String sampleMode = StationSampleModel.sampleModePooled,
}) {
  return StationSampleModel(
    id: 'sample-1',
    auditSessionId: 'session-1',
    stationType: 'Chicks',
    sectorType: StationSampleModel.sectorChickWeights,
    sampleKind: StationSampleModel.sampleKindPooled,
    sampleMode: sampleMode,
    sampleIndex: 0,
    sampleLabel: 'Sample 1',
    sampleType: StationSampleModel.sampleTypeDefault,
    resultSummaryJson: resultSummaryJson,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('panelTablesForDraft', () {
    test('an Egg draft saves to egg_storage and egg_quality', () {
      expect(panelTablesForDraft(_audit('Egg')), [
        'egg_storage',
        'egg_quality',
      ]);
    });

    test('a Chicks draft saves to chick_quality only', () {
      expect(panelTablesForDraft(_audit('Chicks')), ['chick_quality']);
    });

    test('a Setters draft saves to setter_optimizing only', () {
      expect(panelTablesForDraft(_audit('Setters')), ['setter_optimizing']);
    });

    test('a Hatchers draft saves to hatcher_optimizing only', () {
      expect(panelTablesForDraft(_audit('Hatchers')), ['hatcher_optimizing']);
    });

    test('an unknown audit type saves to no tables', () {
      expect(panelTablesForDraft(_audit('Something Else')), isEmpty);
    });
  });

  group('panelValuesForDraft', () {
    test('egg_storage emits every schema measurement column', () {
      final draft = _audit(
        'Egg',
        esEggStorageDays: 5,
        esEstReadingsJson: '[68,69]',
        esEstAvg: 68.5,
        esEstCv: 1.2,
        esTurningTimes: 4,
        esTraySpacing: '2 inches',
        esCoolerProximity: 'near',
        esCondensation: true,
      );
      final values = panelValuesForDraft(
        'egg_storage',
        draft,
        flockAgeWeeks: null,
        flockEntryDate: null,
      );

      for (final column in _schemaColumns('egg_storage')) {
        expect(
          values.containsKey(column),
          isTrue,
          reason: 'missing schema column $column',
        );
      }
      expect(values['estReadingsJson'], '[68,69]');
      expect(values['estAvg'], 68.5);
      expect(values['turningTimes'], 4);
      expect(values['condensationPresent'], 1);
    });

    test('chick_quality emits every schema measurement column', () {
      final draft = _audit(
        'Chicks',
        pasgarSampleSize: 40,
        pasgarReflexes: 2,
        pasgarFinalScore: 9.5,
        yfbmEntries: '[{"pct":1.0}]',
        yfbmAvgPct: 2.5,
        cvtReadingsJson: '[100,101]',
        cvtSampleSize: 2,
        pmSampleSize: 40,
        pmOmphalitisCount: 1,
        pmOmphalitisSeverity: 'mild',
      );
      final values = panelValuesForDraft(
        'chick_quality',
        draft,
        flockAgeWeeks: null,
        flockEntryDate: null,
      );

      for (final column in _schemaColumns('chick_quality')) {
        expect(
          values.containsKey(column),
          isTrue,
          reason: 'missing schema column $column',
        );
      }
      expect(values['pasgarSampleSize'], 40);
      expect(values['pasgarReflexesCount'], 2);
      expect(values['pasgarReflexesPct'], 5.0);
      expect(values['pmOmphalitisCount'], 1);
      expect(values['pmOmphalitisSeverity'], 'mild');
      // No culled-chicks JSON was supplied, so the derived summary is empty.
      expect(values['culledChicksAnalysisJson'], isNull);
      expect(values['culledChicksAffectedPct'], 0.0);
    });

    test(
      'fresh/candled/residue breakout tables delegate to the matching '
      'breakout_value_builders function with flockAgeWeeks/flockEntryDate '
      'threaded through',
      () {
        const flockAgeWeeks = 5;
        final flockEntryDate = DateTime(2025, 12, 1);

        final freshDraft = _audit(
          'Hatch Analysis & Egg Breakouts',
          ebBreakoutType: 'fresh',
        );
        expect(
          panelValuesForDraft(
            'fresh_egg_breakout',
            freshDraft,
            flockAgeWeeks: flockAgeWeeks,
            flockEntryDate: flockEntryDate,
          ),
          freshBreakoutValues(
            freshDraft,
            flockAgeWeeks: flockAgeWeeks,
            flockEntryDate: flockEntryDate,
          ),
        );

        final candledDraft = _audit(
          'Hatch Analysis & Egg Breakouts',
          ebBreakoutType: 'candled',
        );
        expect(
          panelValuesForDraft(
            'candled_egg_breakout',
            candledDraft,
            flockAgeWeeks: flockAgeWeeks,
            flockEntryDate: flockEntryDate,
          ),
          candledBreakoutValues(
            candledDraft,
            flockAgeWeeks: flockAgeWeeks,
            flockEntryDate: flockEntryDate,
          ),
        );

        final residueDraft = _audit(
          'Hatch Analysis & Egg Breakouts',
          ebBreakoutType: 'residue',
        );
        expect(
          panelValuesForDraft(
            'residue_breakout',
            residueDraft,
            flockAgeWeeks: flockAgeWeeks,
            flockEntryDate: flockEntryDate,
          ),
          residueBreakoutValues(
            residueDraft,
            flockAgeWeeks: flockAgeWeeks,
            flockEntryDate: flockEntryDate,
          ),
        );
      },
    );

    test('an unknown table resolves to an empty map', () {
      final values = panelValuesForDraft(
        'not_a_real_table',
        _audit('Egg'),
        flockAgeWeeks: null,
        flockEntryDate: null,
      );
      expect(values, isEmpty);
    });
  });

  group('eggStorageValues / eggQualityValues', () {
    test('eggStorageValues computes upside-down percentage from UV trays', () {
      final draft = _audit(
        'Egg',
        esUvTrays: '[{"totalEggs":100,"upsideDown":10}]',
      );
      final values = eggStorageValues(draft);
      expect(values['upsideDownCount'], 10);
      expect(values['upsideDownPct'], 10.0);
    });

    test('eggQualityValues computes affected percentage from UV trays', () {
      final draft = _audit(
        'Egg',
        esUvTrays: '[{"totalEggs":100,"cuticleDamage":5,"washed":3,"dirty":2}]',
      );
      final values = eggQualityValues(draft);
      expect(values['uvTrayEggCount'], 100);
      expect(values['uvAffectedCount'], 10);
      expect(values['uvAffectedPct'], 10.0);
    });
  });

  group('chickWeightValues / chickWeightValuesForSample', () {
    test('chickWeightValues reads straight off the draft', () {
      final draft = _audit(
        'Chicks',
        chickWeights: '[40.0, 42.0]',
        chickSampleSize: 2,
        chickAvgWeight: 41.0,
      );
      final values = chickWeightValues(draft);
      expect(values['weightsJson'], '[40.0, 42.0]');
      expect(values['sampleSize'], 2);
      expect(values['avgWeight'], 41.0);
    });

    test('a pooled sample with no summary falls back to the draft', () {
      final draft = _audit('Chicks', chickSampleSize: 7, chickAvgWeight: 41.0);
      final sample = _sample(resultSummaryJson: '');
      final values = chickWeightValuesForSample(sample, fallback: draft);
      expect(values['sampleSize'], 7);
      expect(values['avgWeight'], 41.0);
    });

    test(
      'a comparison sample with no summary falls back to empty values',
      () {
        final draft = _audit(
          'Chicks',
          chickSampleSize: 7,
          chickBmkAge: 3,
          chickBmkWeight: 45.0,
        );
        final sample = _sample(
          resultSummaryJson: '',
          sampleMode: StationSampleModel.sampleModeComparison,
        );
        final values = chickWeightValuesForSample(sample, fallback: draft);
        expect(values['sampleSize'], isNull);
        expect(values['weightsJson'], isNull);
        // Benchmark fields still fall back to the draft.
        expect(values['bmkAgeWeeks'], 3);
        expect(values['bmkWeight'], 45.0);
      },
    );

    test('a decoded summary resolves weights and sample size', () {
      final draft = _audit('Chicks');
      final sample = _sample(
        resultSummaryJson:
            '{"chickWeights":[0,40.0,42.0],"chickAvgWeight":41.0,'
            '"chickUniformityPct":88.0,"chickCvPct":5.0}',
      );
      final values = chickWeightValuesForSample(sample, fallback: draft);
      expect(values['weightsJson'], '[0,40.0,42.0]');
      // Only positive weights count toward the sample size.
      expect(values['sampleSize'], 2);
      expect(values['avgWeight'], 41.0);
      expect(values['uniformityPct'], 88.0);
      expect(values['cvPct'], 5.0);
    });
  });

  group('emptyChickWeightValues', () {
    test('every measurement is null except the draft benchmark fields', () {
      final draft = _audit('Chicks', chickBmkAge: 3, chickBmkWeight: 45.0);
      final values = emptyChickWeightValues(draft);
      expect(values['weightsJson'], isNull);
      expect(values['sampleSize'], isNull);
      expect(values['bmkAgeWeeks'], 3);
      expect(values['bmkWeight'], 45.0);
    });
  });

  group('chickPmValues', () {
    test('reads the post-mortem fields straight off the draft', () {
      final draft = _audit(
        'Chicks',
        pmSampleSize: 40,
        pmOmphalitisCount: 1,
        pmOmphalitisSeverity: 'mild',
      );
      final values = chickPmValues(draft);
      expect(values['pmSampleSize'], 40);
      expect(values['pmOmphalitisCount'], 1);
      expect(values['pmOmphalitisSeverity'], 'mild');
    });
  });
}
