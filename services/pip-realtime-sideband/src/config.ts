// Central configuration.
//
// Rule: an invalid value FAILS STARTUP. Nothing is silently clamped, because a
// silently clamped budget or lease is indistinguishable from a working one until
// it costs money or corrupts ownership.

// The type-only import back into session_config is deliberate and safe: it
// erases at compile time, so the two modules do not form a runtime cycle.
import type { RealtimeToolDefinition } from './session_config.ts'

export interface RealtimeConfig {
  /** Kill switch consulted at startup; the DB runtime-control row is checked per session. */
  readonly enabled: boolean
  readonly maxSessionSeconds: number
  readonly setupDeadlineSeconds: number
  readonly clientSecretTtlSeconds: number
  readonly bindTokenTtlSeconds: number
  /** How long a freshly upgraded socket may stay silent before it is closed 4408. */
  readonly bindDeadlineSeconds: number
  readonly startLimitCount: number
  readonly startLimitWindowSeconds: number
  readonly dailySecondsPerProfile: number
  readonly dailySecondsPerTenant: number
  readonly overageFactor: number
  readonly heartbeatSeconds: number
  readonly leaseSeconds: number
  readonly maxToolCallsPerInteraction: number
  readonly model: string
  readonly voice: string
  readonly transcriptionModel: string
  readonly reasoningEffort: 'minimal' | 'low' | 'medium' | 'high'
  readonly transcriptionDelay: 'minimal' | 'low' | 'medium' | 'high' | 'xhigh'
  /**
   * Hint for `audio.input.transcription.language` (singular). Verified
   * accepted for gpt-4o-mini-transcribe on a live probe connection
   * (2026-08-19, `tools/probe_session_knobs.ts`) — echoed back as `"ar"` —
   * distinct from the PLURAL `languages` field, which remains rejected for
   * that model. `''` means OMIT the field entirely: the no-code-deploy
   * rollback knob if the language hint ever needs to come out fast.
   */
  readonly transcriptionLanguage: string
  /**
   * Ceiling on `session.max_output_tokens`. Production has never had one —
   * the session default echoes `"inf"` (2026-08-19,
   * `tools/probe_session_knobs.ts`). Sized in `src/session_config.ts`; see
   * the comment there for the measured token counts behind 1536.
   */
  readonly maxOutputTokens: number
  /**
   * Verified accepted for gpt-realtime-2.1-mini on a live probe connection
   * (2026-08-18, `tools/probe_turn_detection.ts`): `semantic_vad` with
   * `eagerness: 'low'` is acked with `session.updated`. `server_vad` remains
   * selectable as a runtime fallback — see `vadEagerness`/`vadSilenceMs` and
   * the one-shot fallback in `src/sideband.ts`.
   */
  readonly turnDetection: 'semantic_vad' | 'server_vad'
  /** Only meaningful when `turnDetection` is `semantic_vad`. */
  readonly vadEagerness: 'low' | 'medium' | 'high' | 'auto'
  /** Only meaningful when `turnDetection` is `server_vad`. */
  readonly vadSilenceMs: number
  /** Seconds of headroom subtracted from the SIGTERM window before we stop new DB work. */
  readonly drainBudgetMs: number
  readonly supabaseUrl: string
  readonly supabaseServiceRoleKey: string
  readonly openAiApiKey: string
  readonly openAiRealtimeUrl: string
  /** Service-account emails accepted on /internal/cleanup after OIDC verification. */
  readonly cleanupServiceAccounts: readonly string[]
  readonly cleanupAudience: string
  /** Full https URL of the `pip-realtime-tool-broker` edge function. */
  readonly toolBrokerUrl: string
  /** Shared secret for that endpoint. NEVER logged, never echoed to a client. */
  readonly toolBrokerSecret: string
  /** The model-facing catalogue, rendered from AGENT_TOOL_CONTRACT. */
  readonly toolDefinitions: readonly RealtimeToolDefinition[]
  /** Recorded in the startup line so a stale catalogue is visible in logs. */
  readonly toolContractVersion: string
  /** Shared typed-agent policy rendered at deploy time. Never logged. */
  readonly instructions: string
  /** Logged without policy text so a stale policy deploy is visible. */
  readonly instructionVersion: string
}

