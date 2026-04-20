import '../models/user_model.dart';
import '../database/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class UserRepository {
  final dbHelper = DatabaseHelper();

  Future<void> upsertUser(UserModel user) async {
    final db = await dbHelper.db;
    await db.insert(
      'users',
      user.toMap(),
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
  }

  Future<UserModel?> getCachedUser() async {
    final db = await dbHelper.db;
    final result = await db.query(
      'users',
      where:
          "status = 'approved' AND accessToken IS NOT NULL AND tokenExpiry IS NOT NULL",
      orderBy: 'lastLoginAt DESC, tokenExpiry DESC',
      limit: 1,
    );
    if (result.isNotEmpty) {
      final user = UserModel.fromMap(result.first);
      if (user.isTokenValid) return user;
    }
    return null;
  }

  Future<UserModel?> getCachedUserByEmail(String email) async {
    final db = await dbHelper.db;
    final result = await db.query(
      'users',
      where:
          "email = ? AND status = 'approved' AND accessToken IS NOT NULL AND tokenExpiry IS NOT NULL",
      whereArgs: [email],
    );
    if (result.isNotEmpty) {
      final user = UserModel.fromMap(result.first);
      if (user.isTokenValid) return user;
    }
    return null;
  }

  Future<void> clearCachedTokens() async {
    final db = await dbHelper.db;
    await db.update('users', {'accessToken': null, 'tokenExpiry': null});
  }
}
