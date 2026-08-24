export type ChickScopeType =
  | 'pool'
  | 'house'
  | 'setter'
  | 'hatcher'
  | 'setter_hatcher'
  | 'trolley'
  | 'tray'

const requiredScopeKeys: Readonly<Record<ChickScopeType, readonly string[]>> = {
  pool: [],
  house: ['house'],
  setter: ['setter'],
  hatcher: ['hatcher'],
  setter_hatcher: ['setter', 'hatcher'],
  trolley: ['trolley'],
  tray: ['tray'],
}

export function buildScopeKey(
  scopeType: ChickScopeType,
  hierarchy: Readonly<Record<string, string | null | undefined>>,
): string {
  if (scopeType === 'pool') return '{}'
  const normalized: Record<string, string> = {}
  for (const [key, value] of Object.entries(hierarchy)) {
    const text = value?.trim()
    if (text) normalized[key] = text
  }
  for (const key of requiredScopeKeys[scopeType]) {
    if (!normalized[key]) throw new Error(`${scopeType} scope requires ${key}`)
  }
  return JSON.stringify(Object.fromEntries(
    Object.entries(normalized).sort(([left], [right]) =>
      left.localeCompare(right)
    ),
  ))
}

export function buildSampleKey(
  domain: string,
  sessionId: string,
  scopeType: ChickScopeType,
  scopeKey: string,
  replicate: number,
): string {
  if (
    !domain.trim() || !sessionId.trim() || !scopeKey.trim() || replicate < 1
  ) {
    throw new Error('Chick sample identity is incomplete')
  }
  const bytes = new TextEncoder().encode(JSON.stringify([
    domain.trim(),
    sessionId.trim(),
    scopeType,
    scopeKey,
    replicate,
  ]))
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(
    /=+$/,
    '',
  )
}
