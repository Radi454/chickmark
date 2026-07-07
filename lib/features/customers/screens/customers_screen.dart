import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';
import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/features/customers/widgets/customer_card.dart';
import 'package:hatchaudit/features/customers/widgets/add_customer_sheet.dart';
import 'package:hatchaudit/features/customers/screens/customer_detail_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/services/supabase/startup_sync_service.dart';

typedef CustomerDeletionSync = Future<SyncOutcome> Function({String? userId});

class CustomersScreen extends StatefulWidget {
  final CustomerDeletionSync? syncAfterDelete;

  const CustomersScreen({super.key, this.syncAfterDelete});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final Set<String> _deletingCustomerIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<CustomersProvider>();
      if (provider.allCustomers.isEmpty && !provider.isLoading) {
        provider.loadCustomers(currentUser: context.read<AuthProvider>().user);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = context.watch<AuthProvider>().user?.canEditAudits ?? false;

    return Scaffold(
      appBar: const GradientAppBar(title: 'Customers'),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              heroTag: 'customers-add-customer-fab',
              onPressed: () => _showAddCustomerSheet(context),
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Customer'),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            )
          : null,
      body: Consumer<CustomersProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.all(AppSizes.cardPadding),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search customers...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSizes.inputRadius),
                      borderSide: const BorderSide(
                        color: AppColors.borderDefault,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.spaceLg,
                      vertical: AppSizes.spaceMd,
                    ),
                  ),
                  onChanged: provider.setSearchQuery,
                ),
              ),
              // Customer List
              Expanded(
                child: provider.filteredCustomers.isEmpty
                    ? Center(
                        child: _CustomersEmptyState(
                          isSearching: provider.searchQuery.isNotEmpty,
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.cardPadding,
                        ),
                        itemCount: provider.filteredCustomers.length,
                        itemBuilder: (context, index) {
                          final customer = provider.filteredCustomers[index];
                          final flockCount =
                              provider.flockCounts[customer.id] ?? 0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: CustomerCard(
                              customer: customer,
                              flockCount: flockCount,
                              hasEstimatedFlockAge: provider
                                  .customerHasEstimatedFlockAge(customer.id),
                              onEdit: canEdit
                                  ? () => _showEditCustomerSheet(
                                      context,
                                      customer,
                                    )
                                  : null,
                              onDelete:
                                  canEdit &&
                                      !_deletingCustomerIds.contains(
                                        customer.id,
                                      )
                                  ? () => _confirmDeleteCustomer(customer)
                                  : null,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => CustomerDetailScreen(
                                      customer: customer,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddCustomerSheet(BuildContext context) async {
    final customer = await showModalBottomSheet<CustomerModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddCustomerSheet(),
    );
    if (!context.mounted || customer == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomerDetailScreen(customer: customer),
      ),
    );
  }

  Future<void> _showEditCustomerSheet(
    BuildContext context,
    CustomerModel customer,
  ) async {
    final updatedCustomer = await showModalBottomSheet<CustomerModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddCustomerSheet(initialCustomer: customer),
    );
    if (!context.mounted || updatedCustomer == null) return;
    await context.read<CustomersProvider>().loadCustomers(
      currentUser: context.read<AuthProvider>().user,
    );
  }

  Future<void> _confirmDeleteCustomer(CustomerModel customer) async {
    final customersProvider = context.read<CustomersProvider>();
    final authProvider = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete customer?'),
        content: Text(
          'This permanently removes "${customer.name}", including its flocks, hatcheries, visits, station data, Govee captures, and linked photos. The deletion will also be synced to the cloud. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.statusError,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    setState(() {
      _deletingCustomerIds.add(customer.id);
    });

    try {
      await customersProvider.deleteCustomer(customer.id);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _deletingCustomerIds.remove(customer.id);
      });
      messenger.showSnackBar(
        SnackBar(content: Text('Could not delete customer: $error')),
      );
      return;
    }

    var synchronized = false;
    try {
      final userId = authProvider.user?.id;
      final syncAfterDelete = widget.syncAfterDelete;
      final outcome = syncAfterDelete != null
          ? await syncAfterDelete(userId: userId)
          : await StartupSyncService().run(userId: userId);
      synchronized = outcome.online && outcome.pendingDeletes == 0;
    } catch (_) {
      synchronized = false;
    }

    if (!mounted) return;
    setState(() {
      _deletingCustomerIds.remove(customer.id);
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          synchronized
              ? '${customer.name} deleted and synchronized'
              : '${customer.name} deleted locally; cloud deletion is pending sync',
        ),
      ),
    );
  }
}

class _CustomersEmptyState extends StatelessWidget {
  final bool isSearching;

  const _CustomersEmptyState({required this.isSearching});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.spaceXl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.activeBg,
              borderRadius: BorderRadius.circular(AppSizes.iconRadius),
            ),
            child: Icon(
              isSearching ? Icons.search_off_outlined : Icons.business_outlined,
              color: AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(height: AppSizes.spaceLg),
          Text(
            isSearching ? 'No customers found' : 'No customers yet',
            style: AppTextStyles.title,
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Text(
            isSearching
                ? 'Try another customer name, location, or phone.'
                : 'Customer records will appear here once added.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}
