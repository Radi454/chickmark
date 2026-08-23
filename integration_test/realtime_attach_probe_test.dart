// EXPERIMENT (run on macOS, needs network + OPENAI_KEY dart-define):
//
//   flutter test integration_test/realtime_attach_probe_test.dart -d macos \
//     --dart-define=OPENAI_KEY=sk-...
//
// Question it answers: which bearer does the sideband attach
// (wss://api.openai.com/v1/realtime?call_id=...) accept for a call that is
// genuinely LIVE (real ICE/DTLS from this machine)?
//
// Production evidence 2026-08-17: standard-key attach returns 404
// "No session found for the provided call_id" on live calls; OpenAI's docs
// say standard key, a community thread with the same 404 says ephemeral key.
// Canned-offer calls die instantly (no DTLS), so only a real connected call
// can discriminate. This test builds one with flutter_webrtc — the same
// engine the iPhone app ships — and probes both bearers with dart:io
// WebSockets (which, unlike the browser API, can send an Authorization
// header).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:integration_test/integration_test.dart';

const String _key = String.fromEnvironment('OPENAI_KEY');

Future<String> _probeAttach(String callId, String bearer, String label) async {
  try {
    final socket = await WebSocket.connect(
      'wss://api.openai.com/v1/realtime?call_id=$callId',
      headers: <String, String>{'Authorization': 'Bearer $bearer'},
    ).timeout(const Duration(seconds: 15));
    // Exercise the exact production semantics: send a session.update and
    // require the session.updated acknowledgement.
    final events = <String>[];
    final acked = Completer<void>();
    final sub = socket.listen((dynamic frame) {
      if (frame is! String) return;
      final decoded = jsonDecode(frame) as Map<String, dynamic>;
      final type = (decoded['type'] ?? '?') as String;
      events.add(type);
      if (type == 'error') {
        // The whole point of this probe: the provider names the exact field.
        // ignore: avoid_print
        print('PROVIDER ERROR DETAIL: ${jsonEncode(decoded['error'])}');
      }
      if (type == 'session.updated' && !acked.isCompleted) acked.complete();
    });
    // The EXACT production payload from services/pip-realtime-sideband/
    // src/session_config.ts buildSessionUpdate — kept in lockstep by hand so
    // an invalid_value here reproduces the production rejection verbatim.
    socket.add(jsonEncode(<String, dynamic>{
      'type': 'session.update',
      'session': <String, dynamic>{
        'type': 'realtime',
        'output_modalities': <String>['audio'],
        'audio': <String, dynamic>{
          'input': <String, dynamic>{
            'noise_reduction': <String, dynamic>{'type': 'near_field'},
            'transcription': <String, dynamic>{
              'model': 'gpt-4o-mini-transcribe',
              'prompt': 'ChickMark hatchery operations.',
            },
            'turn_detection': <String, dynamic>{
              'type': 'server_vad',
              'threshold': 0.5,
              'prefix_padding_ms': 300,
              'silence_duration_ms': 500,
              'create_response': true,
              'interrupt_response': true,
            },
          },
          'output': <String, dynamic>{'voice': 'cedar'},
        },
        'reasoning': <String, dynamic>{'effort': 'low'},
        'tool_choice': 'auto',
        'tools': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'function',
            'name': 'get_user_scope',
            'description': 'Return the enforced customer access.',
            'parameters': <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{},
              'required': <String>[],
            },
          },
        ],
        'instructions': 'You are a probe. Say nothing.',
      },
    }));
    await acked.future.timeout(const Duration(seconds: 15), onTimeout: () {});
    await sub.cancel();
    await socket.close();
    return '$label: ATTACHED, events: ${events.join(",")}'
        '${acked.isCompleted ? " (session.updated ACK OK)" : " (no ack)"}';
  } on WebSocketException catch (error) {
    return '$label: REJECTED ${error.message}';
  } on TimeoutException {
    return '$label: TIMEOUT';
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('live-call attach bearer experiment', () async {
    expect(_key, isNotEmpty, reason: 'pass --dart-define=OPENAI_KEY=...');

    // 1. Mint an ephemeral secret (long enough TTL to cover the experiment).
    final mint = await HttpClient().postUrl(
      Uri.parse('https://api.openai.com/v1/realtime/client_secrets'),
    );
    mint.headers.set('Authorization', 'Bearer $_key');
    mint.headers.contentType = ContentType.json;
    mint.write(jsonEncode(<String, dynamic>{
      'expires_after': <String, dynamic>{'anchor': 'created_at', 'seconds': 300},
      'session': <String, dynamic>{
        'type': 'realtime',
        'model': 'gpt-realtime-2.1-mini',
        'audio': <String, dynamic>{
          'output': <String, dynamic>{'voice': 'cedar'},
        },
      },
    }));
    final mintResponse = await mint.close();
    final mintBody =
        jsonDecode(await utf8.decoder.bind(mintResponse).join()) as Map<String, dynamic>;
    final ephemeral = mintBody['value'] as String;
    // ignore: avoid_print
    print('minted ephemeral secret (${ephemeral.substring(0, 3)}...)');

    // 2. Real peer connection with a real microphone-less audio transceiver.
    final connection = await createPeerConnection(<String, dynamic>{});
    await connection.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
    );
    await connection.createDataChannel('oai-events', RTCDataChannelInit());

    final gathered = Completer<void>();
    connection.onIceGatheringState = (RTCIceGatheringState state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !gathered.isCompleted) {
        gathered.complete();
      }
    };
    final connected = Completer<void>();
    connection.onConnectionState = (RTCPeerConnectionState state) {
      // ignore: avoid_print
      print('pc state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
          !connected.isCompleted) {
        connected.complete();
      }
    };

    final offer = await connection.createOffer();
    await connection.setLocalDescription(offer);
    await gathered.future.timeout(const Duration(seconds: 10));
    final localSdp = (await connection.getLocalDescription())!.sdp!;

    // 3. Create the call with the ephemeral secret, exactly like the app.
    final call = await HttpClient().postUrl(
      Uri.parse('https://api.openai.com/v1/realtime/calls'),
    );
    call.headers.set('Authorization', 'Bearer $ephemeral');
    call.headers.set('Content-Type', 'application/sdp');
    call.write(localSdp);
    final callResponse = await call.close();
    final answerSdp = await utf8.decoder.bind(callResponse).join();
    final location = callResponse.headers.value('location') ?? '';
    final callId = location.split('/').last;
    // ignore: avoid_print
    print('call created: $callId (http ${callResponse.statusCode})');
    expect(callResponse.statusCode, 201);
    expect(callId, startsWith('rtc_'));

    await connection.setRemoteDescription(RTCSessionDescription(
      answerSdp.endsWith('\n') ? answerSdp : '$answerSdp\n',
      'answer',
    ));

    // 4. Wait for the call to be genuinely live (DTLS complete).
    await connected.future.timeout(const Duration(seconds: 30));
    // ignore: avoid_print
    print('CALL IS LIVE. probing attach...');

    // 5. The experiment.
    // ignore: avoid_print
    print(await _probeAttach(callId, _key, 'standard-key'));
    // ignore: avoid_print
    print(await _probeAttach(callId, ephemeral, 'ephemeral-key'));

    // 6. Hang up.
    final hangup = await HttpClient().postUrl(
      Uri.parse('https://api.openai.com/v1/realtime/calls/$callId/hangup'),
    );
    hangup.headers.set('Authorization', 'Bearer $_key');
    final hangupResponse = await hangup.close();
    await hangupResponse.drain<void>();
    await connection.close();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
