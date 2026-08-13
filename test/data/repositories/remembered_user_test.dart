import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/repositories/user_repository.dart';
import 'package:hatchaudit/services/auth/secure_token_store.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

/// `flutter_secure_storage` talks to the platform over a MethodChannel that
/// has no implementation under `flutter test`. Back it with an in-memory
/// map so `SecureTokenStore` behaves like real secure storage for this
/// suite, without touching production code.
void _fakeSecureStorageChannel() {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'write':
        store[call.arguments['key'] as String] =
            call.arguments['value'] as String;
        return null;
      case 'read':
        return store[call.arguments['key'] as String];
      case 'containsKey':
        return store.containsKey(call.arguments['key'] as String);
      case 'delete':
        store.remove(call.arguments['key'] as String);
        return null;
      case 'deleteAll':
        store.clear();
        return null;
      case 'readAll':
        return store;
      default:
        return null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _fakeSecureStorageChannel();

  late Database db;
  late _MockDatabaseHelper dbHelper;
  late UserRepository repo;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        fullName TEXT,
        email TEXT,
        role TEXT,
        status TEXT,
        customerId TEXT,
        accessToken TEXT,
        tokenExpiry TEXT,
        createdAt TEXT,
        lastLoginAt TEXT
      )
    ''');
    dbHelper = _MockDatabaseHelper();
    when(() => dbHelper.db).thenAnswer((_) async => db);
    repo = UserRepository(dbHelper: dbHelper);
    await SecureTokenStore.deleteAll();
  });

  tearDown(() async {
    await SecureTokenStore.deleteAll();
    await db.close();
  });

  Future<void> insertRemoteUser({
    required String id,
    required DateTime tokenExpiry,
    String status = 'approved',
    DateTime? lastLoginAt,
  }) async {
    await db.insert('users', {
      'id': id,
      'fullName': 'Field Auditor',
      'email': '$id@example.com',
      'role': 'auditor',
      'status': status,
      'accessToken': null,
      'tokenExpiry': tokenExpiry.toIso8601String(),
      'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'lastLoginAt': (lastLoginAt ?? DateTime.utc(2026, 8, 1))
          .toIso8601String(),
    });
    await SecureTokenStore.saveToken(id, 'stale-access-token');
  }

  test('remembers a remote user whose access token already expired', () async {
    await insertRemoteUser(
      id: 'supabase-user-123',
      tokenExpiry: DateTime.now().subtract(const Duration(days: 3)),
    );

    final user = await repo.getRememberedUser();

    expect(user, isNotNull);
    expect(user!.id, 'supabase-user-123');
    expect(user.isTokenValid, isFalse);
    expect(user.accessToken, 'stale-access-token');
  });

  test('does not remember a user who never ticked Remember me', () async {
    await db.insert('users', {
      'id': 'supabase-user-456',
      'fullName': 'No Remember',
      'email': 'no-remember@example.com',
      'role': 'auditor',
      'status': 'approved',
      'accessToken': null,
      'tokenExpiry': null,
      'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'lastLoginAt': DateTime.utc(2026, 8, 1).toIso8601String(),
    });

    expect(await repo.getRememberedUser(), isNull);
  });

  test('does not remember a user with no token in secure storage', () async {
    await insertRemoteUser(
      id: 'supabase-user-789',
      tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
    );
    await SecureTokenStore.deleteToken('supabase-user-789');

    expect(await repo.getRememberedUser(), isNull);
  });

  test('does not remember an unapproved user', () async {
    await insertRemoteUser(
      id: 'supabase-user-pending',
      tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
      status: 'pending',
    );

    expect(await repo.getRememberedUser(), isNull);
  });

  test('prefers the most recently used remembered user', () async {
    await insertRemoteUser(
      id: 'older-user',
      tokenExpiry: DateTime.now().subtract(const Duration(days: 1)),
      lastLoginAt: DateTime.utc(2026, 7, 1),
    );
    await insertRemoteUser(
      id: 'newer-user',
      tokenExpiry: DateTime.now().subtract(const Duration(days: 1)),
      lastLoginAt: DateTime.utc(2026, 8, 10),
    );

    final user = await repo.getRememberedUser();
    expect(user!.id, 'newer-user');
  });

  test('remembers a local account and keeps its password hash', () async {
    await db.insert('users', {
      'id': 'local-abc',
      'fullName': 'Local Auditor',
      'email': 'local@example.com',
      'role': 'auditor',
      'status': 'approved',
      'accessToken': 'v3:pbkdf2-sha256:210000:salt:key',
      'tokenExpiry': DateTime.now()
          .add(const Duration(days: 10))
          .toIso8601String(),
      'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'lastLoginAt': DateTime.utc(2026, 8, 11).toIso8601String(),
    });

    final user = await repo.getRememberedUser();
    expect(user!.id, 'local-abc');
    expect(user.accessToken, 'v3:pbkdf2-sha256:210000:salt:key');
  });
}
