import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/activity_log_repository.dart';
import 'package:hatchaudit/data/repositories/user_repository.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:hatchaudit/services/auth/session_trust_store.dart';

class MockSupabaseService extends Mock implements SupabaseService {}

class FakeSessionTrustStore implements SessionTrustStore {
  SessionTrust? trust;

  @override
  Future<SessionTrust?> read() async => trust;

  @override
  Future<void> record(String userId, DateTime verifiedAt) async {
    trust = SessionTrust(userId: userId, lastVerifiedAt: verifiedAt);
  }

  @override
  Future<void> clear() async {
    trust = null;
  }
}

/// A trust store whose calls can be made to fail, standing in for a
/// Keychain/Keystore fault (locked device, keystore error, disk fault).
class ThrowingSessionTrustStore implements SessionTrustStore {
  SessionTrust? trust;
  bool throwOnRead = false;
  bool throwOnRecord = false;
  bool throwOnClear = false;

  @override
  Future<SessionTrust?> read() async {
    if (throwOnRead) throw Exception('trust store read fault');
    return trust;
  }

  @override
  Future<void> record(String userId, DateTime verifiedAt) async {
    if (throwOnRecord) throw Exception('trust store write fault');
    trust = SessionTrust(userId: userId, lastVerifiedAt: verifiedAt);
  }

