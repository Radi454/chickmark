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

    test('maps Chicks compare audit to batch comparison sample', () {
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
      expect(sample.comparisonType, StationSampleModel.comparisonTypeBatch);
      expect(
        sample.sampleType,
        StationSampleModel.sampleTypeChickQualityHatchedBatch,
      );
      expect(sample.sampleIndex, 2);
      expect(sample.sampleLabel, 'Sample 2');
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
  });
}
