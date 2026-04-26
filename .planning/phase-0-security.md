# Phase 0 — Security & Critical Fixes

**Goal**: Eliminate real security vulnerabilities before any new features are added.
**Priority**: MANDATORY — nothing from Phase 1+ ships until this phase is complete and reviewed.
**Estimated time**: ~6 hours total
**DB version change**: None in this phase (v11 stays)

---

## TASK 0.1 — Fix SQL Injection in `_buildWhere`

**Risk**: HIGH
**Time**: 1.5h

### Problem

`_buildWhere()` and `_eggBreakoutTypeClause()` in `audit_repository.dart` build SQL WHERE clauses using string interpolation:

```dart
// CURRENT — VULNERABLE:
parts.add("customerId = '${filter.customerId}'");
parts.add("flockId = '${filter.flockId}'");
parts.add("auditType = '${_displayAuditType(auditType)}'");
// and in _eggBreakoutTypeClause:
return "AND ebBreakoutType = '$type'";
```

These values come from dropdown selections (UUIDs from DB), so direct exploitation is low — but the pattern is wrong and must be fixed before new features that use this method are added.

### Files to Read (context)
- `lib/data/repositories/audit_repository.dart` — full file

### Files to Modify
- `lib/data/repositories/audit_repository.dart`

### Step-by-Step Implementation

**Step 1**: Change `_buildWhere` to return both the WHERE clause string and a parameterized args list. Replace the existing `_buildWhere` method entirely:

```dart
// NEW: returns clause + args together
({String clause, List<Object?> args}) _buildWhereWithArgs(
  DashboardFilter filter,
  String auditType,
) {
  final parts = <String>['auditType = ?'];
  final args = <Object?>[_displayAuditType(auditType)];

  if (filter.customerId != null) {
    parts.add('customerId = ?');
    args.add(filter.customerId);
  }
  if (filter.flockId != null) {
    parts.add('flockId = ?');
    args.add(filter.flockId);
  }
  if (filter.bmkAge != null) {
    parts.add(
      'COALESCE(haBmkAge, ebBmkAge, chickBmkAge, esEggBmkAge, soIncubationAge, hoIncubationAge) = ?',
    );
    args.add(filter.bmkAge);
  }
  return (clause: 'WHERE ${parts.join(' AND ')}', args: args);
}
```

**Step 2**: Replace `_eggBreakoutTypeClause` to return clause + arg:

```dart
// NEW: returns clause + single arg
({String clause, Object? arg}) _eggBreakoutTypeArg(String breakoutType) {
  final type = switch (breakoutType) {
    'residue' => 'Hatch Residue',
    'fresh'   => 'Fresh Egg',
    'candled' => 'Candled Egg',
    _         => breakoutType,
  };
  return (clause: 'AND ebBreakoutType = ?', arg: type);
}
```

**Step 3**: Update every method that called `_buildWhere`. The pattern for each one is:

```dart
// BEFORE:
final where = _buildWhere(filter, 'hatch_analysis');
final result = await db.rawQuery('SELECT ... FROM audits $where');

// AFTER:
final (:clause, :args) = _buildWhereWithArgs(filter, 'hatch_analysis');
final result = await db.rawQuery('SELECT ... FROM audits $clause', args);
```

For egg breakout queries that also add the breakout type clause:
```dart
// BEFORE:
final where = _buildWhere(filter, 'hatch_analysis');
final typeClause = _eggBreakoutTypeClause(breakoutType);
final result = await db.rawQuery('SELECT ... FROM audits $where $typeClause');

// AFTER:
final (:clause, :args) = _buildWhereWithArgs(filter, 'hatch_analysis');
final (:clause as typeClause, :arg as typeArg) = _eggBreakoutTypeArg(breakoutType);
final result = await db.rawQuery(
  'SELECT ... FROM audits $clause $typeClause',
  [...args, typeArg],
);
```

**Step 4**: Delete the old `_buildWhere` method completely. Do not keep it.

**Step 5**: Add a safety guard on `PRAGMA table_info($table)`. The `$table` param is internal-only but still bad practice:

```dart
// Find this line:
final info = await db.rawQuery('PRAGMA table_info($table)');

// Add assertion above it:
assert(
  RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(table),
  'Invalid table name: $table',
);
// Keep the rawQuery line — assertion documents the safety guarantee
```

### Expected Output
All rawQuery calls in `audit_repository.dart` use `?` placeholders with args list. Zero string interpolation of filter values in SQL. `dart analyze` passes with no new warnings.

