import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/data/repositories/panel_sampling_state_repository.dart';
import 'package:hatchaudit/features/audits/models/egg_breakout_sample.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseHelper databaseHelper;

  setUp(() async {
    await useIsolatedAppDatabase();
    databaseHelper = DatabaseHelper();
    final db = await databaseHelper.db;
    await db.insert('customers', {'id': 'customer-1', 'name': 'Customer'});
    await db.insert('hatcheries', {
      'id': 'hatchery-1',
      'name': 'Hatchery',
      'customerId': 'customer-1',
    });
    await db.insert('flocks', {
      'id': 'flock-1',
      'customerId': 'customer-1',
      'breed': 'Ross308',
    });
    await db.insert('audit_sessions', {
      'id': 'session-1',
      'customerId': 'customer-1',
      'flockId': 'flock-1',
      'hatcheryId': 'hatchery-1',
      'date': '2026-10-05',
    });
  });

  tearDown(() async => databaseHelper.close());

  AuditContext auditContext() => AuditContext(
    auditType: 'Hatch Analysis & Egg Breakouts',
    customerId: 'customer-1',
    flockId: 'flock-1',
    hatcheryId: 'hatchery-1',
    breed: 'Ross308',
    date: '2026-10-05',
  );

  AuditContext setterContext() => AuditContext(
    auditType: 'Setters',
    customerId: 'customer-1',
    flockId: 'flock-1',
    hatcheryId: 'hatchery-1',
    breed: 'Ross308',
    date: '2026-10-05',
  );

  AuditContext breakoutContext() => AuditContext(
    auditType: 'Hatch Analysis & Egg Breakouts',
    customerId: 'customer-1',
    flockId: 'flock-1',
    hatcheryId: 'hatchery-1',
    breed: 'Ross308',
    date: '2026-10-05',
  );

  test('terminal selection restores an independent panel form draft', () async {
    final provider = AuditProvider(autosaveEnabled: false);
    provider.initialize(auditContext(), sessionId: 'session-1', notify: false);
    await provider.loadPanelSamplingState('egg_quality');
    final firstHouse = await provider.addPanelScopeIdentity(
      'egg_quality',
      level: SamplingScopeLevel.house,
      parentId: null,
      identity: const {'code': 'H01'},
    );
    final first = await provider.addPanelTerminalSample(
      'egg_quality',
      parentId: firstHouse.id,
    );
    provider.updateField('esEggSampleSize', 12);
    provider.updateField('notes', 'House 1 notes');

    final secondHouse = await provider.addPanelScopeIdentity(
      'egg_quality',
      level: SamplingScopeLevel.house,
      parentId: null,
      identity: const {'code': 'H02'},
    );
    final other = await provider.addPanelTerminalSample(
      'egg_quality',
      parentId: secondHouse.id,
    );
    await provider.selectPanelSample('egg_quality', other.sampleId!);
    expect(provider.activeSampleIdFor('egg_quality'), other.sampleId);
    expect(provider.activeDraft.esEggSampleSize, isNot(12));
    expect(provider.activeDraft.notes, isNot('House 1 notes'));
    provider.updateField('esEggSampleSize', 5);
    provider.updateField('notes', 'House 2 notes');

    await provider.selectPanelSample('egg_quality', first.sampleId!);
    expect(provider.activeDraft.esEggSampleSize, 12);
    expect(provider.activeDraft.notes, 'House 1 notes');
    expect(
      provider.draftForSample('egg_quality', other.sampleId!)!.esEggSampleSize,
      5,
    );
    expect(
      provider.draftForSample('egg_quality', other.sampleId!)!.notes,
      'House 2 notes',
    );
    provider.dispose();
  });

  test(
    'initialize restores panel drafts keyed by immutable sample id',
    () async {
      final state = await PanelSamplingStateRepository().loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
      );
      final sampleId = state.resolvedActiveSampleId!;
      final provider = AuditProvider(autosaveEnabled: false);
      final sampleDraft = AuditModel(
        id: 'legacy-panel-row-1',
        auditType: 'Egg',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: DateTime(2026, 10, 5),
        hatchNumber: 1,
        status: 'draft',
        createdBy: 'panel',
        createdAt: DateTime(2026, 10, 5),
        updatedAt: DateTime(2026, 10, 5),
        esEggSampleSize: 18,
        esEggAvgWeight: 61.2,
      );
      provider.initialize(
        AuditContext(
          auditType: 'Egg',
          customerId: 'customer-1',
          flockId: 'flock-1',
          hatcheryId: 'hatchery-1',
          breed: 'Ross308',
          date: '2026-10-05',
        ),
        sessionId: 'session-1',
        notify: false,
        samplingDraftsByPanel: {
          'egg_quality': {sampleId: sampleDraft},
        },
      );

      await provider.loadPanelSamplingState('egg_quality');

      expect(provider.activeDraft.esEggSampleSize, 18);
      expect(provider.activeDraft.esEggAvgWeight, 61.2);
      expect(
        provider.draftForSample('egg_quality', sampleId)?.esEggSampleSize,
        18,
      );
      provider.dispose();
    },
  );

  test('legacy measurement row id is reused for its backfilled leaf', () async {
    final state = await PanelSamplingStateRepository().loadOrCreateDefault(
      sessionId: 'session-1',
      panelKey: 'egg_quality',
    );
    final sampleId = state.resolvedActiveSampleId!;
    final rowId = 'session-1:egg_quality:old-draft:row-1';
    final legacySample = StationSampleModel(
      id: rowId,
      sampleId: sampleId,
      auditSessionId: 'session-1',
      stationType: 'egg',
      sectorType: StationSampleModel.sectorEggQuality,
      sampleIndex: 1,
      createdAt: DateTime(2026, 10, 5),
      updatedAt: DateTime(2026, 10, 5),
    );
    final provider = AuditProvider(autosaveEnabled: false);
    provider.initialize(
      AuditContext(
        auditType: 'Egg',
        customerId: 'customer-1',
        flockId: 'flock-1',
        hatcheryId: 'hatchery-1',
        breed: 'Ross308',
        date: '2026-10-05',
      ),
      sessionId: 'session-1',
      existingStationSamples: [legacySample],
      samplingDraftsByPanel: {
        'egg_quality': {
          sampleId: AuditModel(
            id: 'old-draft',
            auditType: 'Egg',
            customerId: 'customer-1',
            flockId: 'flock-1',
            date: DateTime(2026, 10, 5),
            hatchNumber: 1,
            status: 'draft',
            createdBy: 'panel',
            createdAt: DateTime(2026, 10, 5),
            updatedAt: DateTime(2026, 10, 5),
            esEggSampleSize: 18,
          ),
        },
      },
    );
    await provider.loadPanelSamplingState('egg_quality');

    final savedPair = provider.samplingPanelSavePairs().single;

    expect(savedPair.sample.id, rowId);
    expect(savedPair.sample.sampleId, sampleId);
    expect(savedPair.path.sampleId, sampleId);
    provider.dispose();
  });

  test(
    'deleting the last scope restores pooled and keeps other panel state',
    () async {
      final provider = AuditProvider(autosaveEnabled: false);
      provider.initialize(
        auditContext(),
        sessionId: 'session-1',
        notify: false,
      );
      final qualityBefore = await provider.loadPanelSamplingState(
        'egg_quality',
      );
      final storageBefore = await provider.loadPanelSamplingState(
        'egg_storage',
      );
      final house = await provider.addPanelScopeIdentity(
        'egg_quality',
        level: SamplingScopeLevel.house,
        parentId: null,
        identity: const {'code': 'H01'},
      );
      await provider.addPanelTerminalSample('egg_quality', parentId: house.id);

      await provider.deletePanelScopeNode('egg_quality', house.id);
      final qualityAfter = provider.samplingStateFor('egg_quality')!;
      final storageAfter = provider.samplingStateFor('egg_storage')!;
      expect(qualityAfter.samples, hasLength(1));
      expect(qualityAfter.samples.single.level, SamplingScopeLevel.sample);
      expect(
        qualityAfter.nodes.where(
          (node) => node.level == SamplingScopeLevel.house,
        ),
        isEmpty,
      );
      expect(
        storageAfter.samples.single.sampleId,
        storageBefore.samples.single.sampleId,
      );
      expect(qualityBefore.sessionId, qualityAfter.sessionId);
      provider.dispose();
    },
  );

  test('read-only provider blocks sampling mutations', () async {
    final provider = AuditProvider(autosaveEnabled: false);
    provider.initialize(
      auditContext(),
      sessionId: 'session-1',
      readOnly: true,
      notify: false,
    );
    await provider.loadPanelSamplingState('egg_quality');
    await expectLater(
      provider.addPanelScopeIdentity(
        'egg_quality',
        level: SamplingScopeLevel.house,
        parentId: null,
        identity: const {'code': 'H01'},
      ),
      throwsStateError,
    );
    final state = provider.samplingStateFor('egg_quality')!;
    expect(
      state.nodes.where((node) => node.level == SamplingScopeLevel.house),
      isEmpty,
    );
    provider.dispose();
  });

  test(
    'measured Pooled add cancellation is inert until reset is confirmed',
    () async {
      final provider = AuditProvider(autosaveEnabled: false);
      provider.initialize(
        auditContext(),
        sessionId: 'session-1',
        notify: false,
      );
      final before = await provider.loadPanelSamplingState('egg_quality');
      final pooledId = before.resolvedActiveSampleId!;
      provider.updateField('esEggSampleSize', 8);

      await expectLater(
        provider.addPanelScopeIdentity(
          'egg_quality',
          level: SamplingScopeLevel.house,
          parentId: null,
          identity: const {'code': 'H01', 'name': 'House 1'},
        ),
        throwsStateError,
      );
      expect(
        provider.samplingStateFor('egg_quality')!.nodes.map((node) => node.id),
        before.nodes.map((node) => node.id),
      );
      expect(
        provider.draftForSample('egg_quality', pooledId)!.esEggSampleSize,
        8,
      );

      final house = await provider.addPanelScopeIdentity(
        'egg_quality',
        level: SamplingScopeLevel.house,
        parentId: null,
        identity: const {'code': 'H01', 'name': 'House 1'},
        discardPooledData: true,
      );
      expect(house.level, SamplingScopeLevel.house);
      expect(provider.draftForSample('egg_quality', pooledId), isNull);
      provider.dispose();
    },
  );

  test(
    'chick weight leaves keep independent values from each other and quality',
    () async {
      final provider = AuditProvider(autosaveEnabled: false);
      provider.initialize(
        AuditContext(
          auditType: 'Chicks',
          customerId: 'customer-1',
          flockId: 'flock-1',
          hatcheryId: 'hatchery-1',
          breed: 'Ross308',
          date: '2026-10-05',
        ),
        sessionId: 'session-1',
        notify: false,
      );
      final quality = await provider.loadPanelSamplingState('chick_quality');
      provider.updateField('pasgarSampleSize', 5);
      final weightState = await provider.loadPanelSamplingState(
        'chick_weights',
      );
      final houseA = await provider.addPanelScopeIdentity(
        'chick_weights',
        level: SamplingScopeLevel.house,
        parentId: null,
        identity: const {'house': 'house-a', 'code': 'H01', 'name': 'House 1'},
      );
      final weightA = await provider.addPanelTerminalSample(
        'chick_weights',
        parentId: houseA.id,
      );
      provider.updateChickWeightSampleResult(
        weightsJson: '[10,20]',
        avgWeight: 15,
      );

      final houseB = await provider.addPanelScopeIdentity(
        'chick_weights',
        level: SamplingScopeLevel.house,
        parentId: null,
        identity: const {'house': 'house-b', 'code': 'H02', 'name': 'House 2'},
      );
      final weightB = await provider.addPanelTerminalSample(
        'chick_weights',
        parentId: houseB.id,
      );
      expect(provider.activeChickWeightSample.sampleId, weightB.sampleId);
      final summaryB =
          jsonDecode(provider.activeChickWeightSample.resultSummaryJson!)
              as Map<String, dynamic>;
      expect(summaryB['chickWeights'], isNull);
      provider.updateChickWeightSampleResult(
        weightsJson: '[30,40]',
        avgWeight: 35,
      );

      await provider.selectPanelSample('chick_weights', weightA.sampleId!);
      final summaryA =
          jsonDecode(provider.activeChickWeightSample.resultSummaryJson!)
              as Map<String, dynamic>;
      expect(summaryA['chickWeights'], [10, 20]);
      expect(provider.activeDraft.pasgarSampleSize, 5);
      await provider.selectPanelSample(
        'chick_quality',
        quality.resolvedActiveSampleId!,
      );
      expect(provider.activeDraft.pasgarSampleSize, 5);
      expect(weightState.samples, hasLength(1));
      provider.dispose();
    },
  );

  test(
    'optimizer saved fields stay with their selected sampling leaf',
    () async {
      final provider = AuditProvider(autosaveEnabled: false);
      provider.initialize(
        setterContext(),
        sessionId: 'session-1',
        notify: false,
      );
      await provider.activateSamplingPanel('setter_optimizing');

      final setterOne = await provider.addPanelScopeIdentity(
        'setter_optimizing',
        level: SamplingScopeLevel.setter,
        parentId: null,
        identity: const {'code': 'S1'},
      );
      final sampleOne = await provider.addPanelScopeIdentity(
        'setter_optimizing',
        level: SamplingScopeLevel.tray,
        parentId: setterOne.id,
        identity: const {'code': 'T1'},
      );
      await provider.selectPanelSample(
        'setter_optimizing',
        sampleOne.sampleId!,
      );
      provider.updateField('so_setpointF', 100.4);
      provider.updateField('so_actualF', 100.6);

      final setterTwo = await provider.addPanelScopeIdentity(
        'setter_optimizing',
        level: SamplingScopeLevel.setter,
        parentId: null,
        identity: const {'code': 'S2'},
      );
      final sampleTwo = await provider.addPanelScopeIdentity(
        'setter_optimizing',
        level: SamplingScopeLevel.tray,
        parentId: setterTwo.id,
        identity: const {'code': 'T1'},
      );
      await provider.selectPanelSample(
        'setter_optimizing',
        sampleTwo.sampleId!,
      );
      provider.updateField('so_setpointF', 101.4);
      provider.updateField('so_actualF', 101.6);

      await provider.selectPanelSample(
        'setter_optimizing',
        sampleOne.sampleId!,
      );
      final savedDrafts = {
        for (final pair in provider.samplingPanelSavePairs())
          if (pair.path.setter != null) pair.path.setter!: pair.draft,
      };

      expect(savedDrafts['S1']?.soSetpointF, 100.4);
      expect(savedDrafts['S1']?.soActualF, 100.6);
      expect(savedDrafts['S2']?.soSetpointF, 101.4);
      expect(savedDrafts['S2']?.soActualF, 101.6);
      provider.dispose();
    },
  );

  test(
    'breakout panel switches retain independent counts notes and drafts',
    () async {
      final provider = AuditProvider(autosaveEnabled: false);
      provider.initialize(
        breakoutContext(),
        sessionId: 'session-1',
        notify: false,
      );

      provider.updateField(
        'ebBreakoutType',
        EggBreakoutType.freshEggBreakout.storageValue,
      );
      await provider.activateSamplingPanel('fresh_egg_breakout');
      final freshId = provider.activeSampleIdFor('fresh_egg_breakout')!;
      provider.updateField('ebInfertileCount', 4);
      provider.updateField('notes', 'Fresh notes');

      await provider.activateSamplingPanel('candled_egg_breakout');
      final candledId = provider.activeSampleIdFor('candled_egg_breakout')!;
      provider.updateField(
        'ebBreakoutType',
        EggBreakoutType.candledEggBreakout.storageValue,
      );
      provider.updateField('ebEarlyDeadCount', 5);
      provider.updateField('notes', 'Candled notes');

      await provider.activateSamplingPanel('residue_breakout');
      final residueId = provider.activeSampleIdFor('residue_breakout')!;
      provider.updateField(
        'ebBreakoutType',
        EggBreakoutType.residueHatchDay.storageValue,
      );
      provider.updateField('haHatched', 6);
      provider.updateField('notes', 'Residue notes');

      await provider.activateSamplingPanel('fresh_egg_breakout');
      expect(provider.activeDraft.ebInfertileCount, 4);
      expect(provider.activeDraft.notes, 'Fresh notes');
      await provider.activateSamplingPanel('candled_egg_breakout');
      expect(provider.activeDraft.ebEarlyDeadCount, 5);
      expect(provider.activeDraft.notes, 'Candled notes');
      await provider.activateSamplingPanel('residue_breakout');
      expect(provider.activeDraft.haHatched, 6);
      expect(provider.activeDraft.notes, 'Residue notes');

      expect(
        provider
            .draftForSample('fresh_egg_breakout', freshId)
            ?.ebInfertileCount,
        4,
      );
      expect(
        provider
            .draftForSample('candled_egg_breakout', candledId)
            ?.ebEarlyDeadCount,
        5,
      );
      expect(
        provider.draftForSample('residue_breakout', residueId)?.haHatched,
        6,
      );
      provider.dispose();
    },
  );

  test('new breakout leaves retain their panel type', () async {
    final provider = AuditProvider(autosaveEnabled: false);
    provider.initialize(
      breakoutContext(),
      sessionId: 'session-1',
      notify: false,
    );
    await provider.activateSamplingPanel('fresh_egg_breakout');
    final house = await provider.addPanelScopeIdentity(
      'fresh_egg_breakout',
      level: SamplingScopeLevel.house,
      parentId: null,
      identity: const {'code': '1'},
      discardPooledData: true,
    );
    final fresh = await provider.addPanelTerminalSample(
      'fresh_egg_breakout',
      parentId: house.id,
    );
    expect(
      provider.activeDraft.ebBreakoutType,
      EggBreakoutType.freshEggBreakout.storageValue,
    );
    provider.updateField('ebInfertileCount', 12);
    await provider.activateSamplingPanel('candled_egg_breakout');
    final firstId = provider.activeSampleIdFor('candled_egg_breakout')!;
    final tray = await provider.addPanelScopeIdentity(
      'candled_egg_breakout',
      level: SamplingScopeLevel.tray,
      parentId: null,
      identity: const {'code': '2'},
    );
    expect(
      provider.activeDraft.ebBreakoutType,
      EggBreakoutType.candledEggBreakout.storageValue,
    );
    await provider.selectPanelSample('candled_egg_breakout', firstId);
    expect(
      provider.activeDraft.ebBreakoutType,
      EggBreakoutType.candledEggBreakout.storageValue,
    );
    await provider.selectPanelSample('candled_egg_breakout', tray.sampleId!);
    await provider.selectPanelSample('fresh_egg_breakout', fresh.sampleId!);
    expect(
      provider.activeDraft.ebBreakoutType,
      EggBreakoutType.freshEggBreakout.storageValue,
    );
    expect(provider.activeDraft.ebInfertileCount, 12);
    provider.dispose();
  });

  test(
    'default Tray 1 requires ancestor reset but survives adding Tray 2',
    () async {
      final provider = AuditProvider(autosaveEnabled: false);
      provider.initialize(
        setterContext(),
        sessionId: 'session-1',
        notify: false,
      );
      await provider.activateSamplingPanel('setter_optimizing');
      final initial = provider.samplingStateFor('setter_optimizing')!;
      final trayOne = initial.samples.single;
      expect(initial.pathFor(trayOne.sampleId!).tray, 'T1');
      provider.updateField('so_setpointF', 100.2);

      await expectLater(
        provider.addPanelScopeIdentity(
          'setter_optimizing',
          level: SamplingScopeLevel.setter,
          parentId: null,
          identity: const {'code': 'S1'},
        ),
        throwsStateError,
      );
      expect(
        provider.samplingStateFor('setter_optimizing')!.nodes,
        initial.nodes,
      );

      final trayTwo = await provider.addPanelScopeIdentity(
        'setter_optimizing',
        level: SamplingScopeLevel.tray,
        parentId: null,
        identity: const {'code': 'T2'},
      );
      expect(trayTwo.identity['code'], 'T2');
      expect(
        provider
            .draftForSample('setter_optimizing', trayOne.sampleId!)
            ?.soSetpointF,
        100.2,
      );
      provider.dispose();
    },
  );
}
