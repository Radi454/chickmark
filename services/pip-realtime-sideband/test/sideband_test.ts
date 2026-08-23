import { assert, assertEquals } from '@std/assert'
import {
  READINESS_PRECONDITIONS,
  ReadinessGate,
  type ReadinessPrecondition,
  SidebandSession,
} from '../src/sideband.ts'
import { LeaseKeeper } from '../src/lease.ts'
import { testConfig } from '../src/config.ts'
import {
  buildSessionUpdate,
  INTAKE_STAGED_TOOL_NAMES,
  partitionToolCatalogue,
  type RealtimeToolDefinition,
} from '../src/session_config.ts'
import type { ToolExecutor } from '../src/claims.ts'
import { captureLogs, FakeClock, FakeSidebandSocket, FakeStore } from './fakes.ts'
import type { ClientNotice } from '../src/sideband.ts'
import type { TurnInsert } from '../src/store.ts'

const DEFAULT_TOOLS: readonly RealtimeToolDefinition[] = [{
  type: 'function',
  name: 'lookup_flock',
  description: 'Look up a flock',
  parameters: { type: 'object', properties: {} },
}]

async function build(
  options: {
    executor?: ToolExecutor
    /** Overrides the default single-tool ('lookup_flock') catalogue. */
    tools?: readonly RealtimeToolDefinition[]
    /** Overrides the default single-executor map keyed by tool name. Needed
     * whenever `tools` names more than 'lookup_flock'. */
    executors?: Record<string, ToolExecutor>
    ledger?: 'sideband' | 'broker'
    contextInjectionTimeoutMs?: number
    intakeUpgradeAckTimeoutMs?: number
  } = {},
) {
  const store = new FakeStore()
  const clock = new FakeClock()
  const socket = new FakeSidebandSocket()
  const lease = new LeaseKeeper({
    store,
    owner: 'worker_a',
    leaseSeconds: 30,
    heartbeatSeconds: 10,
    now: clock.now,
    setTimer: () => 0,
    clearTimer: () => {},
  })
  await lease.claim('sess_1', 1)
  const notices: ClientNotice[] = []
  const executors = options.executors
    ? new Map(Object.entries(options.executors))
    : new Map([[
      'lookup_flock',
      options.executor ??
        (() => Promise.resolve({ status: 'succeeded' as const, result: { ok: true } })),
    ]])
  const session = new SidebandSession({
    config: testConfig(),
    store,
    socket,
    lease,
    session: (await store.loadSession('sess_1'))!,
    generation: 1,
    leaseOwner: 'worker_a',
    tools: options.tools ?? DEFAULT_TOOLS,
    ownership: {
      ledger: options.ledger ?? 'sideband',
      executors,
    },
    notifyClient: (notice) => notices.push(notice),
    now: clock.now,
    instructions: 'You are ChickMark.',
    contextInjectionTimeoutMs: options.contextInjectionTimeoutMs,
    intakeUpgradeAckTimeoutMs: options.intakeUpgradeAckTimeoutMs,
  })
  // Provider events are fed straight to the handler: the fake socket is used for
  // asserting what the sideband SENT, not for round-tripping what it receives.
  const feed = (event: Record<string, unknown>) => session.handleEvent(event)
  return { store, clock, socket, lease, session, notices, feed }
}

/** A beat of real time, enough for every queued microtask (FakeStore round
 * trips, log-line promises) to drain before the next assertion — the same
 * idiom already used below for `session_config.sent`'s off-path log line. */
function tick(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0))
}

/** Marks every precondition except the ones named — a finer-grained sibling
 * of markAllButConfig, for tests that need to control 'contextInjected'
 * separately from 'configAcknowledged'. */
function markAllExcept(
  gate: ReadinessGate,
  ...excluded: readonly ReadinessPrecondition[]
): void {
  for (const precondition of READINESS_PRECONDITIONS) {
    if (!excluded.includes(precondition)) gate.mark(precondition)
  }
}

/**
 * Seeds a finalized, non-empty durable turn on the fake store's default
 * conversation ('conv_1', contextEpoch 1) — the pair `build()`'s session is
 * pinned to — so `loadRecentTurns` picks it up without further wiring.
 */
function seedTurn(
  store: FakeStore,
  overrides: {
    conversationSeq: number
    direction: 'inbound' | 'outbound'
    text: string
  },
): void {
  const turn: TurnInsert = {
    id: `turn_${overrides.conversationSeq}`,
    conversationId: 'conv_1',
    contextEpoch: 1,
    direction: overrides.direction,
    conversationSeq: overrides.conversationSeq,
    turnIndex: overrides.conversationSeq,
    text: overrides.text,
    language: 'en',
    sourceChannel: 'app_text',
    completionStatus: 'finalized',
    realtimeSessionId: 'sess_1',
    realtimeGeneration: 1,
    providerItemId: null,
    authorizationFingerprint: 'admin:all',
    customerId: null,
    model: null,
    createdAt: '2026-08-16T09:00:00.000Z',
    finalizedAt: '2026-08-16T09:00:00.000Z',
    interruptedAt: null,
  }
  store.addTurn(turn)
}

/** Everything except the configuration ack, which only `session.updated` supplies. */
function markAllButConfig(gate: ReadinessGate): void {
  for (const precondition of READINESS_PRECONDITIONS) {
    if (precondition !== 'configAcknowledged') gate.mark(precondition)
  }
}

Deno.test('live-transcribe keeps its languages/delay knobs; other models never see them', () => {
  const payload = buildSessionUpdate({
    config: testConfig({ transcriptionModel: 'gpt-live-transcribe' }),
    tools: [{ type: 'function', name: 't', description: 'd', parameters: {} }],
    instructions: 'x',
  }) as Record<string, Record<string, never>>
  const session = payload.session as unknown as Record<string, unknown>
  const audio = session.audio as Record<string, Record<string, unknown>>
  const transcription = audio.input.transcription as Record<string, unknown>
  assertEquals(transcription.languages, ['ar', 'en'])
  assertEquals(transcription.delay, 'low')
  // Singular `language` is unprobed in combination with gpt-live-transcribe's
  // own languages/delay shape and must never be sent alongside it.
  assert(!('language' in transcription))
})

Deno.test('transcriptionLanguage "" omits the singular language field entirely', () => {
  const payload = buildSessionUpdate({
    config: testConfig({ transcriptionLanguage: '' }),
    tools: [{ type: 'function', name: 't', description: 'd', parameters: {} }],
    instructions: 'x',
  }) as Record<string, Record<string, never>>
  const session = payload.session as unknown as Record<string, unknown>
  const audio = session.audio as Record<string, Record<string, unknown>>
  const transcription = audio.input.transcription as Record<string, unknown>
  // Assert the key is ABSENT, not merely undefined-valued.
  assert(!('language' in transcription))
})

Deno.test('session.update carries the verified shape', () => {
  const instructions = 'You are ChickMark.'
  const payload = buildSessionUpdate({
    config: testConfig(),
    tools: [{ type: 'function', name: 't', description: 'd', parameters: {} }],
    instructions,
  }) as Record<string, Record<string, never>>
  const session = payload.session as unknown as Record<string, unknown>
  assertEquals(payload.type as unknown, 'session.update')
  assertEquals(session.type, 'realtime')
  assertEquals(session.output_modalities, ['audio'])
  assertEquals(session.tool_choice, 'auto')
  assertEquals(session.instructions, instructions)
  // Backstop ceiling — see src/session_config.ts for the measured
  // justification (tools/probe_output_tokens.ts, 2026-08-19).
  assertEquals(session.max_output_tokens, 1536)

  const audio = session.audio as Record<string, Record<string, unknown>>
  const transcription = audio.input.transcription as Record<string, unknown>
  // `languages` and `delay` are gpt-live-transcribe-only knobs; the provider
  // rejects the whole session.update if they reach any other transcription
  // model (named live 2026-08-17). The default model is
  // gpt-4o-mini-transcribe, so the default payload must NOT carry them.
  assertEquals(transcription.model, 'gpt-4o-mini-transcribe')
  assertEquals(transcription.delay, undefined)
  assertEquals(transcription.languages, undefined)
  // Singular `language` IS sent for the default model/default config
  // (verified accepted, tools/probe_session_knobs.ts, 2026-08-19).
  assertEquals(transcription.language, 'ar')
  // The bilingual prompt carries both the Arabic framing and the retained
  // English hatchery term list.
  assert((transcription.prompt as string).includes('hatchery'))
  assert(/[؀-ۿ]/.test(transcription.prompt as string))
  const turnDetection = audio.input.turn_detection as Record<string, unknown>
  // Default config is semantic_vad (verified accepted for
  // gpt-realtime-2.1-mini, tools/probe_turn_detection.ts, 2026-08-18).
  assertEquals(turnDetection.type, 'semantic_vad')
  assertEquals(turnDetection.eagerness, 'low')
  assertEquals(turnDetection.interrupt_response, true)
  assertEquals(turnDetection.create_response, true)

  // Tool definitions are FLAT, not the nested Chat Completions shape.
  const tools = session.tools as Record<string, unknown>[]
  assertEquals(tools[0].type, 'function')
  assertEquals(tools[0].name, 't')
  assertEquals(tools[0].function, undefined)
})

