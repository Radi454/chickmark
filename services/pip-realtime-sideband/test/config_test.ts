import { assertEquals, assertThrows } from '@std/assert'
import { ConfigError, loadConfig } from '../src/config.ts'

const REQUIRED: Record<string, string> = {
  SUPABASE_URL: 'https://example.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'service-key',
  OPENAI_API_KEY: 'openai-key',
  PIP_REALTIME_TOOL_BROKER_URL:
    'https://example.supabase.co/functions/v1/pip-realtime-tool-broker',
  PIP_REALTIME_BROKER_SECRET: 'broker-secret',
  PIP_REALTIME_INSTRUCTIONS: 'You are ChickMark.',
  PIP_REALTIME_INSTRUCTIONS_VERSION: '1.1.0',
  PIP_REALTIME_TOOL_DEFINITIONS: JSON.stringify([{
    type: 'function',
    name: 'get_user_scope',
    description: 'Return the scope.',
    parameters: { type: 'object', properties: {}, required: [] },
  }]),
}

function env(overrides: Record<string, string> = {}) {
  const merged = { ...REQUIRED, ...overrides }
  return (key: string) => merged[key]
}

Deno.test('config: defaults match the documented Pip Realtime V1 values', () => {
  const config = loadConfig(env())
  assertEquals(config.enabled, true)
  assertEquals(config.maxSessionSeconds, 600)
  assertEquals(config.setupDeadlineSeconds, 60)
  assertEquals(config.clientSecretTtlSeconds, 60)
  assertEquals(config.bindTokenTtlSeconds, 60)
  assertEquals(config.startLimitCount, 5)
  assertEquals(config.startLimitWindowSeconds, 300)
  assertEquals(config.dailySecondsPerProfile, 1800)
  assertEquals(config.dailySecondsPerTenant, 14400)
  assertEquals(config.overageFactor, 1.25)
  assertEquals(config.heartbeatSeconds, 10)
  assertEquals(config.leaseSeconds, 30)
  assertEquals(config.maxToolCallsPerInteraction, 5)
  assertEquals(config.model, 'gpt-realtime-2.1-mini')
  assertEquals(config.turnDetection, 'semantic_vad')
  assertEquals(config.vadEagerness, 'low')
  assertEquals(config.vadSilenceMs, 800)
  assertEquals(config.transcriptionLanguage, 'ar')
  assertEquals(config.maxOutputTokens, 1536)
})

Deno.test('config: max output tokens is bounded and NOT clamped', () => {
  assertThrows(
    () => loadConfig(env({ PIP_REALTIME_MAX_OUTPUT_TOKENS: '199' })),
    ConfigError,
    'between 200 and 4096',
  )
  assertThrows(
    () => loadConfig(env({ PIP_REALTIME_MAX_OUTPUT_TOKENS: '4097' })),
    ConfigError,
    'between 200 and 4096',
  )
  assertEquals(
    loadConfig(env({ PIP_REALTIME_MAX_OUTPUT_TOKENS: '2048' })).maxOutputTokens,
    2048,
  )
})

Deno.test('config: transcription language is a two-letter code, or empty to omit', () => {
  assertThrows(
    () => loadConfig(env({ PIP_REALTIME_TRANSCRIPTION_LANGUAGE: 'arabic' })),
    ConfigError,
    "must be '' (omit) or a two-letter ISO-639-1 code",
  )
  assertThrows(
    () => loadConfig(env({ PIP_REALTIME_TRANSCRIPTION_LANGUAGE: 'A1' })),
    ConfigError,
    "must be '' (omit) or a two-letter ISO-639-1 code",
  )
  assertEquals(
    loadConfig(env({ PIP_REALTIME_TRANSCRIPTION_LANGUAGE: 'en' })).transcriptionLanguage,
    'en',
  )
  assertEquals(
    loadConfig(env({ PIP_REALTIME_TRANSCRIPTION_LANGUAGE: '' })).transcriptionLanguage,
    '',
  )
})

Deno.test('config: turn detection is an enum, not a free string', () => {
  assertThrows(
    () => loadConfig(env({ PIP_REALTIME_TURN_DETECTION: 'vad_lite' })),
    ConfigError,
    'semantic_vad|server_vad',
  )
  assertEquals(
    loadConfig(env({ PIP_REALTIME_TURN_DETECTION: 'server_vad' })).turnDetection,
    'server_vad',
  )
})

