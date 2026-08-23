import { assert, assertEquals } from '@std/assert'

import {
  matchByName,
  nameTokens,
  normalizeOperationalName,
  strictOperationalKey,
} from './agent_name_match.ts'

Deno.test('normalization folds the Arabic spellings that differ between typists', () => {
  // Every pair below is the same name written two ways a real operator, a
  // real ASR transcript, and a real ChickMark data-entry screen produce.
  const pairs: [string, string][] = [
    ['بَدْر', 'بدر'],
    ['أحمد', 'احمد'],
    ['إبراهيم', 'ابراهيم'],
    ['آمنة', 'امنه'],
    ['مصطفى', 'مصطفي'],
    ['فاطمة', 'فاطمه'],
    ['مؤمن', 'مومن'],
    ['قائم', 'قايم'],
    ['بـــدر', 'بدر'],
    ['٢٥', '25'],
    ['۲۵', '25'],
    ['  Badr   Farm ', 'badr farm'],
  ]
  for (const [written, expected] of pairs) {
    assertEquals(normalizeOperationalName(written), expected, written)
  }
})

Deno.test('tokenization splits on every decoration separator a stored name uses', () => {
  assertEquals(
    nameTokens('بدر - 25 Oct 2025 - Avian'),
    ['بدر', '25', 'oct', '2025', 'avian'],
  )
  assertEquals(
    nameTokens('بدر / 25 oct 2025 (Avian)'),
    ['بدر', '25', 'oct', '2025', 'avian'],
  )
  assertEquals(nameTokens('   ---   '), [])
})

const FLOCKS = [
  { name: 'بدر - 25 Oct 2025 - Avian' },
  { name: 'السلام - 1 Jan 2026 - Ross' },
  { name: 'صابر - 3 Feb 2026 - Cobb' },
]

Deno.test('THE INCIDENT: a short spoken flock name resolves the decorated stored name', () => {
  const match = matchByName('بدر', FLOCKS, (flock) => flock.name)
  assertEquals(match?.tier, 'prefix')
  assertEquals(match?.matches, [FLOCKS[0]])
})

Deno.test('an exact match always beats a prefix or contained match', () => {
  const items = [{ name: 'بدر' }, { name: 'بدر - 25 Oct 2025 - Avian' }]
  const match = matchByName('بدر', items, (item) => item.name)
  assertEquals(match?.tier, 'exact')
  assertEquals(match?.matches, [items[0]])
})

Deno.test('a prefix match always beats a contained match', () => {
  const items = [
    { name: 'Ross Farm - North' },
    { name: 'Delta - Ross Farm - South' },
  ]
  const match = matchByName('ross farm', items, (item) => item.name)
  assertEquals(match?.tier, 'prefix')
  assertEquals(match?.matches, [items[0]])
})

Deno.test('a middle word run matches only as the weakest tier', () => {
  const match = matchByName('25 oct', FLOCKS, (flock) => flock.name)
  assertEquals(match?.tier, 'contains')
  assertEquals(match?.matches, [FLOCKS[0]])
})

Deno.test('matching never crosses a word boundary: ابر does not match صابر', () => {
  assertEquals(matchByName('ابر', FLOCKS, (flock) => flock.name), null)
})

Deno.test('every match in the winning tier is reported, so the caller can refuse to guess', () => {
  const items = [
    { name: 'بدر - 25 Oct 2025 - Avian' },
    { name: 'بدر - 3 Mar 2026 - Ross' },
  ]
  const match = matchByName('بدر', items, (item) => item.name)
  assertEquals(match?.tier, 'prefix')
  assertEquals(match?.matches.length, 2)
})

Deno.test('a short fragment never reaches the contains tier', () => {
  const items = [{ name: 'Delta ب Farm' }]
  // It would have matched exactly one item — which is precisely why it is
  // refused: a single character is a typo, not a name.
  assertEquals(matchByName('ب', items, (item) => item.name), null)
  // The same single character still resolves an actually-one-character name
  // through the exact tier.
  assertEquals(
    matchByName('ب', [{ name: 'ب' }], (item) => item.name)?.tier,
    'exact',
  )
})

