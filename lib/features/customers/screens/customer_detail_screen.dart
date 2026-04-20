import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/customers_provider.dart';
import '../../../data/models/customer_model.dart';
import '../../../data/models/flock_model.dart';
import '../../../features/customers/widgets/flock_detail_card.dart';
import '../../../features/customers/widgets/add_flock_sheet.dart';
import '../../../features/customers/widgets/audit_history_card.dart';
import '../../../features/customers/screens/audit_detail_screen.dart';
import '../../../features/auth/providers/auth_provider.dart';

class CustomerDetailScreen extends StatefulWidget {
  final CustomerModel customer;

  const CustomerDetailScreen({super.key, required this.customer});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Load customer data when screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomersProvider>().selectCustomer(widget.customer);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: widget.customer.name,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: null, // Disabled for now
          ),
        ],
      ),
      body: Consumer<CustomersProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Flocks Section
                _buildFlocksSection(provider),
                const SizedBox(height: 24),
                // Audit History Section
                _buildAuditHistorySection(provider),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFlocksSection(CustomersProvider provider) {
    final canEdit = context.watch<AuthProvider>().user?.canEditAudits ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Flocks', style: AppTextStyles.heading.copyWith(fontSize: 20)),
        const SizedBox(height: 12),
        if (provider.flocks.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                'No flocks yet',
                style: AppTextStyles.body.copyWith(color: Colors.grey),
              ),
            ),
          )
        else
          Column(
            children: [
              // Flock Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<FlockModel>(
                    value: provider.selectedFlock,
                    hint: Text('Select a flock', style: AppTextStyles.body),
                    isExpanded: true,
                    items: provider.flocks.map((flock) {
                      return DropdownMenuItem<FlockModel>(
                        value: flock,
                        child: Text(flock.flockId, style: AppTextStyles.body),
                      );
                    }).toList(),
                    onChanged: (flock) {
                      provider.selectFlock(flock);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Add / Edit / Delete Flock Buttons
              if (canEdit)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showAddFlockSheet(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Flock'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: const BorderSide(color: AppColors.primary),
                        ),
                      ),
                    ),
                    if (provider.selectedFlock != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        color: AppColors.primary,
                        tooltip: 'Edit flock',
                        onPressed: () => _showEditFlockSheet(
                          context,
                          provider.selectedFlock!,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        color: Colors.red,
                        tooltip: 'Delete flock',
                        onPressed: () => _confirmDeleteFlock(context, provider),
                      ),
                    ],
                  ],
                ),
              if (canEdit) const SizedBox(height: 12),
              // Flock Detail Card (shown only when flock is selected)
              if (provider.selectedFlock != null)
                FlockDetailCard(
                  flock: provider.selectedFlock!,
                  onTap: canEdit
                      ? () => _showEditFlockSheet(
                          context,
                          provider.selectedFlock!,
                        )
                      : () {},
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildAuditHistorySection(CustomersProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Audit History',
          style: AppTextStyles.heading.copyWith(fontSize: 20),
        ),
        const SizedBox(height: 12),
        if (provider.audits.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                'No audits yet',
                style: AppTextStyles.body.copyWith(color: Colors.grey),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: provider.audits.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final audit = provider.audits[index];
              // Find flock for this audit
              final flock = provider.flocks.firstWhere(
                (f) => f.id == audit.flockId,
                orElse: () => provider.flocks.isEmpty
                    ? FlockModel(
                        id: '',
                        customerId: audit.customerId,
                        flockId: audit.flockId ?? 'Unknown',
                        breed: 'Unknown',
                        entryDate: audit.date,
                      )
                    : provider.flocks.first,
              );
              return AuditHistoryCard(
                audit: audit,
                flock: flock,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AuditDetailScreen(audit: audit),
                    ),
                  );
                },
              );
            },
          ),
      ],
    );
  }

  void _showAddFlockSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddFlockSheet(),
    );
  }

  void _showEditFlockSheet(BuildContext context, FlockModel flock) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddFlockSheet(initialFlock: flock),
    );
  }

  void _confirmDeleteFlock(BuildContext context, CustomersProvider provider) {
    final flock = provider.selectedFlock!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Flock'),
        content: Text(
          'Delete flock "${flock.flockId}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.deleteFlock(flock.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
