# Offline-Resilient Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A phone that has already signed in successfully keeps working fully offline instead of being bounced to `/login`, and silently re-establishes its Supabase session when connectivity returns.

**Architecture:** Split the single auth gate into two. The **login gate** stays exactly as strict as today (Supabase sign-in, real credentials). The **usage gate** stops asking "is the access token still fresh?" and instead asks "has this install proven a successful login, and is that proof still inside the offline grace window?". Startup runs a pure decision function (`decideStartupAuth`) over three inputs — the remembered local user, the result of trying to restore/refresh the Supabase session, and a secure-storage "session trust" record — and returns one of three outcomes: enter app, enter app pending re-validation, go to login. A lifecycle + connectivity trigger calls back into `AuthProvider.revalidateSession()` so the pending flag clears itself with no user action.

**Tech Stack:** Flutter, Provider (`ChangeNotifier`), `supabase_flutter ^2.5.0`, `flutter_secure_storage ^9.2.2`, `connectivity_plus ^6.1.0`, `sqflite`, `mocktail ^0.3.0`, `sqflite_common_ffi` for repository tests.

---

## Findings from the code (read this before Task 1)

The requirement doc guesses the root cause is Supabase refresh failing offline. **The code says otherwise.** The real chain:

1. `SupabaseService.signIn` (`lib/services/supabase/supabase_service.dart:236-248`) computes `tokenExpiry = _sessionExpiry(session)` — that is the **access token** expiry, ~1 hour — and writes it to the SQLite `users.tokenExpiry` column via `UserRepository.cacheToken`.
2. `AuthProvider.checkCachedToken()` (`lib/features/auth/providers/auth_provider.dart:59-82`) calls `UserRepository.getCachedUser()`.
3. `getCachedUser()` (`lib/data/repositories/user_repository.dart:69-83`) only returns a user when `user.isTokenValid`, i.e. `tokenExpiry.isAfter(DateTime.now())` (`lib/data/models/user_model.dart:60-63`).
4. So **~1 hour after sign-in, every cold start routes to `/login` — online or offline.** Nothing in `lib/` ever reads `Supabase.instance.client.auth.currentSession`, listens to `onAuthStateChange`, or calls `refreshSession()`. `supabase_flutter` refreshes its own persisted session in the background, but the app's gate never learns about it.

Two consequences for this plan:

- The fix is **mostly local**, not a Supabase settings change. The Supabase session-lifetime change (§3.1 of the requirement) is still needed so a long offline trip can still refresh on return, but it is not what unlocks acceptance criterion 1.
- "Remember me" is **off by default** (`lib/features/auth/screens/login_screen.dart:26`), and `rememberSession: false` means `tokenExpiry` is never written, so nothing is remembered at all. Offline grace therefore applies **only to users who ticked "Remember me"**, which matches the existing string "Offline mode available when Remember me is enabled" (`lib/core/constants/app_strings.dart:21`). Do not change that default.

Also note `AuthProvider` supports **local-only accounts** (`local-` id prefix, PBKDF2 password hash in `users.accessToken`, 30-day `tokenExpiry`). Those never had a Supabase session; they must keep their existing "valid while `tokenExpiry` is in the future" behaviour and must not be sent through the Supabase restore path.

### Deliverable 1 — where the three-case logic lives

