import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../services/realtime/realtime_call_signaling.dart';
import '../../../services/realtime/realtime_background_service.dart';
import '../../../services/realtime/realtime_client_event_policy.dart';
import '../../../services/realtime/realtime_session_service.dart';
import '../../../services/realtime/realtime_sideband_channel.dart';
import '../../../services/realtime/realtime_transport.dart';
import '../../../services/realtime/webrtc_realtime_transport.dart';
import '../../../services/supabase/assistant_chat_service.dart'
    show defaultConversationKey;

/// `'app'` or `'app:'+lowercase-uuid-v4` — the exact shape the control plane
/// accepts for `start`'s `conversationId`. Checked client-side so a malformed
/// key fails fast instead of round-tripping to a 400.
final RegExp _conversationKeyPattern = RegExp(
  r'^app:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

bool isValidRealtimeConversationKey(String key) =>
    key == defaultConversationKey || _conversationKeyPattern.hasMatch(key);

/// Lifecycle of one live voice call.
///
/// [connectingMuted] and [reconnectingMuted] are **enforced media states, not
/// labels**: while the controller is in them the peer connection's audio
/// sender holds a null track, so zero RTP is produced. See
/// [RealtimeTransport] for why `track.enabled` cannot be used for this.
enum RealtimeVoiceState {
  idle,
  requestingPermission,
  connectingMuted,
  registeringCall,
  bindingSideband,
  awaitingAuthoritativeReady,
  listening,
  userSpeaking,
  thinking,
  assistantSpeaking,
  reconnectingMuted,
  ending,
  error,
}

/// Who a caption line belongs to. Captions arrive on the WebRTC data channel
/// straight from OpenAI — the sideband never carries them.
enum RealtimeCaptionSpeaker { user, assistant }

/// One line of locally rendered caption. Captions are display-only and are
/// never sent anywhere.
class RealtimeCaption {
  const RealtimeCaption({
    required this.speaker,
    required this.text,
    this.isFinal = false,
  });

  final RealtimeCaptionSpeaker speaker;
  final String text;
  final bool isFinal;

  RealtimeCaption copyWith({String? text, bool? isFinal}) => RealtimeCaption(
    speaker: speaker,
    text: text ?? this.text,
    isFinal: isFinal ?? this.isFinal,
  );
}

/// Drives "Pip Live": the WebRTC call to OpenAI Realtime, the backend call
/// registration, the Cloud Run sideband, and the one moment audio is allowed
/// to start flowing.
///
/// ## Why every step is generation-guarded
///
/// Setup is a chain of awaits. If the user navigates away, cancels, or logs
/// out mid-chain, the remaining steps are still queued — and the last of them
/// would otherwise turn the microphone on for a call nobody is in. Each
/// attempt therefore takes a monotonically increasing generation number, and
/// every step re-checks it. A superseded attempt tears its own resources down
/// and never touches transmission.
///
/// ## Why READY is validated rather than trusted
///
/// The sideband is authoritative for "safe to transmit", but a READY frame can
/// arrive late (from an attempt already abandoned) or twice. Transmission is
/// enabled at most once per generation, only while the controller is actually
/// awaiting READY, and only when the frame's session and call ids match the
/// current attempt.
class RealtimeVoiceController extends ChangeNotifier {
  RealtimeVoiceController({
    RealtimeSessionPort? sessionPort,
    RealtimeCallSignaling? signaling,
    RealtimeTransport Function()? transportFactory,
    RealtimeSidebandChannel Function()? sidebandFactory,
    RealtimeBackgroundPort? backgroundPort,
  }) : _providedSessionPort = sessionPort,
       _providedSignaling = signaling,
       _transportFactory = transportFactory ?? WebRtcRealtimeTransport.new,
       _sidebandFactory =
           sidebandFactory ?? WebSocketRealtimeSidebandChannel.new,
       _backgroundPort = backgroundPort ?? PlatformRealtimeBackgroundService() {
    _backgroundSubscription = _backgroundPort.endRequests.listen(
      (_) => unawaited(stop()),
    );
  }

  // Defaults are built lazily so merely registering this controller in the
  // shell never opens an http.Client or touches a platform channel — the same
  // discipline AssistantProvider uses for its recorder and player.
  final RealtimeSessionPort? _providedSessionPort;
  RealtimeSessionPort? _lazySessionPort;
  RealtimeSessionPort get _sessionPort =>
      _providedSessionPort ??
      (_lazySessionPort ??= SupabaseRealtimeSessionService());

  final RealtimeCallSignaling? _providedSignaling;
  RealtimeCallSignaling? _lazySignaling;
  RealtimeCallSignaling get _signaling =>
      _providedSignaling ?? (_lazySignaling ??= HttpRealtimeCallSignaling());

  /// A fresh transport per attempt: a torn-down peer connection is never
  /// reused, so recovery always restarts from a null-track sender.
  final RealtimeTransport Function() _transportFactory;
  final RealtimeSidebandChannel Function() _sidebandFactory;
  final RealtimeBackgroundPort _backgroundPort;
  late final StreamSubscription<void> _backgroundSubscription;

  RealtimeVoiceState _state = RealtimeVoiceState.idle;
  int _generation = 0;
  int? _transmittingGeneration;
  bool _recoveryUsed = false;
  bool _isMuted = false;
  bool _disposed = false;
  bool _backgroundActive = false;
  bool _backgroundActivationPending = false;
  String? _errorMessage;
  String? _sessionId;
  int? _serverGeneration;
  String? _callId;

  /// Which conversation the current (or most recently ended) call is/was
  /// bound to. Set on a fresh [start] and carried unchanged across the one
  /// automatic recovery reconnect, so a mid-call reconnect never migrates the
  /// call to a different thread. Cleared only when the controller returns to
  /// [RealtimeVoiceState.idle] — it survives the [RealtimeVoiceState.error]
  /// state so a caller can still tell which conversation a failed call was
  /// for.
  String? _activeConversationKey;
  String? get activeConversationKey => _activeConversationKey;

  RealtimeTransport? _transport;
  RealtimeSidebandChannel? _sideband;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  StreamSubscription<RealtimeConnectionState>? _connectionSubscription;
  StreamSubscription<RealtimeSidebandEvent>? _sidebandSubscription;

  final List<RealtimeCaption> _captions = <RealtimeCaption>[];

  RealtimeVoiceState get state => _state;
  String? get errorMessage => _errorMessage;

  /// One line of diagnostic detail for the last failure: the setup stage the
  /// controller was in, the exception's runtime type, and its text. Shown in
  /// the error banner so a device failure can be reported verbatim instead of
  /// as "nothing happens". Never contains tokens, SDP, or transcript text —
  /// only the stage name and the exception's own message.
  String? get errorDetail => _errorDetail;
  String? _errorDetail;

  bool get isMuted => _isMuted;
  List<RealtimeCaption> get captions => List.unmodifiable(_captions);

  /// True whenever a live call is set up, running, or tearing down. The chat
  /// screen ORs this into its `isVoiceBusy` gate so the legacy recorded-voice
  /// path and Realtime can never contend for the one iOS `AVAudioSession`.
  bool get isRealtimeActive =>
      _state != RealtimeVoiceState.idle && _state != RealtimeVoiceState.error;

  /// True only while the mic track is actually attached to the sender.
  bool get isTransmitting => _transport?.isTransmitting ?? false;

  /// Whether the user can start a call right now.
  bool get canStart =>
      _state == RealtimeVoiceState.idle || _state == RealtimeVoiceState.error;

  /// Starts a live call bound to [conversationKey] — `'app'` (default) or
  /// `'app:'+uuid-v4`. The sideband injects that conversation's recent turns
  /// into the model and persists this call's transcript back into it. A
  /// second call while one is active is ignored. The automatic recovery
  /// reconnect (see [_connect]) reuses the same key; it is never re-supplied
  /// mid-call.
  Future<void> start({String conversationKey = defaultConversationKey}) async {
    if (!canStart) return;
    if (!isValidRealtimeConversationKey(conversationKey)) {
      throw ArgumentError.value(
        conversationKey,
        'conversationKey',
        "must be 'app' or 'app:'+lowercase-uuid-v4",
      );
    }
    _recoveryUsed = false;
    _captions.clear();
    _activeConversationKey = conversationKey;
    await _connect(isRecovery: false);
  }

  /// Ends the call and releases every resource. Safe to call at any point in
  /// setup: bumping the generation strands any in-flight step, so nothing can
  /// enable transmission behind the teardown.
  Future<void> stop() async {
    if (_state == RealtimeVoiceState.idle) return;
    final reachedReady = _transmittingGeneration != null;
    _generation++;
    _setState(RealtimeVoiceState.ending);
    await _teardown();
    await _releaseBackendSession(
      RealtimeEndReason.userEnded,
      reachedReady: reachedReady,
    );
    await _deactivateBackground();
    _isMuted = false;
    _errorMessage = null;
    _errorDetail = null;
    _pendingDetail = null;
    _activeConversationKey = null;
    _setState(RealtimeVoiceState.idle);
  }

  /// Hands the session back to the control plane.
  ///
  /// Two distinct actions, because they mean different things: a call that
  /// never reached READY is *aborted* — reporting its orphaned OpenAI call id
  /// is what lets the sweeper hang it up — while a call that ran is *ended*.
  ///
  /// This must happen before any reconnect: `start` enforces a one-session
  /// invariant per profile, so a recovery attempt that left the previous
  /// session alive would be refused as a conflict.
  Future<void> _releaseBackendSession(
    RealtimeEndReason reason, {
    required bool reachedReady,
  }) async {
    final sessionId = _sessionId;
    final serverGeneration = _serverGeneration;
    final callId = _callId;
    _sessionId = null;
    _serverGeneration = null;
    _callId = null;
    if (sessionId == null) return;
    try {
      if (!reachedReady && serverGeneration != null) {
        await _sessionPort.abortSetup(
          sessionId: sessionId,
          generation: serverGeneration,
          callId: callId,
        );
      } else {
        await _sessionPort.endSession(sessionId: sessionId, reason: reason);
      }
    } catch (_) {
      // Best-effort: the sweeper reclaims abandoned sessions anyway.
    }
  }

  /// Secondary UX mute. Only meaningful once transmission has legitimately
  /// started; before READY the sender has no track at all, so there is
  /// nothing to mute.
  void setMuted(bool muted) {
    if (_isMuted == muted) return;
    _isMuted = muted;
    _transport?.setMicrophoneEnabled(!muted);
    _notify();
  }

  void toggleMute() => setMuted(!_isMuted);

  /// Barge-in. Purely local: it moves the UI off "assistant speaking" so the
  /// user's turn is reflected immediately. Nothing is relayed to any backend.
  void interrupt() {
    if (_state != RealtimeVoiceState.assistantSpeaking) return;
    _setState(RealtimeVoiceState.listening);
  }

  /// Reads `outbound-rtp` audio stats straight off the peer connection so a
  /// caller (or an on-device check) can prove the invariant. See
  /// [noAudioHasBeenTransmitted].
  Future<List<RealtimeOutboundAudioReport>> outboundAudioReports() async =>
      await _transport?.outboundAudioReports() ??
      const <RealtimeOutboundAudioReport>[];

  Future<void> _connect({required bool isRecovery}) async {
    final generation = ++_generation;
    _errorMessage = null;
    if (!isRecovery) _errorDetail = null;
    _isMuted = false;
    _callId = null;

    final transport = _transportFactory();
    final sideband = _sidebandFactory();
    _transport = transport;
    _sideband = sideband;

    // Which setup step was in flight when an exception surfaced. Reported in
    // errorDetail so a device failure names its stage instead of arriving as
    // "the button turned itself off".
    var stage = 'openMicrophone';
    try {
      _setState(
        isRecovery
            ? RealtimeVoiceState.reconnectingMuted
            : RealtimeVoiceState.requestingPermission,
      );
      await transport.openMicrophone();
      if (await _abandonIfStale(generation, transport, sideband)) return;

      if (!_backgroundActive) {
        stage = 'activateBackground';
        _backgroundActivationPending = true;
        try {
          await _backgroundPort.activate();
          _backgroundActive = true;
        } catch (_) {
          throw const RealtimeTransportException(
            'Could not keep the live call active in the background. Please try again.',
          );
        } finally {
          _backgroundActivationPending = false;
        }
        if (generation != _generation) {
          await _deactivateBackground();
          await _releaseAttempt(transport, sideband);
          return;
        }
      }

      _setState(
        isRecovery
            ? RealtimeVoiceState.reconnectingMuted
            : RealtimeVoiceState.connectingMuted,
      );
      stage = 'createSession';
      final grant = await _sessionPort.createSession(
        conversationKey: _activeConversationKey ?? defaultConversationKey,
      );
      if (await _abandonIfStale(generation, transport, sideband)) return;
      _sessionId = grant.sessionId;
      _serverGeneration = grant.generation;

      stage = 'createConnection';
      await transport.createConnection();
      // Null-track sender, created before the offer so the m-line is
      // negotiated once and never renegotiated when audio starts.
      stage = 'addSilentAudioTransceiver';
      await transport.addSilentAudioTransceiver();
      stage = 'openEventChannel';
      await transport.openEventChannel();
      _eventSubscription = transport.events.listen(
        (raw) => _onClientEvent(generation, raw),
      );
      _connectionSubscription = transport.connectionStates.listen(
        (connectionState) => _onConnectionState(generation, connectionState),
      );
      stage = 'createOffer';
      final offer = await transport.createOffer();
      if (await _abandonIfStale(generation, transport, sideband)) return;

      stage = 'exchangeOffer';
      final call = await _signaling.exchangeOffer(
        url: grant.effectiveCallsUrl,
        clientSecret: grant.clientSecret,
        offerSdp: offer,
      );
      if (await _abandonIfStale(generation, transport, sideband)) return;
      _callId = call.callId;

      // The call id exists now, so the backend is told immediately — before
      // the answer is applied and before the sideband is bound. Without this
      // the sideband has nothing to attach to and no READY can ever be issued.
      _setState(RealtimeVoiceState.registeringCall);
      stage = 'registerCall';
      await _sessionPort.registerCall(
        sessionId: grant.sessionId,
        generation: grant.generation,
        callId: call.callId,
      );
      if (await _abandonIfStale(generation, transport, sideband)) return;

      stage = 'acceptAnswer';
      await transport.acceptAnswer(call.answerSdp);
      if (await _abandonIfStale(generation, transport, sideband)) return;

      _setState(RealtimeVoiceState.bindingSideband);
      _sidebandSubscription = sideband.events.listen(
        (event) => _onSidebandEvent(generation, event),
      );
      // Read late, so a token refreshed during setup is the one that binds.
      stage = 'accessToken';
      final accessToken = await _sessionPort.accessToken();
      if (await _abandonIfStale(generation, transport, sideband)) return;
      stage = 'bind';
      await sideband.bind(
        url: grant.sidebandUrl,
        accessToken: accessToken,
        bindingToken: grant.bindingToken,
        sessionId: grant.sessionId,
        generation: grant.generation,
      );
      if (await _abandonIfStale(generation, transport, sideband)) return;

      // The WebRTC transport and the 'oai-events' data channel are both
      // already up by bind time (openEventChannel + acceptAnswer ran
      // earlier in this attempt), so this is always {webrtc:true,
      // data_channel:true}. The server marks webrtcHealthy/dataChannelHealthy
      // from exactly this frame and will never announce READY without it —
      // see WIRE_CONTRACT.md. Sent once per attempt.
      stage = 'sendHealth';
      await sideband.sendHealth();
      if (await _abandonIfStale(generation, transport, sideband)) return;

      // Still silent. Nothing has been sent and nothing will be until a
      // current-generation READY arrives.
      _setState(RealtimeVoiceState.awaitingAuthoritativeReady);
    } on RealtimeMicPermissionException catch (error) {
      // Never auto-recovered: re-prompting a denial just loops.
      if (generation != _generation) return;
      await _teardown();
      await _releaseBackendSession(
        RealtimeEndReason.clientError,
        reachedReady: false,
      );
      await _deactivateBackground();
      _fail(error.message, detail: _detailFor(stage, error));
    } on RealtimeTransportException catch (error) {
      if (stage == 'activateBackground') {
        if (generation != _generation) return;
        await _teardown();
        await _deactivateBackground();
        _fail(error.message, detail: _detailFor(stage, error));
        return;
      }
      await _handleFailure(
        generation,
        _messageFor(error),
        detail: _detailFor(stage, error),
      );
    } catch (error) {
      await _handleFailure(
        generation,
        _messageFor(error),
        detail: _detailFor(stage, error),
      );
    }
  }

  /// `stage: ExceptionType: message`, truncated. Deliberately built only from
  /// the stage name and the exception's own text — never tokens, SDP, or
  /// transcript content.
  static String _detailFor(String stage, Object error) {
    final text = '$stage: ${error.runtimeType}: $error';
    return text.length > 300 ? '${text.substring(0, 300)}…' : text;
  }

  /// True when [generation] has been superseded; also releases the attempt's
  /// resources so a cancelled setup leaks nothing.
  Future<bool> _abandonIfStale(
    int generation,
    RealtimeTransport transport,
    RealtimeSidebandChannel sideband,
  ) async {
    if (generation == _generation) return false;
    await _releaseAttempt(transport, sideband);
    return true;
  }

  Future<void> _releaseAttempt(
    RealtimeTransport transport,
    RealtimeSidebandChannel sideband,
  ) async {
    try {
      await sideband.close();
    } catch (_) {
      // Best-effort.
    }
    try {
      await transport.stopTransmitting();
    } catch (_) {
      // Best-effort.
    }
    try {
      await transport.dispose();
    } catch (_) {
      // Best-effort.
    }
  }

  /// The sideband speaks three notices — `ready`, `error`, `closing` — and
  /// nothing else. Turn state and captions come from the data channel, so an
  /// unknown notice is dropped rather than interpreted.
  void _onSidebandEvent(int generation, RealtimeSidebandEvent event) {
    if (generation != _generation) return;
    switch (event.kind) {
      case RealtimeSidebandEventKind.ready:
        unawaited(_handleReady(generation, event));
      case RealtimeSidebandEventKind.error:
        unawaited(_handleFailure(generation, event.message));
      case RealtimeSidebandEventKind.closing:
        // The `closing` NOTICE is advance warning only; the socket close that
        // follows carries the code, and that is what is acted on. A clean close
        // is the call ending; every private-range code is a failure whose
        // message already distinguishes the cause — a rejected bind, a lost
        // lease and a bind timeout each read differently.
        final cause = event.cause;
        if (cause == null) return;
        if (cause == RealtimeSidebandCloseCause.normal) {
          unawaited(stop());
          return;
        }
        unawaited(_handleFailure(generation, event.message));
      case RealtimeSidebandEventKind.unknown:
        return;
    }
  }

  /// The one path that may enable transmission.
  Future<void> _handleReady(int generation, RealtimeSidebandEvent event) async {
    // Stale generation: a READY from an attempt that has been superseded.
    if (generation != _generation) return;
    // Only ever honoured while actually waiting for it. This is also what
    // makes a duplicate READY inert: the first one moves the state on.
    if (_state != RealtimeVoiceState.awaitingAuthoritativeReady) return;
    // Belt and braces against a second READY racing the state change.
    if (_transmittingGeneration == generation) return;
    // The frame must be about *this* attempt: READY names the session and the
    // server's own generation number, which is the authority for which attempt
    // it belongs to.
    if (event.sessionId != null &&
        _sessionId != null &&
        event.sessionId != _sessionId) {
      return;
    }
    if (event.generation != null &&
        _serverGeneration != null &&
        event.generation != _serverGeneration) {
      return;
    }
    final transport = _transport;
    if (transport == null) return;
    _transmittingGeneration = generation;
    try {
      await transport.startTransmitting();
    } catch (error) {
      _transmittingGeneration = null;
      await _handleFailure(generation, _messageFor(error));
      return;
    }
    if (generation != _generation) {
      // Superseded while replaceTrack was in flight: undo immediately.
      await transport.stopTransmitting();
      return;
    }
    if (_isMuted) transport.setMicrophoneEnabled(false);
    _setState(RealtimeVoiceState.listening);
  }

  /// Data-channel events. Presentation only — see [classifyClientEvent] for
  /// the policy this enforces. Tool events reach here and are dropped without
  /// being executed, relayed, or logged.
  void _onClientEvent(int generation, Map<String, dynamic> raw) {
    if (generation != _generation) return;
    final event = classifyClientEvent(raw);
    switch (event.action) {
      case RealtimeClientEventAction.userSpeechStarted:
        if (_transmittingGeneration == null) return;
        _setState(RealtimeVoiceState.userSpeaking);
      case RealtimeClientEventAction.userSpeechStopped:
        if (_state == RealtimeVoiceState.userSpeaking) {
          _setState(RealtimeVoiceState.listening);
        }
      case RealtimeClientEventAction.assistantThinking:
        if (_transmittingGeneration == null) return;
        _setState(RealtimeVoiceState.thinking);
      case RealtimeClientEventAction.assistantSpeaking:
        if (_transmittingGeneration == null) return;
        if (_state != RealtimeVoiceState.assistantSpeaking) {
          _setState(RealtimeVoiceState.assistantSpeaking);
        }
      case RealtimeClientEventAction.assistantTurnComplete:
        if (_transmittingGeneration == null) return;
        _setState(RealtimeVoiceState.listening);
      case RealtimeClientEventAction.assistantCaption:
        final text = event.text;
        if (text == null) return;
        _appendCaption(
          RealtimeCaptionSpeaker.assistant,
          text,
          isFinal: event.isFinal,
        );
      case RealtimeClientEventAction.userCaption:
        final text = event.text;
        if (text == null) return;
        _appendCaption(
          RealtimeCaptionSpeaker.user,
          text,
          isFinal: event.isFinal,
        );
      case RealtimeClientEventAction.remoteError:
        unawaited(
          _handleFailure(generation, 'The live voice session hit an error.'),
        );
      case RealtimeClientEventAction.ignore:
        // Tool/function-call events and every unrecognised type land here and
        // are dropped without execution, relay, or logging.
        return;
    }
  }

  void _onConnectionState(int generation, RealtimeConnectionState state) {
    if (generation != _generation) return;
    if (state == RealtimeConnectionState.failed) {
      unawaited(_handleFailure(generation, 'The live voice call dropped.'));
    }
  }

  /// One automatic recovery per user-initiated [start]. [_recoveryUsed] is the
  /// only thing standing between a flapping network and an infinite reconnect
  /// loop, so it is set before the retry, not after it succeeds.
  Future<void> _handleFailure(
    int generation,
    String message, {
    String? detail,
  }) async {
    if (generation != _generation) return;
    if (_state == RealtimeVoiceState.ending ||
        _state == RealtimeVoiceState.idle) {
      return;
    }
    final reachedReady = _transmittingGeneration != null;
    await _teardown();
    // Released before any reconnect: the control plane allows one live
    // session per profile, so a retry that left the old one standing would be
    // refused as a conflict rather than recovering.
    await _releaseBackendSession(
      RealtimeEndReason.clientError,
      reachedReady: reachedReady,
    );
    if (!_recoveryUsed) {
      _recoveryUsed = true;
      // Keep the first failure's detail: if recovery also fails, the ORIGINAL
      // cause is the diagnostic that matters, not the retry's echo of it.
      _pendingDetail ??= detail;
      await _connect(isRecovery: true);
      return;
    }
    _fail(message, detail: detail ?? _pendingDetail);
    await _deactivateBackground();
  }

  /// Detail carried across the single automatic recovery attempt.
  String? _pendingDetail;

  void _fail(String message, {String? detail}) {
    _errorMessage = message;
    _errorDetail = detail ?? _pendingDetail;
    _pendingDetail = null;
    _transmittingGeneration = null;
    _setState(RealtimeVoiceState.error);
  }

  Future<void> _teardown() async {
    // Deliberately not awaited. A broadcast-stream subscription's cancel()
    // future is created in the root zone, so under `flutter_test`'s FakeAsync
    // it never completes and awaiting it would hang teardown (and therefore
    // every widget test that ends a call). Cancellation itself is synchronous
    // — the listener stops receiving immediately — so nothing here depends on
    // the future.
    for (final subscription in <StreamSubscription<dynamic>?>[
      _eventSubscription,
      _connectionSubscription,
      _sidebandSubscription,
    ]) {
      if (subscription != null) unawaited(subscription.cancel());
    }
    _eventSubscription = null;
    _connectionSubscription = null;
    _sidebandSubscription = null;
    _transmittingGeneration = null;

    final sideband = _sideband;
    _sideband = null;
    final transport = _transport;
    _transport = null;
    if (sideband != null || transport != null) {
      await _releaseAttempt(
        transport ?? _NullTransport(),
        sideband ?? _NullSideband(),
      );
    }
  }

  Future<void> _deactivateBackground() async {
    if (!_backgroundActive && !_backgroundActivationPending) return;
    _backgroundActive = false;
    _backgroundActivationPending = false;
    try {
      await _backgroundPort.deactivate();
    } catch (_) {
      // The call media and backend session must still be allowed to clean up.
    }
  }

  void _appendCaption(
    RealtimeCaptionSpeaker speaker,
    String text, {
    required bool isFinal,
  }) {
    final last = _captions.isEmpty ? null : _captions.last;
    if (last != null && last.speaker == speaker && !last.isFinal) {
      // A final frame carries the FULL transcript, not an increment: it
      // replaces the streamed line, otherwise the whole reply renders twice.
      _captions[_captions.length - 1] = last.copyWith(
        text: isFinal ? text : '${last.text}$text',
        isFinal: isFinal,
      );
    } else {
      _captions.add(
        RealtimeCaption(speaker: speaker, text: text, isFinal: isFinal),
      );
    }
    _notify();
  }

  static String _messageFor(Object error) {
    if (error is RealtimeSessionException) return error.message;
    if (error is RealtimeSignalingException) return error.message;
    if (error is RealtimeSidebandException) return error.message;
    if (error is RealtimeTransportException) return error.message;
    if (error is RealtimeMicPermissionException) return error.message;
    return 'Live voice is unavailable right now. Please try again.';
  }

  void _setState(RealtimeVoiceState next) {
    if (_state == next) return;
    _state = next;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    // Bumping the generation strands any in-flight setup step so it can never
    // enable transmission after the controller is gone.
    _generation++;
    final reachedReady = _transmittingGeneration != null;
    _disposed = true;
    unawaited(
      _teardown().then((_) async {
        await _releaseBackendSession(
          RealtimeEndReason.appBackgrounded,
          reachedReady: reachedReady,
        );
        await _deactivateBackground();
        _backgroundPort.dispose();
      }),
    );
    unawaited(_backgroundSubscription.cancel());
    super.dispose();
  }
}

/// Stand-ins so [_teardown] can use one release path whether or not both
/// halves of an attempt were built.
class _NullTransport implements RealtimeTransport {
  @override
  Future<void> acceptAnswer(String sdp) async {}
  @override
  Future<void> addSilentAudioTransceiver() async {}
  @override
  Stream<RealtimeConnectionState> get connectionStates =>
      const Stream<RealtimeConnectionState>.empty();
  @override
  Future<void> createConnection() async {}
  @override
  Future<String> createOffer() async => '';
  @override
  Future<void> dispose() async {}
  @override
  Stream<Map<String, dynamic>> get events =>
      const Stream<Map<String, dynamic>>.empty();
  @override
  bool get isMicrophoneEnabled => false;
  @override
  bool get isTransmitting => false;
  @override
  Future<void> openEventChannel() async {}
  @override
  Future<void> openMicrophone() async {}
  @override
  Future<List<RealtimeOutboundAudioReport>> outboundAudioReports() async =>
      const <RealtimeOutboundAudioReport>[];
  @override
  void setMicrophoneEnabled(bool enabled) {}
  @override
  Future<void> startTransmitting() async {}
  @override
  Future<void> stopTransmitting() async {}
}

class _NullSideband implements RealtimeSidebandChannel {
  @override
  Future<void> bind({
    required Uri url,
    required String accessToken,
    required String bindingToken,
    required String sessionId,
    required int generation,
  }) async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> sendHealth() async {}
  @override
  Stream<RealtimeSidebandEvent> get events =>
      const Stream<RealtimeSidebandEvent>.empty();
}
