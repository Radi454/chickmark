import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/panel_sample_model.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/data/repositories/benchmark_lookup.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/features/audits/services/audit_panel_save_coordinator.dart';

class _CapturePanelRepository extends Fake implements PanelSampleRepository {
  Map<String, SamplingMeasurementIdentity> identities = const {};
  int saveCount = 0;

  @override
  Future<void> savePanelWithSamples({
    required PanelRecord panel,
    required List<PanelSampleRecord> samples,
    Map<String, SamplingMeasurementIdentity> samplingIdentitiesByRowId =
        const {},
  }) async {
    saveCount++;
    identities = samplingIdentitiesByRowId;
  }
}

class _NoopBenchmarkLookup extends Fake implements BenchmarkLookup {}

void main() {
  test(
    'coordinator persists each terminal sample identity by row id',
    () async {
      final repository = _CapturePanelRepository();
      final coordinator = AuditPanelSaveCoordinator(
        panelSampleRepository: repository,
        benchmarkLookup: _NoopBenchmarkLookup(),
        context: () => null,
        activeSessionId: () => 'session-1',
        stationSamples: () => const [],
        chickWeightSamples: () => const [],
      );
      final draft = AuditModel(
        id: 'draft-1',
        auditType: 'Setter Optimizing',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: DateTime(2026, 10, 5),
        hatchNumber: 1,
        status: 'draft',
        createdBy: 'auditor-1',
        createdAt: DateTime(2026, 10, 5),
        updatedAt: DateTime(2026, 10, 5),
        soSetterId: 'S1',
      );
      final sample = StationSampleModel(
        id: 'session-1:setter_optimizing:draft-1:leaf-1',
        sampleId: 'leaf-1',
        auditSessionId: 'session-1',
        stationType: 'setters',
        sampleIndex: 1,
        setterNo: 'S1',
        sampleLabel: 'S1 · SA4',
        createdAt: DateTime(2026, 10, 5),
        updatedAt: DateTime(2026, 10, 5),
      );
      final path = SamplingScopePath(
        setter: 'S1',
        sampleId: 'leaf-1',
        sampleNumber: 4,
      );

      await coordinator.savePanelTables(
        panelSavePairs: const [],
        draftsToSave: const [],
        removedStationSampleIds: const [],
        samplingManagedTables: const {'setter_optimizing'},
        samplingSavePairs: [
          (
            tableName: 'setter_optimizing',
            draft: draft,
            sample: sample,
            path: path,
          ),
        ],
      );

      expect(repository.identities.keys, {sample.id});
      expect(repository.identities[sample.id]!.sampleId, 'leaf-1');
      expect(repository.identities[sample.id]!.sampleNumber, 4);
      expect(repository.identities[sample.id]!.path.setter, 'S1');
    },
  );

  test('empty pooled leaf does not create a measurement row', () async {
    final repository = _CapturePanelRepository();
    final coordinator = AuditPanelSaveCoordinator(
      panelSampleRepository: repository,
      benchmarkLookup: _NoopBenchmarkLookup(),
      context: () => null,
      activeSessionId: () => 'session-1',
      stationSamples: () => const [],
      chickWeightSamples: () => const [],
    );
    final draft = AuditModel(
      id: 'draft-1',
      auditType: 'Egg',
      customerId: 'customer-1',
      flockId: 'flock-1',
      date: DateTime(2026, 10, 5),
      hatchNumber: 1,
      status: 'draft',
      createdBy: 'auditor-1',
      createdAt: DateTime(2026, 10, 5),
      updatedAt: DateTime(2026, 10, 5),
    );
    final sample = StationSampleModel(
      id: 'session-1:egg_storage:draft-1:leaf-1',
      sampleId: 'leaf-1',
      auditSessionId: 'session-1',
      stationType: 'egg',
      sampleIndex: 1,
      createdAt: DateTime(2026, 10, 5),
      updatedAt: DateTime(2026, 10, 5),
    );

    await coordinator.savePanelTables(
      panelSavePairs: const [],
      draftsToSave: const [],
      removedStationSampleIds: const [],
      samplingManagedTables: const {'egg_storage'},
      samplingSavePairs: [
        (
          tableName: 'egg_storage',
          draft: draft,
          sample: sample,
          path: SamplingScopePath(sampleId: 'leaf-1', sampleNumber: 1),
        ),
      ],
    );

    expect(repository.saveCount, 0);
  });
}
