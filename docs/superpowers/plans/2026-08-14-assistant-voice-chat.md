# Assistant Voice Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add voice input/output to the existing in-app assistant chat — phone records and plays only, server does Whisper transcription → existing agent brain → TTS.

**Architecture:** `app-hatchery-agent`'s `send` action gains an optional `audioBase64` field alongside the existing `message` field. When present, the server transcribes it (Whisper), runs the transcript through the **unmodified** existing send path, then synthesizes the reply (TTS) and returns `audioBase64` + `transcript` in the response. The Flutter side adds a mic button that records via the `record` package, sends base64 audio, plays a bundled filler chime while waiting, then auto-plays the returned TTS audio via `audioplayers`.

**Tech Stack:** Deno Edge Function (existing `app-hatchery-agent`), OpenAI Whisper (`whisper-1`) + TTS (`tts-1`, voice `alloy`) via raw `fetch`, Flutter `record` + `audioplayers` packages.

## Global Constraints

- New Edge Function secret `OPENAI_VOICE_KEY` — distinct from `OPENAI_API_KEY` (already used by the agent brain via `AI_PROVIDER=openai`), so the plan's $5 spend cap stays isolated. Set via Supabase dashboard, not in code.
- No API keys ever ship in the app. `OPENAI_VOICE_KEY` is read only inside `supabase/functions/app-hatchery-agent`.
- The agent brain (`runAgentTurn`, tool catalog, scope resolution) is never modified or forked — voice reuses it verbatim.
- Audio travels as base64 inside the existing JSON contract (no multipart, no new transport).
- Voice turns are stored identically to typed turns: `text` = Whisper transcript. No DB schema change.
- If `OPENAI_VOICE_KEY` is unset, voice requests fail with the existing `agent_unavailable` (502) shape; typed chat is unaffected.
- If TTS fails after a successful reply, the request still succeeds with text only (no `audioBase64` in the response) — never fail an otherwise-good turn over TTS.
- Per `CLAUDE.md`: this change updates `docs/LIVING_SPEC.md` and adds a `docs/CHANGELOG.md` entry in the same commit as the code (last task).

---

## Task 1: Server — Whisper/TTS provider module

**Files:**
- Create: `supabase/functions/app-hatchery-agent/voice.ts`
- Test: `supabase/functions/app-hatchery-agent/voice_test.ts`

**Interfaces:**
- Produces: `readVoiceConfig(): VoiceConfig | null`, `transcribeAudio(audioBase64: string, config: VoiceConfig): Promise<string>`, `synthesizeSpeech(text: string, config: VoiceConfig): Promise<string>`, `VoiceProviderError`, `interface VoiceConfig { apiKey: string; fetchImpl?: typeof fetch }` — all consumed by Task 2.

- [ ] **Step 1: Write `voice.ts`**

```ts
// supabase/functions/app-hatchery-agent/voice.ts
//
// Wraps OpenAI Whisper (speech-to-text) and TTS (text-to-speech) behind two
// small functions. Uses a dedicated OPENAI_VOICE_KEY secret, kept separate
// from OPENAI_API_KEY (the agent brain's key) so the $5 voice spend cap
// stays isolated from brain billing.
//
// Logging discipline: never log audio bytes, transcripts, or replies.

const TRANSCRIPTION_ENDPOINT = 'https://api.openai.com/v1/audio/transcriptions'
const SPEECH_ENDPOINT = 'https://api.openai.com/v1/audio/speech'
const WHISPER_MODEL = 'whisper-1'
const TTS_MODEL = 'tts-1'
const TTS_VOICE = 'alloy'

export class VoiceProviderError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'VoiceProviderError'
  }
}

export interface VoiceConfig {
  apiKey: string
  fetchImpl?: typeof fetch
}

export function readVoiceConfig(): VoiceConfig | null {
  const apiKey = Deno.env.get('OPENAI_VOICE_KEY')?.trim()
  return apiKey ? { apiKey } : null
}

/** Decodes a base64 audio clip and sends it to Whisper. Returns the transcript. */
export async function transcribeAudio(
  audioBase64: string,
  config: VoiceConfig,
): Promise<string> {
  const bytes = decodeBase64(audioBase64)
  const form = new FormData()
  form.append('file', new Blob([bytes]), 'audio.m4a')
  form.append('model', WHISPER_MODEL)

  const fetchImpl = config.fetchImpl ?? fetch
  let response: Response
  try {
    response = await fetchImpl(TRANSCRIPTION_ENDPOINT, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${config.apiKey}` },
      body: form,
    })
  } catch (_) {
    throw new VoiceProviderError('Transcription request failed')
  }
  if (!response.ok) {
    throw new VoiceProviderError(`Transcription returned HTTP ${response.status}`)
  }
  let payload: unknown
  try {
    payload = await response.json()
  } catch (_) {
    throw new VoiceProviderError('Transcription response is invalid JSON')
  }
  const text = isRecord(payload) && typeof payload.text === 'string'
    ? payload.text.trim()
    : ''
  if (!text) throw new VoiceProviderError('Transcription returned no text')
  return text
}

/** Calls OpenAI TTS on the given text and returns base64-encoded mp3 audio. */
export async function synthesizeSpeech(
  text: string,
  config: VoiceConfig,
): Promise<string> {
  const fetchImpl = config.fetchImpl ?? fetch
  let response: Response
  try {
    response = await fetchImpl(SPEECH_ENDPOINT, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${config.apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ model: TTS_MODEL, voice: TTS_VOICE, input: text }),
    })
  } catch (_) {
    throw new VoiceProviderError('Speech request failed')
  }
  if (!response.ok) {
    throw new VoiceProviderError(`Speech request returned HTTP ${response.status}`)
  }
  let bytes: Uint8Array
  try {
    bytes = new Uint8Array(await response.arrayBuffer())
  } catch (_) {
    throw new VoiceProviderError('Speech response could not be read')
  }
  if (bytes.length === 0) throw new VoiceProviderError('Speech response was empty')
  return encodeBase64(bytes)
}

function decodeBase64(value: string): Uint8Array {
  try {
    const binary = atob(value)
    const bytes = new Uint8Array(binary.length)
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
    return bytes
  } catch (_) {
    throw new VoiceProviderError('audioBase64 is not valid base64')
  }
}

function encodeBase64(bytes: Uint8Array): string {
  let binary = ''
  const chunkSize = 0x8000
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize))
  }
  return btoa(binary)
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
```

- [ ] **Step 2: Write `voice_test.ts`**

```ts
// supabase/functions/app-hatchery-agent/voice_test.ts
import { assertEquals, assertRejects } from '@std/assert'

import {
  readVoiceConfig,
  synthesizeSpeech,
  transcribeAudio,
  VoiceProviderError,
} from './voice.ts'

function fakeFetch(
  handler: (input: string | URL | Request, init?: RequestInit) => Response,
): typeof fetch {
  return ((input: string | URL | Request, init?: RequestInit) =>
    Promise.resolve(handler(input, init))) as typeof fetch
}

Deno.test('readVoiceConfig reads OPENAI_VOICE_KEY and trims it', () => {
  Deno.env.set('OPENAI_VOICE_KEY', '  sk-voice-123  ')
  try {
    assertEquals(readVoiceConfig(), { apiKey: 'sk-voice-123' })
  } finally {
    Deno.env.delete('OPENAI_VOICE_KEY')
  }
})

Deno.test('readVoiceConfig returns null when unset', () => {
  Deno.env.delete('OPENAI_VOICE_KEY')
  assertEquals(readVoiceConfig(), null)
})

Deno.test('transcribeAudio posts multipart form and returns trimmed text', async () => {
  let sawAuth: string | null = null
  const fetchImpl = fakeFetch((_url, init) => {
    sawAuth = (init?.headers as Record<string, string>)['Authorization']
    return new Response(JSON.stringify({ text: '  what is the hatch rate?  ' }), {
      status: 200,
    })
  })
  const text = await transcribeAudio('aGVsbG8=', {
    apiKey: 'sk-test',
    fetchImpl,
  })
  assertEquals(text, 'what is the hatch rate?')
  assertEquals(sawAuth, 'Bearer sk-test')
})

Deno.test('transcribeAudio rejects invalid base64', async () => {
  await assertRejects(
    () => transcribeAudio('not-base64!!!', { apiKey: 'sk-test', fetchImpl: fakeFetch(() => new Response()) }),
    VoiceProviderError,
  )
})

