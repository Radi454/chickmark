import { assertEquals } from '@std/assert'

import { deriveConversationTitle } from './conversation_title.ts'

Deno.test('empty or whitespace-only text yields no title', () => {
  assertEquals(deriveConversationTitle(''), null)
  assertEquals(deriveConversationTitle('   '), null)
  assertEquals(deriveConversationTitle('\n\t  \n'), null)
})

Deno.test('short text is kept as-is after trimming and trailing punctuation strip', () => {
  assertEquals(deriveConversationTitle('  How is the flock?  '), 'How is the flock')
})

Deno.test('internal whitespace is collapsed', () => {
  assertEquals(
    deriveConversationTitle('How   is\n\nthe   flock'),
    'How is the flock',
  )
})

Deno.test('text over 48 chars cuts at the last word boundary at or after char 12', () => {
  const text =
    'What is the current hatchability trend for flock 12 over the last month?'
  const title = deriveConversationTitle(text)
  // window = first 48 chars: 'What is the current hatchability trend for fl'
  // (48 chars) -> last space before/at 48 is before 'fl'
  const window = text.slice(0, 48)
  const lastSpace = window.lastIndexOf(' ')
  const expected = window.slice(0, lastSpace)
  assertEquals(title, expected)
  assertEquals(title !== null && title.length <= 48, true)
});

Deno.test('text with no word boundary in range 12..48 hard-cuts at 48', () => {
  const text = 'x'.repeat(60)
  const title = deriveConversationTitle(text)
  assertEquals(title, 'x'.repeat(48))
})

Deno.test('trailing punctuation is stripped after truncation', () => {
  assertEquals(deriveConversationTitle('Is this normal???'), 'Is this normal')
  assertEquals(deriveConversationTitle('Wait, really?!  '), 'Wait, really')
  assertEquals(deriveConversationTitle('Hello...'), 'Hello')
})

Deno.test('a boundary exactly at char 12 is used', () => {
  // 'What is up?' has length 12, no cut needed since text is short overall,
  // so exercise a longer example with a space at position >=12.
  const text = 'What is up right now with the flock health metrics overall'
  const title = deriveConversationTitle(text)
  const window = text.slice(0, 48)
  const lastSpace = window.lastIndexOf(' ')
  assertEquals(title, window.slice(0, lastSpace).replace(/[.,;:!?،؛\s]+$/u, ''))
})

Deno.test('Arabic text is handled correctly', () => {
  assertEquals(
    deriveConversationTitle('  ما هي نسبة الفقس اليوم؟  '),
    'ما هي نسبة الفقس اليوم؟',
  )
})

Deno.test('long Arabic text truncates at a word boundary and strips Arabic punctuation', () => {
  const text =
    'ما هي نسبة الفقس المتوقعة لهذا القطيع خلال الأسبوعين القادمين في المزرعة؟'
  const title = deriveConversationTitle(text)
  const window = text.slice(0, 48)
  const lastSpace = window.lastIndexOf(' ')
  const expectedRaw = lastSpace >= 12 ? window.slice(0, lastSpace) : window
  const expected = expectedRaw.replace(/[.,;:!?،؛\s]+$/u, '').trim()
  assertEquals(title, expected)
  assertEquals(title !== null && title.length <= 48, true)
})

Deno.test('Arabic trailing punctuation (، and ؛) is stripped', () => {
  assertEquals(deriveConversationTitle('مرحبا،'), 'مرحبا')
  assertEquals(deriveConversationTitle('مرحبا؛'), 'مرحبا')
})

Deno.test('a title that becomes empty after stripping punctuation is null', () => {
  assertEquals(deriveConversationTitle('...'), null)
  assertEquals(deriveConversationTitle('???'), null)
})
