import 'package:hatchaudit/localized_material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/debug/startup_timer.dart';
import 'core/navigation/modal_route_visibility_observer.dart';
import 'core/security/security_policy.dart';
import 'core/theme/app_theme.dart';
import 'features/audits/providers/audit_provider.dart';
import 'features/audits/providers/audit_session_provider.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/pending_approval_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/bmk/providers/bmk_provider.dart';
import 'features/dashboard/providers/dashboard_provider.dart';
import 'features/dashboard/providers/scope_comparison_provider.dart';
import 'features/govee/providers/govee_capture_provider.dart';
import 'features/govee/widgets/govee_global_overlay.dart';
import 'features/home/widgets/main_shell.dart';
import 'features/lab_analysis/providers/lab_analysis_provider.dart';
import 'features/performance/screens/performance_screen.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/sync/screens/startup_sync_screen.dart';
import 'providers/app_provider.dart';
import 'providers/customers_provider.dart';

class HatchAuditApp extends StatefulWidget {
  const HatchAuditApp({super.key});

  @override
  State<HatchAuditApp> createState() => _HatchAuditAppState();
}

class _HatchAuditAppState extends State<HatchAuditApp> {
  late final AuthProvider _authProvider;
  late final bool _authBypassEnabled;
  late final ModalRouteVisibilityObserver _modalRouteObserver;
  late final _AppRouteObserver _appRouteObserver;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final ValueNotifier<bool> _hasModalRoute = ValueNotifier<bool>(false);
  bool _showGlobalLauncher = false;
  bool _hasEnteredMainShell = false;
  String? _topRouteName;

