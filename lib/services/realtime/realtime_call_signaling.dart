import 'package:http/http.dart' as http;

/// The result of the one-shot SDP exchange with OpenAI Realtime.
class RealtimeCallSession {
  const RealtimeCallSession({required this.callId, required this.answerSdp});

  /// The `rtc_…` id, taken from the `Location` response header. This is the
  /// handle the backend needs to bind its sideband to *this* call, which is
  /// why it is extracted and registered before anything else continues.
  final String callId;

  final String answerSdp;
}

class RealtimeSignalingException implements Exception {
  const RealtimeSignalingException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class RealtimeCallSignaling {
  /// POSTs [offerSdp] and returns the answer plus the call id.
  Future<RealtimeCallSession> exchangeOffer({
    required Uri url,
    required String clientSecret,
    required String offerSdp,
  });
}

/// Extracts the `rtc_…` call id from a `Location` header.
///
/// The header looks like `/v1/realtime/calls/rtc_abc123`. Anything that is not
/// a trailing `rtc_…` segment returns null, so a shape change surfaces as a
/// clean failure rather than a bogus id registered against the backend.
String? parseCallIdFromLocation(String? location) {
  if (location == null) return null;
  final trimmed = location.trim();
  if (trimmed.isEmpty) return null;
  final withoutQuery = trimmed.split('?').first.split('#').first;
  final segments = withoutQuery
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty) return null;
  final candidate = segments.last;
  if (!candidate.startsWith('rtc_') || candidate.length <= 'rtc_'.length) {
    return null;
  }
  return candidate;
}

class HttpRealtimeCallSignaling implements RealtimeCallSignaling {
  HttpRealtimeCallSignaling({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<RealtimeCallSession> exchangeOffer({
    required Uri url,
    required String clientSecret,
    required String offerSdp,
  }) async {
    http.Response response;
    try {
      response = await _client.post(
        url,
        headers: <String, String>{
          'Authorization': 'Bearer $clientSecret',
          'Content-Type': 'application/sdp',
        },
        body: offerSdp,
      );
    } catch (_) {
      throw const RealtimeSignalingException(
        'Could not reach the live voice service. Check your connection.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const RealtimeSignalingException(
        'The live voice service refused the call. Please try again.',
      );
    }
    final callId = parseCallIdFromLocation(
      response.headers['location'] ?? response.headers['Location'],
    );
    if (callId == null) {
      throw const RealtimeSignalingException(
        'The live voice service did not identify the call. Please try again.',
      );
    }
    // NEVER trim the body. darwin libwebrtc requires the SDP's terminal
    // newline: an answer with it stripped fails CreateSessionDescription,
    // which surfaces as "setRemoteDescription: Error SessionDescription is
    // NULL." on iOS/macOS while Chrome parses the same string happily. That
    // single missing character was a full live-voice outage — proven by
    // integration_test/realtime_sdp_parse_test.dart against the captured
    // production answer.
    final body = response.body;
    if (body.trim().isEmpty) {
      throw const RealtimeSignalingException(
        'The live voice service returned an empty answer. Please try again.',
      );
    }
    if (!body.startsWith('v=')) {
      // Not an SDP. Quote the first line: it is protocol metadata, never
      // user content, and it is exactly what a bug report needs.
      final firstLine = body.split('\n').first;
      final preview = firstLine.length > 60
          ? '${firstLine.substring(0, 60)}…'
          : firstLine;
      throw RealtimeSignalingException(
        'The live voice service returned an unexpected answer '
        '(starts with "$preview").',
      );
    }
    final answer = body.endsWith('\n') ? body : '$body\n';
    return RealtimeCallSession(callId: callId, answerSdp: answer);
  }

  void close() => _client.close();
}
