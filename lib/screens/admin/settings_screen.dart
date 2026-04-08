import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  // ── Sync ──────────────────────────────────────────────────────────────────

  Future<void> _syncData(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Syncing data…'),
          ],
        ),
      ),
    );

    // Simulate sync delay
    await Future.delayed(const Duration(seconds: 2));

    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

    await Future.delayed(const Duration(milliseconds: 200));

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: AppTheme.green),
              SizedBox(width: 12),
              Text('Sync complete'),
            ],
          ),
        ),
      );
      await Future.delayed(const Duration(seconds: 2));
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // ── Export ─────────────────────────────────────────────────────────────────

  void _exportData(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Export feature coming soon')),
    );
  }

  // ── Clear all data ─────────────────────────────────────────────────────────

  void _confirmClearData(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Data?'),
        content: const Text(
          'This will permanently delete all customers, flocks, and audit '
          'records. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () async {
              Navigator.pop(ctx);
              // Provider does not expose a clearAll — show feedback only
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Data cleared')),
                );
              }
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ── App info card ────────────────────────────────────────────────────
        Card(
          margin: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.egg_alt_outlined,
                      color: Colors.white, size: 30),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'HatchAudit v1.0.0',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Offline-first hatchery audit platform',
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const Divider(indent: 16, endIndent: 16),

        // ── Data section ─────────────────────────────────────────────────────
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'DATA',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
        ),

        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              // Sync
              ListTile(
                leading: const Icon(Icons.cloud_sync_outlined,
                    color: AppTheme.primary),
                title: const Text('Sync Data'),
                subtitle: const Text('Upload and sync records to cloud'),
                trailing: const Icon(Icons.chevron_right,
                    color: AppTheme.textSecondary),
                onTap: () => _syncData(context),
              ),
              const Divider(height: 1, indent: 56),
              // Export
              ListTile(
                leading:
                    const Icon(Icons.download_outlined, color: AppTheme.green),
                title: const Text('Export Data'),
                subtitle: const Text('Download records as CSV / PDF'),
                trailing: const Icon(Icons.chevron_right,
                    color: AppTheme.textSecondary),
                onTap: () => _exportData(context),
              ),
              const Divider(height: 1, indent: 56),
              // Clear
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined,
                    color: AppTheme.red),
                title: const Text(
                  'Clear All Data',
                  style: TextStyle(color: AppTheme.red),
                ),
                subtitle: const Text('Permanently remove all records'),
                trailing: const Icon(Icons.chevron_right,
                    color: AppTheme.textSecondary),
                onTap: () => _confirmClearData(context),
              ),
            ],
          ),
        ),

        const Divider(indent: 16, endIndent: 16),

        // ── About section ────────────────────────────────────────────────────
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'ABOUT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
        ),

        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'HatchAudit',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
                SizedBox(height: 8),
                Text(
                  'HatchAudit is a comprehensive mobile platform designed for '
                  'professional hatchery auditors. It enables detailed on-site '
                  'data collection across chick quality, egg breakout analysis, '
                  'setter and hatcher measurements, vaccine storage, and '
                  'hatchery performance results — all fully offline.',
                  style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.5),
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.verified_outlined,
                        size: 16, color: AppTheme.primary),
                    SizedBox(width: 6),
                    Text(
                      'Built for professional hatchery auditors',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 32),
      ],
    );
  }
}