### Edge Cases
- `bmkAge` is `int?` — SQLite accepts int directly in args list, no conversion needed
- For egg breakout queries: args order must match clause order — `[...whereArgs, typeArg]` (type arg last, after WHERE args)
- `_buildWhere` is called ~12 times — find all calls with: `grep -n '_buildWhere' lib/data/repositories/audit_repository.dart`

### Manual Test
1. Open app → Dashboard tab → select any customer from dropdown
2. Charts should still load correctly
3. Select flock → charts filter correctly
4. No crash, no empty dashboard when filters applied
5. Add temporary `debugPrint('SQL args: $args')` → verify args are UUIDs, not SQL fragments

---

## TASK 0.2 — Fix Offline Password Hashing

**Risk**: HIGH
**Time**: 2h

### Problem

Current offline password token:
```dart
// In auth_provider.dart:
return 'local:${base64Url.encode(utf8.encode(password))}';
```
Base64 is encoding, not hashing. Anyone with read access to the SQLite file can decode the password. Must replace with SHA-256 + salt.

### Package Required
`crypto: ^3.0.3`

First check if already available transitively:
```bash
dart pub deps | grep "^│" | grep crypto
```
If found: no `pubspec.yaml` change needed. If not found: add to `dependencies`.

### Files to Read (context)
- `lib/features/auth/providers/auth_provider.dart` — full file
- `lib/data/repositories/user_repository.dart` — full file

### Files to Modify
- `lib/features/auth/providers/auth_provider.dart`
- `lib/data/repositories/user_repository.dart`
- `pubspec.yaml` (only if `crypto` not already available)

### Step-by-Step Implementation

**Step 1**: Add import to `auth_provider.dart`:
```dart
import 'package:crypto/crypto.dart';
```

**Step 2**: Replace `_localPasswordToken` with two new functions. Add these as private functions in `auth_provider.dart` (outside the class, or as static methods):

```dart
/// Creates a new v2 password hash: 'v2:<salt>:<sha256(salt:password)>'
String _hashPassword(String password, {String? existingSalt}) {
  final salt = existingSalt ?? _generateSalt();
  final content = utf8.encode('$salt:$password');
  final digest = sha256.convert(content);
  return 'v2:$salt:${digest.toString()}';
}

/// Generates a random 16-byte salt as base64url string
String _generateSalt() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return base64Url.encode(bytes);
}

/// Verifies password against stored token (supports both v1 legacy and v2)
bool _verifyPassword(String password, String storedToken) {
  if (storedToken.startsWith('v2:')) {
    final parts = storedToken.split(':');
    if (parts.length != 3) return false;
    final salt = parts[1];
    return _hashPassword(password, existingSalt: salt) == storedToken;
  }
  // Legacy v1 format — accept for migration, then upgrade
  final legacyToken = 'local:${base64Url.encode(utf8.encode(password))}';
  return storedToken == legacyToken;
}
```

Add `import 'dart:math';` for `Random.secure()`.

**Step 3**: Find every place `_localPasswordToken(password)` is used for **writing/creating** a token. Replace with `_hashPassword(password)`.

**Step 4**: Find every place `_localPasswordToken(password)` is used for **comparing** (equality check). Replace with `_verifyPassword(password, storedToken)`.

Example — login comparison:
```dart
// BEFORE:
if (existingUser.accessToken != _localPasswordToken(password)) { ... }

// AFTER:
if (!_verifyPassword(password, existingUser.accessToken ?? '')) { ... }
```

**Step 5**: Add automatic migration from v1 to v2 on successful login. In the login success path, after verifying with `_verifyPassword`, check if the stored token is still v1 and upgrade it:

```dart
// After successful login verification:
if (existingUser.accessToken != null &&
    !existingUser.accessToken!.startsWith('v2:')) {
  // Migrate legacy token to v2 hash
  final newHash = _hashPassword(password);
  await _userRepo.updatePasswordHash(existingUser.id, newHash);
}
```

**Step 6**: Add `updatePasswordHash` to `UserRepository`:

```dart
Future<void> updatePasswordHash(String userId, String newHash) async {
  final db = await dbHelper.db;
  await db.update(
    'users',
    {'accessToken': newHash},
    where: 'id = ?',
    whereArgs: [userId],
  );
}
```

**Step 7**: Delete the old `_localPasswordToken` function entirely.

