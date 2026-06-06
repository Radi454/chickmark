import 'dart:io';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Test-only helpers that keep the global database state hermetic between test
/// suites and tests.
///
/// `flutter test` runs each suite (file) in its own isolate, often several
/// concurrently. The app's [DatabaseHelper] is a singleton that opens a fixed
/// `hatchaudit.db` under [databaseFactory]'s databases path. If two suites use
/// the real singleton at the *default* path, they race on the same physical
/// file and tests fail nondeterministically. These helpers give every suite a
/// unique on-disk database and a clean singleton.
///
/// None of this touches production code paths — it only configures the test
/// `databaseFactory`, the temp database path, and resets the existing public
/// [DatabaseHelper.close] / [DatabaseHelper.seedDemoData] members.

/// Point the app database at a fresh, unique on-disk location for this suite and
/// reset singleton state. Returns the temp directory so callers can delete it.
Future<Directory> useIsolatedAppDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dir = await Directory.systemTemp.createTemp('chickmark_test_db_');
  await databaseFactory.setDatabasesPath(dir.path);
  await resetAppDatabase();
  return dir;
}

/// Close the [DatabaseHelper] singleton and restore default test flags. Safe to
/// call when nothing is open. Use in `setUp`/`tearDown` for hermetic DB tests.
Future<void> resetAppDatabase() async {
  await DatabaseHelper().close();
  DatabaseHelper.seedDemoData = false;
}
