// supabase/functions/pip-realtime-session/config.ts
//
// The single place the PIP_REALTIME_* knobs are read and validated.
//
// Two rules this module exists to enforce:
//
//   1. Invalid configuration FAILS FAST. A malformed or out-of-range value
//      throws PipRealtimeConfigError; it is never silently clamped to a
//      "reasonable" default, because a silently clamped budget or deadline is
//      indistinguishable from a working one until it costs money.
//
//   2. Realtime is OpenAI-only. It reads OPENAI_API_KEY and nothing else. It
//      must NOT read OPENAI_VOICE_KEY (that secret belongs to the legacy
//      recorded-voice path in app-hatchery-agent/voice.ts) and must NOT consult
//      OPENROUTER_API_KEY or the text provider resolver: a Realtime session
//      cannot fall back to a text provider, so a missing key means Realtime is
//      simply unavailable.

import { PIP_MODEL_DEFAULTS } from '../_shared/pip_model_routing.ts'

/** Reads one environment variable. Injectable so tests never touch Deno.env. */
export type EnvReader = (name: string) => string | undefined

export class PipRealtimeConfigError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'PipRealtimeConfigError'
  }
}

export interface PipRealtimeConfig {
  /** Static build-time kill switch. The DB runtime control is the live one. */
  readonly enabled: boolean
  /** Hard ceiling on one session's billable life. */
  readonly maxSessionSeconds: number
  /** How long a provisioned generation has to complete setup. */
  readonly setupDeadlineSeconds: number
  /** TTL of the ephemeral OpenAI client secret, anchored at created_at. */
  readonly clientSecretTtlSeconds: number
  /** TTL of the one-shot binding token handed to the client. */
  readonly bindTokenTtlSeconds: number
  /** Accepted starts per profile per window. */
  readonly sessionStartLimit: number
  readonly sessionStartWindowSeconds: number
  readonly dailySecondsPerProfile: number
  readonly dailySecondsPerTenant: number
  /** Tenant budgets get headroom so one tenant's last session is not cut mid-word. */
  readonly tenantOverageFactor: number
  /** Sideband service the client connects to once it holds a binding token. */
  readonly cloudRunUrl: string | null
  readonly realtimeModel: string
  readonly realtimeVoice: string
}

export const PIP_REALTIME_DEFAULTS = {
  enabled: true,
  maxSessionSeconds: 600,
  setupDeadlineSeconds: 60,
  // 60 rather than the original 30: the secret now doubles as the sideband's
  // attach bearer, and attach happens several seconds after mint (client
  // WebRTC setup + register + bind + up to two attach retries). It is capped
  // by the cross-field guard at the setup deadline (60s), which is exactly
  // the window attach can legally happen in.
  clientSecretTtlSeconds: 60,
  bindTokenTtlSeconds: 60,
  sessionStartLimit: 5,
  sessionStartWindowSeconds: 300,
  dailySecondsPerProfile: 1800,
  dailySecondsPerTenant: 14400,
  tenantOverageFactor: 1.25,
  // Both verified live against the Realtime API during Preflight (2026-08-16):
  // a session.update carrying this model and voice was accepted. `ash` belongs
  // to the legacy recorded-voice path (app-hatchery-agent/voice.ts), not here.
  // The voice must match the Sideband default (PIP_REALTIME_VOICE in
  // services/pip-realtime-sideband/src/config.ts) — otherwise the session is
  // minted with one voice and re-configured to another on session.update.
  realtimeModel: PIP_MODEL_DEFAULTS.live,
  realtimeVoice: 'cedar',
} as const

