import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/panel_sample_model.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockDatabaseHelper extends Mock implements DatabaseHelper {}

Future<void> _createPanelTable(
  Database db,
  String tableName,
  List<String> extraColumns,
) async {
  final isChick = tableName == 'chick_quality' || tableName == 'chick_weights';
  final identityColumns = isChick
      ? ', domain TEXT, schemaVersion INTEGER, scopeKey TEXT, replicate INTEGER, '
            'sampleKey TEXT, source TEXT, captureMethod TEXT, createdBy TEXT, '
            'deviceId TEXT, sourceRefId TEXT, observedAt TEXT'
      : '';
  final extra = extraColumns.isEmpty ? '' : ', ${extraColumns.join(', ')}';
  await db.execute('''CREATE TABLE $tableName (
    id TEXT PRIMARY KEY,
    sessionId TEXT NOT NULL,
    customerId TEXT NOT NULL,
    flockId TEXT,
    hatcheryId TEXT,
    date TEXT NOT NULL,
    breed TEXT,
    flockAgeWeeks INTEGER,
    house TEXT,
    setter TEXT,
    hatcher TEXT,
    trolley TEXT,
    tray TEXT,
    position TEXT,
    scopeType TEXT,
    storagePeriodDays INTEGER,
    bmkAgeWeeks INTEGER,
    notes TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    lastSyncedAt TEXT,
    syncError TEXT$identityColumns$extra,
    FOREIGN KEY (sessionId) REFERENCES audit_sessions(id) ON DELETE CASCADE,
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE,
    FOREIGN KEY (hatcheryId) REFERENCES hatcheries(id) ON DELETE CASCADE
  )''');
  if (isChick) {
    await db.execute(
      'CREATE UNIQUE INDEX idx_${tableName}_sample_key ON $tableName '
      '(customerId, sampleKey) WHERE sampleKey IS NOT NULL',
    );
  } else {
    await db.execute(
      "CREATE UNIQUE INDEX idx_${tableName}_unique_row ON $tableName (sessionId, IFNULL(house, ''), IFNULL(setter, ''), IFNULL(hatcher, ''), IFNULL(trolley, ''), IFNULL(tray, ''), IFNULL(position, ''))",
    );
  }
}

Future<void> _createMachineScopedPanelTable(
  Database db,
  String tableName, {
  required String machineColumn,
}) async {
  await db.execute('''CREATE TABLE $tableName (
    id TEXT PRIMARY KEY,
    sessionId TEXT NOT NULL,
    customerId TEXT NOT NULL,
    flockId TEXT,
    hatcheryId TEXT,
    date TEXT NOT NULL,
    breed TEXT,
    flockAgeWeeks INTEGER,
    $machineColumn TEXT,
    trolley TEXT,
    tray TEXT,
    storagePeriodDays INTEGER,
    bmkAgeWeeks INTEGER,
    notes TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    lastSyncedAt TEXT,
    syncError TEXT,
    estAvg REAL,
    FOREIGN KEY (sessionId) REFERENCES audit_sessions(id) ON DELETE CASCADE,
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE,
    FOREIGN KEY (hatcheryId) REFERENCES hatcheries(id) ON DELETE CASCADE
  )''');
  await db.execute(
    "CREATE UNIQUE INDEX idx_${tableName}_unique_row ON $tableName (sessionId, IFNULL($machineColumn, ''), IFNULL(trolley, ''), IFNULL(tray, ''))",
  );
}

