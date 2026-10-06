import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/photo_model.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/data/repositories/benchmark_lookup.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/data/repositories/panel_sampling_state_repository.dart';
import 'package:hatchaudit/data/repositories/photo_repository.dart';
import 'package:hatchaudit/features/audits/logic/egg_station_reconstruction.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/audits/services/audit_panel_save_coordinator.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseHelper helper;
  setUp(() async {
    await useIsolatedAppDatabase();
    helper = DatabaseHelper();
    final db = await helper.db;
    await db.insert('customers', {'id': 'c', 'name': 'Customer'});
    await db.insert('hatcheries', {
      'id': 'h',
      'customerId': 'c',
      'name': 'Hatchery',
    });
    await db.insert('flocks', {
      'id': 'f',
      'customerId': 'c',
      'breed': 'Ross308',
    });
    await db.insert('audit_sessions', {
      'id': 'session',
      'customerId': 'c',
      'hatcheryId': 'h',
      'flockId': 'f',
      'date': '2026-10-05',
    });
  });
  tearDown(() async => helper.close());

  const cases = [
    (
      table: 'egg_quality',
      station: 'egg',
      type: 'Egg',
      field: 'esEggSampleSize',
      breakout: null,
    ),
    (
      table: 'chick_quality',
      station: 'chicks',
      type: 'Chicks',
      field: 'pasgarSampleSize',
      breakout: null,
    ),
    (
      table: 'chick_weights',
      station: 'chicks',
      type: 'Chicks',
      field: 'chickSampleSize',
      breakout: null,
    ),
    (
      table: 'fresh_egg_breakout',
      station: 'hatch_analysis_egg_breakouts',
      type: 'Hatch Analysis & Egg Breakouts',
      field: 'ebInfertileCount',
      breakout: 'freshEggBreakout',
    ),
    (
      table: 'candled_egg_breakout',
      station: 'hatch_analysis_egg_breakouts',
      type: 'Hatch Analysis & Egg Breakouts',
      field: 'ebInfertileCount',
      breakout: 'candledEggBreakout',
    ),
    (
      table: 'residue_breakout',
      station: 'hatch_analysis_egg_breakouts',
      type: 'Hatch Analysis & Egg Breakouts',
      field: 'ebInfertileCount',
      breakout: 'residueHatchDay',
    ),
    (
      table: 'setter_optimizing',
      station: 'setters',
      type: 'Setter Optimizing',
      field: 'so_setpointF',
      breakout: null,
    ),
    (
      table: 'hatcher_optimizing',
      station: 'hatchers',
      type: 'Hatcher Optimizing',
      field: 'ho_setpointF',
      breakout: null,
    ),
  ];
  for (final item in cases) {
    test(
      '${item.table} A/B measurement rows reopen independently without identity changes',
      () async {
        final trees = PanelSamplingStateRepository(databaseHelper: helper);
        final config = PanelSampleSchema.samplingConfigFor(item.table);
        var state = await trees.loadOrCreateDefault(
          sessionId: 'session',
          panelKey: item.table,
        );
        final leaves = <SamplingNode>[];
        if (config.terminalLevel == SamplingScopeLevel.tray) {
          leaves.add(state.samples.single);
          leaves.add(
            await trees.addScopeIdentity(
              sessionId: 'session',
              panelKey: item.table,
              parentId: null,
              level: SamplingScopeLevel.tray,
              identity: const {'code': '2'},
            ),
          );
        } else {
          for (var i = 1; i <= 2; i++) {
            final group = await trees.addScopeIdentity(
              sessionId: 'session',
              panelKey: item.table,
              parentId: null,
              level: config.levels.first,
              identity: config.pairedLevels == null
                  ? {'code': '$i'}
                  : {'setter': '$i', 'hatcher': '$i'},
            );
            leaves.add(
              await trees.addTerminalSample(
                sessionId: 'session',
                panelKey: item.table,
                parentId: group.id,
              ),
            );
          }
        }
        state = await trees.loadOrCreateDefault(
          sessionId: 'session',
          panelKey: item.table,
        );
        final context = AuditContext(
          auditType: item.type,
          customerId: 'c',
          flockId: 'f',
          hatcheryId: 'h',
          breed: 'Ross308',
          date: '2026-10-05',
        );
        final repository = PanelSampleRepository(databaseHelper: helper);
        final coordinator = AuditPanelSaveCoordinator(
          panelSampleRepository: repository,
          benchmarkLookup: BenchmarkLookup(dbHelper: helper),
          context: () => context,
          activeSessionId: () => 'session',
          stationSamples: () => const [],
          chickWeightSamples: () => const [],
        );
        final pairs = <SamplingPanelSavePair>[];
        for (var i = 0; i < leaves.length; i++) {
          final leaf = leaves[i];
          final value = item.field.endsWith('F') ? 99.0 + i : 11 + i;
          final note = '${item.table} leaf ${i + 1} notes';
          final draft = AuditModel.fromMap({
            'id': 'draft',
            'auditType': item.type,
            'customerId': 'c',
            'flockId': 'f',
            'hatcheryId': 'h',
            'breed': 'Ross308',
            'date': '2026-10-05',
            'hatchNumber': 1,
            'status': 'draft',
            'createdBy': 'test',
            'createdAt': '2026-10-05T00:00:00',
            'updatedAt': '2026-10-05T00:00:00',
            item.field: value,
            'notes': note,
            if (item.breakout != null) 'ebBreakoutType': item.breakout,
            if (item.table == 'setter_optimizing') 'soIncubationAge': 7 + i,
          });
          final sample = StationSampleModel(
            id: PanelSampleRepository.idKeyedPanelTables.contains(item.table)
                ? '${item.table}-row-${i + 1}'
                : 'session:${item.table}:draft:leaf-${i + 1}',
            sampleId: leaf.sampleId,
            auditSessionId: 'session',
            stationType: item.station,
            sampleIndex: i + 1,
            sampleLabel: 'Leaf ${i + 1}',
            notes: note,
            resultSummaryJson: item.table == 'chick_weights'
                ? jsonEncode({
                    'sampleSize': value,
                    'weightsJson': '[40,41]',
                    'avgWeight': 40.5,
                  })
                : null,
            createdAt: DateTime(2026, 10, 5),
            updatedAt: DateTime(2026, 10, 5),
          );
          pairs.add((
            tableName: item.table,
            draft: draft,
            sample: sample,
            path: state.pathFor(leaf.sampleId!),
          ));
        }
        await coordinator.savePanelTables(
          panelSavePairs: const [],
          draftsToSave: const [],
          removedStationSampleIds: const [],
          samplingManagedTables: {item.table},
          samplingSavePairs: pairs,
        );
        final rows = await repository.getRowsBySessionId(item.table, 'session');
        expect(rows, hasLength(2));
        expect(
          rows.map((r) => r['id']).toSet(),
          pairs.map((p) => p.sample.id).toSet(),
        );
        expect(
          rows.map((r) => r['sampleId']).toSet(),
          leaves.map((l) => l.sampleId).toSet(),
        );
        final reopened = reconstructStation(
          stationKey: item.station,
          sessionId: 'session',
          context: AuditContextData(
            auditType: item.type,
            customerId: 'c',
            flockId: 'f',
            hatcheryId: 'h',
            breed: 'Ross308',
            date: '2026-10-05',
          ),
          rowsByPanel: {
            item.table: rows.map((r) => Map<String, dynamic>.from(r)).toList(),
          },
        );
        final restored = reopened.samplingDraftsByPanel[item.table]!;
        for (var i = 0; i < leaves.length; i++) {
          final draft = restored[leaves[i].sampleId]!;
          expect(
            draft.toMap()[item.field],
            item.field.endsWith('F') ? 99.0 + i : 11 + i,
          );
          expect(draft.notes, '${item.table} leaf ${i + 1} notes');
          if (item.table == 'setter_optimizing') {
            expect(draft.toMap()['soIncubationAge'], 7 + i);
          }
        }
        // Saving the reopened adapters must reuse the exact rows rather than
        // prepend another session/panel prefix or prune the sibling sample.
        final resavePairs = [
          for (final pair in pairs)
            (
              tableName: pair.tableName,
              draft: restored[pair.sample.sampleId]!,
              sample: pair.sample,
              path: pair.path,
            ),
        ];
        await coordinator.savePanelTables(
          panelSavePairs: const [],
          draftsToSave: const [],
          removedStationSampleIds: const [],
          samplingManagedTables: {item.table},
          samplingSavePairs: resavePairs,
        );
        final resaved = await repository.getRowsBySessionId(
          item.table,
          'session',
        );
        expect(
          resaved.map((r) => r['id']).toSet(),
          rows.map((r) => r['id']).toSet(),
        );
      },
    );
  }

  test(
    'managed Setter identity and reading save despite a stale blank legacy template',
    () async {
      final context = AuditContext(
        auditType: 'Setters',
        customerId: 'c',
        flockId: 'f',
        hatcheryId: 'h',
        breed: 'Ross308',
        date: '2026-10-05',
      );
      final provider = AuditProvider(autosaveEnabled: false);
      provider.initialize(context, sessionId: 'session', notify: false);
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);

      await provider.loadPanelSamplingState('setter_optimizing');
      final setter = await provider.addPanelScopeIdentity(
        'setter_optimizing',
        level: SamplingScopeLevel.setter,
        parentId: null,
        identity: const {'code': 'SET-1'},
      );
      final trolley = await provider.addPanelScopeIdentity(
        'setter_optimizing',
        level: SamplingScopeLevel.trolley,
        parentId: setter.id,
        identity: const {'code': 'TR-2'},
      );
      final tray = await provider.addPanelTerminalSample(
        'setter_optimizing',
        parentId: trolley.id,
        identity: const {'code': 'T-1', 'name': 'Tray 1'},
      );
      await provider.selectPanelSample('setter_optimizing', tray.sampleId!);
      provider.updateField('so_setpointF', 100.4);

      expect(provider.samplingManagedPanelKeys, contains('setter_optimizing'));
      expect(await provider.saveSamplesWithResult(), isTrue);

      final panels = PanelSampleRepository(databaseHelper: helper);
      final rows = await panels.getRowsBySessionId(
        'setter_optimizing',
        'session',
      );
      expect(rows, hasLength(1));
      expect(rows.single['setter'], 'SET-1');
      expect(rows.single['setpointF'], 100.4);
      final path = jsonDecode(rows.single['samplingPathJson']! as String);
      expect(path['setter'], 'SET-1');
      expect(path['trolley'], 'TR-2');
      expect(path['tray'], 'T-1');

      final restored = reconstructStation(
        stationKey: 'setters',
        sessionId: 'session',
        context: AuditContextData(
          auditType: 'Setters',
          customerId: 'c',
          flockId: 'f',
          hatcheryId: 'h',
          breed: 'Ross308',
          date: '2026-10-05',
        ),
        rowsByPanel: {
          'setter_optimizing': rows.map(Map<String, dynamic>.from).toList(),
        },
      );
      final staleLegacySample = restored.stationSamples
          .singleWhere((sample) => sample.sampleId == tray.sampleId)
          .copyWith(
            legacyAuditId: provider.activeDraft.id,
            sampleMode: StationSampleModel.sampleModeComparison,
            sampleKind: StationSampleModel.sampleKindMachine,
            comparisonType: StationSampleModel.comparisonTypeMachine,
            setterNo: '',
          );
      final reopenedProvider = AuditProvider(autosaveEnabled: false);
      reopenedProvider.initialize(
        context,
        existingAudits: [provider.activeDraft],
        existingStationSamples: [staleLegacySample],
        readOnly: false,
        sessionId: 'session',
        samplingDraftsByPanel: restored.samplingDraftsByPanel,
        notify: false,
      );
      await reopenedProvider.loadPanelSamplingState('setter_optimizing');
      expect(reopenedProvider.activeStationSample.setterNo, '');
      expect(
        reopenedProvider
            .draftForSample('setter_optimizing', tray.sampleId!)
            ?.soSetpointF,
        100.4,
      );
      expect(await reopenedProvider.saveSamplesWithResult(), isTrue);

      final reopenedRows = await panels.getRowsBySessionId(
        'setter_optimizing',
        'session',
      );
      final reopenedTargetRows = reopenedRows
          .where((row) => row['sampleId'] == tray.sampleId)
          .toList();
      expect(reopenedTargetRows, hasLength(1));
      expect(reopenedTargetRows.single['setpointF'], 100.4);
      final reopenedPath = jsonDecode(
        reopenedTargetRows.single['samplingPathJson']! as String,
      );
      expect(reopenedPath['setter'], 'SET-1');
      expect(reopenedPath['trolley'], 'TR-2');
      expect(reopenedPath['tray'], 'T-1');
    },
  );

  test(
    'chick quality values and photos retain sample ownership across save, rename, reopen, and sibling deletion',
    () async {
      final trees = PanelSamplingStateRepository(databaseHelper: helper);
      final panels = PanelSampleRepository(databaseHelper: helper);
      final photos = PhotoRepository();
      final context = AuditContext(
        auditType: 'Chicks',
        customerId: 'c',
        flockId: 'f',
        hatcheryId: 'h',
        breed: 'Ross308',
        date: '2026-10-05',
      );
      final provider = AuditProvider(autosaveEnabled: false);
      provider.initialize(context, sessionId: 'session', notify: false);
      await provider.loadPanelSamplingState('chick_quality');

      Future<SamplingNode> addLeaf(String houseCode) async {
        final house = await provider.addPanelScopeIdentity(
          'chick_quality',
          level: SamplingScopeLevel.setter,
          parentId: null,
          identity: {'setter': houseCode, 'hatcher': 'H01'},
        );
        return provider.addPanelTerminalSample(
          'chick_quality',
          parentId: house.id,
        );
      }

      final leafA = await addLeaf('H01');
      provider.updateField('pasgarSampleSize', 30);
      provider.updateField('notes', 'A only notes');
      final leafB = await addLeaf('H02');
      await provider.selectPanelSample('chick_quality', leafB.sampleId!);
      provider.updateField('pasgarSampleSize', 50);
      provider.updateField('notes', 'B only notes');

      final coordinator = AuditPanelSaveCoordinator(
        panelSampleRepository: panels,
        benchmarkLookup: BenchmarkLookup(dbHelper: helper),
        context: () => context,
        activeSessionId: () => 'session',
        stationSamples: () => const [],
        chickWeightSamples: () => const [],
      );
      Future<void> save(AuditProvider source) async {
        await coordinator.savePanelTables(
          panelSavePairs: const [],
          draftsToSave: const [],
          removedStationSampleIds: const [],
          samplingManagedTables: source.samplingManagedPanelKeys,
          samplingSavePairs: source.samplingPanelSavePairs(),
        );
      }

      await save(provider);
      final initialRows = await panels.getRowsBySessionId(
        'chick_quality',
        'session',
      );
      expect(initialRows, hasLength(2));
      final rowIdBySample = {
        for (final row in initialRows)
          row['sampleId'] as String: row['id'] as String,
      };
      final rowA = rowIdBySample[leafA.sampleId]!;
      final rowB = rowIdBySample[leafB.sampleId]!;
      expect(rowA, isNot(rowB));

      await photos.saveLocalPhoto(
        PhotoModel(
          id: 'photo-a',
          filePath: 'https://example.test/a.jpg',
          createdAt: DateTime(2026, 10, 5, 9),
          sessionId: 'session',
          panelName: 'chick_quality',
          panelRowId: rowA,
          fieldKey: 'pasgarBeakPhoto',
        ),
      );
      await photos.saveLocalPhoto(
        PhotoModel(
          id: 'photo-b',
          filePath: 'https://example.test/b.jpg',
          createdAt: DateTime(2026, 10, 5, 10),
          sessionId: 'session',
          panelName: 'chick_quality',
          panelRowId: rowB,
          fieldKey: 'pasgarBeakPhoto',
        ),
      );

      Future<StationReconstruction> reopen() async {
        final rows = await panels.getRowsBySessionId(
          'chick_quality',
          'session',
        );
        final state = await trees.loadOrCreateDefault(
          sessionId: 'session',
          panelKey: 'chick_quality',
        );
        final result = reconstructStation(
          stationKey: 'chicks',
          sessionId: 'session',
          context: AuditContextData(
            auditType: 'Chicks',
            customerId: 'c',
            flockId: 'f',
            hatcheryId: 'h',
            breed: 'Ross308',
            date: '2026-10-05',
          ),
          rowsByPanel: {
            'chick_quality': rows
                .map((r) => Map<String, dynamic>.from(r))
                .toList(),
          },
        );
        final hydrated = overlayPanelPhotos(
          result,
          await photos.getBySessionId('session'),
        );
        expect(state.samples.map((sample) => sample.sampleId).toSet(), {
          leafA.sampleId,
          leafB.sampleId,
        });
        return hydrated;
      }

      var reopened = await reopen();
      final restored = reopened.samplingDraftsByPanel['chick_quality']!;
      expect(restored[leafA.sampleId]!.pasgarSampleSize, 30);
      expect(restored[leafA.sampleId]!.notes, 'A only notes');
      expect(restored[leafB.sampleId]!.pasgarSampleSize, 50);
      expect(restored[leafB.sampleId]!.notes, 'B only notes');
      final draftBySample = {
        for (var i = 0; i < reopened.stationSamples.length; i++)
          reopened.stationSamples[i].sampleId!: reopened.stationAudits[i],
      };
      expect(
        draftBySample[leafA.sampleId]!.pasgarBeakPhoto,
        'https://example.test/a.jpg',
      );
      expect(
        draftBySample[leafB.sampleId]!.pasgarBeakPhoto,
        'https://example.test/b.jpg',
      );

      final reopenedProvider = AuditProvider(autosaveEnabled: false);
      reopenedProvider.initialize(
        context,
        sessionId: 'session',
        notify: false,
        existingStationSamples: reopened.stationSamples,
        samplingDraftsByPanel: reopened.samplingDraftsByPanel,
      );
      await reopenedProvider.loadPanelSamplingState('chick_quality');
      final houseA = reopenedProvider
          .samplingStateFor('chick_quality')!
          .nodes
          .singleWhere((node) => node.identity['setter'] == 'H01');
      await reopenedProvider.editPanelScopeIdentity(
        'chick_quality',
        houseA.id,
        const {'setter': 'H01-renamed', 'hatcher': 'H01'},
      );
      await save(reopenedProvider);
      reopenedProvider.dispose();

      reopened = await reopen();
      final renamedPath = reopened.stationSamples.singleWhere(
        (sample) => sample.sampleId == leafA.sampleId,
      );
      expect(renamedPath.id, rowA);
      expect(renamedPath.sampleId, leafA.sampleId);
      expect(renamedPath.setterNo, 'H01-renamed');
      final renamedDrafts = reopened.samplingDraftsByPanel['chick_quality']!;
      expect(renamedDrafts[leafA.sampleId]!.pasgarSampleSize, 30);
      expect(renamedDrafts[leafA.sampleId]!.notes, 'A only notes');
      expect(renamedDrafts[leafB.sampleId]!.pasgarSampleSize, 50);
      expect(renamedDrafts[leafB.sampleId]!.notes, 'B only notes');
      final renamedDraftBySample = {
        for (var i = 0; i < reopened.stationSamples.length; i++)
          reopened.stationSamples[i].sampleId!: reopened.stationAudits[i],
      };
      expect(
        renamedDraftBySample[leafA.sampleId]!.pasgarBeakPhoto,
        'https://example.test/a.jpg',
      );
      expect(
        renamedDraftBySample[leafB.sampleId]!.pasgarBeakPhoto,
        'https://example.test/b.jpg',
      );

      final setterANode = (await trees.loadOrCreateDefault(
        sessionId: 'session',
        panelKey: 'chick_quality',
      )).nodes.singleWhere((node) => node.identity['setter'] == 'H01-renamed');
      await trees.deleteSubtree(nodeId: setterANode.id);
      final survivingRows = await panels.getRowsBySessionId(
        'chick_quality',
        'session',
      );
      expect(survivingRows.map((row) => row['id']), [rowB]);
      expect(survivingRows.single['sampleId'], leafB.sampleId);
      expect(survivingRows.single['pasgarSampleSize'], 50);
      expect(survivingRows.single['notes'], 'B only notes');
      expect(
        (await photos.getBySessionId('session')).map((photo) => photo.id),
        ['photo-b'],
      );
      final db = await helper.db;
      expect(
        await db.query(
          'sync_tombstones',
          where: 'tableName = ? AND rowId = ?',
          whereArgs: ['chick_quality', rowA],
        ),
        hasLength(1),
      );
      expect(
        await db.query(
          'sync_tombstones',
          where: 'tableName = ? AND rowId = ?',
          whereArgs: ['photos', 'photo-a'],
        ),
        hasLength(1),
      );
      provider.dispose();
    },
  );
}
