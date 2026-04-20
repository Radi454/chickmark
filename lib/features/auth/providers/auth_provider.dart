import 'dart:async';

import 'package:flutter/foundation.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/customer_repository.dart';
import '../../../data/repositories/flock_repository.dart';
import '../../../data/repositories/audit_repository.dart';
import '../../../data/repositories/bmk_repository.dart';
import '../../../data/repositories/photo_repository.dart';
import '../../../services/supabase/supabase_service.dart';

enum AuthState {
  unauthenticated,
  loading,
  authenticated,
  pendingApproval,
  error,
}

class AuthProvider extends ChangeNotifier {
  final UserRepository _userRepository = UserRepository();
  final SupabaseService _supabaseService = SupabaseService();

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

  Future<void> login(String email, String password) async {
    _setState(AuthState.loading);
    try {
      final result = await _supabaseService.signIn(email, password);
      if (result.success && result.user != null) {
        _user = result.user!;
        await _userRepository.upsertUser(_user!);
        if (!_user!.isApproved) {
          _setState(AuthState.pendingApproval);
        } else {
          _setState(AuthState.authenticated);
          unawaited(_syncFromSupabase());
        }
      } else {
        if (result.error == 'offline') {
          final cachedUser = await _userRepository.getCachedUserByEmail(email);
          if (cachedUser != null) {
            _user = cachedUser;
            _setState(AuthState.authenticated);
            return;
          }
          _setState(
            AuthState.error,
            error: 'Internet access is required to sign in on this device.',
          );
        } else {
          _setState(
            AuthState.error,
            error: _friendlyAuthError(result.error ?? 'Login failed'),
          );
        }
      }
    } catch (e) {
      _setState(AuthState.error, error: _friendlyAuthError(e.toString()));
    }
  }

  Future<void> _syncFromSupabase() async {
    try {
      final customerRepo = CustomerRepository();
      final flockRepo = FlockRepository();
      final auditRepo = AuditRepository();
      final bmkRepo = BmkRepository();
      final photoRepo = PhotoRepository();

      await _supabaseService.pullFromSupabase(
        upsertCustomer: (row) async {
          await customerRepo.upsertCustomer(row);
        },
        upsertFlock: (row) async {
          await flockRepo.upsertFlock(row);
        },
        upsertAudit: (row) async {
          await auditRepo.upsertAudit(row);
        },
        upsertPhoto: (row) async {
          await photoRepo.upsertPhoto(row);
        },
        upsertBmkBreed: (row) async {
          await bmkRepo.upsertBmkBreed(row);
        },
        upsertBmkEggBreakout: (row) async {
          await bmkRepo.upsertBmkEggBreakout(row);
        },
      );
    } catch (_) {}
  }

  Future<void> register(String fullName, String email, String password) async {
    _setState(AuthState.loading);
    try {
      final result = await _supabaseService.signUp(email, password, fullName);
      if (result.success && result.user != null) {
        _user = result.user!;
        await _userRepository.upsertUser(_user!);
        _setState(AuthState.pendingApproval);
      } else {
        _setState(
          AuthState.error,
          error: _friendlyAuthError(result.error ?? 'Registration failed'),
        );
      }
    } catch (e) {
      _setState(AuthState.error, error: _friendlyAuthError(e.toString()));
    }
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
        lower.contains('already exists')) {
      return 'An account with this email already exists.';
    }
    if (lower.contains('supabase credentials') ||
        lower.contains('not configured')) {
      return error;
    }
    if (lower.contains('password')) {
      return error;
    }
    return 'Something went wrong. Please try again.';
  }
}
