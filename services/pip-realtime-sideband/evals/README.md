# Pip Realtime conversation-behavior evals

Scripted, realistic conversations run against the **real model**, over the real
OpenAI Realtime WebSocket, in **text mode** — asserting behavioral budgets (word
counts, tool discipline, forbidden phrasing, benchmark discipline) against the
model's actual replies.

This is **not** part of `deno test`. It costs money (real API calls against
`gpt-realtime-2.1-mini`) and is meant to be run on demand, typically after a
change to the shared policy (`agent_prompt.ts`, rendered here by
`tools/render_agent_instructions.ts`) or the tool contract
(`agent_tool_contract.ts`, rendered by `tools/render_tool_definitions.ts`).

## Running it

```bash
export OPENAI_API_KEY="$(gcloud secrets versions access latest \
  --secret=openai-api-key --project=chickmark-ai-agent)"

cd services/pip-realtime-sideband
deno run --allow-net --allow-env evals/run_evals.ts
```

Options:

- `--filter <substring>` — only run scenarios (or derived/aggregate checks)
  whose id or title contains the substring. Case-insensitive.
- `--debug` — logs any Realtime event type this runner hasn't seen before
  (see `KNOWN_EVENT_TYPES` in `run_evals.ts`), so a wire-shape change is
  visible immediately instead of silently ignored.

The key is read from `OPENAI_API_KEY` only, is never logged, and is never
echoed anywhere in the output. It is **not** the secret name assumed
elsewhere in older notes (`pip-openai-key`) — the actual secret in the
`chickmark-ai-agent` project is named `openai-api-key`; verify with
`gcloud secrets list --project=chickmark-ai-agent` if this ever drifts.

Exit code is non-zero if any scenario assertion, derived check, or aggregate
check fails, so this can be wired into a manual release gate later without
further changes.

## What gets loaded, and why dynamically

`run_evals.ts` imports both the instructions renderer and the tool-definition
renderer with a **dynamic** `await import(...)` inside `main()`, not a static
top-of-file import:

- `tools/render_agent_instructions.ts` exports the shared ChickMark policy
  (`CHICKMARK_AGENT_POLICY` from `agent_prompt.ts`) plus the voice addendum.
  This file is a natural point of change for the realtime policy, so the
  dynamic import means this suite always exercises whatever that module
  currently exports at the moment `run_evals.ts` runs — it never risks going
  stale against a cached static import, and it never fails to parse just
  because that file is mid-edit in a concurrent branch. The loader looks for
  `renderRealtimeInstructions` first and falls back to a couple of plausible
  alternate names (`renderRealtimePolicy`, `renderInstructions`) so a rename
  doesn't silently break this suite either — see `loadInstructions()`.
- `tools/render_tool_definitions.ts` exports `renderRealtimeToolDefinitions()`,
  which renders the full, real `AGENT_TOOL_CONTRACT` (currently 32 tools) in
  the flat Realtime shape. If that export ever disappears, `loadTools()` falls
  back to a minimal hand-written subset (`resolve_customer_flock`,
  `get_breed_benchmark`, `list_customer_flocks`) matching the real schemas in
  `agent_tool_contract.ts`, and logs a warning that it did so.

Nothing in `evals/` hand-invents a tool name. Every stubbed tool call name in
`scenarios.ts` was taken from `agent_tool_contract.ts` after reading it.

## Wire mechanics

Verified directly against the live endpoint before this suite was written
(see the probes referenced in commit history / session notes, and
`WIRE_CONTRACT.md` / `src/sideband.ts` for the sibling production transport):

- `wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1-mini`, via `npm:ws`,
  header `Authorization: Bearer <key>`, **no subprotocols**.
- `session.update` with
  `{type:'realtime', output_modalities:['text'], instructions, tools, tool_choice:'auto'}`.
  Text modality avoids audio entirely — no `audio` block is sent.
- A user turn is `conversation.item.create` with
  `{type:'message', role:'user', content:[{type:'input_text', text}]}`,
  followed by `response.create`.
