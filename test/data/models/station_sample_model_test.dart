import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';

void main() {
  group('StationSampleModel', () {
    final createdAt = DateTime(2026, 4, 27, 8);
    final updatedAt = DateTime(2026, 4, 27, 9);

    test('round-trips full sample metadata', () {
      final sample = StationSampleModel(
        id: 'sample-1',
        auditSessionId: 'session-1',
        legacyAuditId: 'audit-1',
        stationType: 'chicks',
        sectorType: StationSampleModel.sectorChickWeights,
        sampleKind: StationSampleModel.sampleKindHouse,
        sampleMode: StationSampleModel.sampleModeComparison,
        comparisonType: StationSampleModel.comparisonTypeBatch,
        sampleIndex: 2,
        sampleLabel: 'Sample 2',
        sampleType: StationSampleModel.sampleTypeChickQualityHatchedBatch,
        breakoutType: StationSampleModel.breakoutTypeResidue21d,
        groupKey: 'group-1',
        groupLabel: 'Batch comparison',
        batchNo: 'B-02',
        houseNo: 'HSE-01',
        houseLabel: 'North House',
        hatchNo: 'H-02',
        eggProductionDate: DateTime(2026, 4, 1),
        settingDate: DateTime(2026, 4, 3),
        hatchDate: DateTime(2026, 4, 24),
        storageDays: 2,
        incubationDay: 21,
        setterNo: 'S-1',
        hatcherNo: 'H-1',
        calculatedBmkAgeDays: 280,
        benchmarkBreed: 'Ross 308',
        benchmarkAgeDays: 280,
        benchmarkSource: 'local',
        benchmarkSnapshotJson: '{"ageWeek":40}',
        resultSummaryJson: '{"avgWeight":42.5}',
        notes: 'Sample note',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final restored = StationSampleModel.fromMap(sample.toMap());

      expect(restored.id, sample.id);
      expect(restored.auditSessionId, sample.auditSessionId);
      expect(restored.legacyAuditId, sample.legacyAuditId);
      expect(restored.stationType, sample.stationType);
      expect(restored.sectorType, StationSampleModel.sectorChickWeights);
      expect(restored.sampleKind, StationSampleModel.sampleKindHouse);
      expect(restored.sampleMode, sample.sampleMode);
      expect(restored.comparisonType, sample.comparisonType);
      expect(restored.sampleIndex, sample.sampleIndex);
      expect(restored.sampleLabel, sample.sampleLabel);
      expect(restored.sampleType, sample.sampleType);
      expect(restored.breakoutType, sample.breakoutType);
      expect(restored.batchNo, sample.batchNo);
      expect(restored.houseNo, sample.houseNo);
      expect(restored.houseLabel, sample.houseLabel);
      expect(restored.hatchNo, sample.hatchNo);
      expect(restored.eggProductionDate, DateTime(2026, 4, 1));
      expect(restored.settingDate, DateTime(2026, 4, 3));
      expect(restored.hatchDate, DateTime(2026, 4, 24));
      expect(restored.setterNo, 'S-1');
      expect(restored.hatcherNo, 'H-1');
      expect(restored.calculatedBmkAgeDays, 280);
      expect(restored.resultSummaryJson, '{"avgWeight":42.5}');
    });

    test('uses safe defaults for minimal sample rows', () {
      final sample = StationSampleModel(
        id: 'sample-1',
        auditSessionId: 'session-1',
        stationType: 'egg',
        sampleIndex: 1,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final map = sample.toMap();
      final restored = StationSampleModel.fromMap(map);

      expect(restored.sampleMode, StationSampleModel.sampleModePooled);
      expect(restored.sectorType, StationSampleModel.sectorDefault);
      expect(restored.sampleKind, StationSampleModel.sampleKindPooled);
      expect(restored.sampleType, StationSampleModel.sampleTypeDefault);
      expect(restored.sampleLabel, 'Sample 1');
      expect(restored.legacyAuditId, isNull);
      expect(restored.houseNo, isNull);
      expect(restored.houseLabel, isNull);
      expect(restored.eggProductionDate, isNull);
      expect(restored.calculatedBmkAgeDays, isNull);
    });

    test(
      'supports multiple samples in one audit session with different BMK ages',
      () {
        final first = StationSampleModel(
          id: 'sample-1',
          auditSessionId: 'session-1',
          stationType: 'chicks',
          sampleIndex: 1,
          calculatedBmkAgeDays: 280,
          createdAt: createdAt,
          updatedAt: updatedAt,
        );
        final second = first.copyWith(
          id: 'sample-2',
          sampleIndex: 2,
          sampleLabel: 'Sample 2',
          houseNo: 'HSE-02',
          houseLabel: 'South House',
          calculatedBmkAgeDays: 273,
        );

        expect(first.auditSessionId, second.auditSessionId);
        expect(first.calculatedBmkAgeDays, isNot(second.calculatedBmkAgeDays));
        expect(second.sampleLabel, 'Sample 2');
        expect(second.houseNo, 'HSE-02');
        expect(second.houseLabel, 'South House');
      },
    );
  });
}
