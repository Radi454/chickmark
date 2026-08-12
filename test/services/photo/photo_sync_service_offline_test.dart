import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hatchaudit/data/models/photo_model.dart';
import 'package:hatchaudit/data/repositories/photo_repository.dart';
import 'package:hatchaudit/services/photo/photo_sync_service.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';

class _MockPhotoRepository extends Mock implements PhotoRepository {}

class _MockSupabaseService extends Mock implements SupabaseService {}

class _FakePhotoModel extends Fake implements PhotoModel {}

void main() {
  late _MockPhotoRepository repo;
  late _MockSupabaseService supabase;
  late PhotoSyncService service;
  late Directory tempDir;
  late PhotoModel photo;

  setUpAll(() {
    registerFallbackValue(_FakePhotoModel());
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync();
    final testFile = File('${tempDir.path}/does-not-matter.jpg');
    testFile.writeAsBytesSync([1, 2, 3]);

    photo = PhotoModel(
      id: 'photo-1',
      filePath: testFile.path,
      createdAt: DateTime(2026, 8, 1),
      sessionId: 'session-1',
      panelName: 'egg_storage',
      panelRowId: 'row-1',
      fieldKey: 'photo',
      uploadStatus: 'local',
    );

    repo = _MockPhotoRepository();
    supabase = _MockSupabaseService();
    service = PhotoSyncService(
      repository: repo,
      supabase: supabase,
      fileSyncSupported: true,
    );
    when(() => supabase.refreshAvailability()).thenAnswer((_) async => true);
    when(() => repo.getByStatus('local')).thenAnswer((_) async => [photo]);
    when(() => repo.getByStatus('failed')).thenAnswer((_) async => const []);
    when(() => repo.updateStatus(any(), any())).thenAnswer((_) async {});
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('a photo is marked failed, not synced, when upload throws offline',
      () async {
    when(() => supabase.uploadPhoto(any()))
        .thenThrow(StateError('Supabase sync is not available'));

    await service.syncPending();

    verify(() => repo.updateStatus('photo-1', 'failed')).called(1);
    verifyNever(() => repo.updateStatus('photo-1', 'synced'));
  });
}
