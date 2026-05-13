import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openInMemoryDatabase() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('PRAGMA foreign_keys = ON');
  return db;
}

Future<void> _createPreIntegritySchema(Database db) async {
  await db.execute('''CREATE TABLE customers (
    id TEXT PRIMARY KEY,
    name TEXT,
    location TEXT,
    phone TEXT,
    email TEXT,
    createdAt TEXT,
    createdBy TEXT
  )''');
  await db.execute('''CREATE TABLE flocks (
    id TEXT PRIMARY KEY,
    customerId TEXT,
    flockId TEXT,
    breed TEXT,
    entryDate TEXT,
    status TEXT NOT NULL DEFAULT 'active'
  )''');
  await db.execute('''CREATE TABLE hatcheries (
    id TEXT PRIMARY KEY,
    customerId TEXT NOT NULL,
    name TEXT NOT NULL,
    location TEXT,
    notes TEXT,
    createdAt TEXT,
    createdBy TEXT
  )''');
  await db.execute('''CREATE TABLE audit_sessions (
    id TEXT PRIMARY KEY,
    customerId TEXT NOT NULL,
    flockId TEXT NOT NULL,
    hatcheryId TEXT NOT NULL,
    date TEXT NOT NULL,
    status TEXT DEFAULT 'in_progress',
    createdAt TEXT,
    updatedAt TEXT
  )''');
  await db.execute('''CREATE TABLE audits (
    id TEXT PRIMARY KEY,
    customerId TEXT,
    flockId TEXT,
    auditType TEXT,
    date TEXT,
    hatchNumber INTEGER NOT NULL DEFAULT 1,
    setterId TEXT,
    hatcherId TEXT,
    sessionId TEXT,
    createdAt TEXT,
    updatedAt TEXT
  )''');
  await db.execute('''CREATE TABLE photos (
    id TEXT PRIMARY KEY,
    filePath TEXT,
    auditId TEXT,
    uploadStatus TEXT NOT NULL DEFAULT 'local'
  )''');
  await db.execute('''CREATE TABLE activity_log (
    id TEXT PRIMARY KEY,
    userId TEXT NOT NULL,
    action TEXT NOT NULL,
    entityType TEXT,
    entityId TEXT,
    details TEXT,
    timestamp TEXT NOT NULL
  )''');
  await db.execute('''CREATE TABLE sample_records (
    id TEXT PRIMARY KEY,
    auditSessionId TEXT NOT NULL,
    legacyAuditId TEXT,
    stationType TEXT NOT NULL,
    sectorType TEXT NOT NULL DEFAULT 'station',
    sampleKind TEXT NOT NULL DEFAULT 'pooled',
    sampleMode TEXT NOT NULL DEFAULT 'pooled',
    sampleIndex INTEGER NOT NULL DEFAULT 1,
    groupKey TEXT,
    calculatedBmkAgeDays INTEGER,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    FOREIGN KEY (auditSessionId) REFERENCES audit_sessions(id) ON DELETE CASCADE,
    FOREIGN KEY (legacyAuditId) REFERENCES audits(id) ON DELETE CASCADE
  )''');
  await db.execute('''CREATE TABLE sample_house_details (
    sampleRecordId TEXT PRIMARY KEY,
    houseNo TEXT,
    FOREIGN KEY (sampleRecordId) REFERENCES sample_records(id) ON DELETE CASCADE
  )''');
  await db.execute('''CREATE TABLE govee_daily_captures (
    id TEXT PRIMARY KEY,
    customerId TEXT NOT NULL,
    hatcheryId TEXT NOT NULL,
    stationKey TEXT NOT NULL DEFAULT '',
    place TEXT NOT NULL,
    machineId TEXT NOT NULL DEFAULT '',
    captureDate TEXT NOT NULL,
    status TEXT NOT NULL,
    readingCount INTEGER NOT NULL,
    chartPointsJson TEXT NOT NULL DEFAULT '[]',
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    UNIQUE(customerId, hatcheryId, place, machineId, captureDate)
  )''');
  await DatabaseHelper().applyV32UpgradeForTest(db);
}

