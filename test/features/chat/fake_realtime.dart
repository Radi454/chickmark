import 'dart:async';

import 'package:hatchaudit/services/realtime/realtime_call_signaling.dart';
import 'package:hatchaudit/services/realtime/realtime_session_service.dart';
import 'package:hatchaudit/services/realtime/realtime_sideband_channel.dart';
import 'package:hatchaudit/services/realtime/realtime_transport.dart';
import 'package:hatchaudit/services/supabase/assistant_chat_service.dart'
    show defaultConversationKey;

/// Records every call in order so tests can assert *what* happened and *when*
/// — most importantly that `startTransmitting` appears at most once, and never
/// before an authoritative READY.
class FakeRealtimeTransport implements RealtimeTransport {
  FakeRealtimeTransport({this.log});

  /// Optional shared log so a test spanning several attempts can see the
  /// interleaving.
  final List<String>? log;

  final List<String> calls = <String>[];
  final StreamController<Map<String, dynamic>> eventController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<RealtimeConnectionState> connectionController =
      StreamController<RealtimeConnectionState>.broadcast();

  Object? openMicrophoneError;
  Object? startTransmittingError;
  Object? acceptAnswerError;
  Completer<void>? openMicrophoneGate;
  Completer<void>? createOfferGate;

  bool _isTransmitting = false;
  bool _micEnabled = true;
  bool disposed = false;
  int startTransmittingCount = 0;
  List<RealtimeOutboundAudioReport> reports =
      const <RealtimeOutboundAudioReport>[];

  void _record(String call) {
    calls.add(call);
    log?.add(call);
  }

  @override
  Stream<Map<String, dynamic>> get events => eventController.stream;

  @override
  Stream<RealtimeConnectionState> get connectionStates =>
      connectionController.stream;

  @override
  bool get isTransmitting => _isTransmitting;

  @override
  bool get isMicrophoneEnabled => _micEnabled;

  @override
  Future<void> openMicrophone() async {
    _record('openMicrophone');
    if (openMicrophoneGate != null) await openMicrophoneGate!.future;
    if (openMicrophoneError != null) throw openMicrophoneError!;
  }

  @override
  Future<void> createConnection() async => _record('createConnection');

  @override
  Future<void> addSilentAudioTransceiver() async =>
      _record('addSilentAudioTransceiver');

  @override
  Future<void> openEventChannel() async => _record('openEventChannel');

  @override
  Future<String> createOffer() async {
    _record('createOffer');
    if (createOfferGate != null) await createOfferGate!.future;
    return 'offer-sdp';
  }

  @override
  Future<void> acceptAnswer(String sdp) async {
    _record('acceptAnswer');
    final error = acceptAnswerError;
    if (error != null) throw error;
  }

  @override
  Future<void> startTransmitting() async {
    _record('startTransmitting');
    startTransmittingCount++;
    if (startTransmittingError != null) throw startTransmittingError!;
    _isTransmitting = true;
  }

  @override
  Future<void> stopTransmitting() async {
    _record('stopTransmitting');
    _isTransmitting = false;
  }

  @override
  void setMicrophoneEnabled(bool enabled) {
    _record('setMicrophoneEnabled($enabled)');
    _micEnabled = enabled;
  }

  @override
  Future<List<RealtimeOutboundAudioReport>> outboundAudioReports() async =>
      reports;

  @override
  Future<void> dispose() async {
    _record('dispose');
    disposed = true;
    _isTransmitting = false;
    if (!eventController.isClosed) await eventController.close();
    if (!connectionController.isClosed) await connectionController.close();
  }
}

class FakeRealtimeSideband implements RealtimeSidebandChannel {
  FakeRealtimeSideband({this.log});

  final List<String>? log;
  final List<String> calls = <String>[];
  final StreamController<RealtimeSidebandEvent> controller =
      StreamController<RealtimeSidebandEvent>.broadcast();

  Object? bindError;
  Object? sendHealthError;
  bool closed = false;
  String? boundSessionId;
  int sendHealthCount = 0;

  @override
  Stream<RealtimeSidebandEvent> get events => controller.stream;

  int? boundGeneration;
  String? boundBindingToken;
  String? boundAccessToken;

  @override
  Future<void> bind({
    required Uri url,
    required String accessToken,
    required String bindingToken,
    required String sessionId,
    required int generation,
  }) async {
    calls.add('bind');
    log?.add('bind');
    boundSessionId = sessionId;
    boundGeneration = generation;
    boundBindingToken = bindingToken;
    boundAccessToken = accessToken;
    if (bindError != null) throw bindError!;
  }

