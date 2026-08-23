# Text-agent model-acceptance harness

Talks to REAL OpenRouter models using our REAL agent request shape, so we can
decide whether a candidate model (e.g. `google/gemma-4-31b-it:free`, with
`openai/gpt-oss-20b:free` as fallback) is fit to be the ChickMark text-agent
model. This is **not** part of `deno test` — it costs money (real OpenRouter
calls) and is meant to be run on demand, typically when deciding on or changing
the text-agent model.

It is modeled on `services/pip-realtime-sideband/evals/` (read that directory's
own README for the house style this follows): scenario data separate from the
runner, one assertion per behavioral claim, a scorecard, and the same "this is
not `deno test`" discipline. The difference is the transport: the Realtime
harness drives a WebSocket; this harness drives OpenRouter's `/v1/responses`
REST endpoint, because that is what the production text agent
(`agent_provider.ts` / `agent_runtime.ts`) actually uses.

## What gets exercised — the REAL shape, not a re-declaration

- **Tool catalogue**: `AGENT_MODEL_TOOL_DEFINITIONS`, imported directly from
  `../../telegram-hatchery-agent/agent_tools.ts` — the exact constant
  `agent_runtime.ts` sends on every provider call.
- **System prompt**: `buildAgentInstructions`, imported directly from
  `../../telegram-hatchery-agent/agent_prompt.ts` — the exact function
  `agent_runtime.ts` calls to build `instructions`.
- **Request body**: `POST https://openrouter.ai/api/v1/responses`,
  `Authorization: Bearer <OPENROUTER_API_KEY>`, body
  `{model, instructions, input, tools (each with strict:false), tool_choice,
  parallel_tool_calls:false, max_output_tokens:2400, store:false}`
  — copied field-for-field from `createResponsesAgentProvider`'s `send()` in
  `../../telegram-hatchery-agent/agent_provider.ts`. Determinism knobs
  (`temperature`, `seed`, `reasoning_effort`) are layered on top; production
  does not set them (see "Determinism / cost" below).
- **Multi-round loop**: the model's own `output` items are pushed back into
  `input` verbatim, then a `function_call_output` is appended for every
  `function_call`, then the request is sent again — the same shape
  `runAgentTurn` uses in `agent_runtime.ts`. Tool rounds are capped at the same
  `MAX_AGENT_TOOL_CALLS_PER_TURN` (5) the runtime uses, and a turn that spends
  its whole budget gets one final `tool_choice:'none'` pass, matching the
  runtime's forced-final behavior.

All of this transport and loop logic lives in `agent_client.ts`, shared by both
entry points below. Nothing in `evals/` hand-invents a tool name or a
tool-result shape — every tool stub's shape was taken from `agent_read_tools.ts`
and `bmk_tools.ts` after reading them.

### On the `/v1/responses` endpoint itself

Both `/api/v1/responses` and `/api/v1/chat/completions` exist on OpenRouter.
This harness only ever calls `/v1/responses`, because that is what production
calls. If a candidate model's account/route rejects that endpoint outright —
observably, a `404`, or a `400` whose body names the request shape itself rather
than a specific bad argument — `agent_client.ts`'s `describeHttpFailure` labels
it `architecture` rather than a plain scenario failure, and BOTH `run_probe.ts`
and `run_evals.ts` print a loud `ARCHITECTURE FINDING` block and exit non-zero.
That is meant to be impossible to miss in the output: if `/v1/responses` doesn't
work for a given model, that is a blocking finding about the model/endpoint
pairing, not something to silently route around.

## Two entry points

### `run_probe.ts` — tool-calling compatibility probe

Fast, cheap, answers "can this model drive our agent at all?" — one check per
capability:

1. **system/instruction handling** — a directive placed in `instructions` (never
   in a user message) asks every reply to end with a fixed marker token; the
   check looks for that literal marker in the reply.
2. **function/tool definitions** — given a task that needs a lookup, does the
   model emit a well-formed `function_call` (a known tool name, non-empty
   `arguments`) at all?
3. **multiple sequential tool calls** — a task that needs
   `resolve_customer_flock` then, using the id it returns,
   `list_customer_flocks` with that id.
4. **tool result → synthesis** — after a tool result, does the model produce a
   final text answer grounded in the stubbed value (not a re-call, not an
   invented number)?
5. **structured arguments** — are the emitted `arguments` valid JSON matching
   the tool's declared parameter schema (required fields present, correct types,
   no invented fields)? Checked mechanically via `validateToolArguments` (in
   `agent_client.ts`) against the REAL schema in `AGENT_TOOL_CONTRACT`, not by
   eyeballing the JSON.
