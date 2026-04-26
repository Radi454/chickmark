import '../models/user_model.dart';
import '../database/database_helper.dart';
import 'package:sqflite/sqflite.dart';
import '../../services/auth/secure_token_store.dart';

class UserRepository {
  final dbHelper = DatabaseHelper();

  Future<void> upsertUser(UserModel user) async {
    final db = await dbHelper.db;
    await db.insert(
      'users',
      _persistedUser(user).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<UserModel?> getUserByEmail(String email) async {
    final db = await dbHelper.db;
    final result = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email],
    );
    if (result.isNotEmpty) {
      return UserModel.fromMap(result.first);
    }
    return null;
  }

  Future<void> cacheToken(String userId, String token, DateTime expiry) async {
    final db = await dbHelper.db;
    if (_isLocalUserId(userId)) {
      await db.update(
        'users',
        {
          'accessToken': token,
          'tokenExpiry': expiry.toIso8601String(),
          'lastLoginAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [userId],
      );
      return;
    }
    await SecureTokenStore.saveToken(userId, token);
    await db.update(
      'users',
      {
        'accessToken': null,
        'tokenExpiry': expiry.toIso8601String(),
        'lastLoginAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<void> updatePasswordHash(String userId, String hash) async {
    final db = await dbHelper.db;
    await db.update(
      'users',
      {'accessToken': hash},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<UserModel?> getCachedUser() async {
    final db = await dbHelper.db;
    final result = await db.query(
      'users',
      where: "status = 'approved' AND tokenExpiry IS NOT NULL",
      orderBy: 'lastLoginAt DESC, tokenExpiry DESC',
    );
    for (final row in result) {
      final user = await _attachStoredToken(UserModel.fromMap(row));
      if (user != null && user.isTokenValid) {
        return user;
      }
    }
    return null;
  }

  Future<UserModel?> getCachedUserByEmail(String email) async {
    final db = await dbHelper.db;
    final result = await db.query(
      'users',
      where:
          "email = ? AND status = 'approved' AND tokenExpiry IS NOT NULL AND id NOT LIKE 'local-%'",
      whereArgs: [email],
    );
    for (final row in result) {
      final user = await _attachStoredToken(UserModel.fromMap(row));
      if (user != null && user.isTokenValid) {
        return user;
      }
    }
    return null;
  }

  Future<void> clearCachedTokens() async {
    final db = await dbHelper.db;
    await SecureTokenStore.deleteAll();
    await db.update(
      'users',
      {'tokenExpiry': null},
      where: "id LIKE 'local-%'",
    );
    await db.update(
      'users',
      {'accessToken': null, 'tokenExpiry': null},
      where: "id NOT LIKE 'local-%'",
    );
  }

  Future<void> migrateRemoteTokensToSecureStorage() async {
    final db = await dbHelper.db;
    final users = await db.query(
      'users',
      columns: ['id', 'accessToken'],
      where: "id NOT LIKE 'local-%' AND accessToken IS NOT NULL",
    );
    for (final row in users) {
      final userId = row['id'] as String?;
      final token = row['accessToken'] as String?;
      if (userId == null || token == null || token.isEmpty) continue;
      await SecureTokenStore.saveToken(userId, token);
      await db.update(
        'users',
        {'accessToken': null},
        where: 'id = ?',
        whereArgs: [userId],
      );
    }
  }

  UserModel _persistedUser(UserModel user) {
    if (_isLocalUserId(user.id)) {
      return user;
    }
    return UserModel(
      id: user.id,
      fullName: user.fullName,
      email: user.email,
      role: user.role,
      status: user.status,
      customerId: user.customerId,
      accessToken: null,
      tokenExpiry: user.tokenExpiry,
      createdAt: user.createdAt,
      lastLoginAt: user.lastLoginAt,
    );
  }

  Future<UserModel?> _attachStoredToken(UserModel user) async {
    if (_isLocalUserId(user.id)) {
      return user.accessToken == null ? null : user;
    }
    final token = await SecureTokenStore.getToken(user.id);
    if (token == null || token.isEmpty) {
      return null;
    }
    return UserModel(
      id: user.id,
      fullName: user.fullName,
      email: user.email,
      role: user.role,
      status: user.status,
      customerId: user.customerId,
      accessToken: token,
      tokenExpiry: user.tokenExpiry,
      createdAt: user.createdAt,
      lastLoginAt: user.lastLoginAt,
    );
  }

  bool _isLocalUserId(String userId) => userId.startsWith('local-');
}
