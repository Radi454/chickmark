// The `session.update` payload.
//
// Every field below was verified accepted verbatim by the current Realtime API.
// Two shapes are easy to get wrong and both are load-bearing:
//
//   * `audio.input.transcription.delay` is an ENUM
//     (minimal|low|medium|high|xhigh), NOT a millisecond number.
//   * tool definitions are FLAT — `{type, name, description, parameters}` — not
//     the nested `{type:'function', function:{...}}` shape used by Chat
//     Completions.
//
// The `openai-beta.realtime-v1` subprotocol is deliberately absent everywhere in
// this service: sending it forces the retired beta surface and the connection is
// rejected.

import type { RealtimeConfig } from './config.ts'

export interface RealtimeToolDefinition {
  readonly type: 'function'
  readonly name: string
  readonly description: string
  readonly parameters: Record<string, unknown>
}

// ---------------------------------------------------------------------------
// Intake tool staging
// ---------------------------------------------------------------------------

/**
 * Tool names withheld from the model until `propose_intake` is CALLED in this
 * session — see `SidebandSession#maybeUpgradeToolCatalogue` in sideband.ts
 * for why the gate fires on the attempt rather than waiting for it to
 * succeed. Every name below takes `pendingActionId` or `intakeId` as a
 * required argument, and neither id can exist before `propose_intake` (for
 * `pendingActionId`) or `start_intake` (for `intakeId`) has already returned
 * one — see `agent_tool_contract.ts` and `agent_intake_tools.ts` in
 * `telegram-hatchery-agent`. The realtime channel never injects per-session
 * server context into the model's turn the way the text channel injects
 * `activeIntake`; `#injectRecentContext` in sideband.ts injects prior TURN
 * TEXT only. That is not quite the same as "no id can ever appear": a
 * conversation is shared with the app-text channel, so an injected prior
 * ASSISTANT turn is model-authored prose that could in principle contain an id
 * the model saw in a text-channel tool result. The staging argument does not
 * rest on that, though — an unadvertised tool is uncallable whatever the model
 * believes it knows, so the worst case is deferred capability, never a way
 * around the gate. Staging therefore removes no reachable capability, only the
 * token cost of advertising these tools on every turn that never reaches data
 * entry.
 *
 * By the same argument, no tool OTHER than `propose_intake` could serve as
 * this gate: it is the only tool whose call requires no id produced by a
 * STAGED tool (it takes `customerId`, which the core catalogue supplies), so
 * it is the first point in the chain the model can legitimately reach.
 *
 * `list_legacy_draft_questions` and `answer_legacy_draft_question` are
 * DELIBERATELY left off this list even though they also require an id
 * (`submissionId`) nothing in this catalogue ever produces: no core tool's
 * result yields one, so by the same argument they may be just as unreachable.
 * But "probably unreachable" is not "provably unreachable" the way the
 * pendingActionId/intakeId chain above is, and a wrong guess here would
 * silently remove capability rather than merely defer it. They stay
 * advertised until someone can show a tool that actually supplies a
 * `submissionId` in the realtime channel.
 */
export const INTAKE_STAGED_TOOL_NAMES: readonly string[] = [
  'start_intake',
  'record_station_values',
  'get_intake_status',
  'create_station_summary',
  'confirm_station_summary',
  'submit_station_for_review',
  'pause_intake',
  'resume_intake',
  'cancel_intake',
]

export interface ToolCataloguePartition {
  readonly core: readonly RealtimeToolDefinition[]
  readonly full: readonly RealtimeToolDefinition[]
}

