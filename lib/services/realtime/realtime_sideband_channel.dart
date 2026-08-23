import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// The sideband control socket to the Cloud Run service.
///
/// The wire format is written down once, in
/// `services/pip-realtime-sideband/WIRE_CONTRACT.md`, and the server owns it:
/// every field is snake_case, the bind frame is the FIRST application frame,
/// and nothing else may be sent before it succeeds.
///
/// **Captions do not travel here.** Transcript deltas reach this app over its
/// own WebRTC data channel, straight from OpenAI — see
/// `realtime_client_event_policy.dart`. The sideband carries three notices and
/// nothing else.

/// What the Cloud Run sideband can tell the client.
///
/// The sideband is authoritative for the one thing this client cannot decide
/// for itself: when the call is safe to transmit on
/// ([RealtimeSidebandEventKind.ready]). Every tool call runs there, never here.
enum RealtimeSidebandEventKind {
  /// The authoritative go-ahead. The ONLY thing that may start transmission.
  ready,

  /// A fatal, user-visible failure. Carries a machine `code`.
  error,

  /// The server is closing the socket, or it already has.
  closing,

  /// Anything unrecognised. Dropped silently.
  unknown,
}

/// Why the socket closed, read off the WebSocket close code.
///
/// The three codes the UI must be able to tell apart are [bindTimeout],
/// [bindRejected] and [leaseLost]: "you took too long", "you may not have this
/// session" and "another worker owns this session now" are different problems
/// with different remedies.
enum RealtimeSidebandCloseCause {
  /// 4408 — no bind frame arrived in time.
  bindTimeout,

  /// 4401 — the bind frame was refused (identity, authorization, or a binding
  /// token that was wrong, expired or already spent).
  bindRejected,

  /// 4409 — the lease could not be claimed, or the fence moved under us.
  leaseLost,

  /// 4400 — this client sent something the server could not parse.
  malformed,

  /// 4503 — the instance is shutting down. A fresh session will land elsewhere.
  draining,

  /// 4500 — the server failed on its own side.
  internal,

  /// A normal close, or one this revision has no opinion about.
  normal,
}

RealtimeSidebandCloseCause sidebandCloseCauseFor(int? code) {
  switch (code) {
    case 4408:
      return RealtimeSidebandCloseCause.bindTimeout;
    case 4401:
      return RealtimeSidebandCloseCause.bindRejected;
    case 4409:
      return RealtimeSidebandCloseCause.leaseLost;
    case 4400:
      return RealtimeSidebandCloseCause.malformed;
    case 4503:
      return RealtimeSidebandCloseCause.draining;
    case 4500:
      return RealtimeSidebandCloseCause.internal;
    default:
      return RealtimeSidebandCloseCause.normal;
  }
}

/// User-facing text for a close cause. Server codes are machine strings and are
/// never shown raw.
String sidebandCloseMessage(RealtimeSidebandCloseCause cause) {
  switch (cause) {
    case RealtimeSidebandCloseCause.bindTimeout:
      return 'The live voice session took too long to connect. Please try again.';
    case RealtimeSidebandCloseCause.bindRejected:
      return 'The live voice session could not be authorised. Please try again.';
    case RealtimeSidebandCloseCause.leaseLost:
      return 'The live voice session was taken over elsewhere.';
    case RealtimeSidebandCloseCause.malformed:
      return 'The live voice session hit a protocol error.';
    case RealtimeSidebandCloseCause.draining:
      return 'The live voice service is restarting. Please try again.';
    case RealtimeSidebandCloseCause.internal:
      return 'The live voice service hit an error. Please try again.';
    case RealtimeSidebandCloseCause.normal:
      return 'The live voice session ended.';
  }
}

/// User-facing text for the machine `code` on an `error` notice. The codes are
/// the server's `BindFailure` values plus its connection-level reasons; they are
/// never shown raw.
String sidebandErrorMessage(String? code) {
  switch (code) {
    case 'invalid_token':
    case 'identity_mismatch':
    case 'unauthorized':
      return 'The live voice session could not be authorised. Please try again.';
    case 'binding_token_rejected':
    case 'unknown_session':
    case 'session_not_bindable':
    case 'call_not_registered':
      return 'The live voice session expired before it could start. Please try again.';
    case 'lease_unavailable':
    case 'fence_lost':
      return 'The live voice session was taken over elsewhere.';
    case 'kill_switch':
      return 'Live voice is switched off right now.';
    case 'malformed_frame':
    case 'bind_frame_required':
      return 'The live voice session hit a protocol error.';
    default:
      return 'The live voice session failed.';
  }
}

