import 'package:hatchaudit/localized_material.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../data/models/customer_model.dart';
import '../../../widgets/app_card.dart';

class CustomerCard extends StatelessWidget {
  final CustomerModel customer;
  final int flockCount;
  final bool hasEstimatedFlockAge;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const CustomerCard({
    super.key,
    required this.customer,
    required this.flockCount,
    this.hasEstimatedFlockAge = false,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: EdgeInsets.zero,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppSizes.iconContainerMd,
            height: AppSizes.iconContainerMd,
            decoration: BoxDecoration(
              color: AppColors.activeBg,
              borderRadius: BorderRadius.circular(AppSizes.iconRadius),
            ),
            child: const Icon(
              Icons.business_outlined,
              color: AppColors.primary,
              size: AppSizes.iconSm,
            ),
          ),
          const SizedBox(width: AppSizes.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              customer.name,
                              style: AppTextStyles.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (hasEstimatedFlockAge) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message:
                                  'One or more flocks need entry date confirmation',
                              child: Icon(
                                Icons.warning_amber_outlined,
                                size: 18,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (customer.location != null) ...[
                  const SizedBox(height: AppSizes.spaceSm),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: AppColors.inactiveTab,
                      ),
                      const SizedBox(width: 4),
                      Text(customer.location!, style: AppTextStyles.caption),
                    ],
                  ),
                ],
                if (customer.phone != null) ...[
                  const SizedBox(height: AppSizes.spaceSm),
                  Row(
                    children: [
                      const Icon(
                        Icons.phone_outlined,
                        size: 16,
                        color: AppColors.inactiveTab,
                      ),
                      const SizedBox(width: 4),
                      Text(customer.phone!, style: AppTextStyles.caption),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSizes.spaceSm),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFlockBadge(),
              if (onEdit != null) ...[
                const SizedBox(width: AppSizes.spaceSm),
                SizedBox(
                  width: 38,
                  height: 38,
                  child: IconButton.outlined(
                    tooltip: context.tr('Edit customer'),
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
              if (onDelete != null) ...[
                const SizedBox(width: AppSizes.spaceSm),
                SizedBox(
                  width: 38,
                  height: 38,
                  child: IconButton.outlined(
                    tooltip: context.tr('Delete customer'),
                    onPressed: onDelete,
                    color: AppColors.statusError,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFlockBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.ageBadgeBg,
        borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
      ),
      child: Text(
        '$flockCount ${flockCount == 1 ? 'flock' : 'flocks'}',
        style: AppTextStyles.caption.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