export function readPipRealtimeConfig(
  env: EnvReader = (name) => Deno.env.get(name),
): PipRealtimeConfig {
  const config: PipRealtimeConfig = {
    enabled: readBoolean(
      env,
      'PIP_REALTIME_ENABLED',
      PIP_REALTIME_DEFAULTS.enabled,
    ),
    maxSessionSeconds: readPositiveInteger(
      env,
      'PIP_REALTIME_MAX_SESSION_SECONDS',
      PIP_REALTIME_DEFAULTS.maxSessionSeconds,
    ),
    setupDeadlineSeconds: readPositiveInteger(
      env,
      'PIP_REALTIME_SETUP_DEADLINE_SECONDS',
      PIP_REALTIME_DEFAULTS.setupDeadlineSeconds,
    ),
    clientSecretTtlSeconds: readPositiveInteger(
      env,
      'PIP_REALTIME_CLIENT_SECRET_TTL_SECONDS',
      PIP_REALTIME_DEFAULTS.clientSecretTtlSeconds,
    ),
    bindTokenTtlSeconds: readPositiveInteger(
      env,
      'PIP_REALTIME_BIND_TOKEN_TTL_SECONDS',
      PIP_REALTIME_DEFAULTS.bindTokenTtlSeconds,
    ),
    sessionStartLimit: readPositiveInteger(
      env,
      'PIP_REALTIME_SESSION_START_LIMIT',
      PIP_REALTIME_DEFAULTS.sessionStartLimit,
    ),
    sessionStartWindowSeconds: readPositiveInteger(
      env,
      'PIP_REALTIME_SESSION_START_WINDOW_SECONDS',
      PIP_REALTIME_DEFAULTS.sessionStartWindowSeconds,
    ),
    dailySecondsPerProfile: readPositiveInteger(
      env,
      'PIP_REALTIME_DAILY_SECONDS_PER_PROFILE',
      PIP_REALTIME_DEFAULTS.dailySecondsPerProfile,
    ),
    dailySecondsPerTenant: readPositiveInteger(
      env,
      'PIP_REALTIME_DAILY_SECONDS_PER_TENANT',
      PIP_REALTIME_DEFAULTS.dailySecondsPerTenant,
    ),
    tenantOverageFactor: readFactor(
      env,
      'PIP_REALTIME_TENANT_OVERAGE_FACTOR',
      PIP_REALTIME_DEFAULTS.tenantOverageFactor,
    ),
    cloudRunUrl: readUrl(env, 'PIP_REALTIME_CLOUD_RUN_URL'),
    realtimeModel: readText(
      env,
      'PIP_REALTIME_MODEL',
      PIP_REALTIME_DEFAULTS.realtimeModel,
    ),
    realtimeVoice: readText(
      env,
      'PIP_REALTIME_VOICE',
      PIP_REALTIME_DEFAULTS.realtimeVoice,
    ),
  }

  // Cross-field sanity: a setup deadline or a client-secret TTL longer than the
  // session ceiling would let setup outlive the thing it is setting up.
  if (config.setupDeadlineSeconds > config.maxSessionSeconds) {
    throw new PipRealtimeConfigError(
      'PIP_REALTIME_SETUP_DEADLINE_SECONDS must not exceed ' +
        'PIP_REALTIME_MAX_SESSION_SECONDS',
    )
  }
  if (config.clientSecretTtlSeconds > config.setupDeadlineSeconds) {
    throw new PipRealtimeConfigError(
      'PIP_REALTIME_CLIENT_SECRET_TTL_SECONDS must not exceed ' +
        'PIP_REALTIME_SETUP_DEADLINE_SECONDS',
    )
  }
  if (config.bindTokenTtlSeconds > config.setupDeadlineSeconds) {
    throw new PipRealtimeConfigError(
      'PIP_REALTIME_BIND_TOKEN_TTL_SECONDS must not exceed ' +
        'PIP_REALTIME_SETUP_DEADLINE_SECONDS',
    )
  }
  if (config.dailySecondsPerProfile > config.dailySecondsPerTenant) {
    throw new PipRealtimeConfigError(
      'PIP_REALTIME_DAILY_SECONDS_PER_PROFILE must not exceed ' +
        'PIP_REALTIME_DAILY_SECONDS_PER_TENANT',
    )
  }

  return Object.freeze(config)
}

/**
 * The ONLY credential Realtime may use. Deliberately ignores OPENAI_VOICE_KEY
 * and OPENROUTER_API_KEY. Returns null when absent, which the door reports as
 * "Realtime unavailable" — never as a fallback to another provider.
 */
export function readRealtimeOpenAiKey(
  env: EnvReader = (name) => Deno.env.get(name),
): string | null {
  const key = env('OPENAI_API_KEY')?.trim()
  return key ? key : null
}

function readBoolean(env: EnvReader, name: string, fallback: boolean): boolean {
  const raw = env(name)?.trim()
  if (raw === undefined || raw === '') return fallback
  const lowered = raw.toLowerCase()
  if (lowered === 'true' || lowered === '1') return true
  if (lowered === 'false' || lowered === '0') return false
  throw new PipRealtimeConfigError(
    `${name} must be true or false, got "${raw}"`,
  )
}

function readPositiveInteger(
  env: EnvReader,
  name: string,
  fallback: number,
): number {
  const raw = env(name)?.trim()
  if (raw === undefined || raw === '') return fallback
  if (!/^\d+$/.test(raw)) {
    throw new PipRealtimeConfigError(
      `${name} must be a positive integer, got "${raw}"`,
    )
  }
  const value = Number.parseInt(raw, 10)
  if (!Number.isSafeInteger(value) || value < 1) {
    throw new PipRealtimeConfigError(
      `${name} must be a positive integer, got "${raw}"`,
    )
  }
  return value
}

function readFactor(env: EnvReader, name: string, fallback: number): number {
  const raw = env(name)?.trim()
  if (raw === undefined || raw === '') return fallback
  const value = Number.parseFloat(raw)
  if (!Number.isFinite(value) || value < 1) {
    throw new PipRealtimeConfigError(
      `${name} must be a finite number >= 1, got "${raw}"`,
    )
  }
  return value
}

function readUrl(env: EnvReader, name: string): string | null {
  const raw = env(name)?.trim()
  if (!raw) return null
  let parsed: URL
  try {
    parsed = new URL(raw)
  } catch (_) {
    throw new PipRealtimeConfigError(`${name} must be an absolute URL`)
  }
  if (parsed.protocol !== 'https:') {
    throw new PipRealtimeConfigError(`${name} must use https`)
  }
  return raw.replace(/\/+$/, '')
}

function readText(env: EnvReader, name: string, fallback: string): string {
  const raw = env(name)?.trim()
  return raw ? raw : fallback
}
