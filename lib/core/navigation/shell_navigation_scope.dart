import 'package:flutter/widgets.dart';

class ShellNavigationScope extends InheritedWidget {
  final VoidCallback openDrawer;
  final VoidCallback goBack;
  final ValueChanged<int> switchTab;
  final bool hasDrawer;
  final bool canGoBack;

  const ShellNavigationScope({
    super.key,
    required this.openDrawer,
    required this.goBack,
    required this.switchTab,
    required this.hasDrawer,
    required this.canGoBack,
    required super.child,
  });

  static ShellNavigationScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ShellNavigationScope>();
  }

  @override
  bool updateShouldNotify(ShellNavigationScope oldWidget) {
    return openDrawer != oldWidget.openDrawer ||
        goBack != oldWidget.goBack ||
        switchTab != oldWidget.switchTab ||
        hasDrawer != oldWidget.hasDrawer ||
        canGoBack != oldWidget.canGoBack;
  }
}
