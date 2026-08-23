// conversation_title.ts — pure helper that turns a user's first message into
// a short conversation title, shown in a multi-conversation list.
//
// Deliberately has no dependency on the rest of the door so it is trivial to
// unit test in isolation (conversation_title_test.ts).

const MAX_TITLE_CHARS = 48
const MIN_WORD_BOUNDARY = 12

// Trailing punctuation stripped after truncation, Latin and Arabic alike.
const TRAILING_PUNCTUATION = /[.,;:!?،؛\s]+$/u

/**
 * Derives a short title from a user message.
 *
 * - Collapses internal whitespace and trims the ends.
 * - Empty (or whitespace-only) input yields null.
 * - Keeps at most 48 characters, cutting at the last word boundary at or
 *   after character 12 when one exists in that range; otherwise hard-cuts at
 *   48.
 * - Strips trailing punctuation (Latin and Arabic) left over from the cut.
 *
 * Works on Arabic text: cutting by UTF-16 code unit index is safe here
 * because Arabic letters (and the punctuation this strips) are all in the
 * Basic Multilingual Plane, so no surrogate pair is ever split.
 */
export function deriveConversationTitle(text: string): string | null {
  const collapsed = text.replace(/\s+/g, ' ').trim()
  if (collapsed.length === 0) return null

  let truncated = collapsed
  if (collapsed.length > MAX_TITLE_CHARS) {
    const window = collapsed.slice(0, MAX_TITLE_CHARS)
    const lastSpace = window.lastIndexOf(' ')
    truncated = lastSpace >= MIN_WORD_BOUNDARY
      ? window.slice(0, lastSpace)
      : window
  }

  const stripped = truncated.replace(TRAILING_PUNCTUATION, '').trim()
  return stripped.length > 0 ? stripped : null
}
