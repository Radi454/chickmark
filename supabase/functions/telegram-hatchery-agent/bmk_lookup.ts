// Pure breed/age resolution for the BMK benchmark tools.
//
// The vocabulary is always passed in -- it comes from the bmk_breeds table at
// runtime, never from a hardcoded list, so a new breed row is answerable the
// moment it lands.

export interface BreedCoverage {
  breed: string
  minWeek: number
  maxWeek: number
}

/** Lowercase, alphanumeric only. 'Ross 308', 'ROSS-308' -> 'ross308'. */
export function normalizeBreedKey(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]/g, '')
}

/**
 * Exact normalized match first, then a UNIQUE prefix match. A prefix matching
 * more than one breed resolves to null so the caller can ask instead of
 * guessing.
 *
 * Kept for callers that only need the resolved name; `resolveBreedMatch`
 * below is the same decision with the AMBIGUOUS case told apart from the
 * MISSING one.
 */
export function resolveBreed(
  requested: string,
  vocabulary: readonly string[],
): string | null {
  const match = resolveBreedMatch(requested, vocabulary)
  return match.status === 'resolved' ? match.breed : null
}

export type BreedMatch =
  | { status: 'resolved'; breed: string }
  | { status: 'ambiguous'; candidates: string[] }
  | { status: 'unmatched' }

/**
 * The same ladder, reporting WHICH failure occurred.
 *
 * `"Ross"` against `["Ross 308", "Ross 708"]` is not "no such breed" — it is
 * two breeds. Collapsing both into null made the agent tell the user a breed
 * it stocks does not exist, when the honest answer ("which of these two?") was
 * one question away and already computed.
 */
export function resolveBreedMatch(
  requested: string,
  vocabulary: readonly string[],
): BreedMatch {
  const key = normalizeBreedKey(requested ?? '')
  if (!key) return { status: 'unmatched' }

  const exact = vocabulary.find((breed) => normalizeBreedKey(breed) === key)
  if (exact) return { status: 'resolved', breed: exact }

  const prefixed = vocabulary.filter((breed) =>
    normalizeBreedKey(breed).startsWith(key)
  )
  if (prefixed.length === 1) return { status: 'resolved', breed: prefixed[0] }
  if (prefixed.length > 1) return { status: 'ambiguous', candidates: prefixed }
  return { status: 'unmatched' }
}

/** Week coverage for one resolved breed. Coverage differs per breed. */
export function coverageFor(
  breed: string,
  rows: readonly { breed: string; ageWeek: number }[],
): BreedCoverage | null {
  const weeks = rows
    .filter((row) => row.breed === breed)
    .map((row) => row.ageWeek)
    .filter((week) => Number.isFinite(week))
  if (weeks.length === 0) return null
  return {
    breed,
    minWeek: Math.min(...weeks),
    maxWeek: Math.max(...weeks),
  }
}
