import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import '../../../core/security/security_policy.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/activity_log_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../services/supabase/supabase_service.dart';
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
  final Uuid _uuid = const Uuid();
  final bool _bypassAuth;

  AuthProvider({
    UserRepository? userRepository,
    ActivityLogRepository? activityLogRepository,
    SupabaseService? supabaseService,
    bool bypassAuth = false,
  }) : _userRepository = userRepository ?? UserRepository(),
       _activityLogRepository =
           activityLogRepository ?? ActivityLogRepository(),
       _supabaseService = supabaseService ?? SupabaseService(),
       _bypassAuth = bypassAuth && AuthSecurityPolicy.isDebugAuthBypassEnabled {
    if (_bypassAuth) {
      _activateDevelopmentUser();
    }
  }

  AuthState _state = AuthState.unauthenticated;
  String? _errorMessage;
  UserModel? _user;

  AuthState get state => _state;
  String? get errorMessage => _errorMessage;
  UserModel? get user => _user;

  void _setState(AuthState newState, {String? error}) {
    _state = newState;
    _errorMessage = error;
    notifyListeners();
  }

  Future<void> checkCachedToken() async {
    if (_bypassAuth) {
      _activateDevelopmentUser(notify: true);
      return;
    }

    _setState(AuthState.loading);
    try {
      final cachedUser = await _userRepository.getCachedUser();
      if (cachedUser != null) {
        _user = cachedUser;
        _setState(AuthState.authenticated);
      } else {
        _setState(AuthState.unauthenticated);
      }
    } catch (e) {
      _setState(AuthState.unauthenticated, error: e.toString());
    }
  }

  Future<bool> login(
    String email,
    String password, {
    bool rememberSession = true,
  }) async {
    _setState(AuthState.loading);
    try {
      final result = await _supabaseService.signIn(
        email,
        password,
        rememberSession: rememberSession,
      );
      if (result.success && result.user != null) {
        _user = result.user!;
        await _userRepository.upsertUser(_user!);
        await _activityLogRepository.log(_user!.id, 'login');
        if (!_user!.isApproved) {
          _setState(AuthState.pendingApproval);
        } else {
          _setState(AuthState.authenticated);
        }
        return true;
      } else {
        if (result.error == 'offline') {
          if (await _tryLocalLogin(email, password)) {
            return true;
          }
          _setState(
            AuthState.error,
            error: 'Internet access is required to sign in on this device.',
          );
        } else {
          if (await _tryLocalLogin(email, password)) {
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
      _activateDevelopmentUser(notify: true);
      return;
    }

    _setState(AuthState.loading);
    try {
      await _supabaseService.signOut();
      await _userRepository.clearCachedTokens();
      _user = null;
      _setState(AuthState.unauthenticated);
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
      return 'The email or password is incorrect.';
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
