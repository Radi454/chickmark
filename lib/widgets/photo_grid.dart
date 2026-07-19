import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hatchaudit/localized_material.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';

typedef PhotoUrlResolver = Future<String?> Function(String path);
typedef PhotoPlaceholderBuilder = Widget Function(BuildContext context);

bool isPhotoPathDisplayable(String? candidate) {
  final path = candidate?.trim();
  if (path == null || path.isEmpty) return false;
  if (_isNetworkPhotoPath(path) || path.startsWith('supabase://photos/')) {
    return true;
  }
  if (kIsWeb) return false;
  return File(path).existsSync();
}

class PhotoGrid extends StatelessWidget {
  final List<String> filePaths;
  final Function(String)? onTap;
  final PhotoUrlResolver? remoteUrlResolver;

  const PhotoGrid({
    super.key,
    required this.filePaths,
    this.onTap,
    this.remoteUrlResolver,
  });

  @override
  Widget build(BuildContext context) {
    if (filePaths.isEmpty) {
      return _buildEmptyState();
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: AppSizes.spaceXs,
        crossAxisSpacing: AppSizes.spaceXs,
      ),
      itemCount: filePaths.length,
      itemBuilder: (context, index) => _buildTile(filePaths[index]),
    );
  }

  Widget _buildTile(String path) {
    return GestureDetector(
      onTap: onTap != null ? () => onTap!(path) : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.spaceXs),
        child: PhotoImage(
          filePath: path,
          fit: BoxFit.cover,
          remoteUrlResolver: remoteUrlResolver,
          placeholderBuilder: (_) => _buildPlaceholder(),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.background,
      child: const Icon(Icons.image, color: AppColors.textTertiary),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.photo_library_outlined,
            size: AppSizes.iconLg,
            color: AppColors.textDisabled,
          ),
          const SizedBox(height: AppSizes.spaceSm),
          const Text('No photos', style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

class PhotoImage extends StatefulWidget {
  final String filePath;
  final BoxFit fit;
  final int? cacheWidth;
  final PhotoUrlResolver? remoteUrlResolver;
  final PhotoPlaceholderBuilder? placeholderBuilder;

  const PhotoImage({
    super.key,
    required this.filePath,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.remoteUrlResolver,
    this.placeholderBuilder,
  });

  @override
  State<PhotoImage> createState() => _PhotoImageState();
}

class _PhotoImageState extends State<PhotoImage> {
  static SupabaseService? _defaultSupabase;

  Future<String?>? _remoteUrl;

  @override
  void initState() {
    super.initState();
    _preparePath();
  }

  @override
  void didUpdateWidget(covariant PhotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath ||
        oldWidget.remoteUrlResolver != widget.remoteUrlResolver) {
      _preparePath();
    }
  }

  void _preparePath() {
    final path = widget.filePath.trim();
    if (path.startsWith('supabase://photos/')) {
      final resolver =
          widget.remoteUrlResolver ??
          (_defaultSupabase ??= SupabaseService()).createPhotoViewUrl;
      _remoteUrl = resolver(path);
    } else {
      _remoteUrl = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.filePath.trim();
    if (_isNetworkPhotoPath(path)) {
      return _buildNetworkImage(path);
    }

    final remoteUrl = _remoteUrl;
    if (remoteUrl != null) {
      return FutureBuilder<String?>(
        future: remoteUrl,
        builder: (context, snapshot) {
          final url = snapshot.data;
          if (snapshot.connectionState == ConnectionState.done &&
              url != null &&
              _isNetworkPhotoPath(url)) {
            return _buildNetworkImage(url);
          }
          return _buildPlaceholder(context);
        },
      );
    }

    if (kIsWeb || path.isEmpty) return _buildPlaceholder(context);
    final file = File(path);
    if (!file.existsSync()) return _buildPlaceholder(context);
    return Image.file(
      file,
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      errorBuilder: (context, error, stackTrace) => _buildPlaceholder(context),
    );
  }

  Widget _buildNetworkImage(String url) {
    return Image.network(
      url,
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : _buildPlaceholder(context),
      errorBuilder: (context, error, stackTrace) => _buildPlaceholder(context),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return widget.placeholderBuilder?.call(context) ??
        const ColoredBox(
          color: AppColors.background,
          child: Icon(Icons.image, color: AppColors.textTertiary),
        );
  }
}

bool _isNetworkPhotoPath(String path) {
  return path.startsWith('http://') || path.startsWith('https://');
}
