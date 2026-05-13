import 'dart:io';

import '../../data/repositories/photo_repository.dart';
import '../supabase/supabase_service.dart';

class PhotoSyncService {
  PhotoSyncService({PhotoRepository? repository, SupabaseService? supabase})
    : _repo = repository ?? PhotoRepository(),
      _supabase = supabase ?? SupabaseService();

  final PhotoRepository _repo;
  final SupabaseService _supabase;

  Future<void> syncPending() async {
    final available = await _supabase.refreshAvailability();
    if (!available) return;

    final pending = [
      ...await _repo.getByStatus('local'),
      ...await _repo.getByStatus('failed'),
    ];
    for (final photo in pending) {
      try {
        final file = File(photo.filePath);
        if (!await file.exists()) {
          await _repo.updateStatus(photo.id, 'failed');
          continue;
        }

        final size = await file.length();
        if (size > 5 * 1024 * 1024) {
          await _repo.updateStatus(photo.id, 'failed');
          continue;
        }

        await _supabase.uploadPhoto(photo);
        await _repo.updateStatus(photo.id, 'synced');
      } catch (_) {
        await _repo.updateStatus(photo.id, 'failed');
      }
    }
  }
}
