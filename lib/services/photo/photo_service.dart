import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class PhotoService {
  final ImagePicker _picker = ImagePicker();

  /// Pick a photo from camera or gallery
  /// Returns the path to the copied photo in app documents directory, or null if cancelled/failed
  Future<String?> pickPhoto({bool fromCamera = true}) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85,
      );

      if (image == null) return null;

      // Copy to app documents directory
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String savedPath = path.join(appDir.path, fileName);

      await File(image.path).copy(savedPath);
      return savedPath;
    } catch (e) {
      // Silent failure - degrade gracefully
      return null;
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
      // Silent failure
    }
  }
}