Deno.test('DECORATION GUARD: a bare number never resolves a flock by its entry date', () => {
  // "flock 25" means house 25 or batch 25 to an operator. It must not
  // resolve, confidently and uniquely, to whichever flock happens to have
  // been entered on the 25th — that answer is then persisted as the
  // conversation's selected flock.
  for (const query of ['25', '٢٥', '2025', '03']) {
    assertEquals(
      matchByName(query, FLOCKS, (flock) => flock.name),
      null,
      query,
    )
  }
  // A number that IS the whole stored name still resolves, through the exact
  // tier, which the guard does not touch.
  assertEquals(
    matchByName('25', [{ name: '25' }], (item) => item.name)?.tier,
    'exact',
  )
})

Deno.test('the Arabic definite article matches in both directions, in the fallback tiers', () => {
  // Operators say the article about half the time.
  const withArticle = matchByName('البدر', FLOCKS, (flock) => flock.name)
  assertEquals(withArticle?.tier, 'prefix')
  assertEquals(withArticle?.matches, [FLOCKS[0]])

  // And the other way round: the database has the article, the caller does not.
  const stored = [{ name: 'الأمل - 2 Feb 2026 - Ross' }]
  const withoutArticle = matchByName('امل', stored, (item) => item.name)
  assertEquals(withoutArticle?.tier, 'prefix')

  // The exact tier stays strict: if both spellings exist as separate flocks,
  // the caller is told, not guessed at.
  const both = [{ name: 'الأمل' }, { name: 'أمل' }]
  assertEquals(matchByName('امل', both, (item) => item.name)?.tier, 'exact')
  assertEquals(matchByName('امل', both, (item) => item.name)?.matches.length, 1)
})

Deno.test('invisible characters do not split a name in half', () => {
  // U+061C ARABIC LETTER MARK is the one bidi control most likely to appear
  // in a mixed Arabic/Latin string — which is exactly what a decorated flock
  // name is. Because the tokenizer splits on anything that is not a letter or
  // a number, a survivor would not be ignored; it would cut the word in two
  // and the name would silently stop matching itself.
  for (const invisible of ['\u061C', '\u200B', '\u200F', '\uFEFF']) {
    assertEquals(nameTokens(`بد${invisible}ر`), ['بدر'], invisible)
  }
  // Same for the marks outside the common harakat range.
  for (const mark of ['\u0619', '\u06E1', '\u08E4']) {
    assertEquals(nameTokens(`بد${mark}ر`), ['بدر'], mark)
  }
})

Deno.test('Persian and Urdu keyboard letter forms fold to their Arabic equivalents', () => {
  const pairs: [string, string][] = [
    ['مبارک', 'مبارك'],
    ['علی', 'علي'],
    ['ہانی', 'هاني'],
    ['بڪر', 'بكر'],
  ]
  for (const [persian, arabic] of pairs) {
    assertEquals(
      normalizeOperationalName(persian),
      normalizeOperationalName(arabic),
      persian,
    )
  }
})

Deno.test('the strict key keeps apart the names the letter folds merge', () => {
  // Both are needed. The fold is what makes a spoken name findable; the
  // strict key is what stops "they fold together" being mistaken for "they
  // are the same name" — هانئ and هاني are different people.
  for (const [left, right] of [['هانئ', 'هاني'], ['سعدى', 'سعدي'], ['حمزة', 'حمزه']]) {
    assertEquals(normalizeOperationalName(left), normalizeOperationalName(right))
    assert(strictOperationalKey(left) !== strictOperationalKey(right))
  }
  // And it still ignores what is genuinely decoration.
  assertEquals(strictOperationalKey('بَدْر'), strictOperationalKey('بدر'))
  assertEquals(strictOperationalKey('٢٥'), strictOperationalKey('25'))
})

Deno.test('an empty or punctuation-only query matches nothing', () => {
  assertEquals(matchByName('', FLOCKS, (flock) => flock.name), null)
  assertEquals(matchByName('   ', FLOCKS, (flock) => flock.name), null)
  assertEquals(matchByName(' - / - ', FLOCKS, (flock) => flock.name), null)
})

Deno.test('a query longer than the stored name never matches', () => {
  assertEquals(
    matchByName('بدر - 25 Oct 2025 - Avian - Extra', FLOCKS, (flock) => flock.name),
    null,
  )
})
