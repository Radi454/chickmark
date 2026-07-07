import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/security/security_policy.dart';
import '../../auth/providers/auth_provider.dart';

/// Hard, defense-in-depth gate for audit screens.
///
/// The real authorization boundary is Postgres RLS (a read-only customer can
/// never write audit data regardless of the UI). This guard is the client-side
/// belt-and-suspenders: it stops a non-auditor from ever *rendering* an audit
/// screen, even if one is reached by a deep link, a stray `Navigator.push`, or
/// a future bug — not just hidden from the nav.
class AuditAccess {
  const AuditAccess._();

  /// True for approved auditors/admins (or the debug auth-bypass dev build).
  static bool allowed(BuildContext context) {
    if (AuthSecurityPolicy.isDebugAuthBypassEnabled) return true;
    return context.watch<AuthProvider>().user?.canEditAudits ?? false;
  }
}

/// Shown in place of an audit screen when the current account may not audit.
class AuditAccessDenied extends StatelessWidget {
  const AuditAccessDenied({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Auditing')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 56, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Auditing isn\'t available for your account',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Your role has read-only access to dashboards and benchmarks.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
