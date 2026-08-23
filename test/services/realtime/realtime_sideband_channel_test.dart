import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/realtime/realtime_sideband_channel.dart';

void main() {
  _sidebandUriTests();

  // The wire contract lives in services/pip-realtime-sideband/WIRE_CONTRACT.md.
  // The literal below is asserted verbatim on the server side too, by
  // `parseBindFrame` in services/pip-realtime-sideband/test/binding_test.ts: an
  // edit to either side fails the other side's test.
  group('bind frame', () {
    test('is exactly the snake_case frame the server parses', () {
      final encoded = encodeBindFrame(
        sessionId: 'sess_1',
        generation: 1,
        accessToken: 'access',
        bindingToken: 'one-time-binding-token',
      );

      expect(
        encoded,
        '{"type":"bind","session_id":"sess_1","generation":1,'
        '"access_token":"access","binding_token":"one-time-binding-token"}',
      );

      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded.keys, <String>[
        'type',
        'session_id',
        'generation',
        'access_token',
        'binding_token',
      ]);
      expect(decoded['generation'], isA<int>());
    });
  });

  // Pinned the same way as the bind frame above: this literal is asserted
  // verbatim in services/pip-realtime-sideband/test/server_test.ts ('READY is
  // withheld until...'), which sends
  // `{"type":"health","webrtc":true,"data_channel":true}` and expects the
  // server to mark webrtcHealthy/dataChannelHealthy from exactly that frame.
  group('health frame', () {
    test('is exactly the snake_case frame the server parses', () {
      expect(
        kSidebandHealthFrame,
        '{"type":"health","webrtc":true,"data_channel":true}',
      );

      final decoded = jsonDecode(kSidebandHealthFrame) as Map<String, dynamic>;
      expect(decoded.keys, <String>['type', 'webrtc', 'data_channel']);
      expect(decoded['webrtc'], isTrue);
      expect(decoded['data_channel'], isTrue);
    });
  });

  group('parseSidebandEvent', () {
    test('READY keeps the ids the controller validates against', () {
      final event = parseSidebandEvent({
        'type': 'ready',
        'session_id': 'sess_1',
        'generation': 3,
      });

      expect(event.kind, RealtimeSidebandEventKind.ready);
      expect(event.sessionId, 'sess_1');
      expect(event.generation, 3);
    });

    test('camelCase is not the contract, so READY ids read as absent', () {
      final event = parseSidebandEvent({
        'type': 'ready',
        'sessionId': 'sess_1',
      });

      expect(event.kind, RealtimeSidebandEventKind.ready);
      expect(event.sessionId, isNull);
    });

    test('error carries a machine code, closing a machine reason', () {
      final error = parseSidebandEvent({
        'type': 'error',
        'code': 'identity_mismatch',
      });
      expect(error.kind, RealtimeSidebandEventKind.error);
      expect(error.code, 'identity_mismatch');
      // The code is never what the user reads.
      expect(error.message, isNot(contains('identity_mismatch')));

      final closing = parseSidebandEvent({
        'type': 'closing',
        'reason': 'server_drain',
      });
      expect(closing.kind, RealtimeSidebandEventKind.closing);
      expect(closing.reason, 'server_drain');
    });

    test('captions and turn states are not part of this socket', () {
      expect(
        parseSidebandEvent({'type': 'caption', 'text': 'hello'}).kind,
        RealtimeSidebandEventKind.unknown,
      );
      expect(
        parseSidebandEvent({'type': 'state', 'state': 'thinking'}).kind,
        RealtimeSidebandEventKind.unknown,
      );
      expect(
        parseSidebandEvent({'type': 'ended'}).kind,
        RealtimeSidebandEventKind.unknown,
      );
    });

    test('an unknown type collapses to unknown instead of throwing', () {
      expect(
        parseSidebandEvent({'type': 'brand.new'}).kind,
        RealtimeSidebandEventKind.unknown,
      );
      expect(
        parseSidebandEvent(<String, dynamic>{}).kind,
        RealtimeSidebandEventKind.unknown,
      );
    });

    test('blank ids read as absent, so they cannot spoof a match', () {
      final event = parseSidebandEvent({'type': 'ready', 'session_id': '   '});

      expect(event.sessionId, isNull);
    });
  });

  group('close codes', () {
    test('the three the UI must tell apart map to distinct causes', () {
      expect(
        sidebandCloseCauseFor(4408),
        RealtimeSidebandCloseCause.bindTimeout,
      );
      expect(
        sidebandCloseCauseFor(4401),
        RealtimeSidebandCloseCause.bindRejected,
      );
      expect(sidebandCloseCauseFor(4409), RealtimeSidebandCloseCause.leaseLost);
      expect(sidebandCloseCauseFor(4400), RealtimeSidebandCloseCause.malformed);
      expect(sidebandCloseCauseFor(4503), RealtimeSidebandCloseCause.draining);
      expect(sidebandCloseCauseFor(4500), RealtimeSidebandCloseCause.internal);
      expect(sidebandCloseCauseFor(1000), RealtimeSidebandCloseCause.normal);
      expect(sidebandCloseCauseFor(null), RealtimeSidebandCloseCause.normal);

      final messages = <String>{
        sidebandCloseMessage(RealtimeSidebandCloseCause.bindTimeout),
        sidebandCloseMessage(RealtimeSidebandCloseCause.bindRejected),
        sidebandCloseMessage(RealtimeSidebandCloseCause.leaseLost),
      };
      expect(messages, hasLength(3));
    });
  });
}

void _sidebandUriTests() {
  group('sidebandWebSocketUri', () {
    test('derives the wss route from the base service url', () {
      // Exactly what pip-realtime-session returns as `sidebandUrl`.
      expect(
        sidebandWebSocketUri(
          Uri.parse('https://pip-realtime-sideband-604699737882.europe-west1.run.app'),
        ).toString(),
        'wss://pip-realtime-sideband-604699737882.europe-west1.run.app/v1/realtime',
      );
    });

    test('tolerates a trailing slash without doubling it', () {
      expect(
        sidebandWebSocketUri(Uri.parse('https://example.run.app/')).toString(),
        'wss://example.run.app/v1/realtime',
      );
    });

    test('maps http to ws for a local sideband', () {
      expect(
        sidebandWebSocketUri(Uri.parse('http://localhost:8080')).toString(),
        'ws://localhost:8080/v1/realtime',
      );
    });

    test('rejects a scheme that cannot be upgraded', () {
      expect(
        () => sidebandWebSocketUri(Uri.parse('ftp://example.com')),
        throwsArgumentError,
      );
    });
  });
}