Deno.test('transcribeAudio throws on non-2xx response', async () => {
  const fetchImpl = fakeFetch(() => new Response('', { status: 500 }))
  await assertRejects(
    () => transcribeAudio('aGVsbG8=', { apiKey: 'sk-test', fetchImpl }),
    VoiceProviderError,
  )
})

Deno.test('transcribeAudio throws when text is empty', async () => {
  const fetchImpl = fakeFetch(() => new Response(JSON.stringify({ text: '   ' }), { status: 200 }))
  await assertRejects(
    () => transcribeAudio('aGVsbG8=', { apiKey: 'sk-test', fetchImpl }),
    VoiceProviderError,
  )
})

Deno.test('synthesizeSpeech returns base64 audio bytes round-trippably', async () => {
  const audioBytes = new Uint8Array([1, 2, 3, 4, 5])
  const fetchImpl = fakeFetch(() =>
    new Response(audioBytes, { status: 200 })
  )
  const base64 = await synthesizeSpeech('Hatch was 84%.', {
    apiKey: 'sk-test',
    fetchImpl,
  })
  const decoded = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0))
  assertEquals(Array.from(decoded), Array.from(audioBytes))
})

Deno.test('synthesizeSpeech throws on non-2xx response', async () => {
  const fetchImpl = fakeFetch(() => new Response('', { status: 429 }))
  await assertRejects(
    () => synthesizeSpeech('hi', { apiKey: 'sk-test', fetchImpl }),
    VoiceProviderError,
  )
})

Deno.test('synthesizeSpeech throws on empty audio body', async () => {
  const fetchImpl = fakeFetch(() => new Response(new Uint8Array(0), { status: 200 }))
  await assertRejects(
    () => synthesizeSpeech('hi', { apiKey: 'sk-test', fetchImpl }),
    VoiceProviderError,
  )
})
```

- [ ] **Step 3: Run the tests**

Run: `cd supabase/functions/app-hatchery-agent && deno test --allow-env voice_test.ts`
Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/app-hatchery-agent/voice.ts supabase/functions/app-hatchery-agent/voice_test.ts
git commit -m "feat(voice): add Whisper/TTS provider module"
```

---

## Task 2: Server — wire `audioBase64` into `app-hatchery-agent`

**Files:**
- Modify: `supabase/functions/app-hatchery-agent/index.ts`

**Interfaces:**
- Consumes: `readVoiceConfig`, `transcribeAudio`, `synthesizeSpeech` from Task 1 (`./voice.ts`).
- Produces: `AppAgentDeps.transcribeAudio?(audioBase64: string): Promise<string>` and `AppAgentDeps.synthesizeSpeech?(text: string): Promise<string>` — consumed by Task 3's tests and by `serveAppAgent`'s real wiring in this same task.

- [ ] **Step 1: Add the import**

In `supabase/functions/app-hatchery-agent/index.ts`, add near the top with the other imports:

```ts
import { readVoiceConfig, synthesizeSpeech, transcribeAudio } from './voice.ts'
```

- [ ] **Step 2: Add the audio ceiling constant**

Add next to the other constants near the top of the file (after `RATE_LIMIT_WINDOW_MS`):

```ts
const MAX_AUDIO_BASE64_CHARS = 8_000_000
```

- [ ] **Step 3: Extend `AppAgentDeps`**

Replace the `AppAgentDeps` interface:

```ts
export interface AppAgentDeps {
  adminClient: AppAgentAdminClient
  /** Resolves the bearer token to an auth user, or null when it is invalid. */
  authenticate(accessToken: string): Promise<AppAgentAuthUser | null>
  runAgentTurn(input: AgentTurnInput): Promise<AgentTurnResult>
  /** Transcribes a base64 audio clip. Undefined when voice is not configured. */
  transcribeAudio?(audioBase64: string): Promise<string>
  /** Synthesizes speech for a reply. Undefined when voice is not configured. */
  synthesizeSpeech?(text: string): Promise<string>
  newId?: () => string
  now?: () => string
}
```

- [ ] **Step 4: Add the `readAudioBase64` helper**

Add next to `readMessage`:

```ts
function readAudioBase64(value: unknown): string | null {
  if (typeof value !== 'string') return null
  const trimmed = value.trim()
  if (trimmed.length === 0 || trimmed.length > MAX_AUDIO_BASE64_CHARS) return null
  return trimmed
}
```

- [ ] **Step 5: Replace `handleSend` in full**

Replace the entire `handleSend` function with:

```ts
async function handleSend(params: {
  deps: AppAgentDeps
  scope: AgentScope
  conversation: Record<string, unknown>
  conversationId: string
  contextEpoch: number
  body: Record<string, unknown>
  newId: () => string
  now: () => string
}): Promise<Response> {
  const clientMessageId = nullableString(params.body.clientMessageId)
  if (!clientMessageId || clientMessageId.length > 200) {
    return failure(400, 'invalid_request', 'clientMessageId is required.')
  }
  const idempotencyKey = `app:${clientMessageId}`

  const audioProvided = params.body.audioBase64 !== undefined &&
    params.body.audioBase64 !== null
  let audioBase64Input: string | null = null
  if (audioProvided) {
    audioBase64Input = readAudioBase64(params.body.audioBase64)
    if (!audioBase64Input) {
      return failure(
        400,
        'invalid_request',
        `audioBase64 must be a non-empty base64 string under ${MAX_AUDIO_BASE64_CHARS} characters.`,
      )
    }
  }

  // Replay: the same clientMessageId must return the stored reply, never a
  // second model call (and, for voice, never a second transcription call).
  const existingInbound = await params.deps.adminClient
    .from('agent_conversation_turns')
    .select('id, turn_index, context_epoch, text')
    .eq('telegram_update_id', idempotencyKey)
    .maybeSingle()
  if (existingInbound.error) {
    return failure(500, 'server_error', 'Could not check the message.')
  }
  const replayInboundId = existingInbound.data
    ? nullableString(existingInbound.data.id)
    : null
  if (replayInboundId) {
    const storedReply = await loadStoredReply(params.deps, replayInboundId)
    if (storedReply.error) {
      return failure(500, 'server_error', 'Could not load the stored reply.')
    }
    if (storedReply.reply) {
      const payload: Record<string, unknown> = {
        conversationId: params.conversationId,
        userTurnId: replayInboundId,
        replyTurnId: storedReply.reply.id,
        reply: storedReply.reply.text,
        language: storedReply.reply.language,
        createdAt: storedReply.reply.createdAt,
      }
      if (audioProvided) {
        const transcript = nullableString(existingInbound.data?.text)
        if (transcript) payload.transcript = transcript
        const audio = await synthesizeReplyAudio(params.deps, storedReply.reply.text)
        if (audio) payload.audioBase64 = audio
      }
      return success(payload)
    }
    // The earlier attempt stored the inbound turn but never produced a reply.
    // Fall through and finish that same turn instead of creating a duplicate.
  }

  let message: string | null
  if (audioProvided) {
    if (!params.deps.transcribeAudio) {
      return failure(502, 'agent_unavailable', 'Voice is not available right now.')
    }
    let transcript: string
    try {
      transcript = await params.deps.transcribeAudio(audioBase64Input!)
    } catch (_) {
      return failure(
        502,
        'agent_unavailable',
        'Could not understand the audio. Please try again.',
      )
    }
    message = readMessage(transcript)
  } else {
    message = readMessage(params.body.message)
  }
  if (!message) {
    return audioProvided
      ? failure(
        502,
        'agent_unavailable',
        'Could not understand the audio. Please try again.',
      )
      : failure(
        400,
        'invalid_request',
        `message must be between 1 and ${MAX_MESSAGE_CHARS} characters.`,
      )
  }

  const timestamp = params.now()
  if (!replayInboundId) {
    const limited = await isRateLimited(
      params.deps,
      params.conversationId,
      timestamp,
    )
    if (limited === null) {
      return failure(500, 'server_error', 'Could not check the send rate.')
    }
    if (limited) {
      return failure(
        429,
        'rate_limited',
        'Too many messages. Please wait a moment and try again.',
      )
    }
  }

  const historyResult = await params.deps.adminClient
    .from('agent_conversation_turns')
    .select('id, direction, text, turn_index, created_at')
    .eq('conversation_id', params.conversationId)
    .eq('context_epoch', params.contextEpoch)
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .limit(HISTORY_FETCH_LIMIT)
  if (historyResult.error) {
    return failure(500, 'server_error', 'Could not load the conversation.')
  }
  const storedTurns = historyResult.data ?? []

  let inboundTurnId = replayInboundId
  let turnIndex = replayInboundId && existingInbound.data
    ? integerValue(existingInbound.data.turn_index) ?? 1
    : 0
  if (!inboundTurnId) {
    const latestInboundIndex = storedTurns.reduce((latest, turn) => {
      if (turn.direction !== 'inbound') return latest
      const value = integerValue(turn.turn_index)
      return value === null ? latest : Math.max(latest, value)
    }, 0)
    turnIndex = latestInboundIndex + 1
    inboundTurnId = params.newId()
    const inboundInsert = await params.deps.adminClient
      .from('agent_conversation_turns')
      .insert({
        id: inboundTurnId,
        conversation_id: params.conversationId,
        direction: 'inbound',
        turn_index: turnIndex,
        context_epoch: params.contextEpoch,
        telegram_update_id: idempotencyKey,
        telegram_message_id: null,
        text: message,
        language: detectAgentLanguage(message),
        provider: null,
        model: null,
        provider_response_id: null,
        attachment_json: null,
        delivery_status: 'received',
        created_at: timestamp,
      })
    if (inboundInsert.error) {
      // A concurrent request won the idempotency race.
      const stored = await loadStoredReplyByKey(params.deps, idempotencyKey)
      if (stored) {
        return success({ conversationId: params.conversationId, ...stored })
      }
      return failure(500, 'server_error', 'Could not store the message.')
    }
  }

  const activeVisitId = nullableString(params.conversation.active_visit_id)
  let activeIntake: Record<string, unknown> | null = null
  if (activeVisitId) {
    const activeResult = await params.deps.adminClient
      .from('agent_intake_sessions')
      .select(
        'id, visit_id, state, schema_key, schema_version, row_version, ' +
          'working_values_json, pending_clarification_json, summary_version, ' +
          'summary_snapshot_json, user_confirmed_at, updated_at',
      )
      .eq('visit_id', activeVisitId)
      .order('updated_at', { ascending: false })
      .order('id', { ascending: false })
      .limit(1)
    if (!activeResult.error) activeIntake = activeResult.data?.[0] ?? null
  }

  let result: AgentTurnResult
  try {
    result = await params.deps.runAgentTurn({
      scope: params.scope,
      conversationId: params.conversationId,
      activeVisitId,
      conversationTurnId: inboundTurnId,
      conversationTurnIndex: turnIndex,
      conversationContextEpoch: params.contextEpoch,
      text: message,
      attachment: null,
      recentTurns: storedTurns
        .slice()
        .reverse()
        .flatMap((turn) => {
          const role = directionToRole(turn.direction)
          const turnText = nullableString(turn.text)
          return role && turnText ? [{ role, text: turnText }] : []
        })
        .slice(-MODEL_HISTORY_TURNS),
      pendingAction: jsonObjectOrNull(params.conversation.pending_action_json),
      activeIntake,
    })
  } catch (_) {
    console.error('app-hatchery-agent: agent turn threw')
    return failure(
      502,
      'agent_unavailable',
      'The assistant is temporarily unavailable. Please try again shortly.',
    )
  }

  if (result.status !== 'replied') {
    console.error(`app-hatchery-agent: agent turn status ${result.status}`)
    return failure(
      502,
      'agent_unavailable',
      'The assistant is temporarily unavailable. Please try again shortly.',
    )
  }

  const replyTimestamp = params.now()
  const outboundTurnId = params.newId()
  const language = detectAgentLanguage(result.reply)
  const outboundInsert = await params.deps.adminClient
    .from('agent_conversation_turns')
    .insert({
      id: outboundTurnId,
      conversation_id: params.conversationId,
      direction: 'outbound',
      turn_index: turnIndex,
      context_epoch: params.contextEpoch,
      reply_to_turn_id: inboundTurnId,
      telegram_update_id: null,
      telegram_message_id: null,
      text: result.reply,
      language,
      provider: result.provider ?? null,
      model: result.model ?? null,
      provider_response_id: result.providerResponseId,
      attachment_json: null,
      delivery_status: 'delivered',
      created_at: replyTimestamp,
    })
  if (outboundInsert.error) {
    return failure(500, 'server_error', 'Could not store the reply.')
  }

  const replyPayload: Record<string, unknown> = {
    conversationId: params.conversationId,
    userTurnId: inboundTurnId,
    replyTurnId: outboundTurnId,
    reply: result.reply,
    language,
    createdAt: replyTimestamp,
  }
  if (audioProvided) {
    replyPayload.transcript = message
    const audio = await synthesizeReplyAudio(params.deps, result.reply)
    if (audio) replyPayload.audioBase64 = audio
  }
  return success(replyPayload)
}

async function synthesizeReplyAudio(
  deps: AppAgentDeps,
  text: string,
): Promise<string | null> {
  if (!deps.synthesizeSpeech) return null
  try {
    return await deps.synthesizeSpeech(text)
  } catch (_) {
    console.error('app-hatchery-agent: speech synthesis failed')
    return null
  }
}
```

Note the one deliberate change from the original: the empty-transcript failure
(`!message` when `audioProvided`) now returns 502 `agent_unavailable` instead
of 400 `invalid_request` — this is a transcription quality problem, not a
malformed request, so it gets the same status/messaging as the other voice
failure modes ("assistant unavailable") instead of the client's 400 copy
("edit it and try again"), which doesn't make sense for audio.

- [ ] **Step 6: Wire real Whisper/TTS into `serveAppAgent`**

In `serveAppAgent`, replace:

```ts
  return handleAppAgentRequest(request, {
    adminClient,
    authenticate: async (accessToken) => {
      const result = await supabase.auth.getUser(accessToken)
      if (result.error || !result.data?.user) return null
      return { id: result.data.user.id }
    },
    runAgentTurn: (input) =>
```

with:

```ts
  const voiceConfig = readVoiceConfig()

  return handleAppAgentRequest(request, {
    adminClient,
    authenticate: async (accessToken) => {
      const result = await supabase.auth.getUser(accessToken)
      if (result.error || !result.data?.user) return null
      return { id: result.data.user.id }
    },
    transcribeAudio: voiceConfig
      ? (audioBase64) => transcribeAudio(audioBase64, voiceConfig)
      : undefined,
    synthesizeSpeech: voiceConfig
      ? (text) => synthesizeSpeech(text, voiceConfig)
      : undefined,
    runAgentTurn: (input) =>
```

(leave everything after `runAgentTurn: (input) =>` unchanged — this only adds two new properties above it).

- [ ] **Step 7: Type-check**

Run: `cd supabase/functions/app-hatchery-agent && deno check index.ts`
Expected: no errors.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/app-hatchery-agent/index.ts
git commit -m "feat(voice): accept audioBase64 on app-hatchery-agent send"
```

---

## Task 3: Server — tests for the voice send path

**Files:**
- Modify: `supabase/functions/app-hatchery-agent/index_test.ts`

**Interfaces:**
- Consumes: `AppAgentDeps.transcribeAudio` / `.synthesizeSpeech` (Task 2), `createHarness` (existing, extended below).

- [ ] **Step 1: Extend `createHarness` to accept voice fakes**

In `index_test.ts`, replace the `Harness` interface and `createHarness` function:

```ts
interface Harness {
  db: FakeDatabase
  deps: AppAgentDeps
  turns: AgentTurnInput[]
  scopes: AgentScope[]
  transcribeCalls: string[]
  synthesizeCalls: string[]
}

