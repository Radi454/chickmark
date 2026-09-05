import 'package:supabase_flutter/supabase_flutter.dart';

/// A user row as seen by the admin access screen (public.profiles + email).
class AdminProfile {
  final String id;
  final String? email;
  final String? username;
  final String? fullName;
  final String role; // admin | auditor | production_manager | customer
  final String status; // pending | approved | disabled
  final String? customerId; // only meaningful when role == customer

  const AdminProfile({
    required this.id,
    required this.email,
    required this.username,
    required this.fullName,
    required this.role,
    required this.status,
    required this.customerId,
  });

  factory AdminProfile.fromMap(Map<String, dynamic> map) {
    return AdminProfile(
      id: map['id'] as String,
      email: map['email'] as String?,
      username: map['username'] as String?,
      fullName: map['full_name'] as String?,
      role: (map['role'] as String?) ?? 'auditor',
      status: (map['status'] as String?) ?? 'pending',
      customerId: map['customer_id'] as String?,
    );
  }

  String get displayName => (fullName != null && fullName!.trim().isNotEmpty)
      ? fullName!
      : (email ?? id);

  String get loginIdentifier =>
      (username != null && username!.trim().isNotEmpty)
      ? username!
      : (email ?? id);
}

/// Direct (online-only) access to the cloud identity tables. Every call is
/// gated server-side by RLS — only an admin profile can read all rows or write
/// roles / status / assignments. These tables are intentionally NOT part of the
/// offline sync set, so this repository talks to Supabase straight.
class AdminRepository {
  final SupabaseClient? _clientOverride;

  AdminRepository({SupabaseClient? client}) : _clientOverride = client;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  Future<List<AdminProfile>> listProfiles() async {
    final rows = await _client
        .from('profiles')
        .select('id, email, username, full_name, role, status, customer_id')
        .order('email');
    return rows
        .map((row) => AdminProfile.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Creates an approved read-only customer identity without changing the
  /// current admin session. The Edge Function holds the service-role key;
  /// privileged auth-user creation never happens in the Flutter client.
  Future<AdminProfile> createCustomerAccount({
    required String fullName,
    required String username,
    required String password,
    required String customerId,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'create-customer-account',
        body: {
          'fullName': fullName,
          'username': username,
          'password': password,
          'customerId': customerId,
        },
      );
      final data = response.data;
      if (data is! Map || data['profile'] is! Map) {
        throw const AdminAccountException(
          'The server returned an invalid account response.',
        );
      }
      return AdminProfile.fromMap(
        Map<String, dynamic>.from(data['profile'] as Map),
      );
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map ? details['error']?.toString() : null;
      throw AdminAccountException(
        message == null || message.isEmpty
            ? 'Could not create the customer account.'
            : message,
      );
    } on AdminAccountException {
      rethrow;
    } catch (_) {
      throw const AdminAccountException(
        'Could not create the customer account. Check your connection and try again.',
      );
    }
  }

  Future<void> resetCustomerPassword({
    required String userId,
    required String password,
  }) async {
    try {
      await _client.functions.invoke(
        'reset-customer-password',
        body: {'userId': userId, 'password': password},
      );
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map ? details['error']?.toString() : null;
      throw AdminAccountException(
        message == null || message.isEmpty
            ? 'Could not reset the customer password.'
            : message,
      );
    } catch (_) {
      throw const AdminAccountException(
        'Could not reset the customer password. Check your connection and try again.',
      );
    }
  }

  Future<void> updateProfile({
    required String id,
    required String role,
    required String status,
    String? customerId,
  }) async {
    await _client
        .from('profiles')
        .update({
          'role': role,
          'status': status,
          // customer_id only applies to the customer role; clear it otherwise
          'customer_id': role == 'customer' ? customerId : null,
        })
        .eq('id', id);
  }

  /// Customer ids this auditor is assigned to (the many-to-many scope).
  Future<Set<String>> auditorCustomerIds(String auditorId) async {
    final rows = await _client
        .from('auditor_customers')
        .select('customer_id')
        .eq('auditor_id', auditorId);
    return rows.map((row) => row['customer_id'] as String).toSet();
  }

  /// Replace an auditor's full assignment set with [customerIds].
  Future<void> setAuditorCustomers(
    String auditorId,
    Set<String> customerIds,
  ) async {
    await _client
        .from('auditor_customers')
        .delete()
        .eq('auditor_id', auditorId);
    if (customerIds.isEmpty) return;
    await _client
        .from('auditor_customers')
        .insert(
          customerIds
              .map((cid) => {'auditor_id': auditorId, 'customer_id': cid})
              .toList(),
        );
  }
}

class AdminAccountException implements Exception {
  final String message;

  const AdminAccountException(this.message);

  @override
  String toString() => message;
}
