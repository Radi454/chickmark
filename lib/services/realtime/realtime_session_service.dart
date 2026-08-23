import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/assistant_chat_service.dart' show defaultConversationKey;

/// Injectable seam over `functions.invoke(...)`, mirroring
/// `AssistantChatService`'s `AssistantChatRpc` so both assistant transports
/// fail and are faked the same way.
typedef RealtimeSessionRpc =
    Future<dynamic> Function(Map<String, dynamic> body);

/// The authenticated control plane for Pip Realtime. It carries no audio, runs
/// no agent turn and grants no tool authority — it decides whether a voice
/// session may exist and hands back short-lived credentials.
const String realtimeFunctionName = 'pip-realtime-session';

/// Where the SDP offer is POSTed. Not returned by the control plane and not app
/// config either: the minted client secret already encodes the model and voice,
/// so this endpoint is a fixed property of the OpenAI Realtime API.
final Uri openAiRealtimeCallsUrl = Uri.parse(
  'https://api.openai.com/v1/realtime/calls',
);

/// The fixed vocabulary the control plane accepts on `end`. `end_reason` is an
/// audit column, so client free text is refused.
enum RealtimeEndReason {
  userEnded('user_ended'),
  clientError('client_error'),
  appBackgrounded('app_backgrounded'),
  networkLost('network_lost');

  const RealtimeEndReason(this.wireValue);

  final String wireValue;
}

/// Everything the client needs for one live call.
///
/// None of this comes from app config: the ephemeral client secret and the
/// one-shot binding token are minted per user per call, and the sideband
/// address is the backend's to choose. `SupabaseConfig` carries only
/// `SUPABASE_URL` / `SUPABASE_ANON_KEY` and is deliberately not extended.
class RealtimeSessionGrant {
  const RealtimeSessionGrant({
    required this.sessionId,
    required this.generation,
    required this.clientSecret,
    required this.bindingToken,
    required this.sidebandUrl,
    this.callsUrl,
    this.conversationId,
    this.setupDeadlineAt,
    this.sessionExpiresAt,
    this.maxSessionSeconds,
  });

  /// The control plane's handle for this session.
  final String sessionId;

  /// The server-assigned attempt number. Echoed on `register_call` and on the
  /// sideband's READY, and checked before transmission is ever enabled — this
  /// is the authority for "which attempt is this", not a client counter.
  final int generation;

  /// Short-lived OpenAI credential. Never persisted, never logged.
  final String clientSecret;

  /// Returned exactly once, in the body of a successful `start`. Only its hash
  /// is stored server-side, so it cannot be recovered from the database.
  final String bindingToken;

  /// Cloud Run sideband endpoint. The sideband — not this client — executes
  /// every tool call.
  final Uri sidebandUrl;

  /// Overridable only so tests can point the SDP exchange somewhere else.
  final Uri? callsUrl;

  final String? conversationId;
  final DateTime? setupDeadlineAt;
  final DateTime? sessionExpiresAt;
  final int? maxSessionSeconds;

  Uri get effectiveCallsUrl => callsUrl ?? openAiRealtimeCallsUrl;
}

class RealtimeSessionException implements Exception {
  const RealtimeSessionException(this.message, this.code);

  final String message;
  final String code;

  @override
  String toString() => message;
}

abstract interface class RealtimeSessionPort {
  /// `start`: runs the kill switch, rate limit, scope resolution, budgets and
  /// the one-session invariant, then mints the credentials for one call.
  ///
  /// [conversationKey] names which conversation this call's transcript joins
  /// and is seeded from — `'app'` (default) or `'app:'+uuid-v4`. Sent as
  /// `conversationId` in the `start` body; the sideband is what actually
  /// injects recent turns and persists the transcript back into it.
  Future<RealtimeSessionGrant> createSession({
    String conversationKey = defaultConversationKey,
  });

  /// The caller's Supabase JWT, for the sideband bind frame. It proves identity
  /// only — the sideband re-resolves authorization server-side — and is read
  /// per bind rather than cached so a refreshed session is never bound with a
  /// stale token. Never logged, never persisted.
  Future<String> accessToken();

  /// `register_call`: writes the OpenAI call id onto the already-provisioned
  /// generation row. Called the instant the call id is known and *before* the
  /// sideband is bound — without it the sideband has nothing to attach to and
  /// no authoritative READY can ever be issued. It grants no authority.
  Future<void> registerCall({
    required String sessionId,
    required int generation,
    required String callId,
  });

  /// `abort_setup`: the narrow path for a client that created a call but
  /// cannot continue. Reporting the orphaned call id is what lets the sweeper
  /// hang it up, so it is sent even when the setup deadline has passed.
  Future<void> abortSetup({
    required String sessionId,
    required int generation,
    String? callId,
  });

  /// `end`: user-initiated termination.
  Future<void> endSession({
    required String sessionId,
    RealtimeEndReason reason = RealtimeEndReason.userEnded,
  });
}

