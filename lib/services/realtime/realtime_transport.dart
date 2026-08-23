import 'dart:async';

/// The WebRTC surface the Realtime voice feature needs, and nothing else.
///
/// This exists so [RealtimeVoiceController] can be exercised end to end in a
/// plain `flutter_test` unit test: the only implementation that touches
/// `flutter_webrtc` is `WebRtcRealtimeTransport`, and tests fake this
/// interface instead.
///
/// ## The security invariant this interface encodes
///
/// No microphone audio may reach the remote peer before the server declares
/// an authoritative READY. The obvious implementation — holding
/// `track.enabled = false` until READY — does **not** achieve that. W3C
/// defines a disabled track as delivering *zero-information content*, not *no
/// content*: on Web the browser keeps sending silence frames (~40 kbps, ~50
/// packets/second) and `packetsSent` keeps climbing. Native libwebrtc behaves
/// differently again. So `enabled` is a UX mute, never a security control.
///
/// The mechanism that actually works, and the reason the methods below are
/// split the way they are:
///
/// 1. [openMicrophone] acquires the mic stream but never hands the track to
///    `addTrack`.
/// 2. [addSilentAudioTransceiver] adds a `sendrecv` audio transceiver with
///    **no track argument**, producing a sender whose track is null. The
///    m-line direction is settled at negotiation time, but a null-track sender
///    emits zero RTP by specification.
/// 3. SDP is negotiated ([createOffer] / [acceptAnswer]) while still silent.
/// 4. [startTransmitting] calls `sender.replaceTrack(micTrack)`, which is
///    defined as swapping the source *without renegotiation* — nothing touches
///    the wire, and transmission begins at that instant and not before.
/// 5. [stopTransmitting] calls `sender.replaceTrack(null)`.
abstract interface class RealtimeTransport {
  /// Acquires the microphone. The resulting track is deliberately *not*
  /// attached to any sender.
  ///
  /// Throws [RealtimeMicPermissionException] when the user denies access or
  /// no input device is available.
  Future<void> openMicrophone();

  /// Creates the peer connection. No media is attached by this call.
  Future<void> createConnection();

  /// Adds the `sendrecv` audio transceiver **with a null track**. Must be
  /// called before [createOffer] so the m-line is negotiated once and never
  /// renegotiated.
  Future<void> addSilentAudioTransceiver();

  /// Opens the OpenAI event data channel.
  Future<void> openEventChannel();

  /// Decoded JSON objects arriving on the event data channel.
  Stream<Map<String, dynamic>> get events;

  /// Peer connection lifecycle, collapsed to what the controller reacts to.
  Stream<RealtimeConnectionState> get connectionStates;

  /// Creates the offer and applies it as the local description. Returns the
  /// SDP to POST to OpenAI.
  Future<String> createOffer();

  Future<void> acceptAnswer(String sdp);

  /// True once — and only once — [startTransmitting] has run and
  /// [stopTransmitting] has not.
  bool get isTransmitting;

  /// `sender.replaceTrack(micTrack)`. The single moment audio starts leaving
  /// the device. Idempotent: a second call while already transmitting is a
  /// no-op, so a duplicate READY cannot double-attach.
  Future<void> startTransmitting();

  /// `sender.replaceTrack(null)`. Audio stops leaving the device.
  Future<void> stopTransmitting();

  /// Secondary UX mute only. This is *not* the security control — see the
  /// class docs. Safe to use once transmission has legitimately started.
  void setMicrophoneEnabled(bool enabled);

  bool get isMicrophoneEnabled;

  /// `getStats()` filtered to `type == 'outbound-rtp'` && `kind == 'audio'`.
  ///
  /// Deliberately reads the *peer connection's* stats, not
  /// `sender.getStats()`: when a sender's track is null, `sender.getStats()`
  /// silently returns whole-peer-connection stats, which makes it useless as
  /// an assertion target.
  ///
  /// With no track attached some stacks emit no outbound-rtp report at all, so
  /// the invariant to assert is "no audio outbound-rtp report exists, OR its
  /// [RealtimeOutboundAudioReport.packetsSent] is 0" — never a bare field read.
  Future<List<RealtimeOutboundAudioReport>> outboundAudioReports();

  /// Full teardown, in the order that actually releases the OS microphone:
  /// `track.stop()` → `stream.dispose()` → `pc.close()` → `pc.dispose()`.
  /// Skipping `track.stop()` leaves the iOS mic indicator lit after the call.
  Future<void> dispose();
}

/// Peer connection states the controller acts on.
enum RealtimeConnectionState {
  connecting,
  connected,
  disconnected,
  failed,
  closed,
}

/// One `outbound-rtp` audio stats report.
class RealtimeOutboundAudioReport {
  const RealtimeOutboundAudioReport({this.packetsSent, this.bytesSent});

  /// Null when the stack emitted the report without the field.
  final int? packetsSent;
  final int? bytesSent;
}

/// True when [reports] prove no audio has left the device: either there is no
/// audio outbound-rtp report at all, or every one reports zero packets sent.
///
/// This is the assertion helper for the security invariant. It never reads
/// `packetsSent` on an absent report, because a stack with no attached track
/// may emit none.
bool noAudioHasBeenTransmitted(List<RealtimeOutboundAudioReport> reports) {
  if (reports.isEmpty) return true;
  return reports.every((report) => (report.packetsSent ?? 0) == 0);
}

/// The user denied microphone access, or there is no usable input device.
/// Never auto-recovered from: retrying a denial just loops.
class RealtimeMicPermissionException implements Exception {
  const RealtimeMicPermissionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Any other transport-level failure. Eligible for the one automatic recovery.
class RealtimeTransportException implements Exception {
  const RealtimeTransportException(this.message);

  final String message;

  @override
  String toString() => message;
}
