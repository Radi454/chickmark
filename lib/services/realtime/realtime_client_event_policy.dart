/// What the client is allowed to do with an OpenAI Realtime data-channel
/// event.
///
/// ## Client event policy (mandatory)
///
/// The data channel *will* deliver tool / function-call events. Flutter must:
///
/// * **never execute them** — only the Cloud Run sideband runs tools, because
///   only it holds the caller's authenticated scope;
/// * **never relay them** to any backend — a relayed tool call would be an
///   unauthenticated instruction path into the agent;
/// * **never log their arguments or results** — they carry customer data;
/// * **drop unrecognised types silently** — a server-side addition must not
///   crash or leak.
///
/// Every event therefore maps to one of the presentation-only actions below,
/// or to [RealtimeClientEventAction.ignore]. There is no action that runs
/// anything.
enum RealtimeClientEventAction {
  userSpeechStarted,
  userSpeechStopped,
  assistantThinking,
  assistantSpeaking,
  assistantTurnComplete,
  assistantCaption,
  userCaption,
  remoteError,

  /// Recognised-but-irrelevant, tool-related, or entirely unknown. Dropped.
  ignore,
}

class RealtimeClientEvent {
  const RealtimeClientEvent(this.action, {this.text, this.isFinal = false});

  final RealtimeClientEventAction action;

  /// Caption text, for the two caption actions only. Never tool arguments.
  final String? text;

  /// True for the terminal frame of a caption (`.done` / `.completed`), which
  /// closes the current caption line instead of extending it.
  final bool isFinal;

  static const RealtimeClientEvent ignored = RealtimeClientEvent(
    RealtimeClientEventAction.ignore,
  );
}

/// True when [raw] is a tool / function-call event in any of its shapes.
///
/// Matches on the event type *and* on the nested item type, because
/// `response.output_item.added` / `.done` carry the function call in
/// `item.type` rather than in the event type itself.
bool isToolEvent(Map<String, dynamic> raw) {
  final type = raw['type']?.toString() ?? '';
  if (type.contains('function_call') || type.contains('tool')) return true;
  final item = raw['item'];
  if (item is Map) {
    final itemType = item['type']?.toString() ?? '';
    if (itemType.contains('function_call') || itemType.contains('tool')) {
      return true;
    }
  }
  return false;
}

/// Maps one decoded data-channel event to a presentation-only action.
///
/// Tool events short-circuit to [RealtimeClientEventAction.ignore] *before*
/// any other matching, so no future branch can accidentally act on one.
RealtimeClientEvent classifyClientEvent(Map<String, dynamic> raw) {
  if (isToolEvent(raw)) return RealtimeClientEvent.ignored;
  final type = raw['type']?.toString();
  switch (type) {
    case 'input_audio_buffer.speech_started':
      return const RealtimeClientEvent(
        RealtimeClientEventAction.userSpeechStarted,
      );
    case 'input_audio_buffer.speech_stopped':
      return const RealtimeClientEvent(
        RealtimeClientEventAction.userSpeechStopped,
      );
    case 'response.created':
      return const RealtimeClientEvent(
        RealtimeClientEventAction.assistantThinking,
      );
    case 'response.audio.delta':
    case 'response.output_audio.delta':
      return const RealtimeClientEvent(
        RealtimeClientEventAction.assistantSpeaking,
      );
    case 'response.done':
      return const RealtimeClientEvent(
        RealtimeClientEventAction.assistantTurnComplete,
      );
    case 'response.audio_transcript.delta':
    case 'response.audio_transcript.done':
    case 'response.output_audio_transcript.delta':
    case 'response.output_audio_transcript.done':
      return RealtimeClientEvent(
        RealtimeClientEventAction.assistantCaption,
        text: _text(raw['delta']) ?? _text(raw['transcript']),
        isFinal: type!.endsWith('.done'),
      );
    case 'conversation.item.input_audio_transcription.delta':
    case 'conversation.item.input_audio_transcription.completed':
      return RealtimeClientEvent(
        RealtimeClientEventAction.userCaption,
        text: _text(raw['delta']) ?? _text(raw['transcript']),
        isFinal: type!.endsWith('.completed'),
      );
    case 'error':
      return const RealtimeClientEvent(RealtimeClientEventAction.remoteError);
    default:
      return RealtimeClientEvent.ignored;
  }
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}