class SupabaseRealtimeSessionService implements RealtimeSessionPort {
  SupabaseRealtimeSessionService({
    RealtimeSessionRpc? rpc,
    String? Function()? accessTokenReader,
  }) : _accessTokenReader =
           accessTokenReader ??
           (() => Supabase.instance.client.auth.currentSession?.accessToken),
       _rpc =
           rpc ??
           ((body) async {
             final response = await Supabase.instance.client.functions.invoke(
               realtimeFunctionName,
               body: body,
             );
             return response.data;
           });

  final RealtimeSessionRpc _rpc;
  final String? Function() _accessTokenReader;

  @override
  Future<String> accessToken() async {
    final token = _optionalText(_accessTokenReader());
    if (token == null) {
      throw const RealtimeSessionException(
        'Please sign in again to use live voice.',
        'signed_out',
      );
    }
    return token;
  }

  @override
  Future<RealtimeSessionGrant> createSession({
    String conversationKey = defaultConversationKey,
  }) async {
    final row = _object(
      await _invoke({'action': 'start', 'conversationId': conversationKey}),
    );
    return RealtimeSessionGrant(
      sessionId: _requiredText(row['sessionId'], 'sessionId'),
      generation: _requiredInt(row['generation'], 'generation'),
      // The secret arrives as {value, expiresAt}; only the value is kept, and
      // it is never persisted or logged.
      clientSecret: _requiredText(
        row['clientSecret'] is Map
            ? (row['clientSecret'] as Map)['value']
            : row['clientSecret'],
        'clientSecret',
      ),
      bindingToken: _requiredText(row['bindingToken'], 'bindingToken'),
      sidebandUrl: _requiredUri(row['sidebandUrl'], 'sidebandUrl'),
      conversationId: _optionalText(row['conversationId']),
      setupDeadlineAt: _optionalTime(row['setupDeadlineAt']),
      sessionExpiresAt: _optionalTime(row['sessionExpiresAt']),
      maxSessionSeconds: _optionalInt(row['maxSessionSeconds']),
    );
  }

  @override
  Future<void> registerCall({
    required String sessionId,
    required int generation,
    required String callId,
  }) async {
    await _invoke({
      'action': 'register_call',
      'sessionId': sessionId,
      'generation': generation,
      'openaiCallId': callId,
    });
  }

  @override
  Future<void> abortSetup({
    required String sessionId,
    required int generation,
    String? callId,
  }) async {
    await _invoke({
      'action': 'abort_setup',
      'sessionId': sessionId,
      'generation': generation,
      if (callId case final String id) 'openaiCallId': id,
    });
  }

  @override
  Future<void> endSession({
    required String sessionId,
    RealtimeEndReason reason = RealtimeEndReason.userEnded,
  }) async {
    await _invoke({
      'action': 'end',
      'sessionId': sessionId,
      'reason': reason.wireValue,
    });
  }

  Future<dynamic> _invoke(Map<String, dynamic> body) async {
    try {
      return await _rpc(body);
    } on FunctionException catch (error) {
      throw RealtimeSessionException(
        _messageFor(error),
        _codeFor(error) ?? 'function_error',
      );
    } on RealtimeSessionException {
      rethrow;
    } catch (_) {
      throw const RealtimeSessionException(
        'Live voice is unavailable right now. Please try again.',
        'transport_error',
      );
    }
  }

  static String _messageFor(FunctionException error) {
    final details = error.details;
    if (details is Map) {
      final message =
          details['error']?.toString() ?? details['message']?.toString();
      if (message != null && message.trim().isNotEmpty) return message.trim();
    }
    return 'Live voice is unavailable right now. Please try again.';
  }

  static String? _codeFor(FunctionException error) {
    final details = error.details;
    if (details is Map) {
      final code = details['code']?.toString();
      if (code != null && code.trim().isNotEmpty) return code.trim();
    }
    return null;
  }

  static Map<String, dynamic> _object(dynamic payload) {
    if (payload is Map) return Map<String, dynamic>.from(payload);
    throw const RealtimeSessionException(
      'Live voice returned an unexpected response. Please try again.',
      'invalid_response',
    );
  }

  static String? _optionalText(Object? value) {
    final text = value?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  static int? _optionalInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  static DateTime? _optionalTime(Object? value) {
    final text = _optionalText(value);
    return text == null ? null : DateTime.tryParse(text)?.toUtc();
  }

  static String _requiredText(Object? value, String field) {
    final text = _optionalText(value);
    if (text == null) {
      throw RealtimeSessionException(
        'Live voice returned an unexpected response. Please try again.',
        'missing_$field',
      );
    }
    return text;
  }

  static int _requiredInt(Object? value, String field) {
    final parsed = _optionalInt(value);
    if (parsed == null || parsed < 1) {
      throw RealtimeSessionException(
        'Live voice returned an unexpected response. Please try again.',
        'missing_$field',
      );
    }
    return parsed;
  }

  static Uri _requiredUri(Object? value, String field) {
    final parsed = Uri.tryParse(_requiredText(value, field));
    if (parsed == null || !parsed.hasScheme) {
      throw RealtimeSessionException(
        'Live voice returned an unexpected response. Please try again.',
        'invalid_$field',
      );
    }
    return parsed;
  }
}
