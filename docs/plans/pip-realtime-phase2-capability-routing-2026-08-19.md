# Pip Realtime Phase 2 — Capability Routing & Context-on-Demand

Status: **DESIGN / NOT APPROVED — no code written, nothing deployed.**
Date: 2026-08-19
Scope: `services/pip-realtime-sideband`, `supabase/functions/pip-realtime-{session,tool-broker}`,
`supabase/functions/telegram-hatchery-agent/agent_{prompt,tool_contract}.ts`.

This document answers the Phase 2 brief: minimal core → intent router → load only the
relevant tool pack → execute → optionally unload. It is an evolution of the shipped
staged-catalogue design, not a rewrite.

**Headline: the mechanism is feasible and already half-built, but the economics invert the
brief.** Aggressive load/unload is *more* expensive than the status quo, by a wide margin,
because of how Realtime prompt caching and audio-token re-billing interact. The defensible
Phase 2 is a narrower one. Full reasoning in §7 and §8.

---

## 1. Current-state token / context breakdown

### 1.1 What actually enters a fresh Realtime session

The Realtime stack is **not** in `supabase/functions/pip-realtime-session/` — that edge
function is the door only (auth, rate limit, budget, mints the ephemeral client secret,
issues a binding token). It never opens a WebSocket and never sends `session.update`.

The session brain is the Cloud Run service `services/pip-realtime-sideband`. Bootstrap
order (`src/sideband.ts:730-793`, `attachAndConfigure()`):

1. `session.update` — one frame, full config (built by `buildSessionUpdate`,
   `src/session_config.ts:169-253`), then **awaits `session.updated`**.
2. `conversation.item.create` × N — history replay, fired concurrently, bounded at 500 ms.
3. No `response.create` at bootstrap. The first assistant turn is provoked entirely by
   provider-side semantic VAD (`create_response: true`).
4. `ready` is emitted to the client only when all nine `READINESS_PRECONDITIONS` hold
   (`src/sideband.ts:307-320`), one of which is `configAcknowledged`.

The initial `session.update` payload, verbatim shape (`src/session_config.ts:204-252`):

```js
{
  type: 'session.update',
  session: {
    type: 'realtime',
    output_modalities: ['audio'],
    audio: {
      input: {
        noise_reduction: { type: 'near_field' },
        transcription: { model: 'gpt-4o-mini-transcribe', prompt: TRANSCRIPTION_PROMPT, language: 'ar' },
        turn_detection: { type: 'semantic_vad', eagerness: 'low', create_response: true, interrupt_response: true },
      },
      output: { voice: 'cedar' },
    },
    reasoning: { effort: 'low' },
    tool_choice: 'auto',
    tools,                       // core catalogue, 23 of 32
    max_output_tokens: 1536,
    instructions,                // CHICKMARK_REALTIME_POLICY, static
  },
}
```

Not sent: `temperature`, `truncation`, `token_limits`, `input_audio_format` /
`output_audio_format`, any per-response `instructions`/`tools` override.

### 1.2 Input-token cost by component

Two independent measurements. **Use column A for all decisions** — it is what the provider
actually bills.

| Component | A: provider-measured (`response.usage.input_tokens`) | B: raw JSON via tiktoken `o200k_base` |
|---|---:|---:|
| Provider baseline | 123 | — |
| Voice policy (`instructions`) | 2,620 | 3,458 |
| Tool schemas — core 23 | ~1,877 (derived) | 2,202 |
| **Fresh-session total** | **4,620** | 5,660 |
| Tool schemas — full 32 | ~2,500 (derived) | 3,083 |
| **After intake upgrade** | **5,243** | 6,541 |

Column A sources: `docs/CHANGELOG.md:297-299` and `:343-344`, `docs/LIVING_SPEC.md:3714-3721`
— live measurements against deployed revisions (`00013-gpq` before, current after). The
per-component split of the 4,620 is derived, not stated: the changelog is explicit that the
policy text was untouched, so 4,620 − 123 − 2,620 = ~1,877 for the slimmed core catalogue.

Column B is raw JSON tokenized with the real OpenAI BPE (o200k_base). It runs ~20–30% high
because the provider does not bill tool schemas as raw JSON. **Never plan against column B.**

Discrepancy to resolve before any work starts: the 2,620 policy figure predates policy
v2.3.0, which added `REPORT_VS_BENCHMARK` (3,182 chars) on 2026-08-19. The current policy
almost certainly costs more than 2,620. Re-measure (§13, T-01).

### 1.3 Policy composition (`agent_prompt.ts:212-222`)

Nine sections joined by `\n\n`. Char counts measured directly.

| # | Section | Opening line | Chars | Permanent core? |
|---|---|---|---:|---|
| 1 | `AGENT_IDENTITY` | `You are ChickMark's hatchery operations assistant.` | 50 | **Yes** |
| 2 | `VOICE_CONVERSATION` | `Voice conversation:` | 4,688 | **Yes** (mostly) |
| 3 | `AGENT_SECURITY_LINES` | `Security:` | 681 | **Yes** |
| 4 | `EVIDENCE_AND_SCOPE_VOICE` | `Evidence and scope:` | 2,351 | **Yes** |
| 5 | `NATURAL_DATA_ENTRY` | `Natural data entry:` | 2,355 | No — pairs with intake pack |
| 6 | `BENCHMARK_DISCIPLINE` | `Benchmark discipline:` | 1,182 | No — pairs with benchmark pack |
| 7 | `REPORT_VS_BENCHMARK` | `Report vs benchmark routing:` | 3,182 | No — pairs with audit+benchmark |
| 8 | `TOOL_RESULT_SCOPE` | `Tool results:` | 976 | **Yes** |
| 9 | `TOOL_DISCIPLINE` | `Tool discipline:` | 282 | **Yes** |
| | **Total** | | **15,763** | core ≈ 8,748 (55%) |

