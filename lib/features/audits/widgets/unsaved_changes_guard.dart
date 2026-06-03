import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/audit_provider.dart';

class UnsavedChangesGuard extends StatelessWidget {
  final Widget child;
  final bool enabled;
  final VoidCallback? onBackAttempt;

  const UnsavedChangesGuard({
    super.key,
    required this.child,
    this.enabled = true,
    this.onBackAttempt,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        onBackAttempt?.call();

        final provider = context.read<AuditProvider>();
        if (!provider.hasPendingAutosave) {
          if (context.mounted) {
            Navigator.of(context).pop();
          }
          return;
        }

        final saved = await provider.flushAutosave();
        if (saved && context.mounted) {
          Navigator.of(context).pop();
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not autosave. Press Save to retry.'),
            ),
          );
        }
      },
      child: child,
    );
  }
}
