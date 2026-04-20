import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/widgets/status_badge.dart';
import 'package:hatchaudit/features/customers/screens/audit_detail_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';

class AuditsScreen extends StatefulWidget {
  const AuditsScreen({super.key});

  @override
  State<AuditsScreen> createState() => _AuditsScreenState();
}

class _AuditsScreenState extends State<AuditsScreen> {
  String _selectedFilter = 'All';
  String _searchQuery = '';

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
      appBar: const GradientAppBar(title: 'Audits'),
      body: Consumer<CustomersProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              _buildSearchBar(),
              _buildFilterChips(),
              Expanded(child: _buildAuditList(provider)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search audits...',
          prefixIcon: const Icon(Icons.search, size: 20),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (value) {
          setState(() => _searchQuery = value);
        },
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.cardPadding),
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
              'Audits will appear here after sync',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadCustomers(
        currentUser: context.read<AuthProvider>().user,
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        itemCount: audits.length.clamp(0, 50),
        itemBuilder: (context, index) {
          final audit = audits[index];
          final customer = provider.customerById(audit.customerId);
          final flock = provider.flockById(audit.flockId);
          return _AuditCard(
            audit: audit,
            customerName: customer?.name ?? audit.customerId,
            flockLabel: flock?.flockId ?? audit.flockId ?? '--',
            breed: flock?.breed ?? audit.soBreed ?? audit.hoBreed,
            ageWeeks: flock?.currentAgeWeeks.round(),
            onTap: () => _openAuditDetail(audit),
          );
        },
      ),
    );
  }

  List<AuditModel> _filterAudits(CustomersProvider provider) {
    var all = provider.allAudits;

    if (_selectedFilter != 'All') {
      all = all.where((a) => a.auditType == _selectedFilter).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      all = all.where((a) {
        return (a.flockId?.toLowerCase().contains(query) ?? false) ||
            (a.customerId.toLowerCase().contains(query)) ||
            (a.auditType.toLowerCase().contains(query)) ||
            (a.setterId?.toLowerCase().contains(query) ?? false) ||
            (a.hatcherId?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    return all..sort((a, b) => b.date.compareTo(a.date));
  }

  void _openAuditDetail(AuditModel audit) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AuditDetailScreen(audit: audit)),
    );
  }
}

class _AuditCard extends StatelessWidget {
  final AuditModel audit;
  final String customerName;
  final String flockLabel;
  final String? breed;
  final int? ageWeeks;
  final VoidCallback onTap;

  const _AuditCard({
    required this.audit,
    required this.customerName,
    required this.flockLabel,
    required this.breed,
    required this.ageWeeks,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
                  _buildAgeBadge(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      customerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
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
                '${audit.auditType}${(audit.setterId ?? audit.soSetterId) != null ? ' · ${audit.setterId ?? audit.soSetterId}' : ''}${(audit.hatcherId ?? audit.hoHatcherId) != null ? ' · ${audit.hatcherId ?? audit.hoHatcherId}' : ''}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgeBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    );
  }
}
