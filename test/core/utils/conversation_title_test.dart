import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/utils/conversation_title.dart';

// Mirrors supabase/functions/app-hatchery-agent/conversation_title_test.ts —
// same cases, same expectations, so the client and server derivers can never
// silently drift apart.
void main() {
  test('empty or whitespace-only text yields no title', () {
    expect(deriveConversationTitle(''), isNull);
    expect(deriveConversationTitle('   '), isNull);
    expect(deriveConversationTitle('\n\t  \n'), isNull);
  });

  test('short text is kept as-is after trimming and trailing punctuation strip', () {
    expect(deriveConversationTitle('  How is the flock?  '), 'How is the flock');
  });

  test('internal whitespace is collapsed', () {
    expect(
      deriveConversationTitle('How   is\n\nthe   flock'),
      'How is the flock',
    );
  });

  test('text over 48 chars cuts at the last word boundary at or after char 12', () {
    const text =
        'What is the current hatchability trend for flock 12 over the last month?';
    final title = deriveConversationTitle(text);
    final window = text.substring(0, 48);
    final lastSpace = window.lastIndexOf(' ');
    final expected = window.substring(0, lastSpace);
    expect(title, expected);
    expect(title != null && title.length <= 48, isTrue);
  });

  test('text with no word boundary in range 12..48 hard-cuts at 48', () {
    final text = 'x' * 60;
    expect(deriveConversationTitle(text), 'x' * 48);
  });

  test('trailing punctuation is stripped after truncation', () {
    expect(deriveConversationTitle('Is this normal???'), 'Is this normal');
    expect(deriveConversationTitle('Wait, really?!  '), 'Wait, really');
    expect(deriveConversationTitle('Hello...'), 'Hello');
  });

  test('a boundary exactly at char 12 is used', () {
    const text = 'What is up right now with the flock health metrics overall';
    final title = deriveConversationTitle(text);
    final window = text.substring(0, 48);
    final lastSpace = window.lastIndexOf(' ');
    final expected = window
        .substring(0, lastSpace)
        .replaceAll(RegExp(r'[.,;:!?،؛\s]+$'), '');
    expect(title, expected);
  });

  test('Arabic text is handled correctly', () {
    expect(
      deriveConversationTitle('  ما هي نسبة الفقس اليوم؟  '),
      'ما هي نسبة الفقس اليوم؟',
    );
  });

  test('long Arabic text truncates at a word boundary and strips Arabic punctuation', () {
    const text =
        'ما هي نسبة الفقس المتوقعة لهذا القطيع خلال الأسبوعين القادمين في المزرعة؟';
    final title = deriveConversationTitle(text);
    final window = text.substring(0, 48);
    final lastSpace = window.lastIndexOf(' ');
    final expectedRaw = lastSpace >= 12
        ? window.substring(0, lastSpace)
        : window;
    final expected = expectedRaw
        .replaceAll(RegExp(r'[.,;:!?،؛\s]+$'), '')
        .trim();
    expect(title, expected);
    expect(title != null && title.length <= 48, isTrue);
  });

  test('Arabic trailing punctuation (، and ؛) is stripped', () {
    expect(deriveConversationTitle('مرحبا،'), 'مرحبا');
    expect(deriveConversationTitle('مرحبا؛'), 'مرحبا');
  });

  test('a title that becomes empty after stripping punctuation is null', () {
    expect(deriveConversationTitle('...'), isNull);
    expect(deriveConversationTitle('???'), isNull);
  });
}
