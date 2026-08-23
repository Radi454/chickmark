# Pip Realtime Hardening — 2026-08-19

Fixes four production issues found in the diagnosed Realtime session.
**Out of scope: `propose_intake` / Voice Data Entry — untouched.**

## Verified ground facts

- `interaction_id` was ABSENT from production `agent_realtime_response_usage`;
  migration `20260819120000` was never applied before Cloud Run revision
  `00015-b48` shipped. Every usage insert 400'd and was swallowed by
  `#persistResponseUsage`. Table had 0 rows.
- `get_breed_benchmark` already implements the proven `requested` /
  `unavailable` / `unknownMetrics` / `context` shaping;
  `get_egg_breakout_benchmark` returned a flat 11-field row.
- Live probe `tools/probe_session_knobs.ts` (recorded run 2026-08-19):
  singular `language` IS accepted for `gpt-4o-mini-transcribe` (echoed back);
  plural `languages` remains REJECTED; `max_output_tokens` accepted, and the
  session default echoes `"inf"` — production has never had an output ceiling.
- Live probe `tools/probe_output_tokens.ts` (recorded run 2026-08-19), output
  tokens per answer size: greeting 66, single metric 60, two metrics 145,
  six-metric breed summary 488, 11-metric dump 761. Later canary measurement
  put the longest LEGITIMATE reply (an explicitly requested full 11-metric
  breakout summary) at 832-865.
- Live probe `tools/probe_transcription_quality.ts` (recorded run 2026-08-19):
  `language:'ar'` left a pure-English utterance transcribed IDENTICALLY to the
  no-hint variants, and the bilingual prompt stopped `hatchability` being
  transliterated into Arabic script.

## Phase 1 — Telemetry (Issue 4) — DONE

1. Migration reviewed: additive `add column if not exists`, nullable by
   design, composite index, idempotent. Safe.
2. Applied to production. Verified `information_schema` shows the column, and
   PostgREST parses it (`?select=interaction_id` → 401 permission-denied,
   while a bogus column → `42703`).
3. Exact 22-column insert shape proven against the deployed schema by a
   `DO` block that raised to roll itself back — table left at 0 rows.
4. `test/response_usage_schema_contract_test.ts` derives the expected column
   set by PARSING the migration SQL off disk, so it cannot rot the way the
   deployed schema did, plus a non-vacuity guard (≥20 columns, known anchors).
5. Fail-loud-but-non-fatal: first failure per session logs a distinct `error`
   event, later ones stay quiet, and a terminal all-failed event fires when
   every attempt failed. The try/catch still swallows unconditionally — a
   telemetry failure can never break a live call.

## Phase 2 — Breakout answer shaping (Issue 2) — DONE

Mirrors `get_breed_benchmark` branch-for-branch. Metric keys:
`infertile`, `early_24h`, `early_48h`, `blood_ring`, `black_eye`,
`early_dead`, `mid_dead`, `late_dead`, `external_pip`, `cracked`,
`contaminated` (the last maps to `contamPct`, the same deliberate mismatch
already documented for `BREAKOUT_METRIC_SOURCES`).

`parseRequestedMetrics` / `nullMetricKeys` were generalized over a catalogue
rather than copy-pasted, so the two tools cannot drift. An unknown metric
token yields `requested: []` + `unknownMetrics` and NEVER degrades to the flat
row. Full row always preserved in `context`. `week_out_of_range` unchanged.

`AGENT_TOOL_CONTRACT_VERSION` `1.1.0` → `1.2.0`; fingerprint re-pinned.

## Phase 3 — Report vs benchmark routing (Issue 1)

New voice-only `REPORT_VS_BENCHMARK` section in `CHICKMARK_REALTIME_POLICY`.
It must NOT go into `BENCHMARK_DISCIPLINE` — that section is shared with the
typed policy, which is byte-frozen by a pinned snapshot.

Rules: separate "what the standard says" from "what was actually recorded";
make that decision SILENTLY (never ask the user which they meant); default
ambiguous wording to the standard, but note that a missing customer name is
NOT what makes a question a standard question — a report request with no
customer named is still a report request; never answer a report request with a
benchmark tool; when a report request has no resolved customer, ask exactly
ONE short clarification and call no benchmark tool; never carry
`ageWeek`/`breed` from a previous benchmark turn into a report request; the
egg-breakout standard is age-only so never ask for a breed before calling it;
and every question that is neither a standard nor an audit report keeps its
existing tool.