export class ConfigError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'ConfigError'
  }
}

export type EnvSource = (key: string) => string | undefined

const DEFAULTS: Record<string, string> = {
  PIP_REALTIME_ENABLED: 'true',
  PIP_REALTIME_MAX_SESSION_SECONDS: '600',
  PIP_REALTIME_SETUP_DEADLINE_SECONDS: '60',
  // 60 to match the session function: the ephemeral secret doubles as the
  // sideband attach bearer, so it must cover client setup + bind + retries —
  // the whole setup window.
  PIP_REALTIME_CLIENT_SECRET_TTL_SECONDS: '60',
  PIP_REALTIME_BIND_TOKEN_TTL_SECONDS: '60',
  PIP_REALTIME_BIND_DEADLINE_SECONDS: '5',
  // These names must match supabase/functions/pip-realtime-session/config.ts
  // exactly. The session function is the enforcer; the sideband only validates
  // them so a misconfigured deployment fails at startup rather than mid-call.
  // Divergent names would let an operator set one side and silently miss the
  // other.
  PIP_REALTIME_SESSION_START_LIMIT: '5',
  PIP_REALTIME_SESSION_START_WINDOW_SECONDS: '300',
  PIP_REALTIME_DAILY_SECONDS_PER_PROFILE: '1800',
  PIP_REALTIME_DAILY_SECONDS_PER_TENANT: '14400',
  PIP_REALTIME_TENANT_OVERAGE_FACTOR: '1.25',
  PIP_REALTIME_HEARTBEAT_SECONDS: '10',
  PIP_REALTIME_LEASE_SECONDS: '30',
  PIP_REALTIME_MAX_TOOL_CALLS_PER_INTERACTION: '5',
  PIP_REALTIME_MODEL: 'gpt-realtime-2.1-mini',
  // cedar: the natural male voice on gpt-realtime — chosen for a warm male
  // delivery (paired with the Voice conversation section of
  // CHICKMARK_REALTIME_POLICY, rendered by tools/render_agent_instructions.ts).
  PIP_REALTIME_VOICE: 'cedar',
  // gpt-4o-mini-transcribe ($0.003/min) over gpt-live-transcribe ($0.017/min):
  // ~5.7x cheaper for the same captions-only job. Verified as a valid model
  // id on the account before switching the default.
  PIP_REALTIME_TRANSCRIPTION_MODEL: 'gpt-4o-mini-transcribe',
  PIP_REALTIME_REASONING_EFFORT: 'low',
  PIP_REALTIME_TRANSCRIPTION_DELAY: 'low',
  // 'ar': Egyptian Arabic hint sent as singular `language`, verified accepted
  // for the default transcription model (tools/probe_session_knobs.ts,
  // 2026-08-19). Set to '' to omit the field entirely (rollback knob).
  PIP_REALTIME_TRANSCRIPTION_LANGUAGE: 'ar',
  // ~1.8x the largest observed legitimate reply (a live canary measurement of
  // an explicitly requested full eleven-metric summary: 832 and 865 output
  // tokens on two runs) — a backstop against an unanticipated payload, not a
  // cut on any answer the voice policy actually permits. Full derivation in
  // src/session_config.ts, next to where this value is applied.
  PIP_REALTIME_MAX_OUTPUT_TOKENS: '1536',
  // semantic_vad verified accepted for PIP_REALTIME_MODEL's default
  // (gpt-realtime-2.1-mini) on a live probe connection (2026-08-18,
  // tools/probe_turn_detection.ts) — session.updated acked with
  // eagerness:'low'. server_vad remains available as a config override and
  // as the automatic one-shot runtime fallback in src/sideband.ts.
  PIP_REALTIME_TURN_DETECTION: 'semantic_vad',
  PIP_REALTIME_VAD_EAGERNESS: 'low',
  // Only applies when turn_detection is server_vad (default or fallback).
  // Raised from the previous hardcoded 500ms so short natural pauses don't
  // prematurely end the user's turn.
  PIP_REALTIME_VAD_SILENCE_MS: '800',
  // Cloud Run's SIGTERM grace is a fixed, non-configurable 10s. The drain path
  // gets 7s so the close frames and the process exit still land inside it.
  PIP_REALTIME_DRAIN_BUDGET_MS: '7000',
  PIP_REALTIME_OPENAI_REALTIME_URL: 'wss://api.openai.com/v1/realtime',
  PIP_REALTIME_CLEANUP_AUDIENCE: '',
  PIP_REALTIME_TOOL_CONTRACT_VERSION: 'unset',
  PIP_REALTIME_CLEANUP_SERVICE_ACCOUNTS: '',
}

