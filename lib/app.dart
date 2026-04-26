import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/debug/startup_timer.dart';
import 'providers/app_provider.dart';
import 'providers/customers_provider.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/auth/screens/pending_approval_screen.dart';
import 'features/audits/providers/audit_provider.dart';
import 'features/audits/providers/audit_session_provider.dart';
import 'features/temperature/providers/temperature_rh_provider.dart';
import 'features/temperature/widgets/temperature_rh_launcher.dart';
import 'features/home/widgets/main_shell.dart';
import 'features/bmk/providers/bmk_provider.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/dashboard/providers/dashboard_provider.dart';
import 'features/sync/screens/startup_sync_screen.dart';
import 'core/constants/app_colors.dart';
import 'core/theme/app_theme.dart';

class HatchAuditApp extends StatefulWidget {
  const HatchAuditApp({super.key});

  @override
  State<HatchAuditApp> createState() => _HatchAuditAppState();
}

class _HatchAuditAppState extends State<HatchAuditApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final AuthProvider _authProvider;
  String? _currentRoute;
  String? _pendingRoute;
  bool _hasObservedRoute = false;
  bool _currentRouteIsPageRoute = true;
  bool _pendingRouteIsPageRoute = true;
  bool _routeUpdateScheduled = false;

  static const Set<String> _measureHiddenRoutes = {'/login'};

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StartupTimer.lap('first_frame_rendered');
      _authProvider.checkCachedToken().then((_) {
        StartupTimer.lap('auth_check_complete');
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider(create: (_) => CustomersProvider()),
        ChangeNotifierProvider(create: (_) => AuditProvider()),
        ChangeNotifierProvider(create: (_) => AuditSessionProvider()),
        ChangeNotifierProvider(create: (_) => TemperatureRhProvider()),
        ChangeNotifierProvider(create: (_) => BmkProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          return MaterialApp(
            navigatorKey: _navigatorKey,
            navigatorObservers: [
              _RouteNameObserver(onRouteChanged: _handleRouteChanged),
            ],
            title: 'ChickMark',
            theme: AppTheme.light(),
            initialRoute: _getInitialRoute(authProvider.state),
            builder: (context, child) => _AppMeasureOverlay(
              showMeasure: _shouldShowMeasure(authProvider.state),
              panelContextBuilder: () => _navigatorKey.currentContext,
              child: child ?? const SizedBox.shrink(),
            ),
            routes: {
              '/login': (context) => const LoginScreen(),
              '/register': (context) => const RegisterScreen(),
              '/pending-approval': (context) => const PendingApprovalScreen(),
              '/startup-sync': (context) => const StartupSyncScreen(),
              '/main': (context) => const MainShell(),
            },
          );
        },
      ),
    );
  }

  String _getInitialRoute(AuthState state) {
    switch (state) {
      case AuthState.authenticated:
        return '/main';
      case AuthState.pendingApproval:
        return '/pending-approval';
      case AuthState.loading:
        return '/login';
      case AuthState.error:
      case AuthState.unauthenticated:
        return '/login';
    }
  }

  bool _shouldShowMeasure(AuthState state) {
    if (state != AuthState.authenticated) {
      return false;
    }

    if (_hasObservedRoute && !_currentRouteIsPageRoute) {
      return false;
    }

    final routeName = _hasObservedRoute
        ? _currentRoute
        : _getInitialRoute(state);
    return !_measureHiddenRoutes.contains(routeName);
  }

  void _handleRouteChanged(Route<dynamic>? route) {
    final routeName = route?.settings.name;
    final isPageRoute = route == null || route is PageRoute<dynamic>;
    if (_hasObservedRoute &&
        _currentRoute == routeName &&
        _currentRouteIsPageRoute == isPageRoute) {
      return;
    }

    _pendingRoute = routeName;
    _pendingRouteIsPageRoute = isPageRoute;
    if (_routeUpdateScheduled) return;

    _routeUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeUpdateScheduled = false;
      if (!mounted) return;

      final nextRoute = _pendingRoute;
      final nextIsPageRoute = _pendingRouteIsPageRoute;
      _pendingRoute = null;
      if (_hasObservedRoute &&
          _currentRoute == nextRoute &&
          _currentRouteIsPageRoute == nextIsPageRoute) {
        return;
      }

      setState(() {
        _hasObservedRoute = true;
        _currentRoute = nextRoute;
        _currentRouteIsPageRoute = nextIsPageRoute;
      });
    });
  }
}

class _RouteNameObserver extends NavigatorObserver {
  final ValueChanged<Route<dynamic>?> onRouteChanged;

  _RouteNameObserver({required this.onRouteChanged});

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onRouteChanged(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    onRouteChanged(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onRouteChanged(previousRoute);
  }
}

class _AppMeasureOverlay extends StatefulWidget {
  final Widget child;
  final bool showMeasure;
  final BuildContext? Function() panelContextBuilder;

  const _AppMeasureOverlay({
    required this.child,
    required this.showMeasure,
    required this.panelContextBuilder,
  });

  @override
  State<_AppMeasureOverlay> createState() => _AppMeasureOverlayState();
}

class _AppMeasureOverlayState extends State<_AppMeasureOverlay> {
  static const double _launcherWidth = 64;
  static const double _launcherHeight = 64;
  static const double _edgePadding = 34;
  static const double _defaultBottomOffset = 96;
  static const double _dockHandleWidth = 38;
  static const double _dockHandleHeight = 72;
  static const double _dockThreshold = 42;