class RealtimeSidebandEvent {
  const RealtimeSidebandEvent({
    required this.kind,
    this.sessionId,
    this.generation,
    this.code,
    this.reason,
    this.cause,
  });

  final RealtimeSidebandEventKind kind;

  /// Present on READY (`session_id`). Checked against the current attempt
  /// before the event is honoured, so a late READY from an abandoned attempt
  /// is inert.
  final String? sessionId;

  /// The server-assigned attempt number. A READY naming a different
  /// generation belongs to an attempt this client has already abandoned.
  final int? generation;

  /// For [RealtimeSidebandEventKind.error]: the server's machine code.
  final String? code;

  /// For [RealtimeSidebandEventKind.closing]: the server's machine reason.
  final String? reason;

  /// For [RealtimeSidebandEventKind.closing] raised by the socket itself.
  final RealtimeSidebandCloseCause? cause;

  /// What the user is told. Never the raw server code.
  String get message =>
      cause != null ? sidebandCloseMessage(cause!) : sidebandErrorMessage(code);
}

/// The bind frame, encoded exactly as the server parses it.
///
/// Pinned by `test/services/realtime/realtime_sideband_channel_test.dart` and,
/// on the other side, by `parseBindFrame` in
/// `services/pip-realtime-sideband/src/binding.ts`. Key order and casing are
/// part of the contract; changing either breaks both tests, which is the point.
String encodeBindFrame({
  required String sessionId,
  required int generation,
  required String accessToken,
  required String bindingToken,
}) => jsonEncode(<String, dynamic>{
  'type': 'bind',
  'session_id': sessionId,
  'generation': generation,
  'access_token': accessToken,
  'binding_token': bindingToken,
});

/// The health frame, encoded exactly as the server parses it.
///
/// Pinned by `test/services/realtime/realtime_sideband_channel_test.dart` and,
/// on the other side, by the literal used in
/// `services/pip-realtime-sideband/test/server_test.ts` (`READY is withheld
/// until...`): the server ANDs `webrtc`/`data_channel` into
/// `webrtcHealthy`/`dataChannelHealthy` and will never announce READY without
/// this frame. There is only ever one shape to send — by the time the
/// sideband is bound, the WebRTC transport and the `oai-events` data channel
/// are already both up — so this is a literal, not a builder.
const String kSidebandHealthFrame =
    '{"type":"health","webrtc":true,"data_channel":true}';

/// Parses one sideband notice. Unknown shapes collapse to
/// [RealtimeSidebandEventKind.unknown] rather than throwing, so a server-side
/// addition can never crash a live call.
RealtimeSidebandEvent parseSidebandEvent(Map<String, dynamic> raw) {
  final type = raw['type']?.toString();
  switch (type) {
    case 'ready':
      return RealtimeSidebandEvent(
        kind: RealtimeSidebandEventKind.ready,
        sessionId: _text(raw['session_id']),
        generation: _integer(raw['generation']),
      );
    case 'error':
      return RealtimeSidebandEvent(
        kind: RealtimeSidebandEventKind.error,
        code: _text(raw['code']),
      );
    case 'closing':
      return RealtimeSidebandEvent(
        kind: RealtimeSidebandEventKind.closing,
        reason: _text(raw['reason']),
      );
    default:
      return const RealtimeSidebandEvent(
        kind: RealtimeSidebandEventKind.unknown,
      );
  }
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return (text == null || text.isEmpty) ? null : text;
}