function raw(env: EnvSource, key: string): string {
  const value = env(key)
  if (value === undefined || value === '') return DEFAULTS[key] ?? ''
  return value
}

function requireString(env: EnvSource, key: string): string {
  const value = env(key)
  if (value === undefined || value.trim() === '') {
    throw new ConfigError(`${key} is required`)
  }
  return value.trim()
}

function readInt(
  env: EnvSource,
  key: string,
  min: number,
  max: number,
): number {
  const text = raw(env, key)
  if (!/^-?\d+$/.test(text)) {
    throw new ConfigError(`${key} must be an integer, got ${JSON.stringify(text)}`)
  }
  const value = Number.parseInt(text, 10)
  if (value < min || value > max) {
    throw new ConfigError(`${key} must be between ${min} and ${max}, got ${value}`)
  }
  return value
}

function readFloat(env: EnvSource, key: string, min: number, max: number): number {
  const text = raw(env, key)
  const value = Number(text)
  if (!Number.isFinite(value)) {
    throw new ConfigError(`${key} must be a number, got ${JSON.stringify(text)}`)
  }
  if (value < min || value > max) {
    throw new ConfigError(`${key} must be between ${min} and ${max}, got ${value}`)
  }
  return value
}

function readBool(env: EnvSource, key: string): boolean {
  const text = raw(env, key).toLowerCase()
  if (text === 'true') return true
  if (text === 'false') return false
  throw new ConfigError(`${key} must be "true" or "false", got ${JSON.stringify(text)}`)
}

function readEnum<T extends string>(
  env: EnvSource,
  key: string,
  allowed: readonly T[],
): T {
  const text = raw(env, key)
  if (!(allowed as readonly string[]).includes(text)) {
    throw new ConfigError(
      `${key} must be one of ${allowed.join('|')}, got ${JSON.stringify(text)}`,
    )
  }
  return text as T
}

/**
 * `''` (OMIT the field) or a two-letter ISO-639-1 code. Anything else — a
 * three-letter code, a locale tag like `ar-EG`, a language name — fails
 * startup rather than being sent to the provider unchecked, since the
 * transcription field this feeds is one of the two fields per model that
 * gets the ENTIRE session.update rejected when malformed.
 *
 * Deliberately NOT built on `raw()`: `raw()` treats an env var explicitly set
 * to `''` the same as unset and substitutes the default, which would make the
 * `''`-means-omit rollback knob impossible to reach — setting the var to ''
 * would silently keep sending 'ar'. Here an explicit '' is read as '', and
 * only a genuinely UNSET var falls back to `DEFAULTS`.
 */
