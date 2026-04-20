import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/supabase_config.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/user_repository.dart';

class AuthResult {
  final bool success;
  final String? error;
  final UserModel? user;

  AuthResult({required this.success, this.error, this.user});
}

class SupabaseService {
  final _userRepo = UserRepository();

  SupabaseClient get _client => Supabase.instance.client;

  bool get isAvailable => SupabaseConfig.isConfigured && _isNetworkAvailable;
  bool get isConfigured => SupabaseConfig.isConfigured;

  bool _isNetworkAvailable = true;

  SupabaseService() {
    _checkNetworkAvailability();
  }

  Future<void> _checkNetworkAvailability() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    _isNetworkAvailable = !connectivityResult.contains(ConnectivityResult.none);
  }

  Future<AuthResult> signIn(String email, String password) async {
    try {
      await _checkNetworkAvailability();
      if (!SupabaseConfig.isConfigured) {
        return AuthResult(
          success: false,
          error:
              'Supabase credentials are not configured. Run the app with --dart-define-from-file=.env.',
        );
      }
      if (!_isNetworkAvailable) {
        return AuthResult(success: false, error: 'offline');
      }

      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final supabaseUser = response.user;
      final session = response.session;
      if (supabaseUser == null || session == null) {
        return AuthResult(success: false, error: 'Sign-in failed');
      }

      final profile = await _fetchUserProfile(supabaseUser.id);
      final tokenExpiry = _sessionExpiry(session);
      final user = _buildUserFromAuth(
        supabaseUser,
        fallbackEmail: email,
        profile: profile,
        accessToken: session.accessToken,
        tokenExpiry: tokenExpiry,
      );

      await _userRepo.upsertUser(user);
      await _userRepo.cacheToken(user.id, session.accessToken, tokenExpiry);

      return AuthResult(success: true, user: user);
    } on AuthException catch (e) {
      return AuthResult(success: false, error: e.message);
    } catch (e) {
      debugPrint('Supabase sign-in failed: $e');
      return AuthResult(success: false, error: 'offline');
    }
  }

  Future<AuthResult> signUp(
    String email,
    String password,
    String fullName,
  ) async {
    try {
      await _checkNetworkAvailability();
      if (!SupabaseConfig.isConfigured) {
        return AuthResult(
          success: false,
          error:
              'Supabase credentials are not configured. Run the app with --dart-define-from-file=.env.',
        );
      }
      if (!_isNetworkAvailable) {
        return AuthResult(success: false, error: 'offline');
      }

      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName, 'status': 'pending', 'role': 'auditor'},
      );

      final supabaseUser = response.user;
      if (supabaseUser == null) {
        return AuthResult(success: false, error: 'Sign-up failed');
      }

      await _createPendingProfile(
        userId: supabaseUser.id,
        fullName: fullName,
        email: supabaseUser.email ?? email,
      );

      final user = UserModel(
        id: supabaseUser.id,
        fullName: fullName,
        email: email,
        role: 'auditor',
        status: 'pending',
        createdAt: DateTime.now(),
      );

      await _userRepo.upsertUser(user);

      return AuthResult(success: true, user: user);
    } on AuthException catch (e) {
      return AuthResult(success: false, error: e.message);
    } catch (e) {
      debugPrint('Supabase sign-up failed: $e');
      return AuthResult(success: false, error: 'offline');
    }
  }

  Future<bool> sendPasswordReset(String email) async {
    try {
      await _checkNetworkAvailability();
      if (!isAvailable) return false;
      await _client.auth.resetPasswordForEmail(email);
      return true;
    } on AuthException {
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _checkNetworkAvailability();
      if (!isAvailable) return;
      await _client.auth.signOut();
    } catch (_) {}
  }

  Future<void> syncAudit(Map<String, dynamic> audit) async {
    try {
      await _checkNetworkAvailability();
      if (!isAvailable) return;
      await _upsertWithFallback('audits', audit);
    } catch (e) {
      debugPrint('Supabase audit sync failed: $e');
    }
  }

  Future<void> syncCustomer(Map<String, dynamic> customer) async {
    try {
      await _checkNetworkAvailability();
      if (!isAvailable) return;
      await _upsertWithFallback('customers', customer);
    } catch (e) {
      debugPrint('Supabase customer sync failed: $e');
    }
  }

  Future<void> syncFlock(Map<String, dynamic> flock) async {
    try {
      await _checkNetworkAvailability();
      if (!isAvailable) return;
      await _upsertWithFallback('flocks', flock);
    } catch (e) {
      debugPrint('Supabase flock sync failed: $e');
    }
  }

  Future<void> syncUpdateFlock(Map<String, dynamic> flock) async {
    try {
      await _checkNetworkAvailability();
      if (!isAvailable) return;
      await _upsertWithFallback('flocks', flock);
    } catch (e) {
      debugPrint('Supabase flock update sync failed: $e');
    }
  }

  Future<void> syncDeleteFlock(String id) async {
    try {
      await _checkNetworkAvailability();
      if (!isAvailable) return;
      await _client.from('flocks').delete().eq('id', id);
    } catch (e) {
      debugPrint('Supabase flock delete sync failed: $e');
    }
  }

  Future<void> pullFromSupabase({
    required Future<void> Function(Map<String, dynamic>) upsertCustomer,
    required Future<void> Function(Map<String, dynamic>) upsertFlock,
    required Future<void> Function(Map<String, dynamic>) upsertAudit,
    Future<void> Function(Map<String, dynamic>)? upsertPhoto,
    Future<void> Function(Map<String, dynamic>)? upsertBmkBreed,
    Future<void> Function(Map<String, dynamic>)? upsertBmkEggBreakout,
  }) async {
    try {
      await _checkNetworkAvailability();
      if (!isAvailable) return;
      final customers = await _client.from('customers').select();
      debugPrint('Supabase pull: ${customers.length} customers');
      for (final row in customers) {
        await upsertCustomer(Map<String, dynamic>.from(row));
      }
      final flocks = await _client.from('flocks').select();
      debugPrint('Supabase pull: ${flocks.length} flocks');
      for (final row in flocks) {
        await upsertFlock(Map<String, dynamic>.from(row));
      }
      final audits = await _client.from('audits').select();
      debugPrint('Supabase pull: ${audits.length} audits');
      for (final row in audits) {
        await upsertAudit(Map<String, dynamic>.from(row));
      }
      if (upsertPhoto != null) {
        try {
          final photos = await _client.from('photos').select();
          debugPrint('Supabase pull: ${photos.length} photos');
          for (final row in photos) {
            await upsertPhoto(Map<String, dynamic>.from(row));
          }
        } catch (e) {
          debugPrint('Supabase photo pull skipped: $e');
        }
      }
      if (upsertBmkBreed != null) {
        try {
          final breeds = await _client.from('bmk_breeds').select();
          debugPrint('Supabase pull: ${breeds.length} BMK breed rows');
          for (final row in breeds) {
            await upsertBmkBreed(Map<String, dynamic>.from(row));
          }
        } catch (e) {
          debugPrint('Supabase BMK breed pull skipped: $e');
        }
      }
      if (upsertBmkEggBreakout != null) {
        try {
          final breakout = await _client.from('bmk_egg_breakout').select();
          debugPrint('Supabase pull: ${breakout.length} BMK egg breakout rows');
          for (final row in breakout) {
            await upsertBmkEggBreakout(Map<String, dynamic>.from(row));
          }
        } catch (e) {
          debugPrint('Supabase BMK egg breakout pull skipped: $e');
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Supabase pull failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _upsertWithFallback(
    String table,
    Map<String, dynamic> row,
  ) async {
    try {
      await _client.from(table).upsert(_snakeCaseKeys(row));
    } catch (_) {
      await _client.from(table).upsert(row);
    }
  }

  Map<String, dynamic> _snakeCaseKeys(Map<String, dynamic> row) {
    return row.map((key, value) => MapEntry(_snakeCase(key), value));
  }

  String _snakeCase(String key) {
    final buffer = StringBuffer();
    for (var i = 0; i < key.length; i++) {
      final char = key[i];
      final isUpper = char.toUpperCase() == char && char.toLowerCase() != char;
      if (isUpper && i > 0) buffer.write('_');
      buffer.write(char.toLowerCase());
    }
    return buffer.toString();
  }

  Future<Map<String, dynamic>?> _fetchUserProfile(String userId) async {
    try {
      final rows = await _client
          .from('users')
          .select()
          .eq('id', userId)
          .limit(1);
      if (rows.isEmpty) return null;
      return Map<String, dynamic>.from(rows.first);
    } catch (e) {
      debugPrint('Supabase user profile fetch skipped: $e');
      return null;
    }
  }

  Future<void> _createPendingProfile({
    required String userId,
    required String fullName,
    required String email,
  }) async {
    try {
      await _client.from('users').upsert({
        'id': userId,
        'full_name': fullName,
        'email': email,
        'role': 'auditor',
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Supabase pending profile upsert skipped: $e');
    }
  }

  UserModel _buildUserFromAuth(
    User supabaseUser, {
    required String fallbackEmail,
    required Map<String, dynamic>? profile,
    required String accessToken,
    required DateTime tokenExpiry,
  }) {
    final meta = supabaseUser.userMetadata ?? {};
    final normalizedProfile = _normalizeProfile(profile ?? const {});

    final fullName =
        normalizedProfile['fullName'] as String? ??
        meta['full_name'] as String? ??
        meta['fullName'] as String? ??
        supabaseUser.email ??
        fallbackEmail;
    final email =
        normalizedProfile['email'] as String? ??
        supabaseUser.email ??
        fallbackEmail;
    final role =
        normalizedProfile['role'] as String? ??
        meta['role'] as String? ??
        'auditor';
    final status =
        normalizedProfile['status'] as String? ??
        meta['status'] as String? ??
        'pending';
    final customerId =
        normalizedProfile['customerId'] as String? ??
        meta['customer_id'] as String? ??
        meta['customerId'] as String?;
    final createdAt = _parseDate(
      normalizedProfile['createdAt'],
      fallback: DateTime.parse(supabaseUser.createdAt),
    );

    return UserModel(
      id: supabaseUser.id,
      fullName: fullName,
      email: email,
      role: role,
      status: status,
      customerId: customerId,
      accessToken: accessToken,
      tokenExpiry: tokenExpiry,
      createdAt: createdAt,
      lastLoginAt: DateTime.now(),
    );
  }

  DateTime _sessionExpiry(Session session) {
    final expiresAt = session.expiresAt;
    if (expiresAt != null) {
      return DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
    }
    return DateTime.now().add(Duration(seconds: session.expiresIn ?? 3600));
  }

  Map<String, dynamic> _normalizeProfile(Map<String, dynamic> profile) {
    return profile.map((key, value) => MapEntry(_camelize(key), value));
  }

  String _camelize(String key) {
    if (!key.contains('_')) return key;
    final parts = key.split('_');
    return parts.first +
        parts.skip(1).map((part) {
          if (part.isEmpty) return part;
          return part[0].toUpperCase() + part.substring(1);
        }).join();
  }

  DateTime _parseDate(Object? value, {required DateTime fallback}) {
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value) ?? fallback;
    }
    return fallback;
  }
}
