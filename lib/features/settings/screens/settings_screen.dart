import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/providers/app_provider.dart';
import 'package:hatchaudit/widgets/section_card.dart';
import 'package:hatchaudit/widgets/status_badge.dart';
import 'package:hatchaudit/features/settings/providers/settings_provider.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/features/admin/screens/admin_users_screen.dart';
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
          final currentUser = auth.user ?? app.currentUser;
          final isCustomer = currentUser?.isCustomer ?? false;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.cardPadding),
            child: Column(
              // Read-only customers get account + sign-out only — no
              // preferences, sync controls, admin tools or app internals.
              children: isCustomer
                  ? [_buildAccountSection(context, app, auth)]
                  : [
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
      icon: Icons.person_outline,
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
                    fontSize: 18,
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
                      style: AppTextStyles.title,
                    ),
                    const SizedBox(height: AppSizes.spaceXs),
                    Text(
                      user?.email ?? 'No email',
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(height: AppSizes.spaceXs),
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
      icon: Icons.tune_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                flex: 2,
                child: Text('Temperature Unit', style: AppTextStyles.body),
              ),
              _buildTempUnitToggle(app),
            ],
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

  Widget _buildTempUnitToggle(AppProvider app) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tempUnitOption(app, TempUnit.fahrenheit, '°F'),
          _tempUnitOption(app, TempUnit.celsius, '°C'),
        ],
      ),
    );
  }

  Widget _tempUnitOption(AppProvider app, TempUnit unit, String label) {
    final selected = app.tempUnit == unit;
    return GestureDetector(
      onTap: () => app.setTempUnit(unit),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: AppTextStyles.body.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
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
        Expanded(flex: 2, child: Text(label, style: AppTextStyles.body)),
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
    final Color statusColor;
    final IconData statusIcon;
    final String statusLabel;
    if (settings.isSyncing) {
      statusColor = AppColors.primary;
      statusIcon = Icons.sync;
      statusLabel = 'Syncing…';
    } else if (settings.lastSyncError != null) {
      statusColor = Colors.red;
      statusIcon = Icons.error_outline;
      statusLabel = 'Last sync failed';
    } else if (!settings.hasSyncedBefore) {
      statusColor = AppColors.textDisabled;
      statusIcon = Icons.cloud_off_outlined;
      statusLabel = 'Not synced yet';
    } else if (!settings.lastSyncOnline) {
      statusColor = AppColors.statusWarning;
      statusIcon = Icons.cloud_off_outlined;
      statusLabel = 'Offline — using local data';
    } else {
      statusColor = AppColors.completedText;
      statusIcon = Icons.cloud_done_outlined;
      statusLabel = 'Connected';
    }

    return SectionCard(
      title: 'Sync',
      icon: Icons.cloud_sync_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, size: 18, color: statusColor),
              const SizedBox(width: 8),
              Text(
                statusLabel,
                style: AppTextStyles.title.copyWith(color: statusColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _syncStat(
                  Icons.arrow_upward,
                  'Uploaded',
                  settings.lastSyncPushed,
                  AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _syncStat(
                  Icons.arrow_downward,
                  'Downloaded',
                  settings.lastSyncPulled,
                  AppColors.completedText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            settings.lastSyncTimestamp == null
                ? 'No sync yet'
                : 'Last synced: ${_formatSyncTime(settings.lastSyncTimestamp!)}',
            style: AppTextStyles.caption,
          ),
          if (settings.lastSyncError != null) ...[
            const SizedBox(height: 4),
            Text(
              settings.lastSyncError!,
              style: AppTextStyles.caption.copyWith(color: Colors.red),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: settings.isSyncing
                  ? null
                  : () => _syncNow(context, settings),
              icon: settings.isSyncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sync),
              label: Text(settings.isSyncing ? 'Syncing…' : 'Sync Now'),
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

  Widget _syncStat(IconData icon, String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSizes.iconRadius),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('$value', style: AppTextStyles.title.copyWith(color: color)),
        ],
      ),
    );
  }

  String _formatSyncTime(String timestamp) {
    final parsed = DateTime.tryParse(timestamp)?.toLocal();
    if (parsed == null) return timestamp;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} '
        '${two(parsed.hour)}:${two(parsed.minute)}';
  }

  Widget _buildAppSection() {
    return SectionCard(
      title: 'App',
      icon: Icons.info_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Version: 1.0.0+1', style: AppTextStyles.body),
          const SizedBox(height: AppSizes.spaceSm),
          const Text('ChickMark - Hatchery Audit', style: AppTextStyles.body),
        ],
      ),
    );
  }

  Widget _buildAdminSection(BuildContext context) {
    return SectionCard(
      title: 'Admin Tools',
      icon: Icons.admin_panel_settings_outlined,
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.manage_accounts_outlined),
            title: const Text('User access'),
            subtitle: const Text('Roles, approval & customer assignments'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: const Text('Activity Log'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ActivityLogScreen()),
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
    settings.markSyncing();
    try {
      final outcome = await StartupSyncService().run(userId: currentUser?.id);
      await customersProvider.loadCustomers(currentUser: currentUser);
      await settings.recordSync(
        online: outcome.online,
        pushed: outcome.pushed,
        pulled: outcome.pulled,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              outcome.online
                  ? 'Sync complete · ↑${outcome.pushed} ↓${outcome.pulled}'
                  : 'Offline — using local data',
            ),
          ),
        );
      }
    } catch (error) {
      await settings.recordSync(
        online: false,
        pushed: 0,
        pulled: 0,
        error: error.toString(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sync failed: $error')));
      }
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