Deno.test('turn_detection: semantic_vad carries eagerness, not the server_vad knobs', () => {
  const payload = buildSessionUpdate({
    config: testConfig({ turnDetection: 'semantic_vad', vadEagerness: 'auto' }),
    tools: [{ type: 'function', name: 't', description: 'd', parameters: {} }],
    instructions: 'x',
  }) as Record<string, Record<string, never>>
  const session = payload.session as unknown as Record<string, unknown>
  const audio = session.audio as Record<string, Record<string, unknown>>
  const turnDetection = audio.input.turn_detection as Record<string, unknown>
  assertEquals(turnDetection, {
    type: 'semantic_vad',
    eagerness: 'auto',
    create_response: true,
    interrupt_response: true,
  })
})

Deno.test('turn_detection: server_vad uses the configured silence duration', () => {
  const payload = buildSessionUpdate({
    config: testConfig({ turnDetection: 'server_vad', vadSilenceMs: 1200 }),
    tools: [{ type: 'function', name: 't', description: 'd', parameters: {} }],
    instructions: 'x',
  }) as Record<string, Record<string, never>>
  const session = payload.session as unknown as Record<string, unknown>
  const audio = session.audio as Record<string, Record<string, unknown>>
  const turnDetection = audio.input.turn_detection as Record<string, unknown>
  assertEquals(turnDetection, {
    type: 'server_vad',
    threshold: 0.5,
    prefix_padding_ms: 300,
    silence_duration_ms: 1200,
    create_response: true,
    interrupt_response: true,
  })
})

// ---------------------------------------------------------------------------
// Intake tool catalogue staging (partitionToolCatalogue).
// ---------------------------------------------------------------------------

function tool(name: string): RealtimeToolDefinition {
  return { type: 'function', name, description: 'd', parameters: { type: 'object' } }
}

Deno.test('partitionToolCatalogue: full is all, unchanged, in the original order', () => {
  const all = [tool('a'), tool('propose_intake'), tool('start_intake'), tool('b')]
  const { full } = partitionToolCatalogue(all)
  assertEquals(full, all)
})

Deno.test('partitionToolCatalogue: core is all minus the staged names, order preserved', () => {
  const all = [
    tool('get_user_scope'),
    tool('propose_intake'),
    tool('start_intake'),
    tool('record_station_values'),
    tool('get_breed_benchmark'),
    tool('cancel_intake'),
  ]
  const { core } = partitionToolCatalogue(all)
  assertEquals(
    core.map((t) => t.name),
    ['get_user_scope', 'propose_intake', 'get_breed_benchmark'],
  )
})

Deno.test('partitionToolCatalogue: core is a pure subset of full — no renaming, no reshaping', () => {
  const all = [tool('propose_intake'), tool('start_intake'), tool('get_user_scope')]
  const { core, full } = partitionToolCatalogue(all)
  for (const entry of core) {
    assert(
      full.includes(entry),
      `${entry.name} in core must be the SAME object from full`,
    )
  }
})

Deno.test('partitionToolCatalogue: a staged name absent from the deployed catalogue is not an error', () => {
  // Simulates an older or newer deployed contract that does not (yet, or any
  // longer) carry every name in INTAKE_STAGED_TOOL_NAMES.
  const all = [tool('propose_intake'), tool('get_user_scope')]
  const { core, full } = partitionToolCatalogue(all)
  assertEquals(core.map((t) => t.name), ['propose_intake', 'get_user_scope'])
  assertEquals(full.map((t) => t.name), ['propose_intake', 'get_user_scope'])
})

Deno.test('partitionToolCatalogue: core union the staged names equals full, as a set', () => {
  const all = [
    tool('get_user_scope'),
    tool('propose_intake'),
    tool('start_intake'),
    tool('record_station_values'),
    tool('get_intake_status'),
    tool('create_station_summary'),
    tool('confirm_station_summary'),
    tool('submit_station_for_review'),
    tool('pause_intake'),
    tool('resume_intake'),
    tool('cancel_intake'),
    tool('list_legacy_draft_questions'),
  ]
  const { core, full } = partitionToolCatalogue(all)
  const reunited = new Set([...core.map((t) => t.name), ...INTAKE_STAGED_TOOL_NAMES])
  assertEquals(reunited, new Set(full.map((t) => t.name)))
})

Deno.test('READY is withheld while ANY precondition is missing', async () => {
  const { session, notices } = await build()
  for (const missing of READINESS_PRECONDITIONS) {
    const gate = new ReadinessGate()
    for (const precondition of READINESS_PRECONDITIONS) {
      if (precondition !== missing) gate.mark(precondition)
    }
    assertEquals(gate.satisfied, false)
    assertEquals(gate.missing, [missing])
  }
  // The live session's gate starts empty, so nothing has been announced.
  assertEquals(session.gate.satisfied, false)
  assertEquals(notices.length, 0)
})

Deno.test('READY waits for session.updated, not merely for the update being sent', async () => {
  const { feed, session, socket, notices } = await build()
  markAllButConfig(session.gate)

  const configured = session.attachAndConfigure()
  assertEquals(socket.sentOfType('session.update').length, 1)
  // The config has been sent but not acknowledged: still not ready.
  await session.maybeAnnounceReady()
  assertEquals(notices.length, 0)

  await feed({ type: 'session.updated' })
  await configured
  assertEquals(notices.map((notice) => notice.type), ['ready'])
})

Deno.test('a turn_detection rejection before ack resends once with server_vad forced', async () => {
  const { feed, session, socket, notices } = await build()
  markAllButConfig(session.gate)

  const configured = session.attachAndConfigure()
  assertEquals(socket.sentOfType('session.update').length, 1)
  const first = socket.sentOfType('session.update')[0].session as Record<string, unknown>
  const firstAudio = first.audio as Record<string, Record<string, unknown>>
  assertEquals(
    (firstAudio.input.turn_detection as Record<string, unknown>).type,
    'semantic_vad',
  )

  // The provider rejects the whole session.update, naming the field.
  await feed({
    type: 'error',
    error: {
      code: 'invalid_value',
      param: 'session.audio.input.turn_detection.type',
      message: 'x',
    },
  })

  // Exactly one fallback resend, forcing server_vad.
  assertEquals(socket.sentOfType('session.update').length, 2)
  const fallback = socket.sentOfType('session.update')[1].session as Record<
    string,
    unknown
  >
  const fallbackAudio = fallback.audio as Record<string, Record<string, unknown>>
  assertEquals(
    (fallbackAudio.input.turn_detection as Record<string, unknown>).type,
    'server_vad',
  )

  // A second identical rejection does NOT trigger a second resend (one-shot).
  await feed({
    type: 'error',
    error: {
      code: 'invalid_value',
      param: 'session.audio.input.turn_detection.type',
      message: 'x',
    },
  })
  assertEquals(socket.sentOfType('session.update').length, 2)

  // The session still reaches READY once the fallback is acked.
  await feed({ type: 'session.updated' })
  await configured
  assertEquals(notices.map((notice) => notice.type), ['ready'])
})

