import { assertEquals, assertThrows } from '@std/assert'

import {
  PIP_REALTIME_DEFAULTS,
  PipRealtimeConfigError,
  readPipRealtimeConfig,
  readRealtimeOpenAiKey,
} from './config.ts'

function env(values: Record<string, string>) {
  return (name: string) => values[name]
}

Deno.test('config falls back to the documented Realtime defaults', () => {
  const config = readPipRealtimeConfig(env({
    PIP_REALTIME_CLOUD_RUN_URL: 'https://pip-sideband.example.run.app',
  }))
  assertEquals(config.enabled, true)
  assertEquals(config.maxSessionSeconds, 600)
  assertEquals(config.setupDeadlineSeconds, 60)
  assertEquals(config.clientSecretTtlSeconds, 60)
  assertEquals(config.bindTokenTtlSeconds, 60)
  assertEquals(config.sessionStartLimit, 5)
  assertEquals(config.sessionStartWindowSeconds, 300)
  assertEquals(config.dailySecondsPerProfile, 1800)
  assertEquals(config.dailySecondsPerTenant, 14400)
  assertEquals(config.tenantOverageFactor, 1.25)
  assertEquals(config.cloudRunUrl, 'https://pip-sideband.example.run.app')
  assertEquals(config.realtimeModel, 'gpt-realtime-2.1-mini')
  assertEquals(config.realtimeVoice, 'cedar')
  assertEquals(
    config.maxSessionSeconds,
    PIP_REALTIME_DEFAULTS.maxSessionSeconds,
  )
})

Deno.test('config reads overrides instead of ignoring them', () => {
  const config = readPipRealtimeConfig(env({
    PIP_REALTIME_ENABLED: 'false',
    PIP_REALTIME_MAX_SESSION_SECONDS: '900',
    PIP_REALTIME_SESSION_START_LIMIT: '3',
    PIP_REALTIME_TENANT_OVERAGE_FACTOR: '2',
  }))
  assertEquals(config.enabled, false)
  assertEquals(config.maxSessionSeconds, 900)
  assertEquals(config.sessionStartLimit, 3)
  assertEquals(config.tenantOverageFactor, 2)
})

Deno.test('invalid config fails fast and is never silently clamped', () => {
  // A garbage number must not become "the default"; that hides a broken deploy.
  assertThrows(
    () => readPipRealtimeConfig(env({ PIP_REALTIME_MAX_SESSION_SECONDS: 'ten' })),
    PipRealtimeConfigError,
  )
  assertThrows(
    () => readPipRealtimeConfig(env({ PIP_REALTIME_SESSION_START_LIMIT: '0' })),
    PipRealtimeConfigError,
  )
  assertThrows(
    () => readPipRealtimeConfig(env({ PIP_REALTIME_MAX_SESSION_SECONDS: '-5' })),
    PipRealtimeConfigError,
  )
  assertThrows(
    () => readPipRealtimeConfig(env({ PIP_REALTIME_ENABLED: 'maybe' })),
    PipRealtimeConfigError,
  )
  assertThrows(
    () => readPipRealtimeConfig(env({ PIP_REALTIME_TENANT_OVERAGE_FACTOR: '0.5' })),
    PipRealtimeConfigError,
  )
  assertThrows(
    () => readPipRealtimeConfig(env({ PIP_REALTIME_CLOUD_RUN_URL: 'not a url' })),
    PipRealtimeConfigError,
  )
  assertThrows(
    () =>
      readPipRealtimeConfig(env({
        PIP_REALTIME_CLOUD_RUN_URL: 'http://insecure.example.com',
      })),
    PipRealtimeConfigError,
  )
})

Deno.test('config rejects incoherent combinations of valid numbers', () => {
  assertThrows(
    () =>
      readPipRealtimeConfig(env({
        PIP_REALTIME_MAX_SESSION_SECONDS: '30',
        PIP_REALTIME_SETUP_DEADLINE_SECONDS: '60',
      })),
    PipRealtimeConfigError,
  )
  assertThrows(
    () =>
      readPipRealtimeConfig(env({
        PIP_REALTIME_CLIENT_SECRET_TTL_SECONDS: '120',
      })),
    PipRealtimeConfigError,
  )
  assertThrows(
    () =>
      readPipRealtimeConfig(env({
        PIP_REALTIME_DAILY_SECONDS_PER_PROFILE: '20000',
      })),
    PipRealtimeConfigError,
  )
})

Deno.test('Realtime reads OPENAI_API_KEY only', () => {
  assertEquals(
    readRealtimeOpenAiKey(env({ OPENAI_API_KEY: ' sk-live ' })),
    'sk-live',
  )
  // OPENAI_VOICE_KEY belongs to the legacy recorded-voice path, and
  // OPENROUTER_API_KEY belongs to the text brain. Neither may stand in for the
  // Realtime credential: a missing key means Realtime is unavailable.
  assertEquals(
    readRealtimeOpenAiKey(env({
      OPENAI_VOICE_KEY: 'sk-voice',
      OPENROUTER_API_KEY: 'sk-or',
      AI_PROVIDER: 'openrouter',
    })),
    null,
  )
  assertEquals(readRealtimeOpenAiKey(env({ OPENAI_API_KEY: '   ' })), null)
})
