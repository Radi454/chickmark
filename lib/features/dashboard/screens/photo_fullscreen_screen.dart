import 'dart:io';
import 'package:hatchaudit/localized_material.dart';

class PhotoFullscreenScreen extends StatelessWidget {
  final String filePath;

  const PhotoFullscreenScreen({super.key, required this.filePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: File(filePath).existsSync()
              ? Image.file(
                  File(filePath),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.broken_image,
                    color: Colors.white,
                    size: 64,
                  ),
                )
              : const Icon(Icons.broken_image, color: Colors.white, size: 64),
        ),
      ),
    );
  }
}