Deno.test('every config send and ack is fingerprinted: seq, sha, match verdict, no policy text', async () => {
  const { setLogSink, resetLogSink } = await import('../src/log.ts')
  const { sha256Hex } = await import('../src/sideband.ts')
  const lines: Record<string, unknown>[] = []
  setLogSink((line) => lines.push(JSON.parse(line)))
  try {
    const { feed, session } = await build()
    markAllButConfig(session.gate)
    const configured = session.attachAndConfigure()
    // The provider echoes the EFFECTIVE session; here it echoes what was sent.
    await feed({
      type: 'session.updated',
      session: {
        instructions: 'You are ChickMark.',
        model: 'gpt-realtime-2.1-mini',
        tools: [{}],
      },
    })
    await configured
    // The sent-line resolves off-path; give its microtask a beat.
    await new Promise((resolve) => setTimeout(resolve, 0))

    const expectedSha = await sha256Hex('You are ChickMark.')
    const sent = lines.find((l) => l.event === 'session_config.sent')
    assert(sent, 'session_config.sent must be logged')
    assertEquals(sent.seq, 1)
    assertEquals(sent.source, 'initial')
    assertEquals(sent.instructions_sha256, expectedSha)
    assertEquals(sent.instructions_chars, 'You are ChickMark.'.length)
    assertEquals(sent.turn_detection, 'semantic_vad')
    assertEquals(sent.eagerness, 'low')

    const acked = lines.find((l) => l.event === 'session_config.acked')
    assert(acked, 'session_config.acked must be logged')
    assertEquals(acked.ack_seq, 1)
    assertEquals(acked.sent_seq, 1)
    assertEquals(acked.applied_instructions_sha256, expectedSha)
    assertEquals(acked.instructions_match, true)
    assertEquals(acked.applied_model, 'gpt-realtime-2.1-mini')
    assertEquals(acked.applied_tool_count, 1)

    // The policy text itself must never appear in any log line.
    for (const line of lines) {
      assert(!JSON.stringify(line).includes('You are ChickMark.'))
    }
  } finally {
    resetLogSink()
  }
})

Deno.test('an error unrelated to turn_detection does not trigger the fallback', async () => {
  const { feed, session, socket } = await build()
  markAllButConfig(session.gate)
  session.attachAndConfigure()
  assertEquals(socket.sentOfType('session.update').length, 1)

  await feed({
    type: 'error',
    error: { code: 'invalid_value', param: 'session.audio.output.voice', message: 'x' },
  })
  assertEquals(socket.sentOfType('session.update').length, 1)
})

Deno.test('a turn_detection error AFTER config is already acknowledged does not resend', async () => {
  const { feed, session, socket, notices } = await build()
  markAllButConfig(session.gate)
  const configured = session.attachAndConfigure()
  await feed({ type: 'session.updated' })
  await configured
  assertEquals(notices.map((notice) => notice.type), ['ready'])
  assertEquals(socket.sentOfType('session.update').length, 1)

  await feed({
    type: 'error',
    error: {
      code: 'invalid_value',
      param: 'session.audio.input.turn_detection.type',
      message: 'x',
    },
  })
  assertEquals(socket.sentOfType('session.update').length, 1)
})

Deno.test('READY is announced exactly once and marks the call active', async () => {
  const { feed, session, notices, store } = await build()
  markAllButConfig(session.gate)
  const configured = session.attachAndConfigure()
  await feed({ type: 'session.updated' })
  await configured

  await session.maybeAnnounceReady()
  await session.maybeAnnounceReady()
  assertEquals(notices.filter((notice) => notice.type === 'ready').length, 1)
  assertEquals(store.calls.get('sess_1:1')?.setupState, 'active')
  assertEquals((await store.loadSession('sess_1'))!.state, 'active')
})

Deno.test('a finalized user transcript becomes a durable turn via the allocator', async () => {
  const { feed, store } = await build()
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({
    type: 'conversation.item.input_audio_transcription.completed',
    item_id: 'item_1',
    transcript: 'ما هي نسبة الفقس؟',
  })

  assertEquals(store.turns.length, 1)
  const turn = store.turns[0]
  assertEquals(turn.direction, 'inbound')
  assertEquals(turn.sourceChannel, 'realtime_voice')
  assertEquals(turn.completionStatus, 'finalized')
  assertEquals(turn.language, 'ar')
  assertEquals(turn.providerItemId, 'item_1')
  assertEquals(turn.conversationSeq, 1)
  assertEquals(store.allocated.length, 1)
})

Deno.test('failed transcription is recorded as unavailable with no invented content', async () => {
  const { feed, store } = await build()
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({
    type: 'conversation.item.input_audio_transcription.failed',
    item_id: 'item_1',
  })

  assertEquals(store.turns.length, 1)
  assertEquals(store.turns[0].completionStatus, 'unavailable')
  assertEquals(store.turns[0].text, '')
})

Deno.test('deltas are never persisted; only the finalized assistant text is', async () => {
  const { feed, store } = await build()
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  await feed({
    type: 'response.output_item.added',
    response_id: 'resp_1',
    item: { id: 'out_1', type: 'message' },
  })
  await feed({
    type: 'response.output_audio_transcript.delta',
    response_id: 'resp_1',
    item_id: 'out_1',
    delta: 'Hatch rate is ',
  })
  // Nothing durable yet.
  assertEquals(store.turns.length, 0)

  await feed({
    type: 'response.output_audio_transcript.done',
    response_id: 'resp_1',
    item_id: 'out_1',
    transcript: 'Hatch rate is 84 percent.',
  })
  await feed({ type: 'response.done', response: { id: 'resp_1', status: 'completed' } })

  assertEquals(store.turns.length, 1)
  assertEquals(store.turns[0].direction, 'outbound')
  assertEquals(store.turns[0].text, 'Hatch rate is 84 percent.')
  assertEquals(store.turns[0].completionStatus, 'finalized')
})

Deno.test('an interrupted response stores only what was actually said', async () => {
  const { feed, store } = await build()
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  await feed({
    type: 'response.output_item.added',
    response_id: 'resp_1',
    item: { id: 'out_1', type: 'message' },
  })
  await feed({
    type: 'response.output_audio_transcript.delta',
    response_id: 'resp_1',
    item_id: 'out_1',
    delta: 'The setter temperature is',
  })
  await feed({ type: 'response.done', response: { id: 'resp_1', status: 'cancelled' } })

  assertEquals(store.turns.length, 1)
  assertEquals(store.turns[0].completionStatus, 'interrupted')
  assertEquals(store.turns[0].text, 'The setter temperature is')
  assert(store.turns[0].interruptedAt !== null)
})

Deno.test('outbound turn indexes are allocated independently of inbound ones', async () => {
  const { feed, store } = await build()
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({
    type: 'conversation.item.input_audio_transcription.completed',
    item_id: 'item_1',
    transcript: 'question one',
  })
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  await feed({
    type: 'response.output_item.added',
    response_id: 'resp_1',
    item: { id: 'out_1', type: 'message' },
  })
  await feed({
    type: 'response.output_audio_transcript.done',
    response_id: 'resp_1',
    item_id: 'out_1',
    transcript: 'answer one',
  })
  await feed({ type: 'response.done', response: { id: 'resp_1', status: 'completed' } })

  assertEquals(store.turns.map((turn) => turn.conversationSeq), [1, 2])
  assertEquals(store.turns.map((turn) => turn.turnIndex), [1, 1])
  assertEquals(store.turns.map((turn) => turn.direction), ['inbound', 'outbound'])
})

Deno.test('every persisted turn bumps the parent conversation updated_at', async () => {
  const { feed, store } = await build()
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({
    type: 'conversation.item.input_audio_transcription.completed',
    item_id: 'item_1',
    transcript: 'Hello',
  })

  assertEquals(store.turns.length, 1)
  assertEquals(store.conversationTouches.length, 1)
  assertEquals(store.conversationTouches[0].conversationId, 'conv_1')
})

Deno.test(
  'a conversation-touch failure after a turn write is non-fatal and never logs turn text',
  async () => {
    const { setLogSink, resetLogSink } = await import('../src/log.ts')
    const lines: Record<string, unknown>[] = []
    setLogSink((line) => lines.push(JSON.parse(line)))
    try {
      const { feed, store } = await build()
      store.failTouchConversation = true
      await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
      await feed({
        type: 'conversation.item.input_audio_transcription.completed',
        item_id: 'item_1',
        transcript: 'a secret transcript that must never reach the logs',
      })

      // The turn itself is still stored durably despite the touch failing.
      assertEquals(store.turns.length, 1)
      assertEquals(store.conversationTouches.length, 0)
      const warned = lines.find((line) => line.event === 'conversation.touch_failed')
      assert(warned, 'conversation.touch_failed must be logged')
      for (const line of lines) {
        assert(!JSON.stringify(line).includes('secret transcript'))
      }
    } finally {
      resetLogSink()
    }
  },
)

