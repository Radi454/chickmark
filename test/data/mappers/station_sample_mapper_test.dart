import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/mappers/station_sample_mapper.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/models/sample_mode.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';

import '../../features/audits/session_test_helpers.dart';

void main() {
  group('StationSampleMapper', () {
    final session = AuditSessionModel(
      id: 'session-1',
      customerId: 'customer-1',
      flockId: 'flock-1',
      hatcheryId: 'hatchery-1',
      date: DateTime(2026, 4, 27),
      breed: 'Ross 308',
      flockAgeWeeks: 42,
      createdAt: DateTime(2026, 4, 27),
      updatedAt: DateTime(2026, 4, 27),
    );

    StationSampleModel sampleForPatch({
      required String stationType,
      String? sectorType,
      String? sampleType,
      String? breakoutType,
      int? storageDays = 5,
      int? incubationDay,
    }) {
      return StationSampleModel(
        id: 'sample-$stationType',
        auditSessionId: 'session-1',
        legacyAuditId: 'audit-1',
        stationType: stationType,
        sectorType: sectorType,
        sampleKind: StationSampleModel.sampleKindBatch,
        sampleMode: StationSampleModel.sampleModeComparison,
        comparisonType: StationSampleModel.comparisonTypeBatch,
        sampleIndex: 1,
        sampleLabel: 'Sample 1',
        hatchNo: '1',
        batchNo: '1',
        sampleType: sampleType,
        breakoutType: breakoutType,
        storageDays: storageDays,
        incubationDay: incubationDay,
        calculatedBmkAgeDays: 280,
        createdAt: DateTime(2026, 4, 27),
        updatedAt: DateTime(2026, 4, 27),
      );
    }

    void expectAbsent(Map<String, dynamic> patch, Iterable<String> keys) {
      for (final key in keys) {
        expect(
          patch.containsKey(key),
          isFalse,
          reason: '$key must be unchanged',
        );
      }
    }

    test('maps Chicks compare audit to machine comparison sample', () {
      final row = makeStationAudit(
        id: 'audit-1',
        auditType: 'Chicks',
        hatchNumber: 2,
        setterId: 'S-1',
        hatcherId: 'H-1',
        sampleMode: SampleMode.compare,
        compareGroupKey: 'group-1',
        chickAvgWeight: 42.5,
      ).toMap()..['chickBmkAge'] = 40;
      final audit = AuditModel.fromMap(row);

      final sample = StationSampleMapper.fromLegacyAudit(
        audit,
        session: session,
      );

      expect(sample.auditSessionId, 'session-1');
      expect(sample.legacyAuditId, 'audit-1');
      expect(sample.stationType, 'chicks');
      expect(sample.sampleMode, StationSampleModel.sampleModeComparison);
      expect(sample.comparisonType, StationSampleModel.comparisonTypeMachine);
      expect(
        sample.sampleType,
        StationSampleModel.sampleTypeChickQualityHatchedBatch,
      );
      expect(sample.sampleIndex, 2);
      expect(sample.sampleLabel, 'S1H1');
      expect(sample.groupLabel, 'Machine comparison');
      expect(sample.hatchNo, '2');
      expect(sample.batchNo, '2');
      expect(sample.houseNo, isNull);
      expect(sample.houseLabel, isNull);
      expect(sample.setterNo, 'S-1');
      expect(sample.hatcherNo, 'H-1');
      expect(sample.calculatedBmkAgeDays, 280);
      expect(sample.resultSummaryJson, contains('chickAvgWeight'));
    });

    test(
      'maps Hatch Analysis & Egg Breakouts breakout type without tray-global fields',
      () {
        final row = makeHatchAnalysisAudit(id: 'audit-2').toMap()
          ..['sessionId'] = 'session-1'
          ..['ebBreakoutType'] = 'Candled 10d'
          ..['ebBmkAge'] = 39
          ..['ebTrayBreakoutJson'] =
              '[{"tray_no":"T1","tray_level":"top","tray_depth":"front"}]';
        final audit = AuditModel.fromMap(row);

        final sample = StationSampleMapper.fromLegacyAudit(audit);
        final map = sample.toMap();

        expect(sample.stationType, 'hatch_analysis_egg_breakouts');
        expect(
          sample.sampleType,
          StationSampleModel.sampleTypeBreakoutCandled10d,
        );
        expect(sample.breakoutType, StationSampleModel.breakoutTypeCandled10d);
        expect(sample.calculatedBmkAgeDays, 273);
        expect(map.containsKey('trayNo'), isFalse);
        expect(map.containsKey('trayLevel'), isFalse);
        expect(map.containsKey('trayDepth'), isFalse);
      },
    );

    test('defaults missing legacy storage days to zero', () {
      final audit = makeStationAudit(
        id: 'audit-storage-blank',
        auditType: 'Egg',
      );

      final sample = StationSampleMapper.fromLegacyAudit(
        audit,
        session: session,
      );

      expect(sample.storageDays, 0);
      expect(sample.calculatedBmkAgeDays, 273);
    });

    test('builds legacy audit patch from sample metadata', () {
      final sample = StationSampleModel(
        id: 'sample-1',
        auditSessionId: 'session-1',
        legacyAuditId: 'audit-1',
        stationType: 'hatch_analysis_egg_breakouts',
        sampleMode: StationSampleModel.sampleModeComparison,
        comparisonType: StationSampleModel.comparisonTypeBatch,
        sampleIndex: 3,
        sampleLabel: 'Sample 3',
        hatchNo: '3',
        batchNo: '3',
        houseNo: 'HSE-03',
        houseLabel: 'South House',
        setterNo: 'S-3',
        hatcherNo: 'H-3',
        storageDays: 4,
        calculatedBmkAgeDays: 281,
        createdAt: DateTime(2026, 4, 27),
        updatedAt: DateTime(2026, 4, 27),
      );

      final patch = StationSampleMapper.legacyAuditPatchForSample(sample);

      expect(patch['sessionId'], 'session-1');
      expect(patch['hatchNumber'], 3);
      expect(patch['setterId'], 'S-3');
      expect(patch['hatcherId'], 'H-3');
      expect(patch['haStorageDays'], 4);
      expect(patch['haBmkAge'], 41);
      expect(patch.containsKey('houseNo'), isFalse);
      expect(patch.containsKey('houseLabel'), isFalse);
      expect(patch.containsKey('trayNo'), isFalse);
    });

    test('legacy patch writes egg quality storage to egg quality fields', () {
      final patch = StationSampleMapper.legacyAuditPatchForSample(
        sampleForPatch(
          stationType: 'egg',
          sectorType: StationSampleModel.sectorEggQuality,
        ),
      );

      expect(patch['esEggQualityStorageDays'], 5);
      expect(patch['esEggBmkAge'], 40);
      expectAbsent(patch, const [
        'esEggStorageDays',
        'chickStorageDays',
        'haStorageDays',
        'ebStorageDays',
        'chickBmkAge',
        'haBmkAge',
        'ebBmkAge',
      ]);
    });

    test('legacy patch writes chick quality metadata only to chick fields', () {
      final patch = StationSampleMapper.legacyAuditPatchForSample(
        sampleForPatch(
          stationType: 'chicks',
          sectorType: StationSampleModel.sectorChickQuality,
        ),
      );

      expect(patch['chickStorageDays'], 5);
      expect(patch['chickBmkAge'], 40);
      expectAbsent(patch, const [
        'esEggStorageDays',
        'haStorageDays',
        'ebStorageDays',
        'esEggBmkAge',
        'haBmkAge',
        'ebBmkAge',
      ]);
    });

    test('legacy patch writes hatch analysis metadata only to HA fields', () {
      final patch = StationSampleMapper.legacyAuditPatchForSample(
        sampleForPatch(
          stationType: 'hatch_analysis_egg_breakouts',
          sectorType: StationSampleModel.sectorHatchBreakout,
        ),
      );

      expect(patch['haStorageDays'], 5);
      expect(patch['haBmkAge'], 40);
      expectAbsent(patch, const [
        'esEggStorageDays',
        'chickStorageDays',
        'ebStorageDays',
        'esEggBmkAge',
        'chickBmkAge',
        'ebBmkAge',
      ]);
    });

    test(
      'legacy patch writes egg breakout metadata only to breakout fields',
      () {
        final patch = StationSampleMapper.legacyAuditPatchForSample(
          sampleForPatch(
            stationType: 'hatch_analysis_egg_breakouts',
            sectorType: StationSampleModel.sectorHatchBreakout,
            sampleType: StationSampleModel.sampleTypeBreakoutResidue21d,
            breakoutType: StationSampleModel.breakoutTypeResidue21d,
          ),
        );

        expect(patch['ebStorageDays'], 5);
        expect(patch['ebBmkAge'], 40);
        expectAbsent(patch, const [
          'esEggStorageDays',
          'chickStorageDays',
          'haStorageDays',
          'esEggBmkAge',
          'chickBmkAge',
          'haBmkAge',
        ]);
      },
    );

    test('legacy patch writes setter incubation only to setter fields', () {
      final patch = StationSampleMapper.legacyAuditPatchForSample(
        sampleForPatch(
          stationType: 'setters',
          sectorType: StationSampleModel.sectorSetterOptimizing,
          storageDays: null,
          incubationDay: 12,
        ),
      );

      expect(patch['soIncubationAge'], 12);
      expectAbsent(patch, const [
        'hoIncubationAge',
        'esEggStorageDays',
        'chickStorageDays',
        'haStorageDays',
        'ebStorageDays',
        'esEggBmkAge',
        'chickBmkAge',
        'haBmkAge',
        'ebBmkAge',
      ]);
    });

    test('legacy patch writes hatcher incubation only to hatcher fields', () {
      final patch = StationSampleMapper.legacyAuditPatchForSample(
        sampleForPatch(
          stationType: 'hatchers',
          sectorType: StationSampleModel.sectorHatcherOptimizing,
          storageDays: null,
          incubationDay: 18,
        ),
      );

      expect(patch['hoIncubationAge'], 18);
      expectAbsent(patch, const [
        'soIncubationAge',
        'esEggStorageDays',
        'chickStorageDays',
        'haStorageDays',
        'ebStorageDays',
        'esEggBmkAge',
        'chickBmkAge',
        'haBmkAge',
        'ebBmkAge',
      ]);
    });
  });
}