/**
 * Split the deployed catalogue into what a fresh session starts with
 * (`core`) and everything (`full`). `full` is `all`, unchanged.
 *
 * The split is DERIVED from `all` on every call rather than read from a
 * second, separately-maintained list, so the two can never drift out of sync
 * with the deployed catalogue: there is exactly one place
 * (`INTAKE_STAGED_TOOL_NAMES` above) that says which names are staged, and
 * `core` is defined purely as "`all` minus that set". A second env var
 * enumerating the core set directly would let a contract change land in one
 * place and not the other, and a voice session would silently lose or keep a
 * tool with nobody the wiser until a call needed it.
 *
 * `core`'s relative order is `all`'s order with staged entries removed —
 * never resorted — because OpenAI's prompt cache keys on the `tools` array
 * verbatim; reordering `core` independently of `full` would cost a cache miss
 * on every upgraded session for no behavioral gain.
 *
 * A staged name absent from `all` is NOT an error: `all` comes from whatever
 * catalogue is actually deployed (older or newer than this file), and that
 * catalogue must still boot and run with whatever it actually has.
 */
export function partitionToolCatalogue(
  all: readonly RealtimeToolDefinition[],
): ToolCataloguePartition {
  const staged = new Set(INTAKE_STAGED_TOOL_NAMES)
  const core = all.filter((tool) => !staged.has(tool.name))
  return { core, full: all }
}

/**
 * Domain vocabulary handed to the transcriber. Hatchery terms and Arabic/English
 * code-switching are exactly where a general ASR model guesses wrong, and a
 * mis-transcribed breed or station name silently poisons a tool argument.
 *
 * ROOT CAUSE this replaced: the prior prompt was 100% English hatchery
 * vocabulary — a strong English decoding bias — sent with no language hint at
 * all. Production persisted hallucinated English captions ("Hello, world.",
 * "I'm Elly.", "In Tamil") over Egyptian Arabic audio, which then polluted
 * stored conversation history. This is the exact bilingual prompt text
 * verified accepted for gpt-4o-mini-transcribe on a live probe connection
 * (2026-08-19, `tools/probe_session_knobs.ts`, case "language:'ar' +
 * bilingual prompt"). Exported as `TRANSCRIPTION_PROMPT` (the name kept from
 * before) so callers don't need to know it grew Arabic framing.
 */
export const TRANSCRIPTION_PROMPT = [
  'محادثة بالعامية المصرية عن تشغيل المفرخات، وقد تتخلط بكلمات إنجليزية.',
  'مصطلحات: مفرخ، ماكينة تحضين، قطيع، سلالة، خصوبة، فقس، تقرير، تفقيس.',
  'ChickMark hatchery operations. Egyptian Arabic with English terms mixed in.',
  'Terms: hatchery, setter, hatcher, incubation, candling, transfer, pull,',
  'flock, breed, Ross, Cobb, Hubbard, Arbor Acres, Indian River,',
  'egg storage, CVT, Govee, BMK, Pasgar, hatchability, fertility,',
  'early dead, mid dead, late dead, contaminated, cull, chick quality.',
].join(' ')

/**
 * `turn_detection`, built from config so a runtime fallback (see
 * `src/sideband.ts`) can rebuild it with `server_vad` forced without
 * duplicating either shape.
 *
 * Both shapes were verified accepted by the live endpoint:
 *   * `semantic_vad` + `eagerness:'low'` — probed against
 *     gpt-realtime-2.1-mini, 2026-08-18 (`tools/probe_turn_detection.ts`),
 *     acked with `session.updated`.
 *   * `server_vad` — the prior, already-live shape; `silence_duration_ms` is
 *     now config-driven instead of a hardcoded 500ms so short natural pauses
 *     don't end the user's turn early.
 */
export function buildTurnDetection(config: RealtimeConfig): Record<string, unknown> {
  if (config.turnDetection === 'semantic_vad') {
    return {
      type: 'semantic_vad',
      eagerness: config.vadEagerness,
      create_response: true,
      interrupt_response: true,
    }
  }
  return {
    type: 'server_vad',
    threshold: 0.5,
    prefix_padding_ms: 300,
    silence_duration_ms: config.vadSilenceMs,
    create_response: true,
    interrupt_response: true,
  }
}

