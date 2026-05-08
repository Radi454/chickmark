import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/supabase_config.dart';
import '../../data/models/photo_model.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/user_repository.dart';

class AuthResult {
  final bool success;
  final String? error;
  final UserModel? user;

  AuthResult({required this.success, this.error, this.user});
}

class SupabasePullSummary {
  final int customers;
  final int flocks;
  final int hatcheries;
  final int audits;
  final int auditSessions;
  final int photos;
  final int bmkBreeds;
  final int bmkEggBreakout;
  final int temperatureSessions;
  final int temperatureReadings;
  final int goveeDailyCaptures;
  final int goveePlaceReadings;

  const SupabasePullSummary({
    this.customers = 0,
    this.flocks = 0,
    this.hatcheries = 0,
    this.audits = 0,
    this.auditSessions = 0,
    this.photos = 0,
    this.bmkBreeds = 0,
    this.bmkEggBreakout = 0,
    this.temperatureSessions = 0,
    this.temperatureReadings = 0,
    this.goveeDailyCaptures = 0,
    this.goveePlaceReadings = 0,
  });

  int get total =>
      customers +
      flocks +
      hatcheries +
      audits +
      auditSessions +
      photos +
      bmkBreeds +
      bmkEggBreakout +
      temperatureSessions +
      temperatureReadings +
      goveeDailyCaptures +
      goveePlaceReadings;
}

class SupabaseService {
  static const Set<String> _localOnlyAuditColumns = {
    'cvtReadingsJson',
    'cvtPhotosJson',
  };

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

  Future<bool> refreshAvailability() async {
    await _checkNetworkAvailability();
    return isAvailable;
  }

  Future<AuthResult> signIn(
    String email,
    String password, {
    bool rememberSession = true,
  }) async {
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
      final tokenExpiry = rememberSession ? _sessionExpiry(session) : null;
      final user = _buildUserFromAuth(
        supabaseUser,
        fallbackEmail: email,
        profile: profile,
        accessToken: rememberSession ? session.accessToken : null,
        tokenExpiry: tokenExpiry,
      );

      await _userRepo.upsertUser(user);
      if (rememberSession && tokenExpiry != null) {
        await _userRepo.cacheToken(user.id, session.accessToken, tokenExpiry);
      }

      return AuthResult(success: true, user: user);
    } on AuthException catch (e) {
      return AuthResult(success: false, error: e.message);
    } on SocketException {
      return AuthResult(success: false, error: 'offline');
    } catch (e) {
      debugPrint('Supabase sign-in failed: $e');
      final msg = e.toString().toLowerCase();
      if (msg.contains('socket') ||
          msg.contains('failed host') ||
          msg.contains('network') ||
          msg.contains('connection refused') ||
          msg.contains('connection reset')) {
        return AuthResult(success: false, error: 'offline');
      }
      return AuthResult(success: false, error: _cleanError(e));
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
        data: {'full_name': fullName},
      );

      final supabaseUser = response.user;
      if (supabaseUser == null) {
        return AuthResult(success: false, error: 'Sign-up failed');
      }

      final user = UserModel(
        id: supabaseUser.id,
        fullName: fullName,
        email: email,
        role: 'auditor',
        status: 'approved',
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      );

      await _userRepo.upsertUser(user);

