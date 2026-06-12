import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'audit_numeric_keyboard.dart';

class WeightEntrySheetScrollView extends StatelessWidget {
  final ScrollController? controller;
  final Widget child;
  final EdgeInsets padding;
  final AuditNumericInputMode inputMode;

  const WeightEntrySheetScrollView({
    super.key,
    required this.child,
    this.controller,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
    this.inputMode = AuditNumericInputMode.adaptive,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final viewInset = mediaQuery.viewInsets.bottom;
    final usesCustomKeyboard = auditNumericInputModeUsesCustomKeyboard(
      inputMode,
    );
    final customKeyboardInset = usesCustomKeyboard
        ? AuditNumericKeyboard.estimatedHeightForWidth(
            mediaQuery.size.width,
            safeAreaBottom: mediaQuery.padding.bottom,
          )
        : 0.0;

    return SingleChildScrollView(
      controller: controller,
      keyboardDismissBehavior: usesCustomKeyboard
          ? ScrollViewKeyboardDismissBehavior.manual
          : ScrollViewKeyboardDismissBehavior.onDrag,
      padding: padding.copyWith(
        bottom: padding.bottom + math.max(viewInset, customKeyboardInset),
      ),
      child: child,
    );
  }
}
