import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/dashboard/providers/scope_comparison_provider.dart';
import 'package:hatchaudit/features/dashboard/widgets/scope/scope_insights_section.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/govee_environmental_readings_section.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/stub_sections.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/widgets/app_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = context.read<AuthProvider>().user;
      context.read<DashboardProvider>().init(currentUser: user);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, child) {
        // Keep the scope comparison in sync with the dashboard filter
        // (idempotent: only reloads when the filter actually changes).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.read<ScopeComparisonProvider>().applyFilter(
                customerId: provider.selectedCustomerId,
                flockId: provider.selectedFlockId,
                bmkAge: provider.selectedBmkAge,
              );
        });
        return Scaffold(
          appBar: const GradientAppBar(title: 'Dashboard'),
          body: Column(
            children: [
              _buildCascadeFilter(provider),
              Expanded(child: _buildContent(context, provider)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCascadeFilter(DashboardProvider provider) {
    return AppCard(
      margin: const EdgeInsets.fromLTRB(
        AppSizes.cardPadding,
        AppSizes.cardPadding,
        AppSizes.cardPadding,
        0,
      ),
      color: AppColors.surfaceVariant,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final customerFilter = _customerFilter(provider);
          final flockFilter = _flockFilter(provider);
          final ageFilter = _ageFilter(provider);

          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                customerFilter,
                const SizedBox(height: AppSizes.spaceSm),
                Row(
                  children: [
                    Expanded(child: flockFilter),
                    const SizedBox(width: AppSizes.spaceSm),
                    SizedBox(width: 96, child: ageFilter),
                    if (provider.hasActiveFilters) ...[
                      const SizedBox(width: AppSizes.spaceXs),
                      _clearFilterButton(provider, compact: true),
                    ],
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: customerFilter),
              const SizedBox(width: AppSizes.spaceSm),
              Expanded(child: flockFilter),
              const SizedBox(width: AppSizes.spaceSm),
              Expanded(child: ageFilter),
              if (provider.hasActiveFilters) ...[
                const SizedBox(width: AppSizes.spaceSm),
                _clearFilterButton(provider),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _customerFilter(DashboardProvider provider) {
    final entries = <({String? value, String label})>[
      if (provider.canUseAllCustomers) (value: null, label: 'All customers'),
      ...provider.customers.map((c) => (value: c.id, label: c.name)),
    ];

    return DropdownButtonFormField<String>(
      initialValue: provider.selectedCustomerId,
      isExpanded: true,
      decoration: _filterDecoration('Customer'),
      selectedItemBuilder: (context) => [
        for (final entry in entries) _menuText(entry.label),
      ],
      items: [
        for (final entry in entries)
          DropdownMenuItem(value: entry.value, child: _menuText(entry.label)),
      ],
      onChanged: provider.setCustomer,
    );
  }

  Widget _flockFilter(DashboardProvider provider) {
    final entries = <({String? value, String label})>[
      (value: null, label: 'All flocks'),
      ...provider.flocks.map((f) => (value: f.id, label: f.flockId)),
    ];

    return DropdownButtonFormField<String>(
      initialValue: provider.selectedFlockId,
      isExpanded: true,
      decoration: _filterDecoration('Flock'),
      selectedItemBuilder: (context) => [
        for (final entry in entries) _menuText(entry.label),
      ],
      items: [
        for (final entry in entries)
          DropdownMenuItem(value: entry.value, child: _menuText(entry.label)),
      ],
      onChanged: provider.setFlock,
    );
  }

  Widget _ageFilter(DashboardProvider provider) {
    final entries = <({int? value, String label})>[
      (value: null, label: 'All'),
      ...provider.availableBmkAges.map((age) => (value: age, label: '${age}w')),
    ];

    return DropdownButtonFormField<int?>(
      initialValue: provider.selectedBmkAge,
      isExpanded: true,
      decoration: _filterDecoration('Age'),
      selectedItemBuilder: (context) => [
        for (final entry in entries) _menuText(entry.label),
      ],
      items: [
        for (final entry in entries)
          DropdownMenuItem(value: entry.value, child: _menuText(entry.label)),
      ],
      onChanged: provider.setBmkAge,
    );
  }

  InputDecoration _filterDecoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceSm,
        vertical: AppSizes.spaceSm,
      ),
    );
  }

  Widget _menuText(String text) {
    return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  Widget _clearFilterButton(
    DashboardProvider provider, {
    bool compact = false,
  }) {
    if (compact) {
      return IconButton.filledTonal(
        tooltip: 'Clear filters',
        onPressed: provider.clearFilters,
        icon: const Icon(Icons.clear, size: 18),
      );
    }

    return TextButton.icon(
      onPressed: provider.clearFilters,
      icon: const Icon(Icons.clear, size: 16),
      label: const Text('Clear'),
    );
  }

  Widget _buildContent(BuildContext context, DashboardProvider provider) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.customers.isEmpty && provider.flocks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.dashboard_outlined,
              size: 64,
              color: AppColors.textDisabled,
            ),
            SizedBox(height: AppSizes.spaceLg),
            Text('No customer or flock data yet', style: AppTextStyles.title),
            SizedBox(height: AppSizes.spaceSm),
            Text(
              'Add a customer and flock to see dashboard insights.',
              style: AppTextStyles.caption,
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      children: [
        const EggStorageSection(),
        const SizedBox(height: AppSizes.spaceLg),
        const EggQualitySection(),
        const SizedBox(height: AppSizes.spaceLg),
        GoveeEnvironmentalReadingsSection(
          captures: provider.goveeCaptures,
          isLoading: provider.isLoadingGoveeCaptures,
        ),
        const SizedBox(height: AppSizes.spaceLg),
        const ScopeInsightsSection(),
      ],
    );
  }
}