### Expected Output
- New offline accounts: `accessToken` stored as `v2:<salt>:<sha256hash>`
- Legacy accounts: on next login, token migrated from `local:base64...` to `v2:...`
- Wrong password still correctly rejected

### Edge Cases
- Do NOT apply this to Supabase-authenticated users — those accounts use Supabase JWT, not local tokens. Check: `existingUser.id.startsWith('local-')` distinguishes local accounts
- Users who never log in again keep legacy token — acceptable; they must log in to migrate
- `Random.secure()` can throw on some restricted environments — if that happens, fall back to `DateTime.now().microsecondsSinceEpoch` based salt (document this)

### Manual Test
1. Create a new offline account (register while airplane mode is on)
2. Check SQLite `users` table → `accessToken` must start with `v2:`
3. Logout → login again with correct password → succeeds
4. Logout → login with wrong password → fails with error message
5. (If you have a device with old v1 token) Login → check DB → token now starts with `v2:`

---

## TASK 0.3 — Secure Token Storage for Supabase JWT

**Risk**: MEDIUM
**Time**: 2h

### Problem
Supabase JWT `accessToken` is stored in SQLite plaintext in the `users` table. On a rooted/compromised device, SQLite files are readable.

### Package Required
`flutter_secure_storage: ^9.2.2`

Add to `pubspec.yaml`:
```yaml
dependencies:
  flutter_secure_storage: ^9.2.2
```

### Android Configuration Required
Add to `android/app/src/main/AndroidManifest.xml` inside `<application>`:
```xml
<application
  android:allowBackup="false"
  ...>
```
Setting `allowBackup="false"` prevents ADB backup from extracting secure storage.

### Files to Read (context)
- `lib/data/repositories/user_repository.dart` — full file
- `lib/features/auth/providers/auth_provider.dart` — full file
- `lib/main.dart` — full file

### Files to Modify
- `pubspec.yaml`
- `android/app/src/main/AndroidManifest.xml`
- `lib/data/repositories/user_repository.dart`

### New Files to Create
- `lib/services/auth/secure_token_store.dart`

### Step-by-Step Implementation

**Step 1**: Create `lib/services/auth/secure_token_store.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureTokenStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  static const _keyPrefix = 'auth_token_';
  static const _expiryPrefix = 'auth_expiry_';

  static Future<void> saveToken(String userId, String token, DateTime expiry) async {
    if (kIsWeb) return; // web: no secure storage — token kept only in memory
    await _storage.write(key: '$_keyPrefix$userId', value: token);
    await _storage.write(
      key: '$_expiryPrefix$userId',
      value: expiry.toIso8601String(),
    );
  }

  static Future<String?> getToken(String userId) async {
    if (kIsWeb) return null;
    return _storage.read(key: '$_keyPrefix$userId');
  }

  static Future<DateTime?> getExpiry(String userId) async {
    if (kIsWeb) return null;
    final raw = await _storage.read(key: '$_expiryPrefix$userId');
    return raw != null ? DateTime.tryParse(raw) : null;
  }

  static Future<void> deleteToken(String userId) async {
    if (kIsWeb) return;
    await _storage.delete(key: '$_keyPrefix$userId');
    await _storage.delete(key: '$_expiryPrefix$userId');
  }

  static Future<void> deleteAll() async {
    if (kIsWeb) return;
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(_keyPrefix) || key.startsWith(_expiryPrefix)) {
        await _storage.delete(key: key);
      }
    }
  }
}
```

**Step 2**: Modify `UserRepository.cacheToken`:

```dart
// BEFORE:
Future<void> cacheToken(String userId, String token, DateTime expiry) async {
  final db = await dbHelper.db;
  await db.update('users', {
    'accessToken': token,
    'tokenExpiry': expiry.millisecondsSinceEpoch,
  }, where: 'id = ?', whereArgs: [userId]);
}

// AFTER:
Future<void> cacheToken(String userId, String token, DateTime expiry) async {
  // Store token in secure storage, not SQLite
  await SecureTokenStore.saveToken(userId, token, expiry);
  // Keep only expiry in SQLite for quick validity checks
  final db = await dbHelper.db;
  await db.update(
    'users',
    {
      'accessToken': null, // never store token in SQLite
      'tokenExpiry': expiry.millisecondsSinceEpoch,
    },
    where: 'id = ?',
    whereArgs: [userId],
  );
}
```

**Step 3**: Modify `UserRepository.getCachedUser` and `getCachedUserByEmail`. After fetching user from SQLite, attach token from secure storage:

