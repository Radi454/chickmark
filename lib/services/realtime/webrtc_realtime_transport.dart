import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'realtime_transport.dart';

/// Opens the microphone. Injected so unit tests can drive the transport
/// without a platform channel.
typedef RealtimeGetUserMedia =
    Future<MediaStream> Function(Map<String, dynamic> constraints);

/// Creates the peer connection. Injected for the same reason.
typedef RealtimeCreatePeerConnection =
    Future<RTCPeerConnection> Function(
      Map<String, dynamic> configuration,
      Map<String, dynamic> constraints,
    );

typedef RealtimeConfigureCallAudio = Future<void> Function();
typedef RealtimeReleaseCallAudio = Future<void> Function();

/// The only class in the app that touches `flutter_webrtc`.
///
/// Read [RealtimeTransport]'s docs first: the split between [openMicrophone],
/// [addSilentAudioTransceiver] and [startTransmitting] is the security
/// invariant, not an implementation detail.
class WebRtcRealtimeTransport implements RealtimeTransport {
  WebRtcRealtimeTransport({
    RealtimeGetUserMedia? getUserMedia,
    RealtimeCreatePeerConnection? createPeerConnection,
    RealtimeConfigureCallAudio? configureCallAudio,
    RealtimeReleaseCallAudio? releaseCallAudio,
    List<Map<String, dynamic>>? iceServers,
    String eventChannelLabel = 'oai-events',
  }) : _getUserMedia =
           getUserMedia ??
           ((constraints) => navigator.mediaDevices.getUserMedia(constraints)),
       _createPeerConnection =
           createPeerConnection ?? _defaultCreatePeerConnection,
       _configureCallAudio =
           configureCallAudio ??
           (() => Helper.setAppleAudioIOMode(AppleAudioIOMode.localAndRemote)),
       _releaseCallAudio =
           releaseCallAudio ??
           (() => Helper.setAppleAudioIOMode(AppleAudioIOMode.none)),
       _iceServers =
           iceServers ??
           const <Map<String, dynamic>>[
             {'urls': 'stun:stun.l.google.com:19302'},
           ],
       _eventChannelLabel = eventChannelLabel;

  final RealtimeGetUserMedia _getUserMedia;
  final RealtimeCreatePeerConnection _createPeerConnection;
  final RealtimeConfigureCallAudio _configureCallAudio;
  final RealtimeReleaseCallAudio _releaseCallAudio;
  final List<Map<String, dynamic>> _iceServers;
  final String _eventChannelLabel;

  MediaStream? _micStream;
  MediaStreamTrack? _micTrack;
  RTCPeerConnection? _peerConnection;
  RTCRtpTransceiver? _transceiver;
  RTCDataChannel? _dataChannel;
  bool _isTransmitting = false;
  bool _disposed = false;
  bool _callAudioConfigured = false;
  Future<void>? _microphoneAcquisition;

  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<RealtimeConnectionState> _connectionStates =
      StreamController<RealtimeConnectionState>.broadcast();

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  @override
  Stream<RealtimeConnectionState> get connectionStates =>
      _connectionStates.stream;

  @override
  bool get isTransmitting => _isTransmitting;

  @override
  bool get isMicrophoneEnabled => _micTrack?.enabled ?? false;

  @override
  Future<void> openMicrophone() {
    if (_micTrack != null) return Future<void>.value();
    final acquisition = _microphoneAcquisition;
    if (acquisition != null) return acquisition;
    final opening = _openMicrophone();
    _microphoneAcquisition = opening;
    return opening.whenComplete(() {
      if (identical(_microphoneAcquisition, opening)) {
        _microphoneAcquisition = null;
      }
    });
  }

  Future<void> _openMicrophone() async {
    MediaStream stream;
    try {
      await _configureCallAudio();
      _callAudioConfigured = true;
      stream = await _getUserMedia(const <String, dynamic>{
        'audio': true,
        'video': false,
      });
    } catch (error) {
      await _releaseConfiguredAudio();
      throw RealtimeMicPermissionException(
        'ChickMark needs microphone access for live voice. '
        'Enable it in Settings and try again.',
      );
    }
    if (_disposed) {
      await _releaseReturnedMicrophone(stream);
      return;
    }
    final tracks = stream.getAudioTracks();
    if (tracks.isEmpty) {
      await stream.dispose();
      await _releaseConfiguredAudio();
      throw const RealtimeMicPermissionException(
        'No microphone was available for live voice.',
      );
    }
    _micStream = stream;
    // NOTE: the track is held here and nowhere else. It is deliberately never
    // passed to addTrack() or to addTransceiver()'s `track:` argument.
    _micTrack = tracks.first;
  }

  @override
  Future<void> createConnection() async {
    if (_peerConnection != null) return;
    final connection = await _createPeerConnection(<String, dynamic>{
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
    }, const <String, dynamic>{});
    connection.onConnectionState = (state) {
      if (_connectionStates.isClosed) return;
      _connectionStates.add(_mapConnectionState(state));
    };
    _peerConnection = connection;
  }

