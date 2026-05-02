import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/debug/startup_timer.dart';
import 'core/theme/app_theme.dart';
import 'features/audits/providers/audit_provider.dart';
import 'features/audits/providers/audit_session_provider.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/pending_approval_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/bmk/providers/bmk_provider.dart';
import 'features/dashboard/providers/dashboard_provider.dart';
import 'features/govee/providers/govee_capture_provider.dart';
import 'features/govee/widgets/govee_global_overlay.dart';
import 'features/home/widgets/main_shell.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/sync/screens/startup_sync_screen.dart';
import 'features/temperature/providers/temperature_rh_provider.dart';
import 'providers/app_provider.dart';
import 'providers/customers_provider.dart';

const Set<String> _goveeLauncherRoutes = {'/main'};

String _initialRouteForAuthState(AuthState state) {
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

bool shouldShowGoveeLauncher({
  required AuthState state,
  required bool hasObservedRoute,
  required String? currentRoute,
  required bool currentRouteIsPageRoute,
}) {
  if (state != AuthState.authenticated) return false;
  if (hasObservedRoute && !currentRouteIsPageRoute) return false;
  final routeName = hasObservedRoute
      ? currentRoute ?? _initialRouteForAuthState(state)
      : _initialRouteForAuthState(state);
  return _goveeLauncherRoutes.contains(routeName);
}

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
        ChangeNotifierProvider(create: (_) => GoveeCaptureProvider()),
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
            builder: (context, child) => GoveeGlobalOverlay(
              showLauncher: _shouldShowGovee(authProvider.state),
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
    return _initialRouteForAuthState(state);
  }

  bool _shouldShowGovee(AuthState state) {
    return shouldShowGoveeLauncher(
      state: state,
      hasObservedRoute: _hasObservedRoute,
      currentRoute: _currentRoute,
      currentRouteIsPageRoute: _currentRouteIsPageRoute,
    );
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