Future<void> _insertValidGraph(Database db) async {
  const now = '2026-05-13T08:00:00.000';
  await db.insert('customers', {'id': 'customer-1', 'name': 'Farm One'});
  await db.insert('flocks', {
    'id': 'flock-1',
    'customerId': 'customer-1',
    'flockId': 'F-1',
    'breed': 'Ross308',
    'entryDate': '2026-01-01',
    'status': 'active',
  });
  await db.insert('hatcheries', {
    'id': 'hatchery-1',
    'customerId': 'customer-1',
    'name': 'Hatchery One',
  });
  await db.insert('audit_sessions', {
    'id': 'session-1',
    'customerId': 'customer-1',
    'flockId': 'flock-1',
    'hatcheryId': 'hatchery-1',
    'date': '2026-05-13',
    'createdAt': now,
    'updatedAt': now,
  });
  await db.insert('audits', {
    'id': 'audit-1',
    'customerId': 'customer-1',
    'flockId': 'flock-1',
    'auditType': 'Chicks',
    'date': '2026-05-13',
    'hatchNumber': 1,
    'sessionId': 'session-1',
    'createdAt': now,
    'updatedAt': now,
  });
  await db.insert('photos', {
    'id': 'photo-1',
    'filePath': '/tmp/photo.jpg',
    'auditId': 'audit-1',
    'uploadStatus': 'local',
  });
  await db.insert('sample_records', {
    'id': 'sample-1',
    'auditSessionId': 'session-1',
    'legacyAuditId': 'audit-1',
    'stationType': 'Chicks',
    'createdAt': now,
    'updatedAt': now,
  });
  await db.insert('sample_house_details', {
    'sampleRecordId': 'sample-1',
    'houseNo': 'H1',
  });
  await db.insert('govee_daily_captures', {
    'id': 'capture-1',
    'customerId': 'customer-1',
    'hatcheryId': 'hatchery-1',
    'stationKey': 'chicks',
    'place': 'chickHoldingArea',
    'machineId': '',
    'captureDate': '2026-05-13',
    'status': 'completed',
    'readingCount': 0,
    'chartPointsJson': '[]',
    'createdAt': now,
    'updatedAt': now,
  });
  await db.insert('chick_pasgar', {
    'id': 'panel-1',
    'sessionId': 'session-1',
    'auditId': 'audit-1',
    'customerId': 'customer-1',
    'flockId': 'flock-1',
    'date': '2026-05-13T00:00:00.000Z',
    'hatcheryId': 'hatchery-1',
    'mode': 'pool',
    'createdAt': now,
    'updatedAt': now,
  });
  await db.insert('chick_pasgar_samples', {
    'id': 'panel-sample-1',
    'panelId': 'panel-1',
    'scopeType': 'pool',
    'scopeLabel': 'Random',
    'sampleIndex': 0,
    'createdAt': now,
    'updatedAt': now,
  });
}

Future<List<Map<String, Object?>>> _foreignKeys(Database db, String table) {
  return db.rawQuery("PRAGMA foreign_key_list('$table')");
}

