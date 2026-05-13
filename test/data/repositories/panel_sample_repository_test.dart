import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/panel_sample_model.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockDatabaseHelper extends Mock implements DatabaseHelper {}

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
      customerId TEXT,
      FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE
    )''');
    await database.execute('''CREATE TABLE hatcheries (
      id TEXT PRIMARY KEY,
      customerId TEXT NOT NULL,
      name TEXT NOT NULL,
      FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE
    )''');
    await database.execute('''CREATE TABLE audit_sessions (
      id TEXT PRIMARY KEY,
      customerId TEXT NOT NULL,
      flockId TEXT NOT NULL,
      hatcheryId TEXT NOT NULL,
      date TEXT NOT NULL,
      FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE,
      FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE,
      FOREIGN KEY (hatcheryId) REFERENCES hatcheries(id) ON DELETE CASCADE
    )''');
    await database.execute('CREATE TABLE audits (id TEXT PRIMARY KEY)');
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
    await DatabaseHelper().applyV32UpgradeForTest(database);
    return database;
  }

  setUpAll(sqfliteFfiInit);

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

    final panels = await db.query('egg_quality');
    final samples = await db.query('egg_quality_samples');

    expect(panels, hasLength(1));
    expect(panels.single['mode'], PanelRecord.modePool);
    expect(panels.single['customerId'], 'customer-1');
    expect(panels.single['flockId'], 'flock-1');
    expect(samples, hasLength(1));
    expect(samples.single['scopeType'], 'pool');
    expect(samples.single['scopeLabel'], 'Random');
    expect(samples.single['sampleSize'], 100);
  });

  test(
    'savePanelWithSamples writes setter+hatcher comparison with both machine ids',
    () async {
      final panel = PanelRecord(
        id: 'pasgar-1',
        tableName: 'chick_pasgar',
        sessionId: 'session-1',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: DateTime.utc(2026, 5, 13),
        hatcheryId: 'hatchery-1',
        mode: PanelRecord.modeCompare,
        compareLayer: SamplingLayer.setterHatcher,
        metricsJson: '{"pasgarScore":97.5}',
      );
      final sample = PanelSampleRecord(
        id: 'pasgar-sample-1',
        panelId: panel.id,
        scopeType: SamplingLayer.setterHatcher,
        scopeLabel: 'S01 + H02',
        setterId: 'S01',
        hatcherId: 'H02',
        sampleSize: 100,
        summaryJson: '{"pasgarScore":97.5}',
      );

      await repository.savePanelWithSamples(panel: panel, samples: [sample]);

      final panels = await db.query('chick_pasgar');
      final samples = await db.query('chick_pasgar_samples');

      expect(panels.single['mode'], PanelRecord.modeCompare);
      expect(panels.single['compareLayer'], 'setter_hatcher');
      expect(samples.single['scopeType'], 'setter_hatcher');
      expect(samples.single['setterId'], 'S01');
      expect(samples.single['hatcherId'], 'H02');
    },
  );

  test(
    'savePanelWithSamples rejects disallowed tray comparison for chick weights',
    () {
      final panel = PanelRecord(
        id: 'weights-1',
        tableName: 'chick_weights',
        sessionId: 'session-1',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: DateTime.utc(2026, 5, 13),
        mode: PanelRecord.modeCompare,
        compareLayer: SamplingLayer.tray,
      );
      final sample = PanelSampleRecord(
        id: 'weights-sample-1',
        panelId: panel.id,
        scopeType: SamplingLayer.tray,
        scopeLabel: 'Tray 1',
        trayId: 'tray-1',
      );

      expect(
        () => repository.savePanelWithSamples(panel: panel, samples: [sample]),
        throwsArgumentError,
      );
    },
  );
}