`AuthProvider.checkCachedToken()` is the bootstrap step (called from `_HatchAuditAppState.initState`'s post-frame callback, `lib/app.dart:58`). It keeps that role, but the branching itself moves into a pure function `decideStartupAuth(...)` in `lib/features/auth/services/startup_auth_decision.dart`, fed by `SupabaseService.restoreSession()` and `SessionTrustStore`.

### Deliverable 2 — chosen session lifetime

| Setting | Value | Where |
|---|---|---|
| JWT (access token) expiry | 3600 s (unchanged) | Supabase Dashboard → Authentication → Sessions / JWT settings |
| Refresh token rotation | Enabled, reuse interval 10 s | Supabase Dashboard → Authentication → Sessions |
| Time-box user sessions | Disabled | Supabase Dashboard → Authentication → Sessions |
| Inactivity timeout | 90 days | Supabase Dashboard → Authentication → Sessions |
| **Local offline grace** | **30 days** | `AuthSessionPolicy.offlineGrace` (Task 1) |

Local grace (30 d) is deliberately **shorter** than the server session lifetime (90 d) so that a device returning from the longest permitted offline stretch can always still refresh rather than landing on a dead refresh token.

---

## Global Constraints

- **Never weaken a security check.** Offline grace applies only to an install that has already recorded a successful online authentication. No new bypass, no password-free path, no relaxation of `AuthSecurityPolicy`.
- **Session tokens stay in secure storage.** Access/refresh tokens live in `flutter_secure_storage` (`SecureTokenStore`) and in `supabase_flutter`'s own secure session store. Never write a token to SQLite. `users.accessToken` stays `NULL` for remote users (`UserRepository._persistedUser`); for `local-` users it keeps holding a PBKDF2 hash, not a token.
- **No connectivity failure may ever count as a logout.** Only a definitive server rejection observed **while online** clears trust.
- Do not change the "Remember me" default (`false`) or move the remembered email out of `SharedPreferences`.
- Do not touch SQLite schema, JSON shapes, sync payloads, or save primitives. This plan adds **no** migration.
- Run `flutter analyze` and the touched tests after every task; both must be clean before commit.
- Update `docs/LIVING_SPEC.md` (auth/session section + Change Log) in the final task, per that file's own rule.

---

## File Structure

**Create:**
- `lib/core/security/auth_session_policy.dart` — the offline-grace constant and local-account session length. One place to change the policy.
- `lib/services/auth/session_trust_store.dart` — secure-storage record of "this install authenticated successfully at time T as user U". Sits next to the existing `secure_token_store.dart`.
- `lib/features/auth/services/startup_auth_decision.dart` — pure three-case decision function + its enum. No IO, fully unit-testable.
- `lib/features/auth/services/session_revalidation_trigger.dart` — app-resume + connectivity-return trigger that fires the background re-validation.
- `test/services/auth/session_trust_store_test.dart`
- `test/features/auth/startup_auth_decision_test.dart`
- `test/features/auth/session_revalidation_trigger_test.dart`
- `test/data/repositories/remembered_user_test.dart`
- `test/services/supabase/session_restore_test.dart`

**Modify:**
- `lib/data/repositories/user_repository.dart` — replace `getCachedUser()` with `getRememberedUser()` (drops the `isTokenValid` gate; keeps the "remember me" gate).
- `lib/services/supabase/supabase_service.dart` — add `SessionRestoreStatus`, `SessionRestoreResult`, `restoreSession()`, and the pure `classifyRestoreFailure()`.
- `lib/features/auth/providers/auth_provider.dart` — rewrite `checkCachedToken()` around the decision function; add `isPendingRevalidation` + `revalidateSession()`; record/clear trust on login/logout/rejection.
- `lib/app.dart` — own the `SessionRevalidationTrigger` lifecycle.
- `test/features/auth/auth_provider_test.dart` — update for the new repository method and constructor parameter.
- `docs/LIVING_SPEC.md` — auth/session behaviour + Change Log.

**Deliberately unchanged:** `authRedirectRouteForState` in `lib/app.dart`. The offline user stays `AuthState.authenticated` with a separate `isPendingRevalidation` flag, so no existing `state == AuthState.authenticated` permission check (e.g. the Govee launcher gate at `lib/app.dart:129`) silently changes meaning. Adding a fourth enum value would have required auditing every one of those.

---

### Task 1: Session trust record

The proof that this install has authenticated before. Kept in the Keychain, not SQLite, so it cannot be read or forged from the app's database file.

**Files:**
- Create: `lib/core/security/auth_session_policy.dart`
- Create: `lib/services/auth/session_trust_store.dart`
- Test: `test/services/auth/session_trust_store_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `AuthSessionPolicy.offlineGrace` → `Duration` (30 days)
  - `class SessionTrust { final String userId; final DateTime lastVerifiedAt; }`
  - `SessionTrustStore({Future<String?> Function(String)? readValue, Future<void> Function(String, String)? writeValue, Future<void> Function(String)? deleteValue})`
  - `Future<SessionTrust?> read()`
  - `Future<void> record(String userId, DateTime verifiedAt)`
  - `Future<void> clear()`

- [ ] **Step 1: Write the failing test**

Create `test/services/auth/session_trust_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/auth/session_trust_store.dart';

void main() {
  late Map<String, String> storage;
  late SessionTrustStore store;

  setUp(() {
    storage = <String, String>{};
    store = SessionTrustStore(
      readValue: (key) async => storage[key],
      writeValue: (key, value) async => storage[key] = value,
      deleteValue: (key) async => storage.remove(key),
    );
  });

  test('read returns null when nothing was ever recorded', () async {
    expect(await store.read(), isNull);
  });

  test('record then read round-trips user and verification time', () async {
    final verifiedAt = DateTime.utc(2026, 8, 13, 9, 30);
    await store.record('supabase-user-123', verifiedAt);

    final trust = await store.read();
    expect(trust, isNotNull);
    expect(trust!.userId, 'supabase-user-123');
    expect(trust.lastVerifiedAt, verifiedAt);
  });

  test('record overwrites the previous trust record', () async {
    await store.record('user-a', DateTime.utc(2026, 8, 1));
    await store.record('user-b', DateTime.utc(2026, 8, 12));

    final trust = await store.read();
    expect(trust!.userId, 'user-b');
    expect(trust.lastVerifiedAt, DateTime.utc(2026, 8, 12));
  });

  test('clear removes the record', () async {
    await store.record('user-a', DateTime.utc(2026, 8, 1));
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('corrupt stored payload is treated as no trust, not a crash', () async {
    storage['session_trust_v1'] = 'not-json';
    expect(await store.read(), isNull);
  });

  test('payload missing required fields is treated as no trust', () async {
    storage['session_trust_v1'] = '{"userId":"user-a"}';
    expect(await store.read(), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/auth/session_trust_store_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:hatchaudit/services/auth/session_trust_store.dart'`.

- [ ] **Step 3: Write the policy constants**

Create `lib/core/security/auth_session_policy.dart`:

```dart
/// How long the two auth gates stay open.
///
/// The login gate (real Supabase credentials) is unchanged by these values.
/// These govern only the usage gate: how long a device that has *already*
/// proven a successful login may keep working while it cannot reach the
/// server.
class AuthSessionPolicy {
  const AuthSessionPolicy._();

  /// A device that authenticated successfully may keep working offline for
  /// this long before it must prove itself again.
  ///
  /// Deliberately shorter than the Supabase inactivity timeout (90 days) so a
  /// device returning from the longest permitted offline stretch can still
  /// refresh instead of meeting a dead refresh token.
  static const Duration offlineGrace = Duration(days: 30);
}
```

- [ ] **Step 4: Write the trust store**

Create `lib/services/auth/session_trust_store.dart`:

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Proof that this install completed a successful online authentication.
///
/// This is *not* a credential — it grants nothing on its own. It only records
/// that the login gate was passed, so the usage gate can stay open while the
/// device is offline.
@immutable
class SessionTrust {
  final String userId;
  final DateTime lastVerifiedAt;

  const SessionTrust({required this.userId, required this.lastVerifiedAt});
}

/// Keychain-backed store for the [SessionTrust] record.
///
/// Lives in secure storage rather than SQLite so it cannot be read or edited
/// from the app's database file.
class SessionTrustStore {
  static const String storageKey = 'session_trust_v1';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static final Map<String, String> _webFallback = <String, String>{};

  final Future<String?> Function(String key) _readValue;
  final Future<void> Function(String key, String value) _writeValue;
  final Future<void> Function(String key) _deleteValue;

  SessionTrustStore({
    Future<String?> Function(String key)? readValue,
    Future<void> Function(String key, String value)? writeValue,
    Future<void> Function(String key)? deleteValue,
  }) : _readValue = readValue ?? _defaultRead,
       _writeValue = writeValue ?? _defaultWrite,
       _deleteValue = deleteValue ?? _defaultDelete;

  static Future<String?> _defaultRead(String key) async {
    if (kIsWeb) return _webFallback[key];
    return _storage.read(key: key);
  }

  static Future<void> _defaultWrite(String key, String value) async {
    if (kIsWeb) {
      _webFallback[key] = value;
      return;
    }
    await _storage.write(key: key, value: value);
  }

  static Future<void> _defaultDelete(String key) async {
    if (kIsWeb) {
      _webFallback.remove(key);
      return;
    }
    await _storage.delete(key: key);
  }

  Future<SessionTrust?> read() async {
    final raw = await _readValue(storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final userId = decoded['userId'];
      final verifiedAt = decoded['lastVerifiedAt'];
      if (userId is! String || userId.isEmpty || verifiedAt is! String) {
        return null;
      }
      final parsed = DateTime.tryParse(verifiedAt);
      if (parsed == null) return null;
      return SessionTrust(userId: userId, lastVerifiedAt: parsed);
    } catch (_) {
      return null;
    }
  }

  Future<void> record(String userId, DateTime verifiedAt) async {
    await _writeValue(
      storageKey,
      jsonEncode({
        'userId': userId,
        'lastVerifiedAt': verifiedAt.toIso8601String(),
      }),
    );
  }

  Future<void> clear() => _deleteValue(storageKey);
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/services/auth/session_trust_store_test.dart`
Expected: PASS (6 tests).

Note: `DateTime.utc(...)` round-trips through `toIso8601String`/`tryParse` preserving the UTC flag, so the equality assertions hold.

- [ ] **Step 6: Analyze and commit**

Run: `flutter analyze lib/core/security/auth_session_policy.dart lib/services/auth/session_trust_store.dart`
Expected: `No issues found!`

```bash
git add lib/core/security/auth_session_policy.dart lib/services/auth/session_trust_store.dart test/services/auth/session_trust_store_test.dart
git commit -m "feat(auth): add keychain-backed session trust record and offline grace policy"
```

---

### Task 2: Remembered-user lookup that survives an expired access token

Today the usage gate dies with the 1-hour access token. This decouples them: the repository answers "did this user tick Remember me?", not "is the access token fresh?".

**Files:**
- Modify: `lib/data/repositories/user_repository.dart:69-83`
- Modify: `lib/features/auth/providers/auth_provider.dart:72` (call site only, to keep the tree compiling)
- Modify: `test/features/auth/auth_provider_test.dart` (rename the stubbed method)
- Test: `test/data/repositories/remembered_user_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Future<UserModel?> UserRepository.getRememberedUser()` — the most recently used approved user that has a non-null `tokenExpiry` (i.e. "Remember me" was on) and a token still present in secure storage, **regardless of whether `tokenExpiry` is in the past**. Replaces `getCachedUser()`, whose only production caller was `AuthProvider`.

- [ ] **Step 1: Write the failing test**

Create `test/data/repositories/remembered_user_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/user_repository.dart';
import 'package:hatchaudit/services/auth/secure_token_store.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/remembered_user_test.dart`
Expected: FAIL — two reasons: `UserRepository` has no `dbHelper` constructor parameter, and no `getRememberedUser` method.

- [ ] **Step 3: Make `UserRepository` injectable and add the new lookup**

In `lib/data/repositories/user_repository.dart`, replace the field declaration:

```dart
class UserRepository {
  final dbHelper = DatabaseHelper();
```

with an injectable one:

```dart
class UserRepository {
  final DatabaseHelper dbHelper;

  UserRepository({DatabaseHelper? dbHelper})
    : dbHelper = dbHelper ?? DatabaseHelper();
```

Then replace the whole `getCachedUser()` method (currently lines 69-83) with:

```dart
  /// The user this install should come back as, if any.
  ///
  /// "Remembered" means the user ticked Remember me (non-null `tokenExpiry`)
  /// and a token is still in secure storage. It deliberately does **not**
  /// require `tokenExpiry` to be in the future: the access token expires
  /// hourly, and letting that decide the usage gate is what used to lock
  /// field users out. Freshness is decided later, by the session restore
  /// path plus the offline grace window.
  Future<UserModel?> getRememberedUser() async {
    final db = await dbHelper.db;
    final result = await db.query(
      'users',
      where: "status = 'approved' AND tokenExpiry IS NOT NULL",
      orderBy: 'lastLoginAt DESC, tokenExpiry DESC',
    );
    for (final row in result) {
      final user = await _attachStoredToken(UserModel.fromMap(row));
      if (user != null) {
        return user;
      }
    }
    return null;
  }
```

- [ ] **Step 4: Update the call site and its test stubs so the tree compiles**

In `lib/features/auth/providers/auth_provider.dart:72`, change:

```dart
      final cachedUser = await _userRepository.getCachedUser();
```

to:

```dart
      final cachedUser = await _userRepository.getRememberedUser();
```

(The full rewrite of this method happens in Task 4; this is just a rename so the build stays green.)

In `test/features/auth/auth_provider_test.dart`, replace every `mockRepo.getCachedUser()` occurrence (lines 95, 101, 107, 117, 324) with `mockRepo.getRememberedUser()`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/data/repositories/remembered_user_test.dart test/features/auth/auth_provider_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze and commit**

Run: `flutter analyze lib test`
Expected: `No issues found!`

```bash
git add lib/data/repositories/user_repository.dart lib/features/auth/providers/auth_provider.dart test/data/repositories/remembered_user_test.dart test/features/auth/auth_provider_test.dart
git commit -m "feat(auth): remember signed-in user independently of access-token expiry"
```

---

### Task 3: Supabase session restore with a tri-state outcome

The app currently never asks Supabase about its session. This adds that call and — critically — classifies its failures into "no network, try later" versus "server said no".

**Files:**
- Modify: `lib/services/supabase/supabase_service.dart` (add near `signIn`, around line 200)
- Test: `test/services/supabase/session_restore_test.dart`

**Interfaces:**
- Consumes: `SupabaseService._client`, `_isConfigured()`, `_checkNetworkAvailability()`, `_ensureSupabaseReady()` (all existing private members).
- Produces:
  - `enum SessionRestoreStatus { valid, refreshed, offline, rejected }`
  - `class SessionRestoreResult { final SessionRestoreStatus status; final String? userId; final String? accessToken; final DateTime? expiresAt; }`
  - `Future<SessionRestoreResult> SupabaseService.restoreSession()`
  - `@visibleForTesting SessionRestoreStatus classifyRestoreFailure(Object error)`

- [ ] **Step 1: Write the failing test**

Create `test/services/supabase/session_restore_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:hatchaudit/services/supabase/supabase_service.dart';

void main() {
  group('classifyRestoreFailure', () {
    test('socket failures are offline, never a logout', () {
      expect(
        classifyRestoreFailure(const SocketException('Failed host lookup')),
        SessionRestoreStatus.offline,
      );
    });

    test('network-worded errors are offline', () {
      for (final message in [
        'Failed host lookup: supabase.co',
        'Connection reset by peer',
        'Connection closed before full header was received',
        'Network is unreachable',
        'Operation timed out',
      ]) {
        expect(
          classifyRestoreFailure(Exception(message)),
          SessionRestoreStatus.offline,
          reason: message,
        );
      }
    });

    test('an auth rejection is a real logout', () {
      expect(
        classifyRestoreFailure(
          const AuthException('Invalid Refresh Token: Already Used'),
        ),
        SessionRestoreStatus.rejected,
      );
    });

    test('an auth exception worded as a network fault stays offline', () {
      expect(
        classifyRestoreFailure(const AuthException('Failed host lookup')),
        SessionRestoreStatus.offline,
      );
    });

    test('an unrecognised error is offline, not a logout', () {
      expect(
        classifyRestoreFailure(StateError('server exploded')),
        SessionRestoreStatus.offline,
      );
    });
  });

  group('SessionRestoreResult', () {
    test('offline result carries no session material', () {
      const result = SessionRestoreResult(status: SessionRestoreStatus.offline);
      expect(result.userId, isNull);
      expect(result.accessToken, isNull);
      expect(result.expiresAt, isNull);
    });
  });

  group('restoreSession', () {
    test('reports offline when the device has no network', () async {
      final service = SupabaseService(
        isConfiguredForTesting: () => true,
        checkNetworkAvailableForTesting: () async => false,
        initializeSupabaseForTesting: () async => true,
      );

      final result = await service.restoreSession();

      expect(result.status, SessionRestoreStatus.offline);
    });

    test('reports offline when Supabase is not configured', () async {
      final service = SupabaseService(
        isConfiguredForTesting: () => false,
        reloadConfigForTesting: () async {},
        checkNetworkAvailableForTesting: () async => true,
        initializeSupabaseForTesting: () async => true,
      );

      final result = await service.restoreSession();

      expect(result.status, SessionRestoreStatus.offline);
    });
  });
}
```

Rationale for the last case: an unconfigured build cannot prove anything about the session either way, so it must behave like "no network" — never like a rejection.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/supabase/session_restore_test.dart`
Expected: FAIL — `Undefined name 'classifyRestoreFailure'` / `SessionRestoreStatus` isn't defined.

- [ ] **Step 3: Implement the restore path**

In `lib/services/supabase/supabase_service.dart`, add above `class SupabaseService` (next to the other top-level declarations):

```dart
/// Outcome of asking Supabase whether this device's session is still good.
///
/// The distinction that matters: [offline] means "we could not ask", and must
/// never be treated as a logout. Only [rejected] — a definitive answer from
/// the server while online — is a logout.
enum SessionRestoreStatus { valid, refreshed, offline, rejected }

class SessionRestoreResult {
  final SessionRestoreStatus status;
  final String? userId;
  final String? accessToken;
  final DateTime? expiresAt;

  const SessionRestoreResult({
    required this.status,
    this.userId,
    this.accessToken,
    this.expiresAt,
  });
}

const List<String> _networkErrorMarkers = [
  'socket',
  'failed host',
  'network',
  'connection',
  'timed out',
  'timeout',
  'unreachable',
  'handshake',
];

/// Errors are classified conservatively: anything that is not unmistakably a
/// server-side rejection counts as [SessionRestoreStatus.offline], so an
/// ambiguous failure keeps the user signed in rather than locking them out of
/// data that lives on their own phone.
@visibleForTesting
SessionRestoreStatus classifyRestoreFailure(Object error) {
  final message = error.toString().toLowerCase();
  if (_networkErrorMarkers.any(message.contains)) {
    return SessionRestoreStatus.offline;
  }
  if (error is AuthException) {
    return SessionRestoreStatus.rejected;
  }
  return SessionRestoreStatus.offline;
}
```

Then add this method to `SupabaseService`, immediately after `signIn` (after line 263):

```dart
  /// Ask Supabase whether this device's stored session is still usable,
  /// refreshing it if needed.
  ///
  /// Callers must treat [SessionRestoreStatus.offline] as "try again later",
  /// never as a sign-out.
  Future<SessionRestoreResult> restoreSession() async {
    if (!_isConfigured()) {
      await _reloadConfig();
    }
    await _checkNetworkAvailability();
    if (!_isConfigured() || !_isNetworkAvailable) {
      return const SessionRestoreResult(status: SessionRestoreStatus.offline);
    }
    if (!await _ensureSupabaseReady()) {
      return const SessionRestoreResult(status: SessionRestoreStatus.offline);
    }

    try {
      final current = _client.auth.currentSession;
      if (current == null) {
        // Online, and Supabase holds no session for this device: there is
        // nothing to refresh, so real credentials are required.
        return const SessionRestoreResult(
          status: SessionRestoreStatus.rejected,
        );
      }
      if (!current.isExpired) {
        return SessionRestoreResult(
          status: SessionRestoreStatus.valid,
          userId: current.user.id,
          accessToken: current.accessToken,
          expiresAt: _sessionExpiry(current),
        );
      }

      final response = await _client.auth.refreshSession();
      final refreshed = response.session;
      if (refreshed == null) {
        return const SessionRestoreResult(
          status: SessionRestoreStatus.rejected,
        );
      }
      return SessionRestoreResult(
        status: SessionRestoreStatus.refreshed,
        userId: refreshed.user.id,
        accessToken: refreshed.accessToken,
        expiresAt: _sessionExpiry(refreshed),
      );
    } catch (e) {
      final status = classifyRestoreFailure(e);
      safeDebugLog('Supabase session restore failed ($status)', error: e);
      return SessionRestoreResult(status: status);
    }
  }
```

- [ ] **Step 4: Make automatic refresh explicit at initialization**

In `lib/services/supabase/supabase_initializer.dart`, change the `Supabase.initialize` call to state the refresh behaviour instead of relying on the default:

```dart
    final initialization =
        Supabase.initialize(
              url: SupabaseConfig.url,
              anonKey: SupabaseConfig.anonKey,
              authOptions: const FlutterAuthClientOptions(
                autoRefreshToken: true,
              ),
            )
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/services/supabase/session_restore_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 6: Analyze and commit**

Run: `flutter analyze lib/services/supabase`
Expected: `No issues found!`

```bash
git add lib/services/supabase/supabase_service.dart lib/services/supabase/supabase_initializer.dart test/services/supabase/session_restore_test.dart
git commit -m "feat(auth): add tri-state Supabase session restore that never mistakes offline for logout"
```

---

### Task 4: The three-case startup decision

The heart of the change, kept as a pure function so every branch of the requirement is directly testable.

**Files:**
- Create: `lib/features/auth/services/startup_auth_decision.dart`
- Test: `test/features/auth/startup_auth_decision_test.dart`

**Interfaces:**
- Consumes: `SessionRestoreStatus` (Task 3), `AuthSessionPolicy.offlineGrace` (Task 1).
- Produces:
  - `enum StartupAuthDecision { goToLogin, enterApp, enterAppPendingRevalidation }`
  - `StartupAuthDecision decideStartupAuth({required bool hasRememberedUser, required bool isLocalAccount, required bool localTokenValid, required SessionRestoreStatus? sessionStatus, required Duration? sinceLastVerified, Duration offlineGrace})`

- [ ] **Step 1: Write the failing test**

Create `test/features/auth/startup_auth_decision_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/core/security/auth_session_policy.dart';
import 'package:hatchaudit/features/auth/services/startup_auth_decision.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';

void main() {
  StartupAuthDecision decide({
    bool hasRememberedUser = true,
    bool isLocalAccount = false,
    bool localTokenValid = false,
    SessionRestoreStatus? sessionStatus,
    Duration? sinceLastVerified = const Duration(days: 1),
  }) {
    return decideStartupAuth(
      hasRememberedUser: hasRememberedUser,
      isLocalAccount: isLocalAccount,
      localTokenValid: localTokenValid,
      sessionStatus: sessionStatus,
      sinceLastVerified: sinceLastVerified,
    );
  }

  test('a fresh install with nothing remembered goes to login', () {
    expect(
      decide(hasRememberedUser: false, sessionStatus: null),
      StartupAuthDecision.goToLogin,
    );
  });

  test('a still-valid session enters the app', () {
    expect(
      decide(sessionStatus: SessionRestoreStatus.valid),
      StartupAuthDecision.enterApp,
    );
  });

  test('a silently refreshed session enters the app', () {
    expect(
      decide(sessionStatus: SessionRestoreStatus.refreshed),
      StartupAuthDecision.enterApp,
    );
  });

  test('a server rejection while online goes to login', () {
    expect(
      decide(sessionStatus: SessionRestoreStatus.rejected),
      StartupAuthDecision.goToLogin,
    );
  });

  test('offline inside the grace window enters the app pending revalidation', () {
    expect(
      decide(
        sessionStatus: SessionRestoreStatus.offline,
        sinceLastVerified: const Duration(days: 29, hours: 23),
      ),
      StartupAuthDecision.enterAppPendingRevalidation,
    );
  });

  test('offline exactly at the grace boundary still enters the app', () {
    expect(
      decide(
        sessionStatus: SessionRestoreStatus.offline,
        sinceLastVerified: AuthSessionPolicy.offlineGrace,
      ),
      StartupAuthDecision.enterAppPendingRevalidation,
    );
  });

  test('offline past the grace window goes to login', () {
    expect(
      decide(
        sessionStatus: SessionRestoreStatus.offline,
        sinceLastVerified: AuthSessionPolicy.offlineGrace +
            const Duration(seconds: 1),
      ),
      StartupAuthDecision.goToLogin,
    );
  });

  test('offline with no recorded successful login goes to login', () {
    expect(
      decide(
        sessionStatus: SessionRestoreStatus.offline,
        sinceLastVerified: null,
      ),
      StartupAuthDecision.goToLogin,
    );
  });

  test('a clock that jumped backwards is treated as within grace', () {
    expect(
      decide(
        sessionStatus: SessionRestoreStatus.offline,
        sinceLastVerified: const Duration(days: -2),
      ),
      StartupAuthDecision.enterAppPendingRevalidation,
    );
  });

  test('a valid local account enters the app without asking Supabase', () {
    expect(
      decide(
        isLocalAccount: true,
        localTokenValid: true,
        sessionStatus: null,
        sinceLastVerified: null,
      ),
      StartupAuthDecision.enterApp,
    );
  });

  test('an expired local account goes to login', () {
    expect(
      decide(
        isLocalAccount: true,
        localTokenValid: false,
        sessionStatus: null,
        sinceLastVerified: const Duration(days: 1),
      ),
      StartupAuthDecision.goToLogin,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/auth/startup_auth_decision_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../startup_auth_decision.dart'`.

- [ ] **Step 3: Write the decision function**

Create `lib/features/auth/services/startup_auth_decision.dart`:

```dart
import '../../../core/security/auth_session_policy.dart';
import '../../../services/supabase/supabase_service.dart';

/// What the app should do with a startup (or resume) auth check.
enum StartupAuthDecision {
  /// Show the real login screen. Credentials are required.
  goToLogin,

  /// Proceed into the app with a session known to be good.
  enterApp,

  /// Proceed into the app on the strength of a previous successful login.
  /// The session still needs re-validating once the network returns.
  enterAppPendingRevalidation,
}

/// The three-case gate from the offline-auth requirement.
///
/// Authentication guards the door, not the data: a device that has already
/// proven a successful login keeps working while it cannot reach the server.
/// Only a definitive rejection *while online*, or the absence of any prior
/// successful login, sends the user back to `/login`.
///
/// - [sessionStatus] is null when Supabase was never consulted (local-only
///   account).
/// - [sinceLastVerified] is null when this install has never recorded a
///   successful online authentication.
StartupAuthDecision decideStartupAuth({
  required bool hasRememberedUser,
  required bool isLocalAccount,
  required bool localTokenValid,
  required SessionRestoreStatus? sessionStatus,
  required Duration? sinceLastVerified,
  Duration offlineGrace = AuthSessionPolicy.offlineGrace,
}) {
  if (!hasRememberedUser) {
    return StartupAuthDecision.goToLogin;
  }

  // Local-only accounts never had a Supabase session; their own expiry rules.
  if (isLocalAccount) {
    return localTokenValid
        ? StartupAuthDecision.enterApp
        : StartupAuthDecision.goToLogin;
  }

  switch (sessionStatus) {
    case SessionRestoreStatus.valid:
    case SessionRestoreStatus.refreshed:
      return StartupAuthDecision.enterApp;
    case SessionRestoreStatus.rejected:
      return StartupAuthDecision.goToLogin;
    case SessionRestoreStatus.offline:
    case null:
      if (sinceLastVerified == null) {
        return StartupAuthDecision.goToLogin;
      }
      // A device whose clock moved backwards yields a negative duration; that
      // is a clock problem, not a stale session, so keep the user working.
      return sinceLastVerified <= offlineGrace
          ? StartupAuthDecision.enterAppPendingRevalidation
          : StartupAuthDecision.goToLogin;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/auth/startup_auth_decision_test.dart`
Expected: PASS (11 tests).

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze lib/features/auth/services`
Expected: `No issues found!`

```bash
git add lib/features/auth/services/startup_auth_decision.dart test/features/auth/startup_auth_decision_test.dart
git commit -m "feat(auth): add pure three-case startup auth decision"
```

---

### Task 5: Wire the decision into AuthProvider

**Files:**
- Modify: `lib/features/auth/providers/auth_provider.dart:22-130` and `:382-399`
- Test: `test/features/auth/auth_provider_test.dart`

**Interfaces:**
- Consumes: `UserRepository.getRememberedUser()` (Task 2), `SupabaseService.restoreSession()` (Task 3), `decideStartupAuth(...)` (Task 4), `SessionTrustStore` (Task 1).
- Produces:
  - `AuthProvider({..., SessionTrustStore? sessionTrustStore})`
  - `bool get isPendingRevalidation`
  - `Future<void> revalidateSession()`

- [ ] **Step 1: Write the failing tests**

Append to the existing `main()` in `test/features/auth/auth_provider_test.dart` (keep the existing mocks and helpers; add the trust-store fake near the other mocks):

```dart
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
```

Add these imports at the top of the file:

```dart
import 'package:hatchaudit/services/auth/session_trust_store.dart';
```

Add this group inside `main()`:

```dart
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
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/auth/auth_provider_test.dart`
Expected: FAIL — no `sessionTrustStore` parameter, no `isPendingRevalidation`, no `revalidateSession`.

- [ ] **Step 3: Implement the provider changes**

In `lib/features/auth/providers/auth_provider.dart`, add imports:

```dart
import '../../../services/auth/session_trust_store.dart';
import '../services/startup_auth_decision.dart';
```

Add the field and constructor parameter (extending the existing constructor at lines 30-43):

```dart
  final SessionTrustStore _sessionTrustStore;

  AuthProvider({
    UserRepository? userRepository,
    ActivityLogRepository? activityLogRepository,
    SupabaseService? supabaseService,
    SessionTrustStore? sessionTrustStore,
    bool bypassAuth = false,
  }) : _userRepository = userRepository ?? UserRepository(),
       _activityLogRepository =
           activityLogRepository ?? ActivityLogRepository(),
       _supabaseService = supabaseService ?? SupabaseService(),
       _sessionTrustStore = sessionTrustStore ?? SessionTrustStore(),
       _bypassAuth = bypassAuth && AuthSecurityPolicy.isDebugAuthBypassEnabled {
    if (_bypassAuth) {
      _activateDevelopmentUser();
    }
  }
```

Add the pending flag next to the other state fields (after line 47):

```dart
  bool _isPendingRevalidation = false;

  /// True when the app is running on a previously-proven login that has not
  /// yet been re-checked against the server. Local work is unaffected.
  bool get isPendingRevalidation => _isPendingRevalidation;
```

Replace `checkCachedToken()` (lines 59-82) with:

```dart
  Future<void> checkCachedToken() async {
    if (_bypassAuth) {
      if (_debugBypassSignedOut) {
        _user = null;
        _setState(AuthState.unauthenticated);
        return;
      }
      _activateDevelopmentUser(notify: true);
      return;
    }

    _setState(AuthState.loading);
    try {
      final remembered = await _userRepository.getRememberedUser();
      if (remembered == null) {
        _isPendingRevalidation = false;
        _setState(AuthState.unauthenticated);
        return;
      }

      final isLocalAccount = remembered.id.startsWith('local-');
      final restore = isLocalAccount
          ? null
          : await _supabaseService.restoreSession();
      final trust = await _sessionTrustStore.read();

      final decision = decideStartupAuth(
        hasRememberedUser: true,
        isLocalAccount: isLocalAccount,
        localTokenValid: remembered.isTokenValid,
        sessionStatus: restore?.status,
        sinceLastVerified: trust == null
            ? null
            : DateTime.now().difference(trust.lastVerifiedAt),
      );

      await _applyStartupDecision(decision, remembered, restore);
    } catch (e) {
      // A failure to *ask* is never a logout. Fall back to login only because
      // we have no proven user to fall back onto here.
      _isPendingRevalidation = false;
      _setState(AuthState.unauthenticated, error: e.toString());
    }
  }

  Future<void> _applyStartupDecision(
    StartupAuthDecision decision,
    UserModel remembered,
    SessionRestoreResult? restore,
  ) async {
    switch (decision) {
      case StartupAuthDecision.goToLogin:
        if (restore?.status == SessionRestoreStatus.rejected) {
          // A definitive server rejection while online is a real logout.
          await _sessionTrustStore.clear();
          await _userRepository.clearCachedTokens();
        }
        _user = null;
        _isPendingRevalidation = false;
        _setState(AuthState.unauthenticated);
      case StartupAuthDecision.enterApp:
        await _persistVerifiedSession(remembered, restore);
        _user = remembered;
        _isPendingRevalidation = false;
        _setState(
          remembered.isApproved
              ? AuthState.authenticated
              : AuthState.pendingApproval,
        );
      case StartupAuthDecision.enterAppPendingRevalidation:
        _user = remembered;
        _isPendingRevalidation = true;
        _setState(
          remembered.isApproved
              ? AuthState.authenticated
              : AuthState.pendingApproval,
        );
    }
  }

  Future<void> _persistVerifiedSession(
    UserModel user,
    SessionRestoreResult? restore,
  ) async {
    if (restore == null) return;
    final accessToken = restore.accessToken;
    final expiresAt = restore.expiresAt;
    if (accessToken != null && expiresAt != null) {
      await _userRepository.cacheToken(user.id, accessToken, expiresAt);
    }
    await _sessionTrustStore.record(user.id, DateTime.now());
  }

  /// Re-check a pending session once the network is back. Safe to call often;
  /// it is a no-op unless the app is running on offline grace.
  Future<void> revalidateSession() async {
    if (_bypassAuth || !_isPendingRevalidation) return;
    final user = _user;
    if (user == null || user.id.startsWith('local-')) return;

    final restore = await _supabaseService.restoreSession();
    switch (restore.status) {
      case SessionRestoreStatus.valid:
      case SessionRestoreStatus.refreshed:
        await _persistVerifiedSession(user, restore);
        _isPendingRevalidation = false;
        notifyListeners();
      case SessionRestoreStatus.rejected:
        await _sessionTrustStore.clear();
        await _userRepository.clearCachedTokens();
        _user = null;
        _isPendingRevalidation = false;
        _setState(AuthState.unauthenticated);
      case SessionRestoreStatus.offline:
        // Still no network. Stay signed in and try again later.
        break;
    }
  }
```

In `login()`, record trust on a successful remote sign-in. After line 99 (`await _userRepository.upsertUser(_user!);`) add:

```dart
        if (rememberSession && !_user!.id.startsWith('local-')) {
          await _sessionTrustStore.record(_user!.id, DateTime.now());
        }
        _isPendingRevalidation = false;
```

In `logout()`, clear trust. After `await _supabaseService.signOut();` (line 392) add:

```dart
      await _sessionTrustStore.clear();
      _isPendingRevalidation = false;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/auth/auth_provider_test.dart`
Expected: PASS — the pre-existing tests plus the 9 new ones.

- [ ] **Step 5: Run the full auth-related suite**

Run: `flutter test test/features/auth test/app_auth_navigation_test.dart test/data/repositories test/services/auth test/services/supabase`
Expected: PASS.

- [ ] **Step 6: Analyze and commit**

Run: `flutter analyze lib test`
Expected: `No issues found!`

```bash
git add lib/features/auth/providers/auth_provider.dart test/features/auth/auth_provider_test.dart
git commit -m "feat(auth): keep previously-authenticated devices inside the app when offline"
```

---

### Task 6: Re-validate automatically on resume and on connectivity return

Nothing so far triggers the silent recovery. This adds the two moments that matter, per requirement §3.1.

**Files:**
- Create: `lib/features/auth/services/session_revalidation_trigger.dart`
- Modify: `lib/app.dart:35-68`
- Test: `test/features/auth/session_revalidation_trigger_test.dart`

**Interfaces:**
- Consumes: `AuthProvider.revalidateSession()` (Task 5).
- Produces:
  - `bool shouldRevalidateOnConnectivity(List<ConnectivityResult> results)`
  - `class SessionRevalidationTrigger { SessionRevalidationTrigger({required Future<void> Function() onRevalidate, Stream<List<ConnectivityResult>>? connectivityStream}); void start(); void stop(); }`

- [ ] **Step 1: Write the failing test**

Create `test/features/auth/session_revalidation_trigger_test.dart`:

```dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/features/auth/services/session_revalidation_trigger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an interface coming up triggers revalidation', () {
    expect(
      shouldRevalidateOnConnectivity([ConnectivityResult.wifi]),
      isTrue,
    );
    expect(
      shouldRevalidateOnConnectivity([ConnectivityResult.mobile]),
      isTrue,
    );
  });

  test('losing all connectivity does not trigger revalidation', () {
    expect(shouldRevalidateOnConnectivity([ConnectivityResult.none]), isFalse);
    expect(shouldRevalidateOnConnectivity([]), isFalse);
  });

  test('connectivity events fire the callback', () async {
    final controller = StreamController<List<ConnectivityResult>>();
    var calls = 0;
    final trigger = SessionRevalidationTrigger(
      onRevalidate: () async => calls++,
      connectivityStream: controller.stream,
    );
    trigger.start();

    controller.add([ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);

    controller.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    trigger.stop();
    controller.add([ConnectivityResult.mobile]);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    await controller.close();
  });

  test('app resume fires the callback, other lifecycle states do not', () async {
    final controller = StreamController<List<ConnectivityResult>>();
    var calls = 0;
    final trigger = SessionRevalidationTrigger(
      onRevalidate: () async => calls++,
      connectivityStream: controller.stream,
    );
    trigger.start();

    trigger.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);

    trigger.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    trigger.stop();
    await controller.close();
  });

  test('a callback that throws does not break later triggers', () async {
    final controller = StreamController<List<ConnectivityResult>>();
    var calls = 0;
    final trigger = SessionRevalidationTrigger(
      onRevalidate: () async {
        calls++;
        throw StateError('boom');
      },
      connectivityStream: controller.stream,
    );
    trigger.start();

    controller.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(Duration.zero);
    controller.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(Duration.zero);

    expect(calls, 2);

    trigger.stop();
    await controller.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/auth/session_revalidation_trigger_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../session_revalidation_trigger.dart'`.

- [ ] **Step 3: Write the trigger**

Create `lib/features/auth/services/session_revalidation_trigger.dart`:

```dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../../../core/security/safe_debug_log.dart';

/// A connectivity event is worth acting on only when some interface is up.
bool shouldRevalidateOnConnectivity(List<ConnectivityResult> results) {
  if (results.isEmpty) return false;
  return results.any((result) => result != ConnectivityResult.none);
}

/// Fires a silent session re-validation when the app resumes or the network
/// comes back. Never shows UI and never blocks anything.
class SessionRevalidationTrigger with WidgetsBindingObserver {
  final Future<void> Function() _onRevalidate;
  final Stream<List<ConnectivityResult>> _connectivityStream;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _started = false;

  SessionRevalidationTrigger({
    required Future<void> Function() onRevalidate,
    Stream<List<ConnectivityResult>>? connectivityStream,
  }) : _onRevalidate = onRevalidate,
       _connectivityStream =
           connectivityStream ?? Connectivity().onConnectivityChanged;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _subscription = _connectivityStream.listen((results) {
      if (shouldRevalidateOnConnectivity(results)) {
        _fire();
      }
    }, onError: (Object error) {
      safeDebugLog('Connectivity stream error', error: error);
    });
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fire();
    }
  }

  void _fire() {
    unawaited(
      _onRevalidate().catchError((Object error) {
        safeDebugLog('Session revalidation failed', error: error);
      }),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/auth/session_revalidation_trigger_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Wire it into the app**

In `lib/app.dart`, add the import:

```dart
import 'features/auth/services/session_revalidation_trigger.dart';
```

Add the field alongside the other `late final` fields (after line 39):

```dart
  late final SessionRevalidationTrigger _sessionRevalidationTrigger;
```

In `initState`, after `_authProvider = AuthProvider(bypassAuth: _authBypassEnabled);` (line 50):

```dart
    _sessionRevalidationTrigger = SessionRevalidationTrigger(
      onRevalidate: _authProvider.revalidateSession,
    )..start();
```

In `dispose` (line 64-68), before `super.dispose()`:

```dart
    _sessionRevalidationTrigger.stop();
```

- [ ] **Step 6: Run the suite and commit**

Run: `flutter test test/features/auth test/app_auth_navigation_test.dart test/app_govee_launcher_visibility_test.dart`
Expected: PASS.

Run: `flutter analyze lib test`
Expected: `No issues found!`

```bash
git add lib/features/auth/services/session_revalidation_trigger.dart lib/app.dart test/features/auth/session_revalidation_trigger_test.dart
git commit -m "feat(auth): re-establish the session silently on resume and reconnect"
```

---

### Task 7: Supabase session settings, spec update, and field verification

The code change is done; this is the configuration half of the requirement plus the proof.

**Files:**
- Modify: `docs/LIVING_SPEC.md` (auth/session section + Change Log + "Last Updated")
- No code changes.

**Interfaces:**
- Consumes: everything above.
- Produces: documented behaviour.

- [ ] **Step 1: Apply the Supabase Auth session settings**

In the Supabase Dashboard → **Authentication → Sessions** (and **JWT settings**) for the ChickMark project, set:

| Setting | Value |
|---|---|
| Access token (JWT) expiry | `3600` seconds |
| Refresh token rotation | Enabled |
| Refresh token reuse interval | `10` seconds |
| Time-box user sessions | Disabled (no forced expiry) |
| Inactivity timeout | `90 days` |

These are project-level dashboard settings, not repo config — there is no migration to write. Record the values you actually applied; if the dashboard disagrees with this table, trust the dashboard and update the table.

- [ ] **Step 2: Verify on a device — airplane mode**

1. Build and run on a real iPhone with connectivity: `flutter run -d <device>`.
2. Sign in **with "Remember me" ticked**.
3. Force-quit the app. Enable **Airplane Mode**. Wait past the 1-hour access-token expiry (or set the device clock forward by 2 hours to shortcut it, then set it back).
4. Open the app.

Expected: the app lands on `/main`, not `/login`. Create a visit, fill stations, capture photos, save and edit — all must work.

- [ ] **Step 3: Verify the silent recovery**

With the app still open from Step 2, turn Airplane Mode **off**.

Expected: no login prompt appears; sync resumes normally. Confirm in the debug console that `restoreSession` reported `valid`/`refreshed` (no `Supabase session restore failed` line).

- [ ] **Step 4: Verify the two real-logout paths**

1. **Fresh install:** delete the app, reinstall, open it. Expected: `/login`.
2. **Revoked session:** while online, sign the user out from the Supabase Dashboard (Authentication → Users → revoke sessions), then force-quit and reopen the app. Expected: `/login`.

- [ ] **Step 5: Update the living spec**

In `docs/LIVING_SPEC.md`:

- Update **§1 Last Updated** to `2026-08-13` and note the auth/session rework in its description paragraph.
- In the navigation/auth section (around lines 148-158), replace the auth-state-driven initial-route description with the two-gate model. Add text along these lines:

```markdown
Authentication has two independent gates. The **login gate** requires a real
Supabase sign-in and is unchanged. The **usage gate** decides whether an
already-signed-in install may keep working, and no longer depends on the
one-hour access-token expiry.

On startup `AuthProvider.checkCachedToken()` resolves the remembered user
(`UserRepository.getRememberedUser()` — approved, "Remember me" on, token still
in secure storage, regardless of `tokenExpiry`), asks Supabase to restore or
refresh the session (`SupabaseService.restoreSession()`), reads the Keychain
trust record (`SessionTrustStore`), and feeds all three into the pure
`decideStartupAuth()` function, which returns one of three outcomes:

- **Enter app** — the session is valid or was silently refreshed. The refreshed
  access token is re-cached in secure storage and the trust record is stamped.
- **Enter app pending re-validation** — the session could not be checked because
  the device is offline, but this install recorded a successful login within the
  offline grace window (`AuthSessionPolicy.offlineGrace`, 30 days). The app runs
  normally against local SQLite with `AuthProvider.isPendingRevalidation` set.
- **Go to login** — only when this install has never recorded a successful
  online login, when the grace window has lapsed, or when the server definitively
  rejected the session while online. A connectivity failure is never a logout.

`SessionRevalidationTrigger` (app resume + `connectivity_plus` reconnect) calls
`AuthProvider.revalidateSession()`, which clears the pending flag silently on
success and signs the device out only on a definitive rejection.

Local-only accounts (`local-` ids) bypass the Supabase path entirely and keep
their existing 30-day `tokenExpiry` rule.

Session lifetimes: Supabase JWT expiry 1 hour, refresh-token rotation on with a
10-second reuse interval, session time-boxing off, inactivity timeout 90 days.
The 30-day local offline grace is deliberately shorter than the server's 90-day
window so a returning device can always still refresh.

Tokens never move to SQLite: the access token stays in `SecureTokenStore` and the
trust record in `SessionTrustStore`, both Keychain-backed. `users.accessToken`
remains `NULL` for remote users.
```

- Add a Change Log entry dated `2026-08-13` describing the offline-resilient auth split.

- [ ] **Step 6: Full test run and commit**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: PASS.

```bash
git add docs/LIVING_SPEC.md
git commit -m "docs(spec): document the split login and usage auth gates"
```

---

### Task 8 (optional — confirm with product before starting)

Requirement §5 lists a pending-re-validation indicator as optional and asks for product confirmation. Do **not** start this task without that confirmation.

**Files:**
- Modify: `lib/features/home/widgets/main_shell.dart`
- Test: a widget test alongside the existing shell tests.

**Interfaces:**
- Consumes: `AuthProvider.isPendingRevalidation` (Task 5).
- Produces: no new public API.

- [ ] **Step 1: Confirm scope with product**

Ask explicitly: should the app show a passive "Offline — will reconnect" chip while `isPendingRevalidation` is true, and where (app bar vs. the existing sync status area)? If the answer is no, close this task and stop.

- [ ] **Step 2: Write the failing widget test**

Pump `MainShell` with a fake `AuthProvider` exposing `isPendingRevalidation == true`, assert the chip is found; pump with `false`, assert it is absent. Follow the fake-repository + bounded-`pump` pattern used by the existing widget tests (a real sqflite call inside `testWidgets` hangs under `FakeAsync`).

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/widgets/<new_test>.dart`
Expected: FAIL — chip not found.

- [ ] **Step 4: Add the indicator**

Render a passive, non-blocking chip via `context.select<AuthProvider, bool>((p) => p.isPendingRevalidation)`. It must be informational only — no button, no action, nothing that can block the audit workflow.

- [ ] **Step 5: Run test, analyze, commit**

Run: `flutter test test/widgets/<new_test>.dart && flutter analyze lib test`
Expected: PASS / `No issues found!`

```bash
git add lib/features/home/widgets/main_shell.dart test/widgets/<new_test>.dart
git commit -m "feat(auth): show a passive offline session indicator"
```

---

## Acceptance criteria → task map

| Criterion | Covered by |
|---|---|
| Airplane mode lands a signed-in user inside the app | Tasks 2, 3, 4, 5 · verified Task 7 Step 2 |
| All local workflows work offline in that state | Unchanged by design (state stays `AuthState.authenticated`) · verified Task 7 Step 2 |
| Session refreshes automatically on reconnect, no prompt | Tasks 5, 6 · verified Task 7 Step 3 |
| A brand-new install still shows `/login` | Task 4 (`hasRememberedUser: false`), Task 5 · verified Task 7 Step 4.1 |
| A revoked session detected online still routes to `/login` | Tasks 3, 4, 5 · verified Task 7 Step 4.2 |
| Tokens stay in secure storage, never SQLite | Task 1 (Keychain trust record), Task 2 (unchanged `_persistedUser`/`_attachStoredToken`) |
| Extended session lifetime chosen and configured | Task 1 (`offlineGrace`), Task 7 Step 1 (dashboard) |
| Living spec updated | Task 7 Step 5 |

## Open question for the user

The requirement's stated root cause (Supabase refresh failing offline) is not what the code does — the lockout is caused by the local SQLite `tokenExpiry` gate expiring hourly, which bounces users to `/login` **even when online**. This plan fixes the real cause and still applies the Supabase session-lifetime change, but flag it: if you were seeing lockouts *with* connectivity, that is the same bug, and it is fixed here.
