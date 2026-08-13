import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/chat/models/chat_message.dart';
import 'package:hatchaudit/services/supabase/assistant_chat_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('request shape', () {
    test('send posts action/message/clientMessageId per the contract', () async {
      final recorder = _Recorder(_sendResponse());
      final service = AssistantChatService(
        rpc: recorder.call,
        clientMessageIdFactory: () => 'cid-1',
      );

      await service.sendMessage('  How did last hatch go?  ');

      expect(recorder.bodies.single, {
        'action': 'send',
        'message': 'How did last hatch go?',
        'clientMessageId': 'cid-1',
      });
    });

    test('an explicit clientMessageId is used verbatim so retry is idempotent', () async {
      final recorder = _Recorder(_sendResponse());
      final service = AssistantChatService(
        rpc: recorder.call,
        clientMessageIdFactory: () => 'never-used',
      );

      await service.sendMessage('hi', clientMessageId: 'cid-retry');

      expect(recorder.bodies.single['clientMessageId'], 'cid-retry');
    });

    test('history posts action=history with a clamped limit', () async {
      final recorder = _Recorder(_historyResponse());
      final service = AssistantChatService(rpc: recorder.call);

      await service.loadHistory(limit: 500);

      expect(recorder.bodies.single, {'action': 'history', 'limit': 100});
    });

    test('reset posts action=reset and nothing else', () async {
      final recorder = _Recorder({'conversationId': 'c1', 'cleared': true});
      final service = AssistantChatService(rpc: recorder.call);

      await service.resetConversation();

      expect(recorder.bodies.single, {'action': 'reset'});
    });

    test('an empty or over-long message never reaches the wire', () async {
      final recorder = _Recorder(_sendResponse());
      final service = AssistantChatService(rpc: recorder.call);

      await expectLater(
        service.sendMessage('   '),
        throwsA(isA<AssistantChatException>()),
      );
      await expectLater(
        service.sendMessage('x' * (assistantMessageMaxLength + 1)),
        throwsA(isA<AssistantChatException>()),
      );

      expect(recorder.bodies, isEmpty);
    });
  });

  group('sendVoice', () {
    test('sendVoice posts audioBase64 and parses transcript + audioBase64', () async {
      Map<String, dynamic>? capturedBody;
      final service = AssistantChatService(
        rpc: (body) async {
          capturedBody = body;
          return {
            'conversationId': 'conv-1',
            'userTurnId': 'turn-user',
            'replyTurnId': 'turn-reply',
            'reply': 'Hatch was 84%.',
            'transcript': 'What is the hatch rate?',
            'audioBase64': 'c3ludGg=',
            'createdAt': '2026-08-14T10:00:00.000Z',
            'language': 'en',
          };
        },
      );

      final reply = await service.sendVoice('aGVsbG8=', clientMessageId: 'cid-1');

      expect(capturedBody, {
        'action': 'send',
        'audioBase64': 'aGVsbG8=',
        'clientMessageId': 'cid-1',
      });
      expect(reply.reply, 'Hatch was 84%.');
      expect(reply.transcript, 'What is the hatch rate?');
      expect(reply.audioBase64, 'c3ludGg=');
    });

    test('sendVoice rejects an empty audio payload without a request', () async {
      var invoked = false;
      final service = AssistantChatService(
        rpc: (_) async {
          invoked = true;
          return <String, dynamic>{};
        },
      );

      await expectLater(
        () => service.sendVoice(''),
        throwsA(isA<AssistantChatException>()),
      );
      expect(invoked, isFalse);
    });
  });

  group('response parsing', () {
    test('send parses the reply into an assistant turn', () async {
      final service = AssistantChatService(
        rpc: _Recorder(_sendResponse()).call,
      );

      final reply = await service.sendMessage('hello');

      expect(reply.conversationId, 'conv-1');
      expect(reply.userTurnId, 'turn-user');
      expect(reply.replyTurnId, 'turn-reply');
      expect(reply.reply, 'Hatch was 84%.');
      expect(reply.language, 'en');
      expect(reply.createdAt, DateTime.utc(2026, 8, 14, 10));

      final message = reply.toAssistantMessage();
      expect(message.id, 'turn-reply');
      expect(message.role, ChatMessageRole.assistant);
      expect(message.status, ChatMessageStatus.sent);
      expect(message.text, 'Hatch was 84%.');
    });

    test('history parses turns oldest-first, preserving order and roles', () async {
      final service = AssistantChatService(
        rpc: _Recorder(_historyResponse()).call,
      );

      final history = await service.loadHistory();

      expect(history.conversationId, 'conv-1');
      expect(history.messages.map((m) => m.text), [
        'ما نسبة الفقس؟',
        'Hatch was 84%.',
      ]);
      expect(history.messages.map((m) => m.role), [
        ChatMessageRole.user,
        ChatMessageRole.assistant,
      ]);
      expect(history.messages.first.language, 'ar');
      expect(
        history.messages.every((m) => m.status == ChatMessageStatus.sent),
        isTrue,
      );
    });

    test('an empty history is a valid, empty conversation', () async {
      final service = AssistantChatService(
        rpc: _Recorder({
          'conversationId': 'conv-1',
          'messages': <dynamic>[],
        }).call,
      );

      final history = await service.loadHistory();

      expect(history.messages, isEmpty);
    });
  });

  group('error mapping', () {
    // Every contract status maps to its own finished sentence plus the machine
    // code the server sent, so the UI never shows a raw transport error.
    const cases = <int, ({String code, String fragment})>{
      400: (code: 'invalid_request', fragment: 'could not be sent'),
      401: (code: 'unauthenticated', fragment: 'sign-in expired'),
      403: (code: 'not_approved', fragment: 'not approved'),
      429: (code: 'rate_limited', fragment: 'Too many messages'),
      502: (code: 'agent_unavailable', fragment: 'unavailable right now'),
      500: (code: 'server_error', fragment: 'Something went wrong'),
    };

    for (final entry in cases.entries) {
      test('HTTP ${entry.key} -> ${entry.value.code}', () async {
        final service = AssistantChatService(
          rpc: (_) async => throw FunctionException(
            status: entry.key,
            details: {'error': 'server sentence', 'code': entry.value.code},
          ),
        );

        await expectLater(
          service.sendMessage('hello'),
          throwsA(
            isA<AssistantChatException>()
                .having((e) => e.code, 'code', entry.value.code)
                .having(
                  (e) => e.message,
                  'message',
                  contains(entry.value.fragment),
                ),
          ),
        );
      });
    }

    test('every mapped status produces a distinct sentence', () async {
      final messages = <String>{};
      for (final status in cases.keys) {
        final service = AssistantChatService(
          rpc: (_) async =>
              throw FunctionException(status: status, details: null),
        );
        try {
          await service.sendMessage('hello');
        } on AssistantChatException catch (error) {
          messages.add(error.message);
        }
      }
      expect(messages.length, cases.length);
    });

    test('a status with no body still yields the contract code', () async {
      final service = AssistantChatService(
        rpc: (_) async => throw FunctionException(status: 403, details: null),
      );

      await expectLater(
        service.sendMessage('hello'),
        throwsA(
          isA<AssistantChatException>().having(
            (e) => e.code,
            'code',
            'not_approved',
          ),
        ),
      );
    });

    test('a transport failure becomes one connection sentence', () async {
      final service = AssistantChatService(
        rpc: (_) async => throw const SocketException('no route'),
      );

      await expectLater(
        service.sendMessage('hello'),
        throwsA(
          isA<AssistantChatException>()
              .having((e) => e.code, 'code', 'network_error')
              .having((e) => e.message, 'message', contains('connection')),
        ),
      );
    });

    test('history and reset go through the same mapping', () async {
      AssistantChatService failing(int status) => AssistantChatService(
        rpc: (_) async => throw FunctionException(
          status: status,
          details: {'code': 'unauthenticated'},
        ),
      );

      await expectLater(
        failing(401).loadHistory(),
        throwsA(
          isA<AssistantChatException>().having(
            (e) => e.code,
            'code',
            'unauthenticated',
          ),
        ),
      );
      await expectLater(
        failing(401).resetConversation(),
        throwsA(
          isA<AssistantChatException>().having(
            (e) => e.code,
            'code',
            'unauthenticated',
          ),
        ),
      );
    });
  });

  test('the service source carries no url, key, or model literal', () {
    final source = File(
      'lib/services/supabase/assistant_chat_service.dart',
    ).readAsStringSync();

    // The function name is the one endpoint literal the contract fixes.
    expect(source, contains("'app-hatchery-agent'"));

    for (final forbidden in const [
      'http://',
      'https://',
      'supabase.co',
      'SUPABASE_URL',
      'SUPABASE_ANON_KEY',
      'anonKey',
      'apikey',
      'eyJ',
      'sk-',
      'gpt-',
      'claude-',
      'gemini',
      'OPENAI',
      'ANTHROPIC',
    ]) {
      expect(
        source.contains(forbidden),
        isFalse,
        reason: 'assistant_chat_service.dart must not contain "$forbidden"',
      );
    }
  });
}

class _Recorder {
  _Recorder(this.response);

  final Object? response;
  final List<Map<String, dynamic>> bodies = [];

  Future<dynamic> call(Map<String, dynamic> body) async {
    bodies.add(Map<String, dynamic>.from(body));
    return response;
  }
}

Map<String, dynamic> _sendResponse() => {
  'conversationId': 'conv-1',
  'userTurnId': 'turn-user',
  'replyTurnId': 'turn-reply',
  'reply': 'Hatch was 84%.',
  'language': 'en',
  'createdAt': '2026-08-14T10:00:00.000Z',
};

Map<String, dynamic> _historyResponse() => {
  'conversationId': 'conv-1',
  'messages': [
    {
      'id': 'turn-1',
      'role': 'user',
      'text': 'ما نسبة الفقس؟',
      'language': 'ar',
      'createdAt': '2026-08-14T09:59:00.000Z',
    },
    {
      'id': 'turn-2',
      'role': 'assistant',
      'text': 'Hatch was 84%.',
      'language': 'en',
      'createdAt': '2026-08-14T10:00:00.000Z',
    },
  ],
};
