import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/features/customers/widgets/customer_card.dart';
import 'package:hatchaudit/features/customers/widgets/add_customer_sheet.dart';
import 'package:hatchaudit/features/customers/screens/customer_detail_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<CustomersProvider>();
      if (provider.allCustomers.isEmpty && !provider.isLoading) {
        provider.loadCustomers(
          currentUser: context.read<AuthProvider>().user,
        );
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
                padding: const EdgeInsets.all(16),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search customers...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onChanged: provider.setSearchQuery,
                ),
              ),
              // Customer List
              Expanded(
                child: provider.filteredCustomers.isEmpty
                    ? Center(
                        child: Text(
                          provider.searchQuery.isEmpty
                              ? 'No customers yet'
                              : 'No customers found',
                          style: AppTextStyles.body.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
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
}
