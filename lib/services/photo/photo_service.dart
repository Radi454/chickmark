import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import 'photo_compression.dart';

class PhotoService {
  /// Longest edge (px) kept when storing a capture. Large enough for evidence
  /// review, small enough to keep files around the sub-megabyte range.
  static const int _maxImageEdge = 2000;

  /// JPEG quality used when re-encoding a stored capture.
  static const int _jpegQuality = 90;

  final ImagePicker _picker = ImagePicker();

  /// Pick a photo from camera or gallery
  /// Returns the path to the copied photo in app documents directory, or null if cancelled/failed
  Future<String?> pickPhoto({
    bool fromCamera = true,
    int imageQuality = 85,
  }) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: imageQuality,
      );

      if (image == null) return null;

      return saveCapturedPhotoPath(image.path);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Photo pick failed: $e');
      }
      return null;
    }
  }

  /// Copy a captured image into the app documents directory, downscaling and
  /// re-encoding it as JPEG to cap file size. Falls back to a raw copy if the
  /// image can't be decoded, so a capture is never lost to a compression error.
  Future<String?> saveCapturedPhotoPath(String sourcePath) async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String savedPath = path.join(appDir.path, fileName);

      if (await _compressInto(sourcePath, savedPath)) {
        return savedPath;
      }
      await File(sourcePath).copy(savedPath);
      return savedPath;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Photo save failed from $sourcePath: $e');
      }
      return null;
    }
  }

  /// Decode → downscale (long edge ≤ [_maxImageEdge]) → JPEG q[_jpegQuality],
  /// run off the UI thread via `compute`. Returns false (so the caller copies
  /// the raw bytes) on any failure.
  Future<bool> _compressInto(String sourcePath, String destPath) async {
    try {
      final bytes = await File(sourcePath).readAsBytes();
      final out = await compute(
        resizeJpeg,
        JpegResizeJob(bytes, maxEdge: _maxImageEdge, quality: _jpegQuality),
      );
      if (out == null || out.isEmpty) return false;
      await File(destPath).writeAsBytes(out, flush: true);
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Photo compress failed from $sourcePath: $e');
      }
      return false;
    }
  }

  /// Delete a photo from the app documents directory
  Future<void> deletePhoto(String filePath) async {
    try {
      final File file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Photo delete failed for $filePath: $e');
      }
    }
  }
}
