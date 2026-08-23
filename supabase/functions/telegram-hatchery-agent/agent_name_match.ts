// Operational-name matching for every tool that resolves a user-spoken name
// (customer, flock, hatchery, …) against a decorated database name.
//
// WHY THIS EXISTS
//
// Database display names are DECORATED. A flock is stored as
// `بدر - 25 Oct 2025 - Avian`: the operator's short name, plus the entry date,
// plus the breed, joined with hyphens. Nobody says that out loud. They say
// `بدر`. Until this module existed, `resolve_customer_flock` compared the
// spoken name to the stored name with `===` after normalization, so every
// natural utterance missed, the tool answered `flock_not_found`, and the model
// re-asked the same question — the exact production incident this file was
// written for.
//
// THE LADDER. Matching is tried in strictly decreasing confidence, and the
// FIRST tier that produces any match wins outright; later tiers are never
// consulted, so a weak match can never outvote a strong one:
//
//   1. `exact`    — the whole normalized token sequence is identical.
//   2. `prefix`   — the stored name BEGINS with the spoken one, on a token
//                   boundary. `بدر` → `بدر - 25 Oct 2025 - Avian`.
//   3. `contains` — the spoken token run appears anywhere inside the stored
//                   one, on token boundaries. `25 Oct` → the same flock.
//
// AMBIGUITY IS NEVER RESOLVED BY GUESSING. This module reports every match in
// the winning tier and says which tier that was; deciding what to do with two
// matches is the caller's job, and every caller in this repo answers with an
// ambiguity result carrying the candidates' IDs rather than picking one.
//
// Tokens, not substrings: matching on raw substrings would let `ابر` match
// `صابر`, which is a different farm. Splitting on non-alphanumerics and
// comparing token RUNS means a match always starts and ends on a word
// boundary, in Arabic and Latin alike.

/**
 * Fold the cosmetic variation out of an operational name.
 *
 * Arabic is written with several interchangeable spellings of the same sound
 * and the same letter, and a name typed on a phone keyboard, dictated to an
 * ASR model, and typed into ChickMark by a third person will differ in every
 * one of them:
 *
 *   * harakat/tashkeel and the dagger alef are decoration and are dropped;
 *   * tatweel (ـ) is a stretching glyph with no phonetic value;
 *   * أ إ آ ٱ all stand for ا, and ى for ي, ة for ه, ؤ for و, ئ for ي —
 *     writers pick whichever their keyboard offers;
 *   * Arabic-Indic (٠١٢…) and Eastern Arabic-Indic (۰۱۲…) digits are the same
 *     numbers as 0-9 and must compare equal to them;
 *   * zero-width joiners/marks survive copy-paste and are invisible.
 *
 * Latin text is folded to lower case in the same pass. The result is a
 * comparison key only — it is never shown to anyone and never stored.
 */
export function normalizeOperationalName(value: string): string {
  return foldLetters(strictOperationalKey(value))
}

/**
 * The same fold MINUS the letter equivalences — NFKC, marks, invisibles,
 * digits, whitespace and case only.
 *
 * This exists so a caller can tell "these two names are genuinely written the
 * same" from "these two names collapse together once hamza and ta-marbuta are
 * folded". They are not the same question. `هانئ` and `هاني` are different
 * people; `سعدى` and `سعدي` are different people. The letter folds are what
 * make a spoken name findable at all, but they must not be mistaken for
 * evidence that two DATABASE rows carry the same name — see the tenant guard
 * in `resolveCustomerFlock`, which may only disambiguate across customers
 * when the strict keys agree too.
 */
export function strictOperationalKey(value: string): string {
  return value
    .normalize('NFKC')
    // Every nonspacing mark: harakat, tanwin, shadda, sukun, the dagger alef,
    // and the Quranic/extended-Arabic ranges. A range list would have to be
    // maintained against future Unicode additions; the category will not.
    .replace(/\p{Mn}/gu, '')
    // Every format character: ZWJ/ZWNJ, the bidi embeddings and isolates, the
    // BOM, and — the one that actually bites in a mixed Arabic/Latin string
    // like `بدر - 25 Oct 2025 - Avian` — U+061C ARABIC LETTER MARK. These
    // MUST be removed before tokenizing: `nameTokens` splits on anything that
    // is not a letter or a number, so a survivor does not get ignored, it
    // splits the word in half and the name silently stops matching itself.
    .replace(/\p{Cf}/gu, '')
    // Tatweel is a stretching glyph with no phonetic value. It is neither a
    // mark nor a format character, so it needs its own line.
    .replace(/\u0640/g, '')
    .replace(/[٠-٩]/g, (digit) => String(digit.charCodeAt(0) - 0x0660))
    .replace(/[۰-۹]/g, (digit) => String(digit.charCodeAt(0) - 0x06F0))
    .trim()
    .replace(/\s+/g, ' ')
    .toLocaleLowerCase('ar')
}

/**
 * The letter equivalences a name can be spelled with and still be the same
 * name to the person who said it.
 *
 * Two families, and both are load-bearing:
 *
 *   * ARABIC ORTHOGRAPHY — أ إ آ ٱ all stand for ا, ى for ي, ئ for ي, ؤ for و,
 *     ة for ه. Writers pick whichever their keyboard offers and whichever the
 *     word wants that day.
 *   * PERSIAN/URDU KEYBOARD FORMS — ک (U+06A9) and ی (U+06CC) are different
 *     code points from the Arabic ك and ي, and a Farsi or Urdu layout, or a
 *     paste from such a source, produces them for names an operator considers
 *     ordinary Arabic. `مبارک` and `مبارك` are the same farm. This mattered
 *     already: the digit fold above handles ۰-۹ from the SAME keyboards, so
 *     the input class was anticipated and only half of it was covered.
 */
