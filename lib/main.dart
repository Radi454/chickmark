import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/supabase_config.dart';
import 'core/debug/startup_timer.dart';
import 'data/database/database_helper.dart';
import 'data/repositories/user_repository.dart';
import 'services/notifications/notification_service.dart';
import 'app.dart';

void main() async {
  StartupTimer.lap('main_start');
  WidgetsFlutterBinding.ensureInitialized();

  StartupTimer.lap('binding_ready');

  // Database initialization is required before runApp
  // Auth check and other operations depend on local DB
  await DatabaseHelper().db;
  StartupTimer.lap('db_init_complete');

  // Fire non-blocking initializations in parallel while UI renders
  // These are not required for the first frame or auth check
  _initBackgroundServices();

  StartupTimer.lap('runApp_called');
  runApp(const HatchAuditApp());
}

void _initBackgroundServices() {
  // Token migration, notification init, and Supabase init are not
  // required before the first frame. Run them in background.
  UserRepository().migrateRemoteTokensToSecureStorage().then((_) {
    StartupTimer.lap('token_migration_complete');
  }).catchError((e) {
    debugPrint('Secure token migration failed: $e');
  });

  NotificationService.init().then((_) {
    StartupTimer.lap('notification_init_complete');
  }).catchError((e) {
    debugPrint('Notification initialization failed: $e');
  });

  if (SupabaseConfig.isConfigured) {
    Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    ).then((_) {
      StartupTimer.lap('supabase_init_complete');
    }).catchError((e) {
      debugPrint('Supabase initialization failed: $e');
    });
  }
}