Deno.test('config: vad eagerness is an enum', () => {
  assertThrows(
    () => loadConfig(env({ PIP_REALTIME_VAD_EAGERNESS: 'urgent' })),
    ConfigError,
    'low|medium|high|auto',
  )
  assertEquals(
    loadConfig(env({ PIP_REALTIME_VAD_EAGERNESS: 'auto' })).vadEagerness,
    'auto',
  )
})

Deno.test('config: vad silence ms is bounded and NOT clamped', () => {
  assertThrows(
    () => loadConfig(env({ PIP_REALTIME_VAD_SILENCE_MS: '100' })),
    ConfigError,
    'between 200 and 2000',
  )
  assertThrows(
    () => loadConfig(env({ PIP_REALTIME_VAD_SILENCE_MS: '2001' })),
    ConfigError,
    'between 200 and 2000',
  )
  assertEquals(
    loadConfig(env({ PIP_REALTIME_VAD_SILENCE_MS: '1200' })).vadSilenceMs,
    1200,
  )
})

Deno.test('config: a missing secret fails startup rather than defaulting', () => {
  const withoutServiceRole = { ...REQUIRED }
  delete withoutServiceRole.SUPABASE_SERVICE_ROLE_KEY
  assertThrows(
    () => loadConfig((key) => withoutServiceRole[key]),
    ConfigError,
    'SUPABASE_SERVICE_ROLE_KEY',
  )
  // Only SUPABASE_URL present: the first required value missing is the one named.
  assertThrows(
    () =>
      loadConfig((key) => (key === 'SUPABASE_URL' ? REQUIRED.SUPABASE_URL : undefined)),
    ConfigError,
    'is required',
  )
})

Deno.test('config: missing or blank policy deployment values fail startup', () => {
  for (
    const key of [
      'PIP_REALTIME_INSTRUCTIONS',
      'PIP_REALTIME_INSTRUCTIONS_VERSION',
    ]
  ) {
    const without = { ...REQUIRED }
    delete without[key]
    assertThrows(() => loadConfig((name) => without[name]), ConfigError, key)
    assertThrows(() => loadConfig(env({ [key]: '   ' })), ConfigError, key)
  }
})

Deno.test('config: an out-of-range value fails startup and is NOT clamped', () => {
  // 7201s is one second past the provider's client-secret ceiling. A clamp here
  // would silently issue a shorter-lived secret than the operator configured.
  assertThrows(
    () => loadConfig(env({ PIP_REALTIME_CLIENT_SECRET_TTL_SECONDS: '7201' })),
    ConfigError,
    'between 10 and 7200',
  )
  // Above the provider's 60-minute session ceiling.
  assertThrows(
    () => loadConfig(env({ PIP_REALTIME_MAX_SESSION_SECONDS: '3601' })),
    ConfigError,
    'between 30 and 3600',
  )
})

Deno.test('config: a non-numeric value fails startup', () => {
  assertThrows(
    () => loadConfig(env({ PIP_REALTIME_LEASE_SECONDS: '30s' })),
    ConfigError,
    'must be an integer',
  )
})

Deno.test('config: heartbeat must leave room for a missed beat inside the lease', () => {
  assertThrows(
    () =>
      loadConfig(env({
        PIP_REALTIME_HEARTBEAT_SECONDS: '20',
        PIP_REALTIME_LEASE_SECONDS: '30',
      })),
    ConfigError,
    'at most half',
  )
})

Deno.test('config: transcription delay is an enum, not a millisecond number', () => {
  assertThrows(
    () => loadConfig(env({ PIP_REALTIME_TRANSCRIPTION_DELAY: '200' })),
    ConfigError,
    'minimal|low|medium|high|xhigh',
  )
  assertEquals(
    loadConfig(env({ PIP_REALTIME_TRANSCRIPTION_DELAY: 'xhigh' })).transcriptionDelay,
    'xhigh',
  )
})

Deno.test("config: the drain budget stays inside Cloud Run's fixed 10s grace", () => {
  assertThrows(
    () => loadConfig(env({ PIP_REALTIME_DRAIN_BUDGET_MS: '12000' })),
    ConfigError,
    'between 500 and 9000',
  )
})

Deno.test('config: a non-https Supabase URL fails startup', () => {
  assertThrows(
    () => loadConfig(env({ SUPABASE_URL: 'http://example.supabase.co' })),
    ConfigError,
    'https',
  )
})

// ---------------------------------------------------------------------------
// The tool path. Every value here is required: a sideband that starts with no
// broker and no catalogue announces READY, carries audio, and can do nothing.
// ---------------------------------------------------------------------------