      return AuthResult(success: true, user: user);
    } on AuthException catch (e) {
      return AuthResult(success: false, error: e.message);
    } catch (e) {
      debugPrint('Supabase sign-up failed: $e');
      return AuthResult(
        success: false,
        error: 'Account creation failed: ${_cleanError(e)}',
      );
    }
  }

  String _cleanError(Object error) {
    return error.toString().replaceFirst(RegExp(r'^(Exception|Error):\s*'), '');
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

  Future<void> syncAuditSession(Map<String, dynamic> session) async {
    try {
      await _checkNetworkAvailability();
      if (!isAvailable) return;
      await _upsertWithFallback('audit_sessions', session);
    } catch (e) {
      debugPrint('Supabase audit session sync failed: $e');
    }
  }

  Future<void> syncDeleteAudit(String id) async {
    try {
      await _checkNetworkAvailability();
      if (!isAvailable) return;
      await _client.from('audits').delete().eq('id', id);
    } catch (e) {
      debugPrint('Supabase audit delete sync failed: $e');
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

  Future<void> syncHatchery(Map<String, dynamic> hatchery) async {
    try {
      await _checkNetworkAvailability();
      if (!isAvailable) return;
      await _upsertWithFallback('hatcheries', hatchery);
    } catch (e) {
      debugPrint('Supabase hatchery sync failed: $e');
    }
  }

  Future<void> syncTemperatureSession(Map<String, dynamic> session) async {
    try {
      await _checkNetworkAvailability();
      if (!isAvailable) return;
      await _upsertWithFallback('temperature_sessions', session);
    } catch (e) {
      debugPrint('Supabase temperature session sync failed: $e');
    }
  }

  Future<void> syncTemperatureReadings(
    List<Map<String, dynamic>> readings,
  ) async {
    try {
      await _checkNetworkAvailability();
      if (!isAvailable || readings.isEmpty) return;
      final rows = readings.map(_snakeCaseKeys).toList();
      await _client.from('temperature_readings').upsert(rows);
    } catch (e) {
      debugPrint('Supabase temperature readings sync failed: $e');
    }
  }

  Future<void> upsertRows(String table, List<Map<String, dynamic>> rows) async {
    try {
      await _checkNetworkAvailability();
      if (!isAvailable || rows.isEmpty) return;
      await _upsertRowsWithFallback(table, rows);
    } catch (e) {
      debugPrint('Supabase $table sync failed: $e');
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

  Future<void> uploadPhoto(PhotoModel photo) async {
    await _checkNetworkAvailability();
    if (!isAvailable) return;

    final file = File(photo.filePath);
    final bytes = await file.readAsBytes();
    final extension = _fileExtension(photo.filePath);
    final storagePath = '${photo.auditId}/${photo.id}.$extension';

    await _client.storage
        .from('photos')
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _contentTypeForExtension(extension),
          ),
        );

    final publicUrl = _client.storage.from('photos').getPublicUrl(storagePath);
    await _upsertWithFallback('photos', {
      'id': photo.id,
      'filePath': publicUrl,
      'description': photo.description,
      'createdAt': photo.createdAt.toIso8601String(),
      'auditId': photo.auditId,
      'uploadStatus': 'synced',
    });
  }

  Future<SupabasePullSummary> pullFromSupabase({
    required Future<void> Function(Map<String, dynamic>) upsertCustomer,
    required Future<void> Function(Map<String, dynamic>) upsertFlock,
    required Future<void> Function(Map<String, dynamic>) upsertAudit,
    Future<void> Function(Map<String, dynamic>)? upsertHatchery,
    Future<void> Function(Map<String, dynamic>)? upsertAuditSession,
    Future<void> Function(Map<String, dynamic>)? upsertPhoto,
    Future<void> Function(Map<String, dynamic>)? upsertBmkBreed,
    Future<void> Function(Map<String, dynamic>)? upsertBmkEggBreakout,
    Future<void> Function(Map<String, dynamic>)? upsertTemperatureSession,
    Future<void> Function(Map<String, dynamic>)? upsertTemperatureReading,
    Future<void> Function(Map<String, dynamic>)? upsertGoveeDailyCapture,
    Future<void> Function(Map<String, dynamic>)? upsertGoveePlaceReading,
  }) async {
    var summary = const SupabasePullSummary();
    try {
      await _checkNetworkAvailability();
      if (!isAvailable) return summary;
      final customers = await _client.from('customers').select();
      summary = SupabasePullSummary(
        customers: customers.length,
        flocks: summary.flocks,
        hatcheries: summary.hatcheries,
        audits: summary.audits,
        auditSessions: summary.auditSessions,
        photos: summary.photos,
        bmkBreeds: summary.bmkBreeds,
        bmkEggBreakout: summary.bmkEggBreakout,
        temperatureSessions: summary.temperatureSessions,
        temperatureReadings: summary.temperatureReadings,
      );
      debugPrint('Supabase pull: ${customers.length} customers');
      for (final row in customers) {
        await upsertCustomer(Map<String, dynamic>.from(row));
      }
      final flocks = await _client.from('flocks').select();
      summary = SupabasePullSummary(
        customers: summary.customers,
        flocks: flocks.length,
        hatcheries: summary.hatcheries,
        audits: summary.audits,
        auditSessions: summary.auditSessions,
        photos: summary.photos,
        bmkBreeds: summary.bmkBreeds,
        bmkEggBreakout: summary.bmkEggBreakout,
        temperatureSessions: summary.temperatureSessions,
        temperatureReadings: summary.temperatureReadings,
      );
      debugPrint('Supabase pull: ${flocks.length} flocks');
      for (final row in flocks) {
        await upsertFlock(Map<String, dynamic>.from(row));
      }
      if (upsertHatchery != null) {
        try {
          final hatcheries = await _client.from('hatcheries').select();
          summary = SupabasePullSummary(
            customers: summary.customers,
            flocks: summary.flocks,
            hatcheries: hatcheries.length,
            audits: summary.audits,
            auditSessions: summary.auditSessions,
            photos: summary.photos,
            bmkBreeds: summary.bmkBreeds,
            bmkEggBreakout: summary.bmkEggBreakout,
            temperatureSessions: summary.temperatureSessions,
            temperatureReadings: summary.temperatureReadings,
          );
          debugPrint('Supabase pull: ${hatcheries.length} hatcheries');
          for (final row in hatcheries) {
            await upsertHatchery(Map<String, dynamic>.from(row));
          }
        } catch (e) {
          debugPrint('Supabase hatchery pull skipped: $e');
        }
      }
      final audits = await _client.from('audits').select();
      summary = SupabasePullSummary(
        customers: summary.customers,
        flocks: summary.flocks,
        hatcheries: summary.hatcheries,
        audits: audits.length,
        auditSessions: summary.auditSessions,
        photos: summary.photos,
        bmkBreeds: summary.bmkBreeds,
        bmkEggBreakout: summary.bmkEggBreakout,
        temperatureSessions: summary.temperatureSessions,
        temperatureReadings: summary.temperatureReadings,
      );
      debugPrint('Supabase pull: ${audits.length} audits');
      for (final row in audits) {
        await upsertAudit(Map<String, dynamic>.from(row));
      }
      if (upsertAuditSession != null) {
        try {
          final sessions = await _client.from('audit_sessions').select();
          summary = SupabasePullSummary(
            customers: summary.customers,
            flocks: summary.flocks,
            hatcheries: summary.hatcheries,
            audits: summary.audits,
            auditSessions: sessions.length,
            photos: summary.photos,
            bmkBreeds: summary.bmkBreeds,
            bmkEggBreakout: summary.bmkEggBreakout,
            temperatureSessions: summary.temperatureSessions,
            temperatureReadings: summary.temperatureReadings,
          );
          debugPrint('Supabase pull: ${sessions.length} audit sessions');
          for (final row in sessions) {
            await upsertAuditSession(Map<String, dynamic>.from(row));
          }
        } catch (e) {
          debugPrint('Supabase audit session pull skipped: $e');
        }
      }
      if (upsertPhoto != null) {
        try {
          final photos = await _client.from('photos').select();
          summary = SupabasePullSummary(
            customers: summary.customers,
            flocks: summary.flocks,
            hatcheries: summary.hatcheries,
            audits: summary.audits,
            auditSessions: summary.auditSessions,
            photos: photos.length,
            bmkBreeds: summary.bmkBreeds,
            bmkEggBreakout: summary.bmkEggBreakout,
            temperatureSessions: summary.temperatureSessions,
            temperatureReadings: summary.temperatureReadings,
          );
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
          summary = SupabasePullSummary(
            customers: summary.customers,
            flocks: summary.flocks,
            hatcheries: summary.hatcheries,
            audits: summary.audits,
            auditSessions: summary.auditSessions,
            photos: summary.photos,
            bmkBreeds: breeds.length,
            bmkEggBreakout: summary.bmkEggBreakout,
            temperatureSessions: summary.temperatureSessions,
            temperatureReadings: summary.temperatureReadings,
          );
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
          summary = SupabasePullSummary(
            customers: summary.customers,
            flocks: summary.flocks,
            hatcheries: summary.hatcheries,
            audits: summary.audits,
            auditSessions: summary.auditSessions,
            photos: summary.photos,
            bmkBreeds: summary.bmkBreeds,
            bmkEggBreakout: breakout.length,
            temperatureSessions: summary.temperatureSessions,
            temperatureReadings: summary.temperatureReadings,
          );
          debugPrint('Supabase pull: ${breakout.length} BMK egg breakout rows');
          for (final row in breakout) {
            await upsertBmkEggBreakout(Map<String, dynamic>.from(row));
          }
        } catch (e) {
          debugPrint('Supabase BMK egg breakout pull skipped: $e');
        }
      }
      if (upsertTemperatureSession != null) {
        try {
          final sessions = await _client.from('temperature_sessions').select();
          summary = SupabasePullSummary(
            customers: summary.customers,
            flocks: summary.flocks,
            hatcheries: summary.hatcheries,
            audits: summary.audits,
            auditSessions: summary.auditSessions,
            photos: summary.photos,
            bmkBreeds: summary.bmkBreeds,
            bmkEggBreakout: summary.bmkEggBreakout,
            temperatureSessions: sessions.length,
            temperatureReadings: summary.temperatureReadings,
          );
          debugPrint('Supabase pull: ${sessions.length} temperature sessions');
          for (final row in sessions) {
            await upsertTemperatureSession(Map<String, dynamic>.from(row));
          }
        } catch (e) {
          debugPrint('Supabase temperature session pull skipped: $e');
        }
      }
      if (upsertTemperatureReading != null) {
        try {
          final readings = await _client.from('temperature_readings').select();
          summary = SupabasePullSummary(
            customers: summary.customers,
            flocks: summary.flocks,
            hatcheries: summary.hatcheries,
            audits: summary.audits,
            auditSessions: summary.auditSessions,
            photos: summary.photos,
            bmkBreeds: summary.bmkBreeds,
            bmkEggBreakout: summary.bmkEggBreakout,
            temperatureSessions: summary.temperatureSessions,
            temperatureReadings: readings.length,
          );
          debugPrint('Supabase pull: ${readings.length} temperature readings');
          for (final row in readings) {
            await upsertTemperatureReading(Map<String, dynamic>.from(row));
          }
        } catch (e) {
          debugPrint('Supabase temperature reading pull skipped: $e');
        }
      }
      if (upsertGoveeDailyCapture != null) {
        try {
          final captures = await _client.from('govee_daily_captures').select();
          summary = SupabasePullSummary(
            customers: summary.customers,
            flocks: summary.flocks,
            hatcheries: summary.hatcheries,
            audits: summary.audits,
            auditSessions: summary.auditSessions,
            photos: summary.photos,
            bmkBreeds: summary.bmkBreeds,
            bmkEggBreakout: summary.bmkEggBreakout,
            temperatureSessions: summary.temperatureSessions,
            temperatureReadings: summary.temperatureReadings,
            goveeDailyCaptures: captures.length,
            goveePlaceReadings: summary.goveePlaceReadings,
          );
          debugPrint('Supabase pull: ${captures.length} Govee captures');
          for (final row in captures) {
            await upsertGoveeDailyCapture(Map<String, dynamic>.from(row));
          }
        } catch (e) {
          debugPrint('Supabase Govee capture pull skipped: $e');
        }
      }
      if (upsertGoveePlaceReading != null) {
        try {
          final readings = await _client.from('govee_place_readings').select();
          summary = SupabasePullSummary(
            customers: summary.customers,
            flocks: summary.flocks,
            hatcheries: summary.hatcheries,
            audits: summary.audits,
            auditSessions: summary.auditSessions,
            photos: summary.photos,
            bmkBreeds: summary.bmkBreeds,
            bmkEggBreakout: summary.bmkEggBreakout,
            temperatureSessions: summary.temperatureSessions,
            temperatureReadings: summary.temperatureReadings,
            goveeDailyCaptures: summary.goveeDailyCaptures,
            goveePlaceReadings: readings.length,
          );
          debugPrint('Supabase pull: ${readings.length} Govee place readings');
          for (final row in readings) {
            await upsertGoveePlaceReading(Map<String, dynamic>.from(row));
          }
        } catch (e) {
          debugPrint('Supabase Govee place reading pull skipped: $e');
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Supabase pull failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
    return summary;
  }

  Future<void> _upsertWithFallback(
    String table,
    Map<String, dynamic> row,
  ) async {
    final safeRow = _stripLocalOnlyColumns(table, row);
    try {
      await _client.from(table).upsert(_snakeCaseKeys(safeRow));
    } catch (_) {
      await _client.from(table).upsert(safeRow);
    }
  }

  Future<void> _upsertRowsWithFallback(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    final safeRows = rows.map((row) => _stripLocalOnlyColumns(table, row));
    try {
      await _client.from(table).upsert(safeRows.map(_snakeCaseKeys).toList());
    } catch (_) {
      await _client.from(table).upsert(safeRows.toList());
    }
  }

  Map<String, dynamic> _stripLocalOnlyColumns(
    String table,
    Map<String, dynamic> row,
  ) {
    if (table != 'audits') return row;
    final sanitized = Map<String, dynamic>.from(row);
    for (final column in _localOnlyAuditColumns) {
      sanitized.remove(column);
    }
    return sanitized;
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

  String _fileExtension(String filePath) {
    final dotIndex = filePath.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == filePath.length - 1) {
      return 'jpg';
    }
    return filePath.substring(dotIndex + 1).toLowerCase();
  }

  String _contentTypeForExtension(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'jpeg':
      case 'jpg':
      default:
        return 'image/jpeg';
    }
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

  UserModel _buildUserFromAuth(
    User supabaseUser, {
    required String fallbackEmail,
    required Map<String, dynamic>? profile,
    required String? accessToken,
    required DateTime? tokenExpiry,
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
        'approved';
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