Sections 2 and 7 are 50% of the budget on their own. Both are calibration-example-driven.

### 1.4 Conversation history

- Table `agent_conversation_turns`, ordered by monotonic `conversation_seq` (never
  `created_at`).
- Only `completion_status='finalized'` rows. Pending/interrupted turns are durable
  evidence but never model context (`agent_context.ts:18-20`).
- Realtime caps (`src/sideband.ts:277-283`): `CONTEXT_TURN_LIMIT=12`,
  `CONTEXT_PER_TURN_CHAR_CAP=600` (tail-kept), `CONTEXT_TOTAL_CHAR_CAP=4000`,
  `CONTEXT_INJECTION_TIMEOUT_MS=500`.
- Cross-channel: merges `app_text`, `telegram`, and prior `realtime_voice` turns.
- Injected as `conversation.item.create` message items, oldest-first, never followed by a
  `response.create`.
- Tool results are **not** in history. They live in `agent_tool_events` and are never
  replayed as model context.
- Working context (`selected_customer_id` / `selected_flock_id` / `selected_audit_id` on
  `agent_conversations`) is **not** put in the prompt at all. It is re-resolved server-side
  inside the handful of "selected"-scoped tools (`get_audit_summary`,
  `get_selected_audit_breakouts`, `compare_selected_audit_to_benchmark`,
  `select_audit_option`). This is already the architecture §5 of the brief asks for.

Worst case ≈ 4,000 chars ≈ 1,000–1,300 tokens of injected history, only on a session that
continues a prior conversation.

### 1.5 Confirmations requested in the brief

| Question | Answer |
|---|---|
| Core tools | 23 of 32. `partitionToolCatalogue`, `src/session_config.ts:104-110`. |
| Staged intake tools | 9 names, `INTAKE_STAGED_TOOL_NAMES`, `src/session_config.ts:65-75`. |
| `session.update` | One mutator: `#sendSessionConfig(source, turnDetection)`, `src/sideband.ts:861-902`. Exactly 3 call sites: `'initial'`, `'vad_fallback'`, `'intake_upgrade'`. |
| Replacement vs merging | The provider replaces the whole `tools` array. The sideband always sends the **full** desired list, never a delta. |
| Prompt caching | Documented as degraded by any mid-session change to `instructions` or `tools`. The code already knows this — `session_config.ts:95-98` refuses to resort `core` for exactly this reason. |

---

## 2. Feasibility verdict — Realtime API capabilities

Verified against `developers.openai.com` (Realtime client-events reference, realtime
conversations guide, realtime costs guide, `gpt-realtime-2.1-mini` model page) plus the
shipped code and its tests.

| Capability | Verdict | Evidence |
|---|---|---|
| Start with `tools: []` | **UNVERIFIED** | No doc statement; never exercised in code. Needs a live probe (§13, T-02). |
| Add tools later via `session.update` | **CONFIRMED + in production** | `#maybeUpgradeToolCatalogue`, `src/sideband.ts:1421-1468`. |
| Replace the tool list | **CONFIRMED** | Docs: *"Only the fields that are present in the `session.update` are updated."* Arrays replace wholesale. |
| Unload via `tools: []` | **CONFIRMED (documented)** | Docs: *"To clear a field like `tools`, pass an empty array."* Not exercised here. |
| Multiple updates per session | **CONFIRMED** | *"The client may send this event at any time to update any field except for `voice` and `model`."* |
| Conversation survives `session.update` | **CONFIRMED in practice, no explicit doc sentence** | The shipped intake upgrade does exactly this and conversation continuity holds; pinned by `test/sideband_test.ts`. |
| Ack | **CONFIRMED** | *"the server ... will respond with a `session.updated` event showing the full, effective configuration."* |

### 2.1 Limitations, races, and consequences

1. **Immutable mid-session**: `model` always; `voice` once any audio has been emitted.
2. **A rejected `session.update` is dropped WHOLE.** Field-verified in production
   (`src/sideband.ts` comments, from the 2026-08-17 `gpt-live-transcribe` incident) — the
   session is then left with *default VAD and no tools/instructions*. This is the single
   most dangerous failure mode in the entire design.
3. **No documented ordering guarantee** between `session.update` and a later
   `response.create`. The code does not rely on one — it awaits the ack explicitly, and
   `test/sideband_test.ts` pins the wire order. Any new pack loader must do the same.
4. **`event_id` is echoed only on `error`**, never on a successful `session.updated`. The
   sideband correlates updates by sequence counting (`#updateSeq`/`#ackSeq`), not by id.
   Concurrent in-flight updates are therefore not individually attributable — serialize them.
5. **Caching**: docs, verbatim — *"instructions and tool definitions are at the beginning of a
   conversation, thus changing these mid-session will reduce the cache rate for subsequent
   turns."* This is decisive; see §8.
6. **Caps**: `instructions` + `tools` ≤ 16,384 tokens (currently ~35% used — no pressure).
   Session ≤ 60 min. Context window 128k, max output 32k for this model.
7. **Unverified**: max tool count, `session.update` rate limit.

**Verdict: the mechanism is feasible. The published cost guidance says using it aggressively
is a mistake.**

---

## 3. Routing design

### 3.1 The constraint that eliminates most options

Voice UX budget to first audio is ~800 ms. Any router that must run *before* the model
starts speaking sits directly in that budget. Worse, `turn_detection.create_response: true`
means **the provider starts inference the moment VAD detects end-of-speech** — before
`conversation.item.input_audio_transcription.completed` is guaranteed to have arrived.

So a transcript-based router is *racing the model it is trying to configure*. Winning that
race requires `create_response: false` and driving `response.create` from the sideband —
tearing up a proven VAD path and adding a round trip to every single turn.

