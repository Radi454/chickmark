import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/data/repositories/benchmark_lookup.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/data/repositories/panel_sampling_state_repository.dart';
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
}