  @override
  Future<void> sendHealth() async {
    calls.add('sendHealth');
    log?.add('sendHealth');
    sendHealthCount++;
    if (sendHealthError != null) throw sendHealthError!;
  }

  @override
  Future<void> close() async {
    calls.add('close');
    log?.add('close');
    closed = true;
    if (!controller.isClosed) await controller.close();
  }

  void emit(RealtimeSidebandEvent event) {
    if (controller.isClosed) return;
    controller.add(event);
  }

  void emitReady({String? sessionId, int? generation}) => emit(
    RealtimeSidebandEvent(
      kind: RealtimeSidebandEventKind.ready,
      sessionId: sessionId,
      generation: generation,
    ),
  );

  void emitClosing(RealtimeSidebandCloseCause cause) => emit(
    RealtimeSidebandEvent(
      kind: RealtimeSidebandEventKind.closing,
      cause: cause,
    ),
  );
}

class FakeRealtimeSessionPort implements RealtimeSessionPort {
  FakeRealtimeSessionPort({this.log});

  final List<String>? log;
  final List<String> calls = <String>[];
  final List<String> registeredCallIds = <String>[];

  Object? createSessionError;

  /// Per-attempt outcomes, consumed in order and taking precedence over
  /// [createSessionError]. A null entry means "this attempt succeeds".
  final List<Object?> createSessionOutcomes = <Object?>[];

  Object? registerCallError;
  int sessionCounter = 0;

  RealtimeSessionGrant Function(int attempt)? grantBuilder;

  String accessTokenValue = 'supabase-jwt';
  Object? accessTokenError;

  /// Every `conversationKey` a test passed to [createSession], in call order
  /// — lets a test assert the key was actually threaded through.
  final List<String> requestedConversationKeys = <String>[];

  @override
  Future<String> accessToken() async {
    calls.add('accessToken');
    log?.add('accessToken');
    if (accessTokenError != null) throw accessTokenError!;
    return accessTokenValue;
  }

  @override
  Future<RealtimeSessionGrant> createSession({
    String conversationKey = defaultConversationKey,
  }) async {
    calls.add('createSession');
    log?.add('createSession');
    requestedConversationKeys.add(conversationKey);
    if (createSessionOutcomes.isNotEmpty) {
      final outcome = createSessionOutcomes.removeAt(0);
      if (outcome != null) throw outcome;
    } else if (createSessionError != null) {
      throw createSessionError!;
    }
    sessionCounter++;
    return grantBuilder?.call(sessionCounter) ??
        RealtimeSessionGrant(
          sessionId: 'session-$sessionCounter',
          generation: 1,
          clientSecret: 'ek_secret',
          bindingToken: 'binding-token',
          callsUrl: Uri.parse('https://api.openai.com/v1/realtime/calls'),
          sidebandUrl: Uri.parse('wss://sideband.example/realtime'),
        );
  }

  @override
  Future<void> registerCall({
    required String sessionId,
    required int generation,
    required String callId,
  }) async {
    calls.add('registerCall');
    log?.add('registerCall');
    registeredCallIds.add(callId);
    if (registerCallError != null) throw registerCallError!;
  }

  @override
  Future<void> abortSetup({
    required String sessionId,
    required int generation,
    String? callId,
  }) async {
    calls.add('abortSetup');
    log?.add('abortSetup');
    abortedCallIds.add(callId);
  }

  final List<String?> abortedCallIds = <String?>[];

  @override
  Future<void> endSession({
    required String sessionId,
    RealtimeEndReason reason = RealtimeEndReason.userEnded,
  }) async {
    calls.add('endSession');
    log?.add('endSession');
    endReasons.add(reason);
  }

  final List<RealtimeEndReason> endReasons = <RealtimeEndReason>[];
}

class FakeRealtimeSignaling implements RealtimeCallSignaling {
  FakeRealtimeSignaling({this.log});

  final List<String>? log;
  final List<String> calls = <String>[];
  Object? error;
  Completer<void>? gate;
  int counter = 0;

  @override
  Future<RealtimeCallSession> exchangeOffer({
    required Uri url,
    required String clientSecret,
    required String offerSdp,
  }) async {
    calls.add('exchangeOffer');
    log?.add('exchangeOffer');
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    counter++;
    return RealtimeCallSession(
      callId: 'rtc_call$counter',
      answerSdp: 'answer-sdp',
    );
  }
}