| Option | Token cost | Added latency | Arabic/English | Maintenance | Failure mode |
|---|---|---|---|---|---|
| **A. Deterministic keyword/entity** | ~0 | 0 if it wins the race; **loses the race under current VAD config** | Brittle — Egyptian colloquial, code-switching, transliteration ("break out" / "بريك أوت" / "breakout") | High, permanent | Silent misroute → tool absent → model invents or stalls |
| **B. Tiny cheap model (`gpt-5-nano`)** | ~200–400 tok/turn on a separate model | **+300–900 ms**, same race problem | Good | Moderate | Adds a second model + a second failure surface to a voice hot path |
| **C. Permanent `request_capabilities` tool** | ~60 tok permanent | **+1 full model turn (~500–1500 ms)** before the answer can even begin | Excellent (model understands intent natively) | Low | Model forgets to call it → dead end; doubles turn count |
| **D. Hybrid A→B** | A + B | Worst of both | Good | Highest | Two routers to debug |
| **A′. Client-context pre-selection (recommended)** | **0** | **0** | **N/A — no NLU involved** | **Very low** | Wrong screen → wrong pack → falls back to C |

### 3.2 Recommendation: **A′ + C**, not A/B/D

**A′ — client-context pre-selection at session start.** The Flutter app already knows what
screen the user was on when they hit the mic. Pass that as a `capabilityHint` through
`pip-realtime-session`'s `start` action into the sideband's initial config. Benchmarks
screen → benchmark pack. Audit detail → audit pack. Data entry → intake pack. Dashboard /
unknown → the default core.

Why this dominates every NLU option:

- Zero inference cost, zero added latency, zero Arabic/English ambiguity, no race with VAD.
- It applies to the **initial** `session.update` — so it causes **zero cache invalidation**,
  because there is nothing cached yet.
- It is trivially testable deterministically.
- It degrades safely: an unknown hint yields today's exact behaviour.

**C — one permanent tiny tool as the guaranteed fallback.** Keep the already-proven
attempt-triggered pattern and generalize it. Today `propose_intake` acts as the intake
pack's gate. Extend that: each pack gets a cheap, always-advertised **gate tool** whose
attempt triggers the pack attach, exactly as `#maybeUpgradeToolCatalogue` does now. No new
concept, no new model, no new race — the model itself signals the need, in whatever language
it likes, and the existing ack-before-`response.create` sequencing already works.

Explicitly rejected: Option B in the voice hot path (a second model inference in an 800 ms
budget, for a decision worth fractions of a cent — see §7), and Option A as a *primary*
router (loses the VAD race, and Egyptian-Arabic keyword matching is a permanent maintenance
tax with silent failure modes).

---

## 4. Capability packs

Derived from the code: shared resolver parameters, file boundaries, and the existing staging
split. Token figures are column B (raw JSON) — treat as **relative sizes only**; multiply by
~0.82 for the expected provider-billed figure.

| Pack | Tools | Tools | Σ tok (raw) | Depends on | Keep loaded? | Deterministic from intent? |
|---|---|---:|---:|---|---|---|
| **P0 · Core/identity** (permanent) | `get_user_scope`, `list_customers`, `resolve_customer_flock`, `get_customer_context`, `list_customer_flocks`, `list_customer_hatcheries`, `get_flock_context` | 7 | 396 | — | **Always** | n/a — permanent |
| **P1 · Benchmarks** | `get_breed_benchmark`, `get_egg_breakout_benchmark`, `get_operational_standards`, `compare_selected_audit_to_benchmark` | 4 | 508 | last tool needs P2 selection | Yes | **Yes** — breed/age question, benchmarks screen |
| **P2 · Audit read/report** | `list_customer_audits`, `select_audit_option`, `get_audit_summary`, `get_selected_audit_breakouts` | 4 | 277 | P0 (customerId) | Yes | **Yes** — report/history question, audit screen |
| **P3 · Station records & schema** | `query_station_records`, `compare_station_metrics`, `get_record_provenance`, `list_applicable_stations`, `load_station_schema` | 5 | 842 | P0; `get_record_provenance` needs a `recordId` from `query_station_records` | Yes | Partly |
| **P4 · Intake gate** (permanent) | `propose_intake` | 1 | 51 | P0 | **Always** | n/a — it *is* the gate |
| **P5 · Intake writes** (shipped as staged) | `start_intake`, `record_station_values`, `get_intake_status`, `create_station_summary`, `confirm_station_summary`, `submit_station_for_review`, `pause_intake`, `resume_intake`, `cancel_intake` | 9 | 881 | **P4 must fire first** — every member requires `pendingActionId` or `intakeId` | Yes | Yes — data-entry screen |
| **P6 · Legacy draft** | `list_legacy_draft_questions`, `answer_legacy_draft_question` | 2 | 126 | `submissionId` seeded outside the agent graph | **Drop from Realtime entirely** | n/a |
| | | **32** | **3,081** | | | |

Notes:

- **P5's dependency is structurally enforced**, not merely conventional:
  `test/tool_contract_test.ts:202-227` already asserts every staged tool requires
  `pendingActionId` or `intakeId`. That test is the template for validating any new pack.
- **P6 is the one free win.** Both tools need a `submissionId` that no Realtime-reachable
  tool can produce. `session_config.ts:55-63` already flags them as "probably unreachable"
  and keeps them only because nobody proved it. Prove it, drop them: ~126 raw tokens
  (~105 billed) off every session, zero behaviour change, zero cache cost.
- **P1 and P2 are coupled by policy, not by schema.** `REPORT_VS_BENCHMARK` (3,182 chars)
  exists precisely to stop the model confusing them. Loading one without the other
  re-opens the 2026-08-18 production incident. **Treat P1+P2 as a single indivisible pack.**
