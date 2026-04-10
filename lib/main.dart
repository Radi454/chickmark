import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/app_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home_screen.dart';
import 'utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use IndexedDB-backed sqflite on web
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }

  final provider = AppProvider();
  await provider.initialize();

  final prefs = await SharedPreferences.getInstance();
  final isLoggedIn = prefs.getBool('is_logged_in') ?? false;

  runApp(
    ChangeNotifierProvider.value(
      value: provider, 
      child: HatchAuditApp(isLoggedIn: isLoggedIn)
    ),
  );
}

class HatchAuditApp extends StatelessWidget {
  final bool isLoggedIn;
  
  const HatchAuditApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChickMark',
      theme: AppTheme.theme,
      home: isLoggedIn ? const HomeScreen() : const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
