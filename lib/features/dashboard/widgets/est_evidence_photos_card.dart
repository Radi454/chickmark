import 'package:hatchaudit/localized_material.dart';
import 'package:hatchaudit/widgets/photo_grid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/egg_storage_models.dart';

class EstEvidencePhotosCard extends StatelessWidget {
  final EggStorageEstEvidence evidence;
  final ValueChanged<String>? onPhotoTap;

  const EstEvidencePhotosCard({
    super.key,
    required this.evidence,
    this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    final badgeColor = evidence.isComplete
        ? AppColors.greenTab
        : AppColors.textTertiary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Captured Photos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text('9-point EST evidence', style: AppTextStyles.caption),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withAlpha(22),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: badgeColor.withAlpha(80)),
                ),
                child: Text(
                  evidence.isComplete ? 'Confirmed' : 'Partial',
                  style: AppTextStyles.caption.copyWith(
                    color: badgeColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: evidence.points.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: AppSizes.spaceXs,
                  crossAxisSpacing: AppSizes.spaceXs,
                  childAspectRatio: 1.0,
                ),
                itemBuilder: (context, index) => _EvidenceTile(
                  point: evidence.points[index],
                  onPhotoTap: onPhotoTap,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  final EggStorageEstEvidencePoint point;
  final ValueChanged<String>? onPhotoTap;

  const _EvidenceTile({required this.point, required this.onPhotoTap});

  @override
  Widget build(BuildContext context) {
    final path = point.photoPath;
    final hasValidPhoto = isPhotoPathDisplayable(path);
    final label = '${point.positionLabel} ${point.levelLabel}';
    final value = point.readingLabel;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: InkWell(
        key: ValueKey('est-evidence-${point.key}'),
        borderRadius: BorderRadius.circular(8),
        onTap: hasValidPhoto && onPhotoTap != null
            ? () => onPhotoTap!(path!)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: hasValidPhoto
                      ? PhotoImage(
                          filePath: path!,
                          fit: BoxFit.cover,
                          cacheWidth: 220,
                          placeholderBuilder: (_) => _buildPlaceholder(),
                        )
                      : _buildPlaceholder(),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                textAlign: TextAlign.center,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.shade100,
      alignment: Alignment.center,
      child: Icon(
        Icons.add_photo_alternate_outlined,
        size: 20,
        color: Colors.grey.shade400,
      ),
    );
  }
}