- Packs must preserve `AGENT_TOOL_CONTRACT` ordering when concatenated. Never sort a pack
  independently — `session_config.ts:95-98` and `agent_tool_contract.ts:527-530`.

---

## 5. Tool-pack lifecycle

```
1. session starts        →  P0 + P4 + (packs implied by capabilityHint)
2. user speaks           →  provider VAD auto-creates the response
3. gate-tool attempt     →  model calls a pack's gate tool (or a tool it lacks)
4. pack selected         →  union with #activeTools  (ACCUMULATE ONLY)
5. session.update        →  #sendSessionConfig('<pack>_attach', activeTurnDetection)
6. await session.updated →  bounded, 2000 ms, ≤2 attempts (existing constants)
7. tool executes         →  broker; authority re-resolved server-side regardless
8. response completes
9. KEEP. Never unload.
```

Answers to the brief's lifecycle questions:

- **Should packs stay loaded for the rest of the call?** **Yes. Unconditionally.**
- **Unload after each interaction?** **No.** See §8 — every unload is a second cache bust
  that buys back a per-turn saving worth ~1/100th of its cost.
- **Is constant reload worse for caching than it saves?** **Yes, by roughly two orders of
  magnitude.** §8.
- **LRU set of recent packs?** **No.** LRU eviction *is* unloading. An LRU that never
  evicts is just accumulate-only with extra state to get wrong.
- **Simultaneous / overlapping interactions?** `InteractionTracker` already tracks
  concurrent interactions as independent map entries (`src/interaction.ts:92-303`). Pack
  attaches must be **serialized through the existing `#serializeToolOutput` chain** —
  `session.updated` carries no `event_id` echo, so two in-flight updates cannot be told
  apart. One attach in flight at a time; queue the rest.
- **Barge-in while an update is pending?** The user interrupting does not cancel a
  `session.update` — it is session-scoped, not response-scoped. The current code already
  handles this correctly: `#maybeUpgradeToolCatalogue` awaits the ack with a 2 s timeout and
  proceeds regardless, and barge-in only clears *response*-scoped state
  (`#pendingFollowupToolNames`). **Keep exactly this behaviour.** Do not add
  `response.cancel` — barge-in is provider-native here (`interrupt_response: true`) and
  the sideband has deliberately never sent one.

---

## 6. Conversation-context strategy

The brief's four-way separation is **already implemented**, and better than the brief assumes:

| Layer | Where it lives | How it reaches the model | Change needed |
|---|---|---|---|
| Immediate conversational continuity | Provider-side conversation items | Native, within the live session | **None** |
| Working context (selected customer/flock/audit) | `agent_conversations.selected_*` | **Never in the prompt.** Re-resolved server-side inside `get_audit_summary`, `get_selected_audit_breakouts`, `compare_selected_audit_to_benchmark`, `select_audit_option` | **None** |
| Durable history | `agent_conversation_turns`, `finalized` only | 12 turns / 600 chars each / 4,000 total, injected once at bootstrap | **Tune, §6.1** |
| Business data / tool results | `agent_tool_events`, append-only, trigger-protected | Only inside the turn that fetched it. Never replayed | **None** |

Authoritative business data is already kept out of model-authored memory. One residual, in
`src/sideband.ts:41-43`: a replayed prior **assistant** turn is model-authored prose that
could in principle contain an id the model saw in a text-channel tool result. The existing
analysis concludes this is safe because an unadvertised tool is still uncallable and the
broker re-resolves authority anyway — "the worst case is deferred capability, never a way
around the gate." That reasoning survives Phase 2 unchanged (§10). It remains a design
comment, not a test. **Add one** (§13, T-13).

### 6.1 The one context change worth making

"Ross 35 fertility benchmark?" should not carry 4,000 chars of history. But the cost of
being wrong (dropping the context that makes "واللي قبله؟" work) is a user-visible failure,
and the saving is ~1,000 cached tokens ≈ **$0.00006 per turn**. Not worth an NLU gamble.

Instead, use the levers the provider gives us and we currently ignore entirely:

- **`session.truncation.retention_ratio`** — docs: *"Truncation busts the cache near the
  beginning of the conversation... clients can configure truncation to drop more messages
  than necessary."* Default `1.0`. Unused here.
- **`token_limits.post_instructions`** — caps per-response input excluding instructions.
  Unused here.
- **`conversation.item.delete`** — explicit item removal. Unused here.

These matter for **long calls**, where accumulated audio context is re-billed every turn.
That is where the real money is (§7.4) — and it is a completely different problem from
tool-schema size.

---

## 7. Cost model

### 7.1 Prices — `gpt-realtime-2.1-mini`

| | Uncached | Cached | Cached discount |
|---|---:|---:|---:|
| Text input | $0.60 / 1M | **$0.06 / 1M** | 10× |
| Audio input | $10.00 / 1M | **$0.30 / 1M** | 33× |
| Image input | $0.80 / 1M | $0.08 / 1M | 10× |
| Text output | $2.40 / 1M | — | — |
| Audio output | $20.00 / 1M | — | — |

No pricing constants exist anywhere in the repo today. Add them (§12).

### 7.2 The billing shape

Docs: *"The entire conversation is sent to the model for each Response... thus turns later
in the session will be more expensive."* Every turn re-bills the static prefix **plus every
accumulated conversation item**, at cached rates where the prefix matches.

One real production data point exists, pasted verbatim into `test/response_usage_test.ts:6-22`
as `REALISTIC_USAGE`: `input_tokens: 5453`, `cached_tokens: 4864` — **89.2% cached**. It is a
test fixture, not a dated finding, so treat it as indicative. The cache is working well.

### 7.3 Scenario costs — input side, prefix only

Prefix P = 4,620 text tokens today. Turn 1 uncached, turns 2+ cached.