  @override
  Future<void> clear() async {
    if (throwOnClear) throw Exception('trust store delete fault');
    trust = null;
  }
}

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
  late FakeSessionTrustStore sharedTrustStore;
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
    sharedTrustStore = FakeSessionTrustStore();
    provider = AuthProvider(
      userRepository: mockRepo,
      activityLogRepository: mockActivityLog,
      supabaseService: mockSupabase,
      sessionTrustStore: sharedTrustStore,
    );
    when(() => mockActivityLog.log(any(), any())).thenAnswer((_) async {});
    when(() => mockSupabase.restoreSession()).thenAnswer(
      (_) async => const SessionRestoreResult(status: SessionRestoreStatus.valid),
    );
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
        when(() => mockRepo.getRememberedUser()).thenAnswer((_) async => null);

        await provider.checkCachedToken();

        expect(provider.state, AuthState.authenticated);
        expect(provider.user?.email, 'dev-auditor@chickmark.local');
        verifyNever(() => mockRepo.getRememberedUser());
      },
    );

    test('authenticated when valid cached user exists', () async {
      when(
        () => mockRepo.getRememberedUser(),
      ).thenAnswer((_) async => approvedSupabaseUser());

      await provider.checkCachedToken();

      expect(provider.state, AuthState.authenticated);
      expect(provider.user, isNotNull);
    });

    test('unauthenticated when no cached user', () async {
      when(() => mockRepo.getRememberedUser()).thenAnswer((_) async => null);

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

    test(
      'a trust-store fault recording trust does not fail an otherwise-successful login',
      () async {
        provider = AuthProvider(
          userRepository: mockRepo,
          activityLogRepository: mockActivityLog,
          supabaseService: mockSupabase,
          sessionTrustStore: ThrowingSessionTrustStore()
            ..throwOnRecord = true,
        );
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
        expect(provider.user, isNotNull);
      },
    );
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
      expect(
        provider.errorMessage,
        'The username/email or password is incorrect.',
      );
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

    test(
      'a trust-store fault clearing trust does not strand the device signed in',
      () async {
        final throwing = ThrowingSessionTrustStore()..throwOnClear = true;
        provider = AuthProvider(
          userRepository: mockRepo,
          activityLogRepository: mockActivityLog,
          supabaseService: mockSupabase,
          sessionTrustStore: throwing,
        );
        when(() => mockSupabase.signOut()).thenAnswer((_) async {});
        when(() => mockRepo.clearCachedTokens()).thenAnswer((_) async {});

        await provider.logout();

        expect(provider.state, AuthState.unauthenticated);
        expect(provider.user, isNull);
        // The trust-store fault must not skip clearing the actual tokens.
        verify(() => mockRepo.clearCachedTokens()).called(1);
      },
    );

    test(
      'a fault clearing cached tokens still signs the device out locally',
      () async {
        when(() => mockSupabase.signOut()).thenAnswer((_) async {});
        when(
          () => mockRepo.clearCachedTokens(),
        ).thenThrow(Exception('secure storage fault'));

        await provider.logout();

        expect(provider.state, AuthState.unauthenticated);
        expect(provider.user, isNull);
      },
    );

    test('debug auth bypass logout clears the development user', () async {
      provider = AuthProvider(
        userRepository: mockRepo,
        activityLogRepository: mockActivityLog,
        supabaseService: mockSupabase,
        bypassAuth: true,
      );

      expect(provider.state, AuthState.authenticated);
      expect(provider.user?.email, 'dev-auditor@chickmark.local');

      await provider.logout();

      expect(provider.state, AuthState.unauthenticated);
      expect(provider.user, isNull);
      verifyNever(() => mockSupabase.signOut());
      verifyNever(() => mockRepo.clearCachedTokens());

      await provider.checkCachedToken();

      expect(provider.state, AuthState.unauthenticated);
      expect(provider.user, isNull);
      verifyNever(() => mockRepo.getRememberedUser());
    });
  });

  group('startup auth gate', () {
    late FakeSessionTrustStore trustStore;

    UserModel rememberedRemoteUser({DateTime? tokenExpiry}) => UserModel(
      id: 'supabase-user-123',
      fullName: 'Field Auditor',
      email: email,
      role: 'auditor',
      status: 'approved',
      accessToken: 'stale-access-token',
      tokenExpiry:
          tokenExpiry ?? DateTime.now().subtract(const Duration(days: 3)),
      createdAt: DateTime(2026, 1, 1),
      lastLoginAt: DateTime.now().subtract(const Duration(days: 3)),
    );

    setUp(() {
      trustStore = FakeSessionTrustStore();
      provider = AuthProvider(
        userRepository: mockRepo,
        activityLogRepository: mockActivityLog,
        supabaseService: mockSupabase,
        sessionTrustStore: trustStore,
      );
      when(() => mockRepo.cacheToken(any(), any(), any())).thenAnswer(
        (_) async {},
      );
      when(() => mockRepo.clearCachedTokens()).thenAnswer((_) async {});
    });

    test('offline with prior successful login stays inside the app', () async {
      trustStore.trust = SessionTrust(
        userId: 'supabase-user-123',
        lastVerifiedAt: DateTime.now().subtract(const Duration(days: 3)),
      );
      when(
        () => mockRepo.getRememberedUser(),
      ).thenAnswer((_) async => rememberedRemoteUser());
      when(() => mockSupabase.restoreSession()).thenAnswer(
        (_) async =>
            const SessionRestoreResult(status: SessionRestoreStatus.offline),
      );

      await provider.checkCachedToken();

      expect(provider.state, AuthState.authenticated);
      expect(provider.isPendingRevalidation, isTrue);
      verifyNever(() => mockRepo.clearCachedTokens());
    });

    test('offline past the grace window goes to login', () async {
      trustStore.trust = SessionTrust(
        userId: 'supabase-user-123',
        lastVerifiedAt: DateTime.now().subtract(const Duration(days: 45)),
      );
      when(
        () => mockRepo.getRememberedUser(),
      ).thenAnswer((_) async => rememberedRemoteUser());
      when(() => mockSupabase.restoreSession()).thenAnswer(
        (_) async =>
            const SessionRestoreResult(status: SessionRestoreStatus.offline),
      );

      await provider.checkCachedToken();

      expect(provider.state, AuthState.unauthenticated);
      expect(provider.isPendingRevalidation, isFalse);
      // Being offline is never a logout, not even when the grace window has
      // lapsed: the device shows /login, but nothing is wiped, so signing in
      // again — or simply coming back online — restores it intact.
      verifyNever(() => mockRepo.clearCachedTokens());
      expect(trustStore.trust, isNotNull);
    });

    test('a refreshed session enters the app and re-caches the token', () async {
      final expiresAt = DateTime.now().add(const Duration(hours: 1));
      trustStore.trust = SessionTrust(
        userId: 'supabase-user-123',
        lastVerifiedAt: DateTime.now().subtract(const Duration(days: 3)),
      );
      when(
        () => mockRepo.getRememberedUser(),
      ).thenAnswer((_) async => rememberedRemoteUser());
      when(() => mockSupabase.restoreSession()).thenAnswer(
        (_) async => SessionRestoreResult(
          status: SessionRestoreStatus.refreshed,
          userId: 'supabase-user-123',
          accessToken: 'fresh-access-token',
          expiresAt: expiresAt,
        ),
      );

      await provider.checkCachedToken();

      expect(provider.state, AuthState.authenticated);
      expect(provider.isPendingRevalidation, isFalse);
      verify(
        () => mockRepo.cacheToken(
          'supabase-user-123',
          'fresh-access-token',
          expiresAt,
        ),
      ).called(1);
      expect(trustStore.trust, isNotNull);
    });

    test('a rejected session logs the device out and clears trust', () async {
      trustStore.trust = SessionTrust(
        userId: 'supabase-user-123',
        lastVerifiedAt: DateTime.now().subtract(const Duration(days: 3)),
      );
      when(
        () => mockRepo.getRememberedUser(),
      ).thenAnswer((_) async => rememberedRemoteUser());
      when(() => mockSupabase.restoreSession()).thenAnswer(
        (_) async =>
            const SessionRestoreResult(status: SessionRestoreStatus.rejected),
      );

      await provider.checkCachedToken();

      expect(provider.state, AuthState.unauthenticated);
      expect(trustStore.trust, isNull);
      verify(() => mockRepo.clearCachedTokens()).called(1);
    });

    test('a brand-new install goes to login without asking Supabase', () async {
      when(() => mockRepo.getRememberedUser()).thenAnswer((_) async => null);

      await provider.checkCachedToken();

      expect(provider.state, AuthState.unauthenticated);
      verifyNever(() => mockSupabase.restoreSession());
    });

    test('revalidateSession clears the pending flag when back online', () async {
      trustStore.trust = SessionTrust(
        userId: 'supabase-user-123',
        lastVerifiedAt: DateTime.now().subtract(const Duration(days: 3)),
      );
      when(
        () => mockRepo.getRememberedUser(),
      ).thenAnswer((_) async => rememberedRemoteUser());
      when(() => mockSupabase.restoreSession()).thenAnswer(
        (_) async =>
            const SessionRestoreResult(status: SessionRestoreStatus.offline),
      );
      await provider.checkCachedToken();
      expect(provider.isPendingRevalidation, isTrue);

      when(() => mockSupabase.restoreSession()).thenAnswer(
        (_) async => SessionRestoreResult(
          status: SessionRestoreStatus.refreshed,
          userId: 'supabase-user-123',
          accessToken: 'fresh-access-token',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      await provider.revalidateSession();

      expect(provider.isPendingRevalidation, isFalse);
      expect(provider.state, AuthState.authenticated);
    });

    test('revalidateSession while still offline changes nothing', () async {
      trustStore.trust = SessionTrust(
        userId: 'supabase-user-123',
        lastVerifiedAt: DateTime.now().subtract(const Duration(days: 3)),
      );
      when(
        () => mockRepo.getRememberedUser(),
      ).thenAnswer((_) async => rememberedRemoteUser());
      when(() => mockSupabase.restoreSession()).thenAnswer(
        (_) async =>
            const SessionRestoreResult(status: SessionRestoreStatus.offline),
      );
      await provider.checkCachedToken();

      await provider.revalidateSession();

      expect(provider.isPendingRevalidation, isTrue);
      expect(provider.state, AuthState.authenticated);
      verifyNever(() => mockRepo.clearCachedTokens());
    });

    test('revalidateSession signs out on a rejection while online', () async {
      trustStore.trust = SessionTrust(
        userId: 'supabase-user-123',
        lastVerifiedAt: DateTime.now().subtract(const Duration(days: 3)),
      );
      when(
        () => mockRepo.getRememberedUser(),
      ).thenAnswer((_) async => rememberedRemoteUser());
      when(() => mockSupabase.restoreSession()).thenAnswer(
        (_) async =>
            const SessionRestoreResult(status: SessionRestoreStatus.offline),
      );
      await provider.checkCachedToken();

      when(() => mockSupabase.restoreSession()).thenAnswer(
        (_) async =>
            const SessionRestoreResult(status: SessionRestoreStatus.rejected),
      );

      await provider.revalidateSession();

      expect(provider.state, AuthState.unauthenticated);
      expect(provider.isPendingRevalidation, isFalse);
      expect(trustStore.trust, isNull);
    });

    test('a local account never consults Supabase', () async {
      when(() => mockRepo.getRememberedUser()).thenAnswer(
        (_) async => UserModel(
          id: 'local-abc',
          fullName: 'Local Auditor',
          email: 'local@example.com',
          role: 'auditor',
          status: 'approved',
          accessToken: 'v3:pbkdf2-sha256:210000:salt:key',
          tokenExpiry: DateTime.now().add(const Duration(days: 10)),
          createdAt: DateTime(2026, 1, 1),
          lastLoginAt: DateTime.now(),
        ),
      );

      await provider.checkCachedToken();

      expect(provider.state, AuthState.authenticated);
      expect(provider.isPendingRevalidation, isFalse);
      verifyNever(() => mockSupabase.restoreSession());
    });

    test(
      'a trust-store read fault still lets a remembered user in, pending revalidation',
      () async {
        final throwing = ThrowingSessionTrustStore()..throwOnRead = true;
        provider = AuthProvider(
          userRepository: mockRepo,
          activityLogRepository: mockActivityLog,
          supabaseService: mockSupabase,
          sessionTrustStore: throwing,
        );
        when(
          () => mockRepo.getRememberedUser(),
        ).thenAnswer((_) async => rememberedRemoteUser());
        when(() => mockSupabase.restoreSession()).thenAnswer(
          (_) async => const SessionRestoreResult(
            status: SessionRestoreStatus.offline,
          ),
        );

        await provider.checkCachedToken();

        expect(provider.state, AuthState.authenticated);
        expect(provider.isPendingRevalidation, isTrue);
        verifyNever(() => mockRepo.clearCachedTokens());
      },
    );

    test(
      'a cacheToken fault after a confirmed-valid restore still enters the app',
      () async {
        trustStore.trust = SessionTrust(
          userId: 'supabase-user-123',
          lastVerifiedAt: DateTime.now().subtract(const Duration(days: 3)),
        );
        when(
          () => mockRepo.getRememberedUser(),
        ).thenAnswer((_) async => rememberedRemoteUser());
        when(() => mockSupabase.restoreSession()).thenAnswer(
          (_) async => SessionRestoreResult(
            status: SessionRestoreStatus.refreshed,
            userId: 'supabase-user-123',
            accessToken: 'fresh-access-token',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );
        when(
          () => mockRepo.cacheToken(any(), any(), any()),
        ).thenThrow(Exception('keychain write fault'));

        await provider.checkCachedToken();

        expect(provider.state, AuthState.authenticated);
        expect(provider.isPendingRevalidation, isFalse);
      },
    );

    test(
      'a restored session for a different account is never granted to the remembered user',
      () async {
        when(
          () => mockRepo.getRememberedUser(),
        ).thenAnswer((_) async => rememberedRemoteUser());
        when(() => mockSupabase.restoreSession()).thenAnswer(
          (_) async => const SessionRestoreResult(
            status: SessionRestoreStatus.valid,
            userId: 'someone-else',
          ),
        );

        await provider.checkCachedToken();

        expect(provider.state, AuthState.unauthenticated);
        expect(provider.user, isNull);
        verifyNever(() => mockRepo.cacheToken(any(), any(), any()));
      },
    );

    test(
      'a trust record for a different account does not lend its grace window',
      () async {
        trustStore.trust = SessionTrust(
          userId: 'someone-else',
          lastVerifiedAt: DateTime.now().subtract(const Duration(days: 3)),
        );
        when(
          () => mockRepo.getRememberedUser(),
        ).thenAnswer((_) async => rememberedRemoteUser());
        when(() => mockSupabase.restoreSession()).thenAnswer(
          (_) async => const SessionRestoreResult(
            status: SessionRestoreStatus.offline,
          ),
        );

        await provider.checkCachedToken();

        expect(provider.state, AuthState.unauthenticated);
        expect(provider.isPendingRevalidation, isFalse);
      },
    );

    test(
      'overlapping revalidateSession calls make only one restoreSession call',
      () async {
        trustStore.trust = SessionTrust(
          userId: 'supabase-user-123',
          lastVerifiedAt: DateTime.now().subtract(const Duration(days: 3)),
        );
        when(
          () => mockRepo.getRememberedUser(),
        ).thenAnswer((_) async => rememberedRemoteUser());
        when(() => mockSupabase.restoreSession()).thenAnswer(
          (_) async => const SessionRestoreResult(
            status: SessionRestoreStatus.offline,
          ),
        );
        await provider.checkCachedToken();
        expect(provider.isPendingRevalidation, isTrue);

        final completer = Completer<SessionRestoreResult>();
        var restoreCallCount = 0;
        when(() => mockSupabase.restoreSession()).thenAnswer((_) {
          restoreCallCount++;
          return completer.future;
        });

        final first = provider.revalidateSession();
        final second = provider.revalidateSession();

        completer.complete(
          const SessionRestoreResult(status: SessionRestoreStatus.rejected),
        );
        await first;
        await second;

        expect(restoreCallCount, 1);
        expect(provider.state, AuthState.unauthenticated);
        expect(provider.isPendingRevalidation, isFalse);
        expect(trustStore.trust, isNull);
      },
    );

    test(
      'revalidateSession signs out when the restored session belongs to a different account',
      () async {
        trustStore.trust = SessionTrust(
          userId: 'supabase-user-123',
          lastVerifiedAt: DateTime.now().subtract(const Duration(days: 3)),
        );
        when(
          () => mockRepo.getRememberedUser(),
        ).thenAnswer((_) async => rememberedRemoteUser());
        when(() => mockSupabase.restoreSession()).thenAnswer(
          (_) async => const SessionRestoreResult(
            status: SessionRestoreStatus.offline,
          ),
        );
        await provider.checkCachedToken();

        when(() => mockSupabase.restoreSession()).thenAnswer(
          (_) async => const SessionRestoreResult(
            status: SessionRestoreStatus.valid,
            userId: 'someone-else',
          ),
        );

        await provider.revalidateSession();

        expect(provider.state, AuthState.unauthenticated);
        expect(provider.isPendingRevalidation, isFalse);
        expect(trustStore.trust, isNull);
      },
    );

    test(
      'revalidateSession swallows an unexpected failure and stays pending',
      () async {
        trustStore.trust = SessionTrust(
          userId: 'supabase-user-123',
          lastVerifiedAt: DateTime.now().subtract(const Duration(days: 3)),
        );
        when(
          () => mockRepo.getRememberedUser(),
        ).thenAnswer((_) async => rememberedRemoteUser());
        when(() => mockSupabase.restoreSession()).thenAnswer(
          (_) async => const SessionRestoreResult(
            status: SessionRestoreStatus.offline,
          ),
        );
        await provider.checkCachedToken();

        when(
          () => mockSupabase.restoreSession(),
        ).thenThrow(Exception('unexpected failure'));

        await expectLater(provider.revalidateSession(), completes);

        expect(provider.state, AuthState.authenticated);
        expect(provider.isPendingRevalidation, isTrue);
      },
    );

    /// Puts the provider into the offline, pending-revalidation state the
    /// concurrency tests below start from.
    Future<void> enterAppPendingRevalidation() async {
      trustStore.trust = SessionTrust(
        userId: 'supabase-user-123',
        lastVerifiedAt: DateTime.now().subtract(const Duration(days: 3)),
      );
      when(
        () => mockRepo.getRememberedUser(),
      ).thenAnswer((_) async => rememberedRemoteUser());
      when(() => mockSupabase.restoreSession()).thenAnswer(
        (_) async =>
            const SessionRestoreResult(status: SessionRestoreStatus.offline),
      );
      await provider.checkCachedToken();
      expect(provider.isPendingRevalidation, isTrue);
    }

    test(
      'a token write that lands after a concurrent logout is undone, not left behind',
      () async {
        await enterAppPendingRevalidation();
        when(() => mockSupabase.signOut()).thenAnswer((_) async {});

        // The revalidation gets past its identity check and starts writing…
        final cacheTokenParked = Completer<void>();
        when(
          () => mockRepo.cacheToken(any(), any(), any()),
        ).thenAnswer((_) => cacheTokenParked.future);
        when(() => mockSupabase.restoreSession()).thenAnswer(
          (_) async => SessionRestoreResult(
            status: SessionRestoreStatus.refreshed,
            userId: 'supabase-user-123',
            accessToken: 'fresh-access-token',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );
        final revalidation = provider.revalidateSession();
        await pumpEventQueue();

        // …the user logs out, and the logout's own cleanup runs to completion
        // while that write is still parked.
        await provider.logout();

        // Only now does the write land.
        cacheTokenParked.complete();
        await revalidation;

        expect(provider.state, AuthState.unauthenticated);
        expect(provider.user, isNull);
        expect(provider.isPendingRevalidation, isFalse);
        // Nothing survives the logout: the trust record is gone and the
        // late token write was cleared again (once by the logout, once by
        // the persist noticing it had been overtaken).
        expect(trustStore.trust, isNull);
        verify(() => mockRepo.clearCachedTokens()).called(2);
      },
    );

    test(
      'a revalidation resolving after a completed logout writes nothing at all',
      () async {
        await enterAppPendingRevalidation();
        when(() => mockSupabase.signOut()).thenAnswer((_) async {});

        final restoreParked = Completer<SessionRestoreResult>();
        when(
          () => mockSupabase.restoreSession(),
        ).thenAnswer((_) => restoreParked.future);
        final revalidation = provider.revalidateSession();

        await provider.logout();

        restoreParked.complete(
          SessionRestoreResult(
            status: SessionRestoreStatus.refreshed,
            userId: 'supabase-user-123',
            accessToken: 'fresh-access-token',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );
        await revalidation;

        expect(provider.state, AuthState.unauthenticated);
        expect(provider.user, isNull);
        expect(provider.isPendingRevalidation, isFalse);
        expect(trustStore.trust, isNull);
        verifyNever(() => mockRepo.cacheToken(any(), any(), any()));
      },
    );

    UserModel upgradingUser({required DateTime? lastLoginAt}) => UserModel(
      id: 'supabase-user-123',
      fullName: 'Field Auditor',
      email: email,
      role: 'auditor',
      status: 'approved',
      accessToken: 'stale-access-token',
      tokenExpiry: DateTime.now().subtract(const Duration(days: 3)),
      createdAt: DateTime(2026, 1, 1),
      lastLoginAt: lastLoginAt,
    );

    test(
      'an install upgraded while signed in stays inside the app on its last login',
      () async {
        // No trust record was ever written on this device — it was already
        // signed in before trust records existed.
        trustStore.trust = null;
        when(() => mockRepo.getRememberedUser()).thenAnswer(
          (_) async => upgradingUser(
            lastLoginAt: DateTime.now().subtract(const Duration(days: 3)),
          ),
        );
        when(() => mockSupabase.restoreSession()).thenAnswer(
          (_) async =>
              const SessionRestoreResult(status: SessionRestoreStatus.offline),
        );

        await provider.checkCachedToken();

        expect(provider.state, AuthState.authenticated);
        expect(provider.isPendingRevalidation, isTrue);
        verifyNever(() => mockRepo.clearCachedTokens());
      },
    );

    test(
      'an upgraded install whose last login is past the grace window goes to login',
      () async {
        trustStore.trust = null;
        when(() => mockRepo.getRememberedUser()).thenAnswer(
          (_) async => upgradingUser(
            lastLoginAt: DateTime.now().subtract(const Duration(days: 45)),
          ),
        );
        when(() => mockSupabase.restoreSession()).thenAnswer(
          (_) async =>
              const SessionRestoreResult(status: SessionRestoreStatus.offline),
        );

        await provider.checkCachedToken();

        expect(provider.state, AuthState.unauthenticated);
        expect(provider.isPendingRevalidation, isFalse);
        verifyNever(() => mockRepo.clearCachedTokens());
      },
    );

    test(
      'an upgraded install with no last login at all goes to login',
      () async {
        trustStore.trust = null;
        when(
          () => mockRepo.getRememberedUser(),
        ).thenAnswer((_) async => upgradingUser(lastLoginAt: null));
        when(() => mockSupabase.restoreSession()).thenAnswer(
          (_) async =>
              const SessionRestoreResult(status: SessionRestoreStatus.offline),
        );

        await provider.checkCachedToken();

        expect(provider.state, AuthState.unauthenticated);
        expect(provider.isPendingRevalidation, isFalse);
      },
    );
  });
}
