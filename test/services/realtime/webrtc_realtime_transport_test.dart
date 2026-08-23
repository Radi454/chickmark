import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hatchaudit/services/realtime/realtime_transport.dart';
import 'package:hatchaudit/services/realtime/webrtc_realtime_transport.dart';

/// Shared ordered log so teardown ordering can be asserted across objects.
late List<String> log;

class _FakeTrack extends Fake implements MediaStreamTrack {
  final String trackKind = 'audio';
  bool _enabled = true;
  bool stopped = false;

  @override
  String? get kind => trackKind;

  @override
  String? get id => 'track-1';

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) {
    _enabled = value;
    log.add('track.enabled=$value');
  }

  @override
  Future<void> stop() async {
    stopped = true;
    log.add('track.stop');
  }
}

class _FakeStream extends Fake implements MediaStream {
  _FakeStream(this.tracks);

  final List<MediaStreamTrack> tracks;
  bool disposed = false;

  @override
  List<MediaStreamTrack> getAudioTracks() =>
      tracks.where((track) => track.kind == 'audio').toList();

  @override
  Future<void> dispose() async {
    disposed = true;
    log.add('stream.dispose');
  }
}

class _FakeSender extends Fake implements RTCRtpSender {
  MediaStreamTrack? currentTrack;
  final List<MediaStreamTrack?> replaceTrackCalls = <MediaStreamTrack?>[];

  @override
  MediaStreamTrack? get track => currentTrack;

  @override
  Future<void> replaceTrack(MediaStreamTrack? track) async {
    replaceTrackCalls.add(track);
    currentTrack = track;
    log.add('sender.replaceTrack(${track == null ? 'null' : 'track'})');
  }
}

class _FakeTransceiver extends Fake implements RTCRtpTransceiver {
  _FakeTransceiver(this.fakeSender);

  final _FakeSender fakeSender;

  @override
  RTCRtpSender get sender => fakeSender;
}

class _FakeDataChannel extends Fake implements RTCDataChannel {
  Function(RTCDataChannelMessage data)? _onMessage;
  bool closed = false;

  @override
  set onMessage(Function(RTCDataChannelMessage data)? value) =>
      _onMessage = value;

  @override
  Function(RTCDataChannelMessage data)? get onMessage => _onMessage;

  @override
  Future<void> close() async {
    closed = true;
    log.add('channel.close');
  }

  void deliver(String text) => _onMessage?.call(RTCDataChannelMessage(text));
}

class _FakePeerConnection extends Fake implements RTCPeerConnection {
  _FakePeerConnection({this.stats = const <StatsReport>[]});

  final List<StatsReport> stats;
  final _FakeSender sender = _FakeSender();
  late final _FakeTransceiver transceiver = _FakeTransceiver(sender);
  final _FakeDataChannel dataChannel = _FakeDataChannel();

  Function(RTCPeerConnectionState state)? _onConnectionState;
  MediaStreamTrack? addTransceiverTrack;
  bool addTransceiverCalled = false;
  TransceiverDirection? addTransceiverDirection;
  RTCRtpMediaType? addTransceiverKind;
  String? dataChannelLabel;
  RTCSessionDescription? localDescription;
  RTCSessionDescription? remoteDescription;
  bool closed = false;
  bool disposed = false;
  Object? closeError;

  @override
  set onConnectionState(Function(RTCPeerConnectionState state)? value) =>
      _onConnectionState = value;

  @override
  Function(RTCPeerConnectionState state)? get onConnectionState =>
      _onConnectionState;

  void emitConnectionState(RTCPeerConnectionState state) =>
      _onConnectionState?.call(state);

  @override
  Future<RTCRtpTransceiver> addTransceiver({
    MediaStreamTrack? track,
    RTCRtpMediaType? kind,
    RTCRtpTransceiverInit? init,
  }) async {
    addTransceiverCalled = true;
    addTransceiverTrack = track;
    addTransceiverKind = kind;
    addTransceiverDirection = init?.direction;
    return transceiver;
  }

  @override
  Future<RTCRtpSender> addTrack(MediaStreamTrack track, [MediaStream? stream]) {
    fail('addTrack must never be called: it would attach the mic pre-READY.');
  }

  @override
  Future<RTCDataChannel> createDataChannel(
    String label,
    RTCDataChannelInit dataChannelDict,
  ) async {
    dataChannelLabel = label;
    return dataChannel;
  }

  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async => RTCSessionDescription('offer-sdp', 'offer');

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    localDescription = description;
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    remoteDescription = description;
  }

  @override
  Future<List<StatsReport>> getStats([MediaStreamTrack? track]) async => stats;

  @override
  Future<void> close() async {
    closed = true;
    log.add('pc.close');
    final error = closeError;
    if (error != null) throw error;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    log.add('pc.dispose');
  }
}

