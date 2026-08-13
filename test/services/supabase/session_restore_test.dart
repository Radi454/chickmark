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