  @override
  void initState() {
    super.initState();
    _authBypassEnabled = AuthSecurityPolicy.isDebugAuthBypassEnabled;
    _authProvider = AuthProvider(bypassAuth: _authBypassEnabled);
    _modalRouteObserver = ModalRouteVisibilityObserver(_hasModalRoute);
    _appRouteObserver = _AppRouteObserver(_rememberTopRouteName);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StartupTimer.lap('first_frame_rendered');
      if (mounted) {
        setState(() => _showGlobalLauncher = true);
      }
      _authProvider.checkCachedToken().then((_) {
        StartupTimer.lap('auth_check_complete');
      });
    });
  }

  @override
  void dispose() {
    _hasModalRoute.dispose();
    super.dispose();
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
        ChangeNotifierProvider(create: (_) => GoveeCaptureProvider()),
        ChangeNotifierProvider(create: (_) => BmkProvider()),
        ChangeNotifierProvider(create: (_) => LabAnalysisProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => ScopeComparisonProvider()),
      ],
      child: Consumer2<AuthProvider, SettingsProvider>(
        builder: (context, authProvider, settingsProvider, child) {
          final initialRoute = _getInitialRoute(authProvider.state);
          final routes = _buildRoutes(_authBypassEnabled);
          return MaterialApp(
            navigatorKey: _navigatorKey,
            navigatorObservers: [_modalRouteObserver, _appRouteObserver],
            title: 'ChickMark',
            locale: Locale(settingsProvider.languageCode),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            theme: AppTheme.light(),
            initialRoute: initialRoute,
            onGenerateInitialRoutes: (initialRouteName) {
              final routeName = routes.containsKey(initialRouteName)
                  ? initialRouteName
                  : initialRoute;
              return [_buildInitialRoute(routeName, routes)];
            },
            routes: routes,
            builder: (context, child) {
              final authRedirectRoute = authRedirectRouteForState(
                state: authProvider.state,
                topRouteName: _topRouteName,
              );
              if (authRedirectRoute != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _navigatorKey.currentState?.pushNamedAndRemoveUntil(
                    authRedirectRoute,
                    (_) => false,
                  );
                });
              }
              // Govee capture is an auditing tool — never expose it to
              // read-only customers, only auditors/admins (or dev bypass).
              final canUseGoveeLauncher =
                  _authBypassEnabled ||
                  (authProvider.state == AuthState.authenticated &&
                      (authProvider.user?.canEditAudits ?? false));
              final showGoveeLauncher = shouldShowGoveeGlobalLauncher(
                launcherReady: _showGlobalLauncher,
                canUseGoveeLauncher: canUseGoveeLauncher,
                hasEnteredMainShell: _hasEnteredMainShell,
                topRouteName: _topRouteName,
              );
              final isGoveeRecording = context
                  .select<GoveeCaptureProvider, bool>(
                    (provider) => provider.isRecording,
                  );
              return ValueListenableBuilder<bool>(
                valueListenable: _hasModalRoute,
                child: child ?? const SizedBox.shrink(),
                builder: (context, hasModalRoute, navigatorChild) {
                  return GoveeGlobalOverlay(
                    showLauncher: showGoveeLauncher && !hasModalRoute,
                    isRecording: isGoveeRecording,
                    panelContextBuilder: () => _navigatorKey.currentContext,
                    child: navigatorChild ?? const SizedBox.shrink(),
                  );
                },
              );
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

  Map<String, WidgetBuilder> _buildRoutes(bool authBypassEnabled) {
    if (authBypassEnabled) {
      return {
        '/login': (context) => const MainShell(),
        '/register': (context) => const MainShell(),
        '/pending-approval': (context) => const MainShell(),
        '/startup-sync': (context) => const MainShell(),
        '/main': (context) => const MainShell(),
        '/performance': (context) => const PerformanceScreen(),
      };
    }

    return {
      '/login': (context) => const LoginScreen(),
      '/register': (context) => const RegisterScreen(),
      '/pending-approval': (context) => const PendingApprovalScreen(),
      '/startup-sync': (context) => const StartupSyncScreen(),
      '/main': (context) => const MainShell(),
      '/performance': (context) => const PerformanceScreen(),
    };
  }

  Route<dynamic> _buildInitialRoute(
    String routeName,
    Map<String, WidgetBuilder> routes,
  ) {
    final builder =
        routes[routeName] ?? routes['/login'] ?? routes.values.first;
    _rememberTopRouteName(routeName, notify: false);
    return MaterialPageRoute<void>(
      settings: RouteSettings(name: routeName),
      builder: builder,
    );
  }

  void _rememberTopRouteName(String? routeName, {bool notify = true}) {
    final nextHasEnteredMainShell = _nextHasEnteredMainShell(
      routeName: routeName,
      currentValue: _hasEnteredMainShell,
    );
    if (_topRouteName == routeName &&
        _hasEnteredMainShell == nextHasEnteredMainShell) {
      return;
    }

    void update() {
      _topRouteName = routeName;
      _hasEnteredMainShell = nextHasEnteredMainShell;
    }

    if (!notify || !mounted) {
      update();
      return;
    }

    setState(update);
  }
}

const Set<String> _preAppRouteNames = {
  '/login',
  '/register',
  '/pending-approval',
  '/startup-sync',
};

bool _nextHasEnteredMainShell({
  required String? routeName,
  required bool currentValue,
}) {
  if (routeName == '/main') return true;
  if (_preAppRouteNames.contains(routeName)) return false;
  return currentValue;
}

@visibleForTesting
String? authRedirectRouteForState({
  required AuthState state,
  required String? topRouteName,
}) {
  switch (state) {
    case AuthState.unauthenticated:
    case AuthState.error:
      return _preAppRouteNames.contains(topRouteName) ? null : '/login';
    case AuthState.loading:
    case AuthState.authenticated:
    case AuthState.pendingApproval:
      return null;
  }
}

@visibleForTesting
bool shouldShowGoveeGlobalLauncher({
  required bool launcherReady,
  required bool canUseGoveeLauncher,
  required bool hasEnteredMainShell,
  required String? topRouteName,
}) {
  if (!launcherReady || !canUseGoveeLauncher) return false;
  if (_preAppRouteNames.contains(topRouteName)) return false;
  return hasEnteredMainShell || topRouteName == '/main';
}

class _AppRouteObserver extends NavigatorObserver {
  final ValueChanged<String?> onTopRouteChanged;

  _AppRouteObserver(this.onTopRouteChanged);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onTopRouteChanged(route.settings.name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onTopRouteChanged(previousRoute?.settings.name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    onTopRouteChanged(newRoute?.settings.name);
  }
}