void main() {
  late Database db;
  late MockDatabaseHelper dbHelper;
  late PanelSampleRepository repository;

  Future<Database> openPanelDatabase() async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    await database.execute('PRAGMA foreign_keys = ON');
    await database.execute('CREATE TABLE customers (id TEXT PRIMARY KEY)');
    await database.execute('''CREATE TABLE flocks (
      id TEXT PRIMARY KEY,
      customerId TEXT
    )''');
    await database.execute('''CREATE TABLE hatcheries (
      id TEXT PRIMARY KEY,
      customerId TEXT NOT NULL,
      name TEXT NOT NULL
    )''');
    await database.execute('''CREATE TABLE audit_sessions (
      id TEXT PRIMARY KEY,
      customerId TEXT NOT NULL,
      flockId TEXT NOT NULL,
      hatcheryId TEXT NOT NULL,
      date TEXT NOT NULL
    )''');
    await database.execute('''CREATE TABLE sync_tombstones (
      id TEXT PRIMARY KEY,
      tableName TEXT NOT NULL,
      rowId TEXT NOT NULL,
      deletedAt TEXT NOT NULL,
      createdAt TEXT NOT NULL,
      syncedAt TEXT,
      lastError TEXT
    )''');
    await _createPanelTable(database, 'egg_quality', const [
      'sampleSize INTEGER',
    ]);
    await _createPanelTable(database, 'chick_quality', const [
      'sampleSize INTEGER',
    ]);
    await _createPanelTable(database, 'chick_weights', const [
      'sampleSize INTEGER',
    ]);
    await database.insert('customers', {'id': 'customer-1'});
    await database.insert('flocks', {
      'id': 'flock-1',
      'customerId': 'customer-1',
    });
    await database.insert('hatcheries', {
      'id': 'hatchery-1',
      'customerId': 'customer-1',
      'name': 'Hatchery One',
    });
    await database.insert('audit_sessions', {
      'id': 'session-1',
      'customerId': 'customer-1',
      'flockId': 'flock-1',
      'hatcheryId': 'hatchery-1',
      'date': '2026-05-13',
    });
    return database;
  }

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    db = await openPanelDatabase();
    dbHelper = MockDatabaseHelper();
    when(() => dbHelper.db).thenAnswer((_) async => db);
    repository = PanelSampleRepository(databaseHelper: dbHelper);
  });

  tearDown(() async {
    await db.close();
  });

  test('savePanelWithSamples writes one pool sample by default', () async {
    final panel = PanelRecord(
      id: 'egg-quality-1',
      tableName: 'egg_quality',
      sessionId: 'session-1',
      customerId: 'customer-1',
      flockId: 'flock-1',
      date: DateTime.utc(2026, 5, 13),
      hatcheryId: 'hatchery-1',
      breed: 'Ross308',
      flockAgeWeeks: 40,
      metricsJson: '{"cracksPct":1.5}',
    );
    final sample = PanelSampleRecord(
      id: 'egg-quality-sample-1',
      panelId: panel.id,
      sampleSize: 100,
      summaryJson: '{"cracksPct":1.5}',
    );

    await repository.savePanelWithSamples(panel: panel, samples: [sample]);

    final rows = await db.query('egg_quality');

    expect(rows, hasLength(1));
    expect(rows.single['customerId'], 'customer-1');
    expect(rows.single['flockId'], 'flock-1');
    expect(rows.single['house'], isNull);
    expect(rows.single['setter'], isNull);
    expect(rows.single['hatcher'], isNull);
    expect(rows.single['tray'], isNull);
  });

  test('savePanelWithSamples writes explicit hierarchy columns', () async {
    final panel = PanelRecord(
      id: 'pasgar-1',
      tableName: 'chick_quality',
      sessionId: 'session-1',
      customerId: 'customer-1',
      flockId: 'flock-1',
      date: DateTime.utc(2026, 5, 13),
      hatcheryId: 'hatchery-1',
      storagePeriodDays: 4,
      bmkAgeWeeks: 40,
      metricsJson: '{"pasgarScore":97.5}',
    );
    final sample = PanelSampleRecord(
      id: 'pasgar-sample-1',
      panelId: panel.id,
      houseId: 'House A',
      setterId: 'S01',
      hatcherId: 'H02',
      trolleyId: 'T01',
      trayId: 'Tray 03',
      position: 'top',
      sampleSize: 100,
      summaryJson: '{"pasgarScore":97.5}',
    );

    await repository.savePanelWithSamples(panel: panel, samples: [sample]);

    final rows = await db.query('chick_quality');

    expect(rows, hasLength(1));
    expect(rows.single['house'], 'House A');
    expect(rows.single['setter'], 'S01');
    expect(rows.single['hatcher'], 'H02');
    expect(rows.single['trolley'], 'T01');
    expect(rows.single['tray'], 'Tray 03');
    expect(rows.single['position'], 'top');
    expect(rows.single['storagePeriodDays'], 4);
    expect(rows.single.keys, isNot(contains('bmkAgeDays')));
    expect(rows.single['bmkAgeWeeks'], 40);
    expect(rows.single['sampleSize'], 100);
  });

  test(
    'aggregate quality flags remain observable after repository save',
    () async {
      await repository.upsertRow(
        tableName: 'chick_quality',
        row: {
          'id': 'quality-flag-row',
          'sessionId': 'session-1',
          'customerId': 'customer-1',
          'date': '2026-05-13',
          'createdAt': '2026-05-13T00:00:00.000',
          'updatedAt': '2026-05-13T00:00:00.000',
          'pasgarSampleSize': 0,
          'pasgarReflexesCount': 1,
        },
      );

      expect(
        repository.lastQualityFlagsByTable['chick_quality'],
        contains('invalid_denominator'),
      );
    },
  );

  test('savePanelWithSamples writes one row per nested leaf scope', () async {
    final panel = PanelRecord(
      id: 'nested-scope-panel',
      tableName: 'chick_quality',
      sessionId: 'session-1',
      customerId: 'customer-1',
      flockId: 'flock-1',
      date: DateTime.utc(2026, 5, 13),
      hatcheryId: 'hatchery-1',
    );
    final samples = <PanelSampleRecord>[];
    var index = 0;

    for (var house = 1; house <= 2; house++) {
      for (var machine = 1; machine <= 2; machine++) {
        final machineIndex = ((house - 1) * 2) + machine;
        for (var trolley = 1; trolley <= 2; trolley++) {
          for (var tray = 1; tray <= 2; tray++) {
            index += 1;
            samples.add(
              PanelSampleRecord(
                id: 'nested-scope-sample-$index',
                panelId: panel.id,
                houseId: 'H$house',
                setterId: 'S$machineIndex',
                hatcherId: 'H$machineIndex',
                trolleyId: 'T$trolley',
                trayId: 'Tray $tray',
                sampleIndex: index,
              ),
            );
          }
        }
      }
    }

    await repository.savePanelWithSamples(panel: panel, samples: samples);

    final rows = await db.query(
      'chick_quality',
      orderBy: 'house ASC, setter ASC, trolley ASC, tray ASC',
    );

    expect(rows, hasLength(16));
    expect(rows.where((row) => row['house'] == 'H1'), hasLength(8));
    expect(rows.where((row) => row['house'] == 'H2'), hasLength(8));
    expect(rows.where((row) => row['setter'] == 'S1'), hasLength(4));
    expect(rows.where((row) => row['setter'] == 'S4'), hasLength(4));
    expect(rows.first['house'], 'H1');
    expect(rows.first['setter'], 'S1');
    expect(rows.first['hatcher'], 'H1');
    expect(rows.first['trolley'], 'T1');
    expect(rows.first['tray'], 'Tray 1');
  });

  test(
    'savePanelWithSamples omits orphaned hatchery ids from nullable panel rows',
    () async {
      await db.insert('audit_sessions', {
        'id': 'session-orphan-hatchery',
        'customerId': 'customer-1',
        'flockId': 'flock-1',
        'hatcheryId': 'missing-hatchery',
        'date': '2026-05-13',
      });
      final panel = PanelRecord(
        id: 'egg-quality-orphan-hatchery',
        tableName: 'egg_quality',
        sessionId: 'session-orphan-hatchery',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: DateTime.utc(2026, 5, 13),
        hatcheryId: 'missing-hatchery',
      );
      final sample = PanelSampleRecord(
        id: 'egg-quality-orphan-hatchery-sample',
        panelId: panel.id,
        sampleSize: 100,
      );

      await repository.savePanelWithSamples(panel: panel, samples: [sample]);

      final rows = await db.query(
        'egg_quality',
        where: 'id = ?',
        whereArgs: [sample.id],
      );

      expect(rows, hasLength(1));
      expect(rows.single['sessionId'], 'session-orphan-hatchery');
      expect(rows.single['hatcheryId'], isNull);
    },
  );

  test('same Chick hierarchy preserves different ids as replicates', () async {
    final panel = PanelRecord(
      id: 'weights-panel',
      tableName: 'chick_weights',
      sessionId: 'session-1',
      customerId: 'customer-1',
      flockId: 'flock-1',
      date: DateTime.utc(2026, 5, 13),
    );
    final first = PanelSampleRecord(
      id: 'weights-sample-1',
      panelId: panel.id,
      houseId: 'House A',
      scopeType: SamplingLayer.house,
      sampleSize: 80,
    );
    final second = PanelSampleRecord(
      id: 'weights-sample-2',
      panelId: panel.id,
      houseId: 'House A',
      scopeType: SamplingLayer.house,
      sampleSize: 90,
    );

    await repository.savePanelWithSamples(panel: panel, samples: [first]);
    await repository.savePanelWithSamples(panel: panel, samples: [second]);

    final rows = await db.query('chick_weights');
    expect(rows, hasLength(2));
    expect(rows.map((row) => row['id']).toSet(), {
      'weights-sample-1',
      'weights-sample-2',
    });
    expect(rows.map((row) => row['replicate']).toSet(), {1, 2});
    expect(rows.map((row) => row['sampleSize']).toSet(), {80, 90});
  });

  test(
    'moving an existing scoped id never absorbs or tombstones another id',
    () async {
      final panel = PanelRecord(
        id: 'quality-panel',
        tableName: 'chick_quality',
        sessionId: 'session-1',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: DateTime.utc(2026, 5, 13),
      );
      final pooled = PanelSampleRecord(
        id: 'quality-pooled-row',
        panelId: panel.id,
        sampleSize: 40,
      );
      final scoped = PanelSampleRecord(
        id: 'quality-scoped-row',
        panelId: panel.id,
        houseId: 'H1',
        setterId: 'S1',
        hatcherId: 'H1',
        scopeType: SamplingLayer.setterHatcher,
        sampleSize: 50,
      );

      await repository.savePanelWithSamples(panel: panel, samples: [pooled]);
      await repository.savePanelWithSamples(panel: panel, samples: [scoped]);

      await repository.savePanelWithSamples(
        panel: panel,
        samples: [
          PanelSampleRecord(id: scoped.id, panelId: panel.id, sampleSize: 60),
        ],
      );

      final rows = await db.query('chick_quality', orderBy: 'id ASC');
      expect(rows, hasLength(2));
      final byId = {for (final row in rows) row['id'] as String: row};
      expect(byId.keys, {pooled.id, scoped.id});
      expect(byId[pooled.id]!['sampleSize'], 40);
      expect(byId[scoped.id]!['sampleSize'], 60);
      expect(
        byId[scoped.id]!['sampleKey'],
        isNot(byId[pooled.id]!['sampleKey']),
      );

      final tombstones = await db.query('sync_tombstones');
      expect(tombstones, isEmpty);
    },
  );

  test('id-keyed hierarchy prune keeps only exact persisted ids', () async {
    final panel = PanelRecord(
      id: 'quality-panel',
      tableName: 'egg_quality',
      sessionId: 'session-1',
      customerId: 'customer-1',
      flockId: 'flock-1',
      date: DateTime.utc(2026, 5, 13),
    );
    final first = PanelSampleRecord(
      id: 'quality-sample-1',
      panelId: panel.id,
      houseId: 'H1',
      sampleSize: 100,
    );
    final second = PanelSampleRecord(
      id: 'quality-sample-2',
      panelId: panel.id,
      houseId: 'H2',
      sampleSize: 100,
    );
    final pooled = PanelSampleRecord(
      id: 'quality-sample-pool',
      panelId: panel.id,
      sampleSize: 100,
    );

    await repository.savePanelWithSamples(panel: panel, samples: [first]);
    await repository.savePanelWithSamples(panel: panel, samples: [second]);
    await repository.savePanelWithSamples(panel: panel, samples: [pooled]);

    await repository.deleteHierarchyRowsBySessionIdExcept(
      'egg_quality',
      'session-1',
      [first.id],
    );

    final rows = await db.query('egg_quality', orderBy: 'id ASC');
    expect(rows.map((row) => row['id']), ['quality-sample-1']);
    expect(rows.single['house'], 'H1');

    final tombstones = await db.query('sync_tombstones');
    expect(tombstones, hasLength(2));
    expect(tombstones.map((row) => row['tableName']).toSet(), {'egg_quality'});
    expect(tombstones.map((row) => row['rowId']).toSet(), {
      'quality-sample-2',
      'quality-sample-pool',
    });
  });

  test(
    'savePanelWithSamples works with machine-scoped setter hierarchy only',
    () async {
      await _createMachineScopedPanelTable(
        db,
        'setter_optimizing',
        machineColumn: 'setter',
      );
      final panel = PanelRecord(
        id: 'setter-panel',
        tableName: 'setter_optimizing',
        sessionId: 'session-1',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: DateTime.utc(2026, 5, 13),
        hatcheryId: 'hatchery-1',
        values: const {'estAvg': 100.5},
      );

      await repository.savePanelWithSamples(
        panel: panel,
        samples: [
          PanelSampleRecord(
            id: 'setter-machine',
            panelId: panel.id,
            setterId: 'S1',
            hatcherId: 'ignored',
            houseId: 'ignored',
          ),
        ],
      );
      await repository.savePanelWithSamples(
        panel: panel,
        samples: [
          PanelSampleRecord(
            id: 'setter-machine-trolley',
            panelId: panel.id,
            setterId: 'S1',
            trolleyId: 'T1',
            trayId: 'Tray 1',
          ),
        ],
      );

      final rows = await repository.getRowsBySessionId(
        'setter_optimizing',
        'session-1',
      );

      expect(rows, hasLength(2));
      expect(rows.first.keys, isNot(contains('house')));
      expect(rows.first.keys, isNot(contains('hatcher')));
      expect(rows.first['setter'], 'S1');
      expect(rows.last['trolley'], 'T1');
      expect(rows.last['tray'], 'Tray 1');
    },
  );
}
