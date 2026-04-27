import 'package:flutter/material.dart';

class AuditKeyboardDismiss extends StatelessWidget {
  final Widget child;

  const AuditKeyboardDismiss({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}
