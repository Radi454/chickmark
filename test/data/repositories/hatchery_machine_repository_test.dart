import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/hatchery_machine_model.dart';
import 'package:hatchaudit/data/repositories/hatchery_machine_repository.dart';
import 'package:hatchaudit/data/repositories/hatchery_repository.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Database db;
  late _MockDatabaseHelper dbHelper;
  late HatcheryMachineRepository repository;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''CREATE TABLE hatcheries (
      id TEXT PRIMARY KEY, customerId TEXT NOT NULL, name TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE hatchery_machines (
      id TEXT PRIMARY KEY, hatcheryId TEXT NOT NULL, kind TEXT NOT NULL,
      code TEXT NOT NULL, name TEXT NOT NULL, batchSize INTEGER NOT NULL,
      trolleyCapacity INTEGER NOT NULL, traySize INTEGER NOT NULL,
      trolleyCount INTEGER NOT NULL, traysPerTrolley INTEGER NOT NULL,
      createdAt TEXT, updatedAt TEXT, createdBy TEXT,
      syncStatus TEXT NOT NULL DEFAULT 'pending', dirtyAt TEXT,
      lastSyncedAt TEXT, syncError TEXT,
      UNIQUE(hatcheryId, kind, code),
      FOREIGN KEY(hatcheryId) REFERENCES hatcheries(id)
    )''');
    await db.execute('''CREATE TABLE sync_tombstones (
      id TEXT PRIMARY KEY, tableName TEXT NOT NULL, rowId TEXT NOT NULL,
      deletedAt TEXT NOT NULL, createdAt TEXT NOT NULL, syncedAt TEXT,
      lastError TEXT
    )''');
    await db.insert('hatcheries', {
      'id': 'h1',
      'customerId': 'c1',
      'name': 'Hatchery 1',
    });
    await db.insert('hatcheries', {
      'id': 'h2',
      'customerId': 'c1',
      'name': 'Hatchery 2',
    });
    dbHelper = _MockDatabaseHelper();
    when(() => dbHelper.db).thenAnswer((_) async => db);
    repository = HatcheryMachineRepository(dbHelper: dbHelper);
  });

  tearDown(() => db.close());

  HatcheryMachineModel machine({
    String id = 'machine-uuid',
    String hatcheryId = 'h1',
    String kind = 'setter',
    String code = 's-01',
    String name = 'Setter One',
    int batchSize = 19200,
    int trolleyCapacity = 4800,
    int traySize = 150,
    int trolleyCount = 4,
    int traysPerTrolley = 32,
  }) => HatcheryMachineModel(
    id: id,
    hatcheryId: hatcheryId,
    kind: kind,
    code: code,
    name: name,
    batchSize: batchSize,
    trolleyCapacity: trolleyCapacity,
    traySize: traySize,
    trolleyCount: trolleyCount,
    traysPerTrolley: traysPerTrolley,
  );

  test('capacity helper calculates and rounds up registered counts', () {
    expect(
      HatcheryMachineModel.calculateCounts(
        batchSize: 19201,
        trolleyCapacity: 4800,
        traySize: 151,
      ),
      (trolleyCount: 5, traysPerTrolley: 32),
    );
  });

  test('capacity helper rejects non-positive capacity values', () {
    expect(
      () => HatcheryMachineModel.calculateCounts(
        batchSize: 19200,
        trolleyCapacity: 0,
        traySize: 150,
      ),
      throwsArgumentError,
    );
  });

  test('save normalizes physical code and stores registered counts', () async {
    await repository.saveMachine(machine(code: '  s-01  '));
    final stored = await repository.getById('machine-uuid');
    expect(stored?.code, 'S-01');
    expect(stored?.trolleyCount, 4);
    expect(stored?.traysPerTrolley, 32);
    final raw = await repository.getRowById('machine-uuid');
    expect(raw?['syncStatus'], 'pending');
    expect(raw?['dirtyAt'], isNotNull);
  });

  test(
    'physical code is unique per hatchery and kind after normalization',
    () async {
      await repository.saveMachine(machine());
      await expectLater(
        repository.saveMachine(machine(id: 'another-uuid', code: ' S-01 ')),
        throwsArgumentError,
      );
      await repository.saveMachine(
        machine(id: 'hatcher-uuid', kind: 'hatcher', code: 'S-01'),
      );
      await repository.saveMachine(
        machine(id: 'other-hatchery-uuid', hatcheryId: 'h2', code: 'S-01'),
      );
    },
  );

  test(
    'editing by UUID keeps identity and updates registered capacities',
    () async {
      await repository.saveMachine(machine());
      await repository.saveMachine(
        machine(
          code: 'S-09',
          name: 'Renamed Setter',
          batchSize: 20000,
          trolleyCapacity: 5000,
          traySize: 200,
          trolleyCount: 4,
          traysPerTrolley: 25,
        ),
      );
      final edited = await repository.getById('machine-uuid');
      expect(edited?.code, 'S-09');
      expect(edited?.trolleyCount, 4);
      expect(edited?.traysPerTrolley, 25);
      expect(await repository.getById('missing'), isNull);
    },
  );

  test(
    'editing cannot move a machine UUID to another hatchery or kind',
    () async {
      await repository.saveMachine(machine());
      await expectLater(
        repository.saveMachine(machine(hatcheryId: 'h2')),
        throwsArgumentError,
      );
      await expectLater(
        repository.saveMachine(machine(kind: 'hatcher')),
        throwsArgumentError,
      );
      expect((await repository.getById('machine-uuid'))?.kind, 'setter');
      expect((await repository.getById('machine-uuid'))?.hatcheryId, 'h1');
    },
  );

  test('listing filters by hatchery and optional kind', () async {
    await repository.saveMachine(machine());
    await repository.saveMachine(
      machine(id: 'hatcher-uuid', kind: 'hatcher', code: 'H-01'),
    );
    expect((await repository.getByHatchery('h1')).length, 2);
    expect(
      (await repository.getByHatchery('h1', kind: 'setter')).single.id,
      'machine-uuid',
    );
  });

  test(
    'remote upsert is synced and dirty cutoff keeps a concurrent edit',
    () async {
      await repository.upsertRemoteRow({
        'id': 'machine-uuid',
        'hatchery_id': 'h1',
        'kind': 'setter',
        'code': 'S-01',
        'name': 'Setter One',
        'batch_size': 19200,
        'trolley_capacity': 4800,
        'tray_size': 150,
        'trolley_count': 4,
        'trays_per_trolley': 32,
      });
      expect(await repository.getRowSyncStatus('machine-uuid'), 'synced');
      final synced = await repository.getDirtyRows();
      expect(synced, isEmpty);

      await repository.saveMachine(machine());
      final dirty = await repository.getDirtyRows();
      expect(dirty.single['id'], 'machine-uuid');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repository.saveMachine(machine(name: 'Edited mid-push'));
      await repository.markRowsSynced(['machine-uuid']);
      final raw = await repository.getRowById('machine-uuid');
      expect(raw?['syncStatus'], 'pending');
      expect(raw?['dirtyAt'], isNotNull);
    },
  );

  test(
    'remote upsert surfaces duplicate physical IDs instead of dropping rows',
    () async {
      await repository.saveMachine(machine());
      await expectLater(
        repository.upsertRemoteRow({
          'id': 'remote-duplicate',
          'hatchery_id': 'h1',
          'kind': 'setter',
          'code': 'S-01',
          'name': 'Remote duplicate',
          'batch_size': 19200,
          'trolley_capacity': 4800,
          'tray_size': 150,
          'trolley_count': 4,
          'trays_per_trolley': 32,
        }),
        throwsA(anything),
      );
    },
  );

  test(
    'deleting a hatchery tombstones then removes its machine rows',
    () async {
      await repository.saveMachine(machine());
      await HatcheryRepository(dbHelper: dbHelper).deleteHatchery('h1');

      expect(await repository.getById('machine-uuid'), isNull);
      final tombstone = (await db.query(
        'sync_tombstones',
        where: 'tableName = ? AND rowId = ?',
        whereArgs: ['hatchery_machines', 'machine-uuid'],
      )).single;
      expect(tombstone['id'], 'hatchery_machines:machine-uuid');
      expect(await db.query('hatchery_machines'), isEmpty);
    },
  );
}
