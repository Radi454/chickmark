import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import '../../../core/auth/customer_account_identifier.dart';
import '../../../core/security/security_policy.dart';
import '../../../data/models/user_model.dart';
import '../../../core/security/safe_debug_log.dart';
import '../../../data/repositories/activity_log_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../services/supabase/supabase_service.dart';
import '../../../services/auth/session_trust_store.dart';
import '../services/startup_auth_decision.dart';
import 'package:uuid/uuid.dart';

enum AuthState {
  unauthenticated,
  loading,
  authenticated,
  pendingApproval,
  error,
}

class AuthProvider extends ChangeNotifier {
  final UserRepository _userRepository;
  final ActivityLogRepository _activityLogRepository;
  final SupabaseService _supabaseService;
  final SessionTrustStore _sessionTrustStore;
  final Uuid _uuid = const Uuid();
  final bool _bypassAuth;
  bool _debugBypassSignedOut = false;

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

  AuthState _state = AuthState.unauthenticated;
  String? _errorMessage;
  UserModel? _user;
  bool _isPendingRevalidation = false;
  bool _revalidationInFlight = false;

  /// Monotonic counter identifying the current sign-in "generation".
  ///
  /// Bumped by every event that invalidates in-flight session work — a login,
  /// a logout, or any local sign-out commit. Long-running work captures the
  /// epoch it started under and re-checks it around every await, so a write
  /// belonging to a session that has since been signed out can never land
  /// afterwards and silently resurrect it.
  int _sessionEpoch = 0;

  AuthState get state => _state;
  String? get errorMessage => _errorMessage;
  UserModel? get user => _user;

  /// True when the app is running on a previously-proven login that has not
  /// yet been re-checked against the server. Local work is unaffected.
  bool get isPendingRevalidation => _isPendingRevalidation;

  void _setState(AuthState newState, {String? error}) {
    _state = newState;
    _errorMessage = error;
    notifyListeners();
  }

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

    final epoch = _sessionEpoch;
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

      // A live Supabase session for a *different* account than the one this
      // device most recently remembered is never proof for `remembered`.
      // Grant nothing and cache nothing under a mismatched identity — this
      // needs real credentials, not a trip through the grace logic below.
      if (restore?.userId != null && restore!.userId != remembered.id) {
        safeDebugLog(
          'checkCachedToken: restored session user (${restore.userId}) does '
          'not match the remembered user (${remembered.id}); requiring '
          'fresh credentials.',
        );
        _user = null;
        _isPendingRevalidation = false;
        _setState(AuthState.unauthenticated);
        return;
      }

      Duration? sinceLastVerified;
      if (!isLocalAccount) {
        final lookup = await _readTrustSafely();
        if (lookup.readFailed) {
          // A storage fault is not proof this device never verified — a
          // Keychain hiccup at boot must not sign a proven user out. Grant
          // the same benefit of the doubt as "verified moments ago"; the
          // next successful revalidateSession() call confirms for real.
          sinceLastVerified = Duration.zero;
        } else if (lookup.trust != null) {
          if (lookup.trust!.userId == remembered.id) {
            sinceLastVerified = DateTime.now().difference(
              lookup.trust!.lastVerifiedAt,
            );
          } else {
            // The trust record proves a different account, not this one —
            // never lend this user someone else's grace window.
            safeDebugLog(
              'checkCachedToken: trust record belongs to '
              '${lookup.trust!.userId}, not the remembered user '
              '(${remembered.id}); ignoring it.',
            );
          }
        } else if (remembered.lastLoginAt != null) {
          // Upgrade backfill — distinct from the read-fault path above: the
          // store answered, and it genuinely holds nothing. On an install
          // that was already signed in before trust records existed there is
          // no record to find, and without this an offline first launch after
          // the upgrade would sign the entire existing user base out once.
          //
          // This cannot let an install that never authenticated through:
          // `getRememberedUser()` only returns a non-local user when a token
          // for it is present in secure storage, which is itself evidence of
          // a prior successful online login on this device. `lastLoginAt` is
          // when that login happened, so it is the honest seed for the grace
          // window — an install past the window still goes to /login.
          sinceLastVerified = DateTime.now().difference(
            remembered.lastLoginAt!,
          );
        }
      }