Deno.test('a tool call is executed and answered, and the claim is back-filled on transcript', async () => {
  const executed: unknown[] = []
  const { feed, socket, store } = await build({
    executor: (args) => {
      executed.push(args)
      return Promise.resolve({ status: 'succeeded', result: { hatch_rate: 84 } })
    },
  })

  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  await feed({
    type: 'response.output_item.added',
    response_id: 'resp_1',
    item: { id: 'fc_1', type: 'function_call' },
  })
  await feed({
    type: 'response.output_item.done',
    response_id: 'resp_1',
    item: {
      type: 'function_call',
      call_id: 'call_1',
      name: 'lookup_flock',
      arguments: '{"flock_id":"flock_1"}',
    },
  })

  assertEquals(executed, [{ flock_id: 'flock_1' }])
  const outputs = socket.sentOfType('conversation.item.create')
  assertEquals(outputs.length, 1)
  const item = outputs[0].item as Record<string, unknown>
  assertEquals(item.type, 'function_call_output')
  assertEquals(item.call_id, 'call_1')
  // A real result, not a placeholder.
  assertEquals(JSON.parse(item.output as string), { hatch_rate: 84 })
  assertEquals(socket.sentOfType('response.create').length, 1)

  // The evidence exists before any turn does.
  assertEquals(store.toolEvents.length, 1)
  assertEquals(store.toolEvents[0].conversationTurnId, null)
  assertEquals(store.turns.length, 0)

  await feed({
    type: 'conversation.item.input_audio_transcription.completed',
    item_id: 'item_1',
    transcript: 'what is the hatch rate',
  })
  const claim = await store.loadToolClaim('sess_1', 1, 'call_1')
  assertEquals(claim?.inboundTurnId, store.turns[0].id)
  assertEquals(store.toolEvents[0].conversationTurnId, null)
})

Deno.test('a response carrying BOTH audio and a tool call handles each', async () => {
  const { feed, store } = await build()
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  await feed({
    type: 'response.output_item.added',
    response_id: 'resp_1',
    item: { id: 'out_1', type: 'message' },
  })
  await feed({
    type: 'response.output_item.added',
    response_id: 'resp_1',
    item: { id: 'fc_1', type: 'function_call' },
  })
  await feed({
    type: 'response.output_audio_transcript.done',
    response_id: 'resp_1',
    item_id: 'out_1',
    transcript: 'Let me check that.',
  })
  await feed({
    type: 'response.output_item.done',
    response_id: 'resp_1',
    item: {
      type: 'function_call',
      call_id: 'call_1',
      name: 'lookup_flock',
      arguments: '{}',
    },
  })
  await feed({ type: 'response.done', response: { id: 'resp_1', status: 'completed' } })

  assertEquals(store.toolEvents.length, 1)
  assertEquals(store.turns.length, 1)
  assertEquals(store.turns[0].text, 'Let me check that.')
})

Deno.test('the interaction cap survives a tool continuation chain', async () => {
  const { feed, socket, store } = await build()
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({ type: 'response.created', response: { id: 'resp_1' } })

  for (let i = 1; i <= 5; i++) {
    await feed({
      type: 'response.output_item.done',
      response_id: 'resp_1',
      item: {
        type: 'function_call',
        call_id: `call_${i}`,
        name: 'lookup_flock',
        arguments: '{}',
      },
    })
    // Each output opens a continuation response in the same interaction.
    await feed({ type: 'response.created', response: { id: `resp_cont_${i}` } })
  }
  await feed({
    type: 'response.output_item.done',
    response_id: 'resp_cont_5',
    item: {
      type: 'function_call',
      call_id: 'call_6',
      name: 'lookup_flock',
      arguments: '{}',
    },
  })

  assertEquals(store.toolEvents.length, 5)
  assertEquals(await store.loadToolClaim('sess_1', 1, 'call_6'), null)
  // The model is still answered — with a refusal.
  const outputs = socket.sentOfType('conversation.item.create')
  assertEquals(outputs.length, 6)
  const last = JSON.parse((outputs[5].item as Record<string, string>).output)
  assertEquals(last.error, 'tool_limit_reached')
})

// ---------------------------------------------------------------------------
// Per-response token telemetry.
// ---------------------------------------------------------------------------

const REALISTIC_USAGE = {
  total_tokens: 5516,
  input_tokens: 5453,
  output_tokens: 63,
  input_token_details: {
    text_tokens: 5453,
    audio_tokens: 0,
    image_tokens: 0,
    cached_tokens: 4864,
    cached_tokens_details: { text_tokens: 4864, audio_tokens: 0 },
  },
  output_token_details: { text_tokens: 29, audio_tokens: 34 },
}

Deno.test('response.done persists exactly one usage row with the right values', async () => {
  const { feed, store } = await build()
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  await feed({
    type: 'response.done',
    response: { id: 'resp_1', status: 'completed', usage: REALISTIC_USAGE },
  })

  assertEquals(store.responseUsage.size, 1)
  const row = store.responseUsage.get('sess_1:resp_1')
  assertEquals(row?.sessionId, 'sess_1')
  assertEquals(row?.responseId, 'resp_1')
  assertEquals(row?.generation, 1)
  assertEquals(row?.model, testConfig().model)
  assertEquals(row?.status, 'completed')
  assertEquals(row?.totalTokens, 5516)
  assertEquals(row?.inputTokens, 5453)
  assertEquals(row?.cachedInputTokens, 4864)
  assertEquals(row?.uncachedInputTokens, 589)
  assertEquals(row?.outputTokens, 63)
  assertEquals(row?.outputTextTokens, 29)
  assertEquals(row?.outputAudioTokens, 34)
  assertEquals(row?.followedToolCall, false)
  assertEquals(row?.toolNames, [])
  assertEquals(row?.ownerProfileId, 'profile_1')
  assertEquals(row?.tenantId, 'tenant_1')
})

Deno.test('a response.done with no usable response id writes nothing and does not throw', async () => {
  const { feed, store } = await build()
  await feed({ type: 'response.done', response: { status: 'completed' } })
  assertEquals(store.responseUsage.size, 0)
})

Deno.test(
  'persisting usage for a response the tracker never saw writes a null interactionId and does not mint an interaction',
  async () => {
    const { feed, store, session } = await build()

    // No 'response.created' (and no preceding 'input_audio_buffer.committed')
    // for 'resp_unseen' — the tracker has never heard of this response id.
    // Telemetry must not invent an interaction for it: the documented
    // contract (ResponseUsageInsert.interactionId in store.ts, and the
    // migration's column comment) is that this is null, never a synthetic id.
    assertEquals(session.tracker.interactionCount, 0)

    await feed({
      type: 'response.done',
      response: { id: 'resp_unseen', status: 'completed', usage: REALISTIC_USAGE },
    })

    assertEquals(store.responseUsage.size, 1)
    const row = store.responseUsage.get('sess_1:resp_unseen')
    assertEquals(row?.interactionId, null)

    // Reading telemetry must not be able to alter budget-tracking state: no
    // interaction was minted, and the tracker still has no attribution on
    // file for this response id (the minting `interactionForResponse` would
    // have both created one and cached it here).
    assertEquals(session.tracker.interactionCount, 0)
    assertEquals(session.tracker.lookupInteractionForResponse('resp_unseen'), null)
  },
)

Deno.test('a failed response with all-zero usage is still recorded — that IS the signal', async () => {
  const { feed, store } = await build()
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  await feed({
    type: 'response.done',
    response: {
      id: 'resp_1',
      status: 'failed',
      usage: {
        total_tokens: 0,
        input_tokens: 0,
        output_tokens: 0,
        input_token_details: {
          text_tokens: 0,
          audio_tokens: 0,
          image_tokens: 0,
          cached_tokens: 0,
          cached_tokens_details: { text_tokens: 0, audio_tokens: 0 },
        },
        output_token_details: { text_tokens: 0, audio_tokens: 0 },
      },
    },
  })

  assertEquals(store.responseUsage.size, 1)
  const row = store.responseUsage.get('sess_1:resp_1')
  assertEquals(row?.status, 'failed')
  assertEquals(row?.totalTokens, 0)
})

