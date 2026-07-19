import 'dart:io';

import 'package:hatchaudit/localized_material.dart';
import 'package:flutter/foundation.dart';

bool isNetworkPhotoPath(String path) {
  final normalized = path.trim().toLowerCase();
  return normalized.startsWith('http://') ||
      normalized.startsWith('https://') ||
      normalized.startsWith('blob:') ||
      normalized.startsWith('data:');
}

bool isDisplayablePhotoPath(String? path) {
  if (path == null || path.trim().isEmpty) return false;
  if (isNetworkPhotoPath(path)) return true;
  if (kIsWeb) return false;
  try {
    return File(path).existsSync();
  } catch (_) {
    return false;
  }
}

/// Renders either a local mobile/desktop photo or a browser-safe remote URL.
class PhotoImage extends StatelessWidget {
  final String path;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;
  final FilterQuality filterQuality;
  final ImageErrorWidgetBuilder? errorBuilder;

  const PhotoImage({
    super.key,
    required this.path,
    this.fit,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
    this.filterQuality = FilterQuality.medium,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (isNetworkPhotoPath(path)) {
      return Image.network(
        path,
        fit: fit,
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        filterQuality: filterQuality,
        errorBuilder: errorBuilder,
      );
    }
    if (kIsWeb) {
      return errorBuilder?.call(
            context,
            StateError('Local file photos are unavailable on Flutter Web'),
            null,
          ) ??
          const SizedBox.shrink();
    }
    return Image.file(
      File(path),
      fit: fit,
      width: width,
      height: height,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      filterQuality: filterQuality,
      errorBuilder: errorBuilder,
    );
  }
}