```dart
// After loading user from DB:
final token = await SecureTokenStore.getToken(user.id);
return user.copyWith(accessToken: token);
// Note: UserModel needs copyWith — verify it exists, add if not
```

**Step 4**: Modify `UserRepository.clearCachedTokens`:

```dart
Future<void> clearCachedTokens() async {
  await SecureTokenStore.deleteAll();
  final db = await dbHelper.db;
  await db.update('users', {'accessToken': null, 'tokenExpiry': null});
}
```

**Step 5**: One-time migration in `main.dart` after DB is initialized. Add this call before `runApp`:

```dart
// Migrate existing plaintext tokens to secure storage (run once)
await _migrateTokensToSecureStorage();
```

```dart
Future<void> _migrateTokensToSecureStorage() async {
  try {
    final db = await DatabaseHelper().db;
    final users = await db.query(
      'users',
      where: 'accessToken IS NOT NULL',
      columns: ['id', 'accessToken', 'tokenExpiry'],
    );
    for (final user in users) {
      final id = user['id'] as String;
      final token = user['accessToken'] as String;
      final expiryMs = user['tokenExpiry'] as int?;
      final expiry = expiryMs != null
          ? DateTime.fromMillisecondsSinceEpoch(expiryMs)
          : DateTime.now().add(const Duration(days: 30));
      await SecureTokenStore.saveToken(id, token, expiry);
      await db.update('users', {'accessToken': null}, where: 'id = ?', whereArgs: [id]);
    }
  } catch (e) {
    debugPrint('[SecureStorage migration] $e');
  }
}
```

### Expected Output
- SQLite `users.accessToken` column always NULL after migration
- Tokens stored in Android EncryptedSharedPreferences / iOS Keychain
- App reopen still works (token read from secure storage)
- Web platform gracefully skips secure storage

### Edge Cases
- Local offline accounts: their `accessToken` is a password hash (v2:salt:hash) — this IS intentionally in SQLite (it's a hash, not a credential). Only migrate tokens that do NOT start with `v2:` and do NOT start with `local:`
- Add that check to migration: `if (token.startsWith('v2:') || token.startsWith('local:')) continue;`

### Manual Test
1. Login online → open SQLite browser → `users.accessToken` = NULL
2. Kill app → reopen → still logged in
3. Logout → secure storage cleared → must login again
4. Old device with existing token → migration runs → token moves to secure storage, SQLite cleared

---

## TASK 0.4 — Verify No Secrets in Git History

**Risk**: MEDIUM
**Time**: 0.5h

### This is an audit task — no code changes

### Steps

Run these commands and report results:

```bash
# Check if supabase_config.dart was ever committed
git log --all --full-history -- lib/core/constants/supabase_config.dart

# Check if anon key appears anywhere in git history
git log --all -S 'sb_publishable' --oneline

# Check if Supabase URL appears in git history
git log --all -S 'kgucchapksiiqxmiutsz' --oneline

# Verify file is gitignored
git check-ignore -v lib/core/constants/supabase_config.dart
```

### If Any of the Above Returns Results

1. Rotate the Supabase anon key immediately via Supabase dashboard → Settings → API → Regenerate anon key
2. Update `supabase_config.dart` with new key
3. Use `git filter-repo` to scrub history (requires `pip install git-filter-repo`)
4. Force-push cleaned history (coordinate with team)

### Add Pre-Commit Protection

Create `.git/hooks/pre-commit`:
```bash
#!/bin/sh
if grep -r 'sb_publishable' lib/ 2>/dev/null; then
  echo "ERROR: Supabase key found in lib/. Commit blocked."
  exit 1
fi
```
```bash
chmod +x .git/hooks/pre-commit
```

### Expected Output
- Zero git history results for the secret strings
- Pre-commit hook in place
- `git check-ignore` confirms file is ignored

---

## Phase 0 Completion Checklist

Before moving to Phase 1, verify ALL of the following:

- [ ] Task 0.1: `dart analyze` passes, dashboard charts still work with filters
- [ ] Task 0.2: New accounts store `v2:` hashed tokens, login/logout cycle works
- [ ] Task 0.3: `users.accessToken` is NULL in SQLite, app still logs in after reopen
- [ ] Task 0.4: Zero git history hits for secret strings
- [ ] `flutter build apk --debug` compiles without errors
- [ ] `flutter build ios --debug` compiles without errors (or simulator)