Deno.test('a store failure while persisting usage is logged and never propagates', async () => {
  const { feed, store } = await build()
  store.failInsertResponseUsage = true
  const { lines, restore } = captureLogs()

  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  // Must not throw despite the store rejecting.
  await feed({
    type: 'response.done',
    response: { id: 'resp_1', status: 'completed', usage: REALISTIC_USAGE },
  })
  restore()

  assertEquals(store.responseUsage.size, 0)
  // The FIRST failure in a session logs the louder, distinct event — not the
  // quieter one, which is reserved for repeats (see the next test).
  const loud = lines.map((line) => JSON.parse(line)).find((entry) =>
    entry.event === 'response_usage.persist_failed_first'
  )
  assert(loud, 'first failure must log response_usage.persist_failed_first')
  assertEquals(loud.level, 'error')
  const quiet = lines.some((line) => JSON.parse(line).event === 'response_usage.failed')
  assert(!quiet, 'the first-ever failure must not also log the quiet event')
  // Content-free: no token counts or other row content in the log line.
  for (const line of lines) {
    if (JSON.parse(line).event !== 'response_usage.persist_failed_first') continue
    assert(!line.includes('5516'))
  }
})

Deno.test(
  'a second usage-persist failure in the same session logs the quiet event, not another loud one',
  async () => {
    const { feed, store } = await build()
    store.failInsertResponseUsage = true
    const { lines, restore } = captureLogs()

    await feed({ type: 'response.created', response: { id: 'resp_1' } })
    await feed({
      type: 'response.done',
      response: { id: 'resp_1', status: 'completed', usage: REALISTIC_USAGE },
    })
    await feed({ type: 'response.created', response: { id: 'resp_2' } })
    await feed({
      type: 'response.done',
      response: { id: 'resp_2', status: 'completed', usage: REALISTIC_USAGE },
    })
    restore()

    assertEquals(store.responseUsage.size, 0)
    const entries = lines.map((line) => JSON.parse(line))
    const loudCount =
      entries.filter((entry) => entry.event === 'response_usage.persist_failed_first')
        .length
    const quietCount =
      entries.filter((entry) => entry.event === 'response_usage.failed').length
    assertEquals(loudCount, 1, 'exactly one loud event across both failures')
    assertEquals(quietCount, 1, 'the second failure logs the quiet event')
    const quiet = entries.find((entry) => entry.event === 'response_usage.failed')
    assertEquals(quiet?.level, 'error')
  },
)

Deno.test(
  'stopping a session where every usage-persist attempt failed logs the all-failed terminal event',
  async () => {
    const { feed, store, session } = await build()
    store.failInsertResponseUsage = true
    const { lines, restore } = captureLogs()

    await feed({ type: 'response.created', response: { id: 'resp_1' } })
    await feed({
      type: 'response.done',
      response: { id: 'resp_1', status: 'completed', usage: REALISTIC_USAGE },
    })
    session.stop('test_teardown')
    restore()

    const entries = lines.map((line) => JSON.parse(line))
    const terminal = entries.find((entry) => entry.event === 'response_usage.all_failed')
    assert(terminal, 'response_usage.all_failed must be logged on stop()')
    assertEquals(terminal.level, 'error')
    assertEquals(terminal.attempts, 1)
  },
)

Deno.test(
  'stopping a session where at least one usage-persist attempt succeeded does not log the all-failed event',
  async () => {
    const { feed, store, session } = await build()

    // First attempt succeeds.
    await feed({ type: 'response.created', response: { id: 'resp_1' } })
    await feed({
      type: 'response.done',
      response: { id: 'resp_1', status: 'completed', usage: REALISTIC_USAGE },
    })

    // Second attempt fails.
    store.failInsertResponseUsage = true
    await feed({ type: 'response.created', response: { id: 'resp_2' } })
    await feed({
      type: 'response.done',
      response: { id: 'resp_2', status: 'completed', usage: REALISTIC_USAGE },
    })

    const { lines, restore } = captureLogs()
    session.stop('test_teardown')
    restore()

    const terminal = lines.some((line) =>
      JSON.parse(line).event === 'response_usage.all_failed'
    )
    assert(!terminal, 'a partially-successful session must not log the all-failed event')
  },
)

Deno.test('a response following a tool call is flagged followed_tool_call with the tool name', async () => {
  const { feed, store } = await build()
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  await feed({
    type: 'response.output_item.added',
    response_id: 'resp_1',
    item: { id: 'fc_1', type: 'function_call' },
  })
  await feed({
    type: 'response.output_item.done',
    response_id: 'resp_1',
    item: {
      type: 'function_call',
      call_id: 'call_1',
      name: 'lookup_flock',
      arguments: '{}',
    },
  })
  // resp_1 is the response that PRODUCED the tool call, not one that follows
  // one — it must not be flagged.
  await feed({
    type: 'response.done',
    response: { id: 'resp_1', status: 'completed', usage: REALISTIC_USAGE },
  })

  // This is the sideband's own follow-up response, created after the
  // function_call_output was submitted.
  await feed({ type: 'response.created', response: { id: 'resp_cont_1' } })
  await feed({
    type: 'response.done',
    response: { id: 'resp_cont_1', status: 'completed', usage: REALISTIC_USAGE },
  })

  const original = store.responseUsage.get('sess_1:resp_1')
  assertEquals(original?.followedToolCall, false)
  assertEquals(original?.toolNames, [])

  const followUp = store.responseUsage.get('sess_1:resp_cont_1')
  assertEquals(followUp?.followedToolCall, true)
  assertEquals(followUp?.toolNames, ['lookup_flock'])
})

// ---------------------------------------------------------------------------
// Brokered ownership, end to end through the event stream.
// ---------------------------------------------------------------------------

/** Drive one full `function_call` through the session. */
async function feedToolCall(
  feed: (event: Record<string, unknown>) => Promise<void>,
  callId = 'call_1',
): Promise<void> {
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  await feed({
    type: 'response.output_item.added',
    response_id: 'resp_1',
    item: { id: 'fc_1', type: 'function_call' },
  })
  await feed({
    type: 'response.output_item.done',
    response_id: 'resp_1',
    item: {
      type: 'function_call',
      call_id: callId,
      name: 'lookup_flock',
      arguments: '{"flock_id":"flock_1"}',
    },
  })
}

Deno.test('brokered: the model is answered and neither ledger table is written', async () => {
  const { feed, socket, store } = await build({
    ledger: 'broker',
    executor: () => Promise.resolve({ status: 'succeeded', result: { hatch_rate: 84 } }),
  })

  await feedToolCall(feed)

  const outputs = socket.sentOfType('conversation.item.create')
  assertEquals(outputs.length, 1)
  const item = outputs[0].item as Record<string, unknown>
  assertEquals(item.type, 'function_call_output')
  assertEquals(JSON.parse(item.output as string), { hatch_rate: 84 })
  // The response chain is continued, or the user hears nothing back.
  assertEquals(socket.sentOfType('response.create').length, 1)

  // The broker wrote both rows. A second writer here would be a unique
  // violation, and the throw would have skipped the output above entirely.
  assertEquals(store.toolEvents.length, 0)
  assertEquals(store.claims.size, 0)
})

Deno.test('brokered: a broker failure answers the model and does not stop the session', async () => {
  const { feed, socket, session, store } = await build({
    ledger: 'broker',
    executor: () => Promise.reject(new TypeError('network')),
  })

  await feedToolCall(feed)

  const outputs = socket.sentOfType('conversation.item.create')
  assertEquals(outputs.length, 1)
  const item = outputs[0].item as Record<string, unknown>
  const output = JSON.parse(item.output as string) as Record<string, unknown>
  // A real error the assistant can say out loud — never an invented success.
  assertEquals(output.ok, false)
  assertEquals(output.error, 'tool_failed')
  assertEquals(socket.sentOfType('response.create').length, 1)

  // The session is still alive and still recording the conversation.
  assertEquals(session.stopped, false)
  assertEquals(store.toolEvents.length, 0)
  await feed({
    type: 'conversation.item.input_audio_transcription.completed',
    item_id: 'item_1',
    transcript: 'what is the hatch rate',
  })
  assertEquals(store.turns.length, 1)
})

Deno.test('brokered: the stamped session fingerprint reaches the executor', async () => {
  // Sent as a CLAIM for the broker to re-derive and compare — never as an
  // authority, and never anything the client supplied.
  let seen = ''
  const { feed } = await build({
    ledger: 'broker',
    executor: (_args, context) => {
      seen = context.authorizationFingerprint
      return Promise.resolve({ status: 'succeeded', result: { ok: true } })
    },
  })

  await feedToolCall(feed)

  assertEquals(seen, 'admin:all')
})

