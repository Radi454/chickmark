import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/hatchery_model.dart';
import '../../../providers/customers_provider.dart';
import 'add_hatchery_sheet.dart';

class HatcheryManagementSheet extends StatelessWidget {
  final bool allowAuditSelection;

  const HatcheryManagementSheet({super.key, this.allowAuditSelection = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Consumer<CustomersProvider>(
              builder: (context, provider, child) {
                final customer = provider.selectedCustomer;
                final hatcheries = [...provider.hatcheries]
                  ..sort((a, b) => a.name.toLowerCase().compareTo(
                        b.name.toLowerCase(),
                      ));

                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    _buildHandle(),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hatchery Management',
                                style: AppTextStyles.heading.copyWith(
                                  fontSize: 20,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                customer?.name ?? 'Select a customer first',
                                style: AppTextStyles.caption,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: context.tr('Back'),
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const SizedBox(width: 4),
                        FilledButton.icon(
                          onPressed: customer == null
                              ? null
                              : () => _showAddHatcherySheet(
                                    context,
                                    customer.id,
                                  ),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (customer == null)
                      _buildEmptyState(
                        'Choose a customer to manage hatcheries.',
                      )
                    else if (hatcheries.isEmpty)
                      _buildEmptyState(
                        'No hatcheries yet. Add the first hatchery.',
                      )
                    else
                      ...hatcheries.map(
                        (hatchery) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ManagedHatcheryCard(
                            hatchery: hatchery,
                            allowAuditSelection: allowAuditSelection,
                            onUse: () => Navigator.pop(context, hatchery),
                            onEdit: () => _showEditHatcherySheet(
                              context,
                              hatchery,
                            ),
                            onDelete: () => _confirmDeleteHatchery(
                              context,
                              hatchery,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        width: 44,
        height: 5,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: AppTextStyles.body.copyWith(color: Colors.grey.shade700),
      ),
    );
  }

  Future<void> _showAddHatcherySheet(
    BuildContext context,
    String customerId,
  ) async {
    await showModalBottomSheet<HatcheryModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddHatcherySheet(customerId: customerId),
    );
  }

  Future<void> _showEditHatcherySheet(
    BuildContext context,
    HatcheryModel hatchery,
  ) async {
    await showModalBottomSheet<HatcheryModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddHatcherySheet(
        customerId: hatchery.customerId,
        initialHatchery: hatchery,
      ),
    );
  }

  Future<void> _confirmDeleteHatchery(
    BuildContext context,
    HatcheryModel hatchery,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove hatchery?'),
        content: Text(
          'Remove hatchery "${hatchery.name}"? Existing audits will keep '
          'their saved hatchery reference.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await context.read<CustomersProvider>().deleteHatchery(hatchery.id);
  }
}

class _ManagedHatcheryCard extends StatelessWidget {
  final HatcheryModel hatchery;
  final bool allowAuditSelection;
  final VoidCallback? onUse;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ManagedHatcheryCard({
    required this.hatchery,
    required this.allowAuditSelection,
    required this.onUse,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.factory_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hatchery.name,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if ((hatchery.location ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 14,
                    color: Colors.grey.shade700,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      hatchery.location!,
                      style: AppTextStyles.caption,
                    ),
                  ),
                ],
              ),
            ],
            if ((hatchery.notes ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                hatchery.notes!,
                style: AppTextStyles.caption.copyWith(
                  color: Colors.grey.shade700,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (allowAuditSelection && onUse != null)
                  FilledButton.icon(
                    onPressed: onUse,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Use'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                IconButton.outlined(
                  tooltip: context.tr('Edit hatchery'),
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton.outlined(
                  tooltip: context.tr('Remove hatchery'),
                  onPressed: onDelete,
                  color: Colors.red.shade700,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
