import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite/sqflite.dart';
import 'providers/app_provider.dart';
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

  runApp(
    ChangeNotifierProvider.value(value: provider, child: const HatchAuditApp()),
  );
}

class HatchAuditApp extends StatelessWidget {
  const HatchAuditApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChickMark',
      theme: AppTheme.theme,
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