// ---------------------------------------------------------------------------
// Conversation context injection
// ---------------------------------------------------------------------------

Deno.test(
  'conversation context: recent turns are sent after session.update, oldest-first with correct role/content-type',
  async () => {
    const { store, session, socket, feed } = await build()
    seedTurn(store, { conversationSeq: 1, direction: 'inbound', text: 'Hello' })
    seedTurn(store, { conversationSeq: 2, direction: 'outbound', text: 'Hi there' })
    seedTurn(store, { conversationSeq: 3, direction: 'inbound', text: 'Bye' })
    markAllButConfig(session.gate)

    const configured = session.attachAndConfigure()
    // The session.update frame leaves first, synchronously, before injection
    // has had any chance to send anything.
    assertEquals(socket.sent[0].type, 'session.update')
    await session.contextInjectionPromise

    const items = socket.sentOfType('conversation.item.create')
    assertEquals(items.length, 3)
    // All three arrived strictly after the session.update frame.
    assertEquals(
      socket.sent.slice(1, 4).every((f) => f.type === 'conversation.item.create'),
      true,
    )

    type Item = { type: string; role: string; content: { type: string; text: string }[] }
    const [first, second, third] = items.map((frame) => frame.item as unknown as Item)

    assertEquals(first.type, 'message')
    assertEquals(first.role, 'user')
    assertEquals(first.content, [{ type: 'input_text', text: 'Hello' }])

    assertEquals(second.role, 'assistant')
    assertEquals(second.content, [{ type: 'text', text: 'Hi there' }])

    assertEquals(third.role, 'user')
    assertEquals(third.content, [{ type: 'input_text', text: 'Bye' }])

    await feed({ type: 'session.updated' })
    await configured
  },
)

Deno.test(
  'conversation context: a turn over 600 chars is tail-truncated, keeping the END',
  async () => {
    const { store, session, socket, feed } = await build()
    const tail = 'z'.repeat(600)
    seedTurn(store, {
      conversationSeq: 1,
      direction: 'inbound',
      text: 'HEAD-DROPPED-' + tail,
    })
    markAllButConfig(session.gate)

    const configured = session.attachAndConfigure()
    await session.contextInjectionPromise

    const items = socket.sentOfType('conversation.item.create')
    assertEquals(items.length, 1)
    type Item = { content: { text: string }[] }
    const content = (items[0].item as unknown as Item).content[0]
    assertEquals(content.text.length, 600)
    assertEquals(content.text, tail)
    assert(!content.text.includes('HEAD-DROPPED'))

    await feed({ type: 'session.updated' })
    await configured
  },
)

Deno.test(
  'conversation context: the 4000-char total cap drops the OLDEST turns first to fit',
  async () => {
    const { store, session, socket, feed } = await build()
    // Seven turns, each exactly 600 chars (well under the per-turn cap, so
    // none of them get truncated individually). 600 * 6 = 3600 <= 4000, but
    // 600 * 7 = 4200 > 4000 — so the walk (newest-first) keeps the six
    // newest and drops turn 1, the single oldest.
    for (let seq = 1; seq <= 7; seq += 1) {
      const marker = `T${seq}-`
      seedTurn(store, {
        conversationSeq: seq,
        direction: seq % 2 === 0 ? 'outbound' : 'inbound',
        text: marker + 'x'.repeat(600 - marker.length),
      })
    }
    markAllButConfig(session.gate)

    const configured = session.attachAndConfigure()
    await session.contextInjectionPromise

    const items = socket.sentOfType('conversation.item.create')
    type Item = { content: { text: string }[] }
    const markers = items.map((frame) =>
      (frame.item as unknown as Item).content[0].text.slice(0, 3)
    )
    // Turn 1 (oldest) was dropped; turns 2..7 survive, still oldest-first.
    assertEquals(markers, ['T2-', 'T3-', 'T4-', 'T5-', 'T6-', 'T7-'])

    await feed({ type: 'session.updated' })
    await configured
  },
)

Deno.test('conversation context: zero recent turns means zero frames sent', async () => {
  const { session, socket, feed } = await build()
  markAllButConfig(session.gate)

  const configured = session.attachAndConfigure()
  await session.contextInjectionPromise
  assertEquals(socket.sentOfType('conversation.item.create').length, 0)

  await feed({ type: 'session.updated' })
  await configured
})

Deno.test(
  'conversation context: a store failure sends no items but READY is still reached',
  async () => {
    const { store, session, socket, notices, feed } = await build()
    seedTurn(store, { conversationSeq: 1, direction: 'inbound', text: 'never sent' })
    store.failRecentTurns = true
    markAllButConfig(session.gate)

    const configured = session.attachAndConfigure()
    await session.contextInjectionPromise
    assertEquals(socket.sentOfType('conversation.item.create').length, 0)

    await feed({ type: 'session.updated' })
    await configured
    assertEquals(notices.map((notice) => notice.type), ['ready'])
  },
)

Deno.test(
  'conversation context: a fetch failure logs a bounded warning that never carries turn text',
  async () => {
    const { setLogSink, resetLogSink } = await import('../src/log.ts')
    const lines: Record<string, unknown>[] = []
    setLogSink((line) => lines.push(JSON.parse(line)))
    try {
      const { store, session, socket, feed } = await build()
      seedTurn(store, {
        conversationSeq: 1,
        direction: 'inbound',
        text: 'a secret transcript that must never reach the logs',
      })
      store.failRecentTurns = true
      markAllButConfig(session.gate)

      const configured = session.attachAndConfigure()
      await session.contextInjectionPromise

      const warned = lines.find((line) => line.event === 'context_injection.failed')
      assert(warned, 'context_injection.failed must be logged')
      assertEquals(warned.session_id, 'sess_1')
      assertEquals(warned.generation, 1)
      for (const line of lines) {
        assert(!JSON.stringify(line).includes('secret transcript'))
      }

      await feed({ type: 'session.updated' })
      await configured
    } finally {
      resetLogSink()
    }
  },
)

Deno.test(
  'conversation context: injected items never reach the client — only the ready notice does',
  async () => {
    const { store, session, socket, notices, feed } = await build()
    seedTurn(store, { conversationSeq: 1, direction: 'inbound', text: 'Hello' })
    seedTurn(store, { conversationSeq: 2, direction: 'outbound', text: 'Hi there' })
    markAllButConfig(session.gate)

    const configured = session.attachAndConfigure()
    await session.contextInjectionPromise
    // Nothing has been told to the client yet — injection is a MODEL-socket-only
    // affair, and READY has not even been acked yet.
    assertEquals(notices.length, 0)

    await feed({ type: 'session.updated' })
    await configured
    // The client learns nothing about the injected turns: exactly one notice,
    // and it is the plain ready shape with no room for conversation content.
    assertEquals(notices, [{ type: 'ready', session_id: 'sess_1', generation: 1 }])
  },
)

Deno.test(
  'conversation context: READY is withheld until injection settles, even once every other precondition (including config ack) is met',
  async () => {
    const { store, session, notices, feed } = await build()
    let resolveTurns: ((value: never[]) => void) | null = null // deno-lint-ignore no-explicit-any
    ;(store as any).loadRecentTurns = () =>
      new Promise((resolve) => {
        resolveTurns = resolve
      })
    // Deliberately excludes 'contextInjected' as well as 'configAcknowledged'
    // — unlike markAllButConfig, which would pre-mark 'contextInjected' and
    // defeat this test.
    markAllExcept(session.gate, 'configAcknowledged', 'contextInjected')

    const configured = session.attachAndConfigure()
    await feed({ type: 'session.updated' })
    await configured

    // The config is acknowledged and every other precondition holds, but the
    // context fetch is still pending: READY must not have fired yet.
    assertEquals(notices.length, 0)

    assert(resolveTurns, 'loadRecentTurns must have been called')
    ;(resolveTurns as (value: never[]) => void)([])
    await session.contextInjectionPromise

    assertEquals(notices, [{ type: 'ready', session_id: 'sess_1', generation: 1 }])
  },
)