| Scenario | Turns | Prefix cost today | Prefix cost @ P=2,600 | Saving |
|---|---:|---:|---:|---:|
| Minimal startup (no user turn) | 0 | $0 | $0 | $0 |
| Simple chat, no business data | 3 | $0.00305 | $0.00172 | $0.00133 |
| One benchmark lookup (2 model turns) | 2 | $0.00291 | $0.00164 | $0.00127 |
| One report lookup (2 model turns) | 2 | $0.00291 | $0.00164 | $0.00127 |
| Multi-tool interaction (4 model turns) | 4 | $0.00319 | $0.00180 | $0.00139 |
| **10-turn mixed call** | 10 | **$0.00402** | **$0.00227** | **$0.00175** |

**Cutting the prefix nearly in half saves about one sixth of a US cent per ten-minute call.**

### 7.4 The cost of a single cache bust

This is the number that decides the architecture. Assumption-light form:

- Saving from removing Δ prefix tokens, per cached turn: `Δ × $0.06/1M`.
- Cost of busting the cache on one turn: everything before the change re-bills uncached.
  - text delta: `$0.60 − $0.06 = $0.54 / 1M` → **9× the saving rate**
  - audio delta: `$10.00 − $0.30 = $9.70 / 1M` → **162× the saving rate**

> **Busting the cache on 1 accumulated audio token costs as much as saving 162 prefix tokens
> for one turn.**

Worked: a mid-call swap at turn 5 of a call carrying 3,000 accumulated audio tokens costs
`3,000 × $9.70/1M + 2,600 × $0.54/1M ≈ $0.0305`. The *entire* prefix saving for the whole
10-turn call is $0.00175. **One swap costs ~17× the total saving of the call it happens in.**
Swapping per interaction (5 swaps) costs ~$0.15 against $0.00175 saved — an ~85× net loss.

By contrast, an attach applied to the **initial** `session.update` costs nothing at all,
because nothing is cached yet. This is the whole basis of the §3.2 recommendation.

### 7.5 Router inference and round-trip costs

- Option A′: **$0, 0 ms.**
- Option C gate tool: ~60 permanent prefix tokens ≈ $0.0000036/turn cached. Negligible in
  dollars. The cost is **latency** (§9), not money.
- Option B (`gpt-5-nano` classifier): a second inference per turn plus a second failure
  surface, to arbitrate a decision worth ~$0.0002. **Not justifiable.**
- `session.update` frame itself: not billed as tokens; its cost is the ack round trip and
  the cache bust it causes.

### 7.6 What actually binds

Dollars do not. **Throughput does.** The Phase 1 changelog says it plainly: 5,909 → 4,620
raised the ceiling under the account's **40k TPM cap from 6.8 to 8.7 inferences per minute.**
Rate limits count tokens regardless of cache status, so prefix reduction buys real
concurrency headroom while cache status buys the dollars.

This splits the objectives cleanly, and they point opposite ways:

- **For TPM headroom**: smaller prefix is good. Mid-call swaps are neutral (same token count).
- **For dollars**: prefix size is nearly irrelevant. Mid-call swaps are actively harmful.

**Therefore the highest-leverage action in this entire document is not an architecture
change: it is asking OpenAI to raise the 40k TPM cap.** That is a support request. It costs
nothing, risks nothing, and removes the only constraint that Phase 2 was going to fight.

---

## 8. Prompt-caching analysis

Provider guidance, verbatim (realtime costs guide):

> *"The best strategy for maximizing cache rate is keep a session's history static. Removing
> or changing content in the conversation will 'bust' the cache up to the point of the
> change — the input no longer matches as much as before. Note that instructions and tool
> definitions are at the beginning of a conversation, thus changing these mid-session will
> reduce the cache rate for subsequent turns."*

So: **yes**, the tools array participates in the cached prefix; **yes**, changing it
invalidates from that point; **yes**, repeated `session.update` is counterproductive. The
codebase already independently reached this conclusion —
`session_config.ts:95-98` refuses to resort `core` because "OpenAI's prompt cache keys on the
`tools` array verbatim", and `LIVING_SPEC.md:3721-3724` records that the shipped intake
upgrade "costs one cache miss and leaves that session on the larger 32-tool prefix
(5,243 tokens/turn measured) for the rest of the call."

| Strategy | Cache behaviour | 10-turn call, net vs today |
|---|---|---|
| **1 — swap every interaction** | Bust per swap; cache never warms | **−$0.15** (85× worse) |
| **2 — attach once, keep for the call** | One bust, at attach time | **−$0.03** if attached mid-call; **+$0.0018** if attached at bootstrap |
| **3 — accumulate packs, never unload** | One bust per distinct pack, bounded by pack count | **+$0.0018 − ($0.03 × mid-call attaches)** |

**Recommended: Strategy 3, with attaches pushed as early as possible — ideally into the
initial `session.update`, where a "bust" is free.** That is exactly A′ + C: pre-select from
client context at bootstrap (free), fall back to gate-tool attach when the user surprises us
(one bounded bust, kept for the rest of the call).

Strategy 1 is a **hard No-Go**. Unloading is a No-Go. LRU eviction is a No-Go.

---

## 9. Latency impact

| Path | Added latency | Notes |
|---|---|---|
| A′ pre-selection at bootstrap | **0 ms** | Folded into the existing initial `session.update` |
| Gate-tool attach (Option C) | **+1 model turn, ~500–1500 ms** | Model must call the gate, get a result, then answer |
| `session.update` + `session.updated` ack | ~50–200 ms typical; **2,000 ms worst case** | `INTAKE_UPGRADE_ACK_TIMEOUT_MS` |
| Deterministic transcript router (A) | Racing VAD; needs `create_response:false` | Would add a round trip to **every** turn |
| `gpt-5-nano` classifier (B) | **+300–900 ms** on every turn | Plus a second failure surface |

