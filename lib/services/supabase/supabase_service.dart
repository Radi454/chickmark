import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/supabase_config.dart';
import '../../core/network/network_reachability.dart';
import '../../core/security/safe_debug_log.dart';
import '../../core/security/security_policy.dart';
import '../../data/models/panel_sample_schema.dart';
import '../../data/models/photo_model.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/user_repository.dart';
import 'sync_meta.dart';
import 'supabase_initializer.dart';

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
  final int auditSessions;
  final int photos;
  final int bmkBreeds;
  final int bmkEggBreakout;
  final int goveeDailyCaptures;
  final int panelRows;
  final int syncTombstones;

  const SupabasePullSummary({
    this.customers = 0,
    this.flocks = 0,
    this.hatcheries = 0,
    this.auditSessions = 0,
    this.photos = 0,
    this.bmkBreeds = 0,
    this.bmkEggBreakout = 0,
    this.goveeDailyCaptures = 0,
    this.panelRows = 0,
    this.syncTombstones = 0,
  });

  int get total =>
      customers +
      flocks +
      hatcheries +
      auditSessions +
      photos +
      bmkBreeds +
      bmkEggBreakout +
      goveeDailyCaptures +
      panelRows +
      syncTombstones;

  SupabasePullSummary copyWith({
    int? customers,
    int? flocks,
    int? hatcheries,
    int? auditSessions,
    int? photos,
    int? bmkBreeds,
    int? bmkEggBreakout,
    int? goveeDailyCaptures,
    int? panelRows,
    int? syncTombstones,
  }) {
    return SupabasePullSummary(
      customers: customers ?? this.customers,
      flocks: flocks ?? this.flocks,
      hatcheries: hatcheries ?? this.hatcheries,
      auditSessions: auditSessions ?? this.auditSessions,
      photos: photos ?? this.photos,
      bmkBreeds: bmkBreeds ?? this.bmkBreeds,
      bmkEggBreakout: bmkEggBreakout ?? this.bmkEggBreakout,
      goveeDailyCaptures: goveeDailyCaptures ?? this.goveeDailyCaptures,
      panelRows: panelRows ?? this.panelRows,
      syncTombstones: syncTombstones ?? this.syncTombstones,
    );
  }
}

class SupabaseService {
  final UserRepository _userRepo;
  final bool Function() _isConfigured;
  final Future<bool> Function() _initializeSupabase;
  final Future<bool> Function() _checkNetworkAvailable;
  final SupabaseClient Function() _clientProvider;

  SupabaseClient get _client => _clientProvider();

  @visibleForTesting
  SupabaseClient get clientForTesting => _client;

  bool get isAvailable =>
      _isConfigured() && _isNetworkAvailable && _supabaseInitialized;
  bool get isConfigured => _isConfigured();

  bool _isNetworkAvailable = true;
  bool _supabaseInitialized = false;

  SupabaseService({
    UserRepository? userRepository,
    bool Function()? isConfiguredForTesting,
    Future<bool> Function()? initializeSupabaseForTesting,
    Future<bool> Function()? checkNetworkAvailableForTesting,
    SupabaseClient Function()? clientForTesting,
  }) : _userRepo = userRepository ?? UserRepository(),
       _isConfigured =
           isConfiguredForTesting ?? (() => SupabaseConfig.isConfigured),
       _initializeSupabase =
           initializeSupabaseForTesting ??
           SupabaseInitializer.ensureInitialized,
       _checkNetworkAvailable =
           checkNetworkAvailableForTesting ?? _defaultNetworkAvailable,
       _clientProvider = clientForTesting ?? (() => Supabase.instance.client) {
    _checkNetworkAvailability();
  }

  static Future<bool> _defaultNetworkAvailable() =>
      NetworkReachability.isOnline();

  Future<void> _checkNetworkAvailability() async {
    _isNetworkAvailable = await _checkNetworkAvailable();
  }

  Future<bool> refreshAvailability() async {
    await _checkNetworkAvailability();
    return _ensureSupabaseReady();
  }

  Future<bool> _prepareRemoteAccess() async {
    await _checkNetworkAvailability();
    return _ensureSupabaseReady();
  }

  Future<bool> _ensureSupabaseReady() async {
    if (!_isConfigured() || !_isNetworkAvailable) {
      _supabaseInitialized = false;
      return false;
    }
    try {
      _supabaseInitialized = await _initializeSupabase();
      return _supabaseInitialized;
    } catch (e) {
      _supabaseInitialized = false;
      safeDebugLog('Supabase initialization unavailable', error: e);
      return false;
    }
  }

