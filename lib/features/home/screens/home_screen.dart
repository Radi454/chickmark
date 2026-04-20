import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/widgets/status_badge.dart';
import 'package:hatchaudit/features/audits/screens/audit_type_selection_screen.dart';
import 'package:hatchaudit/features/customers/widgets/add_customer_sheet.dart';
import 'package:hatchaudit/features/customers/screens/audit_detail_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _selectedFilter = 'All';

  static const _filters = [
    'All',
    'Chick Quality',
    'Hatch Analysis',
    'Egg Storage',
    'Setter Optimizing',
    'Hatcher Optimizing',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomersProvider>().loadCustomers(
        currentUser: context.read<AuthProvider>().user,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientAppBar(title: 'ChickMark'),
      body: Consumer<CustomersProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              _buildStatsRow(provider),
              _buildActionButtons(context),
              _buildFilterChips(),
              Expanded(child: _buildAuditList(provider)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatsRow(CustomersProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      child: Row(
        children: [
          Expanded(child: _buildStatCard('Customers', provider.customersCount)),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard('Active Audits', provider.activeAuditsCount),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard('Total Audits', provider.totalAuditsCount),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, int value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final canEdit = context.watch<AuthProvider>().user?.canEditAudits ?? false;
    if (!canEdit) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.cardPadding),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _showAddCustomerSheet(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Customer'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AuditTypeSelectionScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Audit'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _filters.map((filter) {
            final isSelected = _selectedFilter == filter;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(filter),
                selected: isSelected,
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontSize: 12,
                ),
                onSelected: (_) {
                  setState(() => _selectedFilter = filter);
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildAuditList(CustomersProvider provider) {
    final audits = _filterAudits(provider);

    if (audits.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No audits yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "New Audit" to create your first audit',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.cardPadding),
      itemCount: audits.length.clamp(0, 20),
      itemBuilder: (context, index) {
        final audit = audits[index];
        final customer = provider.customerById(audit.customerId);
        final flock = provider.flockById(audit.flockId);
        return _AuditListCard(
          audit: audit,
          customerName: customer?.name ?? audit.customerId,
          flockLabel: flock?.flockId ?? audit.flockId ?? '--',
          breed: flock?.breed ?? audit.soBreed ?? audit.hoBreed,
          ageWeeks: flock?.currentAgeWeeks.round(),
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
    );
  }

  List<AuditModel> _filterAudits(CustomersProvider provider) {
    final all = provider.allAudits;
    if (_selectedFilter == 'All') return all;
    return all.where((a) => a.auditType == _selectedFilter).toList();
  }

  void _showAddCustomerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddCustomerSheet(),
    );
  }
}

class _AuditListCard extends StatelessWidget {
  final AuditModel audit;
  final String customerName;
  final String flockLabel;
  final String? breed;
  final int? ageWeeks;
  final VoidCallback onTap;

  const _AuditListCard({
    required this.audit,
    required this.customerName,
    required this.flockLabel,
    required this.breed,
    required this.ageWeeks,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final setterId = audit.setterId ?? audit.soSetterId;
    final hatcherId = audit.hatcherId ?? audit.hoHatcherId;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0E8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      ageWeeks != null ? '${ageWeeks}w' : '--',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      customerName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  StatusBadge(status: audit.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$flockLabel${breed != null ? ' · $breed' : ''} · ${audit.date.toString().split(' ')[0]}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 4),
              Text(
                '${audit.auditType}${setterId != null ? ' · $setterId' : ''}${hatcherId != null ? ' · $hatcherId' : ''}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