Voice UX budget to first audio is ~800 ms. A′ spends none of it. C spends a full turn, but
only on the transition, and only when pre-selection missed — which is the same trade the
shipped intake upgrade already makes and which canaries already pass.

---

## 10. Security implications

Audited end-to-end. **Dynamic tool loading cannot weaken authorization, and no code path
currently treats tool visibility as a permission gate.**

1. **Visibility ≠ permission.** `executeAgentTool` validates every call against
   `AGENT_TOOL_DEFINITIONS` — a static in-module registry — with the comment
   *"regardless of what was ever shown to a model"* (`agent_tools.ts:80-85`). The
   model-facing projection is explicitly *"NEVER what `executeAgentTool` validates against."*
2. **The authorization fingerprint does not hash the tool list.** Its inputs are exactly
   `staffLinkId`, `accessRole`, `allowedCustomerIds`, `profileRole`, `profileStatus`
   (`fingerprint.ts:36-43`). A catalogue change cannot perturb or invalidate it. Verified at
   all three call sites (provisioner, broker, sideband parity copy).
3. **Scope stays server-side and authoritative.** The broker re-resolves scope from
   `profiles`/`auditor_customers` on every call and requires three-way fingerprint agreement
   (recomputed == stamped-at-provisioning == presented-by-caller), refusing with
   `authorization_changed` on any mismatch (`pip-realtime-tool-broker/index.ts:299-343`).
   `enforceArgumentScope` → `assertCustomerAllowed` runs unconditionally.
4. **A model cannot request capabilities the user may not execute.** Loading a pack changes
   only what the model may *attempt*. Every attempt still passes the same DB-anchored gate.
5. **RBAC cannot be bypassed** because routing touches nothing in the RBAC path.
6. **Evidence is unchanged.** `agent_tool_events` stays append-only, enforced by the
   `chickmark_private.protect_agent_tool_event()` trigger which raises on UPDATE/DELETE.

**The one mistake to avoid** (currently not made anywhere): do not let any new pack loader
introduce a check like *"only execute tools present in `session.advertised_tools`"* as a
gate. That would conflate visibility with authorization and bypass the DB-anchored scope
check. `executeAgentTool`'s registry lookup plus `enforceArgumentScope` must remain the sole
authority; an advertised-tools list is prompt shaping only. Pin this with a test (§13, T-11).

---

## 11. Failure handling

The absolute rule: the user must never hear a technical error, and must never hear a
fabricated answer. Existing policy sections `EVIDENCE_AND_SCOPE_VOICE` and `TOOL_RESULT_SCOPE`
already enforce the second; canaries `missing-benchmark`, `missing-metric-value`,
`shaped-null-metric` already guard it.

| Failure | Behaviour |
|---|---|
| **Router uncertain** | Do nothing. Keep the current catalogue. The gate-tool path (C) remains available. Never guess a pack. |
| **Wrong pack loaded** | Harmless — accumulate-only means the right pack can still be added. Costs one extra bust, no correctness impact. |
| **Required tool absent** | Model attempts the gate tool → attach → retry. If the model instead answers without data, the policy's no-invention rules and the `missing-*` canaries catch it. Never surface "tool not loaded" to the user. |
| **Catalogue update rejected** | **Most dangerous case.** A rejected `session.update` is dropped **whole** — the session reverts to default VAD and no tools. Mitigation: (a) validate every pack payload against `readToolDefinitions`' shape rules *before* sending; (b) on a rejection, immediately re-send the last-known-good full config, exactly as `#vadFallbackAttempted` does today; (c) never send an unproven field alongside a pack change. |
| **Update timeout** | Existing behaviour is correct: 2,000 ms bounded wait, ≤2 attempts, proceed regardless, log `sideband.*_ack_timeout`. Do not extend the timeout — a slow ack must not stall a live call. |
| **User changes subject mid-update** | Nothing to do. Updates are session-scoped, not response-scoped. Barge-in clears only response-scoped state. |
| **Tool call before ack** | The provider decides when to run inference; the sideband cannot prevent this. The existing protection is the right one: `ToolCallCoordinator`'s liveness check (`claims.ts:165-183`) plus a broker that re-resolves authority. A pre-ack call simply uses the old catalogue — degraded, never unsafe. |
| **Multiple packs needed** | Union them into one `session.update`. One bust, not N. Serialize through `#serializeToolOutput`. |
| **Malformed router classification** | Reject at the boundary — an unknown `capabilityHint` maps to the default core. Never let an unrecognized string select an empty or partial catalogue. |

---

## 12. Required code changes by file / component

Phased so each phase ships and is measurable on its own.

### Phase 2.0 — measure before building (no behaviour change)

| File | Change |
|---|---|
| `services/pip-realtime-sideband/tools/probe_token_cost.ts` | Add `cachedPct = cached/input` to `Row` and to the markdown table (`:168-175`, `:392-399`). Add a `mid-session-upgrade` scenario: connect core-only → turn → `session.update` full → turn → report the delta. This is the only way to reproduce the `5,243` figure, which no committed file currently derives. |
| new: `services/pip-realtime-sideband/src/pricing.ts` | The §7.1 table as constants, with a source URL and a date. Nothing in the repo has prices today. |
| new: `supabase/migrations/*_realtime_usage_views.sql` | A `service_role` view over `agent_realtime_response_usage` reporting per-session cache-hit rate, text/audio split, and per-turn input growth. The data is already there. |
| `docs/PIP_REALTIME_DEPLOYMENT.md` | Document the TPM-cap-increase request as a prerequisite. |

### Phase 2.1 — free wins (no routing, no new bust)