function createHarness(options: {
  db?: FakeDatabase
  turn?: (input: AgentTurnInput) => AgentTurnResult | Promise<AgentTurnResult>
  authUserId?: string | null
  now?: () => string
  transcribeAudio?: (audioBase64: string) => Promise<string>
  synthesizeSpeech?: (text: string) => Promise<string>
} = {}): Harness {
  const db = options.db ?? seedDatabase()
  const turns: AgentTurnInput[] = []
  const scopes: AgentScope[] = []
  const transcribeCalls: string[] = []
  const synthesizeCalls: string[] = []
  const deps: AppAgentDeps = {
    adminClient: createFakeAdminClient(db) as unknown as AppAgentAdminClient,
    authenticate: (_token) =>
      Promise.resolve(
        options.authUserId === null
          ? null
          : { id: options.authUserId ?? 'user-customer' },
      ),
    runAgentTurn: async (input) => {
      turns.push(input)
      scopes.push(input.scope)
      const handler = options.turn ??
        ((_: AgentTurnInput): AgentTurnResult => ({
          status: 'replied',
          reply: 'Hatchability is 84%.',
          providerResponseId: 'resp-1',
          provider: 'openai',
          model: 'gpt-4.1-mini',
          toolCallCount: 0,
        }))
      return await handler(input)
    },
    transcribeAudio: options.transcribeAudio
      ? (audioBase64) => {
        transcribeCalls.push(audioBase64)
        return options.transcribeAudio!(audioBase64)
      }
      : undefined,
    synthesizeSpeech: options.synthesizeSpeech
      ? (text) => {
        synthesizeCalls.push(text)
        return options.synthesizeSpeech!(text)
      }
      : undefined,
    newId: sequentialIds('id'),
    now: options.now ?? (() => NOW),
  }
  return { db, deps, turns, scopes, transcribeCalls, synthesizeCalls }
}
```

- [ ] **Step 2: Add voice send tests**

Add near the end of `index_test.ts`, before the final closing of the file (find the existing `Deno.test('...')` blocks for `action: 'send'` and add these alongside them):

```ts
Deno.test('send with audioBase64 transcribes, stores the transcript, and returns audio', async () => {
  const harness = createHarness({
    transcribeAudio: (_audio) => Promise.resolve('What is the hatch rate?'),
    synthesizeSpeech: (_text) => Promise.resolve('c3ludGhlc2l6ZWQ='),
  })
  const response = await handleAppAgentRequest(
    postRequest({ action: 'send', audioBase64: 'aGVsbG8=', clientMessageId: 'voice-1' }),
    harness.deps,
  )
  assertEquals(response.status, 200)
  const body = await response.json()
  assertEquals(body.reply, 'Hatchability is 84%.')
  assertEquals(body.transcript, 'What is the hatch rate?')
  assertEquals(body.audioBase64, 'c3ludGhlc2l6ZWQ=')
  assertEquals(harness.transcribeCalls, ['aGVsbG8='])
  assertEquals(harness.synthesizeCalls, ['Hatchability is 84%.'])

  const stored = harness.db.tables.agent_conversation_turns.find(
    (turn) => turn.direction === 'inbound',
  )
  assertEquals(stored?.text, 'What is the hatch rate?')
})

Deno.test('send with audioBase64 returns text-only when TTS fails', async () => {
  const harness = createHarness({
    transcribeAudio: (_audio) => Promise.resolve('Question'),
    synthesizeSpeech: (_text) => Promise.reject(new Error('tts down')),
  })
  const response = await handleAppAgentRequest(
    postRequest({ action: 'send', audioBase64: 'aGVsbG8=', clientMessageId: 'voice-2' }),
    harness.deps,
  )
  assertEquals(response.status, 200)
  const body = await response.json()
  assertEquals(body.reply, 'Hatchability is 84%.')
  assert(!('audioBase64' in body))
})

Deno.test('send with audioBase64 fails when voice is not configured', async () => {
  const harness = createHarness()
  const response = await handleAppAgentRequest(
    postRequest({ action: 'send', audioBase64: 'aGVsbG8=', clientMessageId: 'voice-3' }),
    harness.deps,
  )
  assertEquals(response.status, 502)
  const body = await response.json()
  assertEquals(body.code, 'agent_unavailable')
})

Deno.test('send rejects an empty audioBase64', async () => {
  const harness = createHarness({
    transcribeAudio: (_audio) => Promise.resolve('unused'),
  })
  const response = await handleAppAgentRequest(
    postRequest({ action: 'send', audioBase64: '', clientMessageId: 'voice-4' }),
    harness.deps,
  )
  assertEquals(response.status, 400)
  const body = await response.json()
  assertEquals(body.code, 'invalid_request')
  assertEquals(harness.transcribeCalls, [])
})

Deno.test('send with audioBase64 fails when transcription throws', async () => {
  const harness = createHarness({
    transcribeAudio: (_audio) => Promise.reject(new Error('whisper down')),
  })
  const response = await handleAppAgentRequest(
    postRequest({ action: 'send', audioBase64: 'aGVsbG8=', clientMessageId: 'voice-5' }),
    harness.deps,
  )
  assertEquals(response.status, 502)
  const body = await response.json()
  assertEquals(body.code, 'agent_unavailable')
})

Deno.test('replaying a voice send returns stored transcript and fresh audio without re-transcribing', async () => {
  const harness = createHarness({
    transcribeAudio: (_audio) => Promise.resolve('What is the hatch rate?'),
    synthesizeSpeech: (_text) => Promise.resolve('YXVkaW8x'),
  })
  const first = await handleAppAgentRequest(
    postRequest({ action: 'send', audioBase64: 'aGVsbG8=', clientMessageId: 'voice-6' }),
    harness.deps,
  )
  assertEquals(first.status, 200)
  assertEquals(harness.transcribeCalls.length, 1)

  const second = await handleAppAgentRequest(
    postRequest({ action: 'send', audioBase64: 'aGVsbG8=', clientMessageId: 'voice-6' }),
    harness.deps,
  )
  assertEquals(second.status, 200)
  const body = await second.json()
  assertEquals(body.transcript, 'What is the hatch rate?')
  assertEquals(body.reply, 'Hatchability is 84%.')
  // No second transcription call — the replay short-circuits before Whisper.
  assertEquals(harness.transcribeCalls.length, 1)
  assertEquals(harness.synthesizeCalls.length, 2)
})
```

- [ ] **Step 3: Run the tests**

Run: `cd supabase/functions/app-hatchery-agent && deno test --allow-env index_test.ts`
Expected: all PASS, including the pre-existing tests (unmodified typed-message behavior).

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/app-hatchery-agent/index_test.ts
git commit -m "test(voice): cover the audioBase64 send path"
```

---

## Task 4: Filler chime asset

**Files:**
- Create: `assets/audio/filler_chime.wav`
- Modify: `pubspec.yaml`

**Interfaces:**
- Produces: bundled asset at path `audio/filler_chime.wav` (relative to the `audioplayers` default `assets/` prefix), consumed by Task 6's `AssistantAudioPlayer.playAsset`.

- [ ] **Step 1: Generate the chime**

Run this one-off script to synthesize a short, language-agnostic two-tone chime (no spoken words, so it needs no localization):

```bash
python3 - <<'PY'
import wave, struct, math, os

os.makedirs('assets/audio', exist_ok=True)
rate = 22050
notes = [(880, 0.12), (0, 0.03), (1174, 0.16)]  # A5 then D6, short gap between

frames = []
for freq, duration in notes:
    n = int(rate * duration)
    for i in range(n):
        if freq == 0:
            frames.append(0)
            continue
        t = i / rate
        # Fade in/out to avoid clicks.
        envelope = min(1.0, i / (rate * 0.01), (n - i) / (rate * 0.01))
        sample = math.sin(2 * math.pi * freq * t) * 0.4 * envelope
        frames.append(int(sample * 32767))

with wave.open('assets/audio/filler_chime.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(rate)
    f.writeframes(b''.join(struct.pack('<h', s) for s in frames))
PY
ls -la assets/audio/filler_chime.wav
```

Expected: file created, non-zero size (a few hundred KB, uncompressed).

- [ ] **Step 2: Register the asset**

In `pubspec.yaml`, under `flutter: assets:`, add the new line so the block reads:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/branding/chickmark-icon.png
    - assets/branding/chickmark-mark-onbrand.png
    - assets/audio/filler_chime.wav
    - .env.json
```

- [ ] **Step 3: Commit**

```bash
git add assets/audio/filler_chime.wav pubspec.yaml
git commit -m "feat(voice): add bundled filler chime asset"
```

---

## Task 5: Flutter — add `record` and `audioplayers` dependencies

**Files:**
- Modify: `pubspec.yaml`
- Modify: `ios/Runner/Info.plist`
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Add the packages**

In `pubspec.yaml`, under `dependencies:`, add (alphabetical position not required — append near the other feature packages):

```yaml
  record: ^5.2.1
  audioplayers: ^6.1.0