function foldLetters(value: string): string {
  return value
    .replace(/[أإآٱ]/g, 'ا')
    .replace(/[ىیۍێې]/g, 'ي')
    .replace(/ئ/g, 'ي')
    .replace(/ؤ/g, 'و')
    .replace(/[ةہھۀ]/g, 'ه')
    .replace(/[کڪ]/g, 'ك')
    .replace(/ك/g, 'ك')
    .replace(/ے/g, 'ي')
}

/**
 * Normalized name → its word tokens. Every run of non-alphanumeric characters
 * is a separator, so `بدر - 25 Oct 2025 - Avian` and `بدر / 25 oct 2025 (avian)`
 * tokenize identically. Empty tokens are dropped, so a name that is nothing but
 * punctuation yields `[]` and can never match anything.
 */
export function nameTokens(value: string): string[] {
  return normalizeOperationalName(value)
    .split(/[^\p{L}\p{N}]+/u)
    .filter((token) => token.length > 0)
}

export type NameMatchTier = 'exact' | 'prefix' | 'contains'

export interface NameMatch<T> {
  readonly tier: NameMatchTier
  readonly matches: readonly T[]
}

/**
 * The shortest joined query the `contains` tier will act on. A one-character
 * fragment appears inside a large fraction of any real roster; letting it
 * reach the weakest tier turns a typo into a silent, confident, WRONG
 * resolution whenever the roster happens to hold exactly one hit. Two
 * characters is where a fragment starts carrying enough signal to be worth
 * a guess — and even then, the caller still refuses on more than one match.
 * `exact` and `prefix` are unaffected: a genuinely one-letter name still
 * resolves through them.
 */
const MIN_CONTAINS_QUERY_CHARS = 3

/**
 * Strip a leading Arabic definite article for the FALLBACK tiers only.
 *
 * Operators say the article about half the time — `البدر` for the flock the
 * database calls `بدر`, or `امل` for the one it calls `الأمل`. The ladder
 * compares whole tokens, so neither direction matched at all before this. The
 * length guard keeps `الا` from collapsing to `ا`; a two-letter remainder is
 * not a name, it is the article with a fragment attached.
 *
 * NOT applied at the exact tier: `الأمل` and `أمل` may be two different
 * flocks, and if both exist the caller must be told so rather than have one
 * of them silently win.
 */
function stripArticle(token: string): string {
  return token.length > 4 && token.startsWith('ال') ? token.slice(2) : token
}

/**
 * True when a token carries at least one letter.
 *
 * The `contains` tier is where a query is allowed to match the MIDDLE of a
 * stored name, and every flock name is decorated — `بدر - 25 Oct 2025 -
 * Avian` puts the entry date and the breed into the token stream. Without
 * this guard an operator saying "flock 25" (house 25, pen 25, batch 25)
 * resolves, confidently and uniquely, to whichever flock happens to have been
 * entered on the 25th, and that resolution is then PERSISTED as the
 * conversation's selected flock. A purely numeric fragment is not a name.
 */
function hasLetter(token: string): boolean {
  return /\p{L}/u.test(token)
}

/**
 * Run the ladder. Returns `null` when nothing matched at any tier, otherwise
 * the winning tier and EVERY item that matched at it — deliberately not a
 * single item, because "two farms match" is information the caller has to act
 * on, not a detail to be resolved by taking the first.
 */
export function matchByName<T>(
  query: string,
  items: readonly T[],
  nameOf: (item: T) => string,
): NameMatch<T> | null {
  const wanted = nameTokens(query)
  if (wanted.length === 0) return null
  const tokenized = items.map((item) => ({ item, tokens: nameTokens(nameOf(item)) }))

  const exact = tokenized.filter((entry) => tokensEqual(entry.tokens, wanted))
  if (exact.length > 0) {
    return { tier: 'exact', matches: exact.map((entry) => entry.item) }
  }

  // The article is stripped from BOTH sides for the fallback tiers, so
  // `البدر` finds `بدر` and `امل` finds `الأمل`.
  const wantedLoose = wanted.map(stripArticle)
  const loose = tokenized.map((entry) => ({
    item: entry.item,
    tokens: entry.tokens.map(stripArticle),
  }))

  const prefix = loose.filter((entry) => startsWithTokens(entry.tokens, wantedLoose))
  if (prefix.length > 0) {
    return { tier: 'prefix', matches: prefix.map((entry) => entry.item) }
  }

  // A middle-of-the-name match has to earn it: long enough to be a name, and
  // carrying at least one letter so a bare date or count from a decorated
  // flock name cannot resolve a flock on its own.
  if (
    wantedLoose.join('').length < MIN_CONTAINS_QUERY_CHARS ||
    !wantedLoose.some(hasLetter)
  ) return null
  const contains = loose.filter((entry) => containsTokens(entry.tokens, wantedLoose))
  if (contains.length > 0) {
    return { tier: 'contains', matches: contains.map((entry) => entry.item) }
  }
  return null
}

function tokensEqual(
  candidate: readonly string[],
  wanted: readonly string[],
): boolean {
  return candidate.length === wanted.length && startsWithTokens(candidate, wanted)
}

function startsWithTokens(
  candidate: readonly string[],
  wanted: readonly string[],
): boolean {
  if (wanted.length > candidate.length) return false
  return wanted.every((token, index) => candidate[index] === token)
}

function containsTokens(
  candidate: readonly string[],
  wanted: readonly string[],
): boolean {
  if (wanted.length > candidate.length) return false
  for (let start = 0; start + wanted.length <= candidate.length; start++) {
    if (wanted.every((token, index) => candidate[start + index] === token)) {
      return true
    }
  }
  return false
}
