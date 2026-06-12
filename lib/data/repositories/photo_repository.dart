import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../services/photo/photo_sync_coordinator.dart';
import '../database/database_helper.dart';
import '../models/photo_model.dart';
import 'sync_tombstone_repository.dart';

class PhotoRepository {
  final dbHelper = DatabaseHelper();

  Future<List<PhotoModel>> getAllPhotos() async {
    final db = await dbHelper.db;
    final rows = await db.query('photos', orderBy: 'createdAt DESC');
    return rows.map(PhotoModel.fromMap).toList();
  }

  Future<List<PhotoModel>> getByPanelRow({
    required String sessionId,
    required String panelName,
    required String panelRowId,
  }) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'photos',
      where: 'sessionId = ? AND panelName = ? AND panelRowId = ?',
      whereArgs: [sessionId, panelName, panelRowId],
      orderBy: 'createdAt DESC',
    );
    return rows.map(PhotoModel.fromMap).toList();
  }

  Future<List<PhotoModel>> getBySessionId(String sessionId) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'photos',
      where: 'sessionId = ?',
      whereArgs: [sessionId],
      orderBy: 'createdAt DESC',
    );
    return rows.map(PhotoModel.fromMap).toList();
  }

  Future<PhotoModel?> getByFilePath(String filePath) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'photos',
      where: 'filePath = ?',
      whereArgs: [filePath],
      orderBy: 'createdAt DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PhotoModel.fromMap(rows.first);
  }

  Future<List<PhotoModel>> getByStatus(String status) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'photos',
      where: 'uploadStatus = ?',
      whereArgs: [status],
      orderBy: 'createdAt DESC',
    );
    return rows.map(PhotoModel.fromMap).toList();
  }

  Future<void> updateStatus(String id, String status) async {
    final db = await dbHelper.db;
    await db.update(
      'photos',
      {'uploadStatus': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> saveLocalPhoto(PhotoModel photo) async {
    final db = await dbHelper.db;
    await db.insert(
      'photos',
      photo.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Nudge an opportunistic upload so this capture reaches the cloud without
    // waiting for the next startup/background sync. No-op until enabled at app
    // startup, so tests that save photos stay timer-free.
    PhotoSyncCoordinator.nudge();
  }

  Future<void> deleteByPanelRow({
    required String sessionId,
    required String panelName,
    required String panelRowId,
  }) async {
    final db = await dbHelper.db;
    final localPaths = <String>[];
    await db.transaction<void>((txn) async {
      final rows = await txn.query(
        'photos',
        columns: ['id', 'filePath'],
        where: 'sessionId = ? AND panelName = ? AND panelRowId = ?',
        whereArgs: [sessionId, panelName, panelRowId],
      );
      for (final row in rows) {
        final path = row['filePath'] as String?;
        if (_isLocalFilePath(path)) localPaths.add(path!);
      }
      await SyncTombstoneRepository.queueDeletesWithExecutor(
        txn,
        'photos',
        rows.map((row) => row['id']),
      );
      await txn.delete(
        'photos',
        where: 'sessionId = ? AND panelName = ? AND panelRowId = ?',
        whereArgs: [sessionId, panelName, panelRowId],
      );
    });
    // Drop the backing files only after the rows are gone, and only for local
    // paths — synced rows may carry a remote URL we must not delete.
    for (final path in localPaths) {
      await _deleteLocalFile(path);
    }
  }

  Future<void> _deleteLocalFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup; a leftover file is non-fatal.
    }
  }

  Future<void> upsertPhoto(Map<String, dynamic> row) async {
    final db = await dbHelper.db;
    final columns = await _tableColumns(db, 'photos');
    final normalized = _filterColumns(_normalizePhotoRow(row), columns);
    if (!normalized.containsKey('id')) return;
    normalized['uploadStatus'] = normalized['uploadStatus'] ?? 'synced';

    final existing = await db.query(
      'photos',
      where: 'id = ?',
      whereArgs: [normalized['id']],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final existingPath = existing.first['filePath'] as String?;
      final incomingPath = normalized['filePath'] as String?;
      if (_isLocalFilePath(existingPath) && _isRemotePath(incomingPath)) {
        normalized['filePath'] = existingPath;
      }
    }

    await db.insert(
      'photos',
      normalized,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Set<String>> _tableColumns(Database db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((row) => row['name'] as String).toSet();
  }

  Map<String, dynamic> _filterColumns(
    Map<String, dynamic> row,
    Set<String> columns,
  ) {
    return Map.fromEntries(
      row.entries.where((entry) => columns.contains(entry.key)),
    );
  }

  Map<String, dynamic> _normalizePhotoRow(Map<String, dynamic> row) {
    final normalized = <String, dynamic>{};
    for (final entry in row.entries) {
      normalized[_camelize(entry.key)] = entry.value;
    }
    return normalized;
  }

  bool _isLocalFilePath(String? path) {
    if (path == null || path.isEmpty) return false;
    return !_isRemotePath(path);
  }

  bool _isRemotePath(String? path) {
    if (path == null || path.isEmpty) return false;
    return path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('supabase://');
  }

  String _camelize(String key) {
    if (!key.contains('_')) return key;
    final parts = key.split('_');
    return parts.first +
        parts.skip(1).map((part) {
          if (part.isEmpty) return part;
          return part[0].toUpperCase() + part.substring(1);
        }).join();
  }
}
