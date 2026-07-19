import 'package:hatchaudit/localized_material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../widgets/app_card.dart';

class DashboardPortfolioSummary extends StatelessWidget {
  const DashboardPortfolioSummary({
    super.key,
    required this.customerCount,
    required this.hatcheryCount,
    required this.customerSelected,
  });

  final int customerCount;
  final int hatcheryCount;
  final bool customerSelected;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const ValueKey('dashboard-portfolio-summary'),
      color: AppColors.statusActiveBg,
      child: Semantics(
        label: context.tr('Portfolio summary'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.apartment, color: AppColors.primary, size: 28),
            const SizedBox(width: AppSizes.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Portfolio overview'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr(
                      customerSelected
                          ? 'Select a hatchery to view operational analysis and corrective actions.'
                          : 'Select a customer and hatchery to view operational analysis and corrective actions.',
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSizes.spaceMd),
                  Wrap(
                    spacing: AppSizes.spaceSm,
                    runSpacing: AppSizes.spaceSm,
                    children: [
                      _CountChip(
                        icon: Icons.groups_outlined,
                        label: context.tr('$customerCount customers'),
                      ),
                      _CountChip(
                        icon: Icons.factory_outlined,
                        label: context.tr('$hatcheryCount hatcheries'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
