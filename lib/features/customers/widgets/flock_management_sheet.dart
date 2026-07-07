import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/flock_model.dart';
import '../../../providers/customers_provider.dart';
import 'add_flock_sheet.dart';

class FlockManagementSheet extends StatelessWidget {
  final bool allowAuditSelection;

  const FlockManagementSheet({super.key, this.allowAuditSelection = false});

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
                final flocks = [...provider.flocks]..sort(_sortFlocks);

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
                                'Flock Management',
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
                              : () => _showAddFlockSheet(context),
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
                      _buildEmptyState('Choose a customer to manage flocks.')
                    else if (flocks.isEmpty)
                      _buildEmptyState('No flocks yet. Add the first flock.')
                    else
                      ...flocks.map(
                        (flock) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ManagedFlockCard(
                            flock: flock,
                            allowAuditSelection: allowAuditSelection,
                            onUse: flock.isAvailableForAudit
                                ? () => Navigator.pop(context, flock)
                                : null,
                            onToggleStatus: () =>
                                _toggleFlockSold(context, flock),
                            onEdit: () => _showEditFlockSheet(context, flock),
                            onDelete: () => _confirmDeleteFlock(context, flock),
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

  Future<void> _showAddFlockSheet(BuildContext context) async {
    await showModalBottomSheet<FlockModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddFlockSheet(),
    );
  }

  Future<void> _showEditFlockSheet(
    BuildContext context,
    FlockModel flock,
  ) async {
    await showModalBottomSheet<FlockModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddFlockSheet(initialFlock: flock),
    );
  }

  Future<void> _toggleFlockSold(BuildContext context, FlockModel flock) async {
    final markSold = !flock.isSold;
    final updated = flock.copyWith(
      status: markSold ? FlockModel.soldStatus : FlockModel.activeStatus,
      soldAt: markSold ? DateTime.now() : null,
      clearSoldAt: !markSold,
    );
    await context.read<CustomersProvider>().updateFlock(updated);
  }

  Future<void> _confirmDeleteFlock(
    BuildContext context,
    FlockModel flock,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove flock?'),
        content: Text(
          'Remove flock "${flock.flockId}"? Existing audits will keep their saved flock reference.',
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
    await context.read<CustomersProvider>().deleteFlock(flock.id);
  }

  int _sortFlocks(FlockModel a, FlockModel b) {
    final statusSort = _statusWeight(a).compareTo(_statusWeight(b));
    if (statusSort != 0) return statusSort;
    return b.entryDate.compareTo(a.entryDate);
  }

  int _statusWeight(FlockModel flock) {
    if (flock.isAvailableForAudit) return 0;
    if (flock.hasReachedDepletionAge && !flock.isSold) return 1;
    return 2;
  }
}

class _ManagedFlockCard extends StatelessWidget {
  final FlockModel flock;
  final bool allowAuditSelection;
  final VoidCallback? onUse;
  final VoidCallback onToggleStatus;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ManagedFlockCard({
    required this.flock,
    required this.allowAuditSelection,
    required this.onUse,
    required this.onToggleStatus,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final ageWeeks = flock.currentAgeWeeks.toInt().clamp(0, 999);

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
                Expanded(
                  child: Text(
                    flock.flockId,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _FlockStatusBadge(label: flock.availabilityLabel),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(icon: Icons.category_outlined, label: flock.breed),
                _InfoChip(
                  icon: Icons.calendar_today_outlined,
                  label: '$ageWeeks weeks',
                ),
                _InfoChip(
                  icon: Icons.hourglass_bottom_outlined,
                  label: 'Depletes ${flock.depletionAgeWeeks}w',
                ),
              ],
            ),
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
                OutlinedButton.icon(
                  onPressed: onToggleStatus,
                  icon: Icon(
                    flock.isSold
                        ? Icons.check_circle_outline
                        : Icons.sell_outlined,
                    size: 18,
                  ),
                  label: Text(flock.isSold ? 'Mark active' : 'Mark sold'),
                ),
                IconButton.outlined(
                  tooltip: context.tr('Edit flock'),
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton.outlined(
                  tooltip: context.tr('Remove flock'),
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

class _FlockStatusBadge extends StatelessWidget {
  final String label;

  const _FlockStatusBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final isActive = label == 'Active';
    final isDepleted = label == 'Depleted';
    final color = isActive
        ? AppColors.completedText
        : isDepleted
        ? Colors.orange.shade800
        : Colors.grey.shade700;
    final icon = isActive
        ? Icons.check_circle_outline
        : isDepleted
        ? Icons.hourglass_bottom_outlined
        : Icons.sell_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade700),
          const SizedBox(width: 5),
          Text(label, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}
