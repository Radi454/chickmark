import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/agent/station_adapter.dart';
import 'package:hatchaudit/data/agent/station_registry.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/features/audits/logic/panel_row_to_draft.dart';
import 'package:hatchaudit/features/audits/logic/panel_value_builders.dart';
import 'package:hatchaudit/features/audits/models/culled_chicks_analysis.dart';

/// Safety net for the Chick Quality write/read mapping pair.
///
/// `chickQualityValues` / `chickWeightValues` (draft -> panel row) and
/// `mergePanelRowIntoAuditMap` (panel row -> draft map) are two hand-written
/// column lists that must stay exact inverses of each other. Nothing checked
/// that before this suite: a column renamed on one side only would silently
/// drop an auditor's data on the next reload. These tests lock the mapping as
/// it behaves today so a later refactor has something to fail against.

/// A defect id from the shipped culled-chicks catalogue, so the analysis JSON
/// the draft carries is one the codec can actually decode.
const _culledDefectId = 'navel_open_unhealed';
const _culledTotalEggSet = 12000;

/// Written by `chickQualityValues` but never read back by
/// `mergePanelRowIntoAuditMap`. All seven are derived aggregates the chick
/// screens recompute from the counts/entries they *do* read back, so losing
/// them on reload changes nothing the auditor sees. They exist as columns
/// purely so the dashboard can aggregate without re-deriving.
const _chickQualityWriteOnlyColumns = {
  'pasgarReflexesPct',
  'pasgarBeakPct',
  'pasgarNavelPct',
  'pasgarBellyPct',
  'pasgarLegPct',
  'pasgarFeatherDevPct',
  'yfbmEntryCount',
};

/// `chick_weights` has no derived-only columns: everything written comes back.
const _chickWeightsWriteOnlyColumns = <String>{};

/// The context columns the panel save coordinator puts on every panel row
/// alongside the measurement values (see `_panelRecordForSamples`). They are
/// included here so the row fed to the read side is shaped like a real one.
Map<String, Object?> _contextColumns(AuditModel draft) {
  return {
    'storagePeriodDays': storageDaysForDraft(draft),
    'bmkAgeWeeks': legacyBmkWeeksForDraft(draft),
  };
}

/// A chick draft with every persisted chick domain populated: Pasgar, YFBM,
/// CVT (both the readings JSON and the legacy basket triples), post-mortem,
/// culled-chicks analysis and chick weights.
AuditModel _fullChickDraft() {
  return AuditModel(
    id: 'audit-chicks-round-trip',
    auditType: 'Chicks',
    customerId: 'customer-1',
    flockId: 'flock-1',
    date: DateTime(2026, 8, 20),
    hatchNumber: 1,
    status: 'completed',
    createdBy: 'auditor-1',
    createdAt: DateTime(2026, 8, 20, 8),
    updatedAt: DateTime(2026, 8, 20, 9),
    sessionId: 'session-1',
    sampleMode: 'pool',
    // --- Pasgar ---
    pasgarSampleSize: 100,
    pasgarReflexes: 3,
    pasgarBeak: 4,
    pasgarNavel: 5,
    pasgarBelly: 6,
    pasgarLeg: 7,
    pasgarFeatherDev: 8,
    pasgarFinalScore: 9.25,
    // --- Chick weights ---
    chickStorageDays: 2,
    chickSampleSize: 50,
    chickWeights: '[41.0,42.5,43.25]',
    chickAvgWeight: 42.25,
    chickUniformityPct: 88.5,
    chickCvPct: 4.75,
    chickBmkAge: 34,
    chickBmkWeight: 42.0,
    // --- YFBM ---
    yfbmPhoto: 'photos/yfbm.jpg',
    yfbmEntries:
        '[{"chickWeight":42.0,"yolkWeight":4.2},'
        '{"chickWeight":43.0,"yolkWeight":4.4}]',
    yfbmAvgPct: 10.15,
    yfbmCvPct: 3.2,
    // --- CVT ---
    cvtReadingsJson: '{"unit":"F","readings":[103.1,103.4,103.9]}',
    cvtPhotosJson: '["photos/cvt-1.jpg","photos/cvt-2.jpg"]',
    cvtSampleSize: 3,
    cvtTopBasket: 'T-1',
    cvtTopTemp: 103.1,
    cvtTopPhoto: 'photos/cvt-top.jpg',
    cvtMiddleBasket: 'M-1',
    cvtMiddleTemp: 103.4,
    cvtMiddlePhoto: 'photos/cvt-middle.jpg',
    cvtBottomBasket: 'B-1',
    cvtBottomTemp: 103.9,
    cvtBottomPhoto: 'photos/cvt-bottom.jpg',
    cvtAvg: 103.47,
    cvtCvPct: 0.39,
    // --- Post-mortem (the seven lesion pairs that have columns) ---
    pmSampleSize: 20,
    pmCollectionPoint: 'Chick holding room',
    pmOmphalitisCount: 1,
    pmOmphalitisSeverity: 'mild',
    pmGaseousCecaCount: 2,
    pmGaseousCecaSeverity: 'moderate',
    pmGizzardErosionsCount: 3,
    pmGizzardErosionsSeverity: 'severe',
    pmAirSacCaseationsCount: 4,
    pmAirSacCaseationsSeverity: 'mild',
    pmUrolithiasisCount: 5,
    pmUrolithiasisSeverity: 'moderate',
    pmNephritisCount: 6,
    pmNephritisSeverity: 'severe',
    pmGeneralSepticemiaCount: 7,
    pmGeneralSepticemiaSeverity: 'mild',
    pmOtherLesionsJson: '[{"label":"Beak lesion","count":2}]',
    pmSuspectedCauseManual: 'Late transfer',
    pmPhotosJson: '["photos/pm-1.jpg"]',
    // --- Culled chicks analysis ---
    culledChicksTotalEggSet: _culledTotalEggSet,
    culledChicksAnalysisJson: CulledChicksAnalysisCodec.encodeCounts(const {
      _culledDefectId: 24,
    }, totalEggSet: _culledTotalEggSet),
  );
}

