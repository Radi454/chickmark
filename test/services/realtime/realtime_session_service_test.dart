import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/realtime/realtime_session_service.dart';

void main() {
  Map<String, dynamic> validStart() => <String, dynamic>{
    'sessionId': 'sess_1',
    'generation': 1,
    'conversationId': 'conv_1',
    'clientSecret': {'value': 'ek_secret', 'expiresAt': '2026-08-16T10:00:30Z'},
    'bindingToken': 'bind_token',
    'bindingTokenExpiresAt': '2026-08-16T10:01:00Z',
    'sidebandUrl': 'wss://sideband.example/realtime',
    'setupDeadlineAt': '2026-08-16T10:01:00Z',
    'sessionExpiresAt': '2026-08-16T10:10:00Z',
    'maxSessionSeconds': 600,
    'serverTime': '2026-08-16T10:00:00Z',
  };

  test('createSession sends the start action and unwraps the grant', () async {
    final bodies = <Map<String, dynamic>>[];
    final service = SupabaseRealtimeSessionService(
      rpc: (body) async {
        bodies.add(body);
        return validStart();
      },
    );

    final grant = await service.createSession();

    expect(bodies.single, {'action': 'start', 'conversationId': 'app'});
    expect(grant.sessionId, 'sess_1');
    expect(grant.generation, 1);
    // The secret arrives wrapped as {value, expiresAt}.
    expect(grant.clientSecret, 'ek_secret');
    expect(grant.bindingToken, 'bind_token');
    expect(grant.sidebandUrl.scheme, 'wss');
    expect(grant.maxSessionSeconds, 600);
    expect(grant.setupDeadlineAt, isNotNull);
  });

  test('a caller-supplied conversationKey is sent as conversationId', () async {
    final bodies = <Map<String, dynamic>>[];
    final service = SupabaseRealtimeSessionService(
      rpc: (body) async {
        bodies.add(body);
        return validStart();
      },
    );

    await service.createSession(
      conversationKey: 'app:11111111-1111-4111-8111-111111111111',
    );

    expect(bodies.single, {
      'action': 'start',
      'conversationId': 'app:11111111-1111-4111-8111-111111111111',
    });
  });

  test('the SDP endpoint is a fixed API property, not app config', () async {
    final service = SupabaseRealtimeSessionService(
      rpc: (_) async => validStart(),
    );

    final grant = await service.createSession();

    expect(grant.effectiveCallsUrl, openAiRealtimeCallsUrl);
    expect(grant.effectiveCallsUrl.host, 'api.openai.com');
  });

  test('registerCall carries the session, generation and call id', () async {
    final bodies = <Map<String, dynamic>>[];
    final service = SupabaseRealtimeSessionService(
      rpc: (body) async {
        bodies.add(body);
        return <String, dynamic>{'setupState': 'call_registered'};
      },
    );

    await service.registerCall(
      sessionId: 'sess_1',
      generation: 1,
      callId: 'rtc_abc',
    );

    expect(bodies.single, {
      'action': 'register_call',
      'sessionId': 'sess_1',
      'generation': 1,
      'openaiCallId': 'rtc_abc',
    });
  });

  test('abortSetup reports the orphaned call id when there is one', () async {
    final bodies = <Map<String, dynamic>>[];
    final service = SupabaseRealtimeSessionService(
      rpc: (body) async {
        bodies.add(body);
        return <String, dynamic>{'setupState': 'cleanup_pending'};
      },
    );

    await service.abortSetup(
      sessionId: 'sess_1',
      generation: 1,
      callId: 'rtc_abc',
    );
    await service.abortSetup(sessionId: 'sess_1', generation: 1);

    expect(bodies.first, {
      'action': 'abort_setup',
      'sessionId': 'sess_1',
      'generation': 1,
      'openaiCallId': 'rtc_abc',
    });
    expect(bodies.last.containsKey('openaiCallId'), isFalse);
  });

  test('endSession sends a reason from the fixed vocabulary', () async {
    final bodies = <Map<String, dynamic>>[];
    final service = SupabaseRealtimeSessionService(
      rpc: (body) async {
        bodies.add(body);
        return <String, dynamic>{'state': 'ending'};
      },
    );

    await service.endSession(sessionId: 'sess_1');
    await service.endSession(
      sessionId: 'sess_1',
      reason: RealtimeEndReason.networkLost,
    );

    expect(bodies.first, {
      'action': 'end',
      'sessionId': 'sess_1',
      'reason': 'user_ended',
    });
    expect(bodies.last['reason'], 'network_lost');
  });

  test('a missing field fails rather than half-building a grant', () async {
    final incomplete = validStart()..remove('bindingToken');
    final service = SupabaseRealtimeSessionService(
      rpc: (_) async => incomplete,
    );

    await expectLater(
      service.createSession(),
      throwsA(
        isA<RealtimeSessionException>().having(
          (error) => error.code,
          'code',
          'missing_bindingToken',
        ),
      ),
    );
  });

  test('a missing generation fails', () async {
    final incomplete = validStart()..remove('generation');
    final service = SupabaseRealtimeSessionService(
      rpc: (_) async => incomplete,
    );

    await expectLater(
      service.createSession(),
      throwsA(
        isA<RealtimeSessionException>().having(
          (error) => error.code,
          'code',
          'missing_generation',
        ),
      ),
    );
  });

  test('a non-object payload fails', () async {
    final service = SupabaseRealtimeSessionService(rpc: (_) async => 'nope');

    await expectLater(
      service.createSession(),
      throwsA(isA<RealtimeSessionException>()),
    );
  });

  test('a schemeless sideband url fails', () async {
    final broken = validStart()..['sidebandUrl'] = 'sideband.example';
    final service = SupabaseRealtimeSessionService(rpc: (_) async => broken);

    await expectLater(
      service.createSession(),
      throwsA(
        isA<RealtimeSessionException>().having(
          (error) => error.code,
          'code',
          'invalid_sidebandUrl',
        ),
      ),
    );
  });

  test('accessToken hands the sideband the caller JWT', () async {
    final service = SupabaseRealtimeSessionService(
      rpc: (_) async => validStart(),
      accessTokenReader: () => 'jwt-value',
    );

    expect(await service.accessToken(), 'jwt-value');
  });

  test('a signed-out caller cannot bind the sideband', () async {
    final service = SupabaseRealtimeSessionService(
      rpc: (_) async => validStart(),
      accessTokenReader: () => null,
    );

    await expectLater(
      service.accessToken(),
      throwsA(
        isA<RealtimeSessionException>().having(
          (error) => error.code,
          'code',
          'signed_out',
        ),
      ),
    );
  });

  test('a transport failure becomes a user-facing message', () async {
    final service = SupabaseRealtimeSessionService(
      rpc: (_) async => throw Exception('boom'),
    );

    await expectLater(
      service.createSession(),
      throwsA(
        isA<RealtimeSessionException>().having(
          (error) => error.code,
          'code',
          'transport_error',
        ),
      ),
    );
  });
}
