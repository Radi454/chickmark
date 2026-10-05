import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/panel_sample_model.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';
import 'package:hatchaudit/data/repositories/panel_sampling_state_repository.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import '../../support/test_database.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late PanelSamplingStateRepository repository;

  setUp(() async {
    await useIsolatedAppDatabase();
    database = await DatabaseHelper().db;
    repository = PanelSamplingStateRepository(
      databaseHelper: DatabaseHelper(),
      panelSampleRepository: PanelSampleRepository(),
    );
    await database.insert('customers', {
      'id': 'customer-1',
      'name': 'Customer',
    });
    await database.insert('hatcheries', {
      'id': 'hatchery-1',
      'name': 'Hatchery',
      'customerId': 'customer-1',
    });
    await database.insert('flocks', {
      'id': 'flock-1',
      'customerId': 'customer-1',
      'breed': 'Breed',
    });
    await database.insert('audit_sessions', {
      'id': 'session-1',
      'customerId': 'customer-1',
      'flockId': 'flock-1',
      'hatcheryId': 'hatchery-1',
      'date': '2026-10-05',
    });
  });

  tearDown(() async {
    await DatabaseHelper().close();
  });

  test('creates one terminal default per isolated session and panel', () async {
    final first = await repository.loadOrCreateDefault(
      sessionId: 'session-1',
      panelKey: 'candled_egg_breakout',
    );
    final same = await repository.loadOrCreateDefault(
      sessionId: 'session-1',
      panelKey: 'candled_egg_breakout',
    );
    final otherPanel = await repository.loadOrCreateDefault(
      sessionId: 'session-1',
      panelKey: 'egg_quality',
    );

    expect(first.samples, hasLength(1));
    expect(first.samples.single.level, SamplingScopeLevel.tray);
    expect(first.samples.single.identity['code'], 'T1');
    expect(first.samples.single.sampleNumber, 1);
    expect(same.samples.single.sampleId, first.samples.single.sampleId);
    expect(otherPanel.samples, hasLength(1));
    expect(otherPanel.samples.single.level, SamplingScopeLevel.sample);
    expect(
      otherPanel.samples.single.sampleId,
      isNot(first.samples.single.sampleId),
    );
    expect(
      await database.query('panel_sample_serial_reservations'),
      hasLength(2),
    );
  });

  test(
    'initial default sample ID converges across identical offline replicas',
    () async {
      final first = await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
      );
      final firstId = first.samples.single.sampleId;
      await DatabaseHelper().close();
      await useIsolatedAppDatabase();
      database = await DatabaseHelper().db;
      await database.insert('customers', {
        'id': 'customer-1',
        'name': 'Customer',
      });
      await database.insert('hatcheries', {
        'id': 'hatchery-1',
        'name': 'Hatchery',
        'customerId': 'customer-1',
      });
      await database.insert('flocks', {
        'id': 'flock-1',
        'customerId': 'customer-1',
        'breed': 'Breed',
      });
      await database.insert('audit_sessions', {
        'id': 'session-1',
        'customerId': 'customer-1',
        'flockId': 'flock-1',
        'hatcheryId': 'hatchery-1',
        'date': '2026-10-05',
      });

      final second = await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
      );
      expect(second.samples.single.sampleId, firstId);
      expect(second.samples.single.sampleNumber, 1);
    },
  );

  test('allows only one panel-native terminal per selected parent', () async {
    await repository.loadOrCreateDefault(
      sessionId: 'session-1',
      panelKey: 'egg_quality',
    );
    final house = await repository.addScopeIdentity(
      sessionId: 'session-1',
      panelKey: 'egg_quality',
      parentId: null,
      level: SamplingScopeLevel.house,
      identity: const {'code': 'H01'},
    );
    await repository.addTerminalSample(
      sessionId: 'session-1',
      panelKey: 'egg_quality',
      parentId: house.id,
    );
    await expectLater(
      repository.addTerminalSample(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        parentId: house.id,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('adding another Tray retains measured default Tray1', () async {
    final state = await repository.loadOrCreateDefault(
      sessionId: 'session-1',
      panelKey: 'candled_egg_breakout',
    );
    final trayOne = state.samples.single;
    await database.insert('candled_egg_breakout', {
      'id': 'tray-one-measurement',
      'sessionId': 'session-1',
      'customerId': 'customer-1',
      'date': '2026-10-05',
      'tray': '1',
      'sampleId': trayOne.sampleId,
      'sampleNumber': trayOne.sampleNumber,
      'infertileCount': 8,
      'createdAt': '2026-10-05T00:00:00.000Z',
      'updatedAt': '2026-10-05T00:00:00.000Z',
    });

    final trayTwo = await repository.addScopeIdentity(
      sessionId: 'session-1',
      panelKey: 'candled_egg_breakout',
      parentId: null,
      level: SamplingScopeLevel.tray,
      identity: const {'code': 'T2'},
    );

    final reloaded = await repository.loadOrCreateDefault(
      sessionId: 'session-1',
      panelKey: 'candled_egg_breakout',
    );
    expect(
      reloaded.samples.map((item) => item.sampleId),
      contains(trayOne.sampleId),
    );
    expect(
      reloaded.samples.map((item) => item.sampleId),
      contains(trayTwo.sampleId),
    );
    expect(
      (await database.query(
        'candled_egg_breakout',
        where: 'id = ?',
        whereArgs: ['tray-one-measurement'],
      )).single['infertileCount'],
      8,
    );
  });

  test('panel save attaches sampling identity before row upsert', () async {
    final state = await repository.loadOrCreateDefault(
      sessionId: 'session-1',
      panelKey: 'candled_egg_breakout',
    );
    final sample = state.samples.single;
    final path = state.pathFor(sample.sampleId!);
    final panel = PanelRecord(
      id: 'panel-1',
      tableName: 'candled_egg_breakout',
      sessionId: 'session-1',
      customerId: 'customer-1',
      flockId: 'flock-1',
      hatcheryId: 'hatchery-1',
      date: DateTime.utc(2026, 10, 5),
    );
    final measurement = PanelSampleRecord(
      id: 'measurement-1',
      panelId: panel.id,
      scopeType: SamplingLayer.pool,
    );

    await PanelSampleRepository().savePanelWithSamples(
      panel: panel,
      samples: [measurement],
      samplingIdentitiesByRowId: {
        measurement.id: SamplingMeasurementIdentity(
          sampleId: sample.sampleId!,
          sampleNumber: sample.sampleNumber!,
          path: path,
        ),
      },
    );

    final row = (await database.query('candled_egg_breakout')).single;
    expect(row['sampleId'], sample.sampleId);
    expect(row['sampleNumber'], sample.sampleNumber);
    expect(row['samplingPathJson'], path.toJsonString());
    expect(row['tray'], path.tray);
  });

  test('a stale save cannot recreate a deleted sample measurement', () async {
    final state = await repository.loadOrCreateDefault(
      sessionId: 'session-1',
      panelKey: 'egg_quality',
    );
    final sample = state.samples.single;
    final panel = PanelRecord(
      id: 'stale-panel',
      tableName: 'egg_quality',
      sessionId: 'session-1',
      customerId: 'customer-1',
      flockId: 'flock-1',
      hatcheryId: 'hatchery-1',
      date: DateTime.utc(2026, 10, 5),
    );
    final measurement = PanelSampleRecord(
      id: 'stale-measurement',
      panelId: panel.id,
      sampleSize: 10,
    );
    final identities = {
      measurement.id: SamplingMeasurementIdentity(
        sampleId: sample.sampleId!,
        sampleNumber: sample.sampleNumber!,
        path: state.pathFor(sample.sampleId!),
      ),
    };
    final samples = [measurement];
    final panels = PanelSampleRepository();
    await panels.savePanelWithSamples(
      panel: panel,
      samples: samples,
      samplingIdentitiesByRowId: identities,
    );
    await repository.deleteSubtree(nodeId: sample.id);

    await expectLater(
      panels.savePanelWithSamples(
        panel: panel,
        samples: samples,
        samplingIdentitiesByRowId: identities,
      ),
      throwsA(isA<StaleSamplingIdentityException>()),
    );
    expect(
      await database.query(
        'egg_quality',
        where: 'id = ?',
        whereArgs: [measurement.id],
      ),
      isEmpty,
    );
  });

  test(
    'a stale serial snapshot cannot overwrite reconciled identity',
    () async {
      final state = await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
      );
      final sample = state.samples.single;
      final panel = PanelRecord(
        id: 'serial-stale-panel',
        tableName: 'egg_quality',
        sessionId: 'session-1',
        customerId: 'customer-1',
        flockId: 'flock-1',
        hatcheryId: 'hatchery-1',
        date: DateTime.utc(2026, 10, 5),
      );
      final measurement = PanelSampleRecord(
        id: 'serial-stale-measurement',
        panelId: panel.id,
        sampleSize: 10,
      );
      await repository.applySerialAssignments(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        assignments: {sample.sampleId!: 44},
      );

      await expectLater(
        PanelSampleRepository().savePanelWithSamples(
          panel: panel,
          samples: [measurement],
          samplingIdentitiesByRowId: {
            measurement.id: SamplingMeasurementIdentity(
              sampleId: sample.sampleId!,
              sampleNumber: sample.sampleNumber!,
              path: state.pathFor(sample.sampleId!),
            ),
          },
        ),
        throwsA(isA<StaleSamplingIdentityException>()),
      );
      expect(await database.query('egg_quality'), isEmpty);
    },
  );

  test(
    'resaving a house-only sample preserves an unknown legacy Tray',
    () async {
      await database.insert('fresh_egg_breakout', {
        'id': 'fresh-legacy-row',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'date': '2026-10-05',
        'tray': 'Legacy Tray 9',
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
      });
      final state = await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'fresh_egg_breakout',
      );
      final sample = state.samples.single;
      final panel = PanelRecord(
        id: 'fresh-legacy-row',
        tableName: 'fresh_egg_breakout',
        sessionId: 'session-1',
        customerId: 'customer-1',
        flockId: 'flock-1',
        hatcheryId: 'hatchery-1',
        date: DateTime.utc(2026, 10, 5),
      );
      final measurement = PanelSampleRecord(
        id: 'fresh-legacy-row',
        panelId: panel.id,
        sampleSize: 12,
      );

      await PanelSampleRepository().savePanelWithSamples(
        panel: panel,
        samples: [measurement],
        samplingIdentitiesByRowId: {
          measurement.id: SamplingMeasurementIdentity(
            sampleId: sample.sampleId!,
            sampleNumber: sample.sampleNumber!,
            path: state.pathFor(sample.sampleId!),
          ),
        },
      );

      final row = (await database.query(
        'fresh_egg_breakout',
        where: 'id = ?',
        whereArgs: ['fresh-legacy-row'],
      )).single;
      expect(row['tray'], 'Legacy Tray 9');
      expect(row['sampleId'], sample.sampleId);
    },
  );

  test(
    'adds configured scopes, rejects duplicate identities, and keeps path',
    () async {
      await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'candled_egg_breakout',
      );

      final house = await repository.addScopeIdentity(
        sessionId: 'session-1',
        panelKey: 'candled_egg_breakout',
        parentId: null,
        level: SamplingScopeLevel.house,
        identity: const {'code': 'H01', 'name': 'House One'},
      );
      final trolley = await repository.addScopeIdentity(
        sessionId: 'session-1',
        panelKey: 'candled_egg_breakout',
        parentId: house.id,
        level: SamplingScopeLevel.trolley,
        identity: const {'code': 'TR2'},
      );
      final tray = await repository.addTerminalSample(
        sessionId: 'session-1',
        panelKey: 'candled_egg_breakout',
        parentId: trolley.id,
        identity: const {'code': 'T1'},
      );

      await expectLater(
        repository.addScopeIdentity(
          sessionId: 'session-1',
          panelKey: 'candled_egg_breakout',
          parentId: null,
          level: SamplingScopeLevel.house,
          identity: const {'house': 'H01'},
        ),
        throwsA(isA<ArgumentError>()),
      );
      final state = await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'candled_egg_breakout',
      );
      expect(state.pathFor(tray.sampleId!).house, 'H01');
      expect(state.pathFor(tray.sampleId!).trolley, 'TR2');
      expect(state.pathFor(tray.sampleId!).tray, 'T1');
    },
  );

  test(
    'retains registered House IDs separately from canonical identity',
    () async {
      await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
      );
      final house = await repository.addScopeIdentity(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        parentId: null,
        level: SamplingScopeLevel.house,
        identity: const {
          'id': 'registered-house-1',
          'code': 'H01',
          'name': 'House One',
        },
      );
      expect(house.identity['id'], 'registered-house-1');
      await expectLater(
        repository.addScopeIdentity(
          sessionId: 'session-1',
          panelKey: 'egg_quality',
          parentId: null,
          level: SamplingScopeLevel.house,
          identity: const {
            'id': 'registered-house-2',
            'code': 'H01',
            'name': 'House One',
          },
        ),
        throwsA(isA<ArgumentError>()),
      );

      final trayConfig = await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'candled_egg_breakout',
      );
      await expectLater(
        repository.addScopeIdentity(
          sessionId: 'session-1',
          panelKey: 'candled_egg_breakout',
          parentId: null,
          level: SamplingScopeLevel.tray,
          identity: const {'id': 'unsupported-tray-id', 'code': 'T2'},
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(trayConfig.samples, hasLength(1));
    },
  );

  test(
    'deleting a scope branch removes only its measurement rows and tombstones',
    () async {
      await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
      );
      final houseA = await repository.addScopeIdentity(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        parentId: null,
        level: SamplingScopeLevel.house,
        identity: const {'code': 'H01'},
      );
      final houseB = await repository.addScopeIdentity(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        parentId: null,
        level: SamplingScopeLevel.house,
        identity: const {'code': 'H02'},
      );
      final sampleA = await repository.addTerminalSample(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        parentId: houseA.id,
      );
      final sampleB = await repository.addTerminalSample(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        parentId: houseB.id,
      );
      await database.insert('egg_quality', {
        'id': 'measurement-a',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'date': '2026-10-05',
        'house': 'H01',
        'sampleId': sampleA.sampleId,
        'sampleNumber': sampleA.sampleNumber,
        'eggSampleSize': 12,
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
      });
      await database.insert('egg_quality', {
        'id': 'measurement-b',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'date': '2026-10-05',
        'house': 'H02',
        'sampleId': sampleB.sampleId,
        'sampleNumber': sampleB.sampleNumber,
        'eggSampleSize': 34,
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
      });

      final preview = await repository.previewDeleteSubtree(nodeId: houseA.id);
      expect(preview.measurementCount, 1);
      await repository.deleteSubtree(nodeId: houseA.id);

      final rows = await database.query('egg_quality', orderBy: 'id');
      expect(rows.map((row) => row['id']), ['measurement-b']);
      expect(rows.single['eggSampleSize'], 34);
      expect(
        await database.query(
          'sync_tombstones',
          where: 'tableName = ? AND rowId = ?',
          whereArgs: ['egg_quality', 'measurement-a'],
        ),
        hasLength(1),
      );
      expect(
        (await repository.loadOrCreateDefault(
          sessionId: 'session-1',
          panelKey: 'egg_quality',
        )).samples.map((sample) => sample.sampleId),
        contains(sampleB.sampleId),
      );
    },
  );

  test(
    'branch deletion tombstones photos and keeps shared photo files',
    () async {
      await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
      );
      final house = await repository.addScopeIdentity(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        parentId: null,
        level: SamplingScopeLevel.house,
        identity: const {'code': 'H01'},
      );
      final sample = await repository.addTerminalSample(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        parentId: house.id,
      );
      await database.insert('egg_quality', {
        'id': 'measurement-photo-target',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'date': '2026-10-05',
        'house': 'H01',
        'sampleId': sample.sampleId,
        'sampleNumber': sample.sampleNumber,
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
      });

      final dir = await Directory.systemTemp.createTemp('sampling_photo_');
      final uniqueFile = File('${dir.path}/unique.jpg');
      final sharedFile = File('${dir.path}/shared.jpg');
      await uniqueFile.writeAsBytes([1, 2, 3]);
      await sharedFile.writeAsBytes([4, 5, 6]);
      await database.insert('photos', {
        'id': 'photo-delete',
        'filePath': uniqueFile.path,
        'createdAt': '2026-10-05T00:00:00.000Z',
        'sessionId': 'session-1',
        'panelName': 'egg_quality',
        'panelRowId': 'measurement-photo-target',
        'fieldKey': 'notes',
      });
      await database.insert('photos', {
        'id': 'photo-shared-deleted-ref',
        'filePath': sharedFile.path,
        'createdAt': '2026-10-05T00:00:00.000Z',
        'sessionId': 'session-1',
        'panelName': 'egg_quality',
        'panelRowId': 'measurement-photo-target',
        'fieldKey': 'notes',
      });
      await database.insert('photos', {
        'id': 'photo-shared-survivor',
        'filePath': sharedFile.path,
        'createdAt': '2026-10-05T00:00:00.000Z',
        'sessionId': 'session-1',
        'panelName': 'egg_quality',
        'panelRowId': 'another-row',
        'fieldKey': 'notes',
      });

      await repository.deleteSubtree(nodeId: house.id);

      expect(await uniqueFile.exists(), isFalse);
      expect(await sharedFile.exists(), isTrue);
      expect(
        await database.query(
          'photos',
          where: 'id = ?',
          whereArgs: ['photo-delete'],
        ),
        isEmpty,
      );
      expect(
        await database.query(
          'photos',
          where: 'id = ?',
          whereArgs: ['photo-shared-survivor'],
        ),
        hasLength(1),
      );
      expect(
        await database.query(
          'sync_tombstones',
          where: 'tableName = ? AND rowId IN (?, ?)',
          whereArgs: ['photos', 'photo-delete', 'photo-shared-deleted-ref'],
        ),
        hasLength(2),
      );
      await dir.delete(recursive: true);
    },
  );

  test(
    'Chick Quality deletion includes helper and observation photos',
    () async {
      await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'chick_quality',
      );
      final pair = await repository.addScopeIdentity(
        sessionId: 'session-1',
        panelKey: 'chick_quality',
        parentId: null,
        level: SamplingScopeLevel.setter,
        identity: const {'setter': 'S1', 'hatcher': 'HT1'},
      );
      final sample = await repository.addTerminalSample(
        sessionId: 'session-1',
        panelKey: 'chick_quality',
        parentId: pair.id,
      );
      await database.insert('chick_quality', {
        'id': sample.sampleId,
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'date': '2026-10-05',
        'domain': 'chicks.pasgar',
        'sampleId': sample.sampleId,
        'sampleNumber': sample.sampleNumber,
        'setter': 'S1',
        'hatcher': 'HT1',
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
      });
      await database.insert('chick_quality', {
        'id': 'legacy-helper-row',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'date': '2026-10-05',
        'domain': 'chicks.pasgar',
        'sourceRefId': 'legacy-domain:${sample.sampleId}:legacy',
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
      });
      await database.insert('chick_quality_observation', {
        'id': 'observation-for-sample',
        'sampleId': sample.sampleId,
        'customerId': 'customer-1',
        'sessionId': 'session-1',
        'domain': 'chicks.pasgar',
        'kind': 'ordinal',
        'observationKey': 'score',
        'ordinal': 0,
        'numericValue': 1,
        'unit': 'points',
        'observedAt': '2026-10-05T00:00:00.000Z',
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
      });
      await database.insert('photos', {
        'id': 'photo-helper',
        'filePath': 'https://example.test/helper.jpg',
        'createdAt': '2026-10-05T00:00:00.000Z',
        'sessionId': 'session-1',
        'panelName': 'chick_quality',
        'panelRowId': 'legacy-helper-row',
        'fieldKey': 'pasgarScore',
      });
      await database.insert('photos', {
        'id': 'photo-observation',
        'filePath': 'https://example.test/observation.jpg',
        'createdAt': '2026-10-05T00:00:00.000Z',
        'sessionId': 'session-1',
        'panelName': 'chick_quality',
        'panelRowId': sample.sampleId,
        'observationId': 'observation-for-sample',
        'fieldKey': 'score',
      });

      final preview = await repository.previewDeleteSubtree(nodeId: pair.id);
      expect(preview.photoCount, 2);
      await repository.deleteSubtree(nodeId: pair.id);

      expect(await database.query('photos'), isEmpty);
      expect(await database.query('chick_quality_observation'), isEmpty);
      expect(
        await database.query(
          'chick_quality',
          where: 'id IN (?, ?)',
          whereArgs: [sample.sampleId, 'legacy-helper-row'],
        ),
        isEmpty,
      );
      expect(
        await database.query(
          'sync_tombstones',
          where: 'tableName = ? AND rowId IN (?, ?)',
          whereArgs: ['photos', 'photo-helper', 'photo-observation'],
        ),
        hasLength(2),
      );
    },
  );

  test('paired sampling identity retains registered machine UUIDs', () async {
    await repository.loadOrCreateDefault(
      sessionId: 'session-1',
      panelKey: 'chick_quality',
    );
    final pair = await repository.addScopeIdentity(
      sessionId: 'session-1',
      panelKey: 'chick_quality',
      parentId: null,
      level: SamplingScopeLevel.setter,
      identity: const {
        'setter': 'S01',
        'hatcher': 'H01',
        'setterMachineId': 'setter-uuid',
        'hatcherMachineId': 'hatcher-uuid',
      },
    );

    expect(pair.identity['setterMachineId'], 'setter-uuid');
    expect(pair.identity['hatcherMachineId'], 'hatcher-uuid');
    await expectLater(
      repository.addScopeIdentity(
        sessionId: 'session-1',
        panelKey: 'chick_quality',
        parentId: null,
        level: SamplingScopeLevel.setter,
        identity: const {
          'setter': 'S01',
          'hatcher': 'H01',
          'setterMachineId': 'different-setter-uuid',
          'hatcherMachineId': 'different-hatcher-uuid',
        },
      ),
      throwsArgumentError,
    );

    await repository.updateScopeIdentity(
      nodeId: pair.id,
      identity: const {
        'setter': 'S02',
        'hatcher': 'H02',
        'setterMachineId': 'setter-uuid',
        'hatcherMachineId': 'hatcher-uuid',
      },
    );
    final updated = await repository.loadOrCreateDefault(
      sessionId: 'session-1',
      panelKey: 'chick_quality',
    );
    final persisted = updated.nodes.singleWhere((node) => node.id == pair.id);
    expect(persisted.identity['setterMachineId'], 'setter-uuid');
    expect(persisted.identity['hatcherMachineId'], 'hatcher-uuid');
    expect(persisted.identity['setter'], 'S02');
  });

  test('restores a terminal under the deleted branch parent only', () async {
    await repository.loadOrCreateDefault(
      sessionId: 'session-1',
      panelKey: 'residue_breakout',
    );
    final houseOne = await repository.addScopeIdentity(
      sessionId: 'session-1',
      panelKey: 'residue_breakout',
      parentId: null,
      level: SamplingScopeLevel.house,
      identity: const {'code': 'H01'},
    );
    final houseTwo = await repository.addScopeIdentity(
      sessionId: 'session-1',
      panelKey: 'residue_breakout',
      parentId: null,
      level: SamplingScopeLevel.house,
      identity: const {'code': 'H02'},
    );
    final setter = await repository.addScopeIdentity(
      sessionId: 'session-1',
      panelKey: 'residue_breakout',
      parentId: houseOne.id,
      level: SamplingScopeLevel.setter,
      identity: const {'code': 'S01'},
    );
    final removedSample = await repository.addTerminalSample(
      sessionId: 'session-1',
      panelKey: 'residue_breakout',
      parentId: setter.id,
      identity: const {'code': 'T1'},
    );
    final houseTwoSample = await repository.addTerminalSample(
      sessionId: 'session-1',
      panelKey: 'residue_breakout',
      parentId: houseTwo.id,
      identity: const {'code': 'T1'},
    );

    await repository.deleteSubtree(nodeId: setter.id);

    final state = await repository.loadOrCreateDefault(
      sessionId: 'session-1',
      panelKey: 'residue_breakout',
    );
    expect(state.samples, hasLength(2));
    expect(
      state.samples.map((sample) => sample.sampleId),
      contains(houseTwoSample.sampleId),
    );
    expect(
      state.samples.map((sample) => sample.parentId),
      contains(houseOne.id),
    );
    expect(
      state.samples.map((sample) => sample.sampleId),
      isNot(contains(removedSample.sampleId)),
    );
  });

  test('rejects mutations for an unknown audit session', () async {
    expect(
      () => repository.loadOrCreateDefault(
        sessionId: 'missing-session',
        panelKey: 'egg_quality',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'requires explicit reset before replacing a measured pooled sample',
    () async {
      final initial = await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
      );
      final sample = initial.samples.single;
      await database.insert('egg_quality', {
        'id': 'pooled-measurement',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'date': '2026-10-05',
        'sampleId': sample.sampleId,
        'sampleNumber': sample.sampleNumber,
        'eggSampleSize': 12,
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
      });
      await database.insert('photos', {
        'id': 'pooled-photo',
        'filePath': 'https://example.test/pooled.jpg',
        'createdAt': '2026-10-05T00:00:00.000Z',
        'sessionId': 'session-1',
        'panelName': 'egg_quality',
        'panelRowId': 'pooled-measurement',
        'fieldKey': 'notes',
      });

      await expectLater(
        repository.addScopeIdentity(
          sessionId: 'session-1',
          panelKey: 'egg_quality',
          parentId: null,
          level: SamplingScopeLevel.house,
          identity: const {'code': 'H01'},
        ),
        throwsA(isA<StateError>()),
      );
      expect(await database.query('photos'), hasLength(1));
      final house = await repository.addScopeIdentity(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        parentId: null,
        level: SamplingScopeLevel.house,
        identity: const {'code': 'H01'},
        discardPooledData: true,
      );
      expect(house.identity['code'], 'H01');
      expect(await database.query('egg_quality'), isEmpty);
      expect(await database.query('photos'), isEmpty);
      expect(
        await database.query(
          'sync_tombstones',
          where: 'tableName = ? AND rowId = ?',
          whereArgs: ['egg_quality', 'pooled-measurement'],
        ),
        hasLength(1),
      );
      expect(
        await database.query(
          'sync_tombstones',
          where: 'tableName = ? AND rowId = ?',
          whereArgs: ['photos', 'pooled-photo'],
        ),
        hasLength(1),
      );
    },
  );

  test(
    'adding an earlier comparison resets measured pooled descendants only after approval',
    () async {
      await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'candled_egg_breakout',
      );
      final trolley = await repository.addScopeIdentity(
        sessionId: 'session-1',
        panelKey: 'candled_egg_breakout',
        parentId: null,
        level: SamplingScopeLevel.trolley,
        identity: const {'code': 'TR1'},
      );
      final tray = await repository.addTerminalSample(
        sessionId: 'session-1',
        panelKey: 'candled_egg_breakout',
        parentId: trolley.id,
        identity: const {'code': 'T2'},
      );
      await database.insert('candled_egg_breakout', {
        'id': 'pooled-trolley-measurement',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'date': '2026-10-05',
        'sampleId': tray.sampleId,
        'sampleNumber': tray.sampleNumber,
        'tray': 'T2',
        'trolley': 'TR1',
        'infertileCount': 6,
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
      });

      await expectLater(
        repository.addScopeIdentity(
          sessionId: 'session-1',
          panelKey: 'candled_egg_breakout',
          parentId: null,
          level: SamplingScopeLevel.house,
          identity: const {'code': 'H01'},
        ),
        throwsA(isA<StateError>()),
      );
      await repository.addScopeIdentity(
        sessionId: 'session-1',
        panelKey: 'candled_egg_breakout',
        parentId: null,
        level: SamplingScopeLevel.house,
        identity: const {'code': 'H01'},
        discardPooledData: true,
      );
      expect(await database.query('candled_egg_breakout'), isEmpty);
      expect(
        await database.query(
          'panel_sampling_nodes',
          where: 'id = ?',
          whereArgs: [trolley.id],
        ),
        isEmpty,
      );
    },
  );

  test(
    'updates identity and writes the full sample path without changing sample ID',
    () async {
      await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
      );
      final house = await repository.addScopeIdentity(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        parentId: null,
        level: SamplingScopeLevel.house,
        identity: const {'house': 'H01', 'name': 'House One'},
      );
      final sample = await repository.addTerminalSample(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        parentId: house.id,
      );
      await database.insert('egg_quality', {
        'id': 'measurement-1',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'date': '2026-10-05',
        'eggSampleSize': 21,
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
      });

      await repository.updateScopeIdentity(
        nodeId: house.id,
        identity: const {'code': 'H02', 'name': 'House Two'},
      );
      final state = await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
      );
      final path = state.pathFor(sample.sampleId!);
      await repository.upsertMeasurementIdentity(
        sampleId: sample.sampleId!,
        measurementRowId: 'measurement-1',
        path: path,
        executor: database,
      );

      final saved = (await database.query('egg_quality')).single;
      expect(saved['house'], 'H02');
      expect(saved['sampleId'], sample.sampleId);
      expect(saved['sampleNumber'], sample.sampleNumber);
      expect(saved['eggSampleSize'], 21);
      expect(saved['samplingPathJson'], isNotNull);
    },
  );

  test(
    'preserves distinct sample IDs that share the same legacy hierarchy',
    () async {
      final samples = PanelSampleRepository();
      for (final entry in const [
        ('sample-a', 'H01', 11),
        ('sample-b', 'H01', 22),
      ]) {
        await samples.upsertRow(
          tableName: 'egg_quality',
          row: {
            'id': entry.$1,
            'sessionId': 'session-1',
            'customerId': 'customer-1',
            'date': '2026-10-05',
            'house': entry.$2,
            'sampleId': entry.$1,
            'sampleNumber': entry.$3,
            'eggSampleSize': entry.$3,
            'createdAt': '2026-10-05T00:00:00.000Z',
            'updatedAt': '2026-10-05T00:00:00.000Z',
          },
        );
      }
      final rows = await database.query('egg_quality', orderBy: 'id');
      expect(rows.map((row) => row['id']), ['sample-a', 'sample-b']);
      expect(rows.map((row) => row['eggSampleSize']), [11, 22]);
    },
  );

  test(
    'reconciles serial collisions deterministically and reserves replacements',
    () async {
      await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'candled_egg_breakout',
      );
      final house = await repository.addScopeIdentity(
        sessionId: 'session-1',
        panelKey: 'candled_egg_breakout',
        parentId: null,
        level: SamplingScopeLevel.house,
        identity: const {'code': 'H01'},
      );
      final first = await repository.addTerminalSample(
        sessionId: 'session-1',
        panelKey: 'candled_egg_breakout',
        parentId: house.id,
        identity: const {'code': 'T2'},
      );
      final second = await repository.addTerminalSample(
        sessionId: 'session-1',
        panelKey: 'candled_egg_breakout',
        parentId: house.id,
        identity: const {'code': 'T3'},
      );
      final ids = [first.sampleId!, second.sampleId!]..sort();
      for (final sampleId in ids) {
        await database.update(
          'panel_sampling_nodes',
          {'sampleNumber': 9},
          where: 'sampleId = ?',
          whereArgs: [sampleId],
        );
        await database.update(
          'panel_sample_serial_reservations',
          {'sampleNumber': 9},
          where: 'sampleId = ?',
          whereArgs: [sampleId],
        );
      }

      await repository.reconcileSerialCollision(
        sessionId: 'session-1',
        panelKey: 'candled_egg_breakout',
        conflictingNumber: 9,
        collidingSampleIds: ids.reversed.toList(),
      );
      final active = await repository.getActiveSerialRows(
        sessionId: 'session-1',
        panelKey: 'candled_egg_breakout',
      );
      final numbers = {
        for (final row in active) row['sampleId']: row['sampleNumber'],
      };
      expect(numbers[ids.first], 9);
      expect(numbers[ids.last], 10);

      final loser = (await database.query(
        'panel_sampling_nodes',
        where: 'sampleId = ?',
        whereArgs: [ids.last],
      )).single;
      await repository.deleteSubtree(nodeId: loser['id']! as String);
      final replacement = await repository.addTerminalSample(
        sessionId: 'session-1',
        panelKey: 'candled_egg_breakout',
        parentId: house.id,
        identity: const {'code': 'T4'},
      );
      expect(replacement.sampleNumber, 11);
    },
  );

  test(
    'uses dirty cutoffs and preserves pending local rows during remote upsert',
    () async {
      await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
      );
      final house = await repository.addScopeIdentity(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        parentId: null,
        level: SamplingScopeLevel.house,
        identity: const {'code': 'H01'},
      );
      final initialDirty = await repository.getDirtyRows(
        'panel_sampling_nodes',
      );
      final houseRow = initialDirty.singleWhere((row) => row['id'] == house.id);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await repository.updateScopeIdentity(
        nodeId: house.id,
        identity: const {'code': 'H02'},
      );
      await repository.markRowsSynced('panel_sampling_nodes', [house.id]);
      final afterCutoff = (await database.query(
        'panel_sampling_nodes',
        where: 'id = ?',
        whereArgs: [house.id],
      )).single;
      expect(afterCutoff['syncStatus'], 'pending');
      expect(houseRow['identityJson'], contains('H01'));

      await repository.upsertRemoteRow(
        tableName: 'panel_sampling_nodes',
        row: {
          ...afterCutoff,
          'identityKey': 'code=REMOTE',
          'identityJson': '{"code":"REMOTE"}',
          'syncStatus': 'synced',
          'dirtyAt': null,
        },
      );
      final preserved = (await database.query(
        'panel_sampling_nodes',
        where: 'id = ?',
        whereArgs: [house.id],
      )).single;
      expect(preserved['identityJson'], contains('H02'));
      expect(preserved['syncStatus'], 'pending');
      await repository.markRowsFailed('panel_sampling_nodes', [
        house.id,
      ], 'offline');
      expect(
        (await database.query(
          'panel_sampling_nodes',
          where: 'id = ?',
          whereArgs: [house.id],
        )).single['syncError'],
        'offline',
      );
    },
  );

  test(
    'remote grouping collision remaps local children without losing measurements',
    () async {
      await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
      );
      final house = await repository.addScopeIdentity(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        parentId: null,
        level: SamplingScopeLevel.house,
        identity: const {'code': 'H01'},
      );
      final sample = await repository.addTerminalSample(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        parentId: house.id,
      );
      await database.insert('egg_quality', {
        'id': 'collision-measurement',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'date': '2026-10-05',
        'house': 'H01',
        'sampleId': sample.sampleId,
        'sampleNumber': sample.sampleNumber,
        'eggSampleSize': 17,
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
      });
      final localParent = (await database.query(
        'panel_sampling_nodes',
        where: 'id = ?',
        whereArgs: [house.id],
      )).single;

      await repository.upsertRemoteRow(
        tableName: 'panel_sampling_nodes',
        row: {
          ...localParent,
          'id': 'remote-house-id',
          'syncStatus': 'synced',
          'dirtyAt': null,
          'lastSyncedAt': '2026-10-05T00:00:00.000Z',
          'syncError': null,
        },
      );

      final canonicalParent = (await database.query(
        'panel_sampling_nodes',
        where: 'id = ?',
        whereArgs: ['remote-house-id'],
      )).single;
      final childSample = (await database.query(
        'panel_sampling_nodes',
        where: 'sampleId = ?',
        whereArgs: [sample.sampleId],
      )).single;
      expect(
        await database.query(
          'panel_sampling_nodes',
          where: 'id = ?',
          whereArgs: [house.id],
        ),
        isEmpty,
      );
      expect(canonicalParent['syncStatus'], 'pending');
      expect(childSample['parentId'], 'remote-house-id');
      expect(childSample['syncStatus'], 'pending');
      expect(childSample['sampleId'], sample.sampleId);
      final measurement = (await database.query(
        'egg_quality',
        where: 'id = ?',
        whereArgs: ['collision-measurement'],
      )).single;
      expect(measurement['sampleId'], sample.sampleId);
      expect(measurement['eggSampleSize'], 17);
    },
  );

  test(
    'child-first remote pull merges nested matching groups and keeps both leaves',
    () async {
      await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'residue_breakout',
      );
      final localHouse = await repository.addScopeIdentity(
        sessionId: 'session-1',
        panelKey: 'residue_breakout',
        parentId: null,
        level: SamplingScopeLevel.house,
        identity: const {'code': 'H01', 'name': 'House One'},
      );
      final localSetter = await repository.addScopeIdentity(
        sessionId: 'session-1',
        panelKey: 'residue_breakout',
        parentId: localHouse.id,
        level: SamplingScopeLevel.setter,
        identity: const {'code': 'S1'},
      );
      final localSample = await repository.addTerminalSample(
        sessionId: 'session-1',
        panelKey: 'residue_breakout',
        parentId: localSetter.id,
        identity: const {'code': 'T1'},
      );
      await database.insert('residue_breakout', {
        'id': 'local-residue-row',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'date': '2026-10-05',
        'house': 'H01',
        'setter': 'S1',
        'tray': 'T1',
        'sampleId': localSample.sampleId,
        'sampleNumber': localSample.sampleNumber,
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
      });
      final localHouseRow = (await database.query(
        'panel_sampling_nodes',
        where: 'id = ?',
        whereArgs: [localHouse.id],
      )).single;
      final localSetterRow = (await database.query(
        'panel_sampling_nodes',
        where: 'id = ?',
        whereArgs: [localSetter.id],
      )).single;
      final localTerminalRow = (await database.query(
        'panel_sampling_nodes',
        where: 'sampleId = ?',
        whereArgs: [localSample.sampleId],
      )).single;

      await repository.upsertRemoteRow(
        tableName: 'panel_sampling_nodes',
        row: {
          ...localSetterRow,
          'id': 'remote-setter-id',
          'parentId': 'remote-house-id',
          'syncStatus': 'synced',
          'dirtyAt': null,
          'lastSyncedAt': '2026-10-05T00:00:00.000Z',
          'syncError': null,
        },
      );
      await repository.upsertRemoteRow(
        tableName: 'panel_sampling_nodes',
        row: {
          ...localTerminalRow,
          'id': 'remote-tray-id',
          'parentId': 'remote-setter-id',
          'identityKey': 'code=2',
          'identityJson': '{"code":"T2"}',
          'sampleId': 'remote-sample-id',
          'sampleNumber': 90,
          'syncStatus': 'synced',
          'dirtyAt': null,
          'lastSyncedAt': '2026-10-05T00:00:00.000Z',
          'syncError': null,
        },
      );
      await database.insert('residue_breakout', {
        'id': 'remote-residue-row',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'date': '2026-10-05',
        'house': 'H01',
        'setter': 'S1',
        'tray': 'T2',
        'sampleId': 'remote-sample-id',
        'sampleNumber': 90,
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
      });
      // The nested remote setter and leaf arrive before their house parent.
      await repository.upsertRemoteRow(
        tableName: 'panel_sampling_nodes',
        row: {
          ...localHouseRow,
          'id': 'remote-house-id',
          'syncStatus': 'synced',
          'dirtyAt': null,
          'lastSyncedAt': '2026-10-05T00:00:00.000Z',
          'syncError': null,
        },
      );

      final nodes = await database.query(
        'panel_sampling_nodes',
        where: 'sessionId = ? AND panelKey = ?',
        whereArgs: ['session-1', 'residue_breakout'],
      );
      expect(nodes.where((row) => row['id'] == localHouse.id), isEmpty);
      expect(nodes.where((row) => row['id'] == localSetter.id), isEmpty);
      expect(
        nodes.where((row) => row['id'] == 'remote-house-id'),
        hasLength(1),
      );
      expect(
        nodes.where((row) => row['id'] == 'remote-setter-id'),
        hasLength(1),
      );
      final localLeaf = nodes.singleWhere(
        (row) => row['sampleId'] == localSample.sampleId,
      );
      final remoteLeaf = nodes.singleWhere(
        (row) => row['sampleId'] == 'remote-sample-id',
      );
      expect(localLeaf['parentId'], 'remote-setter-id');
      expect(remoteLeaf['parentId'], 'remote-setter-id');
      expect(
        await database.query('residue_breakout', orderBy: 'id'),
        hasLength(2),
      );
    },
  );

  test(
    'serial assignment updates measurement JSON and raises the high-watermark',
    () async {
      final state = await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
      );
      final sample = state.samples.single;
      await database.insert('egg_quality', {
        'id': 'serial-measurement',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'date': '2026-10-05',
        'sampleId': sample.sampleId,
        'sampleNumber': sample.sampleNumber,
        'samplingPathJson': state.pathFor(sample.sampleId!).toJsonString(),
        'eggSampleSize': 5,
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
      });

      await repository.applySerialAssignments(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        assignments: {sample.sampleId!: 44},
      );

      final row = (await database.query('egg_quality')).single;
      expect(row['sampleNumber'], 44);
      expect(
        (jsonDecode(row['samplingPathJson']! as String) as Map)['sampleNumber'],
        44,
      );
      final updated = await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'egg_quality',
      );
      expect(updated.samples.single.sampleNumber, 44);
      expect(updated.serialHighWatermark, 44);
    },
  );

  test(
    'backfills legacy measurement IDs and values into a scoped state',
    () async {
      await database.insert('candled_egg_breakout', {
        'id': 'legacy-row-1',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'date': '2026-10-05',
        'house': 'Old House Label',
        'trolley': 'Old Trolley Label',
        'tray': 'Old Tray Label',
        'infertileCount': 7,
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
        'syncStatus': 'synced',
      });

      final state = await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'candled_egg_breakout',
      );
      final row = (await database.query('candled_egg_breakout')).single;
      expect(row['id'], 'legacy-row-1');
      expect(row['sampleId'], 'legacy-row-1');
      expect(row['sampleNumber'], 1);
      expect(row['infertileCount'], 7);
      expect(row['house'], 'Old House Label');
      expect(row['samplingPathJson'], contains('Old Tray Label'));
      expect(state.samples, hasLength(1));
      expect(state.samples.single.sampleId, 'legacy-row-1');
      expect(state.pathFor('legacy-row-1').house, 'Old House Label');
      expect(
        state.pathFor('legacy-row-1').unknownLevels,
        contains(SamplingScopeLevel.house),
      );
      final firstNodes = await database.query(
        'panel_sampling_nodes',
        where: 'sessionId = ? AND panelKey = ?',
        whereArgs: ['session-1', 'candled_egg_breakout'],
        orderBy: 'id',
      );
      final firstTrayNodes = firstNodes
          .where((row) => row['level'] == 'tray')
          .toList();
      expect(firstTrayNodes, hasLength(1));
      expect(firstTrayNodes.single['isTerminal'], 1);
      expect(firstNodes.where((row) => row['isTerminal'] == 1), hasLength(1));

      // A second offline device backfilling the same legacy rows must derive
      // the same hierarchy IDs, so the sync merge converges instead of
      // creating duplicate terminal samples.
      await DatabaseHelper().close();
      await useIsolatedAppDatabase();
      database = await DatabaseHelper().db;
      await database.insert('customers', {
        'id': 'customer-1',
        'name': 'Customer',
      });
      await database.insert('hatcheries', {
        'id': 'hatchery-1',
        'name': 'Hatchery',
        'customerId': 'customer-1',
      });
      await database.insert('flocks', {
        'id': 'flock-1',
        'customerId': 'customer-1',
        'breed': 'Breed',
      });
      await database.insert('audit_sessions', {
        'id': 'session-1',
        'customerId': 'customer-1',
        'flockId': 'flock-1',
        'hatcheryId': 'hatchery-1',
        'date': '2026-10-05',
      });
      await database.insert('candled_egg_breakout', {
        'id': 'legacy-row-1',
        'sessionId': 'session-1',
        'customerId': 'customer-1',
        'date': '2026-10-05',
        'house': 'Old House Label',
        'trolley': 'Old Trolley Label',
        'tray': 'Old Tray Label',
        'infertileCount': 7,
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
        'syncStatus': 'synced',
      });
      await repository.loadOrCreateDefault(
        sessionId: 'session-1',
        panelKey: 'candled_egg_breakout',
      );
      final secondNodes = await database.query(
        'panel_sampling_nodes',
        where: 'sessionId = ? AND panelKey = ?',
        whereArgs: ['session-1', 'candled_egg_breakout'],
        orderBy: 'id',
      );
      expect(
        secondNodes.map((row) => row['id']).toList(),
        firstNodes.map((row) => row['id']).toList(),
      );
      expect(secondNodes, hasLength(firstNodes.length));
      expect(secondNodes.where((row) => row['level'] == 'tray'), hasLength(1));
      expect(secondNodes.where((row) => row['isTerminal'] == 1), hasLength(1));
    },
  );
}
