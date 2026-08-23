import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/chat/models/chat_message.dart';
import 'package:hatchaudit/features/chat/providers/assistant_provider.dart';
import 'package:hatchaudit/services/audio/assistant_audio_recorder.dart';
import 'package:hatchaudit/services/supabase/assistant_chat_service.dart';

import 'fake_assistant_audio.dart';
import 'fake_assistant_chat_port.dart';

void main() {
  AssistantProvider providerWith(FakeAssistantChatPort port) {
    var counter = 0;
    return AssistantProvider(
      port: port,
      clientMessageIdFactory: () => 'cid-${++counter}',
    );
  }

  AssistantProvider voiceProviderWith(
    FakeAssistantChatPort port, {
    FakeAssistantAudioRecorder? recorder,
    FakeAssistantAudioPlayer? player,
  }) {
    var counter = 0;
    return AssistantProvider(
      port: port,
      clientMessageIdFactory: () => 'cid-${++counter}',
      audioRecorder: recorder ?? FakeAssistantAudioRecorder(),
      audioPlayer: player ?? FakeAssistantAudioPlayer(),
    );
  }

  test('load populates history oldest-first and lands in loaded', () async {
    final port = FakeAssistantChatPort(history: twoTurnHistory());
    final provider = providerWith(port);

    expect(provider.loadState, AssistantLoadState.uninitialized);
    await provider.load();

    expect(provider.loadState, AssistantLoadState.loaded);
    expect(provider.messages.map((m) => m.text), [
      'ما نسبة الفقس؟',
      'Hatch was 84%.',
    ]);
    expect(provider.error, isNull);
  });

  test('a failed load sets the error state and message', () async {
    final port = FakeAssistantChatPort(
      historyError: const AssistantChatException(
        'Your sign-in expired. Sign in again to keep chatting.',
        'unauthenticated',
      ),
    );
    final provider = providerWith(port);

    await provider.load();

    expect(provider.loadState, AssistantLoadState.error);
    expect(provider.error, contains('sign-in expired'));
    expect(provider.messages, isEmpty);
  });

  test('send appends the user turn optimistically, then the reply', () async {
    final port = FakeAssistantChatPort(manualSend: true);
    final provider = providerWith(port);

    final pending = provider.send('How did last hatch go?');
    await Future<void>.value();

    // The typed text is on screen before the network answers.
    expect(provider.isSending, isTrue);
    expect(provider.messages, hasLength(1));
    expect(provider.messages.single.text, 'How did last hatch go?');
    expect(provider.messages.single.role, ChatMessageRole.user);
    expect(provider.messages.single.status, ChatMessageStatus.sending);

    port.completeSend(reply('Hatch was 84%.'));
    await pending;

    expect(provider.isSending, isFalse);
    expect(provider.messages, hasLength(2));
    expect(provider.messages.first.status, ChatMessageStatus.sent);
    expect(provider.messages.first.id, 'turn-user');
    expect(provider.messages.last.role, ChatMessageRole.assistant);
    expect(provider.messages.last.text, 'Hatch was 84%.');
    expect(provider.error, isNull);
  });

  test('send trims the message before it reaches the port', () async {
    final port = FakeAssistantChatPort();
    final provider = providerWith(port);

    await provider.send('   spaced   ');

    expect(port.sentMessages.single, 'spaced');
  });

  test('a failed send marks the turn failed and keeps the text', () async {
    final port = FakeAssistantChatPort(
      sendError: const AssistantChatException(
        'The assistant is unavailable right now. Try again shortly.',
        'agent_unavailable',
      ),
    );
    final provider = providerWith(port);

    await provider.send('keep me');

    expect(provider.isSending, isFalse);
    expect(provider.messages, hasLength(1));
    expect(provider.messages.single.text, 'keep me');
    expect(provider.messages.single.status, ChatMessageStatus.failed);
    expect(provider.error, contains('unavailable right now'));
  });

  test(
    'retry re-sends the failed turn under the same clientMessageId',
    () async {
      final port = FakeAssistantChatPort(
        sendError: const AssistantChatException('nope', 'server_error'),
      );
      final provider = providerWith(port);

      await provider.send('retry me');
      final failed = provider.messages.single;
      expect(failed.status, ChatMessageStatus.failed);

      port.sendError = null;
      port.nextReply = reply('Recovered.');
      await provider.retry(failed);

      expect(provider.messages, hasLength(2));
      expect(provider.messages.first.status, ChatMessageStatus.sent);
      expect(provider.messages.last.text, 'Recovered.');
      expect(provider.error, isNull);

      // Same idempotency key both times — the server must not store two turns.
      expect(port.sentClientMessageIds, ['cid-1', 'cid-1']);
      expect(port.sentMessages, ['retry me', 'retry me']);
    },
  );

  test('clear resets the conversation and empties the list', () async {
    final port = FakeAssistantChatPort(history: twoTurnHistory());
    final provider = providerWith(port);
    await provider.load();
    expect(provider.messages, hasLength(2));

    await provider.clear();

    expect(port.resetCount, 1);
    expect(provider.messages, isEmpty);
    expect(provider.error, isNull);
  });

  test('a failed clear surfaces an error and keeps the messages', () async {
    final port = FakeAssistantChatPort(
      history: twoTurnHistory(),
      resetError: const AssistantChatException('nope', 'server_error'),
    );
    final provider = providerWith(port);
    await provider.load();

    await provider.clear();

    expect(provider.messages, hasLength(2));
    expect(provider.error, isNotNull);
  });

  test('a message over 4000 chars is refused without a request', () async {
    final port = FakeAssistantChatPort();
    final provider = providerWith(port);

    await provider.send('x' * (AssistantProvider.maxMessageLength + 1));

    expect(port.sentMessages, isEmpty);
    expect(provider.messages, isEmpty);
    expect(provider.error, contains('too long'));
  });

  test('exactly 4000 chars is allowed through', () async {
    final port = FakeAssistantChatPort();
    final provider = providerWith(port);

    await provider.send('x' * AssistantProvider.maxMessageLength);

    expect(port.sentMessages, hasLength(1));
    expect(provider.error, isNull);
  });

  test('empty and whitespace-only sends are no-ops', () async {
    final port = FakeAssistantChatPort();
    final provider = providerWith(port);
    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.send('');
    await provider.send('   \n\t ');

    expect(port.sentMessages, isEmpty);
    expect(provider.messages, isEmpty);
    expect(notifications, 0);
  });

  test('a second send is ignored while one is in flight', () async {
    final port = FakeAssistantChatPort(manualSend: true);
    final provider = providerWith(port);

    final first = provider.send('one');
    await Future<void>.value();
    await provider.send('two');

    expect(provider.messages, hasLength(1));

    port.completeSend(reply('done'));
    await first;
    expect(port.sentMessages, ['one']);
  });

  test('clearError dismisses the banner without touching the list', () async {
    final port = FakeAssistantChatPort(
      sendError: const AssistantChatException('nope', 'server_error'),
    );
    final provider = providerWith(port);
    await provider.send('kept');
    expect(provider.error, isNotNull);

    provider.clearError();

    expect(provider.error, isNull);
    expect(provider.messages.single.text, 'kept');
  });

  test('startRecording flips isRecording on success', () async {
    final recorder = FakeAssistantAudioRecorder();
    final provider = voiceProviderWith(
      FakeAssistantChatPort(),
      recorder: recorder,
    );

    await provider.startRecording();

    expect(provider.isRecording, isTrue);
    expect(recorder.startCount, 1);
    expect(provider.error, isNull);
  });

  test(
    'startRecording surfaces a permission error without recording',
    () async {
      final recorder = FakeAssistantAudioRecorder()
        ..startError = const AssistantAudioException(
          'Microphone access is needed to ask by voice.',
        );
      final provider = voiceProviderWith(
        FakeAssistantChatPort(),
        recorder: recorder,
      );

      await provider.startRecording();

      expect(provider.isRecording, isFalse);
      expect(provider.error, contains('Microphone access'));
    },
  );

  test(
    'stopRecordingAndSend plays the chime, then sends, then plays the reply',
    () async {
      final recorder = FakeAssistantAudioRecorder();
      final player = FakeAssistantAudioPlayer();
      final port = FakeAssistantChatPort(
        nextReply: AssistantChatReply(
          conversationId: 'conv-1',
          userTurnId: 'turn-user',
          replyTurnId: 'turn-reply',
          reply: 'Hatch was 84%.',
          createdAt: DateTime.utc(2026, 8, 14, 10),
          language: 'en',
          transcript: 'What is the hatch rate?',
          audioBase64: 'YXVkaW8tcmVwbHk=',
        ),
      );
      final provider = voiceProviderWith(
        port,
        recorder: recorder,
        player: player,
      );

      await provider.startRecording();
      await provider.stopRecordingAndSend();

      expect(recorder.stopCount, 1);
      expect(port.sentAudio, ['ZmFrZS1hdWRpbw==']);
      expect(player.playedAssets, ['audio/filler_chime.wav']);
      expect(player.playedBase64, ['YXVkaW8tcmVwbHk=']);
      expect(provider.messages, hasLength(2));
      expect(provider.messages.first.text, 'What is the hatch rate?');
      expect(provider.messages.first.role, ChatMessageRole.user);
      expect(provider.messages.last.text, 'Hatch was 84%.');
      expect(provider.isAwaitingVoiceReply, isFalse);
      expect(provider.isSpeaking, isFalse);
    },
  );

  ChatMessage assistantMessageWithAudio({String id = 'reply-1'}) => ChatMessage(
    id: id,
    role: ChatMessageRole.assistant,
    text: 'Hatch was 84%.',
    createdAt: DateTime.utc(2026, 8, 14, 10),
    audioBase64: 'YXVkaW8=',
  );

  test(
    'playMessageAudio plays the message and reports playing state',
    () async {
      final player = FakeAssistantAudioPlayer()..manualCompletion = true;
      final provider = voiceProviderWith(
        FakeAssistantChatPort(),
        player: player,
      );
      final message = assistantMessageWithAudio();

      final playing = provider.playMessageAudio(message);
      await Future<void>.value();

      expect(provider.playingMessageId, message.id);
      expect(provider.isPaused, isFalse);
      expect(provider.isSpeaking, isTrue);
      expect(player.playedBase64, ['YXVkaW8=']);

      player.completePlayback();
      await playing;

      expect(provider.playingMessageId, isNull);
      expect(provider.isSpeaking, isFalse);
    },
  );

  test(
    'pausePlayback pauses without clearing playingMessageId, resume continues',
    () async {
      final player = FakeAssistantAudioPlayer()..manualCompletion = true;
      final provider = voiceProviderWith(
        FakeAssistantChatPort(),
        player: player,
      );
      final message = assistantMessageWithAudio();

      final playing = provider.playMessageAudio(message);
      await Future<void>.value();

      await provider.pausePlayback();
      expect(provider.playingMessageId, message.id);
      expect(provider.isPaused, isTrue);
      expect(provider.isSpeaking, isFalse);
      expect(player.pauseCount, 1);

      await provider.resumePlayback();
      expect(provider.isPaused, isFalse);
      expect(provider.isSpeaking, isTrue);
      expect(player.resumeCount, 1);

      player.completePlayback();
      await playing;
    },
  );

  test(
    'playing a second message stops the first and takes ownership',
    () async {
      final player = FakeAssistantAudioPlayer()..manualCompletion = true;
      final provider = voiceProviderWith(
        FakeAssistantChatPort(),
        player: player,
      );
      final first = assistantMessageWithAudio(id: 'reply-1');
      final second = assistantMessageWithAudio(id: 'reply-2');

      final firstPlaying = provider.playMessageAudio(first);
      await Future<void>.value();
      expect(provider.playingMessageId, 'reply-1');

      // A second play call resolves the first's pending future too (matching
      // the real player's completer-interruption contract).
      final secondPlaying = provider.playMessageAudio(second);
      await Future<void>.value();

      expect(provider.playingMessageId, 'reply-2');
      await firstPlaying;
      // The first call's finally-block must not clobber the second's state —
      // it is no longer the current owner.
      expect(provider.playingMessageId, 'reply-2');

      player.completePlayback();
      await secondPlaying;
      expect(provider.playingMessageId, isNull);
    },
  );

  test('replay restarts an already-finished message', () async {
    final player = FakeAssistantAudioPlayer();
    final provider = voiceProviderWith(FakeAssistantChatPort(), player: player);
    final message = assistantMessageWithAudio();

    await provider.playMessageAudio(message);
    expect(player.playedBase64, ['YXVkaW8=']);

    await provider.playMessageAudio(message);
    expect(player.playedBase64, ['YXVkaW8=', 'YXVkaW8=']);
  });

  test('clear stops in-flight playback', () async {
    final player = FakeAssistantAudioPlayer()..manualCompletion = true;
    final port = FakeAssistantChatPort(history: twoTurnHistory());
    final provider = voiceProviderWith(port, player: player);
    await provider.load();

    final playing = provider.playMessageAudio(assistantMessageWithAudio());
    await Future<void>.value();
    expect(provider.playingMessageId, isNotNull);

    await provider.clear();
    await playing;

    expect(provider.playingMessageId, isNull);
    expect(provider.messages, isEmpty);
  });

  test(
    'a playback failure after a successful send does not surface a send error',
    () async {
      final recorder = FakeAssistantAudioRecorder();
      final player = FakeAssistantAudioPlayer()
        ..playBase64Error = Exception('no output device');
      final port = FakeAssistantChatPort(
        nextReply: AssistantChatReply(
          conversationId: 'conv-1',
          userTurnId: 'turn-user',
          replyTurnId: 'turn-reply',
          reply: 'Hatch was 84%.',
          createdAt: DateTime.utc(2026, 8, 14, 10),
          language: 'en',
          transcript: 'What is the hatch rate?',
          audioBase64: 'YXVkaW8tcmVwbHk=',
        ),
      );
      final provider = voiceProviderWith(
        port,
        recorder: recorder,
        player: player,
      );

      await provider.startRecording();
      await provider.stopRecordingAndSend();

      // The send itself succeeded: both turns are delivered and marked sent.
      expect(provider.messages, hasLength(2));
      expect(provider.messages.first.status, ChatMessageStatus.sent);
      expect(provider.messages.first.text, 'What is the hatch rate?');
      expect(provider.messages.last.text, 'Hatch was 84%.');
      // A local playback failure must not be reported as a send failure.
      expect(provider.error, isNull);
      expect(provider.isAwaitingVoiceReply, isFalse);
      expect(provider.isSpeaking, isFalse);
    },
  );

  test('stopRecordingAndSend with no clip is a no-op', () async {
    final recorder = FakeAssistantAudioRecorder()..nextClip = null;
    final port = FakeAssistantChatPort();
    final provider = voiceProviderWith(port, recorder: recorder);

    await provider.startRecording();
    await provider.stopRecordingAndSend();

    expect(port.sentAudio, isEmpty);
    expect(provider.messages, isEmpty);
  });

  test(
    'a failed voice send marks the turn failed and keeps a placeholder',
    () async {
      final recorder = FakeAssistantAudioRecorder();
      final port = FakeAssistantChatPort(
        sendError: const AssistantChatException(
          'The assistant is unavailable right now. Try again shortly.',
          'agent_unavailable',
        ),
      );
      final provider = voiceProviderWith(port, recorder: recorder);

      await provider.startRecording();
      await provider.stopRecordingAndSend();

      expect(provider.messages, hasLength(1));
      expect(provider.messages.single.status, ChatMessageStatus.failed);
      expect(provider.error, contains('unavailable right now'));
    },
  );
}
