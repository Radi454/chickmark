import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_provider.dart';
import 'providers/customers_provider.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/auth/screens/pending_approval_screen.dart';
import 'features/audits/providers/audit_provider.dart';
import 'features/home/widgets/main_shell.dart';
import 'features/bmk/providers/bmk_provider.dart';
import 'features/settings/providers/settings_provider.dart';
import 'core/theme/app_theme.dart';

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
      _authProvider.checkCachedToken();
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
        ChangeNotifierProvider(create: (_) => BmkProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
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
