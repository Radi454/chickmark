import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
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

  AuthProvider({
    UserRepository? userRepository,
    ActivityLogRepository? activityLogRepository,
    SupabaseService? supabaseService,
  })  : _userRepository = userRepository ?? UserRepository(),
        _activityLogRepository =
            activityLogRepository ?? ActivityLogRepository(),
        _supabaseService = supabaseService ?? SupabaseService();

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
          final cachedUser = await _userRepository.getCachedUserByEmail(email);
          if (cachedUser != null) {
            _user = cachedUser;
            await _activityLogRepository.log(_user!.id, 'login');
            _setState(AuthState.authenticated);
            return true;
          }
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

  String _hashPassword(String password, {String? existingSalt}) {
    final salt = existingSalt ?? _generateSalt();
    final bytes = utf8.encode('$salt:$password');
    final digest = sha256.convert(bytes);
    return 'v2:$salt:${digest.toString()}';
  }

  @visibleForTesting
  String hashPasswordForTesting(String password) => _hashPassword(password);

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  bool _verifyPassword(String password, String? storedToken) {
    if (storedToken == null || storedToken.isEmpty) return false;
    if (storedToken.startsWith('v2:')) {
      final parts = storedToken.split(':');
      if (parts.length != 3) return false;
      final salt = parts[1];
      final expected = _hashPassword(password, existingSalt: salt);
      return expected == storedToken;
    }
    final legacy = 'local:${base64Url.encode(utf8.encode(password))}';
    return storedToken == legacy;
  }

  bool _isLegacyLocalToken(String? storedToken) {
    return storedToken != null && storedToken.startsWith('local:');
  }

  Future<void> logout() async {
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
}