6. **Arabic / Egyptian Arabic** — an Arabic prompt resolves the correct tool AND
   gets an Arabic reply.
7. **multi-turn context** — a fact established in turn 1 (a resolved customer)
   is used correctly in turn 3, across an unrelated turn 2, without re-asking
   who the customer is.

Run it:

```bash
export OPENROUTER_API_KEY="..."   # or place it in the repo's gitignored .env
deno run --allow-net --allow-env --allow-read evals/run_probe.ts \
  --model google/gemma-4-31b-it:free
deno run --allow-net --allow-env --allow-read evals/run_probe.ts \
  --model openai/gpt-oss-20b:free
```

Options: `--model <id>` (required), `--filter <substring>` (matches a check's
key: `instructions`, `tool-definitions`, `sequential-tools`, `synthesis`,
`structured-arguments`, `arabic`, `multi-turn-context`), `--debug`,
`--temperature <n>` (default 0), `--seed <n>` (default `20260819`),
`--reasoning-effort <low|medium|high>` (only sent if given).

### `run_evals.ts` — the acceptance eval suite

Scenario-driven, scored, runnable against ANY model id so both candidates get
the IDENTICAL suite:

```bash
deno run --allow-net --allow-env --allow-read --allow-write=/tmp evals/run_evals.ts \
  --model google/gemma-4-31b-it:free --json /tmp/gemma-4-31b-results.json
deno run --allow-net --allow-env --allow-read --allow-write=/tmp evals/run_evals.ts \
  --model openai/gpt-oss-20b:free --json /tmp/gpt-oss-20b-results.json
```

Options: `--model <id>` (required), `--filter <substring>` (matches a scenario's
id, title, or dimension key), `--debug`, `--json <path>` (also writes
machine-readable results — the API key is never written to it; needs an
`--allow-write` grant covering the path you pass), `--temperature <n>` (default
0), `--seed <n>` (default `20260819`), `--reasoning-effort
<low|medium|high>`
(only sent if given — `gpt-oss-20b:free` supports it, `gemma-4-31b-it:free` does
not accept it, so leave it unset for that model). `--allow-write` is only needed
when `--json` is passed; omit both together.

## The nine dimensions

Scenarios live in `scenarios.ts`, tagged with a `dimension`. Each dimension has
at least two scenarios/cases with explicit, machine-checkable assertions
(`maxWords`, `mustMatchAny`/`mustNotMatch`, `toolCalled`/`toolCalledAny`/
`toolNotCalled`, `toolCalledWithArgs`, `argumentsValidForTool`,
`repliedInArabic`; see the top of `scenarios.ts` for the full list):

