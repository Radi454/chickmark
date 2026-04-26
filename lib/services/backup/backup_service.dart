import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/database/database_helper.dart';

class BackupService {
  Future<void> exportBackup() async {
    final dbPath = await getDatabasesPath();
    final source = File(path.join(dbPath, 'hatchaudit.db'));
    final docs = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);
    final dest = File('${docs.path}/chickmark_backup_$timestamp.db');
    await source.copy(dest.path);
    await Share.shareXFiles([XFile(dest.path)], text: 'ChickMark Backup');
  }

  Future<void> importBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
    );
    if (result == null || result.files.isEmpty || result.files.first.path == null) {
      return;
    }

    final file = File(result.files.first.path!);
    final header = await file.readAsBytes();
    if (header.length < 16 || !_hasSqliteMagic(header.take(16).toList())) {
      throw Exception('Invalid backup file');
    }

    await DatabaseHelper().close();
    final dbPath = await getDatabasesPath();
    await file.copy(path.join(dbPath, 'hatchaudit.db'));
    SystemNavigator.pop();
  }

  bool _hasSqliteMagic(List<int> bytes) {
    const magic = 'SQLite format 3';
    final prefix = String.fromCharCodes(bytes.take(magic.length));
    return prefix == magic;
  }
}
