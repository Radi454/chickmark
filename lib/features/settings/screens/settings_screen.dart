import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/providers/app_provider.dart';
import 'package:hatchaudit/widgets/section_card.dart';
import 'package:hatchaudit/widgets/status_badge.dart';
import 'package:hatchaudit/features/settings/providers/settings_provider.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/features/settings/screens/activity_log_screen.dart';
import 'package:hatchaudit/services/backup/backup_service.dart';
import 'package:hatchaudit/services/supabase/startup_sync_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientAppBar(title: 'Settings'),
      body: Consumer3<AppProvider, SettingsProvider, AuthProvider>(
        builder: (context, app, settings, auth, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.cardPadding),
            child: Column(
              children: [
                _buildAccountSection(context, app, auth),
                const SizedBox(height: 16),
                _buildPreferencesSection(context, app, settings),
                const SizedBox(height: 16),
                _buildSyncSection(context, settings),
                const SizedBox(height: 16),
                if ((auth.user ?? app.currentUser)?.isAdmin ?? false) ...[
                  _buildAdminSection(context),
                  const SizedBox(height: 16),
                ],
                _buildAppSection(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAccountSection(
    BuildContext context,
    AppProvider app,
    AuthProvider auth,
  ) {
    final user = auth.user ?? app.currentUser;
    final initials = user?.fullName != null && user!.fullName.isNotEmpty
        ? user.fullName.split(' ').map((e) => e[0]).take(2).join().toUpperCase()
        : '?';

    return SectionCard(
      title: 'Account',
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.primary,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.fullName ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? 'No email',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    if (user?.role != null) StatusBadge(status: user!.role),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _confirmLogout(context, auth),
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesSection(
    BuildContext context,
    AppProvider app,
    SettingsProvider settings,
  ) {
    return SectionCard(
      title: 'Preferences',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Temperature Unit',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          SegmentedButton<TempUnit>(
            segments: const [
              ButtonSegment(value: TempUnit.fahrenheit, label: Text('°F')),
              ButtonSegment(value: TempUnit.celsius, label: Text('°C')),
            ],
            selected: {app.tempUnit},
            onSelectionChanged: (selected) {
              app.setTempUnit(selected.first);
            },
          ),
          const SizedBox(height: 16),
          _buildNumberField(
            'Pasgar Sample Size',
            settings.pasgarSampleSize,
            (value) => settings.setPasgarSampleSize(int.tryParse(value) ?? 40),
          ),
          const SizedBox(height: 12),
          _buildNumberField(
            'Weights Sample Size',
            settings.weightsSampleSize,
            (value) =>
                settings.setWeightsSampleSize(int.tryParse(value) ?? 100),
          ),
          const SizedBox(height: 12),
          _buildNumberField(
            'Tray Size',
            settings.traySize,
            (value) => settings.setTraySize(int.tryParse(value) ?? 150),
          ),
          const SizedBox(height: 12),
          _buildNumberField(
            'Storage Days',
            settings.storageDays,
            (value) => settings.setStorageDays(int.tryParse(value) ?? 0),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberField(
    String label,
    int value,
    Function(String) onChanged,
  ) {
    return Row(
      children: [
        Expanded(flex: 2, child: Text(label)),
        Expanded(
          child: TextFormField(
            initialValue: '$value',
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onFieldSubmitted: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildSyncSection(BuildContext context, SettingsProvider settings) {
    return SectionCard(
      title: 'Sync',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppColors.completedText,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text('Connected'),
            ],
          ),
          const SizedBox(height: 12),
          if (settings.lastSyncTimestamp != null)
            Text(
              'Last synced: ${settings.lastSyncTimestamp}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _syncNow(context, settings),
              icon: const Icon(Icons.sync),
              label: const Text('Sync Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppSection() {
    return SectionCard(
      title: 'App',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Version: 1.0.0+1'),
          const SizedBox(height: 8),
          const Text('ChickMark - Hatchery Audit'),
        ],
      ),
    );
  }

  Widget _buildAdminSection(BuildContext context) {
    return SectionCard(
      title: 'Admin Tools',
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: const Text('Activity Log'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ActivityLogScreen(),
                ),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Backup database'),
            onTap: () async {
              await BackupService().exportBackup();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.restore_outlined),
            title: const Text('Restore from backup'),
            subtitle: const Text('This will replace ALL current data'),
            onTap: () => _confirmRestore(context),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await auth.logout();
              if (context.mounted) {
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/login', (_) => false);
              }
            },
            child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _syncNow(BuildContext context, SettingsProvider settings) async {
    final customersProvider = context.read<CustomersProvider>();
    final currentUser = context.read<AuthProvider>().user;
    await StartupSyncService().run(userId: currentUser?.id);
    await customersProvider.loadCustomers(currentUser: currentUser);
    await settings.updateLastSync(DateTime.now().toIso8601String());
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sync complete')));
    }
  }

  Future<void> _confirmRestore(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from backup'),
        content: const Text(
          'This will permanently replace all current data with the backup. This cannot be undone. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace All Data'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await BackupService().importBackup();
  }
}
