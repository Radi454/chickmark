import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/audit_provider.dart';

class UnsavedChangesGuard extends StatelessWidget {
  final Widget child;

  const UnsavedChangesGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

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
