import 'package:flutter/material.dart';

class AuditKeyboardDismiss extends StatelessWidget {
  final Widget child;
  final bool enabled;

  const AuditKeyboardDismiss({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}