  Future<AuthResult> signIn(
    String email,
    String password, {
    bool rememberSession = true,
  }) async {
    try {
      await _checkNetworkAvailability();
      if (!_isConfigured()) {
        return AuthResult(
          success: false,
          error:
              'Supabase credentials are not configured. Run the app with --dart-define-from-file=.env.',
        );
      }
      if (!_isNetworkAvailable) {
        return AuthResult(success: false, error: 'offline');
      }
      if (!await _ensureSupabaseReady()) {
        return AuthResult(
          success: false,
          error: 'Supabase is still initializing. Try again in a moment.',
        );
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
      safeDebugLog('Supabase sign-in failed', error: e);
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
      if (!_isConfigured()) {
        return AuthResult(
          success: false,
          error:
              'Supabase credentials are not configured. Run the app with --dart-define-from-file=.env.',
        );
      }
      if (!_isNetworkAvailable) {
        return AuthResult(success: false, error: 'offline');
      }
      if (!await _ensureSupabaseReady()) {
        return AuthResult(
          success: false,
          error: 'Supabase is still initializing. Try again in a moment.',
        );
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
      safeDebugLog('Supabase sign-up failed', error: e);
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
      if (!await _prepareRemoteAccess()) return false;
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
      if (!await _prepareRemoteAccess()) return;
      await _client.auth.signOut();
    } catch (_) {}
  }

  Future<void> syncAuditSession(Map<String, dynamic> session) async {
    try {
      if (!await _prepareRemoteAccess()) return;
      await _upsertWithFallback('audit_sessions', stripSyncMeta(session));
    } catch (e) {
      safeDebugLog('Supabase audit session sync failed', error: e);
    }
  }

  Future<void> syncCustomer(Map<String, dynamic> customer) async {
    try {
      if (!await _prepareRemoteAccess()) return;
      await _upsertWithFallback('customers', customer);
    } catch (e) {
      safeDebugLog('Supabase customer sync failed', error: e);
    }
  }

  Future<void> syncFlock(Map<String, dynamic> flock) async {
    try {
      if (!await _prepareRemoteAccess()) return;
      await _upsertWithFallback('flocks', flock);
    } catch (e) {
      safeDebugLog('Supabase flock sync failed', error: e);
    }
  }

  Future<void> syncHatchery(Map<String, dynamic> hatchery) async {
    try {
      if (!await _prepareRemoteAccess()) return;
      await _upsertWithFallback('hatcheries', hatchery);
    } catch (e) {
      safeDebugLog('Supabase hatchery sync failed', error: e);
    }
  }

  Future<void> upsertRows(String table, List<Map<String, dynamic>> rows) async {
    try {
      if (rows.isEmpty || !await _prepareRemoteAccess()) return;
      await _upsertRowsWithFallback(table, rows);
    } catch (e) {
      safeDebugLog('Supabase sync failed for $table', error: e);
    }
  }

  Future<void> upsertRowsStrict(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    if (!await _prepareRemoteAccess()) {
      throw StateError('Supabase sync is not available');
    }
    await _upsertRowsWithFallback(table, rows);
  }

  Future<void> deleteRows(String table, List<String> ids) async {
    final rowIds = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (rowIds.isEmpty || !await _prepareRemoteAccess()) return;
    if (table == 'photos') {
      await _deletePhotoStorageObjects(rowIds);
    }
    final idColumn = _remoteDeleteIdColumn(table);
    try {
      await _client.from(table).delete().inFilter(idColumn, rowIds);
    } catch (_) {
      await _client.from(table).delete().inFilter(_camelize(idColumn), rowIds);
    }
  }

  Future<List<int>> downloadPhotoBytes(String remoteFilePath) async {
    if (!await _prepareRemoteAccess()) return const [];
    final storagePath = _photoStoragePath(remoteFilePath);
    if (storagePath == null || storagePath.isEmpty) {
      throw ArgumentError.value(remoteFilePath, 'remoteFilePath');
    }
    return _client.storage.from('photos').download(storagePath);
  }

  Future<void> syncUpdateFlock(Map<String, dynamic> flock) async {
    try {
      if (!await _prepareRemoteAccess()) return;
      await _upsertWithFallback('flocks', flock);
    } catch (e) {
      safeDebugLog('Supabase flock update sync failed', error: e);
    }
  }

  Future<void> syncDeleteFlock(String id) async {
    try {
      if (!await _prepareRemoteAccess()) return;
      await _client.from('flocks').delete().eq('id', id);
    } catch (e) {
      safeDebugLog('Supabase flock delete sync failed', error: e);
    }
  }

  Future<void> uploadPhoto(PhotoModel photo) async {
    if (!await _prepareRemoteAccess()) return;

    final file = File(photo.filePath);
    final bytes = await file.readAsBytes();
    final extension = _fileExtension(photo.filePath);
    final storagePath =
        '${photo.sessionId}/${photo.panelName}/${photo.panelRowId}/${photo.id}.$extension';

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

    final remotePhotoPath = SupabaseSecurityPolicy.isPublicPhotoUrlEnabled
        ? _client.storage.from('photos').getPublicUrl(storagePath)
        : 'supabase://photos/$storagePath';
    await _upsertWithFallback('photos', {
      'id': photo.id,
      'filePath': remotePhotoPath,
      'description': photo.description,
      'createdAt': photo.createdAt.toIso8601String(),
      'sessionId': photo.sessionId,
      'panelName': photo.panelName,
      'panelRowId': photo.panelRowId,
      'fieldKey': photo.fieldKey,
      'uploadStatus': 'synced',
    });
  }

  Future<String?> uploadBmkOperationalSourcePhoto({
    required String localPath,
    required String metricKey,
    String? hatcheryId,
  }) async {
    if (!await _prepareRemoteAccess()) return null;

    final file = File(localPath);
    final bytes = await file.readAsBytes();
    final extension = _fileExtension(localPath);
    final scope = _safeStorageSegment(
      hatcheryId == null || hatcheryId.isEmpty ? 'global' : hatcheryId,
    );
    final metric = _safeStorageSegment(metricKey);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath =
        'bmk_operational_sources/$scope/$metric/$stamp.$extension';

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

    return SupabaseSecurityPolicy.isPublicPhotoUrlEnabled
        ? _client.storage.from('photos').getPublicUrl(storagePath)
        : 'supabase://photos/$storagePath';
  }

  Future<void> deleteBmkOperationalSourcePhoto(String? remotePath) async {
    final storagePath = _photoStoragePath(remotePath);
    if (storagePath == null || storagePath.isEmpty) return;
    if (!await _prepareRemoteAccess()) return;
    await _client.storage.from('photos').remove([storagePath]);
  }

  Future<void> _deletePhotoStorageObjects(List<String> rowIds) async {
    final storagePaths = <String>{};
    List<dynamic> rows;
    try {
      rows = await _client
          .from('photos')
          .select('file_path')
          .inFilter('id', rowIds);
    } catch (_) {
      rows = await _client
          .from('photos')
          .select('filePath')
          .inFilter('id', rowIds);
    }
    for (final row in rows) {
      if (row is! Map) continue;
      final filePath = row['file_path'] ?? row['filePath'];
      final storagePath = _photoStoragePath(filePath?.toString());
      if (storagePath != null && storagePath.isNotEmpty) {
        storagePaths.add(storagePath);
      }
    }
    if (storagePaths.isEmpty) return;
    await _client.storage.from('photos').remove(storagePaths.toList());
  }

  Future<SupabasePullSummary> pullFromSupabase({
    required Future<void> Function(Map<String, dynamic>) upsertCustomer,
    required Future<void> Function(Map<String, dynamic>) upsertFlock,
    Future<void> Function(Map<String, dynamic>)? upsertHatchery,
    Future<void> Function(Map<String, dynamic>)? upsertAuditSession,
    Future<void> Function(Map<String, dynamic>)? upsertPhoto,
    Future<void> Function(Map<String, dynamic>)? upsertBmkBreed,
    Future<void> Function(Map<String, dynamic>)? upsertBmkEggBreakout,
    Future<void> Function(Map<String, dynamic>)? upsertGoveeDailyCapture,
    Future<void> Function(String table, Map<String, dynamic> row)?
    upsertPanelRow,
    Future<void> Function(Map<String, dynamic>)? upsertSyncTombstone,
  }) async {
    var summary = const SupabasePullSummary();
    Future<int> pullTable(
      String table,
      Future<void> Function(Map<String, dynamic>) upsert, {
      bool required = false,
    }) async {
      try {
        final rows = await _client.from(table).select();
        safeDebugLog('Supabase pull: ${rows.length} $table rows');
        for (final row in rows) {
          await upsert(Map<String, dynamic>.from(row));
        }
        return rows.length;
      } catch (e) {
        if (required) rethrow;
        safeDebugLog('Supabase $table pull skipped', error: e);
        return 0;
      }
    }

    try {
      if (!await _prepareRemoteAccess()) return summary;
      summary = summary.copyWith(
        customers: await pullTable('customers', upsertCustomer, required: true),
      );
      if (upsertHatchery != null) {
        summary = summary.copyWith(
          hatcheries: await pullTable('hatcheries', upsertHatchery),
        );
      }
      summary = summary.copyWith(
        flocks: await pullTable('flocks', upsertFlock, required: true),
      );
      if (upsertHatchery != null) {
        // Already pulled before flocks so local FK dependencies are available.
      }
      if (upsertAuditSession != null) {
        summary = summary.copyWith(
          auditSessions: await pullTable('audit_sessions', upsertAuditSession),
        );
      }
      if (upsertPhoto != null) {
        summary = summary.copyWith(
          photos: await pullTable('photos', upsertPhoto),
        );
      }
      if (upsertBmkBreed != null) {
        summary = summary.copyWith(
          bmkBreeds: await pullTable('bmk_breeds', upsertBmkBreed),
        );
      }
      if (upsertBmkEggBreakout != null) {
        summary = summary.copyWith(
          bmkEggBreakout: await pullTable(
            'bmk_egg_breakout',
            upsertBmkEggBreakout,
          ),
        );
      }
      if (upsertGoveeDailyCapture != null) {
        summary = summary.copyWith(
          goveeDailyCaptures: await pullTable(
            'govee_daily_captures',
            upsertGoveeDailyCapture,
          ),
        );
      }
      if (upsertPanelRow != null) {
        var count = 0;
        for (final panel in PanelSampleSchema.panels) {
          count += await pullTable(panel.tableName, (row) {
            return upsertPanelRow(panel.tableName, row);
          });
        }
        summary = summary.copyWith(panelRows: count);
      }
      if (upsertSyncTombstone != null) {
        summary = summary.copyWith(
          syncTombstones: await pullTable(
            'sync_tombstones',
            upsertSyncTombstone,
          ),
        );
      }
    } catch (e) {
      safeDebugLog('Supabase pull failed', error: e);
    }
    return summary;
  }

  Future<int> pullSyncTombstones({
    required Future<void> Function(Map<String, dynamic>) upsertSyncTombstone,
  }) async {
    try {
      if (!await _prepareRemoteAccess()) return 0;
      final rows = await _client.from('sync_tombstones').select();
      safeDebugLog('Supabase pull: ${rows.length} sync_tombstones rows');
      for (final row in rows) {
        await upsertSyncTombstone(Map<String, dynamic>.from(row));
      }
      return rows.length;
    } catch (e) {
      safeDebugLog('Supabase sync_tombstones pull skipped', error: e);
      return 0;
    }
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
    return row;
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

  String _remoteDeleteIdColumn(String table) {
    if (table.startsWith('sample_') && table.endsWith('_details')) {
      return 'sample_record_id';
    }
    return 'id';
  }

  String _fileExtension(String filePath) {
    final dotIndex = filePath.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == filePath.length - 1) {
      return 'jpg';
    }
    return filePath.substring(dotIndex + 1).toLowerCase();
  }

  String _safeStorageSegment(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return sanitized.isEmpty ? 'unknown' : sanitized;
  }

  String? _photoStoragePath(String? filePath) {
    if (filePath == null || filePath.trim().isEmpty) return null;
    const privatePrefix = 'supabase://photos/';
    if (filePath.startsWith(privatePrefix)) {
      return filePath.substring(privatePrefix.length);
    }

    final uri = Uri.tryParse(filePath);
    if (uri == null || !uri.hasScheme) return null;
    final segments = uri.pathSegments;
    final bucketIndex = segments.indexOf('photos');
    if (bucketIndex == -1 || bucketIndex == segments.length - 1) return null;
    return segments.skip(bucketIndex + 1).join('/');
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
          .from('profiles')
          .select()
          .eq('id', userId)
          .limit(1);
      if (rows.isEmpty) return null;
      return Map<String, dynamic>.from(rows.first);
    } catch (e) {
      safeDebugLog('Supabase user profile fetch skipped', error: e);
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