  bool _panelOpen = false;
  Offset? _launcherOffset;
  _DockSide? _dockSide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = MediaQuery.paddingOf(context);
        final overlaySize = Size(constraints.maxWidth, constraints.maxHeight);
        final offset = _resolvedOffset(overlaySize, padding);

        return Stack(
          children: [
            widget.child,
            if (widget.showMeasure && !_panelOpen)
              if (_dockSide == null)
                Positioned(
                  left: offset.dx,
                  top: offset.dy,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanUpdate: (details) =>
                        _moveLauncher(details.delta, overlaySize, padding),
                    onPanEnd: (_) => _settleLauncher(overlaySize, padding),
                    child: TemperatureRhLauncher(
                      panelContextBuilder: widget.panelContextBuilder,
                      onPanelVisibilityChanged: _setPanelOpen,
                    ),
                  ),
                )
              else
                Positioned(
                  left: _dockSide == _DockSide.left ? 0 : null,
                  right: _dockSide == _DockSide.right ? 0 : null,
                  top: offset.dy + (_launcherHeight - _dockHandleHeight) / 2,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _pullLauncherBack(overlaySize, padding),
                    onHorizontalDragEnd: (_) =>
                        _pullLauncherBack(overlaySize, padding),
                    child: _MeasurePullTab(side: _dockSide!),
                  ),
                ),
          ],
        );
      },
    );
  }

  void _setPanelOpen(bool isOpen) {
    if (_panelOpen == isOpen || !mounted) return;
    setState(() {
      _panelOpen = isOpen;
    });
  }

  Offset _resolvedOffset(Size overlaySize, EdgeInsets padding) {
    return _clampOffset(
      _launcherOffset ??
          Offset(
            overlaySize.width - _launcherWidth - _edgePadding,
            overlaySize.height -
                padding.bottom -
                _launcherHeight -
                _defaultBottomOffset,
          ),
      overlaySize,
      padding,
      allowDockRange: _dockSide == null,
    );
  }

  Offset _clampOffset(
    Offset offset,
    Size overlaySize,
    EdgeInsets padding, {
    required bool allowDockRange,
  }) {
    final minTop = padding.top + _edgePadding;
    final rawMaxTop =
        overlaySize.height - padding.bottom - _launcherHeight - _edgePadding;
    final minLeft = allowDockRange ? -_launcherWidth + _dockHandleWidth : 0.0;
    final rawMaxLeft = allowDockRange
        ? overlaySize.width - _dockHandleWidth
        : overlaySize.width - _launcherWidth;
    final maxTop = rawMaxTop < minTop ? minTop : rawMaxTop;
    final maxLeft = rawMaxLeft < minLeft ? minLeft : rawMaxLeft;

    return Offset(
      offset.dx.clamp(minLeft, maxLeft).toDouble(),
      offset.dy.clamp(minTop, maxTop).toDouble(),
    );
  }

  void _moveLauncher(Offset delta, Size overlaySize, EdgeInsets padding) {
    setState(() {
      _dockSide = null;
      _launcherOffset = _clampOffset(
        _resolvedOffset(overlaySize, padding) + delta,
        overlaySize,
        padding,
        allowDockRange: true,
      );
    });
  }

  void _settleLauncher(Size overlaySize, EdgeInsets padding) {
    final offset = _resolvedOffset(overlaySize, padding);
    final shouldDockLeft = offset.dx <= _dockThreshold;
    final shouldDockRight =
        offset.dx + _launcherWidth >= overlaySize.width - _dockThreshold;

    setState(() {
      if (shouldDockLeft) {
        _dockSide = _DockSide.left;
        _launcherOffset = Offset(-_launcherWidth + _dockHandleWidth, offset.dy);
      } else if (shouldDockRight) {
        _dockSide = _DockSide.right;
        _launcherOffset = Offset(
          overlaySize.width - _dockHandleWidth,
          offset.dy,
        );
      } else {
        _dockSide = null;
        _launcherOffset = _clampOffset(
          offset,
          overlaySize,
          padding,
          allowDockRange: false,
        );
      }
    });
  }

  void _pullLauncherBack(Size overlaySize, EdgeInsets padding) {
    final side = _dockSide;
    if (side == null) return;

    setState(() {
      _dockSide = null;
      _launcherOffset = _clampOffset(
        Offset(
          side == _DockSide.left
              ? _edgePadding
              : overlaySize.width - _launcherWidth - _edgePadding,
          _resolvedOffset(overlaySize, padding).dy,
        ),
        overlaySize,
        padding,
        allowDockRange: false,
      );
    });
  }
}

enum _DockSide { left, right }

class _MeasurePullTab extends StatelessWidget {
  final _DockSide side;

  const _MeasurePullTab({required this.side});

  @override
  Widget build(BuildContext context) {
    final isLeft = side == _DockSide.left;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: _AppMeasureOverlayState._dockHandleWidth,
        height: _AppMeasureOverlayState._dockHandleHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.horizontal(
            left: isLeft ? Radius.zero : const Radius.circular(24),
            right: isLeft ? const Radius.circular(24) : Radius.zero,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x240B2D5C),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Icon(
          isLeft ? Icons.chevron_right : Icons.chevron_left,
          color: AppColors.primary,
          size: 30,
        ),
      ),
    );
  }
}
