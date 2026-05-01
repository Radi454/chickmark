import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future<void> initializeDatabaseFactory() async {
  sqflite.databaseFactory = databaseFactoryFfiWebNoWebWorker;
}