int? _integer(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

class RealtimeSidebandException implements Exception {
  const RealtimeSidebandException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class RealtimeSidebandChannel {
  /// Opens the socket and sends the bind frame.
  ///
  /// [accessToken] is the caller's Supabase JWT and [bindingToken] the one-shot
  /// token from `pip-realtime-session start`; the sideband consumes the latter,
  /// so it is sent once and never retained. Both travel in the first
  /// application frame — never in the URL — and neither is ever logged.
  Future<void> bind({
    required Uri url,
    required String accessToken,
    required String bindingToken,
    required String sessionId,
    required int generation,
  });

  Stream<RealtimeSidebandEvent> get events;

  /// Sends the health notice ([kSidebandHealthFrame]): the client's report
  /// that its WebRTC transport and the `oai-events` data channel are both up.
  /// The server will never announce READY without it — see
  /// `WIRE_CONTRACT.md`. A no-op if the socket isn't open (bind never
  /// succeeded, or the channel has since closed).
  Future<void> sendHealth();

  Future<void> close();
}

/// The sideband's WebSocket route. The control plane hands back the service's
/// BASE url (it doubles as the Cloud Run OIDC audience, which must have no
/// path), so the client derives the socket url from it. See
/// `services/pip-realtime-sideband/WIRE_CONTRACT.md`.
const String kSidebandWebSocketPath = '/v1/realtime';

/// Turns the base service url into the socket url: `https` becomes `wss`,
/// `http` becomes `ws`, and the route is appended.
///
/// Connecting to the base url verbatim fails — the server only upgrades on
/// [kSidebandWebSocketPath], and `WebSocketChannel.connect` rejects an
/// `https` scheme outright.
Uri sidebandWebSocketUri(Uri base) {
  final scheme = switch (base.scheme) {
    'https' || 'wss' => 'wss',
    'http' || 'ws' => 'ws',
    _ => throw ArgumentError.value(
      base.toString(),
      'base',
      'sideband url must be http(s) or ws(s)',
    ),
  };
  final trimmed = base.path.endsWith('/')
      ? base.path.substring(0, base.path.length - 1)
      : base.path;
  return base.replace(scheme: scheme, path: '$trimmed$kSidebandWebSocketPath');
}

/// Opens the sideband over a WebSocket, sending one `bind` frame as its first
/// application frame.
class WebSocketRealtimeSidebandChannel implements RealtimeSidebandChannel {
  WebSocketRealtimeSidebandChannel({
    WebSocketChannel Function(Uri url)? connect,
  }) : _connect = connect ?? WebSocketChannel.connect;

  final WebSocketChannel Function(Uri url) _connect;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final StreamController<RealtimeSidebandEvent> _events =
      StreamController<RealtimeSidebandEvent>.broadcast();

  @override
  Stream<RealtimeSidebandEvent> get events => _events.stream;

  @override
  Future<void> bind({
    required Uri url,
    required String accessToken,
    required String bindingToken,
    required String sessionId,
    required int generation,
  }) async {
    if (_channel != null) return;
    WebSocketChannel channel;
    try {
      channel = _connect(sidebandWebSocketUri(url));
      await channel.ready;
    } catch (_) {
      throw const RealtimeSidebandException(
        'Could not connect the live voice session. Please try again.',
      );
    }
    _channel = channel;
    _subscription = channel.stream.listen(
      (frame) {
        if (frame is! String) return;
        final decoded = _decode(frame);
        if (decoded == null) return;
        final event = parseSidebandEvent(decoded);
        if (event.kind == RealtimeSidebandEventKind.unknown) return;
        if (_events.isClosed) return;
        _events.add(event);
      },
      onError: (Object _) {
        if (_events.isClosed) return;
        _events.add(_closedEvent(channel));
      },
      onDone: () {
        if (_events.isClosed) return;
        _events.add(_closedEvent(channel));
      },
      cancelOnError: false,
    );
    // Credentials go in the FIRST application frame and nowhere else.
    channel.sink.add(
      encodeBindFrame(
        sessionId: sessionId,
        generation: generation,
        accessToken: accessToken,
        bindingToken: bindingToken,
      ),
    );
  }

  @override
  Future<void> sendHealth() async {
    final channel = _channel;
    // Guard on the socket actually being open: unbound (bind never
    // succeeded) or already closed are both no-ops rather than errors, since
    // a superseded or torn-down attempt has nothing left to report health for.
    if (channel == null || channel.closeCode != null) return;
    channel.sink.add(kSidebandHealthFrame);
  }

  /// The socket's own close, carrying the private-range code so the UI can
  /// tell a rejected bind from a lost lease from a timeout.
  static RealtimeSidebandEvent _closedEvent(WebSocketChannel channel) {
    final cause = sidebandCloseCauseFor(channel.closeCode);
    return RealtimeSidebandEvent(
      kind: RealtimeSidebandEventKind.closing,
      cause: cause,
      reason: channel.closeReason,
    );
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {
      // Best-effort: a socket already dropped by the server is fine.
    }
    _channel = null;
    if (!_events.isClosed) await _events.close();
  }

  static Map<String, dynamic>? _decode(String frame) {
    try {
      final raw = jsonDecode(frame);
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {
      // Unparseable frames are dropped, like unknown types.
    }
    return null;
  }
}