function readLanguageHint(env: EnvSource, key: string): string {
  const value = env(key)
  const text = value === undefined ? (DEFAULTS[key] ?? '') : value
  if (text === '' || /^[a-z]{2}$/.test(text)) return text
  throw new ConfigError(
    `${key} must be '' (omit) or a two-letter ISO-639-1 code, got ${
      JSON.stringify(text)
    }`,
  )
}

function readList(env: EnvSource, key: string): string[] {
  const text = raw(env, key)
  if (text.trim() === '') return []
  return text.split(',').map((entry) => entry.trim()).filter((entry) => entry !== '')
}

/**
 * THE MODEL-FACING TOOL CATALOGUE, as configuration.
 *
 * Why configuration and not an import: the catalogue's single source of truth is
 * `AGENT_TOOL_CONTRACT` in the Supabase edge-function deployment. This service
 * is a separate Cloud Run image whose build copies only `main.ts` and `src/`, so
 * a cross-deployment import would not resolve at image build time — and vendoring
 * a copy into this repo directory is precisely the drift the contract exists to
 * prevent. The value is therefore RENDERED from the contract by
 * `tools/render_tool_definitions.ts` and supplied as one env var, which
 * `test/tool_contract_test.ts` keeps honest.
 *
 * It is REQUIRED. A sideband that starts with an empty catalogue looks perfectly
 * healthy — READY is announced, audio flows — and silently cannot do anything,
 * which is the whole capability of the feature.
 */
function readToolDefinitions(
  env: EnvSource,
  key: string,
): readonly RealtimeToolDefinition[] {
  const text = requireString(env, key)
  let parsed: unknown
  try {
    parsed = JSON.parse(text)
  } catch {
    throw new ConfigError(`${key} must be valid JSON`)
  }
  if (!Array.isArray(parsed) || parsed.length === 0) {
    throw new ConfigError(`${key} must be a non-empty JSON array of tool definitions`)
  }

  const seen = new Set<string>()
  const definitions: RealtimeToolDefinition[] = []
  for (const [index, entry] of parsed.entries()) {
    const where = `${key}[${index}]`
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
      throw new ConfigError(`${where} must be an object`)
    }
    const item = entry as Record<string, unknown>
    // The FLAT Realtime shape. The nested Chat Completions shape
    // (`{type:'function', function:{...}}`) is accepted by neither the provider
    // nor this check, and is the single most common way to get this wrong.
    if (item.type !== 'function') {
      throw new ConfigError(`${where}.type must be "function"`)
    }
    if (typeof item.name !== 'string' || item.name.trim() === '') {
      throw new ConfigError(`${where}.name must be a non-empty string`)
    }
    if (typeof item.description !== 'string' || item.description.trim() === '') {
      throw new ConfigError(`${where}.description must be a non-empty string`)
    }
    if (
      item.parameters === null || typeof item.parameters !== 'object' ||
      Array.isArray(item.parameters)
    ) {
      throw new ConfigError(`${where}.parameters must be a JSON-Schema object`)
    }
    if (seen.has(item.name)) {
      // Two definitions with one name means one executor entry silently wins.
      throw new ConfigError(`${key} declares ${item.name} more than once`)
    }
    seen.add(item.name)
    definitions.push({
      type: 'function',
      name: item.name,
      description: item.description,
      parameters: item.parameters as Record<string, unknown>,
    })
  }
  return Object.freeze(definitions)
}