Deno.test('config: the broker url and secret are required', () => {
  for (const key of ['PIP_REALTIME_TOOL_BROKER_URL', 'PIP_REALTIME_BROKER_SECRET']) {
    const without = { ...REQUIRED }
    delete without[key]
    assertThrows(() => loadConfig((name) => without[name]), ConfigError, key)
  }
})

Deno.test('config: a plaintext broker url fails startup', () => {
  // The shared secret rides in a header on this request.
  assertThrows(
    () =>
      loadConfig(env({
        PIP_REALTIME_TOOL_BROKER_URL: 'http://edge.test/pip-realtime-tool-broker',
      })),
    ConfigError,
    'https',
  )
})

Deno.test('config: an absent tool catalogue fails startup rather than serving none', () => {
  const without = { ...REQUIRED }
  delete without.PIP_REALTIME_TOOL_DEFINITIONS
  assertThrows(
    () => loadConfig((name) => without[name]),
    ConfigError,
    'PIP_REALTIME_TOOL_DEFINITIONS is required',
  )
  assertThrows(
    () => loadConfig(env({ PIP_REALTIME_TOOL_DEFINITIONS: '[]' })),
    ConfigError,
    'non-empty',
  )
})

Deno.test('config: a malformed tool catalogue fails startup', () => {
  const cases: [string, string][] = [
    ['{not json', 'valid JSON'],
    ['{"a":1}', 'non-empty JSON array'],
    ['[{"type":"function","name":"a","description":"d"}]', 'parameters'],
    ['[{"name":"a","description":"d","parameters":{}}]', 'type must be "function"'],
    ['[{"type":"function","name":"","description":"d","parameters":{}}]', 'name'],
    ['[{"type":"function","name":"a","description":"","parameters":{}}]', 'description'],
  ]
  for (const [value, expected] of cases) {
    assertThrows(
      () => loadConfig(env({ PIP_REALTIME_TOOL_DEFINITIONS: value })),
      ConfigError,
      expected,
    )
  }
})

Deno.test('config: the nested Chat Completions tool shape is rejected', () => {
  // `{type:'function', function:{...}}` is the wrong surface for Realtime; it
  // would be accepted silently and leave the model with unusable tools.
  assertThrows(
    () =>
      loadConfig(env({
        PIP_REALTIME_TOOL_DEFINITIONS: JSON.stringify([{
          type: 'function',
          function: { name: 'a', description: 'd', parameters: {} },
        }]),
      })),
    ConfigError,
    'name must be a non-empty string',
  )
})

Deno.test('config: a duplicated tool name fails startup', () => {
  const definition = {
    type: 'function',
    name: 'get_user_scope',
    description: 'd',
    parameters: { type: 'object', properties: {} },
  }
  assertThrows(
    () =>
      loadConfig(env({
        PIP_REALTIME_TOOL_DEFINITIONS: JSON.stringify([definition, definition]),
      })),
    ConfigError,
    'more than once',
  )
})

Deno.test('config: a valid catalogue is parsed into the flat Realtime shape', () => {
  const config = loadConfig(env())
  assertEquals(config.toolDefinitions.length, 1)
  assertEquals(config.toolDefinitions[0].type, 'function')
  assertEquals(config.toolDefinitions[0].name, 'get_user_scope')
  assertEquals(config.toolBrokerSecret, 'broker-secret')
})

Deno.test('config: the bind deadline must expire before the setup deadline', () => {
  // A bind that lands after setup has been abandoned has nothing to attach to.
  assertThrows(
    () =>
      loadConfig(env({
        PIP_REALTIME_BIND_DEADLINE_SECONDS: '30',
        PIP_REALTIME_SETUP_DEADLINE_SECONDS: '30',
      })),
    ConfigError,
    'must be shorter than',
  )
  assertEquals(
    loadConfig(env({ PIP_REALTIME_BIND_DEADLINE_SECONDS: '8' })).bindDeadlineSeconds,
    8,
  )
  assertEquals(loadConfig(env()).bindDeadlineSeconds, 5)
})

Deno.test('config: an out-of-range bind deadline fails startup and is NOT clamped', () => {
  assertThrows(
    () => loadConfig(env({ PIP_REALTIME_BIND_DEADLINE_SECONDS: '0' })),
    ConfigError,
    'between 1 and 60',
  )
  assertThrows(
    () => loadConfig(env({ PIP_REALTIME_BIND_DEADLINE_SECONDS: '61' })),
    ConfigError,
    'between 1 and 60',
  )
})
