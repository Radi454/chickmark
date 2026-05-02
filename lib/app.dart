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
import 'features/home/widgets/main_shell.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/sync/screens/startup_sync_screen.dart';
import 'features/temperature/providers/temperature_rh_provider.dart';
import 'providers/app_provider.dart';
import 'providers/customers_provider.dart';

class HatchAuditApp extends StatefulWidget {
  const HatchAuditApp({super.key});

  @override
  State<HatchAuditApp> createState() => _HatchAuditAppState();
}

class _HatchAuditAppState extends State<HatchAuditApp> {
  late final AuthProvider _authProvider;

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
            title: 'ChickMark',
            theme: AppTheme.light(),
            initialRoute: _getInitialRoute(authProvider.state),
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
}
