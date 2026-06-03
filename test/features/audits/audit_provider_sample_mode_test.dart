import 'dart:convert';

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
      'S1H1',
      'S2H2',
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

  test('chick storage defaults to zero for BMK sample metadata', () {
    final provider = AuditProvider();
    provider.initialize(context(), notify: false);

    expect(provider.activeDraft.chickStorageDays, 0);
    expect(provider.activeStationSample.storageDays, 0);
    expect(provider.activeStationSample.calculatedBmkAgeDays, 273);
  });

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
      'S1H1',
      'S2H2',
    ]);
  });

  test('egg quality measurements stay independent while storage is shared', () {
    final provider = AuditProvider();
    provider.initialize(stationContext('Egg'), notify: false);

    provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
    provider.updateField('esEggStorageDays', 3);
    provider.updateField('esEggAvgWeight', 55.0);
    provider.addSample();
    provider.updateField('esEggStorageDays', 7);
    provider.updateField('esEggAvgWeight', 66.0);
    provider.switchSample(0);

    expect(provider.activeDraft.esEggStorageDays, 7);
    expect(provider.activeDraft.esEggAvgWeight, 55.0);
    expect(provider.activeStationSample.storageDays, 7);

    provider.switchSample(1);

    expect(provider.activeDraft.esEggStorageDays, 7);
    expect(provider.activeDraft.esEggAvgWeight, 66.0);
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

  test('egg quality scopes stay pooled until a scope comparison is added', () {
    final provider = AuditProvider();
    provider.initialize(stationContext('Egg'), notify: false);

    expect(provider.stationSampleMode, StationSampleModel.sampleModePooled);
    expect(provider.sampleCount, 1);

    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);

    expect(provider.stationSampleMode, StationSampleModel.sampleModeComparison);
    expect(provider.stationSamples.map((sample) => sample.sampleKind), [
      StationSampleModel.sampleKindHouse,
    ]);
    expect(provider.stationSamples.map((sample) => sample.comparisonType), [
      StationSampleModel.comparisonTypeHouse,
    ]);
    expect(provider.stationSamples.map((sample) => sample.sampleLabel), ['H']);
    expect(provider.stationSamples.map((sample) => sample.houseNo), ['H']);
  });
  test('first egg quality house scope starts as a prefix placeholder', () {
    final provider = AuditProvider();
    provider.initialize(stationContext('Egg'), notify: false);

    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);

    expect(provider.sampleCount, 1);
    expect(
      provider.activeStationSample.sampleKind,
      StationSampleModel.sampleKindHouse,
    );
    expect(provider.activeStationSample.sampleLabel, 'H');
    expect(provider.activeStationSample.houseNo, 'H');
  });

  test('new egg quality scope placeholders update from entered values', () {
    final provider = AuditProvider();
    provider.initialize(stationContext('Egg'), notify: false);

    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);

    expect(provider.activeStationSample.sampleLabel, 'H');
    expect(provider.activeStationSample.houseNo, 'H');

    provider.updateSampleMetadata({'houseNo': '2'});

    expect(provider.activeStationSample.sampleLabel, 'H2');
    expect(provider.activeStationSample.houseNo, '2');
    expect(provider.activeStationSample.houseLabel, 'House 2');
  });

  test(
    'egg storage and BMK fields are shared across quality scope samples',
    () {
      final provider = AuditProvider();
      provider.initialize(stationContext('Egg'), notify: false);

      provider.updateField('esEggStorageDays', 5);
      provider.updateField('esEggQualityStorageDays', 3);
      provider.updateField('esEggBmkAge', 39);
      provider.updateField('esEggBmkWeight', 61.5);

      provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
      provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
      provider.updateSampleMetadata({'houseNo': '2'});

      expect(provider.drafts.map((draft) => draft.esEggStorageDays), [5, 5]);
      expect(provider.drafts.map((draft) => draft.esEggQualityStorageDays), [
        3,
        3,
      ]);
      expect(provider.drafts.map((draft) => draft.esEggBmkAge), [39, 39]);
      expect(provider.drafts.map((draft) => draft.esEggBmkWeight), [
        61.5,
        61.5,
      ]);

      provider.updateField('esEggQualityStorageDays', 4);
      provider.updateField('esEggBmkAge', 38);
      provider.updateField('esEggBmkWeight', 60.2);

      expect(provider.drafts.map((draft) => draft.esEggQualityStorageDays), [
        4,
        4,
      ]);
      expect(provider.drafts.map((draft) => draft.esEggBmkAge), [38, 38]);
      expect(provider.drafts.map((draft) => draft.esEggBmkWeight), [
        60.2,
        60.2,
      ]);

      provider.switchSample(0);
      provider.updateField('esEggStorageDays', 6);

      expect(provider.drafts.map((draft) => draft.esEggStorageDays), [6, 6]);
    },
  );

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

  test('adding a setter machine sample starts the new machine EST pooled', () {
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

    // First machine has a 2-sample (comparison) incubation-age EST scope.
    provider.updateField(
      'so_estSamplesJson',
      jsonEncode([
        {'id': 'a', 'incubationAge': 3},
        {'id': 'b', 'incubationAge': 6},
      ]),
    );

    provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
    provider.addSample();

    // Adding a machine must not flip the new machine's EST scope out of Pool:
    // the previous machine keeps its 2-sample comparison, while the new machine
    // starts with a single default EST sample (which renders as `Pool`).
    expect(provider.drafts.length, 2);
    final firstEst = jsonDecode(provider.drafts[0].soEstSamplesJson!) as List;
    final secondEst = jsonDecode(provider.drafts[1].soEstSamplesJson!) as List;
    expect(firstEst, hasLength(2));
    expect(secondEst, hasLength(1));
  });

  test('hatcher comparison samples are labeled by hatcher number', () {
    final provider = AuditProvider();
    provider.initialize(
      AuditContext(
        auditType: 'Hatchers',
        customerId: 'customer-1',
        flockId: 'flock-1',
        hatcherId: 'H-01',
        date: '2026-04-27',
      ),
      notify: false,
    );

    provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
    provider.addSample();
    provider.updateField('hatcherId', '3');
    provider.updateField('hoHatcherId', '3');

    expect(provider.stationSamples.map((sample) => sample.comparisonType), [
      StationSampleModel.comparisonTypeMachine,
      StationSampleModel.comparisonTypeMachine,
    ]);
    expect(provider.stationSamples.map((sample) => sample.sampleKind), [
      StationSampleModel.sampleKindMachine,
      StationSampleModel.sampleKindMachine,
    ]);
    expect(provider.stationSamples.map((sample) => sample.sampleLabel), [
      'H01',
      'H3',
    ]);
    expect(provider.stationSamples.map((sample) => sample.hatcherNo), [
      'H-01',
      '3',
    ]);
    expect(provider.stationSamples.map((sample) => sample.groupLabel), [
      'Hatcher comparison',
      'Hatcher comparison',
    ]);
    expect(provider.drafts.map((draft) => draft.hatcherId), ['H-01', '3']);
    expect(provider.drafts.map((draft) => draft.hoHatcherId), ['H-01', '3']);
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
        'S1H1',
        'S2H2',
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
        'H',
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
        'H',
      ]);
      provider.switchChickWeightSample(0);
      expect(provider.activeChickWeightSample.sampleLabel, 'H1');
      expect(provider.activeChickWeightSample.houseNo, 'H1');
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

  test('chick quality machine scope follows egg placeholder behavior', () {
    final provider = AuditProvider();
    provider.initialize(
      AuditContext(
        auditType: 'Chicks',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: '2026-04-27',
      ),
      notify: false,
    );

    provider.addChickQualityMachineScopeSample();

    expect(provider.stationSampleMode, StationSampleModel.sampleModeComparison);
    expect(provider.stationSamples.map((sample) => sample.sampleKind), [
      StationSampleModel.sampleKindMachine,
    ]);
    expect(provider.stationSamples.map((sample) => sample.comparisonType), [
      StationSampleModel.comparisonTypeMachine,
    ]);
    expect(provider.stationSamples.map((sample) => sample.sampleLabel), ['SH']);
    expect(provider.stationSamples.map((sample) => sample.setterNo), ['S']);
    expect(provider.stationSamples.map((sample) => sample.hatcherNo), ['H']);
    expect(provider.stationSamples.map((sample) => sample.houseNo), ['']);

    provider.updateSampleMetadata({'setterNo': '7', 'hatcherNo': '8'});

    expect(provider.activeStationSample.sampleLabel, 'S7H8');
    expect(provider.activeStationSample.setterNo, '7');
    expect(provider.activeStationSample.hatcherNo, '8');
  });

  test('removing the only chick quality machine scope returns to pool', () {
    final provider = AuditProvider();
    provider.initialize(
      AuditContext(
        auditType: 'Chicks',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: '2026-04-27',
      ),
      notify: false,
    );

    provider.addChickQualityMachineScopeSample();
    provider.removeActiveChickQualityMachineScopeSample();

    expect(provider.isCompareMode, isFalse);
    expect(provider.sampleCount, 1);
    expect(provider.stationSampleMode, StationSampleModel.sampleModePooled);
    expect(
      provider.activeStationSample.sampleMode,
      StationSampleModel.sampleModePooled,
    );
    expect(provider.activeStationSample.comparisonType, isNull);
    expect(provider.activeStationSample.sampleLabel, 'Sample 1');
  });

  test('chick weight house scope follows egg placeholder behavior', () {
    final provider = AuditProvider();
    provider.initialize(
      AuditContext(
        auditType: 'Chicks',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: '2026-04-27',
      ),
      notify: false,
    );

    provider.addChickWeightSample();

    expect(
      provider.chickWeightSampleMode,
      StationSampleModel.sampleModeComparison,
    );
    expect(provider.chickWeightSamples.map((sample) => sample.sampleKind), [
      StationSampleModel.sampleKindHouse,
    ]);
    expect(provider.chickWeightSamples.map((sample) => sample.comparisonType), [
      StationSampleModel.comparisonTypeHouse,
    ]);
    expect(provider.chickWeightSamples.map((sample) => sample.sampleLabel), [
      'H',
    ]);
    expect(provider.chickWeightSamples.map((sample) => sample.houseNo), ['H']);

    provider.updateChickWeightSampleMetadata({'houseNo': '12'});

    expect(provider.activeChickWeightSample.sampleLabel, 'H12');
    expect(provider.activeChickWeightSample.houseNo, '12');
    expect(provider.activeChickWeightSample.houseLabel, 'House 12');
  });

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