| File | Change |
|---|---|
| `src/session_config.ts` | Add `UNREACHABLE_TOOL_NAMES = ['list_legacy_draft_questions','answer_legacy_draft_question']`, excluded from the Realtime catalogue entirely. ~105 billed tokens off every session, zero behaviour change. |
| `test/tool_contract_test.ts` | Prove unreachability structurally: assert no Realtime-reachable tool can produce a `submissionId` — the same shape as the existing `pendingActionId`/`intakeId` assertion at `:202-227`. |
| `evals/README.md` | Fix the stale "seven scenarios" line — there are 20. |

### Phase 2.2 — packs + bootstrap pre-selection (the actual Phase 2)

| File | Change |
|---|---|
| `src/session_config.ts` | Generalize `INTAKE_STAGED_TOOL_NAMES` / `partitionToolCatalogue` into a `CAPABILITY_PACKS` registry (§4). Preserve `AGENT_TOOL_CONTRACT` order on every concatenation — never sort. Add `resolvePacks(hint, alwaysOn)` returning a deterministic, order-stable tool list. |
| `supabase/functions/pip-realtime-session/index.ts` | Accept an optional `capabilityHint` on `start`. Validate against a closed enum; unknown → default. Persist on `agent_realtime_sessions` for telemetry. |
| `supabase/functions/pip-realtime-session/config.ts` | Enum of valid hints. |
| `services/pip-realtime-sideband/src/server.ts` | Read the hint from the session row at `bind`. |
| `src/sideband.ts` | Seed `#activeTools` from `resolvePacks(hint)` instead of `#coreTools`. Generalize `#maybeUpgradeToolCatalogue` from the hardcoded `propose_intake` check into a `gateToolName → packId` map. Add the new `source` literals to `#sendSessionConfig`'s union (`:862`). Keep: full-list-not-delta, await-ack-before-`response.create`, ≤2 attempts, one-way accumulate. |
| ChickMark Flutter app (`lib/features/chat/…`) | Pass the current screen as the hint when starting a Live session. |
| `tools/render_tool_definitions.ts` | Emit pack membership metadata. **Watch the env budget — 31,146 / 32,768 bytes, 95% used.** If it does not fit, derive packs from names in code rather than shipping metadata; do not grow the env. |

### Phase 2.3 — conditional, only if 2.0 data justifies it

| File | Change |
|---|---|
| `src/session_config.ts` | Set `truncation.retention_ratio` and `token_limits.post_instructions` for long calls. Probe first — an unproven field can get the whole `session.update` rejected. |
| `agent_prompt.ts` | Split `NATURAL_DATA_ENTRY` / `BENCHMARK_DISCIPLINE` / `REPORT_VS_BENCHMARK` into pack-attached policy fragments. **High risk** — these are canary-load-bearing, and `REPORT_VS_BENCHMARK` exists because of a real production incident. Do this last, or not at all. |

### Untouched by design

`executeAgentTool`, the broker's authorization chain, `fingerprint.ts`, `argument_hash.ts`,
evidence writes, `InteractionTracker`, `ToolCallCoordinator`, `lease.ts`, barge-in handling,
conversation persistence.

---

## 13. Tests and canaries

Deterministic (Deno, no API key) unless marked **[live]**.

| # | Test | Where |
|---|---|---|
| T-01 | Re-measure the fresh-session baseline against policy v2.3.0; assert the recorded figure matches the deployed revision **[live]** | `tools/probe_token_cost.ts --scenario=fresh-hi` |
| T-02 | Probe: does `tools: []` + `tool_choice:'auto'` ack or error? **[live]** | extend `tools/probe_session_knobs.ts` |
| T-03 | Probe: token delta of a mid-session `session.update` **[live]** | new `probe_token_cost.ts` scenario |
| T-04 | Session starts with the minimal catalogue for each hint; unknown hint → default core | `test/tool_contract_test.ts` |
| T-05 | Benchmark hint attaches P1+P2 together, never P1 alone | `test/tool_contract_test.ts` |
| T-06 | Report hint attaches P2 (+P1) | `test/tool_contract_test.ts` |
| T-07 | Gate-tool attempt sends exactly one `session.update`, carrying the full list, **before** the follow-up `response.create` (mirrors the existing intake-upgrade test) | `test/sideband_test.ts` |
| T-08 | A pack is never unloaded; `#activeTools` grows monotonically across a session | `test/sideband_test.ts` |
| T-09 | Two packs needed in one turn → one `session.update`, not two | `test/sideband_test.ts` |
| T-10 | A rejected pack `session.update` re-sends the last-known-good config and does not leave the session tool-less | `test/sideband_test.ts` |
| T-11 | **Security**: a tool absent from `#activeTools` is still rejected by scope, not by visibility — and a tool present in `#activeTools` but out of scope is still refused `scope_denied` | `pip-realtime-tool-broker/index_test.ts` |
| T-12 | Ack timeout → bounded wait, ≤2 attempts, session survives, call continues | `test/sideband_test.ts` |
| T-13 | Injected assistant history never causes an out-of-scope tool to execute (closes the §6 open design comment) | `test/conversation_integrity_test.ts` |
| T-14 | Barge-in during a pending pack update: response-scoped state clears, session config does not | `test/sideband_test.ts` + `test/continuation_test.ts` |
| T-15 | Order stability: any pack union equals `AGENT_TOOL_CONTRACT` order filtered — never resorted | `test/tool_contract_test.ts` |
| T-16 | Env payload stays under the 32,768-byte Cloud Run cap | `test/config_test.ts` |
| T-17 | **[live]** Arabic intent routing: `الإنتاج المفروض كام في Ross 35؟` reaches `get_breed_benchmark` | `evals/run_canaries.ts` |
| T-18 | **[live]** Arabic report routing: `آخر تقرير breakout للعميل X` reaches `list_customer_audits`, **not** `get_egg_breakout_benchmark` (this is the existing `breakout-report-not-benchmark` canary — re-run under packs) | `evals/run_canaries.ts` |
| T-19 | **[live]** Mixed Arabic/English and unparroted phrasing still route correctly (re-run `report-unparroted-phrasing`) | `evals/run_canaries.ts` |
| T-20 | **[live]** Topic switch mid-call attaches the new pack and answers correctly | `evals/run_canaries.ts` |
| T-21 | **[live]** No regression in answer scope — all 20 existing canaries pass unchanged | `evals/run_canaries.ts` |

