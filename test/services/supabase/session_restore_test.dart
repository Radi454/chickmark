import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:hatchaudit/services/supabase/supabase_service.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

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

    test(
      'a retryable 5xx fetch failure is offline, never a logout',
      () {
        // gotrue throws AuthRetryableFetchException for any 5xx response from
        // the Auth server; its message is the raw response body and carries
        // none of the network-error wording, so this must be caught by type,
        // not by string matching. gotrue's own token-refresh handler
        // (`GoTrueClient._callRefreshToken`) likewise refuses to sign the
        // user out on this exact type.
        expect(
          classifyRestoreFailure(
            AuthRetryableFetchException(
              message: '{"error":"upstream connect error"}',
              statusCode: '503',
            ),
          ),
          SessionRestoreStatus.offline,
        );
      },
    );

    test(
      'a genuine auth rejection still classifies as rejected after the '
      'retryable-fetch narrowing',
      () {
        expect(
          classifyRestoreFailure(
            const AuthException('Invalid Refresh Token: Already Used'),
          ),
          SessionRestoreStatus.rejected,
        );
      },
    );
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

    test(
      'a missing local session is offline, never a rejection',
      () async {
        // gotrue holding no session is a purely local condition — no server
        // answered — and "online" here only means an active interface, which
        // captive/uplink-less Wi-Fi also satisfies. Reporting `rejected` here
        // would wipe trust and tokens with no server rejection behind it.
        final auth = _MockGoTrueClient();
        when(() => auth.currentSession).thenReturn(null);
        final client = _MockSupabaseClient();
        when(() => client.auth).thenReturn(auth);

        final service = SupabaseService(
          isConfiguredForTesting: () => true,
          reloadConfigForTesting: () async {},
          checkNetworkAvailableForTesting: () async => true,
          initializeSupabaseForTesting: () async => true,
          clientForTesting: () => client,
        );

        final result = await service.restoreSession();

        expect(result.status, SessionRestoreStatus.offline);
        expect(result.accessToken, isNull);
        verifyNever(() => auth.refreshSession());
      },
    );
  });
}
