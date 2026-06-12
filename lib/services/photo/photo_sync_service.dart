import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/repositories/photo_repository.dart';
import '../supabase/supabase_service.dart';
import 'photo_compression.dart';

class PhotoSyncService {
  PhotoSyncService({
    PhotoRepository? repository,
    SupabaseService? supabase,
    int maxUploadBytes = 5 * 1024 * 1024,
  }) : _repo = repository ?? PhotoRepository(),
       _supabase = supabase ?? SupabaseService(),
       _maxBytes = maxUploadBytes;

  final PhotoRepository _repo;
  final SupabaseService _supabase;
  final int _maxBytes;

  // Re-encode oversize captures below the capture default so they still sync.
  static const int _shrinkMaxEdge = 1600;
  static const int _shrinkQuality = 80;

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

        if (await file.length() > _maxBytes) {
          // Oversize (usually a legacy raw capture from before capture-time
          // compression). Shrink in place rather than giving up — a terminal
          // 'failed' here would never recover on later sync passes.
          final shrunk = await _shrinkInPlace(file);
          if (!shrunk || await file.length() > _maxBytes) {
            await _repo.updateStatus(photo.id, 'failed');
            continue;
          }
        }

        await _supabase.uploadPhoto(photo);
        await _repo.updateStatus(photo.id, 'synced');
      } catch (_) {
        await _repo.updateStatus(photo.id, 'failed');
      }
    }
  }

  /// Re-encode [file] in place at a smaller size so an oversize capture can
  /// still upload. Returns false if it couldn't be decoded or didn't shrink.
  Future<bool> _shrinkInPlace(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final out = await compute(
        resizeJpeg,
        JpegResizeJob(bytes, maxEdge: _shrinkMaxEdge, quality: _shrinkQuality),
      );
      if (out == null || out.isEmpty || out.length >= bytes.length) {
        return false;
      }
      await file.writeAsBytes(out, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}
