import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/repositories/photo_repository.dart';
import 'package:hatchaudit/data/repositories/sync_tombstone_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PhotoRepository repository;
  late Directory tempDirectory;

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  setUp(() async {
    await _resetDatabase();
    repository = PhotoRepository();
    tempDirectory = await Directory.systemTemp.createTemp(
      'photo_repository_test_',
    );
    await _insertSessionFixture();
  });

  tearDown(() async {
    await DatabaseHelper().close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'reconcileLocalPaths rebases a stale path to the current documents directory',
    () async {
      final current = File(p.join(tempDirectory.path, 'breakout.jpg'));
      await current.writeAsBytes([1, 2, 3]);
      await _insertPhoto('/old/container/Documents/breakout.jpg');

      await repository.reconcileLocalPaths(tempDirectory.path);

      expect((await repository.getAllPhotos()).single.filePath, current.path);
    },
  );

  test('upsertPhoto preserves an existing usable local file', () async {
    final local = File(p.join(tempDirectory.path, 'breakout.jpg'));
    await local.writeAsBytes([1]);
    await _insertPhoto(local.path);

    await repository.upsertPhoto(_remotePhotoRow());

    expect((await repository.getAllPhotos()).single.filePath, local.path);
  });

  test(
    'upsertPhoto accepts the remote path when the local file is missing',
    () async {
      await _insertPhoto('/missing/container/Documents/breakout.jpg');

      await repository.upsertPhoto(_remotePhotoRow());

      expect(
        (await repository.getAllPhotos()).single.filePath,
        'supabase://photos/session-1/residue_breakout/row-1/photo-1.jpg',
      );
    },
  );

  test('deleteByFilePath removes the photo row and local file', () async {
    final local = File(p.join(tempDirectory.path, 'obsolete-breakout.jpg'));
    await local.writeAsBytes([1, 2, 3]);
    await _insertPhoto(local.path);

    await repository.deleteByFilePath(local.path);

    expect(await repository.getByFilePath(local.path), isNull);
    expect(await local.exists(), isFalse);
    final tombstone =
        (await SyncTombstoneRepository().getPendingDeletes()).single;
    expect(tombstone.tableName, 'photos');
    expect(tombstone.rowId, 'photo-1');
  });
}

Future<void> _insertSessionFixture() async {
  final db = await DatabaseHelper().db;
  await db.insert('customers', {
    'id': 'customer-1',
    'name': 'Customer 1',
    'createdAt': '2026-07-04T00:00:00.000Z',
  });
  await db.insert('flocks', {
    'id': 'flock-1',
    'customerId': 'customer-1',
    'flockId': 'Flock 1',
    'entryDate': '2026-01-01',
  });
  await db.insert('hatcheries', {
    'id': 'hatchery-1',
    'customerId': 'customer-1',
    'name': 'Hatchery 1',
    'createdAt': '2026-07-04T00:00:00.000Z',
  });
  await db.insert('audit_sessions', {
    'id': 'session-1',
    'customerId': 'customer-1',
    'flockId': 'flock-1',
    'hatcheryId': 'hatchery-1',
    'date': '2026-07-04',
    'createdAt': '2026-07-04T00:00:00.000Z',
    'updatedAt': '2026-07-04T00:00:00.000Z',
  });
}

Future<void> _insertPhoto(String filePath) async {
  final db = await DatabaseHelper().db;
  await db.insert('photos', {
    'id': 'photo-1',
    'filePath': filePath,
    'description': 'Breakout evidence',
    'createdAt': '2026-07-04T00:00:00.000Z',
    'sessionId': 'session-1',
    'panelName': 'residue_breakout',
    'panelRowId': 'row-1',
    'fieldKey': 'breakout_photo',
    'uploadStatus': 'synced',
  });
}

Map<String, dynamic> _remotePhotoRow() {
  return {
    'id': 'photo-1',
    'file_path':
        'supabase://photos/session-1/residue_breakout/row-1/photo-1.jpg',
    'description': 'Breakout evidence',
    'created_at': '2026-07-04T00:00:00.000Z',
    'session_id': 'session-1',
    'panel_name': 'residue_breakout',
    'panel_row_id': 'row-1',
    'field_key': 'breakout_photo',
    'upload_status': 'synced',
  };
}

Future<void> _resetDatabase() async {
  await DatabaseHelper().close();
  final dbPath = p.join(
    await databaseFactory.getDatabasesPath(),
    'hatchaudit.db',
  );
  await databaseFactory.deleteDatabase(dbPath);
}
