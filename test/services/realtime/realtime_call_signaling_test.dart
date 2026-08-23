import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/realtime/realtime_call_signaling.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('parseCallIdFromLocation', () {
    test('extracts the rtc_ id from the documented header shape', () {
      expect(
        parseCallIdFromLocation('/v1/realtime/calls/rtc_abc123'),
        'rtc_abc123',
      );
    });

    test('tolerates an absolute url, a trailing slash and a query', () {
      expect(
        parseCallIdFromLocation(
          'https://api.openai.com/v1/realtime/calls/rtc_abc123?x=1',
        ),
        'rtc_abc123',
      );
      expect(
        parseCallIdFromLocation('/v1/realtime/calls/rtc_abc123/'),
        'rtc_abc123',
      );
    });

    test('refuses anything that is not an rtc_ segment', () {
      expect(parseCallIdFromLocation(null), isNull);
      expect(parseCallIdFromLocation(''), isNull);
      expect(parseCallIdFromLocation('/v1/realtime/calls/'), isNull);
      expect(parseCallIdFromLocation('/v1/realtime/calls/sess_abc'), isNull);
      expect(parseCallIdFromLocation('/v1/realtime/calls/rtc_'), isNull);
    });
  });

  group('HttpRealtimeCallSignaling', () {
    final url = Uri.parse('https://api.openai.com/v1/realtime/calls');

    test('posts the offer as application/sdp with the ephemeral key', () async {
      late http.Request captured;
      final signaling = HttpRealtimeCallSignaling(
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            'v=0\r\no=- 1 1 IN IP4 0.0.0.0\r\n',
            201,
            headers: {'location': '/v1/realtime/calls/rtc_abc'},
          );
        }),
      );

      final session = await signaling.exchangeOffer(
        url: url,
        clientSecret: 'ek_secret',
        offerSdp: 'offer-sdp',
      );

      expect(captured.method, 'POST');
      expect(captured.body, 'offer-sdp');
      expect(captured.headers['Authorization'], 'Bearer ek_secret');
      expect(captured.headers['Content-Type'], contains('application/sdp'));
      expect(session.callId, 'rtc_abc');
      expect(session.answerSdp, 'v=0\r\no=- 1 1 IN IP4 0.0.0.0\r\n');
    });

    test('the answer keeps its terminal newline and CRLF endings', () async {
      // darwin libwebrtc rejects an SDP whose final newline was stripped —
      // trimming here once caused "setRemoteDescription: Error
      // SessionDescription is NULL." on iOS. See
      // integration_test/realtime_sdp_parse_test.dart.
      final signaling = HttpRealtimeCallSignaling(
        client: MockClient(
          (_) async => http.Response(
            'v=0\r\ns=-\r\n',
            201,
            headers: {'location': '/v1/realtime/calls/rtc_abc'},
          ),
        ),
      );

      final session = await signaling.exchangeOffer(
        url: url,
        clientSecret: 'ek',
        offerSdp: 'offer',
      );

      expect(session.answerSdp, endsWith('\n'));
      expect(session.answerSdp, 'v=0\r\ns=-\r\n');
    });

    test('an answer missing its terminal newline gets one appended', () async {
      final signaling = HttpRealtimeCallSignaling(
        client: MockClient(
          (_) async => http.Response(
            'v=0\r\ns=-',
            201,
            headers: {'location': '/v1/realtime/calls/rtc_abc'},
          ),
        ),
      );

      final session = await signaling.exchangeOffer(
        url: url,
        clientSecret: 'ek',
        offerSdp: 'offer',
      );

      expect(session.answerSdp, 'v=0\r\ns=-\n');
    });

    test('a non-SDP answer body fails with the first line quoted', () async {
      final signaling = HttpRealtimeCallSignaling(
        client: MockClient(
          (_) async => http.Response(
            '{"error":{"message":"bad request"}}',
            201,
            headers: {'location': '/v1/realtime/calls/rtc_abc'},
          ),
        ),
      );

      await expectLater(
        signaling.exchangeOffer(
          url: url,
          clientSecret: 'ek',
          offerSdp: 'offer',
        ),
        throwsA(
          isA<RealtimeSignalingException>().having(
            (e) => e.message,
            'message',
            contains('{"error"'),
          ),
        ),
      );
    });

    test('a non-2xx status fails', () async {
      final signaling = HttpRealtimeCallSignaling(
        client: MockClient((_) async => http.Response('nope', 403)),
      );

      await expectLater(
        signaling.exchangeOffer(
          url: url,
          clientSecret: 'ek',
          offerSdp: 'offer',
        ),
        throwsA(isA<RealtimeSignalingException>()),
      );
    });

    test(
      'a missing Location header fails rather than inventing a call',
      () async {
        final signaling = HttpRealtimeCallSignaling(
          client: MockClient((_) async => http.Response('answer-sdp', 201)),
        );

        await expectLater(
          signaling.exchangeOffer(
            url: url,
            clientSecret: 'ek',
            offerSdp: 'offer',
          ),
          throwsA(isA<RealtimeSignalingException>()),
        );
      },
    );

    test('an empty answer fails', () async {
      final signaling = HttpRealtimeCallSignaling(
        client: MockClient(
          (_) async => http.Response(
            '',
            201,
            headers: {'location': '/v1/realtime/calls/rtc_abc'},
          ),
        ),
      );

      await expectLater(
        signaling.exchangeOffer(
          url: url,
          clientSecret: 'ek',
          offerSdp: 'offer',
        ),
        throwsA(isA<RealtimeSignalingException>()),
      );
    });

    test('a transport failure surfaces as a signaling exception', () async {
      final signaling = HttpRealtimeCallSignaling(
        client: MockClient((_) async => throw Exception('offline')),
      );

      await expectLater(
        signaling.exchangeOffer(
          url: url,
          clientSecret: 'ek',
          offerSdp: 'offer',
        ),
        throwsA(isA<RealtimeSignalingException>()),
      );
    });
  });
}
