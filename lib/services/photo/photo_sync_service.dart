import 'dart:io';

import '../../data/repositories/photo_repository.dart';
import '../supabase/supabase_service.dart';

class PhotoSyncService {
  final PhotoRepository _repo = PhotoRepository();
  final SupabaseService _supabase = SupabaseService();

  Future<void> syncPending() async {
    final available = await _supabase.refreshAvailability();
    if (!available) return;

    final pending = await _repo.getByStatus('local');
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
