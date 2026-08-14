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
 */
export function resolveBreed(
  requested: string,
  vocabulary: readonly string[],
): string | null {
  const key = normalizeBreedKey(requested ?? '')
  if (!key) return null

  const exact = vocabulary.find((breed) => normalizeBreedKey(breed) === key)
  if (exact) return exact

  const prefixed = vocabulary.filter((breed) =>
    normalizeBreedKey(breed).startsWith(key)
  )
  return prefixed.length === 1 ? prefixed[0] : null
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
