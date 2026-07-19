import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/activity_log_repository.dart';
import 'package:hatchaudit/data/repositories/user_repository.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';

class MockSupabaseService extends Mock implements SupabaseService {}

class MockUserRepository extends Mock implements UserRepository {}

class MockActivityLogRepository extends Mock implements ActivityLogRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      UserModel(
        id: 'fallback',
        fullName: 'Fallback',
        email: 'fallback@example.com',
        role: 'auditor',
        status: 'approved',
        createdAt: DateTime(2024),
      ),
    );
  });

  late MockSupabaseService mockSupabase;
  late MockUserRepository mockRepo;
  late MockActivityLogRepository mockActivityLog;
  late AuthProvider provider;

  const email = 'test@example.com';
  const password = 'Test.12345';

  UserModel approvedSupabaseUser() => UserModel(
    id: 'supabase-user-123',
    fullName: 'Test User',
    email: email,
    role: 'auditor',
    status: 'approved',
    accessToken: 'valid-token',
    tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
    createdAt: DateTime.now(),
    lastLoginAt: DateTime.now(),
  );

  UserModel pendingSupabaseUser() => UserModel(
    id: 'supabase-user-456',
    fullName: 'Pending User',
    email: email,
    role: 'auditor',
    status: 'pending',
    accessToken: 'valid-token',
    tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
    createdAt: DateTime.now(),
    lastLoginAt: DateTime.now(),
  );

  UserModel localUserFixture(String passwordHash) => UserModel(
    id: 'local-test-abc',
    fullName: 'Local User',
    email: email,
    role: 'auditor',
    status: 'approved',
    accessToken: passwordHash,
    tokenExpiry: DateTime.now().add(const Duration(days: 30)),
    createdAt: DateTime.now(),
    lastLoginAt: DateTime.now(),
  );

  setUp(() {
    mockSupabase = MockSupabaseService();
    mockRepo = MockUserRepository();
    mockActivityLog = MockActivityLogRepository();
    provider = AuthProvider(
      userRepository: mockRepo,
      activityLogRepository: mockActivityLog,
      supabaseService: mockSupabase,
    );
    when(() => mockActivityLog.log(any(), any())).thenAnswer((_) async {});
  });

  group('checkCachedToken', () {
    test(
      'auth bypass request activates the development auditor in debug builds',
      () async {
        provider = AuthProvider(
          userRepository: mockRepo,
          activityLogRepository: mockActivityLog,
          supabaseService: mockSupabase,
          bypassAuth: true,
        );
        when(() => mockRepo.getCachedUser()).thenAnswer((_) async => null);

        await provider.checkCachedToken();

        expect(provider.state, AuthState.authenticated);
        expect(provider.user?.email, 'dev-auditor@chickmark.local');
        verifyNever(() => mockRepo.getCachedUser());
      },
    );

    test('authenticated when valid cached user exists', () async {
      when(
        () => mockRepo.getCachedUser(),
      ).thenAnswer((_) async => approvedSupabaseUser());

      await provider.checkCachedToken();

      expect(provider.state, AuthState.authenticated);
      expect(provider.user, isNotNull);
    });

    test('unauthenticated when no cached user', () async {
      when(() => mockRepo.getCachedUser()).thenAnswer((_) async => null);

      await provider.checkCachedToken();

      expect(provider.state, AuthState.unauthenticated);
      expect(provider.user, isNull);
    });
  });

  group('login — Supabase success', () {
    setUp(() {
      when(() => mockRepo.upsertUser(any())).thenAnswer((_) async {});
    });

    test('sets authenticated when approved user signs in', () async {
      when(
        () => mockSupabase.signIn(
          email,
          password,
          rememberSession: any(named: 'rememberSession'),
        ),
      ).thenAnswer(
        (_) async => AuthResult(success: true, user: approvedSupabaseUser()),
      );

      final result = await provider.login(email, password);

      expect(result, isTrue);
      expect(provider.state, AuthState.authenticated);
    });

    test('sets pendingApproval when user not yet approved', () async {
      when(
        () => mockSupabase.signIn(
          email,
          password,
          rememberSession: any(named: 'rememberSession'),
        ),
      ).thenAnswer(
        (_) async => AuthResult(success: true, user: pendingSupabaseUser()),
      );

      final result = await provider.login(email, password);

      expect(result, isTrue);
      expect(provider.state, AuthState.pendingApproval);
    });
  });

  group('login — offline', () {
    setUp(() {
      when(
        () => mockSupabase.signIn(
          email,
          password,
          rememberSession: any(named: 'rememberSession'),
        ),
      ).thenAnswer((_) async => AuthResult(success: false, error: 'offline'));
    });

    test('does not use a cached Supabase profile as password proof', () async {
      when(() => mockRepo.getUserByEmail(email)).thenAnswer((_) async => null);

      final result = await provider.login(email, password);

      expect(result, isFalse);
      expect(provider.state, AuthState.error);
      expect(provider.errorMessage, contains('Internet access'));
      verifyNever(() => mockRepo.getCachedUserByEmail(email));
    });

    test('authenticated using local account with correct password', () async {
      final hash = provider.hashPasswordForTesting(password, iterations: 1000);
      final localUser = localUserFixture(hash);
      when(
        () => mockRepo.getUserByEmail(email),
      ).thenAnswer((_) async => localUser);
      when(
        () => mockRepo.cacheToken(any(), any(), any()),
      ).thenAnswer((_) async {});

      final result = await provider.login(email, password);

      expect(result, isTrue);
      expect(provider.state, AuthState.authenticated);
    });

    test('error when no cached user and no local account', () async {
      when(() => mockRepo.getUserByEmail(email)).thenAnswer((_) async => null);

      final result = await provider.login(email, password);

      expect(result, isFalse);
      expect(provider.state, AuthState.error);
      expect(provider.errorMessage, contains('Internet access'));
    });

    test('error when local account has wrong password', () async {
      final wrongHash = provider.hashPasswordForTesting(
        'wrong-password',
        iterations: 1000,
      );
      when(
        () => mockRepo.getUserByEmail(email),
      ).thenAnswer((_) async => localUserFixture(wrongHash));

      final result = await provider.login(email, password);

      expect(result, isFalse);
      expect(provider.state, AuthState.error);
    });
  });

  group('login — Supabase error', () {
    setUp(() {
      when(() => mockRepo.getUserByEmail(email)).thenAnswer((_) async => null);
    });

    test('friendly error for invalid credentials', () async {
      when(
        () => mockSupabase.signIn(
          email,
          password,
          rememberSession: any(named: 'rememberSession'),
        ),
      ).thenAnswer(
        (_) async =>
            AuthResult(success: false, error: 'Invalid login credentials'),
      );

      await provider.login(email, password);

      expect(provider.state, AuthState.error);
      expect(provider.errorMessage, 'The email or password is incorrect.');
    });

    test('surfaces Supabase config error verbatim', () async {
      const configError =
          'Supabase credentials are not configured. Run the app with --dart-define-from-file=.env.';
      when(
        () => mockSupabase.signIn(
          email,
          password,
          rememberSession: any(named: 'rememberSession'),
        ),
      ).thenAnswer((_) async => AuthResult(success: false, error: configError));

      await provider.login(email, password);

      expect(provider.state, AuthState.error);
      expect(provider.errorMessage, configError);
    });
  });

  group('password hashing', () {
    test('v3 PBKDF2 hash includes algorithm and iteration metadata', () {
      final hash = provider.hashPasswordForTesting(password, iterations: 1000);

      expect(hash, startsWith('v3:pbkdf2-sha256:1000:'));
      final parts = hash.split(':');
      expect(parts.length, 5);
    });

    test('same password produces different hashes (salted)', () {
      final hash1 = provider.hashPasswordForTesting(password, iterations: 1000);
      final hash2 = provider.hashPasswordForTesting(password, iterations: 1000);

      expect(hash1, isNot(equals(hash2)));
    });
  });

  group('logout', () {
    test('clears user and sets unauthenticated', () async {
      when(() => mockSupabase.signOut()).thenAnswer((_) async {});
      when(() => mockRepo.clearCachedTokens()).thenAnswer((_) async {});

      await provider.logout();

      expect(provider.state, AuthState.unauthenticated);
      expect(provider.user, isNull);
    });
  });
}
