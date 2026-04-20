import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/hatch_analysis_section.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/egg_breakout_section.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/stub_sections.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = context.read<AuthProvider>().user;
    return ChangeNotifierProvider(
      create: (_) => DashboardProvider()..init(currentUser: currentUser),
      child: Consumer<DashboardProvider>(
        builder: (context, provider, child) {
          return Scaffold(
            appBar: const GradientAppBar(title: 'Dashboard'),
            body: Column(
              children: [
                _buildCascadeFilter(provider),
                Expanded(child: _buildContent(provider)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCascadeFilter(DashboardProvider provider) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      color: AppColors.cardBackground,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: provider.selectedCustomerId,
                  decoration: const InputDecoration(
                    labelText: 'Customer',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    if (provider.canUseAllCustomers)
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All customers'),
                      ),
                    ...provider.customers.map((c) {
                      return DropdownMenuItem(value: c.id, child: Text(c.name));
                    }),
                  ],
                  onChanged: (v) {
                    provider.setCustomer(v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: provider.selectedFlockId,
                  decoration: const InputDecoration(
                    labelText: 'Flock',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All flocks'),
                    ),
                    ...provider.flocks.map((f) {
                      return DropdownMenuItem(
                        value: f.id,
                        child: Text(f.flockId),
                      );
                    }),
                  ],
                  onChanged: (v) {
                    provider.setFlock(v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int?>(
                  initialValue: provider.selectedBmkAge,
                  decoration: const InputDecoration(
                    labelText: 'Age',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    ...provider.availableBmkAges.map((a) {
                      return DropdownMenuItem(value: a, child: Text('${a}w'));
                    }),
                  ],
                  onChanged: (v) => provider.setBmkAge(v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent(DashboardProvider provider) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.customers.isEmpty && provider.flocks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.dashboard_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No customer or flock data yet'),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      children: [
        const HatchAnalysisSection(),
        const SizedBox(height: 16),
        const EggBreakoutSection(),
        const SizedBox(height: 16),
        const ChickQualitySection(),
        const SizedBox(height: 16),
        const EggStorageSection(),
        const SizedBox(height: 16),
        const SetterOptimizingSection(),
        const SizedBox(height: 16),
        const HatcherOptimizingSection(),
      ],
    );
  }
}