**Gate: all 20 existing canaries must pass before and after.** They are the only thing
standing between this work and the 2026-08-18 report-vs-benchmark incident.

Commands:

```bash
cd services/pip-realtime-sideband && deno test -A
cd supabase/functions/telegram-hatchery-agent && deno test -A
cd supabase/functions/app-hatchery-agent && deno test -A
```

```bash
export OPENAI_API_KEY="$(gcloud secrets versions access latest --secret=openai-api-key --project=chickmark-ai-agent)"
cd services/pip-realtime-sideband && deno run --allow-net --allow-env --allow-read evals/run_canaries.ts
```

---

## 14. Migration / deployment plan

Deploy order is **edge-first**, per the shipped Harness v2 recipe.

1. **Phase 2.0** — probes, pricing constants, usage view. No behaviour change. Query 30 days
   of `agent_realtime_response_usage` and answer: real cache-hit rate, audio/text split,
   per-turn input growth, and how often TPM is actually the binding constraint.
   **Verify the table has rows** — the `interaction_id` migration was once committed but not
   applied, and every insert 400'd while the table sat empty in production.
2. **Request the TPM cap increase.** If granted, re-evaluate whether 2.2 is worth building
   at all.
3. **Phase 2.1** — drop P6, fix the stale eval doc. Deploy. Re-run `probe_token_cost`. Expect
   a small, provable drop with zero behaviour change.
4. **Phase 2.2** — packs behind a config flag (`PIP_REALTIME_CAPABILITY_PACKS=off|on`),
   defaulting **off**. Deploy the sideband with the flag off; confirm byte-identical
   behaviour. Then: migration → edge functions → sideband → app. Turn the flag on for one
   revision, run the full canary suite live, compare `agent_realtime_response_usage` before
   and after.
5. **Rollback** is a flag flip plus a Cloud Run revision rollback. Keep the previous revision
   warm for a full day.
6. **Docs** — every phase updates `docs/LIVING_SPEC.md` (current behaviour) and adds a dated
   `docs/CHANGELOG.md` entry, per the repo rule.

---

## 15. Risks and open decisions

### Risks

| Risk | Severity | Mitigation |
|---|---|---|
| A rejected `session.update` leaves the session with default VAD and no tools | **High** | Validate before send; re-send last-known-good on rejection; never bundle unproven fields with a pack change (T-10) |
| Splitting P1 from P2 re-opens the 2026-08-18 report-vs-benchmark incident | **High** | Treat P1+P2 as indivisible; T-18/T-19 are blocking |
| Mid-call attaches cost more than the whole optimization saves | **High** | Bootstrap pre-selection (A′); accumulate-only; never unload |
| Splitting the policy into pack fragments breaks canaries | **High** | Deferred to 2.3; may be dropped entirely |
| Env payload already at 95% of the Cloud Run cap | Medium | Derive packs from names in code; do not ship pack metadata in env (T-16) |
| The 2,620-token policy figure predates v2.3.0 | Medium | T-01 before anything else |
| Concurrent `session.update`s are not individually attributable (no `event_id` echo on success) | Medium | Serialize attaches; one in flight at a time |
| `capabilityHint` misroutes because the user opened Pip from an unrelated screen | Low | Accumulate-only makes this self-healing; gate tools are the fallback |

### Open decisions — your call

1. **Is the binding constraint dollars or TPM?** The whole justification hinges on this, and
   30 days of `agent_realtime_response_usage` answers it. If dollars: build almost none of
   this and go after audio-context management instead. If TPM: request the cap increase
   first, then build 2.2 only if the increase is refused.
2. **Ship `capabilityHint` from the app?** It is the single highest-value, lowest-risk
   mechanism here, but it needs a small Flutter change and it means the app's navigation
   state becomes an input to model configuration.
3. **Drop P6 (legacy draft tools) from Realtime?** Free, but it makes "probably unreachable"
   into a shipped assumption. T-11's structural proof should settle it.
4. **Touch the policy at all?** §12 Phase 2.3 is where the biggest single reduction lives
   (~45% of the instruction budget is pack-attachable) and also where all the canary risk
   lives. My recommendation is **no**, at least until 2.0/2.1/2.2 have shipped and been
   measured.
5. **A second model in the voice hot path?** Option B needs an explicit provider/model
   decision and is a standing "ask first" area. My recommendation is **no**.

---

## Go / No-Go

**GO** on Phase 2.0 (measurement, pricing constants, usage view) and Phase 2.1 (drop the
unreachable legacy pack) — cheap, safe, provable, no cache cost.

**GO** on requesting an OpenAI TPM cap increase. Highest leverage action in this document.

**CONDITIONAL GO** on Phase 2.2 (capability packs + bootstrap pre-selection + generalized
gate-tool attach, accumulate-only) — only if the Phase 2.0 data shows TPM is genuinely
binding, and only behind a default-off flag.

**NO-GO** on the aggressive form in the brief: minimal-core-plus-swap-per-interaction,
unloading, and LRU eviction. The provider's own cost guidance and the pricing arithmetic
both say it costs roughly **85× more than it saves**. The cheapest architecture is not the
one with the smallest instantaneous context — it is the one with the most stable prefix.

**NO-GO** on a second routing model in the voice hot path (Option B), and on a transcript
keyword router as the primary mechanism (Option A) — it races the provider's VAD and carries
a permanent Egyptian-Arabic maintenance tax with silent failure modes.