The section was revised three times against live canaries, which caught it
(a) demanding a breed for the breed-less table, (b) asking "لأي عميل؟" for
plain standard questions, (c) asking the user out loud whether they meant a
standard or a report, and (d) classifying the incident query itself as a
standard question because it named no customer.

`CHICKMARK_REALTIME_POLICY_VERSION` `2.2.0` → `2.3.0`.

Known limitation: the typed/Telegram channel keeps the old routing because its
policy is deliberately byte-frozen. Documented, not fixed here.

## Phase 4 — Output length guard (Issue 3)

`PIP_REALTIME_MAX_OUTPUT_TOKENS`, default **1536**, applied as session
`max_output_tokens`.

The value is measured, not guessed, and it was REVISED once during the work.
The first estimate (1024) came from a six-metric breed summary costing 488
output tokens. Live canary measurement then showed the actual longest
legitimate reply — an explicitly requested full ELEVEN-metric breakout summary
— costs 832 and 865 output tokens on the real audio path. 1024 would have left
only ~18% headroom over an answer already observed at 865, so the default is
1536: roughly 1.8x the largest measured legitimate reply. `max_output_tokens`
truncation is not graceful — the response stops and returns `incomplete` — so
a ceiling that can clip a real answer is worse than none.

The ceiling is deliberately NOT sized to cut the 761-token incident dump. That
dump is cured at source by Phase 2 shaping and Phase 3 routing, both pinned by
canaries. `length-guard-long-followup` exercises the largest shape that exists
(the 17-row audit-vs-benchmark comparison) and asserts both the ceiling and
`status === 'completed'`, so truncation is tested rather than assumed.

VAD eagerness is NOT touched — the evidence never implicated it.

## Phase 5 — Transcription (Issue 5)

Root cause of the `"Hello, world."` / `"I'm Elly."` / `"In Tamil"` captions:
the transcription prompt was 100% English hatchery vocabulary — a strong
English decoding bias over Egyptian Arabic audio — with no language hint at
all. Bad captions then persist as inbound turns and pollute conversation
history that gets re-injected as context.

Fix: bilingual Arabic+English `TRANSCRIPTION_PROMPT`, plus
`PIP_REALTIME_TRANSCRIPTION_LANGUAGE` (default `ar`, empty string = omit the
field as a no-code-deploy rollback). The `gpt-live-transcribe` branch keeps
`languages` + `delay` and never receives singular `language` (unprobed there).

Cannot be verified without a real-device call: transcription ACCURACY on live
Egyptian Arabic speech. The probe proves protocol acceptance, not quality.

## Phase 6 — Canaries

`breakout-report-not-benchmark` (no customer → benchmark tools NOT called,
≤1 question), `breakout-single-metric-scope`, `breakout-two-metric-scope`,
`breakout-full-summary-allowed`, `breakout-null-metric`,
`breakout-unknown-metric` (no flat dump), `length-guard-long-followup`.

Two more were added after the Opus review. `breakout-report-not-benchmark`
uses the incident sentence verbatim, and that sentence is also a calibration
example in the policy — so it cannot tell "applied the rule" apart from
"parroted the example". `report-unparroted-phrasing` asks for a recorded
result in wording that appears nowhere in the policy, and
`station-record-not-audit` proves an ordinary station-record question still
reaches `query_station_records` instead of the audit chain.

## Phase 7 — Deploy order (non-negotiable)

1. Migration (done — it alone restores telemetry under the current revision).
2. Edge functions FIRST: `telegram-hatchery-agent`, `pip-realtime-tool-broker`,
   `app-hatchery-agent`. The broker validates arguments with
   `additionalProperties:false`, so the new `metrics` argument must be accepted
   server-side BEFORE the model is ever offered it.
3. THEN the Cloud Run sideband with re-rendered `PIP_REALTIME_TOOL_DEFINITIONS`
   and `PIP_REALTIME_INSTRUCTIONS`, plus the two new env vars.

Cloud-Run-first would expose the new argument to the model while the old
broker still rejected it — every such call would fail until the edge functions
caught up.

## Risks

- Live-model behavior is probabilistic; the routing canaries may need one
  wording iteration.
- `language:'ar'` is proven accepted AND proven not to harm a pure-English
  utterance on clean audio. What is NOT demonstrated is that it cures the
  "Hello, world." hallucinations — clean synthesized speech never reproduces
  them. It is a reasoned mitigation with a measured absence of downside; the
  empty-string env value is the rollback.
- Pinned values move in several places at once (contract version + fingerprint
  + snapshot, policy version, config defaults, session.update shape) — each
  must move with its source change.