export function loadConfig(env: EnvSource = (key) => Deno.env.get(key)): RealtimeConfig {
  const supabaseUrl = requireString(env, 'SUPABASE_URL').replace(/\/+$/, '')
  if (!/^https:\/\//.test(supabaseUrl)) {
    throw new ConfigError('SUPABASE_URL must be an https URL')
  }

  // The provider caps a Realtime session at 60 minutes and a client secret TTL at
  // 10..7200s. Anything outside those is a deploy-time mistake, not a runtime one.
  const maxSessionSeconds = readInt(env, 'PIP_REALTIME_MAX_SESSION_SECONDS', 30, 3600)
  const clientSecretTtlSeconds = readInt(
    env,
    'PIP_REALTIME_CLIENT_SECRET_TTL_SECONDS',
    10,
    7200,
  )
  const leaseSeconds = readInt(env, 'PIP_REALTIME_LEASE_SECONDS', 5, 600)
  const heartbeatSeconds = readInt(env, 'PIP_REALTIME_HEARTBEAT_SECONDS', 1, 300)
  if (heartbeatSeconds * 2 > leaseSeconds) {
    throw new ConfigError(
      'PIP_REALTIME_HEARTBEAT_SECONDS must be at most half of PIP_REALTIME_LEASE_SECONDS ' +
        'so a single missed heartbeat cannot expire the lease',
    )
  }

  const drainBudgetMs = readInt(env, 'PIP_REALTIME_DRAIN_BUDGET_MS', 500, 9000)

  // A socket that never binds holds a Cloud Run CONCURRENCY SLOT for as long as
  // it stays open, so the window is seconds, not minutes. It must also expire
  // well before the setup deadline: a bind that arrives after setup has already
  // been abandoned has nothing left to attach to.
  const setupDeadlineSeconds = readInt(env, 'PIP_REALTIME_SETUP_DEADLINE_SECONDS', 5, 600)
  const bindDeadlineSeconds = readInt(env, 'PIP_REALTIME_BIND_DEADLINE_SECONDS', 1, 60)
  if (bindDeadlineSeconds >= setupDeadlineSeconds) {
    throw new ConfigError(
      'PIP_REALTIME_BIND_DEADLINE_SECONDS must be shorter than ' +
        'PIP_REALTIME_SETUP_DEADLINE_SECONDS',
    )
  }

  // The broker carries a shared secret in a header, so plaintext is disqualifying.
  const toolBrokerUrl = requireString(env, 'PIP_REALTIME_TOOL_BROKER_URL').replace(
    /\/+$/,
    '',
  )
  if (!/^https:\/\//.test(toolBrokerUrl)) {
    throw new ConfigError('PIP_REALTIME_TOOL_BROKER_URL must be an https URL')
  }

  return {
    enabled: readBool(env, 'PIP_REALTIME_ENABLED'),
    maxSessionSeconds,
    setupDeadlineSeconds,
    clientSecretTtlSeconds,
    bindTokenTtlSeconds: readInt(env, 'PIP_REALTIME_BIND_TOKEN_TTL_SECONDS', 5, 600),
    bindDeadlineSeconds,
    startLimitCount: readInt(env, 'PIP_REALTIME_SESSION_START_LIMIT', 1, 1000),
    startLimitWindowSeconds: readInt(
      env,
      'PIP_REALTIME_SESSION_START_WINDOW_SECONDS',
      10,
      86_400,
    ),
    dailySecondsPerProfile: readInt(
      env,
      'PIP_REALTIME_DAILY_SECONDS_PER_PROFILE',
      0,
      86_400,
    ),
    dailySecondsPerTenant: readInt(
      env,
      'PIP_REALTIME_DAILY_SECONDS_PER_TENANT',
      0,
      8_640_000,
    ),
    overageFactor: readFloat(env, 'PIP_REALTIME_TENANT_OVERAGE_FACTOR', 1, 10),
    heartbeatSeconds,
    leaseSeconds,
    maxToolCallsPerInteraction: readInt(
      env,
      'PIP_REALTIME_MAX_TOOL_CALLS_PER_INTERACTION',
      1,
      50,
    ),
    model: raw(env, 'PIP_REALTIME_MODEL'),
    voice: raw(env, 'PIP_REALTIME_VOICE'),
    transcriptionModel: raw(env, 'PIP_REALTIME_TRANSCRIPTION_MODEL'),
    reasoningEffort: readEnum(
      env,
      'PIP_REALTIME_REASONING_EFFORT',
      [
        'minimal',
        'low',
        'medium',
        'high',
      ] as const,
    ),
    // `delay` is an ENUM on the provider side, never a millisecond number.
    transcriptionDelay: readEnum(
      env,
      'PIP_REALTIME_TRANSCRIPTION_DELAY',
      [
        'minimal',
        'low',
        'medium',
        'high',
        'xhigh',
      ] as const,
    ),
    turnDetection: readEnum(
      env,
      'PIP_REALTIME_TURN_DETECTION',
      ['semantic_vad', 'server_vad'] as const,
    ),
    vadEagerness: readEnum(
      env,
      'PIP_REALTIME_VAD_EAGERNESS',
      ['low', 'medium', 'high', 'auto'] as const,
    ),
    vadSilenceMs: readInt(env, 'PIP_REALTIME_VAD_SILENCE_MS', 200, 2000),
    transcriptionLanguage: readLanguageHint(env, 'PIP_REALTIME_TRANSCRIPTION_LANGUAGE'),
    // Provider default is unbounded ("inf") — see the ceiling's derivation in
    // src/session_config.ts.
    maxOutputTokens: readInt(env, 'PIP_REALTIME_MAX_OUTPUT_TOKENS', 200, 4096),
    drainBudgetMs,
    supabaseUrl,
    supabaseServiceRoleKey: requireString(env, 'SUPABASE_SERVICE_ROLE_KEY'),
    openAiApiKey: requireString(env, 'OPENAI_API_KEY'),
    openAiRealtimeUrl: raw(env, 'PIP_REALTIME_OPENAI_REALTIME_URL'),
    cleanupServiceAccounts: readList(env, 'PIP_REALTIME_CLEANUP_SERVICE_ACCOUNTS'),
    cleanupAudience: raw(env, 'PIP_REALTIME_CLEANUP_AUDIENCE'),
    toolBrokerUrl,
    // Read, validated for presence, and then only ever placed in a request
    // header. It is never logged, never returned to a client, and never included
    // in an error message — `requireString` names the KEY, not the value.
    toolBrokerSecret: requireString(env, 'PIP_REALTIME_BROKER_SECRET'),
    toolDefinitions: readToolDefinitions(env, 'PIP_REALTIME_TOOL_DEFINITIONS'),
    toolContractVersion: raw(env, 'PIP_REALTIME_TOOL_CONTRACT_VERSION'),
    instructions: requireString(env, 'PIP_REALTIME_INSTRUCTIONS'),
    instructionVersion: requireString(env, 'PIP_REALTIME_INSTRUCTIONS_VERSION'),
  }
}

/** Test helper: a complete, valid config with overridable fields. */
export function testConfig(overrides: Partial<RealtimeConfig> = {}): RealtimeConfig {
  const base = loadConfig((key) => {
    switch (key) {
      case 'SUPABASE_URL':
        return 'https://example.supabase.co'
      case 'SUPABASE_SERVICE_ROLE_KEY':
        return 'service-role-key'
      case 'OPENAI_API_KEY':
        return 'openai-key'
      case 'PIP_REALTIME_TOOL_BROKER_URL':
        return 'https://example.supabase.co/functions/v1/pip-realtime-tool-broker'
      case 'PIP_REALTIME_BROKER_SECRET':
        return 'broker-secret'
      case 'PIP_REALTIME_TOOL_DEFINITIONS':
        return JSON.stringify([{
          type: 'function',
          name: 'get_user_scope',
          description: 'Return the customer access already enforced for this user.',
          parameters: { type: 'object', properties: {}, required: [] },
        }])
      case 'PIP_REALTIME_INSTRUCTIONS':
        return 'You are ChickMark.'
      case 'PIP_REALTIME_INSTRUCTIONS_VERSION':
        return '1.1.0'
      default:
        return undefined
    }
  })
  return { ...base, ...overrides }
}