export function buildSessionUpdate(input: {
  config: RealtimeConfig
  tools: readonly RealtimeToolDefinition[]
  instructions: string
}): Record<string, unknown> {
  const { config, tools } = input
  // `languages` (plural) and `delay` are gpt-live-transcribe-ONLY knobs.
  // Sending either with any other transcription model (e.g. the default
  // gpt-4o-mini-transcribe) makes the provider reject the ENTIRE
  // session.update with invalid_value — the session then runs with default
  // VAD, no tools and no instructions while sounding perfectly healthy.
  // Named explicitly by the provider on a live call (2026-08-17):
  //   "The 'delay' parameter is not supported for this model."
  //   "The 'languages' parameter is not supported for this model."
  // The same payload without them is acked. Reproduce with
  // integration_test/realtime_attach_probe_test.dart.
  //
  // That rejection is specific to the PLURAL `languages` field and to
  // `delay` — it must NOT be read as "no language field is supported for
  // this model". The SINGULAR `language` field is verified ACCEPTED for
  // gpt-4o-mini-transcribe on a live probe connection (2026-08-19,
  // `tools/probe_session_knobs.ts`), echoed back as `"ar"`. It is therefore
  // sent for every transcription model except gpt-live-transcribe, which
  // keeps its own `languages`/`delay` shape below and must never also
  // receive singular `language` — that combination is unprobed.
  const transcription: Record<string, unknown> = {
    model: config.transcriptionModel,
    prompt: TRANSCRIPTION_PROMPT,
  }
  if (config.transcriptionModel === 'gpt-live-transcribe') {
    transcription.languages = ['ar', 'en']
    transcription.delay = config.transcriptionDelay
  } else if (config.transcriptionLanguage !== '') {
    transcription.language = config.transcriptionLanguage
  }
  const session: Record<string, unknown> = {
    type: 'realtime',
    output_modalities: ['audio'],
    audio: {
      input: {
        noise_reduction: { type: 'near_field' },
        transcription,
        turn_detection: buildTurnDetection(config),
      },
      output: { voice: config.voice },
    },
    reasoning: { effort: config.reasoningEffort },
    tool_choice: 'auto',
    tools,
    // Ceiling on a spoken reply. Production has never had one — the session
    // default echoes "inf" (2026-08-19, `tools/probe_session_knobs.ts`).
    // Measured token cost of every reply size the voice policy allows
    // (`tools/probe_output_tokens.ts`, same date, gpt-realtime-2.1-mini,
    // production session payload, reasoning effort low):
    //   greeting                66 output tokens
    //   single-metric           60
    //   two-metric              145
    //   explicit-full-summary  488  <- longest LEGITIMATE reply the policy permits
    //   eleven-metric-dump     761  <- the 2026-08-19 incident shape
    // The ceiling is sized so it can NEVER truncate a legitimate answer.
    // Live canary measurement (2026-08-19, evals/run_canaries.ts, which sends
    // this exact payload) of the largest reply the policy legitimately
    // permits — an EXPLICITLY requested full 11-metric breakout summary —
    // came back at 832 and 865 output tokens on two runs, status
    // "completed". An earlier 6-metric breed summary cost 488. 1536 is ~1.8x
    // the largest observed legitimate reply, so ordinary run-to-run variance
    // cannot clip one; `max_output_tokens` truncation is not graceful, the
    // response simply stops and comes back `incomplete`.
    //
    // 1024 was the first value tried and is deliberately NOT used: it left
    // only ~18% headroom over an answer already observed at 865, and an
    // explicit full summary of the 17-row audit-vs-benchmark comparison is
    // larger still.
    //
    // The ceiling is NOT sized to cut the 761-token incident dump. That is
    // cured at source by the shaped tool payload and the report-vs-benchmark
    // routing, both pinned by canaries. This is a backstop against an
    // unanticipated payload, and a backstop that truncates real answers is
    // worse than no backstop.
    max_output_tokens: config.maxOutputTokens,
  }
  session.instructions = input.instructions

  return { type: 'session.update', session }
}
