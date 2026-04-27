import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/photo_model.dart';
import '../../../data/repositories/photo_repository.dart';
import '../../../services/photo/photo_service.dart';
import '../providers/audit_provider.dart';

class PhotoButton extends StatefulWidget {
  final String? photoPath;
  final Function(String path) onPhotoCaptured;
  final bool enabled;
  final double size;

  const PhotoButton({
    super.key,
    this.photoPath,
    required this.onPhotoCaptured,
    this.enabled = true,
    this.size = 40,
  });

  @override
  State<PhotoButton> createState() => _PhotoButtonState();
}

class _PhotoButtonState extends State<PhotoButton> {
  final PhotoService _photoService = PhotoService();
  final PhotoRepository _photoRepository = PhotoRepository();
  String? _uploadStatus;

  @override
  void initState() {
    super.initState();
    _refreshUploadStatus();
  }

  @override
  void didUpdateWidget(covariant PhotoButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoPath != widget.photoPath) {
      _refreshUploadStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photoPath == null) {
      return widget.enabled ? _buildCameraButton() : _buildDisabledButton();
    }

    return _buildThumbnailButton();
  }

  Widget _buildDisabledButton() {
    return Container(
      width: widget.size,
      height: widget.size,
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
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Icon(
          Icons.camera_alt,
          color: Colors.grey,
          size: widget.size * 0.5,
        ),
      ),
    );
  }

  Widget _buildThumbnailButton() {
    return InkWell(
      onTap: _viewPhoto,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: widget.size,
        height: widget.size,
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
                width: widget.size - 2,
                height: widget.size - 2,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: widget.size - 2,
                    height: widget.size - 2,
                    color: Colors.grey[200],
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  );
                },
              ),
            ),
            if (widget.enabled)
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
            Positioned(
              left: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(6),
                    bottomLeft: Radius.circular(7),
                  ),
                ),
                child: Icon(
                  _statusIcon(_uploadStatus),
                  size: 12,
                  color: _statusColor(_uploadStatus),
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

    final fromCamera = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );

    if (fromCamera == null) return;

    final path = await _photoService.pickPhoto(fromCamera: fromCamera);
    if (path != null) {
      widget.onPhotoCaptured(path);
      await _saveLocalPhotoRecord(path);
      if (mounted) {
        setState(() {
          _uploadStatus = 'local';
        });
      }
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

  Future<void> _refreshUploadStatus() async {
    final photoPath = widget.photoPath;
    if (photoPath == null) {
      if (mounted) {
        setState(() {
          _uploadStatus = null;
        });
      }
      return;
    }

    final photo = await _photoRepository.getByFilePath(photoPath);
    if (!mounted) return;

    setState(() {
      _uploadStatus = photo?.uploadStatus ?? 'synced';
    });
  }

  Future<void> _saveLocalPhotoRecord(String path) async {
    final auditId = _currentAuditId();
    if (auditId == null || auditId.isEmpty) return;

    final photo = PhotoModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      filePath: path,
      createdAt: DateTime.now(),
      auditId: auditId,
      uploadStatus: 'local',
    );
    await _photoRepository.saveLocalPhoto(photo);
  }

  String? _currentAuditId() {
    try {
      return context.read<AuditProvider>().activeDraft.id;
    } catch (_) {
      return null;
    }
  }

  IconData _statusIcon(String? status) {
    switch (status) {
      case 'failed':
        return Icons.cloud_off;
      case 'local':
        return Icons.cloud_upload;
      case 'synced':
      default:
        return Icons.cloud_done;
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'failed':
        return Colors.redAccent;
      case 'local':
        return Colors.grey.shade300;
      case 'synced':
      default:
        return Colors.greenAccent;
    }
  }
}

class MultiPhotoButton extends StatefulWidget {
  final List<String> photoPaths;
  final Function(int index, String path) onPhotoCaptured;
  final Function(int index)? onPhotoRemoved;
  final bool enabled;
  final int maxPhotos;

  const MultiPhotoButton({
    super.key,
    required this.photoPaths,
    required this.onPhotoCaptured,
    this.onPhotoRemoved,
    this.enabled = true,
    this.maxPhotos = 6,
  });

  @override
  State<MultiPhotoButton> createState() => _MultiPhotoButtonState();
}

class _MultiPhotoButtonState extends State<MultiPhotoButton> {
  final PhotoService _photoService = PhotoService();
  final PhotoRepository _photoRepository = PhotoRepository();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...widget.photoPaths.asMap().entries.map((entry) {
          final index = entry.key;
          final path = entry.value;
          return _buildPhotoThumbnail(index, path);
        }),
        if (widget.photoPaths.length < widget.maxPhotos && widget.enabled)
          _buildAddButton(),
      ],
    );
  }

  Widget _buildPhotoThumbnail(int index, String path) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.file(
              File(path),
              width: 54,
              height: 54,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 54,
                  height: 54,
                  color: Colors.grey[200],
                  child: const Icon(
                    Icons.broken_image,
                    color: Colors.grey,
                    size: 20,
                  ),
                );
              },
            ),
          ),
        ),
        if (widget.enabled)
          Positioned(
            top: -4,
            right: -4,
            child: GestureDetector(
              onTap: () => _removePhoto(index),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.red[700],
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: _addPhoto,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: const Icon(Icons.add_a_photo, color: Colors.grey, size: 24),
      ),
    );
  }

  Future<void> _addPhoto() async {
    if (!widget.enabled) return;

    final fromCamera = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );

    if (fromCamera == null) return;

    final path = await _photoService.pickPhoto(fromCamera: fromCamera);
    if (path != null) {
      final index = widget.photoPaths.length;
      widget.onPhotoCaptured(index, path);
      await _saveLocalPhotoRecord(path);
    }
  }

  void _removePhoto(int index) {
    widget.onPhotoRemoved?.call(index);
  }

  Future<void> _saveLocalPhotoRecord(String path) async {
    final auditId = _currentAuditId();
    if (auditId == null || auditId.isEmpty) return;

    final photo = PhotoModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      filePath: path,
      createdAt: DateTime.now(),
      auditId: auditId,
      uploadStatus: 'local',
    );
    await _photoRepository.saveLocalPhoto(photo);
  }

  String? _currentAuditId() {
    try {
      return context.read<AuditProvider>().activeDraft.id;
    } catch (_) {
      return null;
    }
  }
}
