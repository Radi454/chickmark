// Parses a REAL OpenAI Realtime answer SDP with the exact darwin libwebrtc
// build the iOS app ships (flutter_webrtc shares common/darwin between iOS and
// macOS). Exists because a device failure surfaced as
// "setRemoteDescription: Error SessionDescription is NULL." — which libwebrtc
// emits when SDP PARSING fails, not when the string is null. The answer below
// was captured verbatim from POST /v1/realtime/calls on 2026-08-17.
//
// Run with: flutter test integration_test/realtime_sdp_parse_test.dart -d macos
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:integration_test/integration_test.dart';

const List<String> _answerLines = <String>[
  r'v=0',
  r'o=- 8184931122902577674 1786967632 IN IP4 0.0.0.0',
  r's=-',
  r't=0 0',
  r'a=msid-semantic:WMS *',
  r'a=fingerprint:sha-256 A8:BB:42:19:E4:4E:70:0E:E5:80:DE:40:BB:57:E8:B5:A6:1E:8E:ED:D0:CE:A8:0B:2E:98:93:F0:9D:2E:44:6E',
  r'a=ice-lite',
  r'a=extmap-allow-mixed',
  r'a=group:BUNDLE 0 1',
  r'm=audio 9 UDP/TLS/RTP/SAVPF 111',
  r'c=IN IP4 0.0.0.0',
  r'a=setup:active',
  r'a=mid:0',
  r'a=ice-ufrag:NGikpJ/u0/3oN5GD',
  r'a=ice-pwd:ZrAgINTcLMJzFyMkNRgHkP3eSB1FLxwd',
  r'a=rtcp-mux',
  r'a=rtcp-rsize',
  r'a=rtpmap:111 opus/48000/2',
  r'a=fmtp:111 minptime=10;useinbandfec=1',
  r'a=ssrc:1190514604 cname:realtimeapi',
  r'a=ssrc:1190514604 msid:realtimeapi audio',
  r'a=ssrc:1190514604 mslabel:realtimeapi',
  r'a=ssrc:1190514604 label:audio',
  r'a=msid:realtimeapi audio',
  r'a=sendrecv',
  r'a=candidate:3506478603 1 udp 2130706431 51.4.112.173 3478 typ host ufrag NGikpJ/u0/3oN5GD',
  r'a=candidate:3717646455 1 tcp 1671430143 51.4.112.173 443 typ host tcptype passive ufrag NGikpJ/u0/3oN5GD',
  r'a=candidate:1918949051 1 udp 2130706431 20.74.221.21 3478 typ host ufrag NGikpJ/u0/3oN5GD',
  r'a=candidate:3641609583 1 tcp 1671430143 20.74.221.21 443 typ host tcptype passive ufrag NGikpJ/u0/3oN5GD',
  r'a=candidate:328466154 1 udp 2130706431 72.146.20.246 3478 typ host ufrag NGikpJ/u0/3oN5GD',
  r'a=candidate:2559899422 1 tcp 1671430143 72.146.20.246 443 typ host tcptype passive ufrag NGikpJ/u0/3oN5GD',
  r'm=application 9 UDP/DTLS/SCTP webrtc-datachannel',
  r'c=IN IP4 0.0.0.0',
  r'a=setup:active',
  r'a=mid:1',
  r'a=sendrecv',
  r'a=sctp-port:5000',
  r'a=max-message-size:1073741823',
  r'a=ice-ufrag:NGikpJ/u0/3oN5GD',
  r'a=ice-pwd:ZrAgINTcLMJzFyMkNRgHkP3eSB1FLxwd',
];

Future<RTCPeerConnection> _connectionWithLocalOffer() async {
  final pc = await createPeerConnection(<String, dynamic>{});
  await pc.addTransceiver(
    kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
    init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
  );
  await pc.createDataChannel('oai-events', RTCDataChannelInit());
  final offer = await pc.createOffer(<String, dynamic>{});
  await pc.setLocalDescription(offer);
  return pc;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('darwin libwebrtc parses the OpenAI answer with CRLF endings',
      (tester) async {
    final pc = await _connectionWithLocalOffer();
    final sdp = '${_answerLines.join('\r\n')}\r\n';
    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    await pc.close();
  });

  testWidgets('darwin libwebrtc REJECTS the answer without a final newline',
      (tester) async {
    // This is the outage: the client used to .trim() the response body,
    // stripping the terminal newline, and darwin libwebrtc refuses to parse
    // an SDP whose last line is unterminated ("SessionDescription is NULL.").
    // The signaling layer now guarantees the newline instead. If this test
    // ever starts passing, libwebrtc became tolerant and the guarantee is
    // merely redundant — not wrong.
    final pc = await _connectionWithLocalOffer();
    final sdp = _answerLines.join('\r\n');
    await expectLater(
      pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer')),
      throwsA(anything),
    );
    await pc.close();
  });

  testWidgets('darwin libwebrtc parses the answer with bare LF endings',
      (tester) async {
    final pc = await _connectionWithLocalOffer();
    final sdp = '${_answerLines.join('\n')}\n';
    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    await pc.close();
  });
}
