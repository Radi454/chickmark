import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/realtime/realtime_client_event_policy.dart';

void main() {
  group('tool events', () {
    test('every function-call shape classifies as a tool event', () {
      final toolEvents = <Map<String, dynamic>>[
        {'type': 'response.function_call_arguments.delta'},
        {'type': 'response.function_call_arguments.done'},
        {
          'type': 'response.output_item.added',
          'item': {'type': 'function_call'},
        },
        {
          'type': 'response.output_item.done',
          'item': {'type': 'function_call'},
        },
        {
          'type': 'conversation.item.created',
          'item': {'type': 'function_call_output'},
        },
        {'type': 'session.updated.tools'},
      ];

      for (final event in toolEvents) {
        expect(isToolEvent(event), isTrue, reason: '${event['type']}');
        expect(
          classifyClientEvent(event).action,
          RealtimeClientEventAction.ignore,
          reason: 'Flutter must never act on ${event['type']}',
        );
      }
    });

    test('a tool event never carries text out of the classifier', () {
      final event = classifyClientEvent({
        'type': 'response.function_call_arguments.done',
        'arguments': '{"customerId":"secret"}',
        'delta': 'secret',
        'transcript': 'secret',
      });

      expect(event.action, RealtimeClientEventAction.ignore);
      expect(event.text, isNull);
    });

    test('a plain transcript event is not mistaken for a tool event', () {
      expect(isToolEvent({'type': 'response.audio_transcript.delta'}), isFalse);
    });
  });

  group('presentation events', () {
    test('speech boundaries', () {
      expect(
        classifyClientEvent({
          'type': 'input_audio_buffer.speech_started',
        }).action,
        RealtimeClientEventAction.userSpeechStarted,
      );
      expect(
        classifyClientEvent({
          'type': 'input_audio_buffer.speech_stopped',
        }).action,
        RealtimeClientEventAction.userSpeechStopped,
      );
    });

    test('turn lifecycle', () {
      expect(
        classifyClientEvent({'type': 'response.created'}).action,
        RealtimeClientEventAction.assistantThinking,
      );
      expect(
        classifyClientEvent({'type': 'response.audio.delta'}).action,
        RealtimeClientEventAction.assistantSpeaking,
      );
      expect(
        classifyClientEvent({'type': 'response.output_audio.delta'}).action,
        RealtimeClientEventAction.assistantSpeaking,
      );
      expect(
        classifyClientEvent({'type': 'response.done'}).action,
        RealtimeClientEventAction.assistantTurnComplete,
      );
      expect(
        classifyClientEvent({'type': 'error'}).action,
        RealtimeClientEventAction.remoteError,
      );
    });

    test('assistant captions carry the delta and mark the final frame', () {
      final delta = classifyClientEvent({
        'type': 'response.audio_transcript.delta',
        'delta': 'Hatch ',
      });
      final done = classifyClientEvent({
        'type': 'response.audio_transcript.done',
        'transcript': 'Hatch of 84 percent.',
      });

      expect(delta.action, RealtimeClientEventAction.assistantCaption);
      expect(delta.text, 'Hatch ');
      expect(delta.isFinal, isFalse);
      expect(done.isFinal, isTrue);
      expect(done.text, 'Hatch of 84 percent.');
    });

    test('user captions come from the input transcription events', () {
      final done = classifyClientEvent({
        'type': 'conversation.item.input_audio_transcription.completed',
        'transcript': 'How did last week hatch?',
      });

      expect(done.action, RealtimeClientEventAction.userCaption);
      expect(done.text, 'How did last week hatch?');
      expect(done.isFinal, isTrue);
    });
  });

  group('unknown events', () {
    test('are dropped silently rather than throwing', () {
      for (final event in <Map<String, dynamic>>[
        <String, dynamic>{},
        {'type': 'some.future.event'},
        {'type': 42},
        {'nope': true},
      ]) {
        expect(
          classifyClientEvent(event).action,
          RealtimeClientEventAction.ignore,
        );
      }
    });
  });
}