/// The draft map a reload rebuilds from the two chick panel rows.
Map<String, dynamic> _reloadedMap(AuditModel draft) {
  final map = <String, dynamic>{
    'id': draft.id,
    'auditType': draft.auditType,
    'customerId': draft.customerId,
    'flockId': draft.flockId,
    'date': draft.date.toIso8601String(),
    'hatchNumber': draft.hatchNumber,
    'status': draft.status,
    'createdBy': draft.createdBy,
    'createdAt': draft.createdAt.toIso8601String(),
    'updatedAt': draft.updatedAt.toIso8601String(),
    'sessionId': draft.sessionId,
    'sampleMode': draft.sampleMode,
  };
  mergePanelRowIntoAuditMap(map, 'chick_quality', {
    ..._contextColumns(draft),
    ...chickQualityValues(draft),
  });
  mergePanelRowIntoAuditMap(map, 'chick_weights', {
    ..._contextColumns(draft),
    ...chickWeightValues(draft),
  });
  return map;
}

/// Every `AuditModel` map key that belongs to a chick station.
bool _isChickKey(String key) {
  return key.startsWith('pasgar') ||
      key.startsWith('chick') ||
      key.startsWith('yfbm') ||
      key.startsWith('cvt') ||
      key.startsWith('pm_') ||
      key.startsWith('culledChicks');
}

/// The measurement columns of [table] that `mergePanelRowIntoAuditMap`
/// actually consumes, discovered by feeding one column at a time and seeing
/// whether anything lands in the draft map. Probing beats hand-listing: the
/// list stays right when either side of the mapping is edited.
Set<String> _columnsReadBack(String table) {
  final read = <String>{};
  for (final column in {
    ..._measurementColumnNames(table),
    // Context columns live on every panel table, and `chick_weights` writes
    // its benchmark age into one of them, so they belong in the probe.
    'storagePeriodDays',
    'bmkAgeWeeks',
  }) {
    final map = <String, dynamic>{};
    mergePanelRowIntoAuditMap(map, table, {column: 'probe'});
    if (map.isNotEmpty) read.add(column);
  }
  return read;
}

Set<String> _measurementColumnNames(String table) {
  return PanelSampleSchema.byTable(table).measurementColumns
      .map((definition) => definition.trim().split(RegExp(r'\s+')).first)
      .toSet();
}

