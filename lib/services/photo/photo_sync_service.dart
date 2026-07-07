import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../data/models/photo_model.dart';
import '../../data/repositories/photo_repository.dart';
import '../supabase/supabase_service.dart';
import 'photo_compression.dart';

class PhotoSyncService {
  PhotoSyncService({
    PhotoRepository? repository,
    SupabaseService? supabase,
    int maxUploadBytes = 5 * 1024 * 1024,
    Future<Directory> Function()? documentDirectoryProvider,
  }) : _repo = repository ?? PhotoRepository(),
       _supabase = supabase ?? SupabaseService(),
       _maxBytes = maxUploadBytes,
       _documentDirectoryProvider =
           documentDirectoryProvider ?? getApplicationDocumentsDirectory;

  final PhotoRepository _repo;
  final SupabaseService _supabase;
  final int _maxBytes;
  final Future<Directory> Function() _documentDirectoryProvider;

  // Re-encode oversize captures below the capture default so they still sync.
  static const int _shrinkMaxEdge = 1600;
  static const int _shrinkQuality = 80;

  Future<void> syncDownloaded() async {
    final documentsDir = await _documentDirectoryProvider();
    try {
      await _repo.reconcileLocalPaths(documentsDir.path);
    } catch (_) {
      // Local recovery is best effort; cloud recovery can still proceed.
    }

    final available = await _supabase.refreshAvailability();
    if (!available) return;

    final remotePhotos = await _repo.getRemotePhotos();
    for (final photo in remotePhotos) {
      final localFile = File(
        path.join(documentsDir.path, _localFileNameFor(photo)),
      );
      try {
        if (await localFile.exists() && await localFile.length() > 0) {
          await _repo.updateLocalPath(photo.id, localFile.path);
          continue;
        }

        final bytes = await _supabase.downloadPhotoBytes(photo.filePath);
        if (bytes.isEmpty) continue;
        await localFile.writeAsBytes(bytes, flush: true);
        await _repo.updateLocalPath(photo.id, localFile.path);
      } catch (_) {
        // Keep the remote reference so the next sync can retry the download.
      }
    }
  }

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

  String _localFileNameFor(PhotoModel photo) {
    final safeId = photo.id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final extension = _extensionFor(photo.filePath);
    return '$safeId.$extension';
  }

  String _extensionFor(String filePath) {
    final uri = Uri.tryParse(filePath);
    final remotePath = uri == null ? filePath : uri.path;
    final extension = path.extension(remotePath).replaceFirst('.', '');
    return extension.isEmpty ? 'jpg' : extension.toLowerCase();
  }
}