- The runner does not stream `response.output_text.delta` — `response.done`
  already carries the complete `response.output[]`, which is simpler and
  sufficient for scripted, non-interactive assertions.
- A tool call arrives as a `response.output[]` entry with
  `type: 'function_call'` (`name`, `call_id`, `arguments`). The runner replies
  with `conversation.item.create`
  `{type:'function_call_output', call_id, output}` (the scripted stub, JSON
  stringified) then `response.create` again, looping until a round comes back
  with no more tool calls (capped at `MAX_TOOL_ROUNDS = 6`).

## A real, observed transport hiccup — and how the runner handles it

Running many fresh Realtime sessions back-to-back on this account/project hits
a live throttling behavior: `response.done.response.output` itself comes back
`[]` (verified directly on the wire, not a parsing bug — see the doc comment
on `awaitResponseWithRetry` in `run_evals.ts`), typically starting somewhere
around the 6th–8th rapid successive session.

The runner handles this two ways:

1. `awaitResponseWithRetry` retries `response.create` (never resending the
   user message or a tool output, so it's always side-effect-free) up to
   `MAX_EMPTY_RETRIES = 3` times with a linear backoff (4s, 8s, 12s).
2. `INTER_SCENARIO_DELAY_MS = 4000` — a pause between scenarios (each of
   which opens a fresh session) to reduce how often the hiccup happens at
   all.
3. Even so, if a reply still comes back empty after every retry, an empty
   string would trivially satisfy `maxWords`/`mustNotMatch` — silently
   misreporting a transport failure as a behavioral pass. To avoid that, every
   turn gets an automatic extra row, **`providerReturnedContent`**, asserting
   the final reply is non-empty. If you see that fail, the scenario's other
   assertions for that turn are not meaningful signal — re-run (ideally with
   `--filter`, alone) rather than trusting the number.

A one-off connection failure (DNS/TLS blip before the socket even opens) is
reported as a `transport` row rather than a scenario assertion — also not
behavioral signal, just re-run.

## Scenarios

Each row maps a task-spec item number to what's actually implemented. Several
spec items are combined into one scripted session where the spec explicitly
continues a prior transcript (2+3), reuses another scenario's transcript
without a second connection (11), or aggregates across everything collected
(13):

| Spec # | Scenario id                    | What it tests                                                                              |
| ------ | ------------------------------- | -------------------------------------------------------------------------------------------- |
| 1      | `casual`                        | Casual small talk stays short and doesn't slide into assistant-boilerplate.                  |
| 2, 3   | `direct-count-and-followup`     | A direct count question resolves the named customer and answers briefly; a same-session follow-up keeps context instead of re-asking who the customer is. |
| 4      | `progressive-performance`       | A vague "how's performance" gets a short scoping reply; "why?" is allowed to run longer.     |
| 5      | `no-tool-no-invent`             | An unresolvable customer name never gets an invented percentage — the model says it can't find it. |
| 6      | `benchmark-authoritative`       | A breed benchmark figure is quoted from `get_breed_benchmark`, not stated from memory.        |
| 7      | `benchmark-missing`             | An out-of-range week never gets an interpolated/extrapolated benchmark.                       |
| 8      | `general-knowledge`             | General husbandry knowledge (egg-storage effects) is answered directly, with no tool call.    |
| 9      | `inference-language`            | A causal question with only correlational evidence gets hedged language, not asserted fact.   |
| 10     | `verbosity-guard`               | A direct factual "when was the last audit" question gets a short answer, no unsolicited advice. |
| 11     | `no-preamble` (derived)         | Reuses scenario 2's transcript — no assistant text appears before the first tool call in that response. Does **not** open a second session. |
| 12     | `mixed-code`                    | A mixed Arabic/English request (`قارن آخر audit بالـbenchmark`) triggers `compare_selected_audit_to_benchmark` and cites the returned numbers. |
| 13     | `stock-phrases` (aggregate)     | No stock filler phrases (`بالتأكيد`, `يسعدني`, `سؤال رائع`, `دعني أوضح`) across every reply collected in the run. |
| 14     | `action-confirmation`           | See adaptation note below — a field-observation request gets a confirming question rather than a silent write. |

### Adaptation: `action-confirmation` (spec #14)

`AGENT_TOOL_CONTRACT` (`agent_tool_contract.ts`) has **no** note/observation
tool — there is nothing named anything like `record_note` or
`log_observation`. Per the task's own fallback instruction, this scenario is
adapted to the nearest real tool, `propose_intake`, which is scripted as an
available stub. The assertion only requires the reply to ask one confirming
question (a `؟`/`?`, within a short word budget) — it does not require
`propose_intake` to actually be called, since the policy may reasonably ask
for customer/hatchery/machine context first instead of proposing an intake
immediately.

### Default bootstrap stubs

`scenarios.ts` exports `DEFAULT_TOOL_STUBS` — fallback stubs for
`get_user_scope` and `list_customers`, applied under (never overriding) each
scenario's own `toolStubs`. Without them, several scenarios failed for a
reason that had nothing to do with the behavior being tested: the bare
`renderRealtimeInstructions()` policy (unlike production's
`buildAgentInstructions`) carries no "trusted server context", so a
scope-blind model reasonably calls `get_user_scope`/`list_customers` to
bootstrap before doing anything else. Any tool call with no matching stub
anywhere still gets a synthetic `{ok:false, code:'unstubbed_in_eval', ...}`
rather than hanging the session.

## Assertion helpers (`scenarios.ts`)

- `maxWords(n)` — whitespace-split word count of the **final** reply (the
  last round's message text) is at most `n`. Arabic words are space-separated
  like any other language, so no special counting is needed.
- `mustMatchAny([...])` — at least one pattern must match the final reply.
- `mustNotMatch(pattern | [...])` — no pattern may match the final reply.
- `toolCalled(name)` — the named tool was called at some point during the
  turn (including through an earlier round).
- `noToolCall()` — no tool was called at all during the turn.
- `toolCalledBefore()` — in the round containing the first tool call, no
  assistant message text appeared ahead of that `function_call` item in the
  response's own output order (i.e. no "let me check that for you" preamble).

## Interpreting a failure

Per the task this suite was built for: **a failing assertion is signal about
the current policy, not a bug in the runner**, unless it's a `transport` row
or a `providerReturnedContent` failure (both are infrastructure noise — see
above). Read the actual reply text printed under each `DETAIL` entry before
concluding anything; the assertion label alone won't tell you whether the
model was close or wildly off.

## run_canaries.ts — the production-path gate

`run_evals.ts` above talks to the model in TEXT modality. That is NOT
sufficient evidence about Pip Live: on 2026-08-18 the text suite was green
while the phone still produced canned assistant greetings and multi-question
clarification paragraphs — and the failures reproduced immediately once the
session was configured the way production configures it. gpt-realtime-2.1-mini
follows the brevity rules differently in audio mode.

`run_canaries.ts` therefore sends the EXACT production `session.update` —
built by the same `buildSessionUpdate` the sideband runtime uses (audio output
modality, reasoning effort, semantic VAD, transcription block) — and asserts
on the audio transcript of what the model speaks. User turns are typed text
(synthesizing caller audio isn't practical here); that remaining gap biases
the model TOWARD text-register verbosity, so a canary pass is believable for
voice brevity.

Run it the same way (needs `OPENAI_API_KEY`):

    deno run --allow-net --allow-env --allow-read evals/run_canaries.ts
    # optional: --filter greeting   --effort medium (A/B reasoning effort)

Order of operations for behavior work: canaries FIRST (seven scenarios, a few
thousand tokens), the 47-case text suite only as the final regression tail.
Expect some run-to-run variance from the live model; a canary that fails once
on a borderline word count is noise, a canary that fails the same way twice is
signal.
