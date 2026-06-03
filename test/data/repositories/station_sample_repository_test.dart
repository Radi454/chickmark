import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/data/repositories/station_sample_repository.dart';

void main() {
  test(
    'legacy station sample repository is inert after panel cutover',
    () async {
      final repository = StationSampleRepository();
      final sample = StationSampleModel(
        id: 'sample-1',
        auditSessionId: 'session-1',
        stationType: 'egg',
        sectorType: StationSampleModel.sectorEggQuality,
        sampleKind: StationSampleModel.sampleKindHouse,
        sampleMode: StationSampleModel.sampleModePooled,
        sampleIndex: 1,
        sampleLabel: 'H1',
        createdAt: DateTime(2026, 4, 27),
        updatedAt: DateTime(2026, 4, 27),
      );

      await repository.upsertSample(sample);
      await repository.upsertSampleRow(sample.toMap());

      expect(await repository.getSampleById(sample.id), isNull);
      expect(
        await repository.getSamplesBySessionId(sample.auditSessionId),
        isEmpty,
      );
      expect(
        await repository.getSamplesForStation(sample.auditSessionId, 'egg'),
        isEmpty,
      );
      expect(
        await repository.getSamplesByGroupKey(sample.auditSessionId, 'group'),
        isEmpty,
      );
      expect(
        await repository.getSamplesByLegacyAuditId('legacy-audit'),
        isEmpty,
      );
      expect(await repository.getAllSampleRecordRows(), isEmpty);
      expect(await repository.getSampleRecordRowById(sample.id), isNull);
      expect(StationSampleRepository.detailTables, isEmpty);
    },
  );
}