```

- [ ] **Step 2: Run `flutter pub get`**

Run: `flutter pub get`
Expected: resolves cleanly. If either version conflicts with an existing constraint, bump to the latest version `flutter pub get` reports as compatible and re-run.

- [ ] **Step 3: Add the iOS microphone usage description**

In `ios/Runner/Info.plist`, after the `NSPhotoLibraryUsageDescription` entry (around line 32), add:

```xml
	<key>NSMicrophoneUsageDescription</key>
	<string>ChickMark uses the microphone so you can ask the assistant questions by voice.</string>
```

- [ ] **Step 4: Add the Android record-audio permission**

In `android/app/src/main/AndroidManifest.xml`, add alongside the other `<uses-permission>` lines (after `POST_NOTIFICATIONS`):

```xml
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
```

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock ios/Runner/Info.plist android/app/src/main/AndroidManifest.xml
git commit -m "feat(voice): add record/audioplayers deps and mic permissions"
```

---

## Task 6: Flutter — audio recorder/player ports

**Files:**
- Create: `lib/services/audio/assistant_audio_recorder.dart`
- Create: `lib/services/audio/assistant_audio_player.dart`

**Interfaces:**
- Produces: `abstract interface class AssistantAudioRecorder { Future<void> start(); Future<String?> stop(); bool get isRecording; }`, `class AssistantAudioException implements Exception`, `class RecordAssistantAudioRecorder implements AssistantAudioRecorder`, `abstract interface class AssistantAudioPlayer { Future<void> playAsset(String assetPath); Future<void> playBase64(String base64Audio); Future<void> stop(); }`, `class AudioplayersAssistantAudioPlayer implements AssistantAudioPlayer` — all consumed by Task 7.

- [ ] **Step 1: Write `assistant_audio_recorder.dart`**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Records short voice questions and returns them as base64-encoded audio.
///
/// Abstracted behind this interface so widget/provider tests never touch the
/// real microphone.
abstract interface class AssistantAudioRecorder {
  /// Requests mic permission if needed and starts recording. Throws
  /// [AssistantAudioException] if permission is denied or recording could
  /// not start.
  Future<void> start();

  /// Stops recording and returns the clip as base64. Returns null if no
  /// recording was in progress, or if the clip could not be read back.
  Future<String?> stop();

  /// True while a recording is in progress.
  bool get isRecording;
}

class AssistantAudioException implements Exception {
  const AssistantAudioException(this.message);
  final String message;
  @override
  String toString() => message;
}