| Dimension                   | What it checks                                                                                                                                                                                                                                                                                                                                                                                       |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tool_selection`            | The right tool is called, not a plausible neighbour (e.g. a flock-count question calls `resolve_customer_flock`/`list_customer_flocks`, not a benchmark tool; a breed-standard question calls `get_breed_benchmark`, not the age-only breakout table).                                                                                                                                               |
| `report_vs_benchmark`       | A recorded-report request never resolves to a benchmark tool, and a published-standard question never routes through the audit-discovery tools. **See the important caveat below.**                                                                                                                                                                                                                  |
| `context_retention`         | A fact established in one turn (a resolved customer, or a breed+age pair) is reused correctly several turns later, across an unrelated intervening turn, without re-asking.                                                                                                                                                                                                                          |
| `multi_step_tool_use`       | A task needing tool A then tool B, where B's arguments must use a value A's result returned (e.g. the `customerId` `resolve_customer_flock` returned is what gets passed to `list_customer_flocks`).                                                                                                                                                                                                 |
| `no_repeated_clarification` | Every fact the tool call needs was already given in the user's message; the model calls the tool directly instead of asking for something it was already told.                                                                                                                                                                                                                                       |
| `arabic_understanding`      | An Arabic prompt gets both the correct tool call (when one is needed) and an Arabic reply.                                                                                                                                                                                                                                                                                                           |
| `concise_synthesis`         | A direct factual question gets an answer under an explicit word-count ceiling, not a written report.                                                                                                                                                                                                                                                                                                 |
| `missing_data_honesty`      | When a tool stub returns "not found" / "out of range", the model says so — and, checked mechanically with a regex over the reply, never states an invented number in its place.                                                                                                                                                                                                                      |
| `tool_argument_correctness` | Tool arguments are correct in more than just JSON-schema terms — e.g. an Arabic-script breed name (`روس`) is transliterated to the Latin `Ross 308` before the tool call, per the `BENCHMARK_DISCIPLINE` policy section, and `ageWeek` is passed as an actual integer. Checked with `validateToolArguments` against the real `AGENT_TOOL_CONTRACT` schema, plus a targeted argument-shape assertion. |

### Important caveat on `report_vs_benchmark`

Read `docs/LIVING_SPEC.md`'s "Report vs benchmark routing" section and
`agent_prompt.ts`'s `REPORT_VS_BENCHMARK` constant before changing these
scenarios. That section — and the explicit routing rules it describes — is
**voice-only**: it exists on `CHICKMARK_REALTIME_POLICY` and is explicitly
documented as NOT present on `CHICKMARK_AGENT_POLICY`, the typed policy
`buildAgentInstructions` actually builds and that this harness therefore sends.
The typed policy only carries the general `EVIDENCE_AND_SCOPE` audit-history
rule ("For an audit-history request, call `list_customer_audits`...") and
`BENCHMARK_DISCIPLINE`'s "never state a benchmark from memory" — no explicit
statement that a report request must never fall back to a benchmark tool.

So `report_vs_benchmark`'s scenarios here are not verifying compliance with an
explicit rule the way the voice canaries do; they are testing whether the
GENERAL rules already in the typed policy are enough to keep a smaller model
from making the exact mistake production hit once on voice (answering a "what
did we record" question from a published standard instead). A model that fails
this dimension is not violating a documented rule for its channel — it is
exposing a real gap between what the typed policy states and what a text-agent
conversation actually needs, which is itself useful information for the
acceptance decision.

## Key handling

`OPENROUTER_API_KEY` is read from the environment first (`env.ts`). If unset, it
falls back to parsing the repo's gitignored `.env` at the repo root (`KEY=VALUE`
per line) — pass `--allow-read` so that fallback can run. The key is never
logged, never written into the `--json` output file, and never appears in any
assertion detail (every diagnostic string in this harness is built from the
response, never the request). If neither source has it, both entry points print
a clear error and exit 1.

## Determinism / cost

`temperature: 0` and a fixed `seed` (`20260819` by default, override with
`--seed`) are sent on every request. Both candidate models are documented to
support `seed` and `temperature`; `openai/gpt-oss-20b:free` additionally
supports `reasoning_effort`, sendable via `--reasoning-effort` (omit it for
`gemma-4-31b-it:free`, which does not accept it).

`run_evals.ts` runs 18 scenarios (exactly 2 per dimension, 9 dimensions), each
its own session (a scenario with several turns keeps them in one session so
context persists, per the `context_retention` dimension); `run_probe.ts` runs 7
checks, each its own session or short session sequence. Both are sized to finish
in a few minutes per model. A scenario/check that hits a transient transport
error (network failure, or an HTTP status this harness treats as transient —
`429` or `5xx`) is retried EXACTLY ONCE; the retry is marked `(retried)` in the
report so a flaky pass is never silently indistinguishable from a clean one. A
`404`, or a `400` that looks like it is rejecting the request shape itself, is
treated as the `architecture` finding described above and is never retried.

## Reading the scorecard

`run_evals.ts` prints, in order:

1. **RESULTS BY SCENARIO** — every assertion, PASS/FAIL, one line each.
2. **DETAIL** — the actual reply text for every turn, with failing assertions'
   detail strings underneath (matching the pip-realtime-sideband convention:
   read the actual reply before concluding anything from the label alone).
3. **SCORECARD BY DIMENSION** — `passed/total` for each of the nine dimensions,
   so two models' `--json` outputs can be diffed dimension by dimension.
4. **FINAL** — total assertions passed out of the total scored (the bookkeeping
   `modelReplied` rows are excluded from this count — they exist to catch an
   empty/invalid reply before it silently satisfies a `mustNotMatch`, not to
   score a dimension).

A failing assertion is signal about the CANDIDATE MODEL under test, not a bug in
the harness, with three exceptions: a `transport` row, a `modelReplied` failure
(an empty or invalid reply came back even after the retry), and an
`ARCHITECTURE FINDING` block. All three are infrastructure/compatibility noise,
not scenario signal — re-run (ideally with `--filter`) rather than reading a
score into them.

`run_probe.ts` is simpler: each of the seven checks prints PASS/FAIL plus one
`evidence:` line showing exactly what was observed (the reply text, the tool
calls made, or both), so a failure is diagnosable directly from the terminal
output without re-running anything.

## Comparison suite — `models.ts` + `comparison_scenarios.ts` + `run_comparison.ts`

A SEPARATE, on-demand suite from everything above. `run_probe.ts`/`run_evals.ts`
answer "is this one model fit to be the default at all"; `run_comparison.ts`
answers "of several PAID OpenRouter candidates that all advertise tool support,
which is the cheapest one that still meets our reliability bar" — by running the
identical scenario set against every candidate and diffing the result. It reuses
`agent_client.ts`'s real transport/tool loop and `scenarios.ts`'s assertion
primitives rather than reimplementing either.

**`models.ts`** hand-pins a pricing snapshot (USD per 1,000,000 tokens, dated)
for five candidates — `openai/gpt-oss-20b`, `openai/gpt-oss-120b`,
`qwen/qwen3-30b-a3b-instruct-2507`, `deepseek/deepseek-v4-flash-0731`, and
`google/gemma-4-31b-it` (the current production default, included as the
baseline). `run_comparison.ts` re-verifies this table against OpenRouter's live
`/v1/models` at startup and **aborts before spending anything** if an id has
vanished, no longer advertises `tools`, or its price has drifted beyond 1%
tolerance.

**`comparison_scenarios.ts`** has 45 scenarios across 9 dimensions: Arabic /
mixed-language understanding (intent over keyword matching), tool selection,
tool arguments, tool-result reasoning, progressive disclosure, brevity,
hallucination/grounding, multi-turn (3-6 turn) conversations, and degradation
under load (long history, large tool-result payloads, confusable tool pairs
several turns deep). Every stub result shape was taken from
`agent_read_tools.ts`, `bmk_tools.ts`, and `agent_audit_tools.ts` after reading
them — the one exception is `propose_intake`/`list_applicable_stations` in the
data-entry multi-turn scenario, whose stub OUTPUT is a plausible approximation
(`agent_intake_tools.ts` wasn't read for this suite); that scenario's assertions
are limited to tool-call routing and `argumentsValidForTool` (checked against
the real, exact `AGENT_TOOL_CONTRACT` regardless of stub content) for exactly
that reason.

Run it:

```bash
deno run --allow-net --allow-env --allow-read --allow-write=/tmp \
  evals/run_comparison.ts --models openai/gpt-oss-20b,qwen/qwen3-30b-a3b-instruct-2507 \
  --repeats 3 --max-cost 2.00 --json /tmp/comparison.json
