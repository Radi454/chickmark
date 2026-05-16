import 'package:flutter/material.dart';

class ModalRouteVisibilityObserver extends NavigatorObserver {
  final ValueNotifier<bool> hasModalRoute;
  final List<Route<dynamic>> _modalRoutes = [];

  ModalRouteVisibilityObserver(this.hasModalRoute);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _addIfModal(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _removeIfTracked(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _removeIfTracked(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (oldRoute != null) _removeIfTracked(oldRoute);
    if (newRoute != null) _addIfModal(newRoute);
  }

  void _addIfModal(Route<dynamic> route) {
    if (route is! PopupRoute || _modalRoutes.contains(route)) return;
    _modalRoutes.add(route);
    _syncVisibility();
  }

  void _removeIfTracked(Route<dynamic> route) {
    if (!_modalRoutes.remove(route)) return;
    _syncVisibility();
  }

  void _syncVisibility() {
    hasModalRoute.value = _modalRoutes.isNotEmpty;
  }
}
