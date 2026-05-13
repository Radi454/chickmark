import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/sample_mode.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const connectivityChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (call) async {
          if (call.method == 'check') return ['wifi'];
          return null;
        });
  });

  AuditContext context() => AuditContext(
    auditType: 'Chicks',
    customerId: 'customer-1',
    flockId: 'flock-1',
    flockAgeWeeks: 42,
    date: '2026-04-27',
  );

  AuditContext stationContext(String auditType) => AuditContext(
    auditType: auditType,
    customerId: 'customer-1',
    flockId: 'flock-1',
    date: '2026-04-27',
  );

  test('new audit sessions default to pooled sampling', () {
    final provider = AuditProvider();

    provider.initialize(context(), notify: false);

    expect(provider.sampleMode, SampleMode.pool);
    expect(provider.isCompareMode, isFalse);
    expect(provider.hatchCount, 1);
    expect(provider.activeDraft.hatchNumber, 1);
    expect(provider.activeDraft.compareGroupKey, isNull);
    expect(provider.stationSampleMode, StationSampleModel.sampleModePooled);
    expect(provider.sampleCount, 1);
    expect(provider.activeStationSample.sampleLabel, 'Sample 1');
  });

  test('all station contexts default to one pooled sample', () {
    for (final auditType in [
      'Egg',
      'Chicks',
      'Hatch Analysis & Egg Breakouts',
      'Setters',
      'Hatchers',
    ]) {
      final provider = AuditProvider();
      provider.initialize(stationContext(auditType), notify: false);

      expect(provider.stationSampleMode, StationSampleModel.sampleModePooled);
      expect(provider.sampleCount, 1);
      expect(provider.activeStationSample.stationType, isNotEmpty);
    }
  });

  test('compare mode gives all hatch drafts the same compare group key', () {
    final provider = AuditProvider();
    provider.initialize(context(), notify: false);

    provider.setSampleMode(SampleMode.compare);
    provider.addHatch();

    final groupKey = provider.drafts.first.compareGroupKey;
    expect(groupKey, isNotNull);
    expect(provider.hatchCount, 2);
    expect(provider.drafts.map((draft) => draft.sampleMode), [
      SampleMode.compare,
      SampleMode.compare,
    ]);
    expect(provider.drafts.map((draft) => draft.compareGroupKey).toSet(), {
      groupKey,
    });
    expect(provider.drafts.map((draft) => draft.hatchNumber), [1, 2]);
    expect(provider.stationSamples.map((sample) => sample.sampleLabel), [
      'M1',
      'M2',
    ]);
  });

  test('switching back to pool keeps one pooled sample only', () {
    final provider = AuditProvider();
    provider.initialize(context(), notify: false);

    provider.setSampleMode(SampleMode.compare);
    provider.addHatch();
    provider.setSampleMode(SampleMode.pool);

    expect(provider.sampleMode, SampleMode.pool);
    expect(provider.isCompareMode, isFalse);
    expect(provider.hatchCount, 1);
    expect(provider.activeDraft.hatchNumber, 1);
    expect(provider.activeDraft.compareGroupKey, isNull);
    expect(
      provider.activeStationSample.sampleMode,
      StationSampleModel.sampleModePooled,
    );
  });

  test(
    'sample metadata recalculates BMK age from flock weeks and egg date',
    () {
      final provider = AuditProvider();
      provider.initialize(context(), notify: false);

      provider.updateSampleMetadata({
        'eggProductionDate': DateTime(2026, 4, 20),
      });

      expect(provider.activeStationSample.calculatedBmkAgeDays, 287);
    },
  );

  test('removeActiveHatch keeps compare hatch numbers sequential', () {
    final provider = AuditProvider();
    provider.initialize(context(), notify: false);

    provider.setSampleMode(SampleMode.compare);
    provider.addHatch();
    provider.addHatch();
    provider.switchHatch(1);
    provider.removeActiveHatch();

    expect(provider.isCompareMode, isTrue);
    expect(provider.hatchCount, 2);
    expect(provider.activeHatchIndex, 1);
    expect(provider.drafts.map((draft) => draft.hatchNumber), [1, 2]);
    expect(provider.drafts.map((draft) => draft.compareGroupKey).toSet(), {
      provider.drafts.first.compareGroupKey,
    });
    expect(provider.stationSamples.map((sample) => sample.sampleLabel), [
      'M1',
      'M2',
    ]);
  });

  test('sample drafts keep independent values when switching samples', () {
    final provider = AuditProvider();
    provider.initialize(stationContext('Egg'), notify: false);

    provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
    provider.updateField('esEggStorageDays', 3);
    provider.addSample();
    provider.updateField('esEggStorageDays', 7);
    provider.switchSample(0);

    expect(provider.activeDraft.esEggStorageDays, 3);
    expect(provider.activeStationSample.storageDays, 3);

    provider.switchSample(1);

    expect(provider.activeDraft.esEggStorageDays, 7);
    expect(provider.activeStationSample.storageDays, 7);
  });

  test('egg storage comparison samples are labeled as house samples', () {
    final provider = AuditProvider();
    provider.initialize(stationContext('Egg'), notify: false);

    provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
    provider.addSample();
    provider.addSample();

    expect(provider.stationSamples.map((sample) => sample.comparisonType), [
      StationSampleModel.comparisonTypeHouse,
      StationSampleModel.comparisonTypeHouse,
      StationSampleModel.comparisonTypeHouse,
    ]);
    expect(provider.stationSamples.map((sample) => sample.sampleLabel), [
      'H1',
      'H2',
      'H3',
    ]);
    expect(provider.stationSamples.map((sample) => sample.houseNo), [
      'H1',
      'H2',
      'H3',
    ]);
    expect(provider.stationSamples.map((sample) => sample.houseLabel), [
      'House 1',
      'House 2',
      'House 3',
    ]);
  });

  test('setter comparison samples are labeled by setter number', () {
    final provider = AuditProvider();
    provider.initialize(
      AuditContext(
        auditType: 'Setters',
        customerId: 'customer-1',
        flockId: 'flock-1',
        setterId: '5',
        date: '2026-04-27',
      ),
      notify: false,
    );

    provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
    provider.addSample();
    provider.updateField('setterId', '7');
    provider.updateField('soSetterId', '7');

    expect(provider.stationSamples.map((sample) => sample.comparisonType), [
      StationSampleModel.comparisonTypeMachine,
      StationSampleModel.comparisonTypeMachine,
    ]);
    expect(provider.stationSamples.map((sample) => sample.sampleKind), [
      StationSampleModel.sampleKindMachine,
      StationSampleModel.sampleKindMachine,
    ]);
    expect(provider.stationSamples.map((sample) => sample.sampleLabel), [
      'S5',
      'S7',
    ]);
    expect(provider.stationSamples.map((sample) => sample.setterNo), [
      '5',
      '7',
    ]);
    expect(provider.stationSamples.map((sample) => sample.groupLabel), [
      'Setter comparison',
      'Setter comparison',
    ]);
    expect(provider.drafts.map((draft) => draft.setterId), ['5', '7']);
    expect(provider.drafts.map((draft) => draft.soSetterId), ['5', '7']);
  });

  test(
    'chick quality samples stay machine scoped while weights use houses',
    () {
      final provider = AuditProvider();
      provider.initialize(
        AuditContext(
          auditType: 'Chicks',
          customerId: 'customer-1',
          flockId: 'flock-1',
          setterId: 'S-1',
          hatcherId: 'H-1',
          date: '2026-04-27',
        ),
        notify: false,
      );

      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.addSample();
      provider.updateSampleMetadata({'setterNo': 'S-2', 'hatcherNo': 'H-2'});
      provider.setChickWeightSampleMode(
        StationSampleModel.sampleModeComparison,
      );
      provider.addChickWeightSample();

      expect(provider.stationSamples.map((sample) => sample.comparisonType), [
        StationSampleModel.comparisonTypeMachine,
        StationSampleModel.comparisonTypeMachine,
      ]);
      expect(provider.stationSamples.map((sample) => sample.sampleLabel), [
        'M1',
        'M2',
      ]);
      expect(provider.stationSamples.map((sample) => sample.groupLabel), [
        'Machine comparison',
        'Machine comparison',
      ]);
      expect(provider.stationSamples.map((sample) => sample.sectorType), [
        StationSampleModel.sectorChickQuality,
        StationSampleModel.sectorChickQuality,
      ]);
      expect(provider.stationSamples.map((sample) => sample.sampleKind), [
        StationSampleModel.sampleKindMachine,
        StationSampleModel.sampleKindMachine,
      ]);
      expect(provider.stationSamples.map((sample) => sample.setterNo), [
        'S-1',
        'S-2',
      ]);
      expect(provider.stationSamples.map((sample) => sample.hatcherNo), [
        'H-1',
        'H-2',
      ]);
      expect(provider.activeDraft.setterId, 'S-2');
      expect(provider.activeDraft.hatcherId, 'H-2');

      expect(
        provider.chickWeightSamples.map((sample) => sample.comparisonType),
        [
          StationSampleModel.comparisonTypeHouse,
          StationSampleModel.comparisonTypeHouse,
        ],
      );
      expect(provider.chickWeightSamples.map((sample) => sample.sampleLabel), [
        'H1',
        'H2',
      ]);
      expect(provider.chickWeightSamples.map((sample) => sample.groupLabel), [
        'House comparison',
        'House comparison',
      ]);
      expect(provider.chickWeightSamples.map((sample) => sample.sectorType), [
        StationSampleModel.sectorChickWeights,
        StationSampleModel.sectorChickWeights,
      ]);
      expect(provider.chickWeightSamples.map((sample) => sample.sampleKind), [
        StationSampleModel.sampleKindHouse,
        StationSampleModel.sampleKindHouse,
      ]);
      expect(provider.chickWeightSamples.map((sample) => sample.houseNo), [
        'H1',
        'H2',
      ]);
      expect(provider.chickWeightSamples.map((sample) => sample.setterNo), [
        null,
        null,
      ]);
      expect(provider.chickWeightSamples.map((sample) => sample.hatcherNo), [
        null,
        null,
      ]);
    },
  );

  test('removing egg storage house samples keeps house labels sequential', () {
    final provider = AuditProvider();
    provider.initialize(stationContext('Egg'), notify: false);

    provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
    provider.addSample();
    provider.addSample();
    provider.switchSample(1);
    provider.removeActiveSample();

    expect(provider.stationSamples.map((sample) => sample.sampleLabel), [
      'H1',
      'H2',
    ]);
    expect(provider.stationSamples.map((sample) => sample.houseNo), [
      'H1',
      'H2',
    ]);
    expect(provider.drafts.map((draft) => draft.hatchNumber), [1, 2]);
  });
}