void main() {
  group('chick draft -> panel rows -> draft round trip', () {
    late AuditModel draft;
    late AuditModel reloaded;

    setUp(() {
      draft = _fullChickDraft();
      reloaded = AuditModel.fromMap(_reloadedMap(draft));
    });

    test('every populated chick field survives the round trip', () {
      final before = draft.toMap();
      final after = reloaded.toMap();

      final mismatched = <String, String>{};
      for (final entry in before.entries) {
        if (!_isChickKey(entry.key) || entry.value == null) continue;
        if (after[entry.key] != entry.value) {
          mismatched[entry.key] =
              'wrote ${entry.value}, '
              'reloaded ${after[entry.key]}';
        }
      }

      // KNOWN GAP: `chickStorageDays`. The save side puts the value in the
      // panel row's `storagePeriodDays` context column, but the chick
      // branches of `mergePanelRowIntoAuditMap` never copy it back (the egg
      // and breakout branches do). Correct behaviour would be to copy
      // `storagePeriodDays` -> `chickStorageDays`, matching the egg branch's
      // `storagePeriodDays` -> `esEggStorageDays`. Locked as-is here so the
      // refactor has to decide deliberately rather than silently.
      expect(mismatched.keys, {'chickStorageDays'});
      expect(mismatched['chickStorageDays'], 'wrote 2, reloaded null');
    });

    test('chick_quality reload matches the draft field by field', () {
      expect(reloaded.pasgarSampleSize, draft.pasgarSampleSize);
      expect(reloaded.pasgarReflexes, draft.pasgarReflexes);
      expect(reloaded.pasgarBeak, draft.pasgarBeak);
      expect(reloaded.pasgarNavel, draft.pasgarNavel);
      expect(reloaded.pasgarBelly, draft.pasgarBelly);
      expect(reloaded.pasgarLeg, draft.pasgarLeg);
      expect(reloaded.pasgarFeatherDev, draft.pasgarFeatherDev);
      expect(reloaded.pasgarFinalScore, draft.pasgarFinalScore);

      expect(reloaded.yfbmPhoto, draft.yfbmPhoto);
      expect(reloaded.yfbmEntries, draft.yfbmEntries);
      expect(reloaded.yfbmAvgPct, draft.yfbmAvgPct);
      expect(reloaded.yfbmCvPct, draft.yfbmCvPct);

      expect(reloaded.cvtReadingsJson, draft.cvtReadingsJson);
      expect(reloaded.cvtPhotosJson, draft.cvtPhotosJson);
      expect(reloaded.cvtSampleSize, draft.cvtSampleSize);
      expect(reloaded.cvtTopBasket, draft.cvtTopBasket);
      expect(reloaded.cvtTopTemp, draft.cvtTopTemp);
      expect(reloaded.cvtTopPhoto, draft.cvtTopPhoto);
      expect(reloaded.cvtMiddleBasket, draft.cvtMiddleBasket);
      expect(reloaded.cvtMiddleTemp, draft.cvtMiddleTemp);
      expect(reloaded.cvtMiddlePhoto, draft.cvtMiddlePhoto);
      expect(reloaded.cvtBottomBasket, draft.cvtBottomBasket);
      expect(reloaded.cvtBottomTemp, draft.cvtBottomTemp);
      expect(reloaded.cvtBottomPhoto, draft.cvtBottomPhoto);
      expect(reloaded.cvtAvg, draft.cvtAvg);
      expect(reloaded.cvtCvPct, draft.cvtCvPct);

      expect(reloaded.pmSampleSize, draft.pmSampleSize);
      expect(reloaded.pmCollectionPoint, draft.pmCollectionPoint);
      expect(reloaded.pmOmphalitisCount, draft.pmOmphalitisCount);
      expect(reloaded.pmOmphalitisSeverity, draft.pmOmphalitisSeverity);
      expect(reloaded.pmGaseousCecaCount, draft.pmGaseousCecaCount);
      expect(reloaded.pmGaseousCecaSeverity, draft.pmGaseousCecaSeverity);
      expect(reloaded.pmGizzardErosionsCount, draft.pmGizzardErosionsCount);
      expect(
        reloaded.pmGizzardErosionsSeverity,
        draft.pmGizzardErosionsSeverity,
      );
      expect(reloaded.pmAirSacCaseationsCount, draft.pmAirSacCaseationsCount);
      expect(
        reloaded.pmAirSacCaseationsSeverity,
        draft.pmAirSacCaseationsSeverity,
      );
      expect(reloaded.pmUrolithiasisCount, draft.pmUrolithiasisCount);
      expect(reloaded.pmUrolithiasisSeverity, draft.pmUrolithiasisSeverity);
      expect(reloaded.pmNephritisCount, draft.pmNephritisCount);
      expect(reloaded.pmNephritisSeverity, draft.pmNephritisSeverity);
      expect(reloaded.pmGeneralSepticemiaCount, draft.pmGeneralSepticemiaCount);
      expect(
        reloaded.pmGeneralSepticemiaSeverity,
        draft.pmGeneralSepticemiaSeverity,
      );
      expect(reloaded.pmOtherLesionsJson, draft.pmOtherLesionsJson);
      expect(reloaded.pmSuspectedCauseManual, draft.pmSuspectedCauseManual);
      expect(reloaded.pmPhotosJson, draft.pmPhotosJson);

      expect(reloaded.culledChicksTotalEggSet, draft.culledChicksTotalEggSet);
      expect(reloaded.culledChicksAnalysisJson, draft.culledChicksAnalysisJson);
      // Derived on write from the analysis JSON, so compare against what the
      // summary produces rather than against a null draft field.
      final summary = CulledChicksAnalysisSummary.fromJson(
        draft.culledChicksAnalysisJson,
        totalEggSet: draft.culledChicksTotalEggSet,
      );
      expect(reloaded.culledChicksAffectedPct, summary.affectedPct);
      expect(reloaded.culledChicksTopCategory, summary.topCategory);
      expect(reloaded.culledChicksTopSubtype, summary.topSubtype);
    });

    test('chick_weights reload matches the draft field by field', () {
      expect(reloaded.chickWeights, draft.chickWeights);
      expect(reloaded.chickSampleSize, draft.chickSampleSize);
      expect(reloaded.chickAvgWeight, draft.chickAvgWeight);
      expect(reloaded.chickUniformityPct, draft.chickUniformityPct);
      expect(reloaded.chickCvPct, draft.chickCvPct);
      expect(reloaded.chickBmkAge, draft.chickBmkAge);
      expect(reloaded.chickBmkWeight, draft.chickBmkWeight);
    });
  });

  group('write columns and read columns agree', () {
    test('generated registry reverse mappings cover every Chick field', () {
      for (final schema in AgentStationRegistry.schemas.where(
        (schema) => schema.schemaKey.startsWith('chicks.'),
      )) {
        final row = <String, Object?>{
          for (final field in schema.fields)
            field.persistence['localColumn']! as String: switch (field.type) {
              'integer' => 1,
              'number' => 1.5,
              'string' => 'value',
              'boolean' => 1,
              'number_list' => '[1.0,2.0]',
              'object_list' => '[{"value":1}]',
              _ => null,
            },
        };
        final decoded = AgentStationAdapter.fieldValuesFromLocalRow(
          schema,
          row,
        );
        for (final field in schema.fields) {
          expect(
            decoded,
            contains(field.fieldKey),
            reason: '${schema.schemaKey}.${field.fieldKey}',
          );
        }
      }
    });

    test('generated registry reverse mappings also decode calculations', () {
      final schema = AgentStationRegistry.schemas.singleWhere(
        (schema) => schema.schemaKey == 'chicks.pasgar',
      );
      final decoded = AgentStationAdapter.fieldValuesFromLocalRow(schema, {
        'pasgarFinalScore': 9.5,
      });

      expect(decoded['pasgarFinalScore'], 9.5);
    });

    test('every chick_quality column written is read back', () {
      final written = chickQualityValues(_fullChickDraft()).keys.toSet();
      final read = _columnsReadBack('chick_quality');

      expect(
        written.difference(read),
        _chickQualityWriteOnlyColumns,
        reason: 'a newly write-only column means data is lost on reload',
      );
      // No stale allowlist entries: everything excused must still be written.
      expect(_chickQualityWriteOnlyColumns.difference(written), isEmpty);
      // Nothing is read from a column the writer never fills.
      expect(read.difference(written), isEmpty);
      // The writer covers the whole table, minus nothing.
      expect(
        _measurementColumnNames('chick_quality').difference(written),
        isEmpty,
      );
    });

    test('every chick_weights column written is read back', () {
      final written = chickWeightValues(_fullChickDraft()).keys.toSet();
      final read = _columnsReadBack('chick_weights');

      expect(written.difference(read), _chickWeightsWriteOnlyColumns);
      expect(read.difference(written), isEmpty);
      // `bmkAgeWeeks` is a shared panel context column rather than a
      // `chick_weights` measurement column, so it is written and read but is
      // not part of the table's measurement column list.
      expect(written.difference(_measurementColumnNames('chick_weights')), {
        'bmkAgeWeeks',
      });
      expect(
        _measurementColumnNames('chick_weights').difference(written),
        isEmpty,
      );
    });
  });
}