void main() {
  late _FakeTrack track;
  late _FakeStream stream;
  late _FakePeerConnection peerConnection;
  late List<Map<String, dynamic>> getUserMediaCalls;

  WebRtcRealtimeTransport build({
    List<StatsReport> stats = const <StatsReport>[],
    Object? getUserMediaError,
    Completer<MediaStream>? getUserMediaGate,
    List<MediaStreamTrack>? tracks,
    Future<void> Function()? configureCallAudio,
    Future<void> Function()? releaseCallAudio,
  }) {
    track = _FakeTrack();
    stream = _FakeStream(tracks ?? <MediaStreamTrack>[track]);
    peerConnection = _FakePeerConnection(stats: stats);
    return WebRtcRealtimeTransport(
      configureCallAudio: configureCallAudio,
      releaseCallAudio: releaseCallAudio,
      getUserMedia: (constraints) async {
        log.add('getUserMedia');
        getUserMediaCalls.add(constraints);
        if (getUserMediaGate != null) return getUserMediaGate.future;
        if (getUserMediaError != null) throw getUserMediaError;
        return stream;
      },
      createPeerConnection: (_, _) async => peerConnection,
    );
  }

  Future<WebRtcRealtimeTransport> negotiated({
    List<StatsReport> stats = const <StatsReport>[],
  }) async {
    final transport = build(stats: stats);
    await transport.openMicrophone();
    await transport.createConnection();
    await transport.addSilentAudioTransceiver();
    await transport.openEventChannel();
    await transport.createOffer();
    await transport.acceptAnswer('answer-sdp');
    return transport;
  }

  setUp(() {
    log = <String>[];
    getUserMediaCalls = <Map<String, dynamic>>[];
  });

  group('the null-track transceiver', () {
    test('addTransceiver is called with NO track and sendrecv', () async {
      final transport = await negotiated();

      expect(peerConnection.addTransceiverCalled, isTrue);
      // The whole security invariant in one assertion: the sender exists but
      // has no source, so it emits zero RTP by spec.
      expect(peerConnection.addTransceiverTrack, isNull);
      expect(
        peerConnection.addTransceiverKind,
        RTCRtpMediaType.RTCRtpMediaTypeAudio,
      );
      expect(
        peerConnection.addTransceiverDirection,
        TransceiverDirection.SendRecv,
      );
      expect(peerConnection.sender.currentTrack, isNull);
      await transport.dispose();
    });

    test('negotiating does not attach the mic track', () async {
      final transport = await negotiated();

      expect(transport.isTransmitting, isFalse);
      expect(peerConnection.sender.replaceTrackCalls, isEmpty);
      expect(peerConnection.localDescription?.sdp, 'offer-sdp');
      expect(peerConnection.remoteDescription?.sdp, 'answer-sdp');
      await transport.dispose();
    });

    test('startTransmitting attaches the mic track exactly once', () async {
      final transport = await negotiated();

      await transport.startTransmitting();
      await transport.startTransmitting();
      await transport.startTransmitting();

      expect(peerConnection.sender.replaceTrackCalls, <Object?>[track]);
      expect(transport.isTransmitting, isTrue);
      await transport.dispose();
    });

    test('stopTransmitting replaces the track with null', () async {
      final transport = await negotiated();
      await transport.startTransmitting();

      await transport.stopTransmitting();
      await transport.stopTransmitting();

      expect(peerConnection.sender.replaceTrackCalls, <Object?>[track, null]);
      expect(transport.isTransmitting, isFalse);
      await transport.dispose();
    });

    test('startTransmitting throws when nothing was negotiated', () async {
      final transport = build();
      await transport.openMicrophone();
      await transport.createConnection();

      expect(
        () => transport.startTransmitting(),
        throwsA(isA<RealtimeTransportException>()),
      );
      await transport.dispose();
    });
  });

  group('microphone acquisition', () {
    test(
      'late microphone acquisition after dispose releases returned media',
      () async {
        final gate = Completer<MediaStream>();
        final transport = build(
          getUserMediaGate: gate,
          releaseCallAudio: () async => log.add('audio.release'),
        );
        final opening = transport.openMicrophone();
        await Future<void>.delayed(Duration.zero);

        final disposing = transport.dispose();
        gate.complete(stream);
        await opening;
        await disposing;

        expect(log, <String>[
          'getUserMedia',
          'track.stop',
          'audio.release',
          'stream.dispose',
        ]);
        expect(transport.isMicrophoneEnabled, isFalse);
      },
    );
    test('configures call audio before acquiring the microphone', () async {
      final transport = build(
        configureCallAudio: () async => log.add('audio.configure'),
      );

      await transport.openMicrophone();

      expect(log, <String>['audio.configure', 'getUserMedia']);
      await transport.dispose();
    });
    test('asks for audio only and keeps the track unattached', () async {
      final transport = build();
      await transport.openMicrophone();

      expect(getUserMediaCalls.single, {'audio': true, 'video': false});
      expect(transport.isTransmitting, isFalse);
      await transport.dispose();
    });

    test('a getUserMedia failure surfaces as a permission exception', () async {
      final transport = build(getUserMediaError: Exception('denied'));

      await expectLater(
        transport.openMicrophone(),
        throwsA(isA<RealtimeMicPermissionException>()),
      );
      await transport.dispose();
    });

    test('no audio track surfaces as a permission exception', () async {
      final transport = build(tracks: <MediaStreamTrack>[]);

      await expectLater(
        transport.openMicrophone(),
        throwsA(isA<RealtimeMicPermissionException>()),
      );
      await transport.dispose();
    });
  });

  group('outbound audio stats', () {
    test('filters to outbound-rtp audio reports', () async {
      final transport = await negotiated(
        stats: <StatsReport>[
          StatsReport('a', 'outbound-rtp', 0, {
            'kind': 'audio',
            'packetsSent': 0,
          }),
          StatsReport('b', 'outbound-rtp', 0, {
            'kind': 'video',
            'packetsSent': 99,
          }),
          StatsReport('c', 'inbound-rtp', 0, {
            'kind': 'audio',
            'packetsReceived': 12,
          }),
        ],
      );

      final reports = await transport.outboundAudioReports();

      expect(reports, hasLength(1));
      expect(reports.single.packetsSent, 0);
      expect(noAudioHasBeenTransmitted(reports), isTrue);
      await transport.dispose();
    });

    test('an absent report still proves the invariant', () async {
      final transport = await negotiated();

      expect(
        noAudioHasBeenTransmitted(await transport.outboundAudioReports()),
        isTrue,
      );
      await transport.dispose();
    });

    test('a non-zero packetsSent breaks the invariant', () {
      expect(
        noAudioHasBeenTransmitted(const <RealtimeOutboundAudioReport>[
          RealtimeOutboundAudioReport(packetsSent: 3),
        ]),
        isFalse,
      );
    });
  });

  group('event channel', () {
    test('decodes JSON frames and drops junk', () async {
      final transport = await negotiated();
      final received = <Map<String, dynamic>>[];
      transport.events.listen(received.add);

      peerConnection.dataChannel.deliver(jsonEncode({'type': 'response.done'}));
      peerConnection.dataChannel.deliver('not json');
      peerConnection.dataChannel.deliver(jsonEncode([1, 2, 3]));
      await Future<void>.delayed(Duration.zero);

      expect(received, [
        {'type': 'response.done'},
      ]);
      expect(peerConnection.dataChannelLabel, 'oai-events');
      await transport.dispose();
    });

    test('maps peer connection states', () async {
      final transport = await negotiated();
      final states = <RealtimeConnectionState>[];
      transport.connectionStates.listen(states.add);

      peerConnection.emitConnectionState(
        RTCPeerConnectionState.RTCPeerConnectionStateConnected,
      );
      peerConnection.emitConnectionState(
        RTCPeerConnectionState.RTCPeerConnectionStateFailed,
      );
      await Future<void>.delayed(Duration.zero);

      expect(states, [
        RealtimeConnectionState.connected,
        RealtimeConnectionState.failed,
      ]);
      await transport.dispose();
    });
  });

  group('mute and teardown', () {
    test(
      'releases call audio after stopping the track despite later failures',
      () async {
        final transport = build(
          releaseCallAudio: () async => log.add('audio.release'),
        );
        await transport.openMicrophone();
        await transport.createConnection();
        peerConnection.closeError = Exception('later teardown failure');
        log.clear();

        await transport.dispose();

        expect(
          log.indexOf('track.stop'),
          lessThan(log.indexOf('audio.release')),
        );
        expect(log, contains('pc.close'));
      },
    );
    test('setMicrophoneEnabled only flips the track flag', () async {
      final transport = await negotiated();
      await transport.startTransmitting();

      transport.setMicrophoneEnabled(false);

      expect(track.enabled, isFalse);
      // Still transmitting: `enabled` is a UX mute, never the security gate.
      expect(transport.isTransmitting, isTrue);
      expect(peerConnection.sender.currentTrack, isNotNull);
      await transport.dispose();
    });

    test(
      'dispose releases everything in the order that frees the mic',
      () async {
        final transport = await negotiated();
        await transport.startTransmitting();
        log.clear();

        await transport.dispose();

        expect(log, <String>[
          'sender.replaceTrack(null)',
          'channel.close',
          'track.stop',
          'stream.dispose',
          'pc.close',
          'pc.dispose',
        ]);
        expect(track.stopped, isTrue);
        expect(stream.disposed, isTrue);
        expect(peerConnection.dataChannel.closed, isTrue);
        expect(peerConnection.closed, isTrue);
        expect(peerConnection.disposed, isTrue);
      },
    );

    test('dispose is idempotent', () async {
      final transport = await negotiated();
      await transport.dispose();
      log.clear();

      await transport.dispose();

      expect(log, isEmpty);
    });
  });
}