Deno.test(
  'conversation context: a hung fetch never blocks READY past the injection timeout',
  async () => {
    const { store, session, notices, feed } = await build({
      contextInjectionTimeoutMs: 5,
    }) // deno-lint-ignore no-explicit-any
    ;(store as any).loadRecentTurns = () => new Promise(() => {}) // never resolves
    markAllExcept(session.gate, 'configAcknowledged', 'contextInjected')

    const configured = session.attachAndConfigure()
    await feed({ type: 'session.updated' })
    await configured

    // Immediately after config ack, the (hung) fetch has not yet timed out.
    assertEquals(notices.length, 0)

    // Settles once the bounded timeout fires — no real 500ms wait, since the
    // timeout was overridden to 5ms for this test.
    await session.contextInjectionPromise

    assertEquals(notices, [{ type: 'ready', session_id: 'sess_1', generation: 1 }])
  },
)
// ---------------------------------------------------------------------------
// Intake tool catalogue staging: session-level transition.
// ---------------------------------------------------------------------------

const INTAKE_STAGING_TOOLS: readonly RealtimeToolDefinition[] = [
  tool('propose_intake'),
  tool('start_intake'),
  tool('get_user_scope'),
]

function proposeIntakeSucceeds(): ToolExecutor {
  return () =>
    Promise.resolve({
      status: 'succeeded' as const,
      result: { ok: true, code: 'ok', data: { pendingActionId: 'pa_1' } },
    })
}

/**
 * The REAL result `propose_intake` returns on every realtime call today: the
 * broker's call into `executeAgentTool` omits `conversationTurnId` on
 * purpose (see the WHY-comment on `#maybeUpgradeToolCatalogue` in
 * sideband.ts), so `agent_intake_tools.ts`'s `requiredTurn()` always refuses.
 * Exercising the upgrade against THIS shape, not just a hypothetical success,
 * is the whole point of gating on the attempt rather than the result.
 */
function proposeIntakeFailsWithTurnContextRequired(): ToolExecutor {
  return () =>
    Promise.resolve({
      status: 'succeeded' as const,
      result: { ok: false, code: 'turn_context_required', data: null },
    })
}

/**
 * Feeds the `response.created` and `response.output_item.added` frames a
 * `propose_intake` function call needs before its terminal
 * `response.output_item.done` — the two frames are always safe to await
 * directly. The terminal frame is deliberately left to the CALLER to feed:
 * when this call is the one that triggers the intake upgrade, `feed(...)`
 * for that frame returns a promise that stays pending until `session.updated`
 * lands (see `#maybeUpgradeToolCatalogue`). Routing that promise back through
 * another `async function`'s `return` would silently await it first — every
 * `return somePromise` inside an `async function` flattens onto the outer
 * promise per the language's thenable-resolution rules — which is exactly
 * the deadlock this split avoids: the caller must call `feed` itself to keep
 * hold of the genuinely-pending promise.
 */
async function setUpProposeIntakeCall(
  feed: (event: Record<string, unknown>) => Promise<void>,
  options: { responseId?: string; callId?: string } = {},
): Promise<{ responseId: string; callId: string }> {
  const responseId = options.responseId ?? 'resp_1'
  const callId = options.callId ?? 'call_1'
  await feed({ type: 'response.created', response: { id: responseId } })
  await feed({
    type: 'response.output_item.added',
    response_id: responseId,
    item: { id: `fc_${callId}`, type: 'function_call' },
  })
  return { responseId, callId }
}

function proposeIntakeDoneFrame(
  responseId: string,
  callId: string,
): Record<string, unknown> {
  return {
    type: 'response.output_item.done',
    response_id: responseId,
    item: {
      type: 'function_call',
      call_id: callId,
      name: 'propose_intake',
      arguments: '{}',
    },
  }
}

Deno.test('a fresh session advertises only the core catalogue — staged intake tools withheld', async () => {
  const { feed, session, socket } = await build({
    tools: INTAKE_STAGING_TOOLS,
    executors: { propose_intake: proposeIntakeSucceeds() },
  })
  markAllButConfig(session.gate)
  const configured = session.attachAndConfigure()

  const sent = socket.sentOfType('session.update')
  assertEquals(sent.length, 1)
  const advertised = (sent[0].session as Record<string, unknown>).tools as Record<
    string,
    unknown
  >[]
  // 'start_intake' is staged; 'propose_intake' and 'get_user_scope' are not.
  assertEquals(advertised.map((t) => t.name), ['propose_intake', 'get_user_scope'])

  await feed({ type: 'session.updated' })
  await configured
})

Deno.test(
  'a propose_intake call sends exactly one upgrade session.update, before the follow-up response.create',
  async () => {
    const { feed, socket, session } = await build({
      tools: INTAKE_STAGING_TOOLS,
      executors: { propose_intake: proposeIntakeSucceeds() },
    })
    markAllButConfig(session.gate)
    const configured = session.attachAndConfigure()
    await feed({ type: 'session.updated' })
    await configured
    assertEquals(socket.sentOfType('session.update').length, 1)
    assertEquals(socket.sentOfType('response.create').length, 0)

    const { responseId, callId } = await setUpProposeIntakeCall(feed)
    const toolCallDone = feed(proposeIntakeDoneFrame(responseId, callId))
    await tick()

    // The upgrade's session.update leaves BEFORE response.create — the model
    // must not be asked to answer with the old catalogue after a call that
    // just widened it.
    assertEquals(
      socket.sentOfType('session.update').length,
      2,
      'exactly one upgrade sent',
    )
    assertEquals(socket.sentOfType('response.create').length, 0, 'not sent yet')
    const upgraded = socket.sentOfType('session.update')[1].session as Record<
      string,
      unknown
    >
    assertEquals(
      (upgraded.tools as Record<string, unknown>[]).map((t) => t.name),
      ['propose_intake', 'start_intake', 'get_user_scope'],
    )

    await feed({ type: 'session.updated' })
    await toolCallDone

    assertEquals(socket.sentOfType('response.create').length, 1)

    // Wire order, asserted directly off the raw send sequence.
    const upgradeAt = socket.sent.findIndex((frame, i) =>
      frame.type === 'session.update' && i > 0
    )
    const responseCreateAt = socket.sent.findIndex((frame) =>
      frame.type === 'response.create'
    )
    assert(upgradeAt >= 0 && responseCreateAt >= 0)
    assert(
      upgradeAt < responseCreateAt,
      'the upgrade must be sent before response.create',
    )
  },
)

Deno.test(
  'propose_intake failing with turn_context_required — the REAL production result today — still upgrades',
  async () => {
    const { feed, socket, session } = await build({
      tools: INTAKE_STAGING_TOOLS,
      executors: { propose_intake: proposeIntakeFailsWithTurnContextRequired() },
    })
    markAllButConfig(session.gate)
    const configured = session.attachAndConfigure()
    await feed({ type: 'session.updated' })
    await configured
    assertEquals(socket.sentOfType('session.update').length, 1)

    const { responseId, callId } = await setUpProposeIntakeCall(feed)
    const toolCallDone = feed(proposeIntakeDoneFrame(responseId, callId))
    await tick()

    // Gated on the ATTEMPT, not the result: a turn_context_required refusal
    // still upgrades the catalogue, because a success-gated check would never
    // fire against today's actual `propose_intake` behavior.
    assertEquals(socket.sentOfType('session.update').length, 2, 'the upgrade still fires')
    const upgraded = socket.sentOfType('session.update')[1].session as Record<
      string,
      unknown
    >
    assertEquals(
      (upgraded.tools as Record<string, unknown>[]).map((t) => t.name),
      ['propose_intake', 'start_intake', 'get_user_scope'],
    )

    await feed({ type: 'session.updated' })
    await toolCallDone
    assertEquals(
      socket.sentOfType('response.create').length,
      1,
      'the model is still answered',
    )
  },
)