  @override
  Future<void> addSilentAudioTransceiver() async {
    final connection = _requireConnection();
    if (_transceiver != null) return;
    // NO `track:` argument. This is the whole mechanism: the sender exists,
    // the m-line is negotiated as sendrecv, and the null track means zero RTP
    // until replaceTrack() swaps a real source in.
    _transceiver = await connection.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
    );
  }

  @override
  Future<void> openEventChannel() async {
    final connection = _requireConnection();
    if (_dataChannel != null) return;
    final channel = await connection.createDataChannel(
      _eventChannelLabel,
      RTCDataChannelInit(),
    );
    channel.onMessage = (message) {
      if (message.isBinary) return;
      final decoded = _decodeEvent(message.text);
      if (decoded == null) return;
      if (_events.isClosed) return;
      _events.add(decoded);
    };
    _dataChannel = channel;
  }

  @override
  Future<String> createOffer() async {
    final connection = _requireConnection();
    final offer = await connection.createOffer(const <String, dynamic>{});
    await connection.setLocalDescription(offer);
    final sdp = offer.sdp;
    if (sdp == null || sdp.isEmpty) {
      throw const RealtimeTransportException(
        'Could not start the live call. Please try again.',
      );
    }
    return sdp;
  }

  @override
  Future<void> acceptAnswer(String sdp) async {
    final connection = _requireConnection();
    await connection.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
  }

  @override
  Future<void> startTransmitting() async {
    if (_isTransmitting) return;
    final sender = _transceiver?.sender;
    final track = _micTrack;
    if (sender == null || track == null) {
      throw const RealtimeTransportException(
        'The live call was not ready to send audio.',
      );
    }
    // replaceTrack does not renegotiate — nothing goes on the wire, and
    // transmission starts exactly here.
    await sender.replaceTrack(track);
    _isTransmitting = true;
  }

  @override
  Future<void> stopTransmitting() async {
    if (!_isTransmitting) return;
    _isTransmitting = false;
    await _transceiver?.sender.replaceTrack(null);
  }

  @override
  void setMicrophoneEnabled(bool enabled) {
    final track = _micTrack;
    if (track == null) return;
    // UX mute only. See RealtimeTransport's docs for why this can never be
    // the pre-READY control.
    track.enabled = enabled;
  }

  @override
  Future<List<RealtimeOutboundAudioReport>> outboundAudioReports() async {
    final connection = _peerConnection;
    if (connection == null) return const <RealtimeOutboundAudioReport>[];
    final reports = await connection.getStats();
    return reports
        .where(
          (report) =>
              report.type == 'outbound-rtp' && report.values['kind'] == 'audio',
        )
        .map(
          (report) => RealtimeOutboundAudioReport(
            packetsSent: _asInt(report.values['packetsSent']),
            bytesSent: _asInt(report.values['bytesSent']),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final acquisition = _microphoneAcquisition;
    if (acquisition != null) {
      await _quietly(() async => await acquisition);
    }
    // Detach the source first so nothing can be sampled mid-teardown.
    await _quietly(() async {
      if (_isTransmitting) {
        _isTransmitting = false;
        await _transceiver?.sender.replaceTrack(null);
      }
    });
    await _quietly(() async {
      _dataChannel?.onMessage = null;
      await _dataChannel?.close();
    });
    // Order matters: stop() releases the OS microphone. Skipping it leaves
    // the iOS recording indicator lit for the rest of the app session.
    await _quietly(() async => _micTrack?.stop());
    await _releaseConfiguredAudio();
    await _quietly(() async => _micStream?.dispose());
    await _quietly(() async {
      _peerConnection?.onConnectionState = null;
      await _peerConnection?.close();
    });
    await _quietly(() async => _peerConnection?.dispose());
    _dataChannel = null;
    _transceiver = null;
    _micTrack = null;
    _micStream = null;
    _peerConnection = null;
    await _events.close();
    await _connectionStates.close();
  }

  /// Defined as a static so the global `createPeerConnection` is not shadowed
  /// by the constructor parameter of the same name.
  static Future<RTCPeerConnection> _defaultCreatePeerConnection(
    Map<String, dynamic> configuration,
    Map<String, dynamic> constraints,
  ) => createPeerConnection(configuration, constraints);

  RTCPeerConnection _requireConnection() {
    final connection = _peerConnection;
    if (connection == null) {
      throw const RealtimeTransportException(
        'The live call was not connected yet.',
      );
    }
    return connection;
  }

  static Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Teardown is best-effort: one failing release must not strand the rest.
    }
  }

  Future<void> _releaseReturnedMicrophone(MediaStream stream) async {
    for (final track in stream.getAudioTracks()) {
      await _quietly(track.stop);
    }
    await _releaseConfiguredAudio();
    await _quietly(stream.dispose);
  }

  Future<void> _releaseConfiguredAudio() async {
    if (!_callAudioConfigured) return;
    _callAudioConfigured = false;
    await _quietly(_releaseCallAudio);
  }

  static Map<String, dynamic>? _decodeEvent(String text) {
    try {
      final raw = jsonDecode(text);
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {
      // Unparseable frames are dropped silently, like unknown event types.
    }
    return null;
  }

  static int? _asInt(Object? value) => value is num
      ? value.toInt()
      : (value is String ? int.tryParse(value) : null);

  static RealtimeConnectionState _mapConnectionState(
    RTCPeerConnectionState state,
  ) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return RealtimeConnectionState.connected;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        return RealtimeConnectionState.failed;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return RealtimeConnectionState.disconnected;
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        return RealtimeConnectionState.closed;
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        return RealtimeConnectionState.connecting;
    }
  }
}
