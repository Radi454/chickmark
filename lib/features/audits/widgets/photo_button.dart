import 'dart:io';
import 'package:flutter/material.dart';
import '../../../services/photo/photo_service.dart';

class PhotoButton extends StatefulWidget {
  final String? photoPath;
  final Function(String path) onPhotoCaptured;
  final bool enabled;

  const PhotoButton({
    super.key,
    this.photoPath,
    required this.onPhotoCaptured,
    this.enabled = true,
  });

  @override
  State<PhotoButton> createState() => _PhotoButtonState();
}

class _PhotoButtonState extends State<PhotoButton> {
  final PhotoService _photoService = PhotoService();

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return _buildDisabledButton();
    }

    if (widget.photoPath == null) {
      return _buildCameraButton();
    }

    return _buildThumbnailButton();
  }

  Widget _buildDisabledButton() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.camera_alt_outlined,
        color: Colors.grey,
        size: 20,
      ),
    );
  }

  Widget _buildCameraButton() {
    return InkWell(
      onTap: _pickPhoto,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: const Icon(Icons.camera_alt, color: Colors.grey, size: 20),
      ),
    );
  }

  Widget _buildThumbnailButton() {
    return InkWell(
      onTap: _viewPhoto,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Stack(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.file(
                File(widget.photoPath!),
                width: 38,
                height: 38,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 38,
                    height: 38,
                    color: Colors.grey[200],
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  );
                },
              ),
            ),
            // Re-take button overlay
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: _pickPhoto,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.refresh,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    if (!widget.enabled) return;

    final path = await _photoService.pickPhoto(fromCamera: true);
    if (path != null) {
      widget.onPhotoCaptured(path);
    }
  }

  void _viewPhoto() {
    if (widget.photoPath == null) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.file(File(widget.photoPath!), fit: BoxFit.contain),
              ],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
