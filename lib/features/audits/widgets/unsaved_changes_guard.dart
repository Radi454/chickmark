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
        if (!provider.isDirty) {
          if (context.mounted) {
            Navigator.of(context).pop();
          }
          return;
        }

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Unsaved changes'),
            content: const Text('Leave without saving this tab?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Leave'),
              ),
            ],
          ),
        );

        if (confirmed == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: child,
    );
  }
}