```

Options: `--models a,b,c` (default: all five candidates in `models.ts`),
`--repeats N` (default 3 — temperature 0 does not guarantee identical tool
choices across runs in practice, so a single sample can't tell a genuine defect
from noise; each scenario's per-repeat pass RATE is what gets scored),
`--filter <substring>` (matches a scenario's id, title, or dimension key),
`--json <path>` (full per-run machine-readable detail, API key never written),
`--max-cost <usd>` (default 2.00 — cumulative REAL reported `usage.cost` from
OpenRouter is checked before every scenario-repeat; once it would be exceeded,
the run stops cleanly and prints whatever partial report it has).

A scenario-repeat that hits a 429/5xx/network error is retried with exponential
backoff (capped); one that still can't complete is marked `INCONCLUSIVE` and
**excluded from every pass-rate metric**, reported separately under
"INCONCLUSIVE DETAIL" so it is never misread as a model defect. A 404, or a 400
that looks like it's rejecting the request shape itself, is an
`ARCHITECTURE FINDING` (never retried).

**Fairness**: every model gets identical temperature (0), seed (20260819),
`max_output_tokens` (2400, matching production), tool catalogue, and
instructions. `reasoning_effort` is **never** set for any model, even one whose
live catalogue entry advertises support for it — the run prints which candidates
could have taken that knob so the asymmetry is stated explicitly rather than
silently true of some models and not others.

**Output**: a compact comparison table (weighted score, hard gate verdict, pass
rate, latency percentiles, cost per 1000 turns), a per-dimension breakdown with
flap detection (a scenario that sometimes passes and sometimes fails across
repeats, as opposed to one that fails every time), up to three representative
failure examples per model (actual prompt, actual tool calls, actual reply — not
just aggregate numbers), and the derivation of the cost-per-1000-turns
projection (the measured calls-per-turn ratio for that run, stated explicitly).
The weighted score is 30% tool selection+arguments, 20% grounding, 20%
Arabic/mixed, 15% scope/progressive-disclosure/brevity, 10% latency, 5% cost —
but a hard gate (any failing assertion in tool_selection, tool_arguments,
hallucination_grounding, multi_turn, or degradation_under_load) disqualifies a
model regardless of that score; both are always printed, never just the score.

Like the acceptance harness above, this costs real money and is deliberately not
part of `deno test`.
