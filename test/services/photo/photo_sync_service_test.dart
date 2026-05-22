import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/photo_model.dart';
import 'package:hatchaudit/data/repositories/photo_repository.dart';
import 'package:hatchaudit/services/photo/photo_sync_service.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockPhotoRepository extends Mock implements PhotoRepository {}

class _MockSupabaseService extends Mock implements SupabaseService {}

void main() {
  setUpAll(() {
    registerFallbackValue(_photo('/tmp/fallback.jpg'));
  });

  test(
    'syncPending retries failed photos and marks successful upload synced',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('photo_sync_test');
      final file = File('${tempDir.path}/photo.jpg');
      await file.writeAsBytes([1, 2, 3]);
      final failedPhoto = _photo(file.path, uploadStatus: 'failed');
      final repo = _MockPhotoRepository();
      final supabase = _MockSupabaseService();

      when(() => supabase.refreshAvailability()).thenAnswer((_) async => true);
      when(() => repo.getByStatus('local')).thenAnswer((_) async => []);
      when(
        () => repo.getByStatus('failed'),
      ).thenAnswer((_) async => [failedPhoto]);
      when(() => supabase.uploadPhoto(failedPhoto)).thenAnswer((_) async {});
      when(
        () => repo.updateStatus(failedPhoto.id, 'synced'),
      ).thenAnswer((_) async {});

      await PhotoSyncService(
        repository: repo,
        supabase: supabase,
      ).syncPending();

      verify(() => supabase.uploadPhoto(failedPhoto)).called(1);
      verify(() => repo.updateStatus(failedPhoto.id, 'synced')).called(1);
      await tempDir.delete(recursive: true);
    },
  );
}

PhotoModel _photo(String filePath, {String uploadStatus = 'local'}) {
  return PhotoModel(
    id: 'photo-1',
    filePath: filePath,
    description: 'Evidence',
    createdAt: DateTime(2026, 5, 2),
    sessionId: 'session-1',
    panelName: 'chick_quality',
    panelRowId: 'chick-quality-row-1',
    fieldKey: 'cvtReadings',
    uploadStatus: uploadStatus,
  );
}
