import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../auth/providers/auth_provider.dart';
import 'audit_context_screen.dart';

class AuditTypeSelectionScreen extends StatelessWidget {
  const AuditTypeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final canEdit = context.watch<AuthProvider>().user?.canEditAudits ?? false;
    if (!canEdit) {
      return const Scaffold(
        appBar: GradientAppBar(title: 'Select Audit Type'),
        body: Center(child: Text('This account has read-only access.')),
      );
    }

    return Scaffold(
      appBar: const GradientAppBar(title: 'Select Audit Type'),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        children: [
          _buildAuditTypeCard(
            context,
            icon: Icons.egg,
            title: 'Egg Storage',
            subtitle: 'Monitor egg storage conditions',
            color: Colors.orange,
            onTap: () => _navigateToContext(context, 'Egg Storage'),
          ),
          const SizedBox(height: 12),
          _buildAuditTypeCard(
            context,
            icon: Icons.cruelty_free,
            title: 'Chick Quality',
            subtitle: 'Assess chick health and quality',
            color: Colors.green,
            onTap: () => _navigateToContext(context, 'Chick Quality'),
          ),
          const SizedBox(height: 12),
          _buildAuditTypeCard(
            context,
            icon: Icons.bar_chart,
            title: 'Hatch Analysis',
            subtitle: 'Analyze hatch results and egg breakouts',
            color: Colors.blue,
            onTap: () => _navigateToContext(context, 'Hatch Analysis'),
          ),
          const SizedBox(height: 12),
          _buildAuditTypeCard(
            context,
            icon: Icons.thermostat,
            title: 'Setter Optimizing',
            subtitle: 'Optimize setter temperature and humidity',
            color: Colors.red,
            onTap: () => _navigateToContext(context, 'Setter Optimizing'),
          ),
          const SizedBox(height: 12),
          _buildAuditTypeCard(
            context,
            icon: Icons.device_thermostat,
            title: 'Hatcher Optimizing',
            subtitle: 'Optimize hatcher conditions',
            color: Colors.purple,
            onTap: () => _navigateToContext(context, 'Hatcher Optimizing'),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditTypeCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.cardPadding),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: AppTextStyles.caption),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToContext(BuildContext context, String auditType) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AuditContextScreen(auditType: auditType),
      ),
    );
  }
}