bool _hasForeignKey(
  List<Map<String, Object?>> rows, {
  required String from,
  required String table,
  required String onDelete,
}) {
  return rows.any(
    (row) =>
        row['from'] == from &&
        row['table'] == table &&
        row['on_delete'] == onDelete,
  );
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('v34 migration adds foreign keys to logical parent links', () async {
    final db = await _openInMemoryDatabase();
    addTearDown(db.close);
    await _createPreIntegritySchema(db);
    await _insertValidGraph(db);

    await DatabaseHelper().applyV34UpgradeForTest(db);

    expect(
      _hasForeignKey(
        await _foreignKeys(db, 'flocks'),
        from: 'customerId',
        table: 'customers',
        onDelete: 'CASCADE',
      ),
      isTrue,
    );
    expect(
      _hasForeignKey(
        await _foreignKeys(db, 'hatcheries'),
        from: 'customerId',
        table: 'customers',
        onDelete: 'CASCADE',
      ),
      isTrue,
    );
    final sessionKeys = await _foreignKeys(db, 'audit_sessions');
    expect(
      _hasForeignKey(
        sessionKeys,
        from: 'customerId',
        table: 'customers',
        onDelete: 'CASCADE',
      ),
      isTrue,
    );
    expect(
      _hasForeignKey(
        sessionKeys,
        from: 'flockId',
        table: 'flocks',
        onDelete: 'CASCADE',
      ),
      isTrue,
    );
    expect(
      _hasForeignKey(
        sessionKeys,
        from: 'hatcheryId',
        table: 'hatcheries',
        onDelete: 'CASCADE',
      ),
      isTrue,
    );
    final auditKeys = await _foreignKeys(db, 'audits');
    expect(
      _hasForeignKey(
        auditKeys,
        from: 'customerId',
        table: 'customers',
        onDelete: 'CASCADE',
      ),
      isTrue,
    );
    expect(
      _hasForeignKey(
        auditKeys,
        from: 'flockId',
        table: 'flocks',
        onDelete: 'CASCADE',
      ),
      isTrue,
    );
    expect(
      _hasForeignKey(
        await _foreignKeys(db, 'photos'),
        from: 'auditId',
        table: 'audits',
        onDelete: 'CASCADE',
      ),
      isTrue,
    );
    expect(
      _hasForeignKey(
        await _foreignKeys(db, 'govee_daily_captures'),
        from: 'hatcheryId',
        table: 'hatcheries',
        onDelete: 'CASCADE',
      ),
      isTrue,
    );
    expect(
      _hasForeignKey(
        await _foreignKeys(db, 'chick_pasgar'),
        from: 'sessionId',
        table: 'audit_sessions',
        onDelete: 'CASCADE',
      ),
      isTrue,
    );
  });

  test(
    'v34 migration preserves valid rows while nulling dangling optional refs',
    () async {
      final db = await _openInMemoryDatabase();
      addTearDown(db.close);
      await _createPreIntegritySchema(db);
      await _insertValidGraph(db);
      await db.insert('photos', {
        'id': 'legacy-orphan-photo',
        'filePath': '/tmp/orphan.jpg',
        'auditId': 'missing-audit',
        'uploadStatus': 'local',
      });

      await DatabaseHelper().applyV34UpgradeForTest(db);

      expect(await db.query('customers'), hasLength(1));
      expect(await db.query('flocks'), hasLength(1));
      expect(await db.query('hatcheries'), hasLength(1));
      expect(await db.query('audit_sessions'), hasLength(1));
      expect(await db.query('audits'), hasLength(1));
      expect(await db.query('sample_records'), hasLength(1));
      expect(await db.query('sample_house_details'), hasLength(1));
      expect(await db.query('govee_daily_captures'), hasLength(1));
      expect(await db.query('chick_pasgar'), hasLength(1));
      expect(await db.query('chick_pasgar_samples'), hasLength(1));

      final orphanPhoto = await db.query(
        'photos',
        where: 'id = ?',
        whereArgs: ['legacy-orphan-photo'],
      );
      expect(orphanPhoto.single['auditId'], isNull);
    },
  );

  test(
    'foreign keys reject invalid parent inserts after v34 migration',
    () async {
      final db = await _openInMemoryDatabase();
      addTearDown(db.close);
      await _createPreIntegritySchema(db);
      await _insertValidGraph(db);
      await DatabaseHelper().applyV34UpgradeForTest(db);

      expect(
        () => db.insert('flocks', {
          'id': 'bad-flock',
          'customerId': 'missing-customer',
        }),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        () => db.insert('audit_sessions', {
          'id': 'bad-session',
          'customerId': 'customer-1',
          'flockId': 'missing-flock',
          'hatcheryId': 'hatchery-1',
          'date': '2026-05-13',
        }),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        () => db.insert('photos', {
          'id': 'bad-photo',
          'filePath': '/tmp/bad.jpg',
          'auditId': 'missing-audit',
        }),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        () => db.insert('chick_pasgar_samples', {
          'id': 'bad-panel-sample',
          'panelId': 'missing-panel',
          'scopeType': SamplingLayer.pool.dbValue,
          'scopeLabel': 'Random',
          'createdAt': '2026-05-13T08:00:00.000',
          'updatedAt': '2026-05-13T08:00:00.000',
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'foreign key cascades clean audit, session, and customer children',
    () async {
      final db = await _openInMemoryDatabase();
      addTearDown(db.close);
      await _createPreIntegritySchema(db);
      await _insertValidGraph(db);
      await DatabaseHelper().applyV34UpgradeForTest(db);

      await db.delete('audits', where: 'id = ?', whereArgs: ['audit-1']);
      expect(await db.query('photos'), isEmpty);
      expect(await db.query('sample_records'), isEmpty);
      expect(await db.query('sample_house_details'), isEmpty);
      final panelAfterAuditDelete = await db.query('chick_pasgar');
      expect(panelAfterAuditDelete.single['auditId'], isNull);

      await db.insert('audits', {
        'id': 'audit-2',
        'customerId': 'customer-1',
        'flockId': 'flock-1',
        'auditType': 'Chicks',
        'date': '2026-05-13',
        'hatchNumber': 1,
      });
      await db.insert('sample_records', {
        'id': 'sample-2',
        'auditSessionId': 'session-1',
        'legacyAuditId': 'audit-2',
        'stationType': 'Chicks',
        'createdAt': '2026-05-13T08:00:00.000',
        'updatedAt': '2026-05-13T08:00:00.000',
      });

      await db.delete(
        'audit_sessions',
        where: 'id = ?',
        whereArgs: ['session-1'],
      );
      expect(await db.query('sample_records'), isEmpty);
      expect(await db.query('chick_pasgar'), isEmpty);
      expect(await db.query('chick_pasgar_samples'), isEmpty);

      await db.delete('customers', where: 'id = ?', whereArgs: ['customer-1']);
      expect(await db.query('flocks'), isEmpty);
      expect(await db.query('hatcheries'), isEmpty);
      expect(await db.query('audits'), isEmpty);
      expect(await db.query('govee_daily_captures'), isEmpty);
    },
  );
}
