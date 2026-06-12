import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/photo_model.dart';
import 'package:hatchaudit/data/repositories/photo_repository.dart';
import 'package:hatchaudit/services/photo/photo_sync_service.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:image/image.dart' as img;
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

  test(
    'syncPending shrinks an oversize photo in place then uploads it',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('photo_sync_big');
      final file = File('${tempDir.path}/big.jpg');
      await file.writeAsBytes(_texturedJpeg(2000, 1500));
      final originalSize = await file.length();

      final photo = _photo(file.path);
      final repo = _MockPhotoRepository();
      final supabase = _MockSupabaseService();

      when(() => supabase.refreshAvailability()).thenAnswer((_) async => true);
      when(() => repo.getByStatus('local')).thenAnswer((_) async => [photo]);
      when(() => repo.getByStatus('failed')).thenAnswer((_) async => []);
      when(() => supabase.uploadPhoto(photo)).thenAnswer((_) async {});
      when(
        () => repo.updateStatus(photo.id, 'synced'),
      ).thenAnswer((_) async {});

      // Force the oversize branch by capping just below the current file size.
      await PhotoSyncService(
        repository: repo,
        supabase: supabase,
        maxUploadBytes: originalSize - 1,
      ).syncPending();

      expect(await file.length(), lessThan(originalSize));
      verify(() => supabase.uploadPhoto(photo)).called(1);
      verify(() => repo.updateStatus(photo.id, 'synced')).called(1);
      verifyNever(() => repo.updateStatus(photo.id, 'failed'));
      await tempDir.delete(recursive: true);
    },
  );
}

Uint8List _texturedJpeg(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, (x * 7) % 256, (y * 13) % 256, (x + y) % 256);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
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
