import 'dart:math' as math;

import 'package:flutter/material.dart';

double auditStationKeyboardInset(BuildContext context) {
  final view = View.of(context);
  return math.max(
    MediaQuery.viewInsetsOf(context).bottom,
    view.viewInsets.bottom / view.devicePixelRatio,
  );
}

EdgeInsets auditStationKeyboardAwarePadding(
  BuildContext context,
  EdgeInsets padding,
) {
  final keyboardInset = auditStationKeyboardInset(context);
  if (keyboardInset <= 0) return padding;
  return padding.copyWith(bottom: padding.bottom + keyboardInset + 24);
}

class AuditStationScrollView extends StatelessWidget {
  final Key? scrollKey;
  final ScrollController? controller;
  final EdgeInsets padding;
  final Widget child;

  const AuditStationScrollView({
    super.key,
    this.scrollKey,
    this.controller,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: scrollKey,
      controller: controller,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: auditStationKeyboardAwarePadding(context, padding),
      child: child,
    );
  }
}

class AuditStationListView extends StatelessWidget {
  final ScrollController? controller;
  final EdgeInsets padding;
  final List<Widget> children;

  const AuditStationListView({
    super.key,
    this.controller,
    required this.padding,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: auditStationKeyboardAwarePadding(context, padding),
      children: children,
    );
  }
}