class RecordAssistantAudioRecorder implements AssistantAudioRecorder {
  RecordAssistantAudioRecorder({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  String? _path;

  @override
  bool get isRecording => _path != null;

  @override
  Future<void> start() async {
    if (_path != null) return;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw const AssistantAudioException(
        'Microphone access is needed to ask by voice.',
      );
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/assistant-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    _path = path;
  }

  @override
  Future<String?> stop() async {
    final wasRecording = _path != null;
    _path = null;
    if (!wasRecording) return null;
    final path = await _recorder.stop();
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    await file.delete();
    return base64Encode(bytes);
  }
}
```

- [ ] **Step 2: Write `assistant_audio_player.dart`**

```dart
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';

/// Plays short assistant audio clips: the bundled filler chime and the TTS
/// reply returned by the server. Abstracted so tests never touch a real
/// audio device.
abstract interface class AssistantAudioPlayer {
  /// [assetPath] is relative to the `assets/` prefix, e.g. `audio/filler_chime.wav`.
  Future<void> playAsset(String assetPath);
  Future<void> playBase64(String base64Audio);
  Future<void> stop();
}

class AudioplayersAssistantAudioPlayer implements AssistantAudioPlayer {
  AudioplayersAssistantAudioPlayer({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> playAsset(String assetPath) async {
    await _player.stop();
    await _player.play(AssetSource(assetPath));
  }

  @override
  Future<void> playBase64(String base64Audio) async {
    await _player.stop();
    await _player.play(BytesSource(base64Decode(base64Audio)));
  }

  @override
  Future<void> stop() => _player.stop();
}
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/services/audio`
Expected: no issues.

- [ ] **Step 4: Commit**

```bash
git add lib/services/audio
git commit -m "feat(voice): add recorder/player ports over record and audioplayers"
```

---

## Task 7: Flutter — `sendVoice` on the chat port/service

**Files:**
- Modify: `lib/services/supabase/assistant_chat_service.dart`
- Modify: `test/features/chat/assistant_chat_service_test.dart`
- Modify: `test/features/chat/fake_assistant_chat_port.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `AssistantChatPort.sendVoice(String audioBase64, {String? clientMessageId}): Future<AssistantChatReply>`, `AssistantChatReply.transcript` and `.audioBase64` (both `String?`) — consumed by Task 8.

- [ ] **Step 1: Add the failing test**

In `test/features/chat/assistant_chat_service_test.dart`, find the existing tests around `sendMessage` (open the file to match its exact structure — it follows the same `AssistantChatRpc` fake-body pattern as `assistant_provider_test.dart`) and add:

```dart
test('sendVoice posts audioBase64 and parses transcript + audioBase64', () async {
  Map<String, dynamic>? capturedBody;
  final service = AssistantChatService(
    rpc: (body) async {
      capturedBody = body;
      return {
        'conversationId': 'conv-1',
        'userTurnId': 'turn-user',
        'replyTurnId': 'turn-reply',
        'reply': 'Hatch was 84%.',
        'transcript': 'What is the hatch rate?',
        'audioBase64': 'c3ludGg=',
        'createdAt': '2026-08-14T10:00:00.000Z',
        'language': 'en',
      };
    },
  );

  final reply = await service.sendVoice('aGVsbG8=', clientMessageId: 'cid-1');

  expect(capturedBody, {
    'action': 'send',
    'audioBase64': 'aGVsbG8=',
    'clientMessageId': 'cid-1',
  });
  expect(reply.reply, 'Hatch was 84%.');
  expect(reply.transcript, 'What is the hatch rate?');
  expect(reply.audioBase64, 'c3ludGg=');
});

test('sendVoice rejects an empty audio payload without a request', () async {
  var invoked = false;
  final service = AssistantChatService(
    rpc: (_) async {
      invoked = true;
      return <String, dynamic>{};
    },
  );

  await expectLater(
    () => service.sendVoice(''),
    throwsA(isA<AssistantChatException>()),
  );
  expect(invoked, isFalse);
});
```

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/features/chat/assistant_chat_service_test.dart`
Expected: FAIL — `sendVoice` is not defined on `AssistantChatService`.

- [ ] **Step 3: Add `transcript`/`audioBase64` to `AssistantChatReply`**

In `lib/services/supabase/assistant_chat_service.dart`, replace the `AssistantChatReply` class:

```dart
class AssistantChatReply {
  const AssistantChatReply({
    required this.conversationId,
    required this.userTurnId,
    required this.replyTurnId,
    required this.reply,
    required this.createdAt,
    required this.language,
    this.transcript,
    this.audioBase64,
  });

  final String conversationId;
  final String userTurnId;
  final String replyTurnId;
  final String reply;
  final DateTime createdAt;
  final String? language;

  /// The Whisper transcript of the user's audio, present only when the turn
  /// originated as a voice message.
  final String? transcript;

  /// Base64-encoded TTS audio for [reply], present only when the turn
  /// originated as a voice message and speech synthesis succeeded.
  final String? audioBase64;

  /// The assistant turn as it should appear in the message list.
  ChatMessage toAssistantMessage() => ChatMessage(
    id: replyTurnId,
    role: ChatMessageRole.assistant,
    text: reply,
    createdAt: createdAt,
    language: language,
  );
}
```

- [ ] **Step 4: Add `sendVoice` to the port and service**

In the same file, replace the `AssistantChatPort` interface's `sendMessage` declaration to add a sibling method:

```dart
abstract interface class AssistantChatPort {
  /// Sends one user turn and returns the assistant's reply.
  ///
  /// [clientMessageId] is optional; when omitted the implementation mints a
  /// fresh v4 uuid. Passing the same id twice returns the same stored reply
  /// rather than producing a second turn, which is what makes retry safe.
  Future<AssistantChatReply> sendMessage(String message, {String? clientMessageId});

  /// Sends one recorded question as base64 audio and returns the assistant's
  /// reply, including the Whisper [AssistantChatReply.transcript] and TTS
  /// [AssistantChatReply.audioBase64] when available.
  Future<AssistantChatReply> sendVoice(String audioBase64, {String? clientMessageId});

  /// Loads the visible conversation, oldest turn first.
  Future<AssistantChatHistory> loadHistory({int limit = 50});

  /// Clears the visible conversation. Prior turns are retained server-side but
  /// are no longer shown or sent to the model.
  Future<void> resetConversation();
}
```

Add the ceiling constant next to `assistantMessageMaxLength`:

```dart
/// Server-imposed ceiling on a single message, per the frozen contract.
const int assistantMessageMaxLength = 4000;

/// Client-side ceiling on a single base64-encoded voice clip, matching the
/// server's MAX_AUDIO_BASE64_CHARS.
const int assistantAudioMaxBase64Chars = 8000000;
```

Add the implementation to `AssistantChatService`, right after `sendMessage`:

```dart
  @override
  Future<AssistantChatReply> sendVoice(
    String audioBase64, {
    String? clientMessageId,
  }) async {
    final trimmed = audioBase64.trim();
    if (trimmed.isEmpty) {
      throw const AssistantChatException(
        'Record a question before sending.',
        'invalid_request',
      );
    }
    if (trimmed.length > assistantAudioMaxBase64Chars) {
      throw const AssistantChatException(
        'That recording is too long. Try a shorter question.',
        'invalid_request',
      );
    }

    final payload = await _invoke({
      'action': 'send',
      'audioBase64': trimmed,
      'clientMessageId': clientMessageId ?? _newClientMessageId(),
    });
    final row = _object(payload);
    return AssistantChatReply(
      conversationId: _requiredText(row['conversationId'], 'conversationId'),
      userTurnId: _requiredText(row['userTurnId'], 'userTurnId'),
      replyTurnId: _requiredText(row['replyTurnId'], 'replyTurnId'),
      reply: _requiredText(row['reply'], 'reply'),
      createdAt: _timestamp(row['createdAt']),
      language: row['language']?.toString(),
      transcript: row['transcript']?.toString(),
      audioBase64: row['audioBase64']?.toString(),
    );
  }
```

- [ ] **Step 5: Run the test again**

Run: `flutter test test/features/chat/assistant_chat_service_test.dart`
Expected: PASS.

- [ ] **Step 6: Add `sendVoice` to the shared fake port**

In `test/features/chat/fake_assistant_chat_port.dart`, add tracking fields and the method:

```dart
  final List<String> sentMessages = [];
  final List<String?> sentClientMessageIds = [];
  final List<String> sentAudio = [];
  int historyCount = 0;
  int resetCount = 0;
```

```dart
  @override
  Future<AssistantChatReply> sendVoice(
    String audioBase64, {
    String? clientMessageId,
  }) {
    sentAudio.add(audioBase64);
    sentClientMessageIds.add(clientMessageId);
    final error = sendError;
    if (error != null) return Future.error(error);
    if (!manualSend) return Future.value(nextReply);
    final completer = Completer<AssistantChatReply>();
    _pendingSend = completer;
    return completer.future;
  }
```

Place it directly after the existing `sendMessage` override.

- [ ] **Step 7: Run the full chat test suite**

Run: `flutter test test/features/chat`
Expected: PASS (existing tests still compile now that `AssistantChatPort` has a new required method the fake implements).

- [ ] **Step 8: Commit**

```bash
git add lib/services/supabase/assistant_chat_service.dart test/features/chat/assistant_chat_service_test.dart test/features/chat/fake_assistant_chat_port.dart
git commit -m "feat(voice): add sendVoice to the assistant chat port/service"
```

---

## Task 8: Flutter — voice state in `AssistantProvider`

**Files:**
- Modify: `lib/features/chat/providers/assistant_provider.dart`
- Modify: `test/features/chat/assistant_provider_test.dart`

**Interfaces:**
- Consumes: `AssistantAudioRecorder`, `AssistantAudioPlayer` (Task 6); `AssistantChatPort.sendVoice`, `AssistantChatReply.transcript`/`.audioBase64` (Task 7).
- Produces: `AssistantProvider.isRecording`, `.isAwaitingVoiceReply`, `.isSpeaking` (all `bool`), `.startRecording()`, `.stopRecordingAndSend()` — consumed by Task 9.

- [ ] **Step 1: Write the failing tests**

Add to `test/features/chat/assistant_provider_test.dart` (needs a fake recorder/player — add these small fakes at the top of the file, above `void main()`):

```dart
import 'dart:async';

import 'package:hatchaudit/services/audio/assistant_audio_player.dart';
import 'package:hatchaudit/services/audio/assistant_audio_recorder.dart';

class FakeAssistantAudioRecorder implements AssistantAudioRecorder {
  Object? startError;
  String? nextClip = 'ZmFrZS1hdWRpbw==';
  bool _recording = false;
  int startCount = 0;
  int stopCount = 0;

  @override
  bool get isRecording => _recording;

  @override
  Future<void> start() async {
    startCount++;
    final error = startError;
    if (error != null) throw error;
    _recording = true;
  }

  @override
  Future<String?> stop() async {
    stopCount++;
    _recording = false;
    return nextClip;
  }
}

class FakeAssistantAudioPlayer implements AssistantAudioPlayer {
  final List<String> playedAssets = [];
  final List<String> playedBase64 = [];

  @override
  Future<void> playAsset(String assetPath) async {
    playedAssets.add(assetPath);
  }

  @override
  Future<void> playBase64(String base64Audio) async {
    playedBase64.add(base64Audio);
  }

  @override
  Future<void> stop() async {}
}
```

Then add these tests inside `void main() { ... }`, alongside the existing ones (update `providerWith` to also build the audio fakes so voice tests can reach them — add a second helper rather than editing the existing signature, to avoid touching every existing call site):

```dart
  AssistantProvider voiceProviderWith(
    FakeAssistantChatPort port, {
    FakeAssistantAudioRecorder? recorder,
    FakeAssistantAudioPlayer? player,
  }) {
    var counter = 0;
    return AssistantProvider(
      port: port,
      clientMessageIdFactory: () => 'cid-${++counter}',
      audioRecorder: recorder ?? FakeAssistantAudioRecorder(),
      audioPlayer: player ?? FakeAssistantAudioPlayer(),
    );
  }

  test('startRecording flips isRecording on success', () async {
    final recorder = FakeAssistantAudioRecorder();
    final provider = voiceProviderWith(FakeAssistantChatPort(), recorder: recorder);

    await provider.startRecording();

    expect(provider.isRecording, isTrue);
    expect(recorder.startCount, 1);
    expect(provider.error, isNull);
  });

  test('startRecording surfaces a permission error without recording', () async {
    final recorder = FakeAssistantAudioRecorder()
      ..startError = const AssistantAudioException('Microphone access is needed to ask by voice.');
    final provider = voiceProviderWith(FakeAssistantChatPort(), recorder: recorder);

    await provider.startRecording();

    expect(provider.isRecording, isFalse);
    expect(provider.error, contains('Microphone access'));
  });

  test('stopRecordingAndSend plays the chime, then sends, then plays the reply', () async {
    final recorder = FakeAssistantAudioRecorder();
    final player = FakeAssistantAudioPlayer();
    final port = FakeAssistantChatPort(
      nextReply: AssistantChatReply(
        conversationId: 'conv-1',
        userTurnId: 'turn-user',
        replyTurnId: 'turn-reply',
        reply: 'Hatch was 84%.',
        createdAt: DateTime.utc(2026, 8, 14, 10),
        language: 'en',
        transcript: 'What is the hatch rate?',
        audioBase64: 'YXVkaW8tcmVwbHk=',
      ),
    );
    final provider = voiceProviderWith(port, recorder: recorder, player: player);

    await provider.startRecording();
    await provider.stopRecordingAndSend();

    expect(recorder.stopCount, 1);
    expect(port.sentAudio, ['ZmFrZS1hdWRpbw==']);
    expect(player.playedAssets, ['audio/filler_chime.wav']);
    expect(player.playedBase64, ['YXVkaW8tcmVwbHk=']);
    expect(provider.messages, hasLength(2));
    expect(provider.messages.first.text, 'What is the hatch rate?');
    expect(provider.messages.first.role, ChatMessageRole.user);
    expect(provider.messages.last.text, 'Hatch was 84%.');
    expect(provider.isAwaitingVoiceReply, isFalse);
    expect(provider.isSpeaking, isFalse);
  });

  test('stopRecordingAndSend with no clip is a no-op', () async {
    final recorder = FakeAssistantAudioRecorder()..nextClip = null;
    final port = FakeAssistantChatPort();
    final provider = voiceProviderWith(port, recorder: recorder);

    await provider.startRecording();
    await provider.stopRecordingAndSend();

    expect(port.sentAudio, isEmpty);
    expect(provider.messages, isEmpty);
  });

  test('a failed voice send marks the turn failed and keeps a placeholder', () async {
    final recorder = FakeAssistantAudioRecorder();
    final port = FakeAssistantChatPort(
      sendError: const AssistantChatException(
        'The assistant is unavailable right now. Try again shortly.',
        'agent_unavailable',
      ),
    );
    final provider = voiceProviderWith(port, recorder: recorder);

    await provider.startRecording();
    await provider.stopRecordingAndSend();

    expect(provider.messages, hasLength(1));
    expect(provider.messages.single.status, ChatMessageStatus.failed);
    expect(provider.error, contains('unavailable right now'));
  });
```

- [ ] **Step 2: Run to see it fail**

Run: `flutter test test/features/chat/assistant_provider_test.dart`
Expected: FAIL — `AssistantProvider` has no `audioRecorder`/`audioPlayer` constructor params, `startRecording`, or `stopRecordingAndSend`.

- [ ] **Step 3: Implement the voice state in `AssistantProvider`**

In `lib/features/chat/providers/assistant_provider.dart`, update the imports:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../services/audio/assistant_audio_player.dart';
import '../../../services/audio/assistant_audio_recorder.dart';
import '../../../services/supabase/assistant_chat_service.dart';
import '../models/chat_message.dart';
```

Update the constructor and fields:

```dart
class AssistantProvider extends ChangeNotifier {
  AssistantProvider({
    AssistantChatPort? port,
    AssistantClientMessageIdFactory? clientMessageIdFactory,
    AssistantAudioRecorder? audioRecorder,
    AssistantAudioPlayer? audioPlayer,
  }) : _port = port ?? AssistantChatService(),
       _newClientMessageId =
           clientMessageIdFactory ?? (() => const Uuid().v4()),
       _audioRecorder = audioRecorder ?? RecordAssistantAudioRecorder(),
       _audioPlayer = audioPlayer ?? AudioplayersAssistantAudioPlayer();

  final AssistantChatPort _port;
  final AssistantClientMessageIdFactory _newClientMessageId;
  final AssistantAudioRecorder _audioRecorder;
  final AssistantAudioPlayer _audioPlayer;

  static const String _fillerChimeAsset = 'audio/filler_chime.wav';

  final List<ChatMessage> _messages = <ChatMessage>[];
  AssistantLoadState _loadState = AssistantLoadState.uninitialized;
  bool _isSending = false;
  bool _isRecording = false;
  bool _isAwaitingVoiceReply = false;
  bool _isSpeaking = false;
  String? _error;
  bool _disposed = false;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  AssistantLoadState get loadState => _loadState;
  bool get isLoading => _loadState == AssistantLoadState.loading;
  bool get isSending => _isSending;
  bool get isRecording => _isRecording;
  bool get isAwaitingVoiceReply => _isAwaitingVoiceReply;
  bool get isSpeaking => _isSpeaking;
  String? get error => _error;
  bool get isEmpty => _messages.isEmpty;
```

Add the two new methods after `send` (before `retry`):

```dart
  Future<void> startRecording() async {
    if (_isSending || _isRecording || _isAwaitingVoiceReply) return;
    try {
      await _audioRecorder.start();
    } on AssistantAudioException catch (error) {
      _error = error.message;
      _notify();
      return;
    }
    _isRecording = true;
    _error = null;
    _notify();
  }

  /// Stops recording, sends the clip, and auto-plays whatever comes back:
  /// a filler chime while waiting, then the TTS reply audio.
  Future<void> stopRecordingAndSend() async {
    if (!_isRecording) return;
    _isRecording = false;
    final audioBase64 = await _audioRecorder.stop();
    if (audioBase64 == null || audioBase64.isEmpty) {
      _notify();
      return;
    }

    final clientMessageId = _newClientMessageId();
    final pending = ChatMessage(
      id: clientMessageId,
      role: ChatMessageRole.user,
      text: 'Voice message',
      createdAt: DateTime.now().toUtc(),
      status: ChatMessageStatus.sending,
      clientMessageId: clientMessageId,
    );
    _messages.add(pending);
    _isAwaitingVoiceReply = true;
    _error = null;
    _notify();
    unawaited(_audioPlayer.playAsset(_fillerChimeAsset));

    try {
      final reply = await _port.sendVoice(
        audioBase64,
        clientMessageId: clientMessageId,
      );
      _replace(pending.id, (current) => current.copyWith(
        id: reply.userTurnId,
        text: reply.transcript ?? current.text,
        status: ChatMessageStatus.sent,
      ));
      _messages.add(reply.toAssistantMessage());
      _loadState = AssistantLoadState.loaded;
      final audio = reply.audioBase64;
      if (audio != null && audio.isNotEmpty) {
        _isAwaitingVoiceReply = false;
        _isSpeaking = true;
        _notify();
        await _audioPlayer.playBase64(audio);
      }
    } on AssistantChatException catch (error) {
      _failMessage(pending.id, error.message);
    } catch (_) {
      _failMessage(pending.id, 'Could not send that recording. Please try again.');
    } finally {
      _isAwaitingVoiceReply = false;
      _isSpeaking = false;
      _notify();
    }
  }
```

- [ ] **Step 4: Run the tests again**

Run: `flutter test test/features/chat/assistant_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full test suite for this feature**

Run: `flutter test test/features/chat`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/chat/providers/assistant_provider.dart test/features/chat/assistant_provider_test.dart
git commit -m "feat(voice): add recording/playback state to AssistantProvider"
```

---

## Task 9: Flutter — mic button in `AssistantChatScreen`

**Files:**
- Modify: `lib/features/chat/screens/assistant_chat_screen.dart`
- Modify: `test/features/chat/assistant_chat_screen_test.dart`

**Interfaces:**
- Consumes: `AssistantProvider.isRecording`, `.isAwaitingVoiceReply`, `.isSpeaking`, `.startRecording()`, `.stopRecordingAndSend()` (Task 8).

- [ ] **Step 1: Write the failing widget test**

Add to `test/features/chat/assistant_chat_screen_test.dart` (it already imports `FakeAssistantChatPort` and has the `_pumpScreen` helper — extend that helper to accept audio fakes, then add tests). First, add the fake-audio imports and extend `_pumpScreen`:

```dart
import 'package:hatchaudit/services/audio/assistant_audio_player.dart';
import 'package:hatchaudit/services/audio/assistant_audio_recorder.dart';
```

```dart
const _micKey = ValueKey('assistant-mic');
```

```dart
Future<AssistantProvider> _pumpScreen(
  WidgetTester tester, {
  required FakeAssistantChatPort port,
  bool offline = false,
  bool loadOnInit = true,
  AssistantAudioRecorder? audioRecorder,
  AssistantAudioPlayer? audioPlayer,
}) async {
  var counter = 0;
  final provider = AssistantProvider(
    port: port,
    clientMessageIdFactory: () => 'cid-${++counter}',
    audioRecorder: audioRecorder,
    audioPlayer: audioPlayer,
  );
  ...
```

(leave the rest of `_pumpScreen` unchanged — this only widens its parameter list; `audioRecorder`/`audioPlayer` default to `null`, which `AssistantProvider` already treats as "use the real implementation," so every existing call site keeps working unchanged. For the new tests below, pass fakes explicitly.)

Reuse the `FakeAssistantAudioRecorder` / `FakeAssistantAudioPlayer` classes added in Task 8's `assistant_provider_test.dart` — move them into a small shared file so both test files can use them:

- [ ] **Step 1a: Extract the fakes into a shared file**

Create `test/features/chat/fake_assistant_audio.dart` with exactly the two classes (`FakeAssistantAudioRecorder`, `FakeAssistantAudioPlayer`) currently inline at the top of `assistant_provider_test.dart` (same code as written in Task 8, Step 1) plus their `dart:async`/service imports. Then in `assistant_provider_test.dart`, delete those two class definitions and their now-redundant imports, replacing with:

```dart
import 'fake_assistant_audio.dart';
```

Run: `flutter test test/features/chat/assistant_provider_test.dart`
Expected: still PASS — pure refactor, no behavior change.

- [ ] **Step 1b: Add the screen tests**

In `assistant_chat_screen_test.dart`, add:

```dart
import 'fake_assistant_audio.dart';
```

```dart
  testWidgets('tapping the mic starts recording, tapping again sends it', (
    tester,
  ) async {
    final recorder = FakeAssistantAudioRecorder();
    final player = FakeAssistantAudioPlayer();
    final port = FakeAssistantChatPort(
      nextReply: AssistantChatReply(
        conversationId: 'conv-1',
        userTurnId: 'turn-user',
        replyTurnId: 'turn-reply',
        reply: 'Hatch was 84%.',
        createdAt: DateTime.utc(2026, 8, 14, 10),
        language: 'en',
        transcript: 'What is the hatch rate?',
        audioBase64: 'YXVkaW8=',
      ),
    );
    await _pumpScreen(
      tester,
      port: port,
      audioRecorder: recorder,
      audioPlayer: player,
    );

    await tester.tap(find.byKey(_micKey));
    await tester.pump();
    expect(recorder.startCount, 1);

    await tester.tap(find.byKey(_micKey));
    await tester.pump();
    await tester.pump();

    expect(port.sentAudio, ['ZmFrZS1hdWRpbw==']);
    expect(find.text('What is the hatch rate?'), findsOneWidget);
    expect(find.text('Hatch was 84%.'), findsOneWidget);
  });

  testWidgets('mic button is disabled while offline', (tester) async {
    await _pumpScreen(
      tester,
      port: FakeAssistantChatPort(),
      offline: true,
      audioRecorder: FakeAssistantAudioRecorder(),
      audioPlayer: FakeAssistantAudioPlayer(),
    );

    final button = tester.widget<IconButton>(find.byKey(_micKey));
    expect(button.onPressed, isNull);
  });
```

- [ ] **Step 2: Run to see it fail**

Run: `flutter test test/features/chat/assistant_chat_screen_test.dart`
Expected: FAIL — no widget with key `assistant-mic`.

- [ ] **Step 3: Add the mic button to `_AssistantComposer`**

In `lib/features/chat/screens/assistant_chat_screen.dart`, replace the `_AssistantComposer` class:

```dart
class _AssistantComposer extends StatelessWidget {
  const _AssistantComposer({
    required this.controller,
    required this.enabled,
    required this.isSending,
    required this.onSend,
    required this.isRecording,
    required this.isVoiceBusy,
    required this.onMicTap,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isSending;
  final VoidCallback onSend;
  final bool isRecording;
  final bool isVoiceBusy;
  final VoidCallback onMicTap;

  @override
  Widget build(BuildContext context) {
    final canType = enabled && !isSending && !isRecording && !isVoiceBusy;
    final canRecord = enabled && !isSending && !isVoiceBusy;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderDefault)),
      ),
      padding: const EdgeInsets.all(AppSizes.spaceSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('assistant-input'),
              controller: controller,
              enabled: canType,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: enabled
                    ? 'Ask the assistant'
                    : 'Unavailable while offline',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: AppSizes.spaceSm),
          IconButton(
            key: const ValueKey('assistant-mic'),
            tooltip: isRecording ? 'Stop recording' : 'Ask by voice',
            icon: Icon(isRecording ? Icons.stop_circle : Icons.mic),
            color: isRecording ? AppColors.statusError : AppColors.primary,
            onPressed: canRecord ? onMicTap : null,
          ),
          const SizedBox(width: AppSizes.spaceSm),
          IconButton(
            key: const ValueKey('assistant-send'),
            tooltip: 'Send message',
            icon: const Icon(Icons.send),
            color: AppColors.primary,
            onPressed: canType ? onSend : null,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Wire it up in `_AssistantChatViewState`**

Add the handler method next to `_send`:

```dart
  Future<void> _toggleMic() async {
    final provider = context.read<AssistantProvider>();
    if (provider.isRecording) {
      await provider.stopRecordingAndSend();
    } else {
      await provider.startRecording();
    }
  }
```

In `build`, update the thinking-indicator condition and the `_AssistantComposer` call:

```dart
            Expanded(child: _buildBody(provider)),
            if (provider.isSending || provider.isAwaitingVoiceReply)
              const _AssistantThinkingIndicator(),
            _AssistantComposer(
              controller: _input,
              enabled: !isOffline,
              isSending: provider.isSending,
              onSend: _send,
              isRecording: provider.isRecording,
              isVoiceBusy: provider.isAwaitingVoiceReply || provider.isSpeaking,
              onMicTap: _toggleMic,
            ),
```

- [ ] **Step 5: Run the tests again**

Run: `flutter test test/features/chat/assistant_chat_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Run the full test suite**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 7: Analyze**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 8: Commit**

```bash
git add lib/features/chat/screens/assistant_chat_screen.dart test/features/chat/assistant_chat_screen_test.dart test/features/chat/fake_assistant_audio.dart test/features/chat/assistant_provider_test.dart
git commit -m "feat(voice): add mic button to the assistant composer"
```

---

## Task 10: Manual verification in the browser preview / simulator

**Files:** none (verification only).

- [ ] **Step 1: Confirm the secret is set**

This cannot be scripted from the repo — tell the user to add the `OPENAI_VOICE_KEY` secret under Supabase → Edge Functions → Secrets before this task, if not already done. Voice requests 502 with `agent_unavailable` until it's set; typed chat is unaffected either way.

- [ ] **Step 2: Deploy the function**

Run: `supabase functions deploy app-hatchery-agent`
Expected: deploy succeeds.

- [ ] **Step 3: Run the app and exercise the flow**

Run the app on a simulator/device (voice recording needs a real mic — the Flutter web preview cannot exercise this). Open the assistant chat, tap the mic, ask a short question, confirm:
- The chime plays immediately after tapping stop.
- A "thinking" indicator shows while waiting.
- The transcript appears as a user bubble, matching what was asked.
- The reply appears as an assistant bubble and its audio auto-plays.
- Repeat once in Arabic to confirm no noticeable accuracy gap (per the plan's "done when" criterion).

- [ ] **Step 4: Confirm no regression in typed chat**

Send a typed message in the same conversation; confirm it still works exactly as before (no audio requested, no `audioBase64` sent).

---

## Task 11: Docs

**Files:**
- Modify: `docs/LIVING_SPEC.md`
- Modify: `docs/CHANGELOG.md`

- [ ] **Step 1: Update `docs/LIVING_SPEC.md`**

Find the section describing the in-app assistant chat / `app-hatchery-agent` (search for `app-hatchery-agent` or `AssistantChatScreen`). Add a subsection describing the voice capability: the phone records and plays only; the server transcribes via Whisper, runs the transcript through the existing agent brain unchanged, then synthesizes a spoken reply via TTS; `OPENAI_VOICE_KEY` is a separate secret from the text-brain's `OPENAI_API_KEY`; voice turns are stored with `text` = transcript, identical to typed turns; TTS failure degrades to a text-only reply rather than failing the turn.

- [ ] **Step 2: Add a `docs/CHANGELOG.md` entry**

Add at the top (newest first), dated 2026-08-14:

```markdown
- 2026-08-14: Added voice input/output to the in-app assistant chat. The
  phone records and plays audio only; `app-hatchery-agent` transcribes via
  OpenAI Whisper, runs the transcript through the existing unmodified agent
  brain, then synthesizes the reply via OpenAI TTS. Uses a new
  `OPENAI_VOICE_KEY` secret, separate from the brain's `OPENAI_API_KEY`.
```

- [ ] **Step 3: Commit**

```bash
git add docs/LIVING_SPEC.md docs/CHANGELOG.md
git commit -m "docs: record voice chat in the living spec and changelog"
```

---

## Self-Review Notes

- **Spec coverage:** every section of `2026-08-14-assistant-voice-chat-design.md` maps to a task — loop (Tasks 1–2), secrets (Global Constraints + Task 10), server (Tasks 1–3), phone (Tasks 4–9), testing (Tasks 3, 7, 8, 9), docs (Task 11).
- **Type consistency checked:** `AssistantChatReply.transcript`/`.audioBase64`, `AssistantChatPort.sendVoice`, `AssistantAudioRecorder`/`AssistantAudioPlayer` method names and signatures are identical everywhere they're declared vs. consumed across Tasks 6–9.
- **One deliberate deviation from the design doc**, called out inline in Task 2 Step 5: the "could not understand the audio" failure returns 502 `agent_unavailable` instead of 400 `invalid_request`, since it's a transcription-quality problem, not a malformed request — the client's existing error-message mapping already has better copy for that status/code.