Deno.test('a second propose_intake attempt does not send a second upgrade', async () => {
  let calls = 0
  const { feed, socket, session } = await build({
    tools: INTAKE_STAGING_TOOLS,
    executors: {
      propose_intake: () => {
        calls += 1
        // The first attempt fails exactly like production does today; the
        // second succeeds. Idempotency must hold regardless of either
        // attempt's result — the gate is on the CALL, not the outcome.
        return Promise.resolve(
          calls === 1
            ? {
              status: 'succeeded' as const,
              result: { ok: false, code: 'turn_context_required', data: null },
            }
            : {
              status: 'succeeded' as const,
              result: { ok: true, code: 'ok', data: { pendingActionId: 'pa_1' } },
            },
        )
      },
    },
  })
  markAllButConfig(session.gate)
  const configured = session.attachAndConfigure()
  await feed({ type: 'session.updated' })
  await configured

  const first = await setUpProposeIntakeCall(feed, {
    responseId: 'resp_1',
    callId: 'call_1',
  })
  const firstDone = feed(proposeIntakeDoneFrame(first.responseId, first.callId))
  await tick()
  assertEquals(socket.sentOfType('session.update').length, 2)
  await feed({ type: 'session.updated' })
  await firstDone

  // Second call, same session: safe to await straight through — the upgrade
  // is already applied, so `#maybeUpgradeToolCatalogue` returns immediately
  // without arming a second pending ack.
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_2' })
  const second = await setUpProposeIntakeCall(feed, {
    responseId: 'resp_2',
    callId: 'call_2',
  })
  await feed(proposeIntakeDoneFrame(second.responseId, second.callId))

  assertEquals(calls, 2, 'the tool itself still runs every time it is called')
  assertEquals(socket.sentOfType('session.update').length, 2, 'no second upgrade sent')
})

Deno.test(
  'after an upgrade, a vad_fallback resend still carries the FULL catalogue, not core',
  async () => {
    const { feed, socket, session } = await build({
      tools: INTAKE_STAGING_TOOLS,
      executors: { propose_intake: proposeIntakeSucceeds() },
    })
    markAllButConfig(session.gate)
    // The initial config is deliberately left unacknowledged: this drives a
    // propose_intake call, and only THEN the provider's rejection of that
    // still-unacked initial config, forcing the vad_fallback resend.
    // Contrived ordering — in production a tool call cannot precede the
    // model even having tools — but it is exactly the case `#sendSessionConfig`
    // reading a single `#activeTools` field is there to get right regardless
    // of ordering: every send, including vad_fallback, must carry whichever
    // catalogue is CURRENT.
    session.attachAndConfigure()
    assertEquals(socket.sentOfType('session.update').length, 1)

    const { responseId, callId } = await setUpProposeIntakeCall(feed)
    const toolCallDone = feed(proposeIntakeDoneFrame(responseId, callId))
    await tick()
    assertEquals(socket.sentOfType('session.update').length, 2, 'upgrade sent')

    await feed({
      type: 'error',
      error: {
        code: 'invalid_value',
        param: 'session.audio.input.turn_detection.type',
        message: 'x',
      },
    })
    assertEquals(socket.sentOfType('session.update').length, 3, 'vad_fallback resent')
    const fallback = socket.sentOfType('session.update')[2].session as Record<
      string,
      unknown
    >
    assertEquals(
      (fallback.tools as Record<string, unknown>[]).map((t) => t.name),
      ['propose_intake', 'start_intake', 'get_user_scope'],
    )

    // Settle both pending sends so nothing is left hanging past the test.
    await feed({ type: 'session.updated' })
    await toolCallDone
  },
)

Deno.test(
  'an upgrade ack timeout still lets response.create through, and logs a warn',
  async () => {
    const { lines, restore } = captureLogs()
    const { feed, socket, session } = await build({
      tools: INTAKE_STAGING_TOOLS,
      intakeUpgradeAckTimeoutMs: 5,
      executors: { propose_intake: proposeIntakeSucceeds() },
    })
    markAllButConfig(session.gate)
    const configured = session.attachAndConfigure()
    await feed({ type: 'session.updated' })
    await configured

    // The upgrade's own `session.updated` is deliberately never fed: the
    // overridden 5ms timeout must fire and let the call proceed rather than
    // hang the response chain on a lost or slow ack.
    const { responseId, callId } = await setUpProposeIntakeCall(feed)
    await feed(proposeIntakeDoneFrame(responseId, callId))
    restore()

    assertEquals(
      socket.sentOfType('session.update').length,
      2,
      'the upgrade was still sent',
    )
    assertEquals(
      socket.sentOfType('response.create').length,
      1,
      'the model is still answered',
    )
    const warned = lines.some((line) =>
      JSON.parse(line).event === 'sideband.intake_upgrade_ack_timeout'
    )
    assert(warned, 'a warn must be logged when the upgrade ack times out')
  },
)

Deno.test('a barge-in drops the pending attribution instead of stamping a later turn', async () => {
  const { feed, store } = await build()
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  await feed({
    type: 'response.output_item.added',
    response_id: 'resp_1',
    item: { id: 'fc_1', type: 'function_call' },
  })
  await feed({
    type: 'response.output_item.done',
    response_id: 'resp_1',
    item: {
      type: 'function_call',
      call_id: 'call_1',
      name: 'lookup_flock',
      arguments: '{}',
    },
  })
  await feed({
    type: 'response.done',
    response: { id: 'resp_1', status: 'completed', usage: REALISTIC_USAGE },
  })

  // The user interrupts: our follow-up response.create never produces a
  // response, and a NEW user utterance is committed instead.
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_2' })
  await feed({ type: 'response.created', response: { id: 'resp_2' } })
  await feed({
    type: 'response.done',
    response: { id: 'resp_2', status: 'completed', usage: REALISTIC_USAGE },
  })

  // resp_2 answers the user's NEW question. It followed no tool call.
  const later = store.responseUsage.get('sess_1:resp_2')
  assertEquals(later?.followedToolCall, false)
  assertEquals(later?.toolNames, [])
})

Deno.test('two tool calls in one response land on ONE follow-up row together', async () => {
  const { feed, store } = await build()
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  for (
    const [callId, name] of [['call_1', 'lookup_flock'], ['call_2', 'get_user_scope']]
  ) {
    await feed({
      type: 'response.output_item.added',
      response_id: 'resp_1',
      item: { id: `fc_${callId}`, type: 'function_call' },
    })
    await feed({
      type: 'response.output_item.done',
      response_id: 'resp_1',
      item: { type: 'function_call', call_id: callId, name, arguments: '{}' },
    })
  }
  await feed({
    type: 'response.done',
    response: { id: 'resp_1', status: 'completed', usage: REALISTIC_USAGE },
  })
  await feed({ type: 'response.created', response: { id: 'resp_cont_1' } })
  await feed({
    type: 'response.done',
    response: { id: 'resp_cont_1', status: 'completed', usage: REALISTIC_USAGE },
  })

  const followUp = store.responseUsage.get('sess_1:resp_cont_1')
  assertEquals(followUp?.followedToolCall, true)
  // BOTH names on the single row they jointly caused — not split, not dropped.
  assertEquals(followUp?.toolNames, ['lookup_flock', 'get_user_scope'])
})

Deno.test(
  'an un-acked upgrade is retried once by a later propose_intake, then stops',
  async () => {
    const { feed, socket, session } = await build({
      tools: INTAKE_STAGING_TOOLS,
      intakeUpgradeAckTimeoutMs: 5,
      executors: { propose_intake: proposeIntakeSucceeds() },
    })
    markAllButConfig(session.gate)
    const configured = session.attachAndConfigure()
    await feed({ type: 'session.updated' })
    await configured

    // First attempt: never acked, so the session may still be on the core
    // catalogue and the upgrade must not be treated as durably done.
    const first = await setUpProposeIntakeCall(feed)
    await feed(proposeIntakeDoneFrame(first.responseId, first.callId))
    assertEquals(socket.sentOfType('session.update').length, 2, 'first upgrade sent')

    // Second attempt: retries, because the first was never confirmed. A NEW
    // user turn — distinct ids alone are not enough, since a second call
    // inside the same interaction spends that interaction's continuation
    // budget and is terminated before it reaches the upgrade path.
    await feed({ type: 'input_audio_buffer.committed', item_id: 'item_2' })
    const second = await setUpProposeIntakeCall(feed, {
      responseId: 'resp_2',
      callId: 'call_2',
    })
    await feed(proposeIntakeDoneFrame(second.responseId, second.callId))
    assertEquals(socket.sentOfType('session.update').length, 3, 'retried once')

    // Third attempt: the bound is reached; the session settles for what it has
    // rather than spending more of a live turn on session.update round trips.
    await feed({ type: 'input_audio_buffer.committed', item_id: 'item_3' })
    const third = await setUpProposeIntakeCall(feed, {
      responseId: 'resp_3',
      callId: 'call_3',
    })
    await feed(proposeIntakeDoneFrame(third.responseId, third.callId))
    assertEquals(
      socket.sentOfType('session.update').length,
      3,
      'no third upgrade — the retry bound holds',
    )
  },
)
