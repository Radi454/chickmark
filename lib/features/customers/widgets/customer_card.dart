import 'package:flutter/material.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/customer_model.dart';

class CustomerCard extends StatelessWidget {
  final CustomerModel customer;
  final int flockCount;
  final bool hasEstimatedFlockAge;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;

  const CustomerCard({
    super.key,
    required this.customer,
    required this.flockCount,
    this.hasEstimatedFlockAge = false,
    this.onTap,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            customer.name,
                            style: AppTextStyles.body.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildFlockBadge(),
                      if (onEdit != null) ...[
                        const SizedBox(width: 6),
                        IconButton.outlined(
                          tooltip: 'Edit customer',
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              if (customer.location != null) ...[
                const SizedBox(height: 8),
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
                const SizedBox(height: 8),
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
      ),
    );
  }

  Widget _buildFlockBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.ageBadgeBg,
        borderRadius: BorderRadius.circular(12),
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
