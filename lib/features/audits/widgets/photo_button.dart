import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/photo_model.dart';
import '../../../data/repositories/photo_repository.dart';
import '../../../services/photo/photo_service.dart';
import '../providers/audit_provider.dart';
import 'inline_camera_capture.dart';

class PhotoButton extends StatefulWidget {
  final String? photoPath;
  final Function(String path) onPhotoCaptured;
  final bool enabled;
  final double size;
  final bool cameraFirst;
  final String? panelName;
  final String? panelRowId;
  final String? fieldKey;

  const PhotoButton({
    super.key,
    this.photoPath,
    required this.onPhotoCaptured,
    this.enabled = true,
    this.size = 40,
    this.cameraFirst = false,
    this.panelName,
    this.panelRowId,
    this.fieldKey,
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

    final path = widget.cameraFirst
        ? await _openCameraFirstPicker()
        : await _openSourcePicker();

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

  Future<String?> _openSourcePicker() async {
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

    if (fromCamera == null) return null;

    return _photoService.pickPhoto(fromCamera: fromCamera);
  }

  Future<String?> _openCameraFirstPicker() {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.black,
      builder: (context) =>
          _CameraFirstPhotoPicker(photoService: _photoService),
    );
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
    final identity = _currentPanelPhotoIdentity();
    if (identity == null) return;

    final photo = PhotoModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      filePath: path,
      createdAt: DateTime.now(),
      sessionId: identity.sessionId,
      panelName: identity.panelName,
      panelRowId: identity.panelRowId,
      fieldKey: identity.fieldKey,
      uploadStatus: 'local',
    );
    await _photoRepository.saveLocalPhoto(photo);
  }

  _PanelPhotoIdentity? _currentPanelPhotoIdentity() {
    try {
      final draft = context.read<AuditProvider>().activeDraft;
      final sessionId = draft.sessionId;
      final panelName = widget.panelName ?? _defaultPanelName(draft.auditType);
      if (sessionId == null || sessionId.isEmpty || panelName == null) {
        return null;
      }
      return _PanelPhotoIdentity(
        sessionId: sessionId,
        panelName: panelName,
        panelRowId: widget.panelRowId ?? '$sessionId:$panelName:${draft.id}',
        fieldKey: widget.fieldKey ?? 'photo',
      );
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

class _CameraFirstPhotoPicker extends StatefulWidget {
  const _CameraFirstPhotoPicker({required this.photoService});

  final PhotoService photoService;

  @override
  State<_CameraFirstPhotoPicker> createState() =>
      _CameraFirstPhotoPickerState();
}

class _CameraFirstPhotoPickerState extends State<_CameraFirstPhotoPicker> {
  final GlobalKey<InlineCameraCaptureState> _cameraKey = GlobalKey();
  bool _cameraReady = false;
  bool _isCapturing = false;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.88;

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: InlineCameraCapture(
              key: _cameraKey,
              isScanning: false,
              onCameraReadyChanged: _handleCameraReadyChanged,
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: IconButton.filled(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withAlpha(0),
                      Colors.black.withAlpha(210),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Gallery',
                      onPressed: _isCapturing ? null : _pickFromGallery,
                      icon: const Icon(Icons.photo_library_outlined),
                    ),
                    const Spacer(),
                    SizedBox.square(
                      dimension: 68,
                      child: FilledButton(
                        onPressed: _isCapturing ? null : _capturePhoto,
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: EdgeInsets.zero,
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          disabledBackgroundColor: Colors.white70,
                          disabledForegroundColor: Colors.black45,
                        ),
                        child: _isCapturing
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Icon(Icons.photo_camera, size: 30),
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _capturePhoto() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    String? savedPath;
    final sourcePath = _cameraReady
        ? await _cameraKey.currentState?.takePicture()
        : null;

    if (sourcePath != null) {
      savedPath = await widget.photoService.saveCapturedPhotoPath(sourcePath);
      unawaited(widget.photoService.deletePhoto(sourcePath));
    } else {
      savedPath = await widget.photoService.pickPhoto(fromCamera: true);
    }

    if (!mounted) return;
    setState(() => _isCapturing = false);
    if (savedPath != null) Navigator.pop(context, savedPath);
  }

  Future<void> _pickFromGallery() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    final path = await widget.photoService.pickPhoto(fromCamera: false);

    if (!mounted) return;
    setState(() => _isCapturing = false);
    if (path != null) Navigator.pop(context, path);
  }

  void _handleCameraReadyChanged(bool ready) {
    if (!mounted || _cameraReady == ready) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _cameraReady == ready) return;
      setState(() => _cameraReady = ready);
    });
  }
}

class MultiPhotoButton extends StatefulWidget {
  final List<String> photoPaths;
  final Function(int index, String path) onPhotoCaptured;
  final Function(int index)? onPhotoRemoved;
  final bool enabled;
  final int maxPhotos;
  final String? panelName;
  final String? panelRowId;
  final String? fieldKey;

  const MultiPhotoButton({
    super.key,
    required this.photoPaths,
    required this.onPhotoCaptured,
    this.onPhotoRemoved,
    this.enabled = true,
    this.maxPhotos = 6,
    this.panelName,
    this.panelRowId,
    this.fieldKey,
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
    final identity = _currentPanelPhotoIdentity();
    if (identity == null) return;

    final photo = PhotoModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      filePath: path,
      createdAt: DateTime.now(),
      sessionId: identity.sessionId,
      panelName: identity.panelName,
      panelRowId: identity.panelRowId,
      fieldKey: identity.fieldKey,
      uploadStatus: 'local',
    );
    await _photoRepository.saveLocalPhoto(photo);
  }

  _PanelPhotoIdentity? _currentPanelPhotoIdentity() {
    try {
      final draft = context.read<AuditProvider>().activeDraft;
      final sessionId = draft.sessionId;
      final panelName = widget.panelName ?? _defaultPanelName(draft.auditType);
      if (sessionId == null || sessionId.isEmpty || panelName == null) {
        return null;
      }
      return _PanelPhotoIdentity(
        sessionId: sessionId,
        panelName: panelName,
        panelRowId: widget.panelRowId ?? '$sessionId:$panelName:${draft.id}',
        fieldKey: widget.fieldKey ?? 'photo',
      );
    } catch (_) {
      return null;
    }
  }
}

class _PanelPhotoIdentity {
  const _PanelPhotoIdentity({
    required this.sessionId,
    required this.panelName,
    required this.panelRowId,
    required this.fieldKey,
  });

  final String sessionId;
  final String panelName;
  final String panelRowId;
  final String fieldKey;
}

String? _defaultPanelName(String auditType) {
  return switch (auditType) {
    'Egg' => 'egg_storage',
    'Chicks' => 'chick_quality',
    'Hatch Analysis & Egg Breakouts' => 'residue_breakout',
    'Setters' => 'setter_optimizing',
    'Hatchers' => 'hatcher_optimizing',
    _ => null,
  };
}
