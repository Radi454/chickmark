import 'dart:async';

import 'package:flutter/material.dart';
import 'core/debug/startup_timer.dart';
import 'core/security/safe_debug_log.dart';
import 'data/database/database_factory_initializer.dart';
import 'data/database/database_helper.dart';
import 'data/repositories/user_repository.dart';
import 'services/notifications/notification_service.dart';
import 'services/supabase/supabase_initializer.dart';
import 'app.dart';

void main() async {
  StartupTimer.lap('main_start');
  WidgetsFlutterBinding.ensureInitialized();

  StartupTimer.lap('binding_ready');

  // Database initialization is required before runApp
  // Auth check and other operations depend on local DB
  await initializeDatabaseFactory();
  // Seed the Dashboard demo customer on app launch (the seeder itself no-ops in
  // release). Kept out of DatabaseHelper.onOpen so tests open a clean DB.
  DatabaseHelper.seedDemoData = true;
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
  UserRepository()
      .migrateRemoteTokensToSecureStorage()
      .then((_) {
        StartupTimer.lap('token_migration_complete');
      })
      .catchError((e) {
        safeDebugLog('Secure token migration failed', error: e);
      });

  NotificationService.init()
      .then((_) {
        StartupTimer.lap('notification_init_complete');
      })
      .catchError((e) {
        safeDebugLog('Notification initialization failed', error: e);
      });

  unawaited(
    SupabaseInitializer.ensureInitialized()
        .then((initialized) {
          if (!initialized) return;
          StartupTimer.lap('supabase_init_complete');
        })
        .catchError((e) {
          safeDebugLog('Supabase initialization failed', error: e);
        }),
  );
}