      final decision = decideStartupAuth(
        hasRememberedUser: true,
        isLocalAccount: isLocalAccount,
        localTokenValid: remembered.isTokenValid,
        sessionStatus: restore?.status,
        sinceLastVerified: sinceLastVerified,
      );

      await _applyStartupDecision(decision, remembered, restore, epoch);
    } catch (e) {
      // A failure to *ask* is never a logout. Every failure-prone step past
      // `remembered` (trust lookup, token persistence) is handled as
      // best-effort above and can no longer throw, so anything still
      // reaching this catch means we never even established whether a
      // proven user exists — unauthenticated is the only safe fallback.
      _isPendingRevalidation = false;
      _setState(AuthState.unauthenticated, error: e.toString());
    }
  }

  /// Reads the trust record without letting a platform-storage fault (e.g. a
  /// locked-device Keychain error at boot) look identical to "no trust was
  /// ever recorded" — the two must be handled differently by the caller.
  Future<({SessionTrust? trust, bool readFailed})> _readTrustSafely() async {
    try {
      return (trust: await _sessionTrustStore.read(), readFailed: false);
    } catch (e) {
      safeDebugLog('Session trust read failed', error: e);
      return (trust: null, readFailed: true);
    }
  }

  Future<void> _applyStartupDecision(
    StartupAuthDecision decision,
    UserModel remembered,
    SessionRestoreResult? restore,
    int epoch,
  ) async {
    switch (decision) {
      case StartupAuthDecision.goToLogin:
        _commitSignedOut();
        if (restore?.status == SessionRestoreStatus.rejected) {
          // A definitive server rejection while online is a real logout.
          await _clearSessionArtifactsBestEffort();
        }
      case StartupAuthDecision.enterApp:
        await _persistVerifiedSession(remembered, restore, epoch);
        // A logout that landed while the startup check was in flight wins:
        // never re-seat a user the app has since signed out.
        if (_sessionEpoch != epoch) return;
        _user = remembered;
        _isPendingRevalidation = false;
        _setState(
          remembered.isApproved
              ? AuthState.authenticated
              : AuthState.pendingApproval,
        );
      case StartupAuthDecision.enterAppPendingRevalidation:
        if (_sessionEpoch != epoch) return;
        _user = remembered;
        _isPendingRevalidation = true;
        _setState(
          remembered.isApproved
              ? AuthState.authenticated
              : AuthState.pendingApproval,
        );
    }
  }

  /// Persists a server-confirmed session locally. Best-effort: the server
  /// has already vouched for this session, so a local storage fault here
  /// (Keychain write failure, disk error) must never undo that and send an
  /// offline-capable, already-approved user back to the login screen.
  ///
  /// [epoch] is the sign-in generation this persist belongs to. Every write
  /// is gated on it still being current, and if a sign-out overtook us
  /// mid-write the artifacts are cleared again — no write may outlive the
  /// session that authorised it, or the next cold start would come back as a
  /// user who has already been signed out.
  Future<void> _persistVerifiedSession(
    UserModel user,
    SessionRestoreResult? restore,
    int epoch,
  ) async {
    if (restore == null) return;
    final accessToken = restore.accessToken;
    final expiresAt = restore.expiresAt;
    if (accessToken != null && expiresAt != null && _sessionEpoch == epoch) {
      try {
        await _userRepository.cacheToken(user.id, accessToken, expiresAt);
      } catch (e) {
        safeDebugLog('Failed to cache refreshed access token', error: e);
      }
    }
    if (_sessionEpoch == epoch) {
      await _recordTrustBestEffort(user.id);
      return;
    }
    // The epoch moved while we were writing. If that was a sign-out (nobody
    // is signed in now), undo anything that may have landed after it. If a
    // *different* sign-in took over instead, leave its own freshly written
    // artifacts alone — clearing them would be the very logout this whole
    // feature exists to prevent.
    if (_user == null) {
      safeDebugLog(
        'Discarding session artifacts persisted after a concurrent sign-out.',
      );
      await _clearSessionArtifactsBestEffort();
    }
  }

  void _commitSignedOut() {
    _sessionEpoch++;
    _user = null;
    _isPendingRevalidation = false;
    _setState(AuthState.unauthenticated);
  }

  Future<void> _signOutLocally() async {
    _commitSignedOut();
    await _clearSessionArtifactsBestEffort();
  }

  Future<void> _clearSessionArtifactsBestEffort() async {
    await _clearTrustBestEffort();
    try {
      await _userRepository.clearCachedTokens();
    } catch (e) {
      safeDebugLog('Failed to clear cached tokens', error: e);
    }
  }

  Future<void> _clearTrustBestEffort() async {
    try {
      await _sessionTrustStore.clear();
    } catch (e) {
      safeDebugLog('Failed to clear session trust', error: e);
    }
  }

  Future<void> _recordTrustBestEffort(String userId) async {
    try {
      await _sessionTrustStore.record(userId, DateTime.now());
    } catch (e) {
      safeDebugLog('Failed to record session trust', error: e);
    }
  }

  /// Re-check a pending session once the network is back. Safe to call
  /// often — including overlapping app-resume and connectivity events —
  /// because it is re-entrancy guarded, re-checks that this is still the
  /// pending session after every await, and is a no-op unless the app is
  /// actually running on offline grace. Never throws: any failure is logged
  /// and treated the same as "still offline, try again later," so it can
  /// never escape as an uncaught error into an event handler.
  Future<void> revalidateSession() async {
    if (_bypassAuth || !_isPendingRevalidation || _revalidationInFlight) {
      return;
    }
    final user = _user;
    if (user == null || user.id.startsWith('local-')) return;

    _revalidationInFlight = true;
    final epoch = _sessionEpoch;
    try {
      final restore = await _supabaseService.restoreSession();

      // The world may have moved on while we awaited a server round trip —
      // a login, a logout, or another revalidation may already have
      // resolved this session. Only act if it is still exactly the pending
      // session we set out to check.
      if (!identical(_user, user) ||
          !_isPendingRevalidation ||
          _sessionEpoch != epoch) {
        return;
      }

      switch (restore.status) {
        case SessionRestoreStatus.valid:
        case SessionRestoreStatus.refreshed:
          if (restore.userId != null && restore.userId != user.id) {
            // The live Supabase session belongs to a different account than
            // the one pending revalidation. Never grant it that account's
            // access or cache a token under its id.
            safeDebugLog(
              'revalidateSession: restored session user (${restore.userId}) '
              'does not match the pending user (${user.id}); signing out.',
            );
            await _signOutLocally();
            return;
          }
          await _persistVerifiedSession(user, restore, epoch);
          if (identical(_user, user) &&
              _isPendingRevalidation &&
              _sessionEpoch == epoch) {
            _isPendingRevalidation = false;
            notifyListeners();
          }
        case SessionRestoreStatus.rejected:
          await _signOutLocally();
        case SessionRestoreStatus.offline:
          // Still no network. Stay signed in and try again later.
          break;
      }
    } catch (e) {
      safeDebugLog('revalidateSession failed', error: e);
    } finally {
      _revalidationInFlight = false;
    }
  }

  Future<bool> login(
    String email,
    String password, {
    bool rememberSession = true,
  }) async {
    // A new sign-in supersedes anything the previous session still had in
    // flight; bump before the first await so those writes can see it.
    final epoch = ++_sessionEpoch;
    _setState(AuthState.loading);
    try {
      final loginEmail = CustomerAccountIdentifier.loginEmail(email);
      final result = await _supabaseService.signIn(
        loginEmail,
        password,
        rememberSession: rememberSession,
      );
      // A logout (or another login) that landed while we were awaiting the
      // server has already decided who this device is. Do not overwrite it.
      if (_sessionEpoch != epoch) {
        safeDebugLog('login: superseded while awaiting the server; discarding.');
        return false;
      }
      if (result.success && result.user != null) {
        // Held locally until every write is done: assigning `_user` early
        // would let a sign-out landing mid-write be silently overwritten.
        final signedIn = result.user!;
        await _userRepository.upsertUser(signedIn);
        if (rememberSession && !signedIn.id.startsWith('local-')) {
          // Best-effort: the sign-in already succeeded, so a Keychain fault
          // recording trust must not turn it into a failed login.
          await _recordTrustBestEffort(signedIn.id);
        }
        await _activityLogRepository.log(signedIn.id, 'login');
        if (_sessionEpoch != epoch) {
          safeDebugLog('login: superseded mid-write; discarding.');
          return false;
        }
        _user = signedIn;
        _isPendingRevalidation = false;
        if (!_user!.isApproved) {
          _setState(AuthState.pendingApproval);
        } else {
          _setState(AuthState.authenticated);
        }
        return true;
      } else {
        if (result.error == 'offline') {
          if (await _tryLocalLogin(loginEmail, password)) {
            return true;
          }
          _setState(
            AuthState.error,
            error: 'Internet access is required to sign in on this device.',
          );
        } else {
          if (await _tryLocalLogin(loginEmail, password)) {
            return true;
          }
          _setState(
            AuthState.error,
            error: _friendlyAuthError(result.error ?? 'Login failed'),
          );
        }
      }
    } catch (e) {
      _setState(AuthState.error, error: _friendlyAuthError(e.toString()));
    }
    return false;
  }

  Future<bool> register(String fullName, String email, String password) async {
    _setState(AuthState.loading);
    try {
      final result = await _supabaseService.signUp(email, password, fullName);
      if (result.success && result.user != null) {
        _user = result.user!;
        await _userRepository.upsertUser(_user!);
        _setState(AuthState.unauthenticated);
        return true;
      } else {
        _setState(
          AuthState.error,
          error: _friendlyAuthError(result.error ?? 'Registration failed'),
        );
      }
    } catch (e) {
      _setState(AuthState.error, error: _friendlyAuthError(e.toString()));
    }
    return false;
  }

  Future<bool> registerLocalFallback(
    String fullName,
    String email, {
    required String password,
    String? remoteError,
  }) async {
    if (!AuthSecurityPolicy.isLocalFallbackAuthEnabled) {
      _setState(
        AuthState.error,
        error:
            'Local account fallback is disabled for this build. Internet access is required to create an account.',
      );
      return false;
    }
    try {
      final existingUser = await _userRepository.getUserByEmail(email);
      if (existingUser != null) {
        if (existingUser.id.startsWith('local-') &&
            !_verifyPassword(password, existingUser.accessToken)) {
          _setState(
            AuthState.error,
            error:
                'An account with this email exists locally, but the password does not match.',
          );
          return false;
        }
        if (existingUser.id.startsWith('local-') &&
            _isLegacyLocalToken(existingUser.accessToken)) {
          await _userRepository.updatePasswordHash(
            existingUser.id,
            _hashPassword(password),
          );
        }
        _user = existingUser;
        _setState(AuthState.unauthenticated);
        return true;
      }

      final now = DateTime.now();
      final user = UserModel(
        id: 'local-${_uuid.v4()}',
        fullName: fullName,
        email: email,
        role: 'auditor',
        status: 'approved',
        accessToken: _hashPassword(password),
        tokenExpiry: now.add(const Duration(days: 30)),
        createdAt: now,
        lastLoginAt: now,
      );
      _user = user;
      await _userRepository.upsertUser(user);
      _setState(
        AuthState.unauthenticated,
        error: remoteError == null
            ? null
            : 'Supabase signup failed, so a local account was created. $remoteError',
      );
      return true;
    } catch (e) {
      _setState(AuthState.error, error: _friendlyAuthError(e.toString()));
      return false;
    }
  }

  Future<bool> _tryLocalLogin(String email, String password) async {
    if (!AuthSecurityPolicy.isLocalFallbackAuthEnabled) {
      return false;
    }
    final localUser = await _userRepository.getUserByEmail(email);
    if (localUser == null || !localUser.id.startsWith('local-')) {
      return false;
    }
    final storedToken = localUser.accessToken;
    if (!localUser.isApproved || !_verifyPassword(password, storedToken)) {
      return false;
    }
    final expiresAt = DateTime.now().add(const Duration(days: 30));
    var activeToken = storedToken;
    if (_isLegacyLocalToken(storedToken)) {
      activeToken = _hashPassword(password);
      await _userRepository.updatePasswordHash(localUser.id, activeToken);
    }
    await _userRepository.cacheToken(localUser.id, activeToken!, expiresAt);
    _user = await _userRepository.getUserByEmail(email);
    if (_user != null) {
      await _activityLogRepository.log(_user!.id, 'login');
    }
    _setState(AuthState.authenticated);
    return true;
  }

  static const String _passwordKdfAlgorithm = 'pbkdf2-sha256';
  static const int _passwordKdfIterations = 210000;
  static const int _passwordKdfKeyLength = 32;
  static const int _sha256DigestLength = 32;

  String _hashPassword(
    String password, {
    String? existingSalt,
    int? iterations,
  }) {
    final salt = existingSalt ?? _generateSalt();
    final rounds = iterations ?? _passwordKdfIterations;
    if (rounds < 1000) {
      throw ArgumentError.value(rounds, 'iterations', 'must be at least 1000');
    }
    final derivedKey = _pbkdf2HmacSha256(
      password: utf8.encode(password),
      salt: _decodeBase64Url(salt),
      iterations: rounds,
      keyLength: _passwordKdfKeyLength,
    );
    return 'v3:$_passwordKdfAlgorithm:$rounds:$salt:${_encodeBase64Url(derivedKey)}';
  }

  @visibleForTesting
  String hashPasswordForTesting(String password, {int? iterations}) =>
      _hashPassword(password, iterations: iterations);

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return _encodeBase64Url(bytes);
  }

  bool _verifyPassword(String password, String? storedToken) {
    if (storedToken == null || storedToken.isEmpty) return false;
    if (storedToken.startsWith('v3:')) {
      final parts = storedToken.split(':');
      if (parts.length != 5 || parts[1] != _passwordKdfAlgorithm) {
        return false;
      }
      final iterations = int.tryParse(parts[2]);
      if (iterations == null || iterations < 1000) return false;
      final salt = parts[3];
      final String expected;
      try {
        expected = _hashPassword(
          password,
          existingSalt: salt,
          iterations: iterations,
        );
      } catch (_) {
        return false;
      }
      return _constantTimeEquals(expected, storedToken);
    }
    if (storedToken.startsWith('v2:')) {
      final parts = storedToken.split(':');
      if (parts.length != 3) return false;
      final salt = parts[1];
      final expected = _legacySha256PasswordHash(password, salt);
      return _constantTimeEquals(expected, storedToken);
    }
    final legacy = 'local:${base64Url.encode(utf8.encode(password))}';
    return _constantTimeEquals(legacy, storedToken);
  }

  bool _isLegacyLocalToken(String? storedToken) {
    return storedToken != null &&
        (storedToken.startsWith('local:') || storedToken.startsWith('v2:'));
  }

  String _legacySha256PasswordHash(String password, String salt) {
    final bytes = utf8.encode('$salt:$password');
    final digest = sha256.convert(bytes);
    return 'v2:$salt:${digest.toString()}';
  }

  List<int> _pbkdf2HmacSha256({
    required List<int> password,
    required List<int> salt,
    required int iterations,
    required int keyLength,
  }) {
    final hmac = Hmac(sha256, password);
    final blockCount =
        (keyLength + _sha256DigestLength - 1) ~/ _sha256DigestLength;
    final derivedKey = <int>[];

    for (var blockIndex = 1; blockIndex <= blockCount; blockIndex++) {
      var u = hmac.convert([...salt, ..._int32BigEndian(blockIndex)]).bytes;
      final block = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < block.length; j++) {
          block[j] ^= u[j];
        }
      }
      derivedKey.addAll(block);
    }

    return derivedKey.take(keyLength).toList();
  }

  List<int> _int32BigEndian(int value) {
    return [
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ];
  }

  String _encodeBase64Url(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  List<int> _decodeBase64Url(String value) {
    final padding = (4 - value.length % 4) % 4;
    return base64Url.decode(value + ('=' * padding));
  }

  bool _constantTimeEquals(String a, String b) {
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);
    var difference = aBytes.length ^ bBytes.length;
    final maxLength = aBytes.length > bBytes.length
        ? aBytes.length
        : bBytes.length;
    for (var i = 0; i < maxLength; i++) {
      final aByte = i < aBytes.length ? aBytes[i] : 0;
      final bByte = i < bBytes.length ? bBytes[i] : 0;
      difference |= aByte ^ bByte;
    }
    return difference == 0;
  }

  Future<void> logout() async {
    if (_bypassAuth) {
      _debugBypassSignedOut = true;
      _user = null;
      _setState(AuthState.unauthenticated);
      return;
    }

    // Invalidate every in-flight session write *before* the first await:
    // a revalidation already past its own identity check must not be able to
    // re-persist a token or trust record behind this logout.
    _sessionEpoch++;
    _setState(AuthState.loading);
    try {
      await _supabaseService.signOut();
      // Commit the local sign-out state first — a Keychain fault clearing
      // trust or cached tokens must never strand this device signed in.
      await _signOutLocally();
    } catch (e) {
      _setState(AuthState.error, error: _friendlyAuthError(e.toString()));
    }
  }

  String _friendlyAuthError(String error) {
    final lower = error.toLowerCase();
    if (lower == 'offline' ||
        lower.contains('socket') ||
        lower.contains('network') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection')) {
      return 'Internet access is required to sign in on this device.';
    }
    if (lower.contains('invalid login credentials')) {
      return 'The username/email or password is incorrect.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Please confirm your email before signing in.';
    }
    if (lower.contains('already registered') ||
        lower.contains('already exists') ||
        lower.contains('user already registered')) {
      return 'An account with this email already exists.';
    }
    if (lower.contains('signup') && lower.contains('disabled')) {
      return 'Account creation is disabled in Supabase. Enable signups to create new accounts.';
    }
    if (lower.contains('database error') && lower.contains('saving new user')) {
      return 'Account creation is blocked by a Supabase database trigger or policy.';
    }
    if (lower.contains('unexpected_failure')) {
      return 'Supabase returned unexpected_failure. Check Auth settings, email confirmation, and database triggers for new users.';
    }
    if (lower.contains('account creation failed')) {
      return error;
    }
    if (lower.contains('supabase credentials') ||
        lower.contains('not configured')) {
      return error;
    }
    if (lower.contains('password')) {
      return error;
    }
    return error.replaceFirst(RegExp(r'^(Exception|Error):\s*'), '');
  }

  void _activateDevelopmentUser({bool notify = false}) {
    final now = DateTime.now();
    _user = UserModel(
      id: 'local-development-auditor',
      fullName: 'Development Auditor',
      email: 'dev-auditor@chickmark.local',
      role: 'auditor',
      status: 'approved',
      tokenExpiry: now.add(const Duration(days: 365)),
      createdAt: now,
      lastLoginAt: now,
    );
    if (notify) {
      _setState(AuthState.authenticated);
    } else {
      _state = AuthState.authenticated;
      _errorMessage = null;
    }
  }
}
